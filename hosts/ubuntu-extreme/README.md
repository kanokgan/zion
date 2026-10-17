# ubuntu-extreme (the Lenovo: host `ubuntu-extreme`, cluster `extreme`)

Ubuntu Server 24.04 on a Lenovo X1 Extreme Gen 2 with an NVIDIA GeForce GTX 1650 (4 GB). Until 2026-10-17 the host was named `k3s-master` and ran the legacy cluster `zion-old`. The OS was kept; k3s and everything on top of it was removed and recreated from this repo as the cluster `extreme` (ADR 0009). Host-level setup lives here, outside Flux (ADR 0006).

This file records what was found on 2026-10-17 (the "State found" table and the incident notes are history), then the rebuild runbook, which was followed that day.

## Access

- Tailscale runs on the host (not in the cluster), so SSH over the tailnet survives removing k3s. Prefs: no exit node, no advertised routes, no Tailscale SSH.
- No out-of-band access (no IPMI, no wake-on-LAN, no remote power control). A machine that fails to boot needs someone at the keyboard. It is on a UPS.
- Disk: LVM with ext4 on the NVMe, not encrypted, so a reboot does not wait for a passphrase.
- `ssh.service` reports `disabled` because sshd is socket-activated on 24.04; confirm `ssh.socket` is `enabled` before any reboot.
- **Known issue, found 2026-10-17: the wired link runs at 100 Mb/s, not gigabit.** `enp0s31f6` (Intel, gigabit-capable) advertises 1000baseT but the link partner (the home router, a TP-Link, where the NAS is also plugged in) only advertises up to 100baseT, so the port negotiates 100 Mb/s full duplex (`ethtool enp0s31f6`). Real throughput is about 11 MB/s: the 1.3 TB library copy takes about 33 hours, and LAN clients reach Immich at 100 Mb/s at most. Likely the Lenovo's cable or the router port it uses (a cable with two working pairs makes the partner stop offering 1000). Not fixed: needs someone at the machine. Test order, cheapest first, checking `cat /sys/class/net/enp0s31f6/speed` for 1000 after each step: (1) a different known-good cable, plugged into a free router port (do not unplug the NAS: it serves the library copy and is the backup target); (2) the same cable in another port; (3) inspect or replace the Lenovo-side Ethernet extension adapter, for example by trying a USB-C gigabit adapter with the cluster idle (a new interface changes the address k3s is bound to). Cable to buy: Cat5e or Cat6, 100% copper (not CCA), round, UTP, 1 to 3 m. Until then, copies to it are throttled (`rsync --bwlimit`) so SSH and Tailscale keep headroom. If someone is at home at the cutover, copying from the mini's NVMe over USB is far faster than the network.

## State found on 2026-10-17

| Area | As found | Rebuild |
|---|---|---|
| k3s | Started with `server --write-kubeconfig-mode 644` only, no config file: Traefik and ServiceLB on (default), node `k3s-master`, kubeconfig readable by every user | Pinned `v1.33.6+k3s1` (same as the mini), `--disable traefik --disable servicelb --node-name extreme`, kubeconfig stays root-only (`hosts/ubuntu-extreme/k3s-install.sh`) |
| containerd | Custom `config.toml.tmpl` that makes `nvidia` the default runtime for every pod (`default_runtime_name = "nvidia"`) | Not needed: pods ask for `runtimeClassName: nvidia`, including the device plugin (`infrastructure/base/nvidia-device-plugin`). Fallback if that fails on the first boot: the template is `{{ template "base" . }}` plus the `default_runtime_name = "nvidia"` setting under `[plugins.'io.containerd.cri.v1.runtime'.containerd]` |
| GPU device plugin | `nvidia-device-plugin-daemonset`, image v0.14.5, privileged, `FAIL_ON_INIT_ERROR=false`, config `nvidia-device-plugin-config`: time-slicing, `nvidia.com/gpu` replicas 4, `migStrategy: none` | In the repo, same version and config, but `FAIL_ON_INIT_ERROR=true` so a broken driver crashes the pod instead of hiding |
| Firewall (ufw) | Active: 22/tcp from anywhere, tailscale0 all, 80 and 443 from the LAN, 10250/tcp (kubelet) from anywhere | Unchanged by the wipe (the OS stays). After the cluster is up: replace "10250 from anywhere" with allows from the k3s pod and service ranges (`10.42.0.0/16`, `10.43.0.0/16`), drop 80/443, then check node metrics and pod logs still work. Leave SSH alone while there is no physical access |
| Cron | Root crontab: `0 3 * * *  /root/scripts/k3s-disaster-backup.sh` (log `/var/log/k3s-disaster-backup.log`). **Contents not recorded yet** | Read it before the wipe: what it backs up and where. Remove the entry after the wipe |
| Mounts | `/etc/fstab`: 15 writable CIFS mounts of NAS shares under `/mnt` (personal drives, camera folders, `temp`, `HomeBrain`, `ZionLabs` over the tailnet), credentials in root-only files outside Git, all `_netdev`, none `nofail` | Stay as they are (the OS is kept). Add `nofail,x-systemd.mount-timeout=30`. No LAN addresses or real names in Git |
| Tailscale devices | Old sidecars from the cluster are still registered (`actual`, `immich`, `monitoring`, `humulos-scrape`, `filebrowser`, plus the mini's `*-standby`) | Delete the stale ones in the admin console before the rebuild, or the new sidecars get `-1` names |

## NVIDIA GPU stack

| Piece | State |
|---|---|
| Driver | `nvidia-driver-580-server`, DKMS, built for both installed kernels. 580.178.04 since 2026-10-17 |
| GPU | GeForce GTX 1650 with 4 GB of VRAM: with time-slicing (4 replicas) the pods share that memory, so ML and transcoding together can run out of VRAM |
| Container toolkit | `libnvidia-container1` and tools 1.18.1; static CDI spec at `/etc/cdi/nvidia.yaml` (dated 2026-08-03, older than the driver upgrade) |
| Kubernetes | `nvidia` RuntimeClass (k3s creates it when it finds `nvidia-container-runtime`), the device plugin, time-slicing 4 |
| Consumers | `immich-server` (transcoding) and `immich-machine-learning` (CUDA) each request `nvidia.com/gpu: 1` |

### Incident: "Driver/library version mismatch" (found 2026-10-17)

An unattended apt upgrade moved the NVIDIA user-space packages from 580.173.02 to 580.178.04 while the older kernel module stayed loaded (the host had not rebooted). `nvidia-smi` failed with `Failed to initialize NVML: Driver/library version mismatch`. New GPU pods could not start: `failed to inject CDI devices: unresolvable CDI devices runtime.nvidia.com/gpu=all`. Running pods kept working because they had loaded the old libraries before the upgrade; the first restart would have failed too. It went unnoticed for weeks because the device plugin ran with `FAIL_ON_INIT_ERROR=false` (so it kept the old GPU count) and nothing alerted on a pod failing to get a GPU.

Fix (done 2026-10-17): reboot so the new module loads (kernel 6.8.0-147, driver 580.178.04, `nvidia-smi` works). A GPU pod then started without regenerating the CDI spec, so the reboot alone was enough. If a GPU pod still fails with the CDI error after a driver upgrade, regenerate it with `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` (as root).

### Rules for the rebuilt host

- Keep NVIDIA packages out of unattended upgrades (`hosts/ubuntu-extreme/apt/51-zion-nvidia-blacklist`); upgrade them on purpose, then reboot, then check `nvidia-smi` and a GPU pod.
- `FAIL_ON_INIT_ERROR=true` on the device plugin, and (with monitoring) an alert when a GPU pod is not scheduled.
- Pin every image to an exact version. The Lenovo's floating `v3` Immich tag pulled v3.3.3 on a restart on 2026-10-17.

## Rebuild runbook (draft, in order; each step is run by the owner)

Gates (checked 2026-10-17): NAS snapshots on `ZionLabs` (hourly, done); the NAS holds the library as of the first cutover and the mini's NVMe holds everything newer; the old library, databases, `monitoring` and `web-scraper` data are accepted as lost; `k3s-disaster-backup.sh` was half-written and does nothing, so it is dropped; Plex and Jellyfin stay on the mini. The mini to NAS sync is not a gate for the wipe but must exist before the Immich cutover.

1. Push this repo's pending commits, then clone it on the Lenovo (it is public, read-only use) for the scripts below.
2. Stop k3s and unmount the writable CIFS mounts (`k3s-killall.sh`, `umount -a -t cifs`; `mount | grep -E "kubelet|k3s|cifs"` must be empty), then `k3s-uninstall.sh`, then remove the `k3s-disaster-backup.sh` cron entry. A directory removal through a live mount would delete NAS files. This is the point of no return for the old cluster's data.
3. Rename the host (after k3s is gone): `hostnamectl set-hostname ubuntu-extreme`, fix the `127.0.1.1` line in `/etc/hosts`, `tailscale set --hostname=ubuntu-extreme`. `ssh k3s-master` becomes `ssh ubuntu-extreme`. Remount with `mount -a`.
4. `mkdir /srv/immich` for the library (outside k3s's state, so a k3s reinstall never touches it).
5. Install the NVIDIA exclusion file and k3s with `k3s-install.sh`; copy the kubeconfig to `~/.kube/config` (mode 600) and name the context `extreme`.
6. Copy the library from the NAS into `/srv/immich` while the mini keeps serving (hours; the delta is copied again at the cutover).
7. Create the `sops-age` secret and bootstrap Flux on `clusters/extreme`.
8. Install `cloudflared` on the host (`cloudflared/README.md`) with a new tunnel named `ubuntu-extreme` (token file outside Git); the routes `http://localhost:30283` (Immich) and `http://localhost:30506` (Actual) are added at the cutover.
9. Cutover: the mini in maintenance mode, dump, sync mini to NAS, copy the delta NAS to Lenovo, restore on the Lenovo, move both hostnames to the new tunnel, then repeat for Actual (export and import).
10. Delete the `home-brain` tunnel and its leftover DNS records, and the stale Tailscale devices.

## Open items

- Contents of `/root/scripts/k3s-disaster-backup.sh` and where its output goes.
- ufw: tighten after the rebuild (see the table).
- Untested: `k3s-install.sh`, the apt exclusion file, `cloudflared/` (unit and README), `fstab.example`. All written, none run yet.
- `flux bootstrap` for `clusters/extreme/` (adds `flux-system/` beside the two Kustomizations already there).
- External libraries (the personal drives, `/V11Pro`, `/70Mai`) are not mounted in `apps/extreme/immich`: their paths contain real names, so they need Flux `postBuild.substituteFrom` from a SOPS secret, or they stay unavailable.
