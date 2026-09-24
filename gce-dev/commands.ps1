# Crowd & Cult — GCE dev VM commands (PowerShell)
# Project: crowdandcult-prod | VM: crowd-cult-dev-vm | Zone: asia-south1-a | IP: 8.234.105.200
# Schedule: ON 12:00 IST, OFF 00:00 IST

$Project = "crowdandcult-prod"
$Zone    = "asia-south1-a"
$Vm      = "crowd-cult-dev-vm"

# --- SSH ---
gcloud compute ssh $Vm --project=$Project --zone=$Zone

# One-off remote command
# gcloud compute ssh $Vm --project=$Project --zone=$Zone --command="pm2 status"

# Copy a file to the VM
# gcloud compute scp .\local.txt "${Vm}:~/" --project=$Project --zone=$Zone

# --- Start / stop (compute is $0 when STOPPED; disk + static IP still bill) ---
# gcloud compute instances start $Vm --project=$Project --zone=$Zone
# gcloud compute instances stop  $Vm --project=$Project --zone=$Zone
# gcloud compute instances describe $Vm --project=$Project --zone=$Zone --format="value(status)"

# --- After SSH, app locations ---
# /opt/crowd-cult/crowd-cult-backend      API
# /opt/crowd-cult/crowd-cult-frontend     public site
# /opt/crowd-cult/crowd-cult-admin        admin
# nginx: /etc/nginx/sites-enabled/crowd-cult-dev
# MySQL DB: crowdandcult (localhost only)

# --- After SSH, process / logs ---
# sudo -u ubuntu pm2 status
# sudo -u ubuntu pm2 logs crowd-api --lines 80
# sudo -u ubuntu pm2 logs crowd-frontend --lines 80
# sudo -u ubuntu pm2 logs crowd-admin --lines 80
# sudo -u ubuntu pm2 restart crowd-api
# sudo -u ubuntu pm2 restart crowd-frontend
# sudo -u ubuntu pm2 restart crowd-admin
# sudo nginx -t && sudo systemctl reload nginx

# --- After SSH, git pull + rebuild (deploy keys must be on GitHub) ---
# cd /opt/crowd-cult/crowd-cult-backend && git pull && npm ci && NODE_ENV=development npm run migrate && sudo -u ubuntu pm2 restart crowd-api
# Demo data (dev only — refuses to run in production): cd /opt/crowd-cult/crowd-cult-backend && NODE_ENV=development npm run seed:demo
# cd /opt/crowd-cult/crowd-cult-frontend && git pull && NEXT_PUBLIC_API_URL=https://api.dev.crowdandcult.com npm ci && NEXT_PUBLIC_API_URL=https://api.dev.crowdandcult.com npm run build && sudo -u ubuntu pm2 restart crowd-frontend
# cd /opt/crowd-cult/crowd-cult-admin && git pull && NEXT_PUBLIC_API_URL=https://api.dev.crowdandcult.com npm ci && NEXT_PUBLIC_API_URL=https://api.dev.crowdandcult.com npm run build && sudo -u ubuntu pm2 restart crowd-admin

# --- URLs ---
# https://dev.crowdandcult.com
# https://admin.dev.crowdandcult.com
# https://api.dev.crowdandcult.com/health

# --- Twilio + FreeSWITCH (TELEPHONY) ---
# Local repo: D:\WORKSPACE\TELEPHONY\freeswitch
# Deploy to VM (/opt/telephony/freeswitch + boot service):
#   cd D:\WORKSPACE\TELEPHONY\freeswitch\deploy; .\deploy.ps1
# On VM after deploy / daily boot:
#   systemctl status freeswitch telephony-apply
#   fs_cli -x "sofia status gateway twilio"
#   sudo /opt/telephony/freeswitch/scripts/watch-sip.sh
# Docs: D:\WORKSPACE\TELEPHONY\freeswitch\docs\twilio-call-flow.md
