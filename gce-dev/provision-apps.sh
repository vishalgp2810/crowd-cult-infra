#!/bin/bash
# Run on the VM after repos exist under /opt/crowd-cult
set -euxo pipefail
export NODE_ENV=development
ROOT=/opt/crowd-cult
API_URL=https://api.dev.crowdandcult.com

# MySQL listen localhost + app DB already created by startup.sh
if [[ -f /root/crowd-cult-mysql.env ]]; then
  # shellcheck disable=SC1091
  source /root/crowd-cult-mysql.env
else
  echo "Missing /root/crowd-cult-mysql.env" >&2
  exit 1
fi

python3 - <<'PY'
import json, os, pathlib, re
p = pathlib.Path("/opt/crowd-cult/crowd-cult-backend/config/development.json")
data = json.loads(p.read_text())
pw = open("/root/crowd-cult-mysql.env").read().split("=",1)[1].strip()
data["DATABASE"]["DB_HOST"] = "localhost"
data["DATABASE"]["DB_PORT"] = 3306
data["DATABASE"]["DB_USER"] = "root"
data["DATABASE"]["DB_PASS"] = pw
data["GOOGLE_AUTH"]["CALLBACK_URL"] = "https://api.dev.crowdandcult.com/auth/google/callback"
data["GOOGLE_AUTH"]["FRONTEND_BASE_URL"] = "https://dev.crowdandcult.com"
data["AUTH_COOKIE"]["SECURE"] = True
p.write_text(json.dumps(data, indent=2) + "\n")
PY

cd "$ROOT/crowd-cult-backend"
sudo -u ubuntu npm ci
sudo -u ubuntu env NODE_ENV=development npm run migrate
sudo -u ubuntu env NODE_ENV=development npm run seed || true

cd "$ROOT/crowd-cult-frontend"
sudo -u ubuntu npm ci
sudo -u ubuntu env NEXT_PUBLIC_API_URL="$API_URL" npm run build

cd "$ROOT/crowd-cult-admin"
sudo -u ubuntu npm ci
sudo -u ubuntu env NEXT_PUBLIC_API_URL="$API_URL" npm run build

# PM2 as ubuntu
sudo -u ubuntu bash -lc "pm2 delete all || true"
sudo -u ubuntu bash -lc "cd $ROOT/crowd-cult-backend && NODE_ENV=development pm2 start server.js --name crowd-api"
sudo -u ubuntu bash -lc "cd $ROOT/crowd-cult-frontend && PORT=3000 NEXT_PUBLIC_API_URL=$API_URL pm2 start npm --name crowd-frontend -- start"
sudo -u ubuntu bash -lc "cd $ROOT/crowd-cult-admin && PORT=3001 NEXT_PUBLIC_API_URL=$API_URL pm2 start npm --name crowd-admin -- start"
sudo -u ubuntu bash -lc "pm2 save"
env PATH=$PATH:/usr/bin pm2 startup systemd -u ubuntu --hp /home/ubuntu || true
sudo -u ubuntu bash -lc "pm2 save"
