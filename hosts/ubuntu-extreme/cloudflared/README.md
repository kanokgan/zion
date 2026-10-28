# cloudflared on ubuntu-extreme

Public access for the Lenovo, like the mini's (`hosts/macos-mini/README.md`): `cloudflared` runs on the host, not in the cluster (ADR 0009). It reaches the apps through NodePorts on `localhost`: Immich 30283, Actual 30506, SilverBullet 30300, Obsidian 30320 (`apps/extreme/*/nodeport.yaml`). Current routes on the tunnel `ubuntu-extreme` (managed in the Cloudflare dashboard, not in Git):

| Hostname | Service | Note |
|---|---|---|
| `immich.kanokgan.com` | `http://localhost:30283` | [immich.md](../../../docs/services/immich.md) |
| `actual.kanokgan.com` | `http://localhost:30506` | [actual.md](../../../docs/services/actual.md) |
| `silverbullet.kanokgan.com` | `http://localhost:30300` | added 2026-10-25 after its tailnet test passed ([silverbullet.md](../../../docs/services/silverbullet.md)) |
| `obsidian.kanokgan.com` | `http://localhost:30320` | behind a Cloudflare Access policy, which must exist before the route ([obsidian.md](../../../docs/services/obsidian.md)) |

## Setup (once, run by the owner)

1. Cloudflare dashboard, Zero Trust, Networks, Tunnels: create the tunnel **`ubuntu-extreme`** (type cloudflared) and copy its token.
2. On the Lenovo, install `cloudflared` from Cloudflare's apt repository and create a service user:
   ```sh
   sudo useradd --system --no-create-home --shell /usr/sbin/nologin cloudflared
   sudo install -d -m 0750 -o root -g cloudflared /etc/cloudflared
   read -rs T; printf '%s\n' "$T" | sudo install -m 0640 -o root -g cloudflared /dev/stdin /etc/cloudflared/ubuntu-extreme.token; unset T   # paste the token; nothing is echoed
   sudo cp cloudflared.service /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now cloudflared
   ```
3. Add a public hostname only when its service runs and has passed its tailnet test. When moving one from another tunnel (as `immich.kanokgan.com` and `actual.kanokgan.com` were moved from `macos-mini`), remember that a hostname can point at one tunnel only; if the dashboard complains, fix the DNS record first (the error 1016 on 2026-10-17 was a record created under the wrong tunnel). Adding a route before the connector exists gives Cloudflare error 1033.

## Verify

```sh
systemctl is-active cloudflared
journalctl -u cloudflared -n 20 --no-pager          # "Registered tunnel connection" lines
curl -s http://localhost:30283/api/server/ping       # {"res":"pong"} once Immich runs
```
The tunnel shows Healthy in the dashboard once the connector is registered (`cloudflared` 2026.10.5 since 2026-10-28).

## Upgrading

`--no-autoupdate` is set on purpose, so the package is bumped by hand: `sudo apt update && sudo apt install --only-upgrade cloudflared && sudo systemctl restart cloudflared`. Full procedure for all three connectors, with verify steps and a version log: [docs/runbooks/upgrading-cloudflared.md](../../../docs/runbooks/upgrading-cloudflared.md).

## Not in Git

The token. Rotate it in the dashboard if it is ever shown in a log or a chat.
