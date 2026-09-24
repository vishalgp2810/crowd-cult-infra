#!/bin/bash
# First-boot install for the Crowd & Cult single-VM dev box (no Docker).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
MARKER=/var/lib/crowd-cult-dev-bootstrap.done
if [[ -f "$MARKER" ]]; then
  exit 0
fi

apt-get update
apt-get install -y \
  git curl ca-certificates gnupg build-essential python3 \
  nginx mysql-server ufw \
  certbot python3-certbot-nginx

# Node.js 20
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi
npm install -g pm2

# MySQL: localhost only, utf8mb4, app database
install -d -m 755 /etc/mysql/mysql.conf.d
cat >/etc/mysql/mysql.conf.d/zz-crowd-cult-dev.cnf <<'EOF'
[mysqld]
bind-address = 127.0.0.1
mysqlx-bind-address = 127.0.0.1
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
lower_case_table_names = 0
skip-name-resolve
EOF

systemctl enable mysql
systemctl restart mysql

if [[ ! -f /root/crowd-cult-mysql.env ]]; then
  MYSQL_ROOT_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
  umask 077
  printf 'MYSQL_ROOT_PASSWORD=%s\n' "$MYSQL_ROOT_PASS" >/root/crowd-cult-mysql.env
fi
# shellcheck disable=SC1091
source /root/crowd-cult-mysql.env

mysql --protocol=socket -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS crowdandcult CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
FLUSH PRIVILEGES;
SQL

install -d -m 755 -o ubuntu -g ubuntu /opt/crowd-cult
install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh
if [[ ! -f /home/ubuntu/.ssh/id_ed25519 ]]; then
  sudo -u ubuntu ssh-keygen -t ed25519 -N "" -f /home/ubuntu/.ssh/id_ed25519 -C "crowd-cult-dev-vm"
fi
sudo -u ubuntu tee /home/ubuntu/.ssh/config >/dev/null <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
chown ubuntu:ubuntu /home/ubuntu/.ssh/config
chmod 600 /home/ubuntu/.ssh/config
cp /home/ubuntu/.ssh/id_ed25519.pub /home/ubuntu/GITHUB_DEPLOY_KEY.pub
chown ubuntu:ubuntu /home/ubuntu/GITHUB_DEPLOY_KEY.pub

# nginx placeholders until TLS
cat >/etc/nginx/sites-available/crowd-cult-dev <<'EOF'
map $http_upgrade $connection_upgrade {
  default upgrade;
  '' close;
}

server {
  listen 80;
  server_name dev.crowdandcult.com;
  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}

server {
  listen 80;
  server_name admin.dev.crowdandcult.com;
  location / {
    proxy_pass http://127.0.0.1:3001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}

server {
  listen 80;
  server_name api.dev.crowdandcult.com;
  client_max_body_size 50m;
  location / {
    proxy_pass http://127.0.0.1:3031;
    proxy_http_version 1.1;
    # Websockets (/realtime/ws — live table requests) need the upgrade headers and a long read timeout.
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
EOF
ln -sfn /etc/nginx/sites-available/crowd-cult-dev /etc/nginx/sites-enabled/crowd-cult-dev
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl reload nginx

# ufw: SSH + HTTP/S only (MySQL stays on loopback)
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

date -u >"$MARKER"
