#!/usr/bin/env bash
# .claude/hooks/test-guard.sh
# Checks guard-bash.sh: commands that must be blocked (exit 2) and commands that must pass (exit 0).
# Run after every change to the hook:  .claude/hooks/test-guard.sh
# It only feeds text to the hook; nothing here is executed.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fail=0

check() { # expected_exit  command-text
  local want="$1" cmd="$2" got
  jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | "$here/guard-bash.sh" >/dev/null 2>&1
  got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL (wanted $want, got $got): $cmd"
    fail=1
  fi
}

block() { check 2 "$1"; }
allow() { check 0 "$1"; }

# --- cluster mutations
block 'kubectl --context zion delete pod x -n y'
block 'kubectl --context extreme scale deploy/x --replicas=0'
block 'kubectl rollout restart deploy/x -n y'
block 'kubectl apply -f x.yaml'
block 'flux reconcile kustomization apps'

# --- secrets and credentials
block 'kubectl get secret x -n y -o yaml'
block 'kubectl get -o yaml secret x -n y'
block 'kubectl get cm,secret -o yaml -n y'
block 'kubectl get secrets -n y -ojson'
block "kubectl get secret x -o jsonpath='{.data}'"
block 'kubectl get --raw /api/v1/namespaces/y/secrets'
block 'kubectl config view --raw'
block 'sops decrypt apps/x/secret.sops.yaml'
block 'sops -d apps/x/secret.sops.yaml'
block 'sops --decrypt apps/x/secret.sops.yaml'
block 'sops apps/x/secret.sops.yaml'
block 'EDITOR=cat sops edit apps/x/secret.sops.yaml'
block 'sops exec-env apps/x/secret.sops.yaml env'
block 'age -d -i key.txt file.age'
block 'cat ~/.config/sops/age/keys.txt'
block 'ls ~/Downloads/zion.agekey'

# --- host-level tools
block 'sudo ls'
block 'ssh host uptime'
block 'scp a b:c'
block 'rsync -a a b'
block 'systemctl status k3s'
block 'k3s kubectl get nodes'
block 'limactl stop zion'
block 'launchctl list'
block 'tailscale set --hostname=x'
block 'ufw status'
block 'cloudflared tunnel run x'
block 'crontab -l'
block 'umount /mnt/x'

# --- git: only reading is allowed
block 'git push'
block 'git -C . push origin main'
block 'git --no-pager push origin main'
block 'git commit -m x'
block 'git add -A && git commit -m x'
block 'git reset --hard HEAD~1'
block 'git reset HEAD file'
block 'git stash'
block 'git pull'
block 'git tag v1'
block 'git clean -fd'
block 'git merge main'
block 'git rebase main'

# --- things that must keep working
allow 'kubectl --context extreme get pods -A'
allow 'kubectl --context zion describe pod x -n y'
allow 'kubectl --context extreme logs deploy/x -n y --tail=20'
allow 'kubectl get secret sops-age -n flux-system'
allow 'kubectl get secrets -A'
allow 'kubectl get pvc -A -o wide'
allow 'kubectl get pods -n y -o jsonpath={.items[*].metadata.name}'
allow 'kubectl top nodes'
allow 'kubectl rollout status deploy/x -n y'
allow 'kubectl get kustomization -n flux-system'
allow 'kubectl kustomize apps/extreme'
allow 'kubectl config get-contexts'
allow 'flux get kustomization'
allow 'git status --short'
allow 'git diff --stat'
allow 'git log --oneline -5'
allow 'git show HEAD --stat'
allow 'git status | grep commit'
allow 'sops --encrypt --in-place apps/x/secret.sops.yaml'
allow 'sops --version'
allow 'ls -la apps'
allow 'grep -rn foo docs'
allow 'python3 -I -c "print(1)"'
allow 'bash -n hosts/ubuntu-extreme/k3s-install.sh'

if [ "$fail" -eq 0 ]; then echo "guard-bash: all cases behave as expected"; fi
exit "$fail"
