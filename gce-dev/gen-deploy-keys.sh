#!/bin/bash
set -euxo pipefail
SSH_DIR=/home/ubuntu/.ssh
sudo -u ubuntu mkdir -p "$SSH_DIR"
sudo -u ubuntu chmod 700 "$SSH_DIR"
for name in backend frontend admin; do
  key="$SSH_DIR/id_ed25519_${name}"
  if [[ ! -f "$key" ]]; then
    sudo -u ubuntu ssh-keygen -t ed25519 -N "" -f "$key" -C "crowd-cult-dev-${name}"
  fi
done
sudo -u ubuntu tee "$SSH_DIR/config" >/dev/null <<'EOF'
Host github.com-backend
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_backend
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new

Host github.com-frontend
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_frontend
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new

Host github.com-admin
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_admin
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
sudo chmod 600 "$SSH_DIR/config"
sudo chown ubuntu:ubuntu "$SSH_DIR/config"
echo '---BACKEND---'
cat "$SSH_DIR/id_ed25519_backend.pub"
echo '---FRONTEND---'
cat "$SSH_DIR/id_ed25519_frontend.pub"
echo '---ADMIN---'
cat "$SSH_DIR/id_ed25519_admin.pub"
