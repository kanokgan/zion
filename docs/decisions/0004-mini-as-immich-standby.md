# 0004. Mac mini as a warm standby for Immich

- Status: accepted
- Date: 2026-10-11

## Context
The Lenovo (`k3s-master`, 2 TB NVMe, all data on local-path volumes) is the main host. Immich is the one service that must not go down: it is in daily use by family. The Mac mini M2 (8 GiB RAM, 8 cores, no GPU, FileVault on) is kept as a standby that can run Immich while the Lenovo is off for maintenance or has failed. It does not need to run the other services.

Current data path on the Lenovo, verified 2026-10-11:
- A CronJob `immich-library-sync` (04:00 Asia/Bangkok) runs `rclone copy` of the whole Immich folder, including Immich's own nightly database dump (`backups/`, written ~00:00), to the Synology over SFTP on Tailscale.
- That folder was copied to an external 2 TB APFS drive (`HighSpeed2T`) attached to the mini. It holds 1.3 TB, with dumps named `immich-db-backup-<ts>-v3.2.4-pg14.19.sql.gz` (~1 GB each).
- Images on the Lenovo: `immich-server:v3` (3.2.4 today), `immich/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, `redis:6.2-alpine`, ML `release-cuda`.

## Decision
- Two independent single-node clusters, not one two-node cluster. k3s with SQLite supports one server only, and a two-server etcd cluster is less available than one server. The mini's node sits in a NAT'd VM, and local volumes would not follow a pod anyway.
- The mini runs `zion` now (ADR 0003). When the Lenovo is rebuilt from this repo, the Lenovo becomes `zion` and the mini's cluster is renamed `zion-standby`.
- The standby runs Immich only, pinned to the same versions as production (server `v3.2.4`, same Postgres image). Machine learning is off on the standby (no GPU, little RAM); search and face recognition degrade there, which is accepted.
- Resting state: the server runs (1 replica) on the standby and is reachable over the tailnet at `https://immich-standby.dove-komodo.ts.net` (Tailscale sidecar). It is a read-mostly copy: uploads made there live only on the mini and are overwritten when the NVMe is refreshed from the NAS (FreeFileSync, one way NAS to mini, never the reverse). Its database stays at whatever dump was last restored.
- Public traffic is not wired to the standby: no `cloudflared` connector runs on the mini for now. A real failover for family therefore means pointing them at the tailnet address or adding the connector first.
- Standby data is the nightly offsite copy: photos from the external drive (shared into the VM), Postgres restored from the latest Immich dump onto the VM's own disk, not onto the shared mount.
- Only one cluster runs Immich writable at a time. Failover is manual and ordered: stop Immich on the Lenovo (if reachable), restore on the mini, verify, then switch traffic.

## Failover and failback (outline, to be tested before it is relied on)
1. Stop Immich on the Lenovo if it is up.
2. Start Immich on the mini; restore the latest dump through Immich's restore flow.
3. Verify login, recent photos, and a sample upload.
4. Switch traffic to the mini (not built; deferred). The Lenovo's tunnel is `home-brain` (it carries `immich.kanokgan.com` to `http://immich-server.immich.svc.cluster.local:80`); the mini has its own separate tunnel `macos-mini`, whose connector is `cloudflared` running on the Mac itself (ADR 0008), not in the cluster. Routes are managed in the Cloudflare dashboard, not in Git. A failover would move the `immich.kanokgan.com` hostname from `home-brain` to `macos-mini` and point it at something the Mac can reach, because cluster DNS names do not resolve from the host. That needs a NodePort Service plus a Lima port forward to the host (not written yet). One hostname may point at one tunnel only, so do not leave it on both. The Tailscale sidecar already has its own identity (`immich-standby`).
5. Failback: copy everything uploaded on the mini back to the Lenovo, restore the database there, verify, switch traffic back.

## Alternatives considered
- One two-node cluster: see Decision.
- Continuous replication (Postgres streaming, live file sync): more moving parts than a homelab needs; the nightly copy already exists.
- Standby for all services: the mini has 8 GiB of RAM and cannot hold them.

## Consequences
- Up to about 24 hours of photos and edits can be missing after a failover. Photos taken after the last sync exist only on the Lenovo.
- `rclone copy` never deletes, so a restore brings back photos that were deleted after the copy.
- ML runs on CPU on the mini and will be slow. During an outage it can be paused; search and face recognition degrade, browsing and uploading still work.
- The mini cannot recover unattended after a power cut while FileVault is on (open question).
- A restore from the mini's copy was tested once on 2026-10-11 and worked. Repeat it from a clean Postgres volume before relying on it for a real outage.
- Follow-ups for the Lenovo setup: pin `rclone/rclone`, `tailscale/tailscale` and the Immich server tag; consider replacing `--size-only`.
- Open: failback step 5 is only an outline, and the public traffic switch (a `cloudflared` connector on the mini) is deferred.
