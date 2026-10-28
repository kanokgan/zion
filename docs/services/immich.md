# Immich

Photo library used daily by family. Since 2026-10-21 the Lenovo (cluster `extreme`) serves `immich.kanokgan.com` (database restored 2026-10-20, hostname moved to the `ubuntu-extreme` tunnel; ADR 0009). Between 2026-10-17 and then the Mac mini (`mini`) served it while the Lenovo was rebuilt from this repo. The mini keeps its own old copy, running on purpose at its Tailscale name only (see "What runs where"); it takes no uploads. The old Lenovo cluster (`zion-old`) was wiped on 2026-10-17, so its library and databases are gone: the NAS, the mini's NVMe and the Lenovo's `/srv/immich` hold the data. Immich is the one service that must not go down.

## What runs where

| | Lenovo (`extreme`, production since 2026-10-21) | Mac mini (`mini`, old copy since the cutover) |
|---|---|---|
| Server | `immich-server:v3.3.4`, one GPU slice (transcoding) | `immich-server:v3.2.4`, 1 replica, kept running on purpose, at `https://immich-macos-mini.dove-komodo.ts.net` only. **Do not upload there**: it is not synchronised with the Lenovo |
| Postgres | `immich/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, 20Gi local-path, 2 CPU and 3Gi limits, restored from the mini's dump on 2026-10-20 | same image, 20Gi local-path, holds the database as of the cutover (v3.2.4) |
| Redis | `redis:6.2-alpine` | same |
| Machine learning | `immich-machine-learning:v3.3.4-cuda`, 1 replica on a GPU slice | CPU image, **0 replicas, disabled** (no GPU) |
| Library | `/srv/immich` on the Lenovo's disk (host directory, static PV) | external NVMe `HighSpeed2T`, folder `Immich/Backup`, shared into the Lima VM at `/mnt/immich-library`; frozen at the cutover |
| Public access | `immich.kanokgan.com` via tunnel `ubuntu-extreme` (host `cloudflared`), service `http://localhost:30283` -> NodePort Service (`apps/extreme/immich/nodeport.yaml`) | none (the hostname moved away from tunnel `macos-mini`) |

Manifests: `apps/base/immich/` (shared), `apps/extreme/immich/` and `apps/mini/immich/` (per-cluster overlays: library volume, Tailscale sidecar, NodePort, image tags). Secrets: `apps/*/immich/secret.sops.yaml` (SOPS, ADR 0007).

### Hostnames

| Name | What | Where |
|---|---|---|
| `immich.kanokgan.com` | production, public through Cloudflare | whichever machine is primary |
| `immich-ubuntu-extreme.dove-komodo.ts.net` | debug, tailnet only (Tailscale sidecar) | the Lenovo's instance |
| `immich-macos-mini.dove-komodo.ts.net` | debug, tailnet only (Tailscale sidecar) | the mini's instance (renamed from `immich-standby` on 2026-10-18, while the pod was down anyway) |

Pattern: `<app>-<machine>`, the machine names of the naming convention. Actual follows the same pattern.

## Data and backups

- Photos, thumbnails, encoded video and Immich's own nightly database dump (`backups/`, written about 00:00 Asia/Bangkok) live in the Immich upload folder.
- **Nightly Lenovo to NAS job** (since 2026-10-21): a systemd timer at 04:00 runs `rclone copy` (one way, never deletes) from `/srv/immich` to the NAS folder `/ZionLabs/Immich/Backup`, as root with the rclone config of the owner's home. Setup and reasons: [hosts/ubuntu-extreme/backup/](../../hosts/ubuntu-extreme/backup/README.md). First manual run 2026-10-21, then `rclone check` reported 0 differences over 556,496 files. Hourly Synology snapshots on `ZionLabs` protect against a bad copy. No alert yet if a night fails (monitoring stage 3).
- Only the primary machine writes to that NAS path. The mini's job (`hosts/macos-mini/backup/`) was never installed (its rclone remote was never configured) and must stay off while the mini holds only an old copy.
- Never copy the NAS onto the mini's NVMe or the Lenovo's `/srv/immich` except as a deliberate restore: it could overwrite newer uploads.
- Disk space: see the storage plan in [hosts/ubuntu-extreme/README.md](../../hosts/ubuntu-extreme/README.md). Cleanups still to do: untracked files (Administration, Repair) and a lower database backup retention.

### External libraries on the Lenovo (from 2026-10-21)

- A NAS "camera uploads" folder is bind-mounted read-only on the host at `/srv/external/camera-uploads` (an `/etc/fstab` line with the real names, kept off Git; pattern in [hosts/ubuntu-extreme/fstab.example](../../hosts/ubuntu-extreme/fstab.example)) and mounted read-only into the server at `/CameraUpload` (`apps/extreme/immich/kustomization.yaml`).
- The family's NAS drives (`ChurinDrive`, `JongdeeDrive`, `KanokganDrive`, `OrawanDrive`) and the dashcam share `IPCamera` are mounted read-only too, at `/<Share>` in the server pod (so an import path is `/IPCamera/<Folder>`). They use the host's existing CIFS mounts; the NAS account used there has read access only.
- Libraries are created in the Immich UI, one per subfolder, with an import path under a mount (checked inside the container) and folder watching off (inotify does not work on CIFS).
- The dashcam subfolder is deliberately not imported: its transcodes filled the disk before.
- The originals stay on the NAS and are not copied by the nightly job; the thumbnails and transcodes land in `/srv/immich`. If the NAS is down the folder is empty and a scan marks the assets offline until the files return.
- Roughly all of the drives' photos are already uploaded to Immich, and external-library assets are matched by path, not by content, so test with a small folder before importing a whole drive (duplicates).
- The mini mounts none of this.

## Restore tests

- 2026-10-11: server scaled to 1 on the mini, database restored from the Oct 11 dump through Immich's restore flow; recent photos opened and verified. Server then set back to 0.
- 2026-10-17: the NAS copy of the library was restored onto the mini's NVMe (FreeFileSync) and the database restored from a fresh dump.
- 2026-10-20 to 21: the library was copied from the NAS to the Lenovo's `/srv/immich` (plus a delta) and the database restored from the mini's dump (see "History").
- Not yet done: a restore from the nightly job's NAS copy onto a clean Lenovo, and a restore onto the mini from a Lenovo dump (needs the mini upgraded first).

## Runbook: restore a dump into an empty Immich

Verified on the mini on 2026-10-11 and on the Lenovo on 2026-10-20. Before: the library on the volume is as recent as you need, and the dump in `backups/` passes `gzip -t`.

1. Set the server's replicas to `1` in the cluster's overlay (`apps/<cluster>/immich/kustomization.yaml`) if it is `0`, commit and push. Flux applies it within its interval.
2. Wait for `kubectl --context <cluster> get pods -n immich` to show `immich-server` Running (2/2 with the sidecar).
3. Open the cluster's Tailscale name (see "Hostnames"), or `kubectl --context <cluster> port-forward -n immich svc/immich-server 2283:80` and `http://localhost:2283`. The empty database shows the first-run page: do not create an admin.
4. Restore from the newest `immich-db-backup-*.sql.gz` using Immich's restore from backup, and click Restore **once**. The restore takes several minutes (about 1 GB dump); a retry or page refresh kills it half way (`terminating connection due to administrator command` in the Postgres log). Watch `kubectl --context <cluster> logs deploy/immich-server -c immich-server -f` for `Restore progress`.
5. Log in with the existing admin account and check recent photos, an old photo, a video and thumbnails.

The dump carries the Immich version it was made with (`-v3.2.4-pg14.19`): restore it into the same or a newer server version, never an older one.

## Runbook: upgrade Immich

Immich releases often and some releases migrate the database, which a revert of the image tag does not undo. So an upgrade is one small commit, preceded by checks.

**Where the version lives:** only in the `images:` block of the cluster's overlay (`apps/extreme/immich/kustomization.yaml` for production; the mini has its own in `apps/mini/immich/kustomization.yaml`). The base manifests have no tag. Server and machine learning get the same tag (the CUDA image adds `-cuda`); change both lines together.

Risk: downtime during the rollout (`Recreate` strategy, plus startup migrations) and a possible one-way database migration. Rollback is a restore from the pre-upgrade dump, not just a revert. Upgrade one cluster, verify, then the other, never both on the same day.

Before:
1. Read the release notes for every version you skip, looking for "breaking changes" and Postgres or VectorChord requirements. Upgrade one major or minor at a time.
2. Confirm a fresh `immich-db-backup-*.sql.gz` exists in the library `backups/` folder, written within the last day, and note its file name (it carries the old version, which is what a rollback needs).
3. Confirm the new tag exists: `https://github.com/immich-app/immich/pkgs/container/immich-server` (and for `immich-machine-learning`).

Upgrade:
1. Edit both `newTag` values in the overlay.
2. Check the render: `kustomize build apps/extreme | grep 'image: ghcr.io/immich-app'` shows the new tag on both Immich images.
3. Commit (`immich: upgrade to vX.Y.Z`) and push. Flux applies it within its interval.

Verify:
```sh
kubectl --context extreme rollout status deploy/immich-server -n immich
kubectl --context extreme get pods -n immich
kubectl --context extreme logs deploy/immich-server -n immich --tail=50
flux get kustomization apps --context extreme   # READY True
curl -s https://immich.kanokgan.com/api/server/ping
```
Then open the app, check the version under the user menu, and open a recent and an old photo.

Rollback:
- Pod never became ready and logs show no migration ran: revert the commit and push.
- A migration ran (or you are unsure): scale the server to 0, revert the commit, bring up the old version on an empty database, and restore the pre-upgrade dump (runbook above).

Other Immich images (`postgres`, `redis`) are pinned in `apps/base/immich/` and are upgraded separately, only when the Immich release notes require it.

## Runbook: move production between the two machines

Used once, on 2026-10-20 to 21 (mini to Lenovo), and the template for the next swap. Rollback is possible only until the first upload lands on the new primary: move the hostname back to the old tunnel and start the old server again. After that, the uploads made on the new primary would have to be carried over first. On the Lenovo that window closed on 2026-10-20.

Ready when all of these are true:
- The library copy to the new primary's volume finished, and a second pass of the same `rsync` only lists a small delta.
- `apps` and `infrastructure` are Ready on the new cluster, the ML pod logs CUDA (if it has a GPU), and its tunnel is Healthy with no routes yet.
- The new primary's nightly backup is installed and has run once by hand, with its timer not yet enabled.
- A fresh Actual export is on the NAS, and the family knows uploads pause for a few hours.

Cutover (downtime starts at step 1), written for old primary = mini, new primary = Lenovo:
1. Old primary: in the Immich admin UI create a database backup (Administration, Jobs), wait for it, then put Immich in maintenance mode. Scale its server to 0 by committing `replicas: 0` in its overlay (otherwise Flux scales it back).
2. Old primary: run its NAS sync by hand and check the log shows no errors. Then **disable its nightly job**: only one machine may write to that NAS path.
3. New primary: copy the delta (`rsync` from `/mnt/ZionLabs/Immich/Backup/` to `/srv/immich/`). Check the new dump is there: `ls -lt /srv/immich/backups | head -3` and `gzip -t` on it.
4. New primary: commit `replicas: 1` for `immich-server` in its overlay and restore the dump (runbook above) on its tailnet name.
5. Verify before any traffic moves: a recent photo, an old photo, a video, thumbnails; pause the smart search and face queues if ML misbehaves; an upload from the tailnet address lands in `/srv/immich/upload`; a transcode job uses the GPU (`nvidia-smi` while it runs).
6. Cloudflare: move `immich.kanokgan.com` to the new tunnel (service `http://localhost:30283`). Test from a phone off Wi-Fi and off Tailscale: log in, scroll, upload.
7. New primary: enable the nightly backup timer (`sudo systemctl enable --now immich-nas-sync.timer`).
8. Old primary: either leave the server at 0 or keep it as a frozen old copy at its Tailscale name (what the owner chose on 2026-10-20). Nothing refreshes it yet.
9. Update the docs and the tracker.

Verify:
```sh
kubectl --context extreme get pods -n immich
curl -s https://immich.kanokgan.com/api/server/ping
ls -lt /srv/immich/upload/*/ | head
systemctl list-timers immich-nas-sync.timer
```

## Failover and failback (outline, untested)

The mini is not a working standby: its copy is frozen at the cutover, it runs v3.2.4 while the Lenovo runs v3.3.4 (a newer dump cannot be restored onto it until it is upgraded), and no `cloudflared` route points at it for Immich. Until the refresh procedure exists (tracker), a Lenovo outage means waiting for the Lenovo, or restoring from the NAS on the mini by hand.

Only one instance may be writable at a time. Outline for when the standby is real:
1. Make sure the Lenovo's Immich is stopped (if reachable): scale `immich-server` to 0 there.
2. On the mini, refresh the NVMe copy from the NAS if it is stale, upgrade it to the Lenovo's version, restore the newest dump (runbook above) and keep the server at 1.
3. Move `immich.kanokgan.com` from tunnel `ubuntu-extreme` to `macos-mini` (service `http://localhost:30283`, forwarded by Lima). One hostname belongs to one tunnel.
4. Tell the family which address to use.

Known limits: up to the last NAS copy of photos is missing; deleted photos can come back; ML search and faces are off; NAS external libraries are missing.

Failback is not automated: stop Immich on the mini, copy anything uploaded there back to the Lenovo's library, restore the mini's latest dump on the Lenovo (or accept that only the files return and re-scan them in), verify, then move the hostname back. Decide the database question before the first real failover.

## History

### Cutover to the mini (2026-10-17)

Lenovo put in maintenance mode, manual DB dump (`immich-db-backup-20261017T095245-v3.2.4-pg14.19.sql.gz`), library synced Lenovo to NAS to NVMe (FreeFileSync, about 2 hours), mini pinned to v3.2.4 (the Lenovo's version; the mini had been on v3.3.1 and its migrated DB refused v3.2.4, so its Postgres PVC was recreated), dump checked with `gzip -t`, Lenovo server scaled to 0, database restored through Immich's restore flow, `immich.kanokgan.com` moved from tunnel `home-brain` to `macos-mini`. External libraries and machine learning were not available on the mini.

### Cutover back to the Lenovo (2026-10-20 to 21)

Mini: fresh database dump, maintenance mode, server scaled to 0 (commit), library copied mini to NAS (FreeFileSync, update mode), `rclone check` clean. Lenovo: delta `rsync` from the NAS into `/srv/immich`, server scaled to 1, database restored from the mini's `immich-db-backup-20261019T221057-v3.2.4-pg14.19.sql.gz`, then `immich.kanokgan.com` moved to the `ubuntu-extreme` tunnel. Lessons:
- The restore took several minutes at the Postgres 1 CPU limit (about 1 GB dump). Earlier attempts "hung" because each retry or page refresh killed the restore before it finished.
- The container writes `/srv/immich` as root, so host jobs that read it (the NAS backup) must run as root.
- The Lenovo was upgraded to v3.3.4 after the restore; the mini stayed on v3.2.4.
- After the restore, the Postgres limits on `extreme` were raised from 1 CPU and 1.5Gi to 2 CPU and 3Gi (`apps/extreme/immich/kustomization.yaml`, 2026-10-21; the mini keeps the base values). Applying it restarts Postgres, so Immich is briefly unavailable.
- At the cutover the owner kept the mini's server at 1 replica instead of 0, as a frozen old copy.

## Image pinning exception

All Immich images are pinned. The Tailscale sidecar (`tailscale/tailscale:latest`, `imagePullPolicy: Always`) is a deliberate exception: it is a backward-compatible networking client and should pick up security fixes without a commit. Cost: starting the pod needs Docker Hub reachable, and a bad release could break a sidecar without a commit to point at. If that happens, pin a stable `vX.Y.Z` tag (check Docker Hub for what exists).

## Open items

- A refresh procedure for the mini (NAS to NVMe, upgrade to the Lenovo's version, DB restore on a clean Postgres volume), then a tested failover and failback. Automate the NAS to NVMe copy and record how stale is acceptable.
- Restore the library from the nightly job's NAS copy onto a clean Lenovo, once, before relying on it.
- Clean up untracked files and lower the database backup retention (after the cutover is verified).
- Alert when the nightly NAS job fails (monitoring stage 3, [monitoring.md](monitoring.md)).
