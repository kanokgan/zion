# Upgrading cloudflared

Three `cloudflared` connectors carry the public hostnames on kanokgan.com. None of them updates itself (`--no-autoupdate` is on purpose, see below), so each is bumped by hand when Cloudflare emails a minimum version.

| Machine | Tunnel | Installed as | Upgrade with |
|---|---|---|---|
| `ubuntu-extreme` (Lenovo) | `ubuntu-extreme` | apt package, systemd unit `cloudflared` ([setup](../../hosts/ubuntu-extreme/cloudflared/README.md)) | apt |
| `macos-mini` | `macos-mini` | Homebrew, LaunchDaemon `com.cloudflare.cloudflared` ([setup](../../hosts/macos-mini/README.md)) | brew |
| Synology DS923+ | NAS tunnel | Container Manager project `cloudflare-tunnel`, image `cloudflare/cloudflared:latest` | re-pull the image |

Risk: a restart drops that tunnel's connections for a few seconds (public Immich, Actual and SilverBullet on the Lenovo; Plex and Jellyfin on the mini; whatever the NAS tunnel serves). Nothing is lost and the connector reconnects by itself. Do one machine at a time.

## Before: check the version

```sh
cloudflared --version        # on the Lenovo and the mini
```

On the NAS, read the version in the container log (Container Manager, Container, the tunnel container, Log) or in the tunnel's connector list in the Cloudflare dashboard.

## ubuntu-extreme

```sh
sudo apt update
apt-cache policy cloudflared                      # Candidate must be the version you want
sudo apt install --only-upgrade cloudflared
sudo systemctl restart cloudflared
```

## macos-mini

```sh
brew update && brew upgrade cloudflared
sudo launchctl kickstart -k system/com.cloudflare.cloudflared
```

## Synology NAS (Container Manager)

A restart never updates a container: it is tied to the image it was created from, and `latest` is only looked up when the image is pulled. The project's data lives in `/volume1/docker/cloudflare-tunnel`, not in the image, so removing the image loses nothing.

1. Container Manager, Project, select `cloudflare-tunnel`, Action, **Stop**.
2. Image, select `cloudflare/cloudflared:latest`, Action, **Delete**.
3. Registry, search `cloudflare/cloudflared`, **Download**, tag `latest`.
4. Project, `cloudflare-tunnel`, Action, **Start**. The project recreates the container from the new image.

## Verify

```sh
cloudflared --version                              # Lenovo and mini: the new version
systemctl is-active cloudflared                    # Lenovo
journalctl -u cloudflared -n 20 --no-pager         # Lenovo: "Registered tunnel connection" lines
curl -sI https://immich.kanokgan.com | head -1     # Lenovo tunnel
curl -sI https://plex.kanokgan.com | head -1       # mini tunnel
```

On the NAS, the container log shows the new version at startup. In the Cloudflare dashboard (Zero Trust, Networks, Tunnels) every tunnel shows Healthy and its connector shows the new version.

## Why autoupdate is off

- **Docker image:** the entrypoint sets `--no-autoupdate`. A container is replaced, not patched in place, so a self-updated binary would be lost on the next recreate.
- **apt and Homebrew:** the packaged builds are meant to be updated through the package manager. On the Lenovo the unit also runs as the `cloudflared` user with `ProtectSystem=strict`, so `/usr/bin` is read-only to it.
- **Intent:** an unattended update restarts the tunnel at a time nobody chose, and the repo prefers known versions to "whatever was pulled last". Cloudflare gives advance notice by email.

## Version log

| Date | Lenovo | mini | NAS | Reason |
|---|---|---|---|---|
| 2026-10-28 | 2026.10.5 | 2026.10.5 | `latest` pulled the same day | Cloudflare email: upgrade to 2026.10.3 or later |
