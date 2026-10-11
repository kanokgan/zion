# 0006. Repository layout

- Status: accepted
- Date: 2026-10-11

## Context
Two clusters will sync from this repo (`zion` now, `zion-standby` later, ADR 0004), running different subsets of the same applications. The Lima VM that hosts the mini's cluster is host-level config and is not applied by Flux.

## Decision
```
clusters/<cluster>/     Flux bootstrap files and the Kustomizations that say what this cluster runs
infrastructure/         cluster-wide components (storage, ingress, monitoring), shared and per-cluster overlays
apps/base/<app>/        one definition per application, shared by every cluster
apps/<cluster>/<app>/   per-cluster overlay (for example, the standby turns off Immich machine learning)
hosts/<machine>/        per-machine setup outside Kubernetes and Flux (macos-mini: Lima VM, native apps)
docs/                   ADRs, migration tracker, service docs
```
Rules:
- One namespace per app, named after the app.
- An application is defined once in `apps/base/`; clusters differ only through overlays.
- Cluster-specific values live in the overlay, never in `base/`.
- Machines are named `<os>-<nickname>`, lowercase (`macos-mini`, `windows-extreme`). The `hosts/` folder, the Tailscale device and the Cloudflare tunnel use the same name.

## Alternatives considered
- One directory per cluster with full copies of manifests: simple but the copies drift, which defeats a standby.
- Separate repos per cluster: duplicates the single source of truth.

## Consequences
- Adding a cluster means adding `clusters/<name>/` and overlays, not copying apps.
- The Lenovo's host setup, if it ever needs a file, gets a sibling named the same way: `hosts/<os>-<nickname>/`.
- CLAUDE.md "Repo layout" should point here.

Amended 2026-10-12: host-level setup moved from `infra/mini/` to `hosts/macos-mini/`. Next to `infrastructure/`, the name `infra/` did not say which one Flux applies, and the folder now follows the machine naming convention.
