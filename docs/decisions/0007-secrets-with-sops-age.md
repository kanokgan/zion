# 0007. Secrets with SOPS and age

- Status: accepted
- Date: 2026-10-11

## Context
Secrets must never be in Git in plain text, yet the cluster must be rebuildable from the repo plus backups (CLAUDE.md). Flux (ADR 0005) can decrypt SOPS-encrypted manifests natively. Two clusters (`zion` and later `zion-standby`, ADR 0004) need to decrypt the same secrets.

## Decision
Use SOPS with age.
- Secret manifests are named `*.sops.yaml`. Only `data` and `stringData` are encrypted; names, keys and metadata stay readable in Git (`.sops.yaml` at the repo root holds the rule and the public key).
- A single age key pair is shared by all clusters for now. The private key lives in two places only: the password manager and a `sops-age` Secret in the `flux-system` namespace of each cluster. It is never committed (`*.agekey` is gitignored).
- Flux Kustomizations that contain secrets set `spec.decryption: {provider: sops, secretRef: {name: sops-age}}`.

The `sops-age` Secret is the one manual step outside Git. Creating it on a new cluster:
```sh
kubectl --context <cluster> create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=<path to the private key>
```

## Alternatives considered
- Sealed Secrets: the key pair is per cluster, so the standby cannot decrypt secrets sealed for the primary without extra work, and secrets are tied to one cluster's key.
- External secret managers (Vault, cloud KMS): more infrastructure than a homelab needs.

## Consequences
- Losing the private key means every secret in the repo has to be re-created and re-encrypted. Back it up in the password manager before relying on it.
- Anyone who can read the `sops-age` Secret in a cluster can decrypt every secret in the repo. Keep cluster access tight.
- Rotating the key means re-encrypting all `*.sops.yaml` files (`sops updatekeys`) and replacing the Secret in each cluster.
- Adding a recipient (for example a separate standby key) is a `.sops.yaml` change plus `sops updatekeys`.
