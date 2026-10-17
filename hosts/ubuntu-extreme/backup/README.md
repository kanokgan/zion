# Immich library backup (Lenovo to Synology)

Nightly at 04:00 a systemd timer runs `immich-nas-sync.sh`, which copies `/srv/immich` to the NAS folder `/ZionLabs/Immich/Backup` with `rclone copy` over SFTP on Tailscale. Immich writes its own database dump at about 00:00, so by 04:00 the dump is complete.

This is the mirror of `hosts/macos-mini/backup/` (ADR 0009). **Only the machine that runs Immich as primary may have its timer enabled.** At the cutover the mini's job is disabled and this one is enabled; both writing to the same NAS path would mix two libraries.

- **One way, never deletes.** Photos deleted in Immich stay on the NAS, and a restore brings them back. Never copy the NAS onto `/srv/immich` except for a deliberate restore.
- **`--size-only`**, as before: a nightly run over 1.3 TB stays fast. It would miss a file that changed without changing size; the protection against that is the NAS snapshots on `ZionLabs` (hourly).
- Not in Git by design: the SFTP key and `~/.config/rclone/rclone.conf` (remote `zion-nas`, the same dedicated NAS user as on the mini, access to `ZionLabs` only).
- No alert yet when a night fails: check the journal until monitoring exists.

## Setup (once, run by the owner)

```sh
sudo apt install -y rclone
rclone config                                    # remote "zion-nas": sftp, host tnbk.dove-komodo.ts.net, key_file = the NAS user's key
rclone lsd zion-nas:/ZionLabs/Immich/Backup      # upload, thumbs, backups ...
# dry run: only the files changed since the last copy should be listed
rclone copy /srv/immich zion-nas:/ZionLabs/Immich/Backup --size-only --dry-run -v | tail
sudo install -m 0755 immich-nas-sync.sh /usr/local/sbin/
sudo cp immich-nas-sync.service immich-nas-sync.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start immich-nas-sync.service     # one manual run, then check the journal
journalctl -u immich-nas-sync -n 30 --no-pager
# only at the cutover, once the mini's job is disabled:
sudo systemctl enable --now immich-nas-sync.timer
```

## Verify

```sh
rclone check /srv/immich zion-nas:/ZionLabs/Immich/Backup --size-only --one-way \
  --exclude ".DS_Store" --exclude "@eaDir/**" --exclude "#recycle/**"
systemctl list-timers immich-nas-sync.timer
journalctl -u immich-nas-sync -n 30 --no-pager
```

No differences from `rclone check` means the NAS holds everything.

## Restore

Copy the library back with `rclone copy zion-nas:/ZionLabs/Immich/Backup <target>`, then restore the newest `immich-db-backup-*.sql.gz` through Immich's restore flow (`docs/services/immich.md`). Not tested from this machine yet.
