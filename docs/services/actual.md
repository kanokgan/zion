# Actual Budget

Personal budgeting app used daily by family. Since 2026-10-17 production runs on the rebuilt Lenovo (cluster `extreme`, host `ubuntu-extreme`, ADR 0009) at `actual.kanokgan.com`. It ran on the Mac mini for the hours in between; the mini's copy is stale and, by the owner's choice (2026-10-21), is kept running at 1 replica at its tailnet name only. For debugging one specific instance there are tailnet-only names of the form `actual-<machine>.dove-komodo.ts.net`.

## What runs where

| | Lenovo (`extreme`, production) | Mac mini (`mini`, previous production, stale copy kept running) |
|---|---|---|
| Image | `actualbudget/actual-server:26.10.0` | `actualbudget/actual-server:26.10.0` |
| Data | 10Gi `local-path` PVC `actual-data`, mounted at `/data` | 10Gi `local-path` PVC `actual-data` on the Lima VM disk |
| Tailscale (debug, tailnet only) | sidecar `actual-ubuntu-extreme`: `https://actual-ubuntu-extreme.dove-komodo.ts.net` | sidecar `actual-macos-mini` (renamed from `actual-standby` on 2026-10-18) |
| Public | `actual.kanokgan.com` via tunnel `ubuntu-extreme` (`cloudflared` on the host), service `http://localhost:30506` -> NodePort Service `actual-nodeport` (`apps/extreme/actual/nodeport.yaml`) | none: the route moved to the Lenovo's tunnel |
| Config | env `ACTUAL_SERVER_FILES=/data`, `ACTUAL_PORT=5006`; no secrets other than the Tailscale auth key | same |

The two servers are separate and do not share storage (SQLite over a network share is risky). Manifests: `apps/base/actual/`, `apps/extreme/actual/` and `apps/mini/actual/`. Each overlay has its own `tailscale-auth.sops.yaml`. A Tailscale auth key only has to be valid when the sidecar first joins: afterwards the node's identity lives in the `actual-tailscale-state` Secret, so an expired key does not hurt a running pod. (On 2026-10-17 the Lenovo's copy of the mini's key was no longer valid and the sidecar crash-looped until a new key was encrypted; a sidecar that fails to join keeps the pod unready, so nothing is routed to it.)

## Data and backup

Everything lives in `/data` (server files, user files and the account database).

Backup approach: manual. The owner exports the budget from the Actual UI (Settings, Export data) and saves the zip on the NAS at `/ZionLabs/Actual/Backup`. Actual has no built-in scheduled backup for the self-hosted server (its docs describe only manual export and the desktop app's Backup Now), so a daily backup would have to be an external job.

What an export does not contain: the server's logins and budget file IDs. After a total loss, importing the export rebuilds the budget, but devices have to re-download it.

Optional later: a CronJob that copies `/data` to the NAS over SFTP on the LAN (needs an SFTP key as a SOPS secret and the NAS's LAN address).

## Restore test (done 2026-10-12, on the mini with disposable data)

1. In the Lenovo's Actual: Settings, Export data. Keep the zip safe (it contains the budget).
2. On `https://actual-macos-mini.dove-komodo.ts.net`: set a server password on first open, then import the budget from the zip.
3. Check accounts, recent transactions and the balances against the Lenovo.
4. Result: export from the Lenovo and import on the mini worked. This tested the manual export path, not an automated backup.

Note: importing creates a new budget file ID on the new server. Devices that already hold a copy have to re-download. For the real cutover, copying the `/data` folder from the Lenovo keeps the same IDs and logins.

## Runbook: upgrade Actual

Actual migrates its data files when a newer version starts, and an older version may refuse to open migrated data. Rolling back means restoring a backup, not just reverting the tag.

**Where the version lives:** only in the `images:` block of the cluster's overlay: `apps/extreme/actual/kustomization.yaml` (production) and `apps/mini/actual/kustomization.yaml` (the stale copy). The base manifest has no tag.

Before:
1. Read the release notes for breaking changes (`https://actualbudget.org/docs/releases`).
2. Export the budget (Settings, Export data) and keep the zip on the NAS at `/ZionLabs/Actual/Backup`.
3. Confirm the tag exists on Docker Hub (`actualbudget/actual-server`).

Upgrade:
1. Edit `newTag` in `apps/extreme/actual/kustomization.yaml`. Leave the mini alone unless you are deliberately testing the new version there first.
2. Check the render: `kustomize build apps/extreme | grep 'image: actualbudget'`.
3. Commit (`actual: upgrade to X.Y.Z`) and push. Flux applies it within its interval.

Verify:
```sh
kubectl --context extreme rollout status deploy/actual -n actual
kubectl --context extreme logs deploy/actual -n actual --tail=50
flux get kustomization apps --context extreme   # READY True
```
Then open `https://actual.kanokgan.com` and check accounts and recent transactions.

Rollback: revert the commit if the pod never became healthy. If data was migrated, restore the exported zip into the old version on a fresh volume.

## Cutovers (2026-10-17)

1. **Lenovo (old cluster) to the mini:** final export from the Lenovo, its Actual scaled to 0, export imported on the mini (new budget file ID, devices re-downloaded), route moved from `home-brain` to `macos-mini`. A budget export zip was also saved to the NAS.
2. **Mini to the rebuilt Lenovo (`extreme`):** the Lenovo's cluster was rebuilt from this repo (ADR 0009); Actual runs there with the Tailscale sidecar and `cloudflared` as described above, and `actual.kanokgan.com` points at the tunnel `ubuntu-extreme`. Both the public address and the debug address were checked working. Order of problems met on the way: the hostname was moved before `cloudflared` existed on the Lenovo (Cloudflare error 1033: the tunnel had no connector), and the sidecar's auth key was invalid (pod `1/2`, no traffic).

## Open items

- The mini's Actual is kept at 1 replica on purpose (decided 2026-10-21): it is a stale copy with its own data, so it does not conflict with the Lenovo's, but anything entered there is not synchronised and will be lost. Enter data only at `actual.kanokgan.com`. Scale it to 0 in `apps/mini/actual/kustomization.yaml` if it ever causes confusion.
- Backup is a manual export to the NAS. Automating it with a CronJob or a host job is optional (backup ADR).
