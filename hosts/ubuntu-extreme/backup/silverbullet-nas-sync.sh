#!/bin/bash
# hosts/ubuntu-extreme/backup/silverbullet-nas-sync.sh
# Nightly copy of the SilverBullet notes (pages, PDFs, spreadsheets, attachments) from /srv/silverbullet to the
# Synology. One way, Lenovo -> NAS, and it never deletes on the NAS (rclone copy): a note deleted by mistake can be
# fetched from the NAS. Only the machine that runs SilverBullet as primary may run it (one writer per NAS path).
# Run by a systemd timer at 04:30, after the Immich copy (04:00). Setup: hosts/ubuntu-extreme/backup/README.md
set -euo pipefail

SRC="/srv/silverbullet"
# rclone remote "zion-nas" (SFTP to the NAS over Tailscale) is defined in ~/.config/rclone/rclone.conf, outside Git.
DEST="zion-nas:/ZionLabs/SilverBullet/Backup"

[[ -d "$SRC" ]] || { echo "notes folder missing: $SRC" >&2; exit 3; }
# An empty folder means the volume is not what we think it is: do not copy "nothing" and call it a backup.
[[ -n "$(ls -A "$SRC")" ]] || { echo "notes folder is empty: $SRC" >&2; exit 4; }

# One run at a time.
exec 9>/run/lock/silverbullet-nas-sync.lock
flock -n 9 || { echo "previous run still going, skipping" >&2; exit 0; }

echo "start $(date -Iseconds)"
# Default comparison (size + modification time): notes are small and edited in place, so size alone would miss an edit.
rclone copy "$SRC" "$DEST" \
  --transfers 4 --checkers 8 \
  --exclude ".DS_Store" --exclude "@eaDir/**" --exclude "#recycle/**" \
  --log-level NOTICE --stats 0
echo "done $(date -Iseconds)"
