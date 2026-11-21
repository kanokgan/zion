# 0011. GitHub backup: portable bare mirrors on the NAS

- Status: accepted
- Date: 2026-11-13

## Context
My repositories live on GitHub (17 repos on 2026-11-13, 16 private, about 0.3 GB of git data) and a few on GitLab. One of them, `kanokgan-work`, keeps slides and course material in Git LFS: about 1.2 GB over its whole history, 170 objects. If GitHub loses data, locks my account, or is down when I need something, I have no copy: local clones on my laptops are partial, and one of them holds only LFS pointer files, not the slides.

I want every GitHub repo copied to my NAS every night, including all LFS objects, in a form I can use on any machine with plain `git` and `git-lfs`, offline, without running any server of mine. The NAS already has snapshots on `ZionLabs`, so point-in-time history is covered there; the mirror itself does not need to keep deleted branches.

## Decision
- **Bare mirrors with their LFS objects inside.** Each repo is a `git clone --mirror`, and `git lfs fetch --all` stores every LFS object of every ref inside the bare repo (`<repo>.git/lfs/objects/`). One folder per repo is the whole backup. Checked on 2026-11-13 with a throwaway repo: `git clone /path/repo.git` followed by `git lfs pull` restores the real files from such a folder, with no network.
- **Only branches and tags.** The mirror fetches `refs/heads/*` and `refs/tags/*`, not GitHub's `refs/pull/*`, so a restore can be pushed to any new host with `git push --mirror`.
- **A host job on the Lenovo**, like the other NAS backup jobs: `hosts/ubuntu-extreme/backup/github-mirror.{sh,service,timer}`, nightly at 05:00. It lists my repos through the GitHub API, so a new repo is picked up without any change; a repo deleted on GitHub is kept and only logged.
- **Working copy on the NVMe, then `rclone sync` to the NAS** (`/srv/git-mirror` to `/ZionLabs/Git/GitHub`). Git is not run directly on the SMB or SFTP share. `sync` (which deletes on the NAS), unlike the other jobs' `copy`: git rewrites files such as `packed-refs` and repacks objects, and a NAS copy that keeps stale files can show a ref at an old commit. History comes from the NAS snapshots. A guard refuses to sync when the local folder holds fewer repos than the NAS, so a lost or empty disk never wipes the backup.
- **Read-only credentials.** A fine-grained GitHub token with read access to contents and metadata of all my repos, in a file readable only by the job's user, outside Git. It is passed to `git` and `git-lfs` through a credential helper in the environment, never on the command line or in a repo's config, so the NAS copy holds no credential.
- **Runs as the owner's user, not root**: the files are created by the job itself, unlike Immich's, which a container writes as root.
- GitLab is left out for now (small); the same script can take a second source later.

## Alternatives considered
- **Forgejo (or Gitea) with pull mirrors:** a web UI and a place to push to if GitHub is down, but its repos depend on Forgejo for LFS (its own object layout outside the bare repo), new repos must be added one by one, and it is one more stateful app to run, back up and upgrade. I do not need a UI for a backup. Revisit if I want to work from my own server during a GitHub outage.
- **A Kubernetes CronJob instead of a systemd timer:** GitOps-managed, but the other NAS jobs are host timers, the token would become a SOPS secret for little gain, and a backup should not depend on the cluster being healthy.
- **`git bundle` files:** one file per repo and easy to copy, but bundles do not carry LFS objects, and each night is a full rewrite.
- **Hosted backup services (for example BackHub):** the data leaves hardware I own, and it costs money.
- **Running git directly on the NAS share:** git needs reliable file locking and renames, which SMB over Tailscale does not guarantee; the nightly copy is fast at this size.

## Consequences
- First run downloads all LFS objects (about 1.2 GB), which counts against GitHub's LFS bandwidth quota; later runs fetch only new objects.
- The token expires (GitHub requires an expiry for fine-grained tokens, up to a year): the job then fails every night until it is replaced. Until the backup-job alert exists (ADR 0010, stage 3) the only signal is the journal, so set a calendar reminder.
- `rclone sync` means a bad night is repaired from a NAS snapshot, not from the folder itself.
- A restore test is part of the definition of done: copy a repo from the NAS to another machine, go offline, clone, `git lfs pull`, open a slide.
