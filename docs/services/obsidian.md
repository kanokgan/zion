# Obsidian in the browser

Obsidian's own interface, run as a web app in the browser with [Ignis](https://github.com/Nystik-gh/ignis): a small Node server reads and writes the vault on the Lenovo, and the Obsidian UI runs in the browser tab. It exists because the work laptop blocks installing apps, so a browser is the only way in. Personal vault only.

**Status: switching to Ignis (2026-11-13).** From 2026-10-25 to 2026-11-13 this was the linuxserver image: the Obsidian desktop app streamed as a remote desktop (Selkies). It was replaced because a remote desktop in a browser tab keeps colliding with the browser: shortcuts such as Ctrl/Cmd+W closed the browser tab instead of the Obsidian tab, there was typing latency, and the clipboard went through a relay. Alternatives looked at: SilverBullet (already on the vault, but not Obsidian), Browsidian (a basic editor, no license, no image, no login).

Note: a browser never hands Ctrl/Cmd+W, T, N or Q to a page, so Ignis does not fix those keys by itself. Install the page as an app (Chrome/Edge: menu, "Install page as app", or Ignis's own install prompt) so it opens in its own window, and rebind Obsidian's "close tab" (Settings, Hotkeys) if it still collides.

## What runs where

| | Lenovo (`extreme`) |
|---|---|
| Image | `nobbe/ignis:0.9.0` (amd64 and arm64), which downloads and pins Obsidian 1.14.4 on first start; `caddy:2.11.9-alpine` as the basic-auth sidecar `auth-proxy` |
| Data | host directory `/srv/obsidian` (static PV/PVC `obsidian-data`, `Retain`): `vault/` at `/vaults/vault` (the live vault, kept in sync by Syncthing), `ignis/data` at `/app/data` (Ignis settings), `ignis/app` at `/app/obsidian-app` (the downloaded Obsidian). `config/` is the old linuxserver settings, unused, to delete after the soak |
| Login | Ignis has none. Public path: Cloudflare Access, then basic auth in `auth-proxy` (`CUSTOM_USER` and `BASIC_AUTH_HASH` from `obsidian-auth.sops.yaml`) |
| Tailscale (debug, tailnet only) | sidecar `obsidian-ubuntu-extreme`: `https://obsidian-ubuntu-extreme.dove-komodo.ts.net`, straight to Ignis on 8080 (no basic auth; the tailnet is the access control) |
| Public | `obsidian.kanokgan.com` via tunnel `ubuntu-extreme`, service `http://localhost:30320` -> NodePort Service `obsidian-nodeport` -> `auth-proxy` (3000) -> Ignis (8080) |
| Mini | none |

Manifests: `apps/base/obsidian/`, `apps/extreme/obsidian/`. Resources: Ignis 256 MiB requested, 1 GiB limit; the heavy part (Obsidian itself) now runs in the browser, not in the pod.

## Security (read this)

Ignis has **no login**: anyone who reaches port 8080 can read, change or delete the whole vault. Therefore:
- `obsidian.kanokgan.com` stays behind **Cloudflare Access** (one policy: Allow, your own email, one-time PIN). An app that is not Access-protected must not be routed.
- The NodePort listens on every interface of the Lenovo, LAN included, so it points at the **basic-auth sidecar**, never at Ignis. Basic auth uses a bcrypt hash in the Secret, not the password.
- Port 8080 is reachable only inside the pod network and through the Tailscale sidecar.
- `WS_ORIGINS` limits the vault-change WebSocket to the two hostnames above.
- Ignis has a cross-origin proxy (`/api/proxy`) for plugins. By default it refuses private addresses; leave `PROXY_ALLOW_PRIVATE_HOSTS` unset, and turn the proxy off in Ignis settings if no plugin needs it.
- Unlike the linuxserver image there is no terminal and no sudo in the page. Community plugins still run with full access to the vault, as on the desktop.
- Cloudflare terminates TLS and can see the session; so can a company TLS-inspecting proxy on the work laptop.

## Setup (done by the owner; the steps for a rebuild)

1. **Directories on the Lenovo** (the pod writes as UID 1000):
   ```sh
   sudo install -d -o kanokgan -g kanokgan -m 0750 /srv/obsidian /srv/obsidian/vault /srv/obsidian/ignis /srv/obsidian/ignis/data /srv/obsidian/ignis/app
   ```
2. **Fill the vault**: let Syncthing fill an empty `vault/` folder ([syncthing.md](syncthing.md), "Join the vault from zero").
3. **Secrets** (in `apps/extreme/obsidian/`; never push a plain or placeholder file, Flux then fails to decrypt and holds back every app):
   - `obsidian-auth.sops.yaml`: `CUSTOM_USER` (a username) and `BASIC_AUTH_HASH`, a bcrypt hash of a long random password. Make the hash on the Mac without the password landing in shell history: `htpasswd -nBC 12 "" | tr -d ':\n'` (it prompts twice; macOS ships `htpasswd`), then `sops apps/extreme/obsidian/obsidian-auth.sops.yaml` and paste it as the value. Keep the password in your password manager.
   - `tailscale-auth.sops.yaml`: a Tailscale auth key (not ephemeral).
4. **Check, commit, push:** `kubectl kustomize apps/extreme > /dev/null && echo ok`.
5. **Test on the tailnet name** `https://obsidian-ubuntu-extreme.dove-komodo.ts.net`: the first start downloads Obsidian (a minute or two), then the vault `vault` opens.
6. **Cloudflare Access first, then the route** (already in place; for a rebuild): in Cloudflare Zero Trust, Access, Applications, a self-hosted application for `obsidian.kanokgan.com` with one policy, Allow, Emails, your own address. Only then the public hostname `obsidian.kanokgan.com` -> `http://localhost:30320` on the tunnel `ubuntu-extreme`. Test in a private window: Cloudflare login, then the basic-auth prompt, then Obsidian. Repeat after any change to the application or the tunnel.

## Switch from linuxserver to Ignis (2026-11-13)

Risk: Ignis opens the live vault, which Syncthing copies to every device. A bad write reaches all of them. Safety net: Syncthing's staggered versions on the Lenovo and the copies on the other devices; check that at least one other device is in sync before starting. The switch itself is a short outage (the old pod stops, then Ignis starts and downloads Obsidian).

1. Prepare on the Lenovo: the `ignis` directories from Setup step 1 (only the two new ones are missing), and check the inotify limit, since Ignis, Syncthing and SilverBullet all watch the same 10,000+ files as the same user: `cat /proc/sys/fs/inotify/max_user_watches` (fine if it is well above 100000).
2. Add `BASIC_AUTH_HASH` to `obsidian-auth.sops.yaml` (Setup step 3). Remove `PASSWORD` at the same time; nothing reads it any more.
3. Commit the manifests and the secret together, push. Flux applies; `Recreate` stops the linuxserver pod before Ignis starts.
4. Verify (below). Edit a test note in the browser and see it on another device; edit on another device and see it in the browser.
5. Soak about 2 weeks. Then `sudo rm -r /srv/obsidian/config` (the linuxserver settings).

Rollback: revert the commit (and restore `PASSWORD` in the secret). `/srv/obsidian/config` is kept until the soak ends, so the linuxserver image comes back as it was.

## Verify

```sh
kubectl --context extreme -n obsidian get pods,pvc          # pod 3/3 Running, PVC Bound
kubectl --context extreme -n obsidian logs deploy/obsidian -c ignis --tail=30
kubectl --context extreme -n obsidian logs deploy/obsidian -c auth-proxy --tail=10
```
On the Lenovo: `curl -s -o /dev/null -w '%{http_code}\n' http://localhost:30320/` must print `401` (basic auth is in front). In the app: open a few notes, search for a word, open a note with images, check that your community plugins load (those that need Node native modules or `child_process`, such as obsidian-git, do not; see Ignis's plugin compatibility page).

If `auth-proxy` fails with `operation not permitted`, the container's capability settings are the cause (the caddy binary carries `cap_net_bind_service`); say so before loosening them.

## Limits to expect

- Browser shortcuts win over Obsidian's (see the note at the top).
- Plugins that need Node native modules or `child_process` do not load.
- Ignis is pre-1.0 and maintained by one person; read the changelog before each upgrade.
- Obsidian is free for personal use; use on company notes would need a commercial license.

## Vault sync

Syncthing shares `/srv/obsidian/vault` with the owner's other devices ([syncthing.md](syncthing.md)), so edits in the browser reach every device. Syncthing conflicts are the risk to watch: avoid editing the same note on two devices at once. Syncthing is not a backup: deletes sync too. SilverBullet opens the same folder ([silverbullet.md](silverbullet.md)); keep to one editor per note at a time.

## Backup and restore

The vault exists on the owner's other devices, and the Lenovo's Syncthing folder keeps staggered versions. A restore is "let Syncthing resync" or restore a version from the Syncthing admin page. `/srv/obsidian/ignis` (Ignis settings and the downloaded Obsidian) is not backed up and is recreated on start; Ignis settings made in its UI would need redoing. A nightly copy of the vault to the NAS, as for the other apps, is not decided. Restore test: **not done yet**.

## Runbook: upgrade

Versions live in the `images:` block of `apps/extreme/obsidian/kustomization.yaml`. Each Ignis release pins the Obsidian version it downloads, so upgrading Obsidian means upgrading Ignis (do not set `OBSIDIAN_VERSION`). Read the [changelog](https://ignis.thiefling.com/docs/changelog/), confirm the tag exists (`docker manifest inspect nobbe/ignis:<tag>`), change `newTag`, commit `obsidian: upgrade ignis to X.Y.Z`. Rollback: revert the commit. Caddy: same, tag `X.Y.Z-alpine`.

## Open items

- Do the switch above; record the date and how the hotkeys behave with the page installed as an app.
- Check that "Install page as app" works with basic auth in front. If the browser cannot fetch the web app manifest, exempt that one path from basic auth in the Caddyfile (it is still behind Cloudflare Access).
- Decide whether a nightly NAS copy of the vault is needed on top of the other devices' copies.
- Restore test (resync a vault from the other devices into an empty folder).
- With Ignis, decide whether to keep SilverBullet on the vault as well (one less writer if not).
