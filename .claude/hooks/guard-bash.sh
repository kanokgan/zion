#!/usr/bin/env bash
# .claude/hooks/guard-bash.sh
# PreToolUse guard for Claude Code Bash calls. Exit 2 blocks; stderr is shown to Claude.
# Fails closed: false positives are acceptable, the owner runs those commands.
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
  has '[[:space:]]get[[:space:]]+(secret|secrets)([[:space:]/]|$)' && has '[[:space:]](-o|--output)' \
    && block "reading secret values"
fi

has '(^|[;&|(`[:space:]])helm[[:space:]]+(install|upgrade|uninstall|delete|rollback|get[[:space:]]+values)' && block "helm mutation / values read"
has '(^|[;&|(`[:space:]])flux[[:space:]]+(bootstrap|install|uninstall|reconcile|suspend|resume|delete|create)' && block "flux mutation"
has '(^|[;&|(`[:space:]])argocd[[:space:]]+.*(sync|delete|set|create|rollback)' && block "argocd mutation"

has '(^|[;&|(`[:space:]])sops[[:space:]].*(-d|--decrypt|exec-env|exec-file)' && block "decrypting secrets"
has '(^|[;&|(`[:space:]])age[[:space:]].*(-d|--decrypt)' && block "decrypting with age"
has '\.agekey|/sops/age/' && block "touching age keys"

has '(^|[;&|(`[:space:]])(sudo|ssh|scp|rsync|k3s|systemctl)([[:space:]]|$)' && block "host-level command"

has '(^|[;&|(`[:space:]])git[[:space:]]+(push|reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f|filter-branch|filter-repo)' && block "destructive or remote git operation"

exit 0
