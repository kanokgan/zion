# ubuntu-extreme (the Lenovo: host `ubuntu-extreme`, cluster `extreme`)

Ubuntu Server 24.04 on a Lenovo X1 Extreme Gen 2 with an NVIDIA GeForce GTX 1650 (4 GB). Until 2026-10-17 the host was named `k3s-master` and ran the legacy cluster `zion-old`. The OS was kept; k3s and everything on top of it was removed and recreated from this repo as the cluster `extreme` (ADR 0009). Host-level setup lives here, outside Flux (ADR 0006).

Sections: access, what lives on the host, the NVIDIA stack, the network incident, what was found on 2026-10-17 (history), the rebuild runbook (followed, kept for the next rebuild), the storage plan and the open items.

## Access

- Tailscale runs on the host (not in the cluster), so SSH over the tailnet survives removing k3s. Prefs: no exit node, no advertised routes, no Tailscale SSH.
- No out-of-band access (no IPMI, no wake-on-LAN, no remote power control). A machine that fails to boot needs someone at the keyboard. It is on a UPS.
- Disk: LVM with ext4 on the NVMe, not encrypted, so a reboot does not wait for a passphrase.
- `ssh.service` reports `disabled` because sshd is socket-activated on 24.04; confirm `ssh.socket` is `enabled` before any reboot.

## What lives on the host

| Path or unit | What | Where it is described |
|---|---|---|
| `/srv/immich` | Immich library (static PV), root-owned | [immich.md](../../docs/services/immich.md) |
| `/srv/silverbullet` | SilverBullet notes (static PV) | [silverbullet.md](../../docs/services/silverbullet.md) |
| `/srv/obsidian` (`config/`, `vault/`) | Obsidian settings and the synced vault | [obsidian.md](../../docs/services/obsidian.md) |
| `/srv/syncthing/config` | Syncthing identity and config | [syncthing.md](../../docs/services/syncthing.md) |
| `/mnt/*` and `/srv/external/*` | CIFS mounts of NAS shares (`/etc/fstab`, credentials outside Git, pattern in `fstab.example`) | [immich.md](../../docs/services/immich.md), "External libraries" |
| `cloudflared.service` | tunnel `ubuntu-extreme` | [cloudflared/](cloudflared/README.md) |
| `immich-nas-sync.timer` (04:00), `silverbullet-nas-sync.timer` (04:30) | nightly copies to the NAS | [backup/](backup/README.md) |
| `k3s-install.sh`, `apt/51-zion-nvidia-blacklist` | k3s install, NVIDIA packages held back from unattended upgrades | below |

All `/srv/*` directories sit on the one root volume (see the storage plan).

## NVIDIA GPU stack

| Piece | State |
|---|---|
| Driver | `nvidia-driver-580-server`, DKMS, built for both installed kernels. 580.178.04 since 2026-10-17 |
| GPU | GeForce GTX 1650 with 4 GB of VRAM: with time-slicing (4 replicas) the pods share that memory, so ML and transcoding together can run out of VRAM |
| Container toolkit | `libnvidia-container1` and tools 1.18.1; static CDI spec at `/etc/cdi/nvidia.yaml` (dated 2026-08-03, older than the driver upgrade) |
| Kubernetes | `nvidia` RuntimeClass (k3s creates it when it finds `nvidia-container-runtime`), the device plugin, time-slicing 4 |
| Consumers | `immich-server` (transcoding) and `immich-machine-learning` (CUDA) each request `nvidia.com/gpu: 1` |

### Rules for the rebuilt host

- Keep NVIDIA packages out of unattended upgrades (`apt/51-zion-nvidia-blacklist`); upgrade them on purpose, then reboot, then check `nvidia-smi` and a GPU pod.
- `FAIL_ON_INIT_ERROR=true` on the device plugin, and an alert when the GPU is not advertised (`GpuNotAdvertised` in the monitoring rules).
- Pin every image to an exact version. The Lenovo's floating `v3` Immich tag pulled v3.3.3 on a restart on 2026-10-17.

### Incident: "Driver/library version mismatch" (found 2026-10-17)

An unattended apt upgrade moved the NVIDIA user-space packages from 580.173.02 to 580.178.04 while the older kernel module stayed loaded (the host had not rebooted). `nvidia-smi` failed with `Failed to initialize NVML: Driver/library version mismatch`. New GPU pods could not start: `failed to inject CDI devices: unresolvable CDI devices runtime.nvidia.com/gpu=all`. Running pods kept working because they had loaded the old libraries before the upgrade; the first restart would have failed too. It went unnoticed for weeks because the device plugin ran with `FAIL_ON_INIT_ERROR=false` (so it kept the old GPU count) and nothing alerted on a pod failing to get a GPU.

Fix (done 2026-10-17): reboot so the new module loads (kernel 6.8.0-147, driver 580.178.04, `nvidia-smi` works). A GPU pod then started without regenerating the CDI spec, so the reboot alone was enough. If a GPU pod still fails with the CDI error after a driver upgrade, regenerate it with `nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml` (as root).

## Network incident: the wired link at 100 Mb/s (fixed 2026-10-18)

On 2026-10-17 `enp0s31f6` (Intel, gigabit-capable) negotiated 100 Mb/s full duplex because the link partner (the home router, a TP-Link, where the NAS is also plugged in) only advertised up to 100baseT. Real throughput was about 11 MB/s, so the 1.3 TB library copy would take about 33 hours. The link also dropped for about 4 minutes (kernel log: link down 21:47, up 21:51), which cut the copy. Reseating the cable brought it to 1000 Mb/s Full (link up at 22:14, `ethtool` confirms). The Wi-Fi interface `wlp82s0` is a metric-200 backup on the same subnet; it does not rescue live connections, because they are bound to the wired address.

Watch for a relapse: the `HostNetworkLinkSlow` alert fires below 1 Gb/s, and `journalctl -k --since today | grep -i "NIC Link"` shows drops. If it drops back to 100 or flaps, the likely cause is the cable or the router port (a cable with two working pairs makes the partner stop offering 1000). Test order, cheapest first, checking `cat /sys/class/net/enp0s31f6/speed` for 1000 after each step:
1. A different known-good cable, plugged into a free router port (do not unplug the NAS: it is the backup target).
2. The same cable in another port.
3. Inspect or replace the Lenovo-side Ethernet extension adapter, for example with a USB-C gigabit adapter while the cluster is idle (a new interface changes the address k3s is bound to).

Cable to buy: Cat5e or Cat6, 100% copper (not CCA), round, UTP, 1 to 3 m. Bulk copies to this machine are throttled (`rsync --bwlimit`, about 50m on gigabit) so SSH and Tailscale keep headroom.

## State found on 2026-10-17 (history)

| Area | As found | Rebuild |
|---|---|---|
| k3s | Started with `server --write-kubeconfig-mode 644` only, no config file: Traefik and ServiceLB on (default), node `k3s-master`, kubeconfig readable by every user | Pinned `v1.33.6+k3s1` (same as the mini), `--disable traefik --disable servicelb --node-name extreme`, kubeconfig stays root-only (`k3s-install.sh`) |
| containerd | Custom `config.toml.tmpl` that makes `nvidia` the default runtime for every pod (`default_runtime_name = "nvidia"`) | Not needed: pods ask for `runtimeClassName: nvidia`, including the device plugin (`infrastructure/base/nvidia-device-plugin`). Fallback if that ever fails on a fresh boot: the template is `{{ template "base" . }}` plus the `default_runtime_name = "nvidia"` setting under `[plugins.'io.containerd.cri.v1.runtime'.containerd]` |
| GPU device plugin | `nvidia-device-plugin-daemonset`, image v0.14.5, privileged, `FAIL_ON_INIT_ERROR=false`, config `nvidia-device-plugin-config`: time-slicing, `nvidia.com/gpu` replicas 4, `migStrategy: none` | In the repo, same version and config, but `FAIL_ON_INIT_ERROR=true` so a broken driver crashes the pod instead of hiding |
| Firewall (ufw) | Active: 22/tcp from anywhere, tailscale0 all, 80 and 443 from the LAN, 10250/tcp (kubelet) from anywhere | Unchanged by the wipe (the OS stays). Still to do, see open items |
| Cron | Root crontab: `0 3 * * *  /root/scripts/k3s-disaster-backup.sh`. The script was half-written and did nothing | Dropped; the cron entry was removed after the wipe |
| Mounts | `/etc/fstab`: 15 writable CIFS mounts of NAS shares under `/mnt` (personal drives, camera folders, `temp`, `HomeBrain`, `ZionLabs` over the tailnet), credentials in root-only files outside Git, all `_netdev`, none `nofail` | Stay as they are (the OS is kept). Add `nofail,x-systemd.mount-timeout=30`. No LAN addresses or real names in Git |
| Tailscale devices | Old sidecars from the cluster are still registered (`actual`, `immich`, `monitoring`, `humulos-scrape`, `filebrowser`, plus the mini's `*-standby`) | Delete the stale ones in the admin console (still open) |

## Rebuild runbook (followed 2026-10-17 to 21; kept for the next rebuild)

Each step is run by the owner. Gates that were checked on 2026-10-17: NAS snapshots on `ZionLabs` (hourly); the NAS holds the library as of the first cutover and the mini's NVMe holds everything newer; the old library, databases, `monitoring` and `web-scraper` data are accepted as lost; Plex and Jellyfin stay on the mini. A recent NAS copy of the library must exist before wiping.

1. Clone this repo on the Lenovo (it is public, read-only use) for the scripts below.
2. Stop k3s and unmount the writable CIFS mounts (`k3s-killall.sh`, `umount -a -t cifs`; `mount | grep -E "kubelet|k3s|cifs"` must be empty), then `k3s-uninstall.sh`, then remove any root cron entry. A directory removal through a live mount would delete NAS files. This is the point of no return for the old cluster's data.
3. Rename the host (after k3s is gone): `hostnamectl set-hostname ubuntu-extreme`, fix the `127.0.1.1` line in `/etc/hosts`, `tailscale set --hostname=ubuntu-extreme`. Remount with `mount -a`.
4. `mkdir /srv/immich` for the library (outside k3s's state, so a k3s reinstall never touches it).
5. Install the NVIDIA exclusion file and k3s with `k3s-install.sh`; copy the kubeconfig to `~/.kube/config` (mode 600) and name the context `extreme`.
6. Copy the library from the NAS into `/srv/immich` while the other machine keeps serving (hours; the delta is copied again at the cutover).
7. Create the `sops-age` secret and bootstrap Flux on `clusters/extreme`.
8. Install `cloudflared` on the host ([cloudflared/README.md](cloudflared/README.md)) with a tunnel named `ubuntu-extreme` (token file outside Git); the routes to the NodePorts are added per service at its cutover.
9. Cutover per service: see [immich.md](../../docs/services/immich.md) and [actual.md](../../docs/services/actual.md).
10. Delete the old tunnel and check no DNS record still points at it; delete stale Tailscale devices.

## Storage plan (decided 2026-10-21)

The root filesystem is one LVM logical volume on a single 2 TB NVMe (`/dev/mapper/ubuntu--vg-ubuntu--lv`). `/srv/immich` is on it: about 1.5 TB used of 1.9 TB (82%) on 2026-10-21, mostly `library` (1.1 TB of originals), plus `encoded-video` (191 GB), `backups` (69 GB, DB dumps) and `thumbs` (52 GB).
- **Headroom:** about six months at the current growth, after the cleanups listed in the tracker (dashcam transcodes, untracked files, lower DB dump retention). Revisit around April 2027, or earlier when the disk reaches about 90% (the monitoring alerts fire at 80% and 90%, ADR 0010). The notes apps (SilverBullet, Obsidian, Syncthing) are on the same volume; about 400 GB were free after Immich on 2026-10-25.
- **Plan: add a second 2 TB NVMe and extend the volume** (add it to the volume group, grow the logical volume and the filesystem online; no reinstall, no change to `/srv/immich` or the manifests). The machine has two M.2 slots; installing the disk needs someone at the machine and a shutdown, so everything is down while it is open.
- **Accepted risk:** the filesystem then spans two disks, so losing either NVMe loses the whole filesystem (OS, k3s state, Postgres, library). The mitigation is the nightly copy of `/srv/immich` to the NAS (`backup/`) and rebuilding from this repo. The alternative that keeps the failure domains separate (the new disk mounted only at `/srv/immich/library`, a one-time copy of about 1.1 TB) was considered and not chosen.
- **Considered and deferred:** moving the originals (`library`, `upload`) to the NAS and keeping only thumbnails and transcodes on the NVMe. It makes the NAS the only good copy of the photos, so it needs a second copy of the originals elsewhere and an ADR on the NAS storage pattern first.
- Before opening the machine: check the last nightly sync was clean (`journalctl -u immich-nas-sync`), paste `lsblk -f` before formatting anything, and extend with `pvcreate`, `vgextend`, `lvextend -r` after checking the device name.

## Open items

- ufw: replace "10250 from anywhere" with allows from the k3s pod and service ranges (`10.42.0.0/16`, `10.43.0.0/16`), drop 80/443, then check node metrics and pod logs still work. Leave SSH alone while there is no physical access.
- Delete the stale Tailscale device entries.
- The storage plan above (second NVMe) when the disk nears 90%.
- Add `nofail,x-systemd.mount-timeout=30` to the CIFS mounts in `/etc/fstab` if not done yet (see `fstab.example`).
