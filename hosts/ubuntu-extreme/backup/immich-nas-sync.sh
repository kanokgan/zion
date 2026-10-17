#!/bin/bash
# hosts/ubuntu-extreme/backup/immich-nas-sync.sh
# Nightly copy of the Immich library (photos, thumbnails, encoded video, Immich's own DB dumps in backups/) from
# /srv/immich to the Synology. One way, Lenovo -> NAS, and it never deletes on the NAS (rclone copy).
# The same job as hosts/macos-mini/backup/ with the roles swapped (ADR 0009): only the machine that currently runs
# Immich as primary may run it, because only one machine writes to that NAS path. Run by a systemd timer at 04:00;
# Immich writes its DB dump at about 00:00. Setup and the reasons: hosts/ubuntu-extreme/backup/README.md
set -euo pipefail

SRC="/srv/immich"
# rclone remote "zion-nas" (SFTP to the NAS over Tailscale) is defined in ~/.config/rclone/rclone.conf, outside Git.
DEST="zion-nas:/ZionLabs/Immich/Backup"

[[ -d "$SRC/upload" ]] || { echo "library missing or wrong path: $SRC" >&2; exit 3; }

# One run at a time.
exec 9>/run/lock/immich-nas-sync.lock
flock -n 9 || { echo "previous run still going, skipping" >&2; exit 0; }

echo "start $(date -Iseconds)"
rclone copy "$SRC" "$DEST" \
  --size-only --transfers 4 --checkers 8 \
  --exclude ".DS_Store" --exclude "@eaDir/**" --exclude "#recycle/**" \
  --log-level NOTICE --stats 0
echo "done $(date -Iseconds)"
