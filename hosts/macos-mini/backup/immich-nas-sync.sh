#!/bin/bash
# hosts/macos-mini/backup/immich-nas-sync.sh
# Nightly copy of the Immich library (photos, thumbnails, encoded video, Immich's own DB dumps in backups/) from
# the mini's external NVMe to the Synology. One way, mini -> NAS, and it never deletes on the NAS (rclone copy),
# like the Lenovo's CronJob did. Run by launchd at 04:00; Immich writes its DB dump at about 00:00.
# Setup, restore and the reason for each choice: hosts/macos-mini/backup/README.md
set -euo pipefail

SRC="/Volumes/HighSpeed2T/Immich/Backup"
# rclone remote "zion-nas" (SFTP to the NAS over Tailscale) is defined in ~/.config/rclone/rclone.conf, outside Git.
DEST="zion-nas:/ZionLabs/Immich/Backup"
LOG="$HOME/Library/Logs/immich-nas-sync.log"
LOCK="/tmp/immich-nas-sync.lock"

[[ -d "$SRC/upload" ]] || { echo "$(date -Iseconds) NVMe not mounted or wrong path: $SRC" >> "$LOG"; exit 3; }

# One run at a time (macOS has no flock); mkdir is atomic.
mkdir "$LOCK" 2>/dev/null || { echo "$(date -Iseconds) previous run still going, skipping" >> "$LOG"; exit 0; }
trap 'rmdir "$LOCK"' EXIT

echo "$(date -Iseconds) start" >> "$LOG"
/opt/homebrew/bin/rclone copy "$SRC" "$DEST" \
  --size-only --transfers 4 --checkers 8 \
  --exclude ".DS_Store" --exclude ".Spotlight-V100/**" --exclude ".fseventsd/**" --exclude ".Trashes/**" \
  --log-file "$LOG" --log-level NOTICE --stats 0
echo "$(date -Iseconds) done" >> "$LOG"
