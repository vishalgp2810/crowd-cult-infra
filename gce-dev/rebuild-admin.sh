#!/bin/bash
set -euo pipefail
sed -i 's/\r$//' /tmp/CategoryTreeSidebar.tsx
cp /tmp/CategoryTreeSidebar.tsx /opt/crowd-cult/crowd-cult-admin/src/features/menu/components/CategoryTreeSidebar.tsx
chown ubuntu:ubuntu /opt/crowd-cult/crowd-cult-admin/src/features/menu/components/CategoryTreeSidebar.tsx
sudo -u ubuntu bash -lc 'cd /opt/crowd-cult/crowd-cult-admin && NEXT_PUBLIC_API_URL=https://api.dev.crowdandcult.com npm run build'
sudo -u ubuntu bash -lc 'pm2 delete crowd-admin || true'
sudo -u ubuntu bash -lc 'cd /opt/crowd-cult/crowd-cult-admin && PORT=3001 pm2 start npm --name crowd-admin -- start'
sudo -u ubuntu bash -lc 'pm2 save'
sleep 4
curl -s -o /dev/null -w 'admin_local:%{http_code}\n' http://127.0.0.1:3001/
