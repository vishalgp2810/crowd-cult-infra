# Crowd & Cult single-VM development (GCE)

| Item | Value |
|------|--------|
| Project | `crowdandcult-prod` |
| VM | `crowd-cult-dev-vm` (`e2-standard-2`, 8 GB RAM, 40 GB pd-standard) |
| Zone | `asia-south1-a` |
| Static IP | `8.234.105.200` (`crowd-cult-dev-vm-ip`) |
| Schedule | ON 12:00 IST, OFF 00:00 IST (`crowd-cult-dev-schedule`) |
| SSH | `gcloud compute ssh crowd-cult-dev-vm --project=crowdandcult-prod --zone=asia-south1-a` |
| Commands file | [commands.ps1](./commands.ps1) |

## DNS (create A records at the domain registrar)

`crowdandcult.com` NS is **Hostinger** (`hyperion.dns-parking.com` / `atlas.dns-parking.com`), not Cloud DNS. Create **A** records there, all pointing at **8.234.105.200**:

- `dev.crowdandcult.com`
- `admin.dev.crowdandcult.com`
- `api.dev.crowdandcult.com`

Then on the VM (must be during the ON window):

```bash
sudo /usr/local/sbin/crowd-cult-issue-certs.sh
```

Until those A records exist, nginx already serves HTTP by `Host` header. GCS CORS on `crowd-cult-prod-media` includes the three `https://*.dev.crowdandcult.com` origins.

Media uploads use the **prod bucket** `crowd-cult-prod-media` with prefix `dev/` (same as laptop). The API impersonates `local-dev-storage@crowdandcult-prod.iam.gserviceaccount.com`. The VM Compute Engine default SA must have `roles/iam.serviceAccountTokenCreator` on that GSA (already granted). After changing IAM, `pm2 restart crowd-api`.

## Apps on the box

Code lives in `/opt/crowd-cult/{crowd-cult-backend,crowd-cult-frontend,crowd-cult-admin}`. PM2 (`ubuntu`) runs `crowd-api`, `crowd-frontend` (`next start`), `crowd-admin` (`next dev` — production `next build` currently fails on HeroUI `useDisclosure`). Local MySQL 8 is bound to localhost only. After a scheduled start, `pm2-ubuntu.service` resurrects the process list.

## GitHub deploy keys (read-only, one key per repo)

GitHub does not allow one deploy key on multiple repositories. Add each public key as a Deploy key (read-only) on the matching repo.

**backend** (`vishalgp2810/crowd-cult-backend`):
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGYLERlHj0/138wTkn3zaw/e8AktB8kv5oiybTLXZpQM crowd-cult-dev-backend
```

**frontend** (`vishalgp2810/crowd-cult-frontend`):
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPqxt61CzeSgIDJGcoSGX3Zw4NSb4i5+GEOSZWAGuep6 crowd-cult-dev-frontend
```

**admin** (`vishalgp2810/crowd-cult-admin`):
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKfdb1Q8g7JlXlNBsWc5ZK6d79iFaCLVFyBLUqCHZEv8 crowd-cult-dev-admin
```

Repos are already cloned under `/opt/crowd-cult` from git bundles. After the keys are added:

```bash
cd /opt/crowd-cult/crowd-cult-backend && git fetch origin
cd /opt/crowd-cult/crowd-cult-frontend && git fetch origin
cd /opt/crowd-cult/crowd-cult-admin && git fetch origin
```
