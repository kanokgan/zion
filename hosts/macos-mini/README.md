# macos-mini: Mac mini host-level setup

Things that run directly on macOS, outside the Lima VM and outside Flux (ADR 0008). Keep this current: if it is not here, a rebuilt mini will not have it.

## Installed
| What | How installed | Notes |
|---|---|---|
| Plex Media Server | app: `/Applications/Plex Media Server.app` | exposed as `plex.kanokgan.com` via the `macos-mini` tunnel, service URL `http://localhost:32400` |
| Jellyfin | app: `/Applications/Jellyfin.app` | exposed as `jellyfin.kanokgan.com` via the `macos-mini` tunnel, service URL `http://localhost:8096` (the Lenovo's `home-brain` tunnel also has a `jellyfin` route; it is not migrated and goes away when the Lenovo is wiped, so make sure DNS points at `macos-mini`) |
| cloudflared | Homebrew `cloudflared` (version 2026.9.0 on 2026-10-12) | system LaunchDaemon `/Library/LaunchDaemons/com.cloudflare.cloudflared.plist`, runs `tunnel run --token-file ...`; tunnel `macos-mini`; token file is outside the repo and never committed |
| Public hostnames (tunnel `macos-mini`) | Cloudflare dashboard | `immich.kanokgan.com` -> `http://localhost:30283` (NodePort Service forwarded by Lima, see `lima/zion.yaml`). `actual.kanokgan.com` is NOT on this tunnel: Actual is served by the Lenovo's tunnel `ubuntu-extreme`, and the mini's copy is a stale standby. Plex and Jellyfin hostnames are on this tunnel too (rows above) |
| Tailscale | macOS app | device `macos-mini`; `tailscale serve` publishes the k3s API on tailnet port 6443 (Lens) |
| Lima | Homebrew `lima` | VM `zion` (see `hosts/macos-mini/lima/zion.yaml`). The cluster is called `mini` (kubectl context, `clusters/mini/`, since 2026-10-20), but the VM and the k3s node keep the name `zion`: local-path volumes are tied to the node name, so renaming the node would orphan them |

## After a reboot
FileVault is on, so nothing user-level starts until someone logs in. The Lima VM `zion` (k3s, Immich, Actual) does not start by itself: on 2026-10-18, after a reboot and login, `limactl list` showed it `Stopped` and every service on the cluster was down, even though the external drive was mounted.

1. Log in and make sure `/Volumes/HighSpeed2T` is mounted (`ls /Volumes/HighSpeed2T/Immich/Backup`). Lima refuses to start without it (see `mounts` in `lima/zion.yaml`).
2. `limactl start zion`
3. Verify: `limactl list` shows `Running`, `kubectl --context mini get nodes` shows `Ready`, `curl -sI http://localhost:30283` answers.

Autostart is not set up yet. Candidate: `limactl start-at-login zion` (a launchd agent that runs after login, which fits FileVault). Untested: confirm it exists in the installed Lima version, that the VM comes up after a reboot, and what happens if the drive mounts late (the agent may not retry). Record the result here.

## To find out and record
- Whether Plex and Jellyfin are meant to be running now, and how they start (login item, launchd, manual). Both were not listening on 2026-10-12.
- Where each keeps its config/database and where its media is mounted (NAS over SMB, which path).
- How they are backed up and how a restore works.
- FileVault is on, so after a reboot nothing here starts until the disk is unlocked.

## Not in Git by design
Secrets (tunnel token, Tailscale auth) stay out of the repo.
