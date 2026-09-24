#!/bin/bash
set -euxo pipefail
export NODE_ENV=development
ROOT=/opt/crowd-cult
API_URL=https://api.dev.crowdandcult.com
python3 /tmp/fix-db-host.py

cd "$ROOT/crowd-cult-backend"
sudo -u ubuntu env NODE_ENV=development npm run migrate
sudo -u ubuntu env NODE_ENV=development npm run seed || true

cd "$ROOT/crowd-cult-frontend"
sudo -u ubuntu npm ci
sudo -u ubuntu env NEXT_PUBLIC_API_URL="$API_URL" npm run build

cd "$ROOT/crowd-cult-admin"
sudo -u ubuntu npm ci
sudo -u ubuntu env NEXT_PUBLIC_API_URL="$API_URL" npm run build

sudo -u ubuntu bash -lc "pm2 delete all || true"
sudo -u ubuntu bash -lc "cd $ROOT/crowd-cult-backend && NODE_ENV=development pm2 start server.js --name crowd-api"
sudo -u ubuntu bash -lc "cd $ROOT/crowd-cult-frontend && PORT=3000 pm2 start npm --name crowd-frontend -- start"
sudo -u ubuntu bash -lc "cd $ROOT/crowd-cult-admin && PORT=3001 pm2 start npm --name crowd-admin -- start"
sudo -u ubuntu bash -lc "pm2 save"
# Enable pm2 on boot for ubuntu
STARTUP_CMD=$(sudo -u ubuntu bash -lc "pm2 startup systemd -u ubuntu --hp /home/ubuntu" | tail -n 1 || true)
if echo "$STARTUP_CMD" | grep -q systemd; then
  eval "$STARTUP_CMD" || true
fi
sudo -u ubuntu bash -lc "pm2 save"
sudo -u ubuntu bash -lc "pm2 status"
