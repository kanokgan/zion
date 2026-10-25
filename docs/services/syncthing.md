# Syncthing

The Lenovo as one more device in the owner's Syncthing network. Its job today: keep the Obsidian vault used by the browser Obsidian ([obsidian.md](obsidian.md)) in sync with the owner's other devices (Macs, PCs, NAS units, Android and iOS devices, a handheld). Without it the vault on the Lenovo is a disconnected copy.

## What runs where

| | Lenovo (`extreme`) |
|---|---|
| Image | `syncthing/syncthing:2.1.7` (amd64 and arm64 published) |
| Config | host directory `/srv/syncthing/config` (static PV/PVC `syncthing-config`, `Retain`), mounted at `/var/syncthing/config`: the device identity, device list and folder list |
| Data | the Obsidian vault, host directory `/srv/obsidian/vault` (PV/PVC `syncthing-vault`), mounted at `/sync/obsidian-vault`. The browser Obsidian mounts the same folder |
| Access | tailnet only: admin page `https://syncthing-ubuntu-extreme.dove-komodo.ts.net`, sync port `tcp://syncthing-ubuntu-extreme.dove-komodo.ts.net:22000` (Tailscale sidecar, `TCPForward`). No public hostname, no NodePort |
| Other devices | those on the tailnet connect to the address above; those that cannot (for example a work phone that blocks Tailscale) reach the Lenovo through Syncthing's relays, which need only outbound connections |
| Mini | none |

Manifests: `apps/base/syncthing/`, `apps/extreme/syncthing/`. The `.stignore` of the vault folder is seeded from the owner's main ignore list (ConfigMap `syncthing-seed`) the first time only, if the folder has none; later edits in the admin page are kept.

## Rules

- **Only add folders whose path is a mounted volume.** A folder added under any other path is written to the container's temporary disk and is gone at the next restart. To sync another folder, add its volume in `apps/extreme/syncthing/volumes.yaml` and the base manifest first, then add it in the admin page.
- **The admin page has a password only after you set one.** Do it on the first visit. It is reachable only on the tailnet, but a Syncthing admin can add any device and share any folder.
- **Syncthing is not a backup.** Deletes sync too. The protection is the other devices' copies and the file versioning set on the Lenovo's folder (below).
- **Avoid editing the same note on two devices at once.** Syncthing then keeps the losing version as a `*.sync-conflict-*` file next to the note. The seeded `.stignore` lists `*.sync-conflict-*`, so those files are not synced to other devices: they stay on the device where the conflict happened (on the Lenovo, in `/srv/obsidian/vault`). If a note looks like it lost an edit, look for one there.

## Setup (run by the owner)

1. On the Lenovo, create the config folder (the container runs as UID 1000):
   ```sh
   sudo install -d -o kanokgan -g kanokgan -m 0750 /srv/syncthing /srv/syncthing/config
   ls -ld /srv/obsidian/vault        # must already exist, with the vault copy
   ```
2. Secret: `apps/extreme/syncthing/tailscale-auth.sops.yaml` holds a Tailscale auth key (placeholder until you replace it; same method as the other apps: edit the plain placeholder, `sops --encrypt --in-place <file>` once, `sops <file>` for later changes; never push a placeholder).
3. Check, commit and push: `kubectl kustomize apps/extreme > /dev/null && echo ok`.
4. First visit to `https://syncthing-ubuntu-extreme.dove-komodo.ts.net`:
   - Actions, Settings, GUI: set a user name and a long password.
   - Actions, Settings, General: Default Folder Path `/sync`.
   - Actions, Settings, Connections: leave global discovery and relays on (the relays are how some devices reach it). NAT traversal can be turned off: it does nothing inside a cluster.
   - Actions, Show ID: this is the Lenovo's device ID (not a secret).

## Join the vault from zero

The vault on the Lenovo started as a one-off copy that Obsidian had opened, so it can differ in a few files from the real one (Obsidian rewrites some `.obsidian` files). To avoid any conflict, the copy is emptied and Syncthing fills it from the network (owner's decision, 2026-10-25). An empty folder is safe: Syncthing sees nothing locally and downloads; it does not turn missing files into deletions for the other devices.

1. Before wiping, confirm the real vault still exists on the network (the NAS copy and the other devices). Then empty the Lenovo's copy, keeping the folder itself (deleting the folder would leave the running pods with a stale mount):
   ```sh
   find /srv/obsidian/vault -mindepth 1 -delete
   kubectl --context extreme -n syncthing rollout restart deploy/syncthing    # seeds .stignore again
   ```
2. On one always-on device of the network (the NAS, or your main hub): Add Remote Device with the Lenovo's ID. Under Advanced, Addresses: `tcp://syncthing-ubuntu-extreme.dove-komodo.ts.net:22000, dynamic`. Do not make it an Introducer. Share the vault folder with it, and only that folder.
3. On the Lenovo: accept the device, then accept the folder with the path `/sync/obsidian-vault`. Folder Type stays Send & Receive. Edit the folder, File Versioning **Staggered** (for example keep 30 days). Versions are kept in `.stversions` inside the folder.
4. Wait until the folder is "Up to Date" (about 2.8 GB).
5. Restart the browser Obsidian so it reopens the vault: `kubectl --context extreme -n obsidian rollout restart deploy/obsidian`.
6. Other devices do not each need the Lenovo: changes travel through the hub as long as the hub is online. Add the Lenovo directly on a device only if you want a direct link.

## Verify

```sh
kubectl --context extreme -n syncthing get pods,pvc          # pod 2/2 Running, PVC Bound
kubectl --context extreme -n syncthing logs deploy/syncthing -c syncthing --tail=30
ls -la /srv/obsidian/vault/.stignore /srv/syncthing/config   # the seeded ignore file, the config files
```
Then: change a note in the browser Obsidian and see it on another device within a minute; change a note on another device and see it in the browser Obsidian (it should refresh by itself; if it does not, reload the app with Ctrl+R and tell me).

## Backup and restore

The vault: copies on the other devices, plus the Lenovo's staggered versions; a restore is "let Syncthing resync" or restore a version from the admin page. The config in `/srv/syncthing/config` is the Lenovo's identity (certificate and key, in no repo by design): if it is lost, the Lenovo gets a new device ID and each device must accept it again; nothing in the vault is lost. Backup of that folder is an open item. Restore test: **not done yet**.

## Runbook: upgrade

Version lives in the `images:` block of `apps/extreme/syncthing/kustomization.yaml`. Read the release notes (`https://github.com/syncthing/syncthing/releases`) because a major version can migrate its database, confirm the tag exists (`docker manifest inspect syncthing/syncthing:<tag>`), change `newTag`, commit `syncthing: upgrade to X.Y.Z`. Rollback after a database migration may need the old version's data restored from a copy of `/srv/syncthing/config`: copy it first.

## Open items

- Everything in Setup (nothing is deployed yet).
- Back up `/srv/syncthing/config`.
- Optional ignore patterns for Obsidian's noisy files (for example `.obsidian/workspace*.json`), if they cause churn; the owner's ignore list was used as is.
