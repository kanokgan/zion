# Migration status

Rebuilding Zion Lab from the ad hoc setup into a Git-managed, reproducible one. Strategy ([ADR 0002](../decisions/0002-parallel-cluster-migration.md)): build new clusters only from this repo and migrate one service at a time. The legacy cluster `zion-old` (k3s on the Lenovo) was wiped on 2026-10-17 and the Lenovo rebuilt in place as `extreme` ([ADR 0009](../decisions/0009-rebuild-lenovo-in-place.md)). The Mac mini's cluster (called `zion` until 2026-10-20, now `mini`) carried production in between.

Never two instances writable against the same data. Clusters are named after the machine (`extreme`, `mini`), not the role.

Last updated: 2026-10-29

**Where things are:** the migration is done. Everything below runs on `extreme` from this repo, except Plex and Jellyfin (native on the mini, ADR 0008). The mini keeps old copies of Immich and Actual on purpose and is meant to become the Immich standby once a refresh procedure exists (ADR 0004). What is left is hardening, documentation and the open items at the bottom.

## Services

| Service | Runs on | Backup | Restore tested | Doc |
|---|---|---|---|---|
| Immich | `extreme` (cut over 2026-10-20 to 21); mini: old frozen copy | Nightly Lenovo to NAS `rclone` job (04:00, since 2026-10-21), plus Immich's own DB dump and hourly NAS snapshots | DB restore from a dump: 2026-10-11 (mini) and at the 2026-10-20 cutover (Lenovo). Library copied from the NAS to the Lenovo at the cutover. Not yet from the nightly job's output on the Lenovo | [immich.md](../services/immich.md) |
| Actual Budget | `extreme` (since 2026-10-17); mini: stale copy | Manual export to the NAS | Export and import onto the mini worked, 2026-10-12 | [actual.md](../services/actual.md) |
| SilverBullet | `extreme` (since 2026-10-25, `silverbullet.kanokgan.com`); mini: tailnet-only standby, starts empty | Nightly Lenovo to NAS job (04:30) | Not done; mini refresh procedure to be written | [silverbullet.md](../services/silverbullet.md) |
| Obsidian in the browser | `extreme` (`obsidian.kanokgan.com`, behind Cloudflare Access) | The vault is copied by Syncthing to the owner's other devices; no NAS job yet | Not done | [obsidian.md](../services/obsidian.md) |
| Syncthing | `extreme`, tailnet only; the Obsidian vault is joined and syncing | Config in `/srv/syncthing/config` is not backed up yet | Not done | [syncthing.md](../services/syncthing.md) |
| Monitoring | `extreme` (stages 1 and 2 live) | Prometheus data is disposable, Grafana is stateless (ADR 0010) | n/a | [monitoring.md](../services/monitoring.md) |
| Plex, Jellyfin | native on the mini (ADR 0008) | Unknown: how they start, where config lives and how it is backed up are still to be recorded in [hosts/macos-mini/](../../hosts/macos-mini/README.md) | No | not in Kubernetes |

Not a migration, but worth knowing: SilverBullet was found unsuitable (it needs plugins for basics) and is still running; whether to keep or remove it is decided after living with Obsidian for a while.

Found on `zion-old` and decided when it was wiped on 2026-10-17:
- `monitoring` (kube-prometheus, Grafana, Alertmanager) and `web-scraper` (data 50Gi): dropped, their data discarded. Monitoring was rebuilt from Git (ADR 0010); the web scraper has not been.
- `cloudflare`: the in-cluster `cloudflared` and the tunnel `home-brain` are replaced by `cloudflared` on the host of each machine (tunnels `macos-mini` and `ubuntu-extreme`). `home-brain` was deleted in the dashboard on 2026-10-21. The Lenovo's Jellyfin was not migrated (ADR 0008).

## Foundation decisions

| Decision | Status | ADR |
|---|---|---|
| Migration strategy | accepted, partly superseded by 0009 | 0002 |
| Kubernetes on macOS | accepted: Lima VM + k3s | 0003 |
| Mac mini as Immich standby | accepted, not operational yet | 0004 |
| GitOps tool | accepted: Flux | 0005 |
| Repo layout | accepted | 0006 |
| Secrets | accepted: SOPS + age | 0007 |
| Plex and Jellyfin | accepted: native on the mini | 0008 |
| Rebuild the Lenovo in place, clusters named after machines | accepted | 0009 |
| Monitoring | accepted | 0010 |
| Ingress / DNS pattern (Tailscale + kanokgan.com) | undecided (the pattern works today) | - |
| NAS storage pattern | undecided | - |
| Backup approach | undecided | - |
| FileVault on the mini (unattended boot vs disk encryption) | undecided | - |
| Read-only access for Lens and Claude | undecided | - |

## Done

- Bootstrap: repo and ADRs, guardrails (`.claude/`, pre-commit, secret scan), SOPS + age with end-to-end decryption through Flux (tested 2026-10-11, key in the password manager).
- `mini`: Lima VM and k3s, Flux with a read-only deploy key, k3s API on the tailnet for Lens (`macos-mini.dove-komodo.ts.net:6443`).
- `extreme`: rebuilt from this repo on 2026-10-17 (k3s, Flux, GPU device plugin, `cloudflared` on the host); Actual, then Immich (2026-10-20 to 21), SilverBullet (2026-10-25), then Obsidian and Syncthing; monitoring stage 1 (2026-10-17) and stage 2 (alert rules, Grafana on the tailnet, Telegram alerts).
- Rename of the mini's cluster `zion` to `mini` (2026-10-20, safe order in [ADR 0009](../decisions/0009-rebuild-lenovo-in-place.md)); the Lima VM and k3s node keep the name `zion`.
- Lenovo nightly NAS backup (2026-10-21, first `rclone check` clean over 556,496 files); NAS user `sc-zion` limited to `ZionLabs` and its home, old cronjob key removed (2026-10-21).
- Mini: Immich and Actual deliberately kept at 1 replica as old copies, Tailscale names only, no uploads, no backup job (decided 2026-10-21).
- External libraries mounted read-only into the Immich server on the Lenovo (2026-10-21); Postgres limits raised to 2 CPU and 3Gi.
- Immich upgraded to v3.3.4 on the Lenovo.
- `cloudflared` upgraded to 2026.10.5 on all three connectors and the NAS tunnel put behind Cloudflare Access (2026-10-28, [runbook](../runbooks/upgrading-cloudflared.md)).
- Docs sweep after the rename (2026-10-20 and 2026-10-21) and a full pass on 2026-10-29.

## Open

Platform and security:
- [ ] Read-only credentials for Lens and Claude Code on both clusters (a ServiceAccount with a read-only role, defined in Git, token created by hand). Lens currently uses the admin credential on the mini.
- [ ] Check the tailnet ACL: devices shared from another account must not reach the mini's port 6443.
- [ ] Tighten ufw on the Lenovo (`hosts/ubuntu-extreme/README.md`).
- [ ] Delete the stale Tailscale device entries, and confirm no DNS record still points at the deleted `home-brain` tunnel.
- [ ] Pending ADRs: ingress/DNS/TLS, NAS storage pattern, backups, FileVault, read-only access.
- [ ] Mini: VM start at boot (blocked by the FileVault decision).

Immich and the Lenovo:
- [ ] Clean up untracked files (Administration, Repair) and lower the database backup retention, after the cutover is verified.
- [ ] Storage: the Lenovo's disk was at about 82% on 2026-10-21. Plan: a second 2 TB NVMe and an online LVM extend; revisit around April 2027 or at 90% ([storage plan](../../hosts/ubuntu-extreme/README.md)). Moving originals to the NAS waits for a second copy of them and the NAS storage ADR.
- [ ] Make the library PV's declared size realistic (1Ti declared, 1.3 TB real).
- [ ] Mini standby refresh for Immich: upgrade the mini to the Lenovo's version, NAS to NVMe in the right direction, DB restore on a clean Postgres volume, then a tested failover and failback (ADR 0004).
- [ ] Test a restore of the library from the nightly job's NAS copy.

Notes stack:
- [ ] SilverBullet: restore test (on the mini, which doubles as its refresh procedure), then decide whether to keep it.
- [ ] Syncthing: back up `/srv/syncthing/config`. Obsidian vault: decide on a nightly NAS copy.

Monitoring ([ADR 0010](../decisions/0010-monitoring.md), [service doc](../services/monitoring.md)):
- [ ] Stage 3: Immich and backup-job metrics (the NAS jobs must write a last-success timestamp), dashboards in Git.
- [ ] Stage 4: the mini, the overview dashboard over both data sources, the dead-man's switch.
- [ ] Later: read-only Telegram bot, logs (Loki), file browsing, the web scraper.

Mac mini host:
- [ ] Plex and Jellyfin: confirm how they start, where their config and media live, and how they are backed up (`hosts/macos-mini/`).
