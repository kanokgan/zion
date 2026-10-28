# NAS backup jobs (Lenovo to Synology)

Two systemd timers copy host directories to the NAS with `rclone copy` over SFTP on Tailscale, both with the same rclone remote `zion-nas`:

| Timer | Copies | To | Doc |
|---|---|---|---|
| `immich-nas-sync.timer`, 04:00 | `/srv/immich` | `/ZionLabs/Immich/Backup` | this file |
| `silverbullet-nas-sync.timer`, 04:30 | `/srv/silverbullet` | `/ZionLabs/SilverBullet/Backup` | [silverbullet.md](../../../docs/services/silverbullet.md), "Backup and restore" |

The rest of this file covers the Immich job. The SilverBullet job uses the same account, key and install steps (its scripts and units are `silverbullet-nas-sync.*` here).

## Immich library backup

Nightly at 04:00 a systemd timer runs `immich-nas-sync.sh`, which copies `/srv/immich` to the NAS folder `/ZionLabs/Immich/Backup`. Immich writes its own database dump at about 00:00, so by 04:00 the dump is complete.

This is the mirror of `hosts/macos-mini/backup/` (ADR 0009), which was never installed. **Only the machine that runs Immich as primary may have its timer enabled.** At the 2026-10-20 to 21 cutover this job was enabled; both machines writing to the same NAS path would mix two libraries.

- **One way, never deletes.** Photos deleted in Immich stay on the NAS, and a restore brings them back. Never copy the NAS onto `/srv/immich` except for a deliberate restore.
- **`--size-only`**, as before: a nightly run over 1.3 TB stays fast. It would miss a file that changed without changing size; the protection against that is the NAS snapshots on `ZionLabs` (hourly).
- Not in Git by design: the SFTP key and `~/.config/rclone/rclone.conf` (remote `zion-nas`, the NAS user `sc-zion`).
- NAS account `sc-zion` (checked 2026-10-21): not in the `administrators` group, Read/Write on `ZionLabs`, explicit No access on every other share except its `home` (which holds `~/.ssh/authorized_keys`), SFTP only. An SFTP `ls` as that user shows only `ZionLabs` and `home`. Its `authorized_keys` holds only this machine's key (`ubuntu-extreme immich-nas-sync`); the key `immich-library-sync-cronjob` of the wiped cluster was removed on 2026-10-21.
- No alert yet when a night fails (monitoring stage 3, [monitoring.md](../../../docs/services/monitoring.md)): check the journal.

## Setup (once, run by the owner; already done)

The job runs as root, because the Immich container writes `/srv/immich` as root and its folders are not readable by other users. Manual runs of rclone against the library therefore need `sudo rclone --config /home/kanokgan/.config/rclone/rclone.conf ...`; the systemd unit sets the same path in `RCLONE_CONFIG`.

```sh
sudo apt install -y rclone
ssh-keygen -t ed25519 -f ~/.ssh/zion-nas -C "ubuntu-extreme immich-nas-sync" -N ""   # a dedicated key; add the .pub line to the NAS user's ~/.ssh/authorized_keys
rclone config                                    # remote "zion-nas": sftp, host tnbk.dove-komodo.ts.net, user sc-zion, key_file = /home/kanokgan/.ssh/zion-nas
rclone lsd zion-nas:/ZionLabs/Immich/Backup      # upload, thumbs, backups ...
# dry run: only the files changed since the last copy should be listed
sudo rclone --config /home/kanokgan/.config/rclone/rclone.conf copy /srv/immich zion-nas:/ZionLabs/Immich/Backup --size-only --dry-run -v | tail
sudo install -m 0755 immich-nas-sync.sh /usr/local/sbin/
sudo cp immich-nas-sync.service immich-nas-sync.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start immich-nas-sync.service     # one manual run, then check the journal
journalctl -u immich-nas-sync -n 30 --no-pager
# enable only on the machine that is Immich's primary:
sudo systemctl enable --now immich-nas-sync.timer
```

## Verify

```sh
sudo rclone --config /home/kanokgan/.config/rclone/rclone.conf check /srv/immich zion-nas:/ZionLabs/Immich/Backup \
  --size-only --one-way --exclude "@eaDir/**" --exclude "#recycle/**"
systemctl list-timers immich-nas-sync.timer
journalctl -u immich-nas-sync -n 30 --no-pager
```

No differences from `rclone check` means the NAS holds everything. The line `No common hash found - not using a hash for checks` is logged as ERROR but is expected: with `--size-only` between a local disk and SFTP there is no shared checksum.

Status: installed 2026-10-21, first manual run clean, `rclone check` 0 differences over 556,496 files, timer enabled. The first scheduled run (2026-10-21 04:00 to 04:03) succeeded unattended, with the restricted NAS account.

## Restore

Copy the library back with `rclone copy zion-nas:/ZionLabs/Immich/Backup <target>`, then restore the newest `immich-db-backup-*.sql.gz` through Immich's restore flow (`docs/services/immich.md`). Not tested from this machine yet.
