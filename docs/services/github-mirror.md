# GitHub mirror (backup of all GitHub repos)

A nightly backup of every repo owned by the `kanokgan` GitHub account, including all Git LFS objects, as plain bare repositories on the NAS. Each folder works on its own with `git` and `git-lfs`, offline, with no server: copy it anywhere, clone from it. Not a Kubernetes app: a systemd timer on the Lenovo, next to the other NAS jobs. Decision and alternatives: [ADR 0011](../decisions/0011-github-backup-as-bare-mirrors.md).

Status: **installed 2026-11-13.** First run 2.5 minutes (17 repos, 1.5 GB, including LFS objects in five repos, not only `kanokgan-work`); second run 33 seconds; `git fsck` clean on all 17 mirrors; `rclone check` 0 differences over 720 files; timer enabled (first scheduled run 2026-11-14 05:00). The `No common hash found` ERROR line of `rclone check` is expected (SFTP, see the Immich job). Restore test passed 2026-11-13 (below).

## What runs where

| | |
|---|---|
| Job | `github-mirror.timer` (05:00 nightly) runs `/usr/local/sbin/github-mirror.sh` as the user `kanokgan` on `ubuntu-extreme`. Files: [hosts/ubuntu-extreme/backup/](../../hosts/ubuntu-extreme/backup/README.md) `github-mirror.*` |
| Working copy | `/srv/git-mirror/<repo>.git` on the Lenovo's NVMe: bare repos, branches and tags only, LFS objects in `<repo>.git/lfs/objects/` |
| Backup | NAS `/ZionLabs/Git/GitHub/<repo>.git`, `rclone sync` over SFTP on Tailscale (remote `zion-nas`, account `sc-zion`); history from the Synology snapshots on `ZionLabs` |
| Credential | fine-grained GitHub token, read-only, in `~kanokgan/.config/github-mirror/token` (mode 0600, outside Git) |
| Size (2026-11-13) | 17 repos, 1.5 GB on disk: about 0.3 GB of git data plus about 1.2 GB of LFS (almost all in `kanokgan-work`, 170 objects; one object each in four other repos) |

What the script does, each night:
1. Lists the account's repos through the GitHub API, so new repos are picked up automatically.
2. For each repo: `git fetch --prune` of branches and tags, HEAD set to GitHub's default branch, `git lfs fetch --all` (every LFS object of every ref). A new repo is built as `<repo>.git.partial` and renamed when complete.
3. A repo deleted or renamed on GitHub is **kept** and logged as `kept, no longer on GitHub`. Delete it by hand when you are sure.
4. `rclone sync` to the NAS, unless the local folder holds fewer repos than the NAS (a lost or emptied disk then cannot wipe the backup). `sync` deletes on the NAS, unlike the other jobs' `copy`, because git rewrites some files in place (ADR 0011).

## Setup (run by the owner)

1. **Create the token** on GitHub: Settings, Developer settings, Personal access tokens, Fine-grained tokens, Generate new token.
   - Resource owner: `kanokgan`. Expiration: the longest offered, and put the date in your calendar (the job fails every night after it).
   - Repository access: **All repositories** (so new repos are included without editing the token).
   - Permissions: Repository, **Contents: Read-only**. Metadata: Read-only is added automatically. Nothing else.
2. **On the Lenovo**, store the token without it reaching the shell history:
   ```sh
   install -d -m 0700 ~/.config/github-mirror
   (umask 077; nano ~/.config/github-mirror/token)       # paste the token on one line, save
   # check it: prints the number of repos (17 on 2026-11-13), never the token
   printf 'header = "Authorization: Bearer %s"\n' "$(<~/.config/github-mirror/token)" \
     | curl -fsS --config - "https://api.github.com/user/repos?affiliation=owner&per_page=100" | jq length
   ```
3. **Packages and folder** (rclone and the `zion-nas` remote already exist from the Immich job):
   ```sh
   sudo apt install -y git git-lfs jq curl
   sudo install -d -o kanokgan -g kanokgan -m 0750 /srv/git-mirror
   ```
4. **Install the job**, from a checkout of this repo on the Lenovo:
   ```sh
   cd hosts/ubuntu-extreme/backup
   sudo install -m 0755 github-mirror.sh /usr/local/sbin/
   sudo cp github-mirror.service github-mirror.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl start github-mirror.service        # first run: about 1.5 GB from GitHub, waits until done
   journalctl -u github-mirror -n 50 --no-pager      # "new repo: ..." for each, then "done ...: 17 repos"
   sudo systemctl enable --now github-mirror.timer
   ```
   The first run downloads all LFS objects once, which counts against GitHub's monthly LFS bandwidth; later runs fetch only what is new. If a run fails with `Read-only file system`, the unit's hardening blocks a path: add it to `ReadWritePaths` in the `.service` file.

## Verify

```sh
systemctl list-timers github-mirror.timer
journalctl -u github-mirror -n 50 --no-pager
du -sh /srv/git-mirror; ls /srv/git-mirror
# every mirror is a consistent repo
for d in /srv/git-mirror/*.git; do git -C "$d" fsck --connectivity-only --no-progress 2>&1 | grep -v '^dangling' | grep . && echo "^^ $d"; done; echo fsck finished
# LFS objects present (170 on 2026-11-13; the fetch log says 171 because two pointers share one object)
find /srv/git-mirror/kanokgan-work.git/lfs/objects -type f | wc -l
# the NAS holds the same files (as kanokgan, no sudo)
rclone check /srv/git-mirror zion-nas:/ZionLabs/Git/GitHub --one-way
```

## Restore

Any machine with `git` and `git-lfs`, no network needed once the folder is local:

```sh
# 1. get the folder from the NAS (Finder/SMB, or rclone), onto a local disk
rclone copy zion-nas:/ZionLabs/Git/GitHub/kanokgan-work.git ./kanokgan-work.git
# 2. a working copy with the real LFS files
git clone ./kanokgan-work.git kanokgan-work
cd kanokgan-work && git lfs pull
```
To move a repo to a new host (GitHub again, GitLab, Forgejo): from inside the bare folder, `git push --mirror <new-url>` and then `git lfs push --all <new-url>`. A point in time other than last night: take the folder from a Synology snapshot of `ZionLabs` instead.

Fallback if `git lfs pull` cannot read the local folder (it could on 2026-11-13 with git-lfs 3.8.1): copy the objects by hand, then check them out.
```sh
mkdir -p .git/lfs && cp -R ../kanokgan-work.git/lfs/objects .git/lfs/ && git lfs checkout
```

## Restore test

**Passed 2026-11-13** on the Mac (git-lfs 3.8.1), from the NAS copy of the first nightly-job output: `kanokgan-work.git` copied from the mounted share `/Volumes/ZionLabs/Git/GitHub/` (1.4 GB), cloned, `git lfs pull`: every LFS file listed with `*` (real content, not a pointer). `git lfs fetch --all` from the mirror: 170 objects in the clone, the same as the mirror.

To repeat it (yearly, or after a git-lfs upgrade):
```sh
mkdir -p ~/restore-test
cp -R /Volumes/ZionLabs/Git/GitHub/kanokgan-work.git ~/restore-test/
cd ~/restore-test && git clone kanokgan-work.git kanokgan-work && cd kanokgan-work && git lfs pull
git lfs ls-files | head
git lfs fetch --all && find .git/lfs/objects -type f | wc -l
cd ~ && rm -rf ~/restore-test
```
Every line of `ls-files` must show `*`, and the count must equal `find <mirror>/lfs/objects -type f | wc -l`. Paste the commands without comments: zsh does not treat `#` as a comment when typing commands. Record the date here and in [docs/migration/README.md](../migration/README.md).

## Token rotation

Create a new token with the same settings (Setup, step 1), replace the file's content (step 2, including the check), and delete the old token on GitHub. No restart: the script reads the file on each run. Run `sudo systemctl start github-mirror.service` to confirm.

## Open items

- No alert when a night fails, and none when the token expires, until the backup-job metrics exist ([monitoring.md](monitoring.md), stage 3). Until then: the journal, and a calendar reminder for the token.
- GitLab repos (small, left out on 2026-11-13). The script would need a second source list and token.
