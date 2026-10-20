# 0005. GitOps with Flux

- Status: accepted
- Date: 2026-10-11

## Context
The repo is the source of truth (CLAUDE.md). Clusters must be rebuildable from the repo plus backups, and nothing may be applied by hand. The `zion` cluster runs on a Mac mini inside a Lima VM with 5 GiB of RAM (ADR 0003) and also has to carry the Immich standby (ADR 0004), so controller footprint matters. Secrets will be encrypted in Git (separate ADR).

## Decision
Use Flux v2. Each cluster runs its own Flux in the `flux-system` namespace and pulls from `git@github.com:kanokgan/zion.git`, branch `main`, at its own path (`clusters/<cluster>/`). Flux manages its own manifests from that path, so Git is the only source of truth after the one-time `flux bootstrap`.

## Alternatives considered
- Argo CD: has a UI and is widely used, but is heavier on a small VM, and SOPS decryption needs a plugin. Revisit if a UI becomes important.
- Pushing manifests from CI or a laptop (`kubectl apply`): not pull-based, and drifts without anyone noticing.

## Consequences
- The only imperative step per cluster is `flux bootstrap`. It needs a GitHub credential that is not stored in the repo.
- Flux's SOPS integration is built in, which fits SOPS + age for secrets.
- Controllers cost a few hundred MiB of RAM per cluster.
- Changing the cluster means committing and pushing. This includes failover for the standby (ADR 0004), so push access from somewhere other than the Lenovo must be available during an outage.
- No UI; use `flux get` and `kubectl` to inspect state.

## Update 2026-10-21
Two clusters now sync from this repo: `extreme` (the Lenovo, reads the public repo over HTTPS, ADR 0009) and `mini` (the Mac mini, SSH deploy key as described above). The mini's Flux was repointed from `clusters/zion` to `clusters/mini` on 2026-10-20 with one `kubectl apply` of `clusters/mini/flux-system/gotk-sync.yaml`, after copying the folders with identical output; nothing was pruned. The `flux` CLI is not installed on the Lenovo, so a sync is forced by annotating the `GitRepository` and `Kustomization` with `reconcile.fluxcd.io/requestedAt`; otherwise Flux syncs on its interval.
