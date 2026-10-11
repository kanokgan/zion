# 0008. Plex and Jellyfin run natively on the Mac mini

- Status: accepted
- Date: 2026-10-12

## Context
ADR 0002 planned to migrate Plex and Jellyfin into Kubernetes and noted they would likely lose hardware transcoding inside a VM. The Mac mini already runs both as native macOS apps (`Plex Media Server.app`, `Jellyfin.app`), exposed through a Cloudflare tunnel named `macos-mini` (public hostnames `plex.kanokgan.com` and `jellyfin.kanokgan.com`). The tunnel's connector is `cloudflared` installed with Homebrew, running as a system LaunchDaemon (`/Library/LaunchDaemons/com.cloudflare.cloudflared.plist`) with `--token-file`, so the token is not in the plist.

The Lenovo cluster has its own tunnel, `home-brain`, which carries Immich, Jellyfin, Actual Budget and a stale Argo CD route. The two tunnels are separate. `jellyfin.kanokgan.com` appears as a route on both; DNS can point it at only one of them.

## Decision
Plex and Jellyfin stay native on the Mac mini and are not moved into Kubernetes. They are documented in the repo under `hosts/macos-mini/` instead of being managed by Flux. The `macos-mini` tunnel and its `cloudflared` daemon are host-level too.

## Alternatives considered
- Run them in the Lima VM through Kubernetes: everything in Git and Flux, but software transcoding only (no Apple VideoToolbox), on a 5 GiB VM that also runs Immich.
- Keep them on the Lenovo until its rebuild: no change for now, but the Lenovo is being rebuilt, and the mini already has them working.

## Consequences
- Hardware transcoding is kept (VideoToolbox), which was the main cost of the VM route.
- These two services are not rebuildable from Flux. A rebuilt mini needs the manual steps in `hosts/macos-mini/`. This is a deliberate exception to "everything in Git".
- Their config and library databases need a documented backup and restore. Not designed yet.
- Updates are manual (app updaters).
- Media access (NAS mounts) happens on the host, not in the VM.
- At the check on 2026-10-12, neither app was listening on its default port (32400, 8096) and there were no launchd jobs for them. Whether they are meant to be running, and how they start, still has to be confirmed.
- The Lenovo's Jellyfin and its `home-brain` Jellyfin route are not migrated: the Lenovo is wiped and rebuilt from the repo later, so that Jellyfin's config and watch history are dropped. Until then, `jellyfin.kanokgan.com` must point at exactly one tunnel (it should be `macos-mini`).
- ADR 0002's consequence about losing hardware transcoding is superseded for Plex and Jellyfin by this ADR.
- If FileVault stays on, these also stay offline after a reboot until the disk is unlocked.
