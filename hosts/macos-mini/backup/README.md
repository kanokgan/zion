# Immich library backup (mini to Synology)

Nightly at 04:00, `immich-nas-sync.sh` copies `/Volumes/HighSpeed2T/Immich/Backup` to the NAS folder `/ZionLabs/Immich/Backup` with `rclone copy` over SFTP on Tailscale. Immich writes its own database dump at about 00:00, so by 04:00 the dump is complete.

- **One way, never deletes.** Photos deleted in Immich stay on the NAS, and a restore brings them back. Never sync the NAS onto the NVMe (it would overwrite newer uploads). Only one machine writes to that NAS path at any time.
- **Runs on the Mac host, not in the cluster.** The Lima VM cannot reach the tailnet by itself, and the library is a host volume.
- **`--size-only`**, as on the Lenovo: a nightly run over 1.3 TB stays fast. It would miss a file that changed without changing size, and the NAS keeps only one version of a file. The protection against that is Synology snapshots on the `ZionLabs` share (hourly, kept 24 hourly, 7 daily, 2 weekly, set up 2026-10-17).
- macOS metadata (`.DS_Store`, `.Spotlight-V100`, `.fseventsd`, `.Trashes`) is excluded so it never reaches the NAS.
- Not in Git by design: the SFTP key and `~/.config/rclone/rclone.conf` (remote `zion-nas`). The job should use a dedicated NAS user with access to `ZionLabs` only.
- No alert yet if a night fails: check the log until monitoring exists.

## Setup (once)

```sh
brew install rclone
rclone config                        # new remote "zion-nas", type sftp, host tnbk.dove-komodo.ts.net, key_file = the private key
rclone lsd zion-nas:/ZionLabs/Immich/Backup   # same top-level folders as the NVMe
# dry run: only a few files should be listed (plus macOS metadata), not thousands
rclone copy /Volumes/HighSpeed2T/Immich/Backup zion-nas:/ZionLabs/Immich/Backup --size-only --dry-run -v | tail
# then a manual run:
./immich-nas-sync.sh && tail "$HOME/Library/Logs/immich-nas-sync.log"
sudo cp com.zionlab.immich-nas-sync.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.zionlab.immich-nas-sync.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.zionlab.immich-nas-sync.plist
```

## Verify

```sh
rclone check /Volumes/HighSpeed2T/Immich/Backup zion-nas:/ZionLabs/Immich/Backup --size-only --one-way \
  --exclude ".DS_Store" --exclude ".Spotlight-V100/**" --exclude ".fseventsd/**" --exclude ".Trashes/**"
sudo launchctl print system/com.zionlab.immich-nas-sync | grep -E "state|last exit"
tail "$HOME/Library/Logs/immich-nas-sync.log"
```

`rclone check ... --one-way` reports files that are on the NVMe and missing or different on the NAS. No differences means the NAS holds everything.

## Restore

Copy the library back with `rclone copy zion-nas:/ZionLabs/Immich/Backup <target>` (the reverse direction), then restore the newest `immich-db-backup-*.sql.gz` through Immich's restore flow (see `docs/services/immich.md`). Record the date of the first tested restore here: the NAS copy of the library was restored onto the mini on 2026-10-17 (FreeFileSync from the NAS, then the DB restore); the rclone job itself has not been run yet.
