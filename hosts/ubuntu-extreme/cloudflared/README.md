# cloudflared on ubuntu-extreme

Public access for the Lenovo, like the mini's (`hosts/macos-mini/README.md`): `cloudflared` runs on the host, not in the cluster (ADR 0009). It reaches the apps through NodePorts on `localhost`: Immich 30283, Actual 30506 (`apps/extreme/*/nodeport.yaml`).

## Setup (once, run by the owner)

1. Cloudflare dashboard, Zero Trust, Networks, Tunnels: create the tunnel **`ubuntu-extreme`** (type cloudflared) and copy its token.
2. On the Lenovo, install `cloudflared` from Cloudflare's apt repository and create a service user:
   ```sh
   sudo useradd --system --no-create-home --shell /usr/sbin/nologin cloudflared
   sudo install -d -m 0750 -o root -g cloudflared /etc/cloudflared
   sudo install -m 0640 -o root -g cloudflared /dev/stdin /etc/cloudflared/ubuntu-extreme.token   # paste the token, then Ctrl-D
   sudo cp cloudflared.service /etc/systemd/system/
   sudo systemctl daemon-reload && sudo systemctl enable --now cloudflared
   ```
3. Do **not** add the public hostnames yet. At the cutover, move `immich.kanokgan.com` and `actual.kanokgan.com` from the tunnel `macos-mini` to `ubuntu-extreme` (service `http://localhost:30283` and `http://localhost:30506`). A hostname can point at one tunnel only; if the dashboard complains, fix the DNS record first (the error 1016 on 2026-10-17 was a record created under the wrong tunnel).

## Verify

```sh
systemctl is-active cloudflared
journalctl -u cloudflared -n 20 --no-pager          # "Registered tunnel connection" lines
curl -s http://localhost:30283/api/server/ping       # {"res":"pong"} once Immich runs
```
The tunnel shows Healthy in the dashboard once the connector is registered.

## Not in Git

The token. Rotate it in the dashboard if it is ever shown in a log or a chat.
