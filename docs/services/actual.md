# Actual Budget

Personal budgeting app used daily by family (family via `actual.kanokgan.com`, owner via `actual.dove-komodo.ts.net`). Production runs on the Mac mini (`zion`) since 2026-10-17 (`actual.kanokgan.com` via the `macos-mini` tunnel). The Lenovo's copy (`zion-old`) is scaled to 0 and will be wiped.

## What runs where

| | Lenovo (`zion-old`, production) | Mac mini (`zion`, test endpoint) |
|---|---|---|
| Image | `actualbudget/actual-server:latest` (currently 26.10.0, verified by digest 2026-10-12) | `actualbudget/actual-server:26.10.0` |
| Data | 10Gi `local-path` PVC `actual-data`, mounted at `/data` | 10Gi `local-path` PVC `actual-data` on the Lima VM disk |
| Tailscale | sidecar, hostname `actual` | sidecar, hostname `actual-standby` (`https://actual-standby.dove-komodo.ts.net`) |
| Public | route removed on 2026-10-17 | `actual.kanokgan.com` via tunnel `macos-mini`, service `http://localhost:30506` -> Lima port forward -> NodePort Service `actual-nodeport` (`apps/zion/actual/nodeport.yaml`) |
| Config | env `ACTUAL_SERVER_FILES=/data`, `ACTUAL_PORT=5006`; no secrets other than the Tailscale auth key | same |

The two servers are separate and do not share storage (a shared NAS volume was considered and dropped: SQLite over a network share is risky, and mounting the NAS into the VM is not worth it for a short period). Manifests: `apps/base/actual/` and `apps/zion/actual/`. The Tailscale auth key is in `apps/zion/actual/tailscale-auth.sops.yaml`.

## Data and backup

Everything lives in `/data` (server files, user files and the account database).

Backup approach: manual. The owner exports the budget from the Actual UI (Settings, Export data) and saves the zip on the NAS at `/ZionLabs/Actual/Backup`. Actual has no built-in scheduled backup for the self-hosted server (its docs describe only manual export and the desktop app's Backup Now), so a daily backup would have to be an external job.

What an export does not contain: the server's logins and budget file IDs. After a total loss, importing the export rebuilds the budget, but devices have to re-download it.

Optional later: a CronJob that copies `/data` to the NAS over SFTP on the LAN (needs an SFTP key as a SOPS secret and the NAS's LAN address).

## Restore test (on the mini, with disposable data)

1. In the Lenovo's Actual: Settings, Export data. Keep the zip safe (it contains the budget).
2. On `https://actual-standby.dove-komodo.ts.net`: set a server password on first open, then import the budget from the zip.
3. Check accounts, recent transactions and the balances against the Lenovo.
4. Result: export from the Lenovo and import on the mini worked (2026-10-12).

Note: importing creates a new budget file ID on the new server. Devices that already hold a copy have to re-download. For the real cutover, copying the `/data` folder from the Lenovo keeps the same IDs and logins.

## Runbook: upgrade Actual

Actual migrates its data files when a newer version starts, and an older version may refuse to open migrated data. Rolling back means restoring a backup, not just reverting the tag.

**Where the version lives:** only in the `images:` block of `apps/zion/actual/kustomization.yaml`. The base manifest has no tag.

Before:
1. Read the release notes for breaking changes (`https://actualbudget.org/docs/releases`).
2. Export the budget (Settings, Export data) and keep the zip on the NAS at `/ZionLabs/Actual/Backup`.
3. Confirm the tag exists on Docker Hub (`actualbudget/actual-server`).
4. Until cutover, keep the mini on the same version as the Lenovo unless you are deliberately testing the new one there first.

Upgrade:
1. Edit `newTag` in `apps/zion/actual/kustomization.yaml`.
2. Check the render: `kustomize build apps/zion | grep 'image: actualbudget'`.
3. Commit (`actual: upgrade to X.Y.Z`), push, then `flux reconcile kustomization apps --with-source --context zion`.

Verify:
```sh
kubectl --context zion rollout status deploy/actual -n actual
kubectl --context zion logs deploy/actual -n actual --tail=50
flux get kustomization apps --context zion   # READY True
```
Then open the app and check accounts and recent transactions.

Rollback: revert the commit if the pod never became healthy. If data was migrated, restore the exported zip into the old version on a fresh volume.

## Cutover (done 2026-10-17)

Final export from the Lenovo, its Actual scaled to 0, export imported on the mini (new budget file ID, devices re-downloaded), route moved from `home-brain` to `macos-mini`. A budget export zip was also saved to the NAS. Original outline: scale the Lenovo's Actual to 0, copy its `/data` into the mini's volume (or import the final export), verify on `actual-standby`, repoint `actual.kanokgan.com` and the Tailscale name, keep the old data about 2 weeks, then remove it from the Lenovo.

## Open items

- Cutover is run by the owner; method (folder copy vs export/import) still to be chosen and tested on the test endpoint.
- Backup is manual export to the NAS. Automating it with a CronJob is optional (backup ADR).
- Cloudflare tunnel backend for `actual.kanokgan.com` at cutover: `http://actual.actual.svc.cluster.local:5006` matches the Service on both clusters; confirm in the dashboard.
- Memory: check `free -m` in the VM with Immich and Actual both running.
