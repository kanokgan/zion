#!/bin/bash
# hosts/ubuntu-extreme/k3s-install.sh
# Installs k3s on the Lenovo (cluster `extreme`, ADR 0009). Run as root, once, after the old k3s is removed.
# Same version and flags as the mini (hosts/macos-mini/lima/zion.yaml) so the two clusters behave alike.
# Differences from the old install: the kubeconfig stays root-only (no --write-kubeconfig-mode 644), and the node
# is named after the machine's cluster, not `k3s-master`.
set -euo pipefail

export INSTALL_K3S_VERSION="v1.33.6+k3s1"

# k3s creates the `nvidia` RuntimeClass at start only if it finds the NVIDIA runtime. Fail early if it is missing.
command -v nvidia-container-runtime >/dev/null || { echo "nvidia-container-runtime not found" >&2; exit 1; }
nvidia-smi >/dev/null || { echo "nvidia-smi fails: reboot after a driver upgrade first" >&2; exit 1; }

# Traefik and ServiceLB stay disabled: public traffic comes through the host's cloudflared on NodePorts.
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --disable servicelb \
  --node-name extreme

until k3s kubectl get node extreme 2>/dev/null | grep -q ' Ready'; do sleep 3; done
k3s kubectl get runtimeclass nvidia
