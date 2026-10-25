# Obsidian in the browser

The real Obsidian desktop app, run in a container and streamed to the browser (linuxserver image, Selkies). It exists because the work laptop blocks installing apps, so a browser is the only way in. Personal vault only. Decision date 2026-10-25, after trying SilverBullet (a web editor that needs custom plugins for basics).

**Status: phase 1, a trial on a COPY of the vault.** The original vault (NAS, synced with Syncthing to the other devices) is never written by this app. Phase 2 (where the real vault lives) is decided only if the trial works.

## What runs where

| | Lenovo (`extreme`) |
|---|---|
| Image | `lscr.io/linuxserver/obsidian:1.14.4` (amd64 and arm64 published) |
| Data | host directory `/srv/obsidian` (static PV/PVC `obsidian-data`, `Retain`): `config/` mounted at `/config` (Obsidian settings), `vault/` mounted at `/vault` (the copy) |
| Login | basic auth (`CUSTOM_USER` / `PASSWORD` from `obsidian-auth.sops.yaml`), plus Cloudflare Access on the public name |
| Tailscale (debug, tailnet only) | sidecar `obsidian-ubuntu-extreme`: `https://obsidian-ubuntu-extreme.dove-komodo.ts.net` |
| Public | `obsidian.kanokgan.com` via tunnel `ubuntu-extreme`, service `http://localhost:30320` -> NodePort Service `obsidian-nodeport` |
| Mini | none |

Manifests: `apps/base/obsidian/`, `apps/extreme/obsidian/`. Resources: 1 GiB requested, 3 GiB limit (Electron on a 10,000-file vault).

## Security (read this)

The web page includes a terminal with **passwordless sudo**, so anyone who reaches it is root inside the container and can read, change or delete the vault. Upstream says not to expose it to the internet without strong authentication. Therefore:
- `obsidian.kanokgan.com` must sit behind **Cloudflare Access** before the tunnel route is added (owner's decision, 2026-10-25, unlike SilverBullet and Actual). An app that is not Access-protected must not be routed.
- Basic auth stays on as a second layer, with a long random password.
- The pod is not privileged and has no host mounts other than `/srv/obsidian`. The vault copy holds personal files only; the original is only read.
- Cloudflare terminates TLS and can see the session.

## Setup (run by the owner)

1. **Directories on the Lenovo** (the container runs as UID 1000):
   ```sh
   sudo install -d -o kanokgan -g kanokgan -m 0750 /srv/obsidian /srv/obsidian/config /srv/obsidian/vault
   ```
2. **Copy the vault.** Read the original, write only to the copy; exclude Syncthing's bookkeeping so the copy cannot be mistaken for a synced folder. From the m5 (or wherever the vault is reachable), for example:
   ```sh
   rsync -a --info=progress2 --exclude ".stfolder" --exclude ".stversions" <path-to-vault>/ kanokgan@ubuntu-extreme:/srv/obsidian/vault/
   ```
   Check `du -sh /srv/obsidian/vault` (about 10 GB) and `find /srv/obsidian/vault -type f | wc -l` (10,000+).
3. **Secrets** (placeholder files in `apps/extreme/obsidian/`; same method as SilverBullet: edit the plain placeholder, then `sops --encrypt --in-place <file>` once, `sops <file>` for later changes; never push a plain or placeholder file, Flux then fails to decrypt and holds back every app):
   - `obsidian-auth.sops.yaml`: `CUSTOM_USER` (a username) and `PASSWORD` (`openssl rand -base64 24`).
   - `tailscale-auth.sops.yaml`: a Tailscale auth key (not ephemeral).
4. **Check, commit, push:** `kubectl kustomize apps/extreme > /dev/null && echo ok`.
5. **Test on the tailnet name** `https://obsidian-ubuntu-extreme.dove-komodo.ts.net` (log in with the basic-auth user): the Obsidian window appears; choose "Open folder as vault" and select `/vault`.
6. **Cloudflare Access first, then the route.** In Cloudflare Zero Trust, Access, Applications, add a self-hosted application for `obsidian.kanokgan.com` with one policy: Allow, Emails, your own address (login by one-time PIN). Only then add the public hostname `obsidian.kanokgan.com` -> `http://localhost:30320` on the tunnel `ubuntu-extreme`. Test in a private window: you must get the Cloudflare login before anything from Obsidian.

## Verify

```sh
kubectl --context extreme -n obsidian get pods,pvc          # pod 2/2 Running, PVC Bound
kubectl --context extreme -n obsidian logs deploy/obsidian -c obsidian --tail=30
```
In the app: open a few notes, search for a word, open a note with images, scroll the graph. Judge speed and typing from the work laptop for a few days. If the pod crash-loops or Obsidian will not start, tell me the log; a seccomp or sandbox setting may need adjusting (the upstream docs do not mention one).

## Limits to expect

It is a remote desktop: some latency, copy and paste goes through the browser, a few shortcuts belong to the browser, and it is poor on a phone (use the Android app for that). Obsidian is free for personal use; use on company notes would need a commercial license.

## Phase 2 (only if the trial works)

The trial works (2026-10-25). The Lenovo's copy becomes another Syncthing device (an app on the Lenovo sharing `/srv/obsidian/vault` with the owner's other devices, see [syncthing.md](syncthing.md)), so edits in the browser reach every device. Until it is joined, the copy is disposable and edits made in it do not reach the real vault. Syncthing conflicts are the risk to watch: avoid editing the same note on two devices at once.

## Backup and restore

Phase 1 needs none: the vault copy is disposable and the original is untouched. Phase 2 needs a backup (the vault stays on the NAS and is copied by Syncthing to the other devices; a nightly copy to the NAS, as for the other apps, to be decided).

## Runbook: upgrade

Version lives in the `images:` block of `apps/extreme/obsidian/kustomization.yaml`. Read the image's release notes, confirm the tag exists (`docker manifest inspect lscr.io/linuxserver/obsidian:<tag>`), change `newTag`, commit `obsidian: upgrade to X.Y.Z`. Rollback: revert the commit.

## Open items

- Everything in Setup (nothing is deployed yet).
- Decide after the trial: keep, change, or remove.
- Phase 2 design and backup.
