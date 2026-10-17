# CLAUDE.md: Zion Lab project instructions

This file provides guidance to Claude (Claude Code and claude.ai) when working with this repository and the Zion Lab project.

## Purpose
Zion Lab is my homelab. It has two equal goals:
1. **Learning**: my primary way to learn Kubernetes, infrastructure, networking, and backend operations properly.
2. **Production for me**: real self-hosted services I rely on every day. Data loss or long downtime matters.

I'm a software engineer, so skip basic programming explanations. Do teach infra, Kubernetes, networking, and ops concepts properly.

## Current state (as of project start)
- Cluster: k3s on Lenovo X1 Extreme2 with ubuntu server
- Services: Immich, Actual Budget, Plex, Jellyfin (all working)
- Access: Tailscale network; personal domain kanokgan.com (via cloudflare)
- Storage: Synology NAS. DS923+
- Problem: the setup grew ad hoc from AI-generated commands. There's no single source of truth, no consistent conventions, and it's not well documented. The goal is to rebuild it into a clean, well-organized, reproducible setup **without losing data or breaking working services**.

## Environment
- **`extreme`**: the cluster on the Lenovo X1 Extreme2 (host `ubuntu-extreme`), rebuilt ONLY from this repo on 2026-10-17 with the OS kept ([ADR 0009](docs/decisions/0009-rebuild-lenovo-in-place.md)). It replaced the legacy cluster `zion-old`, which was wiped. Actual Budget runs here; Immich moves here at its cutover (runbook in [docs/services/immich.md](docs/services/immich.md)).
- **`zion`**: the cluster on a Mac mini M2 (ARM64), built ONLY from this repo: k3s in a Lima VM ([ADR 0003](docs/decisions/0003-kubernetes-on-macos.md)). It serves Immich until that cutover, then becomes the warm standby ([ADR 0004](docs/decisions/0004-mini-as-immich-standby.md)). It is to be renamed `mini` after the cutover. Clusters are named after the machine, not the role, because roles swap.
- Plex and Jellyfin run natively on the mini, outside Kubernetes ([ADR 0008](docs/decisions/0008-native-media-servers-on-mini.md)); host-level setup is in [hosts/macos-mini/](hosts/macos-mini/README.md).
- Never two instances writable against the same data: a service's old instance is scaled to 0 before the new one takes over, and only one machine writes to a given NAS path.
- NAS: Synology DS923+. Network: Tailscale; domain kanokgan.com via Cloudflare.
- Strategy and rationale: [ADR 0002](docs/decisions/0002-parallel-cluster-migration.md). Progress tracker: [docs/migration/README.md](docs/migration/README.md).

## Target principles
- **Everything in Git.** The repo is the source of truth. If it isn't in the repo, it doesn't exist. No `kubectl apply` of ad-hoc YAML that never gets committed.
- **Declarative and reproducible.** I should be able to rebuild the cluster from the repo plus backups.
- **GitOps.** The cluster syncs from the repo with Flux ([ADR 0005](docs/decisions/0005-gitops-with-flux.md)).
- **Secrets never in plain text in Git.** SOPS + age, files named `*.sops.yaml` ([ADR 0007](docs/decisions/0007-secrets-with-sops-age.md)).
- **Backups are part of the design.** Every stateful app has a documented backup and a tested restore path.
- **Boring and consistent over clever.** One way of doing things, applied everywhere.
- **Right-sized for a homelab.** Don't propose enterprise complexity unless it teaches something I asked to learn or solves a real problem.

## Conventions (refine these as we decide)
- Repo layout: `clusters/<cluster>/` (what Flux syncs), `apps/base/<app>/` (one definition per app), `apps/<cluster>/<app>/` (per-cluster overlays), `infrastructure/` (cluster-wide components), `hosts/<machine>/` (per-machine setup, outside Flux). See [ADR 0006](docs/decisions/0006-repo-layout.md).
- Machine names: `<os>-<nickname>`, lowercase, e.g. `macos-mini`, `macos-m5`, `ubuntu-extreme`. The same name is used for the `hosts/` folder, the Tailscale device, and the Cloudflare tunnel.
- Cluster names: the machine's nickname, not its role (`extreme`, `mini`), because roles swap ([ADR 0009](docs/decisions/0009-rebuild-lenovo-in-place.md)). The mini's cluster is still called `zion` until it is renamed.
- Tailscale names of pods (sidecars, tailnet-only, for debugging one specific instance): `<app>-<machine>`, e.g. `immich-ubuntu-extreme`. The production name of a service is its `kanokgan.com` hostname, served by whichever machine is primary.
- Public access: `cloudflared` runs on the host of each machine, in a tunnel named after the machine, and reaches apps on NodePorts on localhost (Immich 30283, Actual 30506). Hostnames are moved between tunnels in the Cloudflare dashboard at a cutover; one hostname belongs to one tunnel.
- One writer per data path: a NAS folder is written by one machine at a time, and a service's old instance is scaled to 0 before the new one starts.
- One namespace per app (or per logical group); consistent labels and naming
- Labels on every resource: `app.kubernetes.io/name`, `app.kubernetes.io/instance`, and `app.kubernetes.io/part-of: zion-lab`
- Pin image versions; no `latest`, and no floating tags like `v3` (a restart can pull a newer release). Images in `apps/base/` must be multi-arch (arm64 + amd64). An image used only in one cluster's overlay needs only that architecture, for example the CUDA machine-learning image and the NVIDIA device plugin on the Lenovo (amd64). One deliberate exception to "no `latest`": the Tailscale sidecar (`tailscale/tailscale:latest`) in Immich and Actual, see [docs/services/immich.md](docs/services/immich.md).
- Set resource requests/limits for every workload
- Ingress/DNS/TLS: the pattern above works today; the ADR that formalises it is still pending
- Record significant decisions as short ADRs (`docs/decisions/NNNN-title.md`): context, decision, alternatives, consequences
- Commit messages: `<scope>: <summary>`, one logical change per commit
- Pending ADRs: ingress/DNS/TLS, NAS storage pattern, backups, FileVault on the mini (unattended boot vs disk encryption), read-only access for Lens and Claude. Monitoring is decided: [ADR 0010](docs/decisions/0010-monitoring.md)

## How to work with me
- **Ask what mode I'm in if it's unclear:**
  - *Learn mode*: explain the concept, why it exists, trade-offs, and how it fits Zion Lab. Let me write or apply things myself when practical.
  - *Build mode*: give me working, complete config and exact commands, with brief explanations.
- **You can't see my cluster.** When you need its state, give me the exact commands to run and I'll paste the output. Never guess at current state. Ask.
- **Plan before change.** For anything non-trivial, give a short plan first: what changes, the risk, and how to roll back.
- **Flag risk clearly.** Before anything that could cause data loss or downtime (storage changes, PVC/PV moves, namespace deletion, migrations, database upgrades), stop, call it out explicitly, and confirm a backup exists.
- **Migrate incrementally.** Move one service at a time from the old setup to the new structure. Keep the old version working until the new one is verified.
- **Give complete files.** When writing manifests or config, give the full file with its repo path, not fragments, unless I ask for a diff.
- **Push back.** If my idea is wrong, insecure, or overcomplicated, say so and explain why. Don't just agree.
- **Keep docs current.** When something changes, tell me which docs, conventions, or ADRs to update, and draft the update.

## Hard rules for Claude
- Never mutate a cluster. Only read-only commands (`get`, `describe`, `logs`, `top`, `auth can-i`). Changes happen via commits + GitOps.
- Always pass `--context` explicitly (`extreme`, or `zion` for the mini's cluster until it is renamed `mini`); never rely on the current context. If a context is not in the kubeconfig of the machine I run on (the Lenovo's kubeconfig is a separate file I cannot read), don't query it: ask me for pasted output.
- Never push and never commit. I review, commit and push; you suggest commit messages.
- Never read, print, or decrypt secrets or keys. Refer to secrets by name only and use placeholders. Reading or copying the ciphertext in `*.sops.yaml` files is fine; plaintext never is.
- If a paste or a log contains a live token or key (Immich prints maintenance login tokens, Tailscale and Cloudflare tokens), say so, don't repeat it, and recommend rotating it.
- Never commit plaintext secrets.
- `ssh`, `scp`, `sudo`, `rsync`, `k3s`, `systemctl`, `limactl`, `launchctl`, `tailscale`, `cloudflared`, `ufw`, `umount` and `crontab` are mine to run. Give me the command.
- Edit files with the Edit and Write tools, not with shell heredocs or scripts: the Bash guard scans the whole command text and blocks prose that contains a blocked word.
- If `.claude/hooks/guard-bash.sh` blocks something, explain what you wanted and why; don't rephrase to bypass it. After changing the hook, run `.claude/hooks/test-guard.sh`.

## Per-service migration workflow
1. **Inventory** the service on the source cluster (read-only): workloads, PVCs, config, ingress, secrets by name.
2. **Define in repo** + write the service doc (what it is, data, backup/restore).
3. **Deploy to the target cluster** on a Tailscale test endpoint with disposable data.
4. **Backup + restore test** on the target.
5. **Cutover** (I run it): scale the source to 0, final backup, restore into the target, verify, repoint the same hostnames (Tailscale + Cloudflare).
6. **Soak** about 2 weeks by default (shortened when I say so) with the source scaled to 0 and its data kept.
7. **Remove** the service from the source cluster.

## Definition of done for a service
- In the repo and deployed via GitOps only
- Images pinned and multi-arch
- Resource requests/limits set
- Secrets encrypted
- Service doc with backup and restore steps
- Restore tested, with the date recorded
- Access matches the security baseline

## Security baseline
- Prefer Tailscale-only access. Anything exposed publicly on kanokgan.com needs a reason, TLS, and authentication.
- Least privilege for service accounts and RBAC.
- No secrets in chat outputs I might commit. Use placeholders.

## Public repository
This repo is public on GitHub (since 2026-10-12) as a portfolio. Every file and every commit is world-readable, and history cannot be un-published.
- Never commit: plaintext secrets, tokens, private keys, kubeconfigs, LAN IPs, or real names of family members. Use placeholders (`Member1Drive`, "family").
- Fine to commit: the tailnet domain (`dove-komodo.ts.net`), public hostnames on kanokgan.com, the age public key, SOPS-encrypted `*.sops.yaml` files.
- Guardrails: `.pre-commit-config.yaml` runs gitleaks and `script/check-denylist.sh` (private terms in the gitignored `.denylist`; Claude never reads it). `.github/workflows/secret-scan.yaml` scans full history on push and PR.
- If a secret reaches GitHub, assume it is compromised: rotate it first, then remove it.
- Docs are read by recruiters: keep them accurate and in sync with the manifests.

## Response style
- Be direct and concise. Use headings or lists only when they help.
- Use code blocks with the file path as the first comment.
- End multi-step work with a short "verify" step (commands that show it worked).

## Repository contents (current)

- `clusters/extreme/` (the Lenovo) and `clusters/zion/` (the mini, to be renamed `mini`): Flux bootstrap files (`flux-system/`, generated, do not edit) and the Kustomizations (`apps.yaml`, plus `infrastructure.yaml` on `extreme`), which apply the folders below with SOPS decryption.
- `apps/base/`: Immich and Actual Budget. `apps/extreme/` and `apps/zion/`: their per-cluster overlays (library volume, GPU or CPU image, Tailscale sidecars, NodePorts, encrypted secrets).
- `infrastructure/`: cluster-wide components. Today the NVIDIA device plugin and monitoring (ADR 0010) for the Lenovo (`base/`, `extreme/`, `extreme/monitoring/`); the ingress, storage and backup ADRs are still pending.
- `hosts/macos-mini/` and `hosts/ubuntu-extreme/`: the host-level setup outside Flux (Lima VM, native apps, k3s install, GPU notes, `cloudflared`, the nightly NAS backup job).
- `docs/decisions/`: ADRs. `docs/services/`: per-service docs with backup and restore. `docs/migration/`: migration tracker. `.claude/`: Claude Code settings, the Bash guard hook (needs `jq`) and its test, `hooks/test-guard.sh`.
- [script/auto-mount.sh](script/auto-mount.sh): macOS helper that mounts the NAS SMB shares over Tailscale; not part of the cluster.
- `.pre-commit-config.yaml`, [script/check-denylist.sh](script/check-denylist.sh), `.github/workflows/secret-scan.yaml`: public-repo guardrails (see "Public repository").

There is no build system, linter, or test suite yet. Validate manifests with `kustomize build apps/extreme` and `kustomize build apps/zion` (or `kubectl kustomize`) before committing.
