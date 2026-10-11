# Migration status

Rebuilding Zion Lab from the ad hoc setup into a Git-managed, reproducible one. Strategy ([ADR 0002](../decisions/0002-parallel-cluster-migration.md)): build a new cluster `zion` only from this repo, in parallel with the legacy cluster `zion-old` (node `k3s-master`, k3s v1.33.6+k3s1), and migrate one service at a time.

`zion-old` keeps serving production (including the public domain) until each service is cut over. `zion` uses Tailscale test endpoints with disposable data copies until then. Never two instances writable against the same data.

The Mac mini's long-term role is a warm standby for Immich ([ADR 0004](../decisions/0004-mini-as-immich-standby.md)). Once the Lenovo is rebuilt from this repo it becomes `zion` and the mini's cluster is renamed `zion-standby`.

Last updated: 2026-10-12

## Phase 0: Bootstrap

- [x] Repo + ADR scaffolding
- [x] Synced to claude.ai
- [x] Guardrails committed (`.claude/settings.json`, `.claude/hooks/guard-bash.sh`, `.gitignore`)
- [ ] Read-only kubeconfig for Claude Code on `zion-old` (note: creates a ServiceAccount outside Git)

## Phase 1: Platform on `zion` (Mac mini)

- [x] Lima VM + k3s v1.33.6+k3s1 running (`hosts/macos-mini/lima/zion.yaml`, ADR 0003); kubeconfig context `zion`
- [x] Flux bootstrapped, syncing `clusters/zion/` with a read-only deploy key (ADR 0005)
- [x] Tailscale access to `zion`: API published on the tailnet at `macos-mini.dove-komodo.ts.net:6443` (`tailscale serve`, tailnet only); Lens connects with a separate kubeconfig (`tls-server-name: localhost`); Immich standby at `https://immich-standby.dove-komodo.ts.net` via a Tailscale sidecar
- [ ] Read-only kubeconfig for Lens (it currently uses the admin credential)
- [ ] Check the tailnet ACL: devices shared from another account must not reach the mini's port 6443
- [ ] VM start at boot (blocked by the FileVault decision)
- [x] Secrets: SOPS + age (ADR 0007); end-to-end decryption through Flux tested 2026-10-11; private key backed up in the password manager
- [ ] Ingress / DNS / TLS, NAS storage, backups (ADRs)

## Foundation decisions (each needs an ADR)

| Decision | Status | ADR |
|---|---|---|
| Migration strategy | accepted | 0002 |
| Host for zion | Mac mini M2 now; Lenovo rebuilt later (mini becomes standby) | 0002, 0004 |
| Kubernetes on macOS | accepted: Lima VM + k3s | 0003 |
| Mac mini as Immich standby | accepted | 0004 |
| Plex and Jellyfin | accepted: run natively on the mini, outside Kubernetes | 0008 |
| GitOps tool | accepted: Flux | 0005 |
| Repo layout | accepted | 0006 |
| Secrets | accepted: SOPS + age | 0007 |
| Ingress / DNS pattern (Tailscale + kanokgan.com) | undecided | - |
| NAS storage pattern | undecided | - |
| Backup approach | undecided | - |
| FileVault on the mini (unattended boot vs disk encryption) | undecided | - |

## Services

Migration order (ADR 0002): Jellyfin, Plex, Actual Budget, Immich. The Immich standby on the mini (ADR 0004) is a separate track and does not follow this order.

| Service | Stateful data | Backup exists | Restore tested | In repo | Inventoried | On zion (test) | Cut over | Soak done | Migrated |
|---|---|---|---|---|---|---|---|---|---|
| Jellyfin | yes (config/metadata) | unknown | no | no (native on the mini, ADR 0008; documented in `hosts/macos-mini/`) | the mini's native install; the Lenovo's Jellyfin is dropped, not migrated | n/a (native) | no | no | no |
| Plex | yes (config 20Gi, transcode 100Gi on the Lenovo) | unknown | no | no (native on the mini, ADR 0008; documented in `hosts/macos-mini/`) | partly (installed as an app on the mini; Lenovo PVCs seen) | n/a (native) | no | no | no |
| Actual Budget | yes (10Gi PVC `actual-data`, mounted at `/data`) | no: manual export only | export/import into the mini worked, 2026-10-12 (not a restore of an automated backup) | yes (`apps/base/actual`, `apps/zion/actual`) | yes (26.10.0, Tailscale sidecar, no secrets besides the auth key) | yes (`https://actual-standby.dove-komodo.ts.net`, disposable data) | no | no | no |
| Immich | yes (library 1Ti, Postgres 20Gi) | yes: nightly Immich DB dump + nightly rclone copy to NAS; copy on mini's external drive (refreshed from the NAS with FreeFileSync) | yes, 2026-10-11 (standby on mini, port-forward only; restored from the Oct 11 dump, recent photos verified) | yes (`apps/base/immich`, `apps/zion/immich`) | yes (see ADR 0004) | yes (standby, server at 1 replica, read-mostly at `https://immich-standby.dove-komodo.ts.net`) | no | no | no |

Found on `zion-old` and not in the migration plan yet; each needs a decision (migrate, replace, or drop):
- `monitoring`: kube-prometheus, Grafana, Alertmanager (PVCs)
- `web-scraper`: scraper data 50Gi, Tailscale sidecar state
- `cloudflare`: `cloudflared` DaemonSet, token-based tunnel `home-brain` (routes live in the Cloudflare dashboard, not in Git; the `cloudflared-config` ConfigMap is stale). Not migrated: it keeps serving Immich and Actual until their cutover, and is rebuilt from the repo when the Lenovo is wiped. The Lenovo's Jellyfin is not migrated either (ADR 0008).

"unknown" means the live cluster hasn't been fully inspected yet.

## Phase 3: Decommission `zion-old`

Only after every service has cut over and finished its soak.

- [ ] All services: soak done, data kept until here
- [ ] Final backups of everything on `zion-old` verified restorable
- [ ] Public domain and Tailscale hostnames confirmed pointing at `zion`
- [ ] Old NAS paths / PVC data archived or deleted (explicit decision)
- [ ] `zion-old` shut down, then wiped or repurposed; rebuild the Lenovo as `zion` from this repo and rename the mini's cluster to `zion-standby`
- [ ] Rebuilt Lenovo follows the machine naming convention: `ubuntu-extreme` (today `k3s-master`) for the hostname, Tailscale device, Cloudflare tunnel (replaces `home-brain`) and `hosts/ubuntu-extreme/`

## Next steps
1. Immich standby on the mini: manifests are in the repo, the restore test passed (2026-10-11), and the server runs at 1 replica on `immich-standby`. Remaining: public failover path (NodePort Service + Lima port forward for the mini's `macos-mini` tunnel, see ADR 0004), failback decision.
2. Actual Budget: choose the cutover method (folder copy vs export/import), test it on `actual-standby`, then cut over.
3. Plex and Jellyfin on the mini: confirm how they start, where their config and media live, and how they are backed up (`hosts/macos-mini/`).
4. Read-only kubeconfig for `zion-old`, then decide on monitoring and web-scraper (migrate, replace, or drop).
5. Remaining platform ADRs: ingress/DNS/TLS, NAS storage pattern, backups, FileVault.
