# SilverBullet

Personal notes as markdown pages in a folder, edited in the browser. Production runs on the Lenovo (cluster `extreme`, host `ubuntu-extreme`) at `silverbullet.kanokgan.com`; the mini holds a warm standby reachable on the tailnet only. Notes also hold PDFs and spreadsheets, so storage growth matters (see "Storage").

## What runs where

| | Lenovo (`extreme`, primary) | Mac mini (`mini`, standby) |
|---|---|---|
| Image | `ghcr.io/silverbulletmd/silverbullet:2.12.1-slim` | same tag |
| Data | host directory `/srv/silverbullet` (static PV/PVC `silverbullet-data`, `Retain`), mounted at `/data` | 20Gi `local-path` PVC `silverbullet-data` on the Lima VM disk |
| Tailscale (debug, tailnet only) | sidecar `silverbullet-ubuntu-extreme`: `https://silverbullet-ubuntu-extreme.dove-komodo.ts.net` | sidecar `silverbullet-macos-mini`: `https://silverbullet-macos-mini.dove-komodo.ts.net` |
| Public | `silverbullet.kanokgan.com` via tunnel `ubuntu-extreme` (`cloudflared` on the host), service `http://localhost:30300` -> NodePort Service `silverbullet-nodeport` | none |
| Login | SilverBullet's own, `SB_USER` (`username:password`) from `silverbullet-auth.sops.yaml` | same mechanism, own secret |

Manifests: `apps/base/silverbullet/`, `apps/extreme/silverbullet/`, `apps/mini/silverbullet/`. The two instances do not share storage. The slim image variant leaves out Chromium (the Runtime API), which is not used.

Access decisions: no Cloudflare Access in front, only SilverBullet's own login (owner's decision, 2026-10-25); Cloudflare terminates TLS and can see the traffic, as for Actual and Immich. The work laptop reaches it through the public hostname (the company allows `*.kanokgan.com`). The password therefore protects notes on the open internet: use a long random one. SilverBullet locks an account after repeated failures (`SB_LOCKOUT_LIMIT`, default 10 tries, then 60 s).

Licensing (checked 2026-10-25): the server is MIT licensed and free. The SilverBullet+ desktop app is free for personal use, and its author asks for payment (about $50 a year per person) for work use; it is an honor system. Decision: the work laptop uses the browser only, no desktop app, so no license is needed and no copy of the notes is kept there.

## Server mode

SilverBullet 2.x defaults to a "multi-space" server mode configured in a Dashboard; `SB_USER` and `SB_FOLDER` are documented as the single-space (legacy) settings, and the docs do not say how the server picks the mode. The manifest uses the single-space settings. Confirmed on the first start (2026-10-25): the log says `boot mode: single-space (SB_USER is set)`, the process runs as UID 1000 (the owner of `/srv/silverbullet`), and the "runtime Chrome not found" lines are expected with the `-slim` image. Login and saving a page were checked on the tailnet name before the tunnel route was added. These are legacy settings upstream, so re-check this section when upgrading.

## Setup (run by the owner)

1. On the Lenovo, create the notes directory (the container follows the owner of `/data`):
   ```sh
   sudo install -d -o kanokgan -g kanokgan -m 0750 /srv/silverbullet
   ```
2. Create two encrypted secrets per cluster (placeholders, not real values). A Tailscale auth key is only needed when the sidecar first joins.
   ```yaml
   # apps/extreme/silverbullet/silverbullet-auth.sops.yaml   (same shape for apps/mini/silverbullet/)
   apiVersion: v1
   kind: Secret
   metadata:
     name: silverbullet-auth
     namespace: silverbullet
   stringData:
     SB_USER: <username>:<long-random-password>
   ```
   ```yaml
   # apps/extreme/silverbullet/tailscale-auth.sops.yaml   (same shape for apps/mini/silverbullet/)
   apiVersion: v1
   kind: Secret
   metadata:
     name: tailscale-auth
     namespace: silverbullet
   stringData:
     TS_AUTHKEY: <tailscale-auth-key>
   ```
   Fill them in, then `sops --encrypt --in-place <file>` (rules in `.sops.yaml`). Use a different password on each cluster's secret only if you want the standby to be distinguishable; it is not required.
3. Check the render, then commit and push (Flux applies it):
   ```sh
   kustomize build apps/extreme > /dev/null && kustomize build apps/mini > /dev/null && echo ok
   ```
4. Install the backup job (below).
5. Only after the tailnet test passes: in the Cloudflare dashboard add the route `silverbullet.kanokgan.com` -> `http://localhost:30300` on the tunnel `ubuntu-extreme` (Zero Trust, Networks, Tunnels), and the matching entry in `hosts/ubuntu-extreme/cloudflared/README.md`.

Status: live on the Lenovo since 2026-10-25 (tailnet name and `silverbullet.kanokgan.com` both checked).

## Verify

```sh
kubectl --context extreme -n silverbullet get pods,pvc          # 2/2 Running, PVC Bound
kubectl --context extreme -n silverbullet logs deploy/silverbullet -c silverbullet --tail=30
flux get kustomization apps --context extreme                   # READY True
ls -la /srv/silverbullet                                        # on the Lenovo: pages appear after the first edit
```
Then open the tailnet address, log in, create a page, and check the file on disk. Repeat on `silverbullet.kanokgan.com` from a phone off Wi-Fi.

## Storage

- Notes live on the Lenovo's NVMe (about 400 GB free after Immich, 2026-10-25). `hostPath` has no quota: the declared 100Gi is only a label. Watch `df -h /srv` and `du -sh /srv/silverbullet`.
- Keep **meeting recordings out of the notes**. Videos are large and SilverBullet's browser client keeps a local copy of the space for offline use (verify in the docs before relying on it), so large files slow every device. Put recordings on the NAS and link to them from a page. Revisit if PDFs and spreadsheets alone grow past about 50 GB.
- The Lenovo storage plan (second NVMe, LVM extend) is in `hosts/ubuntu-extreme/README.md`.

## Backup and restore

Nightly at 04:30 a systemd timer runs `silverbullet-nas-sync.sh`, which copies `/srv/silverbullet` to the NAS folder `/ZionLabs/SilverBullet/Backup` over SFTP on Tailscale. One way, never deletes on the NAS; the NAS snapshots on `ZionLabs` cover accidental changes. Files: `hosts/ubuntu-extreme/backup/silverbullet-nas-sync.*`.

Setup (once; the rclone remote `zion-nas` already exists from the Immich job):
```sh
cd hosts/ubuntu-extreme/backup
sudo install -m 0755 silverbullet-nas-sync.sh /usr/local/sbin/
sudo cp silverbullet-nas-sync.service silverbullet-nas-sync.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start silverbullet-nas-sync.service       # one manual run (the folder must not be empty)
journalctl -u silverbullet-nas-sync -n 30 --no-pager
sudo systemctl enable --now silverbullet-nas-sync.timer
sudo rclone --config /home/kanokgan/.config/rclone/rclone.conf check /srv/silverbullet zion-nas:/ZionLabs/SilverBullet/Backup --one-way
```
The NAS account `sc-zion` can write only under `ZionLabs`, so `/ZionLabs/SilverBullet/Backup` is created by rclone on the first run.

Restore: scale the app to 0 (set `replicas: 0` in a commit), `rclone copy zion-nas:/ZionLabs/SilverBullet/Backup /srv/silverbullet`, scale back to 1.

Status: installed 2026-10-25, first manual run clean, `rclone check` 0 differences over 3 files, timer enabled (first scheduled run 2026-10-26 04:30).

Restore test: **not done yet**. Do it on the mini (below), record the date here.

## Refresh the mini (standby)

The mini has no backup job and starts empty. To refresh it from the NAS copy: set `replicas: 0` for the mini overlay, copy the NAS folder into the mini's volume (for example `rclone copy` into the local-path directory in the Lima VM), set `replicas: 1`. Anything written on the mini is overwritten. This doubles as the restore test. The exact procedure is to be filled in the first time it is run (the mini's standby refresh for Immich is also still open).

## Runbook: upgrade SilverBullet

**Where the version lives:** the `images:` block of `apps/extreme/silverbullet/kustomization.yaml` and `apps/mini/silverbullet/kustomization.yaml`; the base has no tag.

1. Read the release notes (`https://github.com/silverbulletmd/silverbullet/releases`).
2. Confirm the tag exists and covers arm64 and amd64: `docker manifest inspect ghcr.io/silverbulletmd/silverbullet:<tag>-slim`.
3. Run the backup job by hand (`sudo systemctl start silverbullet-nas-sync.service`).
4. Upgrade the mini first, check it on the tailnet name, then the Lenovo. Commit `silverbullet: upgrade to X.Y.Z`.
5. Verify with the commands above. Rolling back means reverting the tag and, if the notes were changed by a migration, restoring the backup.

## Open items

- Restore test and the mini refresh procedure.
- Import the existing notes (by the owner, by hand), or decide to remove SilverBullet in favour of [Obsidian in the browser](obsidian.md), which the owner found more suitable.
- Disk usage is covered by the root disk alert (80% and 90%, [monitoring.md](monitoring.md)); there is no per-directory alert.
