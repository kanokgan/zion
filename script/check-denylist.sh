#!/usr/bin/env bash
# script/check-denylist.sh
# Pre-commit check: blocks a commit whose staged additions contain a term from .denylist.
# .denylist is gitignored: one term per line, case-insensitive, # for comments. The real private terms
# (family names, private hostnames, ...) live only in that local file, never in Git.
set -euo pipefail

denylist="$(git rev-parse --show-toplevel)/.denylist"
if [ ! -f "$denylist" ]; then
  echo "check-denylist: no .denylist found, private terms are NOT being checked." >&2
  exit 0
fi

patterns="$(grep -vE '^[[:space:]]*(#|$)' "$denylist" || true)"
[ -z "$patterns" ] && exit 0

hits="$(git diff --cached -U0 --no-color \
  | grep -E '^\+' | grep -vE '^\+\+\+ ' \
  | grep -iF -f <(printf '%s\n' "$patterns") || true)"

if [ -n "$hits" ]; then
  echo "check-denylist: staged changes contain a term from .denylist:" >&2
  echo "$hits" >&2
  echo "Replace it with a placeholder. This repo is public." >&2
  exit 1
fi
