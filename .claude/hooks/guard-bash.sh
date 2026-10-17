#!/usr/bin/env bash
# .claude/hooks/guard-bash.sh
# PreToolUse guard for Claude Code Bash calls. Exit 2 blocks; stderr is shown to Claude.
# Fails closed: false positives are acceptable, the owner runs those commands. It scans the whole command text,
# including heredocs, so prose that contains a blocked word is blocked too: edit documents with the Edit/Write tools.
# Tested by .claude/hooks/test-guard.sh.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "guard-bash: jq is required; blocking." >&2; exit 2; }

cmd="$(jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

block() {
  echo "BLOCKED by guard-bash: $1" >&2
  echo "Propose the change as a commit (GitOps), or ask the owner to run it. Do not rephrase to bypass." >&2
  exit 2
}

has() { grep -Eq -- "$1" <<<"$cmd"; }

# Cluster mutations (verbs matched anywhere, so --context before the verb can't bypass)
if has '(^|[;&|(`[:space:]])kubectl([[:space:]]|$)'; then
  has '[[:space:]](apply|create|delete|edit|patch|replace|scale|drain|cordon|uncordon|taint|label|annotate|set|exec|cp|debug|run|expose|autoscale|attach|port-forward|proxy)([[:space:]]|$)' \
    && block "mutating or interactive kubectl command"
  has '[[:space:]]rollout[[:space:]]+(restart|undo|pause|resume)' && block "kubectl rollout mutation"
  # Secret values: any kubectl line that mentions secrets and asks for output, wherever the resource name sits
  # (`get -o yaml secret x`, `get cm,secret -o yaml`, `get --raw /api/v1/.../secrets`, jsonpath, go-template).
  has '[Ss]ecret' && has '(^|[[:space:]])(-o|--output|--raw|-o[a-z=]+|--template|--show-managed-fields)([[:space:]=]|$)|jsonpath|go-template' \
    && block "reading secret values"
  has '[[:space:]]--raw([[:space:]=]|$)' && block "kubectl --raw (raw API reads can return secrets)"
  has '[[:space:]]config[[:space:]]+view' && block "kubectl config view (can print credentials)"
fi

has '(^|[;&|(`[:space:]])helm[[:space:]]+(install|upgrade|uninstall|delete|rollback|get[[:space:]]+values)' && block "helm mutation / values read"
has '(^|[;&|(`[:space:]])flux[[:space:]]+(bootstrap|install|uninstall|reconcile|suspend|resume|delete|create)' && block "flux mutation"
has '(^|[;&|(`[:space:]])argocd[[:space:]]+.*(sync|delete|set|create|rollback)' && block "argocd mutation"

# sops: only encrypting (and version/help) is allowed. Every other form opens or prints plaintext
# (`sops file`, `sops edit`, `sops decrypt`, `-d`, exec-env, exec-file).
if has '(^|[;&|(`[:space:]])sops([[:space:]]|$)'; then
  has '[[:space:]](-d|--decrypt|decrypt|edit|exec-env|exec-file)([[:space:]]|$)' && block "decrypting secrets"
  has '[[:space:]](-e|--encrypt|encrypt|--version|-v|--help|-h)([[:space:]]|$)' || block "sops without --encrypt (would decrypt or open plaintext)"
fi
has '(^|[;&|(`[:space:]])age[[:space:]].*(-d|--decrypt)' && block "decrypting with age"
has '\.agekey|/sops/age/' && block "touching age keys"

# Host-level tools: the owner runs these (they change machines, tunnels, VMs, firewalls, jobs).
has '(^|[;&|(`[:space:]])(sudo|ssh|scp|rsync|k3s|systemctl|limactl|launchctl|tailscale|cloudflared|ufw|umount|crontab)([[:space:]]|$)' && block "host-level command"

# Git: reading is fine (status, diff, log, show). Anything that writes history, moves the working tree or
# talks to a remote is the owner's, including forms like `git -C dir push`.
has '(^|[;&|(`[:space:]])git[[:space:]]([^;&|]*[[:space:]])?(push|commit|merge|rebase|reset|tag|stash|pull|clean|filter-branch|filter-repo)([[:space:]]|$)' \
  && block "git operation that writes history or touches a remote"

exit 0
