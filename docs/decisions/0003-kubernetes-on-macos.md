# 0003. Kubernetes on macOS: Lima VM running k3s

- Status: accepted
- Date: 2026-10-11

## Context
The Mac mini (Apple silicon, macOS) must run a Kubernetes cluster built only from this repo. macOS cannot run Linux containers natively, so a Linux environment is needed. The legacy cluster `zion-old` runs k3s on Ubuntu, so staying on k3s keeps behaviour familiar.

The mini is the build host for `zion` now and becomes a warm standby for Immich later (ADR 0004); this decision holds for both.

## Decision
Run a Lima VM (`vmType: vz`, aarch64 Ubuntu 24.04) defined in `hosts/macos-mini/lima/zion.yaml`, with a pinned k3s installed by the VM's provision script. The VM should start at boot via launchd; that is not set up yet, because it depends on the FileVault decision (with FileVault on, nothing starts until the disk is unlocked). Only one macOS directory is mounted into the VM: the Immich standby library on the external NVMe, at `/mnt/immich-library` (ADR 0004). The macOS home directory is not shared.

Amended 2026-10-12: originally stated that the VM starts at boot and that no macOS directories are mounted.

## Alternatives considered
- Colima (`--kubernetes`): wraps Lima and starts k3s with one flag; quicker, but hides the VM and k3s settings we want in Git.
- Asahi Linux on bare metal: best performance, but not casually reversible and removes macOS from the mini.
- OrbStack: polished but GUI-oriented and closed source; teaches the least about the real stack.
- Apple `container`: no Kubernetes story.

## Consequences
- Declarative, headless VM in Git; k3s matches `zion-old`.
- No GPU passthrough, so no hardware transcoding for Plex/Jellyfin in the VM (they run natively instead, ADR 0008).
- The external NVMe must be attached when the VM starts, or Lima fails to start.
- We own boot-start (launchd), disabling macOS sleep, and VM networking (VM IP can change across restarts).
- The VM disk is a sparse file on the host: it is not a backup. Backups follow the backup ADR.
- NAS access (SMB on the host vs NFS directly from the VM) is decided in the NAS storage ADR.
- Images must be arm64-capable (already a convention).

## Update 2026-10-21
The cluster in this VM is now called `mini` (kubectl context, `clusters/mini/`, `apps/mini/`, since 2026-10-20), but the Lima VM and the k3s node keep the name `zion`: local-path volumes are tied to the node name, so renaming the node would orphan them. Two things learned in operation: the VM must be started by hand after a reboot and login (autostart is still an open item in `hosts/macos-mini/`), and if the external drive is unmounted or remounted while the VM runs, the virtiofs mount goes stale ("Bad file descriptor") and the VM must be restarted. The library on the drive is now a frozen old copy of Immich (ADR 0004).
