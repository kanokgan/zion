# Immich

Photo library used daily by family. Since 2026-10-17 the Mac mini (`zion`) serves `immich.kanokgan.com`; the Lenovo (`zion-old`, node `k3s-master`) is scaled to 0 and kept as a rollback until it is wiped and rebuilt (ADR 0004). Immich is the one service that must not go down.

## What runs where

| | Lenovo (`zion-old`, scaled to 0 since 2026-10-17) | Mac mini (`zion`, production since 2026-10-17) |
|---|---|---|
| Server | `immich-server:v3` (resolves to v3.2.4), GPU | `immich-server:v3.2.4`, 1 replica (also at `https://immich-standby.dove-komodo.ts.net`) |
| Postgres | `immich/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, 20Gi local-path | same image, 20Gi local-path, restored from the Lenovo's dump on 2026-10-17 |
| Redis | `redis:6.2-alpine` | same |
| Machine learning | `release-cuda`, GPU | CPU image, **0 replicas, disabled** (not needed on the standby) |
| Library | 1Ti local-path PVC on the Lenovo's NVMe | external NVMe `HighSpeed2T`, folder `Immich/Backup`, shared into the Lima VM at `/mnt/immich-library` |
| Public access | Cloudflare tunnel `home-brain`; the `immich.kanokgan.com` route was removed on 2026-10-17 | `immich.kanokgan.com` via tunnel `macos-mini` (host `cloudflared`), service `http://localhost:30283` -> Lima port forward -> NodePort Service `immich-server-nodeport` (`apps/zion/immich/nodeport.yaml`) |

Manifests: `apps/base/immich/` (shared) and `apps/zion/immich/` (standby overlay and library volume). Secrets: `apps/zion/immich/secret.sops.yaml` (SOPS, ADR 0007).

## Data and backups

- Photos, thumbnails, encoded video and Immich's own nightly database dump (`backups/`, written about 00:00 Asia/Bangkok) live in the Immich upload folder.
- The Lenovo's CronJob `immich-library-sync` (04:00, `rclone copy`, never deletes) is no longer the source of truth. **A nightly mini to NAS job (04:00, `rclone copy`, run on the Mac host, not in the cluster) is planned and not built yet**, so new uploads on the mini exist only on its NVMe until it runs.
- Never run FreeFileSync from the NAS to the NVMe again: it would overwrite the mini's newer uploads. The only direction is mini to NAS.
- NAS external libraries (four personal drives, `/V11Pro`, `/70Mai`) are not mounted on the standby. Their assets will show as unavailable there.

## Cutover to the mini (2026-10-17)

Lenovo put in maintenance mode, manual DB dump (`immich-db-backup-20261017T095245-v3.2.4-pg14.19.sql.gz`), library synced Lenovo to NAS to NVMe (FreeFileSync, about 2 hours), mini pinned to v3.2.4 (the Lenovo's version; the mini had been on v3.3.1 and its migrated DB refused v3.2.4, so its Postgres PVC was recreated), dump checked with `gzip -t`, Lenovo server scaled to 0, database restored through Immich's restore flow, `immich.kanokgan.com` moved from tunnel `home-brain` to `macos-mini`. External libraries and machine learning are not available on the mini. Newer Immich versions (v3.3.x) are a separate upgrade, see the runbook below.

## Restore test

- 2026-10-11: server scaled to 1 on the mini, database restored from the Oct 11 dump through Immich's restore flow; recent photos opened and verified. Server then set back to 0.

## Runbook: start the standby and restore (verified once, on 2026-10-11)

Before: confirm the NVMe is attached, the Lima VM is running, and the copy on the NVMe is as recent as you need.

1. The resting state is 1 replica. If `apps/zion/immich/kustomization.yaml` has the `immich-server` replicas value at `0`, set it to `1`, commit and push.
2. `flux reconcile kustomization apps --with-source --context zion`
3. Wait for `kubectl --context zion get pods -n immich` to show `immich-server` `1/1 Running`.
4. Open `https://immich-standby.dove-komodo.ts.net` (or `kubectl --context zion port-forward -n immich svc/immich-server 2283:80` and `http://localhost:2283`).
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

**Where the version lives:** only in the `images:` block of `apps/zion/immich/kustomization.yaml` (each cluster overlay owns its own). The base manifests have no tag. Server and machine learning get the same tag; change both lines together.

Risk: downtime during the rollout (`Recreate` strategy, plus startup migrations) and a possible one-way database migration. Rollback is a restore from the pre-upgrade dump, not just a revert. Do not upgrade the standby and the Lenovo on the same day: upgrade one, verify, then the other.

Before:
1. Read the release notes for every version you skip, looking for "breaking changes" and Postgres or VectorChord requirements. Upgrade one major or minor at a time.
2. Confirm a fresh `immich-db-backup-*.sql.gz` exists in the library `backups/` folder, written within the last day, and note its file name (it carries the old version, which is what a rollback needs).
3. Confirm the new tag exists: `https://github.com/immich-app/immich/pkgs/container/immich-server` (and for `immich-machine-learning`).

Upgrade:
1. Edit both `newTag` values in `apps/zion/immich/kustomization.yaml`.
2. Check the render: `kustomize build apps/zion | grep 'image: ghcr.io/immich-app'` shows the new tag on both Immich images.
3. Commit (`immich: upgrade to vX.Y.Z`), push, then `flux reconcile kustomization apps --with-source --context zion` to skip the wait.

Verify:
```sh
kubectl --context zion rollout status deploy/immich-server -n immich
kubectl --context zion get pods -n immich
kubectl --context zion logs deploy/immich-server -n immich --tail=50
flux get kustomization apps --context zion   # READY True
```
Then open the app, check the version under the user menu, and open a recent and an old photo.

Rollback:
- Pod never became ready and logs show no migration ran: revert the commit and push.
- A migration ran (or you are unsure): scale the server to 0, revert the commit, bring up the old version on an empty database, and restore the pre-upgrade dump through Immich's restore flow (runbook above).

Other Immich images (`postgres`, `redis`) are pinned in `apps/base/immich/` and are upgraded separately, only when the Immich release notes require it.

## Image pinning exception

All Immich images are pinned. The Tailscale sidecar (`tailscale/tailscale:latest`, `imagePullPolicy: Always`) is a deliberate exception: it is a backward-compatible networking client and should pick up security fixes without a commit. Cost: starting the pod needs Docker Hub reachable, and a bad release could break `immich-standby` without a commit to point at. If that happens, pin a stable `vX.Y.Z` tag (check Docker Hub for what exists).

## Open items

- Nightly mini to NAS `rclone` job (04:00) on the Mac host; until then uploads on the mini have no second copy.
- Upgrade the mini from v3.2.4 to the current release after reading the notes (v3.3.3 was the latest seen on 2026-10-17).
- Re-enable the external libraries when the Lenovo is rebuilt (their paths are not mounted on the mini).
- Failback step 3 needs a decision and a test.
- Automate the NAS to NVMe copy (FreeFileSync schedule) and record how stale is acceptable.
- Restore from the NVMe copy has been tested once; repeat it from a clean Postgres volume before relying on it.
