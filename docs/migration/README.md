# Migration status

Rebuilding Zion Lab from the ad hoc setup into a Git-managed, reproducible one. Strategy ([ADR 0002](../decisions/0002-parallel-cluster-migration.md)): build new clusters only from this repo and migrate one service at a time. The legacy cluster `zion-old` (k3s on the Lenovo) was wiped on 2026-10-17 and the Lenovo rebuilt in place as `extreme` ([ADR 0009](../decisions/0009-rebuild-lenovo-in-place.md)); the Mac mini's cluster `zion` carried production in between.

Never two instances writable against the same data. Clusters are named after the machine (`extreme`, `mini`), not the role.

The Mac mini's long-term role is a warm standby for Immich ([ADR 0004](../decisions/0004-mini-as-immich-standby.md)); Immich returns to the Lenovo at its cutover.

Last updated: 2026-10-17

## Phase 0: Bootstrap

- [x] Repo + ADR scaffolding
- [x] Synced to claude.ai
- [x] Guardrails committed (`.claude/settings.json`, `.claude/hooks/guard-bash.sh`, `.gitignore`)
- [x] `zion-old` (the cluster this item was for) was wiped on 2026-10-17
- [ ] Read-only credentials for Lens and Claude Code on `extreme` and `mini` (a ServiceAccount with a read-only role, defined in Git, token created by hand)

## Phase 1: Platform on `mini` (Mac mini, formerly `zion`)

- [x] Lima VM + k3s v1.33.6+k3s1 running (`hosts/macos-mini/lima/zion.yaml`, ADR 0003); kubeconfig context `mini`
- [x] Flux bootstrapped, syncing `clusters/mini/` with a read-only deploy key (ADR 0005)
- [x] Tailscale access to `mini`: API published on the tailnet at `macos-mini.dove-komodo.ts.net:6443` (`tailscale serve`, tailnet only); Lens connects with a separate kubeconfig (`tls-server-name: localhost`); Immich on the mini at `https://immich-macos-mini.dove-komodo.ts.net` via a Tailscale sidecar
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
| Actual Budget | yes (10Gi PVC `actual-data`, mounted at `/data`) | no: manual export only | export/import into the mini worked, 2026-10-12 (not a restore of an automated backup) | yes (`apps/base/actual`, `apps/mini/actual`) | yes (26.10.0, Tailscale sidecar, no secrets besides the auth key) | yes (`https://actual-macos-mini.dove-komodo.ts.net`) | yes, 2026-10-17 (first to the mini, then back to the rebuilt Lenovo, cluster `extreme`; `actual.kanokgan.com` via tunnel `ubuntu-extreme`) | skipped by choice | yes, on `extreme`; the mini's copy is to be stopped |
| Immich | yes (library 1Ti, Postgres 20Gi) | yes: Immich's nightly DB dump, plus the Lenovo to NAS nightly rclone job (04:00, since 2026-10-21; restore of the library from the NAS not tested from the Lenovo yet) | yes, 2026-10-11 (standby on mini, port-forward only; restored from the Oct 11 dump, recent photos verified) | yes (`apps/base/immich`, `apps/mini/immich`) | yes (see ADR 0004) | yes | yes, 2026-10-17 to the mini, then back to the Lenovo 2026-10-20 to 21 (restored from the mini's dump; `immich.kanokgan.com` via tunnel `ubuntu-extreme`) | skipped by choice | yes, on `extreme`; the mini keeps an old copy running on purpose |

Found on `zion-old`, and decided when it was wiped on 2026-10-17:
- `monitoring` (kube-prometheus, Grafana, Alertmanager) and `web-scraper` (data 50Gi): dropped, their data discarded. To be rebuilt from Git, properly, and mirrored on the mini.
- `cloudflare`: the in-cluster `cloudflared` and the tunnel `home-brain` are replaced by `cloudflared` on the host of each machine (tunnels `macos-mini` and `ubuntu-extreme`). The `home-brain` tunnel and its leftover DNS records are still to be deleted in the dashboard. The Lenovo's Jellyfin was not migrated (ADR 0008).

"unknown" means the live cluster hasn't been fully inspected yet.

## Phase 3: Finish the move to `extreme` (after the Immich cutover)

`zion-old` was wiped on 2026-10-17 and rebuilt from this repo as the cluster `extreme` on the host `ubuntu-extreme` (ADR 0009). Actual already runs there. What is left, in order:

- [x] Immich cutover to the Lenovo, following the runbook in [docs/services/immich.md](../services/immich.md): database restored 2026-10-20, `immich.kanokgan.com` on the `ubuntu-extreme` tunnel by 2026-10-21; Lenovo upgraded to v3.3.4
- [x] The Lenovo's nightly backup timer enabled (2026-10-21, first `rclone check` clean: 0 differences over 556,496 files); the mini's job was never installed (`hosts/ubuntu-extreme/backup/`)
- [x] NAS user `sc-zion` limited to `ZionLabs` and its home, out of the `administrators` group (2026-10-21)
- [x] NAS user `sc-zion`: the old `immich-library-sync-cronjob` key (left over from the wiped cluster) removed from its `authorized_keys` (2026-10-21)
- [x] Mini: Immich and Actual are deliberately kept running at 1 replica (decided 2026-10-21): old copies, Tailscale names only, no uploads or data entry there; no backup job runs on the mini. The sidecars are named `actual-macos-mini` and `immich-macos-mini`. Still to define: the mini's standby refresh for Immich
- [x] Immich on `extreme`: Postgres limits raised to 2 CPU and 3Gi (`apps/extreme/immich/kustomization.yaml`, 2026-10-21)
- [ ] Immich on `extreme`: clean up untracked files (Administration, Repair) and lower the database backup retention, after the cutover is verified
- [ ] Cloudflare: delete the tunnel `home-brain` and its leftover DNS records. Tailscale: delete the stale device entries
- [x] **Rename the mini's cluster `zion` to `mini`** (cluster name = machine nickname, ADR 0009), in the order below. Done 2026-10-20: folders, Flux sync path and kubectl context; the Lima VM and k3s node keep the name `zion`
- [x] Docs sweep after the rename: done 2026-10-20 for CLAUDE.md, README, `docs/services/*` and the host README; on 2026-10-21 "Update" sections were added to ADRs 0002 to 0007, 0009 and 0010 to match the current state
- [ ] Later, each its own change: external libraries on the Lenovo (Flux `postBuild.substituteFrom` from a SOPS secret, because their paths hold real names), tighten ufw, make the library PV's declared size realistic (1Ti declared, 1.3 TB real), a read-only Lens credential for both clusters, monitoring and the web-scraper rebuilt in Git (mirrored on the mini), Immich upgrade to v3.3.x after reading the release notes, and the mini's standby refresh procedure (NAS to its NVMe, then the DB restore)

### Renaming the mini's cluster (`zion` to `mini`), safe order

Done after the cutover, with the mini idle, because the cutover edits `apps/zion/…`. A plain `git mv` is not safe: the mini's Flux has `./clusters/zion` in its own sync object, which lives in the folder that would move. Flux would stop syncing (the path is missing) and could not repair itself without a manual step.

1. Copy `clusters/zion` to `clusters/mini` and `apps/zion` to `apps/mini`, keeping the old folders. In the copy change only: `path: ./apps/mini` in `clusters/mini/apps.yaml`, `path: ./clusters/mini` in `clusters/mini/flux-system/gotk-sync.yaml`, and the `zion-apps` style labels. Push. The mini still reads the old path, so nothing changes yet.
2. On the mini, once: apply `clusters/mini/flux-system/gotk-sync.yaml` (the one imperative step). The `apps` Kustomization has the same name and renders identical content, so nothing is pruned.
3. Verify: all Kustomizations Ready, the same pods with no new restarts.
4. Delete `clusters/zion` and `apps/zion`; push; verify again.
5. Rename the kubectl context (`kubectl config rename-context zion mini`) everywhere it exists, including the Lens kubeconfig.

Do not rename the Lima VM or the k3s node (both are called `zion`): local-path volumes are tied to the node name. Leave them and note it in `hosts/macos-mini/`.

## Monitoring ([ADR 0010](../decisions/0010-monitoring.md), [service doc](../services/monitoring.md))

One Prometheus per cluster, one Grafana on the Lenovo with a data source for each; alerts to Telegram.

- [ ] Stage 1: stack on the Lenovo (applied 2026-10-17, HelmRelease Ready, all pods Running; dashboards and Prometheus targets still to be checked)
- [ ] Stage 2: part A applied (alert rules, Flux scraping, Grafana sidecar objects, secret templates); part B written (HelmRelease wired to the three encrypted secrets: Grafana admin, Tailscale key, Alertmanager/Telegram), live once pushed together with them
- [ ] Stage 3: Immich and backup-job metrics, dashboards in Git
- [ ] Stage 4: the mini (after the Immich cutover), overview dashboard, dead-man's switch
- [ ] Later: read-only Telegram bot, logs (Loki), file browsing

## Next steps
1. Immich: finish the library copy to the Lenovo (tmux session `copy`, about 36 hours because the Lenovo's wired link negotiates 100 Mb/s), then the cutover runbook.
2. Before that cutover: the mini's own nightly NAS backup job, the Lenovo's backup job dry run, and the fresh Actual export are the open prerequisites.
3. Then Phase 3 above, in order.
4. Plex and Jellyfin on the mini: confirm how they start, where their config and media live, and how they are backed up (`hosts/macos-mini/`).
5. Remaining platform ADRs: ingress/DNS/TLS, NAS storage pattern, backups, FileVault (the mini cannot restart unattended with FileVault on, and it serves Immich until the cutover).
