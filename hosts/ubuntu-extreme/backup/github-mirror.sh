#!/bin/bash
# hosts/ubuntu-extreme/backup/github-mirror.sh
# Nightly backup of every GitHub repo owned by the account below, as portable bare mirrors with their Git LFS objects
# inside (ADR 0011). Two steps:
#   1. GitHub -> /srv/git-mirror on the Lenovo's NVMe: one bare repo per GitHub repo, branches and tags only, plus
#      `git lfs fetch --all` (every LFS object of every ref, stored in <repo>.git/lfs/objects).
#   2. /srv/git-mirror -> NAS with `rclone sync` (deletes on the NAS: git rewrites files such as packed-refs, and a
#      stale copy of them shows refs at old commits). Point-in-time history comes from the NAS snapshots on ZionLabs.
# A repo deleted or renamed on GitHub is kept here and only logged. Any folder <name>.git from the NAS works offline:
#   git clone /path/<name>.git && cd <name> && git lfs pull
# Runs as the owner's user (not root) from a systemd timer at 05:00. Setup and restore: docs/services/github-mirror.md
set -euo pipefail
shopt -s inherit_errexit

GITHUB_OWNER="kanokgan"
MIRROR_DIR="/srv/git-mirror"
# Fine-grained GitHub token, read-only (Contents + Metadata), one line, mode 0600, outside Git.
TOKEN_FILE="${GITHUB_TOKEN_FILE:-$HOME/.config/github-mirror/token}"
# rclone remote "zion-nas" (SFTP to the NAS over Tailscale), defined in ~/.config/rclone/rclone.conf, outside Git.
DEST="zion-nas:/ZionLabs/Git/GitHub"

for cmd in git git-lfs curl jq rclone flock; do
  command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 3; }
done
[[ -d "$MIRROR_DIR" ]] || { echo "mirror folder missing: $MIRROR_DIR" >&2; exit 3; }
[[ -r "$TOKEN_FILE" ]] || { echo "token file missing or unreadable: $TOKEN_FILE" >&2; exit 3; }

# One run at a time.
exec 9>/run/lock/github-mirror.lock
flock -n 9 || { echo "previous run still going, skipping" >&2; exit 0; }

# Credentials for git and git-lfs, from the environment only: the token is read from the file by a credential helper,
# so it never appears in a command line (visible in `ps`), in a remote URL, or in any repo's config (which goes to
# the NAS). The empty helper first clears any helper from the user's global config, so nothing stores the token.
export GITHUB_TOKEN_FILE="$TOKEN_FILE"
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0="credential.helper"
export GIT_CONFIG_VALUE_0=""
export GIT_CONFIG_KEY_1="credential.https://github.com.helper"
# shellcheck disable=SC2016  # expanded by git's shell when the helper runs, not here
export GIT_CONFIG_VALUE_1='!f() { test "$1" = get && printf "username=x-access-token\npassword=%s\n" "$(cat "$GITHUB_TOKEN_FILE")"; }; f'

# Prints "<name> <https clone url>" for every repo owned by GITHUB_OWNER that the token can read (private included).
list_repos() {
  local page=1 out
  while :; do
    # The token goes to curl on stdin (--config -), not on the command line.
    out=$(printf 'header = "Authorization: Bearer %s"\n' "$(<"$TOKEN_FILE")" \
      | curl -fsS --config - \
          -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/user/repos?affiliation=owner&per_page=100&page=${page}")
    [[ "$(jq 'length' <<<"$out")" -gt 0 ]] || break
    jq -r --arg owner "$GITHUB_OWNER" '.[] | select(.owner.login == $owner) | "\(.name) \(.clone_url)"' <<<"$out"
    page=$((page + 1))
  done
}

# Fetches branches, tags and all LFS objects into an existing bare repo, and points HEAD at GitHub's default branch
# (so a clone from the mirror checks it out). Each step returns on failure: `set -e` does not apply inside a function
# called with `||`.
update_repo() {
  local dir=$1 head
  git -C "$dir" fetch --quiet --prune origin || return 1
  head=$(git -C "$dir" ls-remote --symref origin HEAD | awk '/^ref:/ {print $2; exit}') || return 1
  if [[ -n "$head" ]]; then
    git -C "$dir" symbolic-ref HEAD "$head" || return 1
  fi
  # An empty repo (no commits yet) has nothing to fetch for LFS.
  if [[ -n "$(git -C "$dir" for-each-ref --count=1)" ]]; then
    git -C "$dir" lfs fetch --all origin || return 1
  fi
}

# A new repo is built in <name>.git.partial and renamed only when complete, so a half-made mirror never looks done.
create_repo() {
  local name=$1 url=$2 dir="$MIRROR_DIR/$1.git" tmp="$MIRROR_DIR/$1.git.partial"
  rm -rf -- "$tmp"
  git init --quiet --bare "$tmp" || return 1
  git -C "$tmp" remote add origin "$url" || return 1
  # Branches and tags only. A plain `--mirror` would also copy GitHub's refs/pull/*, which no other host accepts,
  # so a restore could not be pushed with `git push --mirror`.
  git -C "$tmp" config --replace-all remote.origin.fetch '+refs/heads/*:refs/heads/*' || return 1
  git -C "$tmp" config --add remote.origin.fetch '+refs/tags/*:refs/tags/*' || return 1
  update_repo "$tmp" || return 1
  mv -- "$tmp" "$dir"
}

echo "start $(date -Iseconds)"

repos=$(list_repos)
[[ -n "$repos" ]] || { echo "GitHub returned no repos: wrong token or API problem, nothing changed" >&2; exit 4; }
echo "repos on GitHub: $(wc -l <<<"$repos")"

failed=()
# fd 3, so that no git command can read the repo list from stdin.
while read -r -u 3 name url; do
  if [[ -d "$MIRROR_DIR/$name.git" ]]; then
    update_repo "$MIRROR_DIR/$name.git" || failed+=("$name")
  else
    echo "new repo: $name"
    create_repo "$name" "$url" || failed+=("$name")
  fi
done 3<<<"$repos"

# Mirrors whose repo is gone from GitHub (deleted or renamed) are kept, never removed by this script.
for dir in "$MIRROR_DIR"/*.git; do
  [[ -d "$dir" ]] || continue
  name=$(basename "$dir" .git)
  grep -q "^${name} " <<<"$repos" || echo "kept, no longer on GitHub: $name"
done

# Guard before `rclone sync`: never let a lost or emptied folder delete the NAS copy.
local_count=$(find "$MIRROR_DIR" -mindepth 1 -maxdepth 1 -type d -name '*.git' | wc -l)
nas_count=$(rclone lsf --dirs-only "$DEST" 2>/dev/null | grep -c '\.git/$' || true)
if (( local_count == 0 || local_count < nas_count )); then
  echo "refusing to sync: $local_count repos here, $nas_count on the NAS" >&2
  exit 5
fi

rclone sync "$MIRROR_DIR" "$DEST" \
  --transfers 4 --checkers 8 \
  --exclude "*.git.partial/**" --exclude "@eaDir/**" --exclude "#recycle/**" \
  --log-level NOTICE --stats 0

if (( ${#failed[@]} > 0 )); then
  echo "failed: ${failed[*]} (their previous state was synced, if any)" >&2
  exit 1
fi
echo "done $(date -Iseconds): $local_count repos"
