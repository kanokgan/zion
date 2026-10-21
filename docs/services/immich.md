# Immich

Photo library used daily by family. Since 2026-10-21 the Lenovo (cluster `extreme`) serves `immich.kanokgan.com` again (database restored 2026-10-20, hostname moved to the `ubuntu-extreme` tunnel; ADR 0009). Between 2026-10-17 and then the Mac mini (`mini`) served it while the Lenovo was rebuilt from this repo. The mini keeps its own old copy, running on purpose at its Tailscale name only (see "What runs where"); it takes no uploads. The old Lenovo cluster (`zion-old`) was wiped on 2026-10-17, so its library and databases are gone: the NAS, the mini's NVMe and the Lenovo's `/srv/immich` hold the data. Immich is the one service that must not go down.

## What runs where

| | Lenovo (`extreme`, production since 2026-10-21) | Mac mini (`mini`, old copy since the cutover) |
|---|---|---|
| Server | `immich-server:v3.3.4`, one GPU slice (transcoding) | `immich-server:v3.2.4`, 1 replica, kept running on purpose, at `https://immich-macos-mini.dove-komodo.ts.net` only. **Do not upload there**: it is not synchronised with the Lenovo |
| Postgres | `immich/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, 20Gi local-path, restored from the mini's dump on 2026-10-20 | same image, 20Gi local-path, holds the database as of the cutover (v3.2.4) |
| Redis | `redis:6.2-alpine` | same |
| Machine learning | `immich-machine-learning:v3.3.4-cuda`, 1 replica on a GPU slice | CPU image, **0 replicas, disabled** (no GPU) |
| Library | `/srv/immich` on the Lenovo's disk (host directory, static PV) | external NVMe `HighSpeed2T`, folder `Immich/Backup`, shared into the Lima VM at `/mnt/immich-library`; frozen at the cutover |
| Public access | `immich.kanokgan.com` via tunnel `ubuntu-extreme` (host `cloudflared`), service `http://localhost:30283` -> NodePort Service (`apps/extreme/immich/nodeport.yaml`) | none (the hostname moved away from tunnel `macos-mini`) |

Manifests: `apps/base/immich/` (shared), `apps/extreme/immich/` and `apps/mini/immich/` (per-cluster overlays: library volume, Tailscale sidecar, NodePort, image tags). Secrets: `apps/*/immich/secret.sops.yaml` (SOPS, ADR 0007).

## Data and backups

- Photos, thumbnails, encoded video and Immich's own nightly database dump (`backups/`, written about 00:00 Asia/Bangkok) live in the Immich upload folder.
- **Nightly Lenovo to NAS job** (since 2026-10-21): a systemd timer at 04:00 runs `rclone copy` (one way, never deletes) from `/srv/immich` to the NAS folder `/ZionLabs/Immich/Backup`, as root with the rclone config of the owner's home. Setup and reasons: [hosts/ubuntu-extreme/backup/](../../hosts/ubuntu-extreme/backup/README.md). First manual run 2026-10-21, then `rclone check` reported 0 differences over 556,496 files. Hourly Synology snapshots on `ZionLabs` protect against a bad copy. No alert yet if a night fails.
- Only the primary machine writes to that NAS path. The mini's job (`hosts/macos-mini/backup/`) was never installed (its rclone remote was never configured) and must stay off while the mini holds only an old copy.
- Never copy the NAS onto the mini's NVMe or the Lenovo's `/srv/immich` except as a deliberate restore: it could overwrite newer uploads.
- **External libraries on the Lenovo (from 2026-10-21):** a NAS "camera uploads" folder is bind-mounted read-only on the host at `/srv/external/camera-uploads` (an `/etc/fstab` line with the real names, kept off Git; pattern in [hosts/ubuntu-extreme/fstab.example](../../hosts/ubuntu-extreme/fstab.example)) and mounted read-only into the server at `/CameraUpload` (`apps/extreme/immich/kustomization.yaml`). Libraries are created in the Immich UI, one per subfolder, with an import path under that mount (`/CameraUpload/<SubFolder>`, checked inside the container) and folder watching off (inotify does not work on CIFS). The dashcam subfolder is deliberately not imported: its transcodes filled the disk before. The originals stay on the NAS and are not copied by the nightly job; the thumbnails and transcodes land in `/srv/immich`. If the NAS is down the folder is empty and a scan marks the assets offline until the files return. The family's NAS drives (`ChurinDrive`, `JongdeeDrive`, `KanokganDrive`, `OrawanDrive`) and the dashcam share `IPCamera` are mounted read-only too, at `/<Share>` in the server pod (so an import path is `/IPCamera/<Folder>`) (the host's existing CIFS mounts; the NAS account used there has read access only). Roughly all of their photos are already uploaded to Immich, and external-library assets are matched by path, not by content, so test with a small folder before importing a whole drive (duplicates). The mini mounts none of this.

## Cutover to the mini (2026-10-17)

Lenovo put in maintenance mode, manual DB dump (`immich-db-backup-20261017T095245-v3.2.4-pg14.19.sql.gz`), library synced Lenovo to NAS to NVMe (FreeFileSync, about 2 hours), mini pinned to v3.2.4 (the Lenovo's version; the mini had been on v3.3.1 and its migrated DB refused v3.2.4, so its Postgres PVC was recreated), dump checked with `gzip -t`, Lenovo server scaled to 0, database restored through Immich's restore flow, `immich.kanokgan.com` moved from tunnel `home-brain` to `macos-mini`. External libraries and machine learning are not available on the mini. Newer Immich versions (v3.3.x) are a separate upgrade, see the runbook below.

## Cutover back to the Lenovo (2026-10-20 to 21)

Mini: fresh database dump, maintenance mode, server scaled to 0 (commit), library copied mini to NAS (FreeFileSync, update mode), `rclone check` clean. Lenovo: delta `rsync` from the NAS into `/srv/immich`, server scaled to 1, database restored through Immich's restore flow from the mini's `immich-db-backup-20261019T221057-v3.2.4-pg14.19.sql.gz`, then `immich.kanokgan.com` moved to the `ubuntu-extreme` tunnel. Lessons:
- The restore took several minutes at the Postgres 1 CPU limit (about 1 GB dump). Earlier attempts "hung" because each retry or page refresh killed the restore before it finished (`terminating connection due to administrator command` in the Postgres log). Watch `kubectl logs deploy/immich-server -c immich-server -f` for `Restore progress`, and click Restore once.
- The container writes `/srv/immich` as root, so host jobs that read it (the NAS backup) must run as root.
- The Lenovo was upgraded to v3.3.4 after the restore; the mini stays on v3.2.4, so a newer dump cannot be restored onto the mini until it is upgraded too.
- After the restore, the Postgres limits on `extreme` were raised from 1 CPU and 1.5Gi to 2 CPU and 3Gi (`apps/extreme/immich/kustomization.yaml`, 2026-10-21; the mini keeps the base values). Applying it restarts Postgres, so Immich is briefly unavailable.

## Hostnames

| Name | What | Where |
|---|---|---|
| `immich.kanokgan.com` | production, public through Cloudflare | whichever machine is primary |
| `immich-ubuntu-extreme.dove-komodo.ts.net` | debug, tailnet only (Tailscale sidecar) | the Lenovo's instance |
| `immich-macos-mini.dove-komodo.ts.net` | debug, tailnet only (Tailscale sidecar) | the mini's instance (renamed from `immich-standby` on 2026-10-18, while the pod was down anyway) |

Pattern: `<app>-<machine>`, the machine names of the naming convention. Actual follows the same pattern.

## Runbook: cutover between the two machines (ADR 0009; run once, 2026-10-20 to 21, keep for the next swap)

The Lenovo is the cluster `extreme` (`hosts/ubuntu-extreme/`, `clusters/extreme/`, `apps/extreme/`). This runbook moves production from the mini to the Lenovo and is the template for moving it back. Rollback is possible only until the first upload lands on the new primary: move the hostname back to the old tunnel and start the old server again. After that, the uploads made on the new primary would have to be carried over first. On the Lenovo that window closed on 2026-10-20.

Ready when all of these are true:
- The library copy to `/srv/immich` finished, and a second pass of the same `rsync` only lists a small delta.
- `apps` and `infrastructure` are Ready on `extreme`, the ML pod logs CUDA, and the `ubuntu-extreme` tunnel is Healthy with no routes yet (`hosts/ubuntu-extreme/cloudflared/README.md`).
- The Lenovo's nightly backup is installed and has run once by hand (`hosts/ubuntu-extreme/backup/`), with its timer not yet enabled.
- A fresh Actual export is on the NAS, and the family knows uploads pause for a few hours.

Cutover (downtime starts at step 1):
1. Mini: in the Immich admin UI create a database backup (Administration, Jobs), wait for it, then put Immich in maintenance mode. Scale the mini's server to 0 by committing `replicas: 0` in `apps/mini/immich/kustomization.yaml` (otherwise Flux scales it back). Both mini sidecars are already named `immich-macos-mini` and `actual-macos-mini`.
2. Mini: run `hosts/macos-mini/backup/immich-nas-sync.sh` by hand; check its log shows no errors. Then **disable its nightly job** (`sudo launchctl bootout system /Library/LaunchDaemons/com.zionlab.immich-nas-sync.plist`): only one machine may write to that NAS path.
3. Lenovo: copy the delta, the same command as the first copy (`rsync` from `/mnt/ZionLabs/Immich/Backup/` to `/srv/immich/`). Check the new dump is there: `ls -lt /srv/immich/backups | head -3` and `gzip -t` on it.
4. Lenovo: commit `replicas: 1` for `immich-server` in `apps/extreme/immich/kustomization.yaml`; wait for the pod (2/2). Open `https://immich-ubuntu-extreme.dove-komodo.ts.net`: the first-run page. Do not create an admin. Restore from the newest `immich-db-backup-*-v3.2.4-pg14.19.sql.gz`, then log in with the existing admin account.
5. Verify before any traffic moves: a recent photo, an old photo, a video, thumbnails; pause the smart search and face queues if ML misbehaves (the GPU should now run them); an upload from the tailnet address lands in `/srv/immich/upload`. Check a transcode job uses the GPU (`nvidia-smi` while it runs). The external libraries are still not mounted.
6. Cloudflare: move `immich.kanokgan.com` from tunnel `macos-mini` to `ubuntu-extreme` (service `http://localhost:30283`). Test from a phone off Wi-Fi and off Tailscale: log in, scroll, upload.
7. Lenovo: enable the nightly backup timer (`sudo systemctl enable --now immich-nas-sync.timer`).
8. Mini: the runbook said to leave the server at 0; at the 2026-10-20 cutover the owner kept it at 1 instead, reachable only at its Tailscale name, as a frozen old copy. It holds an old database and takes no uploads; nothing refreshes it yet. Define the mini's standby refresh (NAS to NVMe, then the DB restore, which needs the mini upgraded to the Lenovo's version) before relying on it as a standby.
9. Switch `apps.yaml` health checks back (Actual at 1 replica, `wait: true`) after the Actual cutover, update the docs and the tracker, and record the date here.

Verify:
```sh
kubectl --context extreme get pods -n immich
curl -s https://immich.kanokgan.com/api/server/ping
ls -lt /srv/immich/upload/*/ | head
systemctl list-timers immich-nas-sync.timer
```

## Restore test

- 2026-10-11: server scaled to 1 on the mini, database restored from the Oct 11 dump through Immich's restore flow; recent photos opened and verified. Server then set back to 0.

## Runbook: start the standby and restore (verified once, on 2026-10-11)

Before: confirm the NVMe is attached, the Lima VM is running, and the copy on the NVMe is as recent as you need.

1. The resting state is 1 replica. If `apps/mini/immich/kustomization.yaml` has the `immich-server` replicas value at `0`, set it to `1`, commit and push.
2. `flux reconcile kustomization apps --with-source --context mini`
3. Wait for `kubectl --context mini get pods -n immich` to show `immich-server` `1/1 Running`.
4. Open `https://immich-macos-mini.dove-komodo.ts.net` (or `kubectl --context mini port-forward -n immich svc/immich-server 2283:80` and `http://localhost:2283`).
5. On an empty database, restore from the newest `immich-db-backup-*-v3.2.4-pg14.19.sql.gz` using Immich's restore from backup.
6. Log in and check recent photos, an old photo, and thumbnails.

Check these steps against what you actually clicked and correct this section: it was written from the plan, not recorded during the run.

## Failover (Lenovo unavailable)

Superseded while the mini is production; kept for when the Lenovo is rebuilt and the mini returns to standby.

Only one instance may be writable at a time.

1. Make sure the Lenovo's Immich is stopped (if reachable): scale `immich-server` to 0 there.
2. Refresh the NVMe copy from the NAS if the Lenovo is down for a while and the copy is stale.
3. Run the restore runbook above (steps 1 to 6) and keep the server at 1.
4. Switch public traffic: stop the Lenovo's `cloudflared` connector, then run a `cloudflared` connector on the mini with the same tunnel token. The backend URL is identical on both clusters. (Not built yet.)
5. Tell family to use the standby address (Tailscale name once set up, see below).

Known limits: up to the last NAS copy of photos is missing; deleted photos can come back; ML search and faces are off; NAS external libraries are missing.

## Failback (Lenovo back)

Not automated. Outline:

1. On the mini, stop Immich (replicas 0) so nothing else is written.
2. Copy anything new from the mini's NVMe library (files added since the failover) back to the Lenovo's library.
3. Restore the mini's latest database dump on the Lenovo, or accept that uploads made during the outage are only the files and re-scan them in. Decide this before the first real failover.
4. Verify on the Lenovo, then move public traffic back and stop the mini's connector.

## Runbook: upgrade Immich

Immich releases often and some releases migrate the database, which a revert of the image tag does not undo. So an upgrade is one small commit, preceded by checks.

**Where the version lives:** only in the `images:` block of `apps/mini/immich/kustomization.yaml` (each cluster overlay owns its own). The base manifests have no tag. Server and machine learning get the same tag; change both lines together.

Risk: downtime during the rollout (`Recreate` strategy, plus startup migrations) and a possible one-way database migration. Rollback is a restore from the pre-upgrade dump, not just a revert. Do not upgrade the standby and the Lenovo on the same day: upgrade one, verify, then the other.

Before:
1. Read the release notes for every version you skip, looking for "breaking changes" and Postgres or VectorChord requirements. Upgrade one major or minor at a time.
2. Confirm a fresh `immich-db-backup-*.sql.gz` exists in the library `backups/` folder, written within the last day, and note its file name (it carries the old version, which is what a rollback needs).
3. Confirm the new tag exists: `https://github.com/immich-app/immich/pkgs/container/immich-server` (and for `immich-machine-learning`).

Upgrade:
1. Edit both `newTag` values in `apps/mini/immich/kustomization.yaml`.
2. Check the render: `kustomize build apps/mini | grep 'image: ghcr.io/immich-app'` shows the new tag on both Immich images.
3. Commit (`immich: upgrade to vX.Y.Z`), push, then `flux reconcile kustomization apps --with-source --context mini` to skip the wait.

Verify:
```sh
kubectl --context mini rollout status deploy/immich-server -n immich
kubectl --context mini get pods -n immich
kubectl --context mini logs deploy/immich-server -n immich --tail=50
flux get kustomization apps --context mini   # READY True
```
Then open the app, check the version under the user menu, and open a recent and an old photo.

Rollback:
- Pod never became ready and logs show no migration ran: revert the commit and push.
- A migration ran (or you are unsure): scale the server to 0, revert the commit, bring up the old version on an empty database, and restore the pre-upgrade dump through Immich's restore flow (runbook above).

Other Immich images (`postgres`, `redis`) are pinned in `apps/base/immich/` and are upgraded separately, only when the Immich release notes require it.

## Image pinning exception

All Immich images are pinned. The Tailscale sidecar (`tailscale/tailscale:latest`, `imagePullPolicy: Always`) is a deliberate exception: it is a backward-compatible networking client and should pick up security fixes without a commit. Cost: starting the pod needs Docker Hub reachable, and a bad release could break `immich-macos-mini` without a commit to point at. If that happens, pin a stable `vX.Y.Z` tag (check Docker Hub for what exists).

## Open items

- Nightly mini to NAS `rclone` job (04:00) on the Mac host; until then uploads on the mini have no second copy.
- Upgrade the mini from v3.2.4 to the current release after reading the notes (v3.3.3 was the latest seen on 2026-10-17).
- Re-enable the external libraries when the Lenovo is rebuilt (their paths are not mounted on the mini).
- Failback step 3 needs a decision and a test.
- Automate the NAS to NVMe copy (FreeFileSync schedule) and record how stale is acceptable.
- Restore from the NVMe copy has been tested once; repeat it from a clean Postgres volume before relying on it.
