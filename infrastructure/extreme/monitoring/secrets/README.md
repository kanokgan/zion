# Monitoring secrets (templates)

Three secrets are needed for stage 2 of [ADR 0010](../../../../docs/decisions/0010-monitoring.md). Only templates with placeholders are in Git here; the real files are encrypted with SOPS (ADR 0007) and live one folder up, next to `helmrelease.yaml`. Nothing in this folder is applied to the cluster.

| Template | Becomes | Holds |
|---|---|---|
| `grafana-admin.sops.yaml.template` | `../grafana-admin.sops.yaml` | Grafana admin user and password (a strong password from the password manager) |
| `tailscale-auth.sops.yaml.template` | `../tailscale-auth.sops.yaml` | a Tailscale auth key for Grafana's sidecar (a reusable key; used only on first join) |
| `alertmanager-config.sops.yaml.template` | `../alertmanager-config.sops.yaml` | the full Alertmanager config, including the Telegram bot token and your chat ID |

## Telegram

1. In Telegram, message `@BotFather`, send `/newbot`, and pick a name. Keep the token it returns (looks like `123456:ABC...`).
2. Open a chat with your new bot and press Start (a bot cannot message you until you do).
3. Get your numeric chat ID, for example by messaging `@userinfobot`. It is a number such as `123456789`.
4. Put both in `alertmanager-config.sops.yaml` as `bot_token` and `chat_id` (the ID is a plain number, no quotes).

## For each secret (from the repo root, one at a time)

```sh
cd infrastructure/extreme/monitoring
cp secrets/grafana-admin.sops.yaml.template grafana-admin.sops.yaml
# edit grafana-admin.sops.yaml in your editor and replace the placeholders (do not type secrets into the shell)
sops --encrypt --in-place grafana-admin.sops.yaml
grep -n "CHANGE_ME\|BOT_TOKEN\|tskey" grafana-admin.sops.yaml || echo "no plaintext left"
```
Repeat for the other two. Do the edit and the encrypt back to back: for those seconds the file holds the secret in plain text. Before committing, `git status` should show the `*.sops.yaml` files as new, and `git diff --cached` must show only `ENC[AES256_GCM,...]` values. The pre-commit gitleaks hook also scans staged files, including Telegram bot tokens.

## After that

Tell Claude the three files exist. The HelmRelease values and `kustomization.yaml` are then changed to use them (Grafana admin secret, the tailnet sidecar, the Alertmanager config), in one commit, so Flux never references a Secret that is not there yet.

If a token is ever shown on a screen share, a log or a chat, rotate it: `/revoke` in BotFather for the bot, a new key in the Tailscale console, a new Grafana password.
