# 0009. Rebuild the Lenovo in place as the cluster `extreme`

- Status: accepted
- Date: 2026-10-17

## Context
The Lenovo (host and node `k3s-master`, cluster `zion-old`) grew ad hoc and is not described in Git (ADR 0002). On 2026-10-17 Immich and Actual moved to the Mac mini (`zion`), which now serves `immich.kanokgan.com` and `actual.kanokgan.com`; the Lenovo's Immich is scaled to 0. The mini has 8 GiB of RAM, no GPU and a FileVault disk, and is meant to be the standby (ADR 0004). The Lenovo has the GPU and the 1 TB NVMe.

Found while preparing (details in `hosts/ubuntu-extreme/README.md`): k3s started with defaults plus a world-readable kubeconfig, a custom containerd template making `nvidia` the default runtime, GPU time-slicing and a device plugin that exist only in the cluster, a root cron job nobody documented, and an unattended driver upgrade that broke the GPU silently for weeks. None of it was in Git.

## Decision
- **Keep the OS, replace everything above it.** Ubuntu Server, Tailscale, SSH and `/etc/fstab` stay. k3s is removed and reinstalled from this repo. No OS reinstall, because the machine cannot be reached physically.
- **Name clusters after the machine, not the role.** The Lenovo's cluster is `extreme` (context, node, `clusters/extreme/`, `apps/extreme/`, `infrastructure/extreme/`); the machine is `ubuntu-extreme`. Roles swap (primary and standby already did), so a role in the name goes stale. The mini's cluster keeps the name `zion` until it is renamed `mini`, a separate step done safely: add the new folders next to the old ones with identical output, repoint Flux, check nothing is pruned, then delete the old folders. `zion` remains the name of the lab. This supersedes the "`zion-standby`" naming in ADR 0004, 0006 and 0007.
- **The Lenovo becomes primary again; the mini returns to standby.** Immich and Actual move back to the Lenovo; Plex and Jellyfin stay native on the mini (ADR 0008).
- **Library: full restore from the NAS** (not the old local copy). The NAS copy is copied to a host directory outside k3s's state (`/srv/immich`, static PV), in advance while the mini keeps serving; the cutover then needs only the delta and the database dump.
- **Public access: `cloudflared` on the host**, as on the mini, in a new tunnel named after the machine (`ubuntu-extreme`), pointing at NodePorts on localhost (30283 Immich, 30506 Actual). Running it in the cluster was a mistake. The `home-brain` tunnel and its DNS records are removed.
- **GPU**: device plugin and time-slicing in `infrastructure/`; pods and the plugin ask for `runtimeClassName: nvidia` instead of making it the default runtime; the plugin fails loudly (`FAIL_ON_INIT_ERROR=true`); NVIDIA packages are excluded from unattended upgrades.
- **k3s**: `v1.33.6+k3s1`, Traefik and ServiceLB disabled, root-only kubeconfig, same as the mini apart from that.
- **Flux** (same v2.9.6 components as the mini) reads the public repo over HTTPS with no deploy key; this differs from ADR 0005's SSH deploy key and needs no secret. The one manual secret is `sops-age` (ADR 0007). Immich's server and Actual stay at 0 replicas until their data is restored, so no empty instance offers first-run signup on the tailnet.
- **Dropped, data discarded:** `monitoring` and `web-scraper` on the old cluster (to be rebuilt from Git, mirrored on the mini), the old Postgres and Redis volumes, `home-brain`.

## Alternatives considered
- Reinstall Ubuntu: cleanest, but needs someone at the machine.
- Keep the old library and fetch only the delta from the NAS: fastest, but the old copy would then be trusted without being tested; the NAS copy has been restored once already.
- `cloudflared` as an in-cluster Deployment: reproducible from Git, but unlike the mini, and it ties public access to the cluster being healthy.
- Names by role (`zion`, `zion-standby`): need a rename at every swap, and renaming a live cluster's Flux path can prune it.

## Consequences
- Family photo uploads are paused during the Immich cutover (a few hours at most with the library pre-copied).
- After the wipe, the Lenovo's old library and databases are gone; the NAS and the mini's NVMe are the copies. Gate: the mini to NAS job has run once with a clean `rclone check`, the NAS has hourly snapshots, and `k3s-disaster-backup.sh` has been read.
- Two host-level `cloudflared` instances (mini, Lenovo) have to be managed outside Flux; their token files are never in Git.
- CLAUDE.md contexts change from `zion` and `zion-old` to `extreme`, `zion` (mini, until renamed) and `zion-old` (until the wipe).
- Open: the ingress/DNS/TLS, NAS storage and backup ADRs stay pending; monitoring comes back after the rebuild.

## Update 2026-10-21: outcome
- **Rebuild:** done 2026-10-17 as described. Actual runs on `extreme` since then.
- **Immich cutover back to the Lenovo:** done 2026-10-20 to 21 (library copied from the NAS ahead of time plus a delta, database restored from the mini's dump, `immich.kanokgan.com` moved to the `ubuntu-extreme` tunnel). Record and lessons: [docs/services/immich.md](../services/immich.md). The Lenovo was then upgraded to Immich v3.3.4, and its Postgres limits raised to 2 CPU and 3Gi.
- **Rename of the mini's cluster `zion` to `mini`:** done 2026-10-20 in the order this ADR describes (copy folders, repoint Flux, verify, delete the old folders). The Lima VM and the k3s node keep the name `zion` (ADR 0003).
- **Deviation from "the mini returns to standby":** the mini keeps running Immich and Actual at 1 replica on purpose, as frozen old copies at their Tailscale names, with no uploads and no backup job. It is not a working standby until a refresh procedure exists (ADR 0004).
- **Backup gate, as it ended up:** the mini to NAS job was never installed. The NAS copy used for the cutover was made by hand (FreeFileSync, then `rclone check`). The Lenovo's nightly NAS backup (systemd timer, 04:00, runs as root because the library is root-owned) has run clean since 2026-10-21, with a restricted NAS account.
- **`home-brain`:** the tunnel was deleted in Cloudflare on 2026-10-21.
- **Still open from this ADR:** delete stale Tailscale devices, and the pending ingress, NAS storage and backup ADRs.
