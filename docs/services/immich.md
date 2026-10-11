# Immich

Photo library used daily by family. The main instance runs on the Lenovo (`zion-old`, node `k3s-master`). A warm standby runs on the Mac mini (`zion`, ADR 0004). Immich is the one service that must not go down.

## What runs where

| | Lenovo (`zion-old`) | Mac mini (`zion`, standby) |
|---|---|---|
| Server | `immich-server:v3` (resolves to v3.2.4), GPU | `immich-server:v3.2.4`, **1 replica** (read-mostly copy at `https://immich-standby.dove-komodo.ts.net`) |
| Postgres | `immich/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, 20Gi local-path | same image, 20Gi local-path, **running, empty until restored** |
| Redis | `redis:6.2-alpine` | same |
| Machine learning | `release-cuda`, GPU | CPU image, **0 replicas, disabled** (not needed on the standby) |
| Library | 1Ti local-path PVC on the Lenovo's NVMe | external NVMe `HighSpeed2T`, folder `Immich/Backup`, shared into the Lima VM at `/mnt/immich-library` |
| Public access | Cloudflare tunnel (token-based, routes in the Cloudflare dashboard), backend `http://immich-server.immich.svc.cluster.local:80` | none until a failover |

Manifests: `apps/base/immich/` (shared) and `apps/zion/immich/` (standby overlay and library volume). Secrets: `apps/zion/immich/secret.sops.yaml` (SOPS, ADR 0007).

## Data and backups

- Photos, thumbnails, encoded video and Immich's own nightly database dump (`backups/`, written about 00:00 Asia/Bangkok) live in the Immich upload folder.
- CronJob `immich-library-sync` on the Lenovo copies that folder to the Synology at 04:00 (`rclone copy`, never deletes).
- FreeFileSync copies the NAS folder onto the mini's NVMe. The standby is only as fresh as the last run of that copy.
- NAS external libraries (four personal drives, `/V11Pro`, `/70Mai`) are not mounted on the standby. Their assets will show as unavailable there.

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

## Image pinning exception

All Immich images are pinned. The Tailscale sidecar (`tailscale/tailscale:latest`, `imagePullPolicy: Always`) is a deliberate exception: it is a backward-compatible networking client and should pick up security fixes without a commit. Cost: starting the pod needs Docker Hub reachable, and a bad release could break `immich-standby` without a commit to point at. If that happens, pin a stable `vX.Y.Z` tag (check Docker Hub for what exists).

## Open items

- Tailscale access to the standby (see the mini's Tailscale plan).
- `cloudflared` connector manifest for the mini, and the actual switch procedure.
- Failback step 3 needs a decision and a test.
- Automate the NAS to NVMe copy (FreeFileSync schedule) and record how stale is acceptable.
- Restore from the NVMe copy has been tested once; repeat it from a clean Postgres volume before relying on it.
