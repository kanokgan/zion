# 0002. Parallel-cluster migration

- Status: accepted
- Date: 2026-10-11

## Context
The legacy cluster `zion-old` (k3s on the Lenovo X1 Extreme2) grew ad hoc and is not reproducible from Git. It serves production today: Immich (including a public domain used by family), Actual Budget, Plex, and Jellyfin. Data loss or long downtime matters.

We want a clean cluster built only from this repo. Rebuilding in place would not prove that the repo can recreate the cluster, so the new cluster `zion` is built separately, on a Mac mini M2 (ARM64). The Mac mini is a temporary host. How to run Kubernetes on macOS (Linux VM vs Asahi Linux) is undecided and gets its own ADR.

Running both clusters in parallel:
- `zion-old` keeps serving production, including the public domain, until each service is cut over. It is a read-only reference for configuration and data; nothing changes it except the cutover steps below.
- `zion` is reachable through Tailscale test endpoints and uses disposable copies of data until that service's cutover.
- Never two instances writable against the same data.

Order of work: platform first (Kubernetes on macOS, repo layout, GitOps, secrets, ingress/DNS/TLS, NAS storage, backups), then services in this order: Jellyfin, Plex, Actual Budget, Immich.

Cutover per service:
1. Scale the old instance to 0.
2. Take a final backup.
3. Restore it into `zion`.
4. Verify.
5. Repoint the same hostnames (Tailscale and Cloudflare) to `zion`.
6. Soak for about 2 weeks with the old instance scaled to 0 and its data kept.
7. Remove the service from `zion-old`.

## Decision
Build `zion` in parallel from the repo only, and migrate one service at a time with the cutover procedure above. `zion-old` stays untouched (read-only reference) until it is decommissioned.

## Alternatives considered
- In-place refactor of the existing cluster: never proves that the cluster can be rebuilt from the repo, and every change risks the live services.
- Big-bang rebuild: all the downtime at once, and no rollback once the old cluster is gone.
- Letting users switch to `zion` early: photo and budget data would diverge between clusters, with no way to merge them.

## Consequences
- Container images must be multi-arch (ARM64 on the Mac mini, AMD64 on the old host and a possible future host).
- Plex and Jellyfin will likely lose hardware transcoding when running inside a VM. (Superseded by ADR 0008: they run natively on the mini instead.)
- The Mac mini is temporary, so there will be a second move later. That move should be a rebuild-from-repo plus restore, which doubles as the reproducibility test.
- `zion` app state gets its own NAS paths, separate from `zion-old`. Media may be mounted read-only by both clusters.
- Two sets of endpoints exist during the migration (production hostnames on `zion-old`, Tailscale test endpoints on `zion`), and hostnames are repointed per service at cutover.
- Revisit when the host for `zion` changes, and when the last service leaves `zion-old` (decommission).
