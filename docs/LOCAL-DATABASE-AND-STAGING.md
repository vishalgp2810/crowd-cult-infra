# Local database access and new environment (staging) setup

## Part A — Connect to Cloud SQL from your laptop

### Prerequisites

- **gcloud** installed and authenticated:
  - `gcloud auth login`
  - `gcloud auth application-default login` (required for Cloud SQL Auth Proxy / Docker below)
- **Cloud SQL Client** IAM role (or org policy allowing instance access) for your Google account.
- **Production instance connection name** (example for this project):

  `crowdandcult-prod:asia-south1:crowd-cult-prod-sql`

### Where database credentials live (passwords never in this doc)

- **Example only (safe to commit):** [`k8s/prod/cloud-sql-credentials.local.env.example`](../k8s/prod/cloud-sql-credentials.local.env.example)
- **Real values (gitignored):** [`k8s/prod/cloud-sql-credentials.local.env`](../k8s/prod/cloud-sql-credentials.local.env)  
  Copy from the example, then set `DATABASE__DB_PASS` and optional `MYSQL_ROOT_PASSWORD`. **Do not commit** the `.local.env` file.
- **Cluster source of truth:** `kubectl get secret crowd-cult-backend-secret -n crowd-cult-prod` (keys `DATABASE__DB_*`). If DBeaver says “access denied”, decode the secret and paste that password (local file can drift).

### DBeaver / GUI (after proxy is running)

Use values from your **`.local.env`** (or decoded K8s secret):

| Setting | Value |
|--------|--------|
| Host | `127.0.0.1` (must match `DATABASE__DB_HOST` while using proxy) |
| Port | `3306` (or the host port you mapped if using Docker, e.g. `3307`) |
| Database | Value of `DATABASE__DB_NAME` (e.g. `crowdandcult`) |
| Username | Value of `DATABASE__DB_USER` (e.g. `crowd_app`) |
| Password | Value of `DATABASE__DB_PASS` |

Keep the proxy running for the whole session. The MySQL host may appear as `cloudsqlproxy~…` in errors; that is normal.

---

## Cloud SQL Auth Proxy — command reference

Proxy image / binary version used elsewhere in this repo: **`2.14.3`**.

### 0) Check Application Default Credentials (ADC)

```powershell
Test-Path "$env:APPDATA\gcloud\application_default_credentials.json"
```

Should be `True` on Windows after `gcloud auth application-default login`.

### 1) Native binary (Linux / macOS / Windows if installed)

Install: [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/mysql/sql-proxy).

```bash
export CLOUD_SQL_INSTANCE="crowdandcult-prod:asia-south1:crowd-cult-prod-sql"
cloud-sql-proxy --port 3306 "$CLOUD_SQL_INSTANCE"
```

Leave this terminal open. Connect clients to `127.0.0.1:3306`.

### 2) Docker on Windows (recommended if `cloud-sql-proxy` is not on PATH)

**Start** (foreground; Ctrl+C to stop):

```powershell
$INSTANCE = "crowdandcult-prod:asia-south1:crowd-cult-prod-sql"
docker run --rm -p 3306:3306 `
  -v "$env:APPDATA/gcloud/application_default_credentials.json:/secrets/adc.json:ro" `
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/adc.json `
  gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.3 `
  --address 0.0.0.0 --port 3306 $INSTANCE
```

**Start detached** (background; fixed container name):

```powershell
$INSTANCE = "crowdandcult-prod:asia-south1:crowd-cult-prod-sql"
docker rm -f crowd-cult-sql-proxy 2>$null
docker run -d --name crowd-cult-sql-proxy -p 3306:3306 `
  -v "$env:APPDATA/gcloud/application_default_credentials.json:/secrets/adc.json:ro" `
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/adc.json `
  gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.3 `
  --address 0.0.0.0 --port 3306 $INSTANCE
```

**Logs:**

```powershell
docker logs crowd-cult-sql-proxy
```

**Stop / remove:**

```powershell
docker stop crowd-cult-sql-proxy
docker rm crowd-cult-sql-proxy
```

### 3) Port already in use (e.g. local MySQL on 3306)

Map host **3307** to proxy **3306**:

```powershell
$INSTANCE = "crowdandcult-prod:asia-south1:crowd-cult-prod-sql"
docker run -d --name crowd-cult-sql-proxy -p 3307:3306 `
  -v "$env:APPDATA/gcloud/application_default_credentials.json:/secrets/adc.json:ro" `
  -e GOOGLE_APPLICATION_CREDENTIALS=/secrets/adc.json `
  gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.3 `
  --address 0.0.0.0 --port 3306 $INSTANCE
```

Then use DBeaver host `127.0.0.1` and port **`3307`**.

### 4) Copy password from Kubernetes into clipboard (Windows)

```powershell
kubectl get secret crowd-cult-backend-secret -n crowd-cult-prod -o jsonpath="{.data.DATABASE__DB_PASS}" `
  | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) } `
  | Set-Clipboard
```

### Connect with `mysql` client

With proxy listening on `127.0.0.1:3306` and password from `.local.env` or K8s:

```bash
mysql -h 127.0.0.1 -P 3306 -u YOUR_APP_USER -p YOUR_DATABASE_NAME
```

Use the **app** user for application parity; use **root** only for grants / break-glass (`MYSQL_ROOT_PASSWORD` in `.local.env` if set).

---

## Part B — Checklist: new stage environment (e.g. `staging`)

Use this to clone the pattern from production without missing steps.

### 1. GCP project (or folder)

- Create or choose a project (e.g. `crowdandcult-staging`).
- Enable APIs (see [gcp-prerequisites.md](./gcp-prerequisites.md) **and** add `iamcredentials.googleapis.com` for signed URLs).

### 2. Artifact Registry

- Create Docker repos: `crowd-cult-backend`, `crowd-cult-frontend`, `crowd-cult-admin` in your **region**.

### 3. GKE

- Create cluster with **Workload Identity** enabled.
- Node pools: **`--workload-metadata=GKE_METADATA`** (required for WI tokens to work correctly with Cloud SQL and IAM).

### 4. Cloud SQL

- New MySQL instance (dev/staging tier is fine).
- Create **database** and **app user**; run:

  ```sql
  GRANT ALL ON your_db.* TO 'your_user'@'%';
  FLUSH PRIVILEGES;
  ```

### 5. GCS

- New bucket for media (e.g. `crowd-cult-staging-media`).
- Create a **Google service account** for the backend (or one GSA for SQL + GCS):
  - `roles/cloudsql.client`
  - On the bucket: `roles/storage.objectAdmin`
  - On **that GSA**: grant **`roles/iam.serviceAccountTokenCreator`** to **itself** (principal = same GSA email).

### 6. Kubernetes namespace and identity

- `kubectl create namespace crowd-cult-staging` (example).
- Apply `backend-serviceaccount.yaml` but **change** the annotation to your **staging** GSA email.
- Bind WI:

  ```bash
  gcloud iam service-accounts add-iam-policy-binding STAGING_GSA@PROJECT.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:PROJECT.svc.id.goog[NAMESPACE/crowd-cult-backend-sa]"
  ```

### 7. Secrets and ConfigMaps

- Copy `k8s/base/secrets.template.yaml` → fill **all** `REPLACE_*` values.
- Set **`GCP__SIGNING_SERVICE_ACCOUNT`** to the **same** email as the WI GSA on `crowd-cult-backend-sa`.
- Apply `k8s/prod/configmaps.yaml` (or a `staging` variant) with **staging** URLs for OAuth callbacks if different.

### 8. Ingress, DNS, TLS

- Reserve a **static IP**; point **DNS** for `api.staging...`, `staging...`, `admin.staging...`.
- Apply Ingress + **ManagedCertificate** with staging hostnames.

### 9. Build images with **staging** public URLs

- **Frontend / admin:** rebuild with  
  `NEXT_PUBLIC_API_URL=https://api.staging.yourdomain.com`  
  (and `NEXT_PUBLIC_SITE_URL` if used).
- **Backend:** no change to API URL inside the image; staging uses K8s env.

### 10. Deploy and Jobs

- Apply Deployments, Services, Ingress.
- Run **migrate** Job with `-n` your namespace.
- Run **seed** Job if needed.
- Verify `/health`, upload, and that **`readUrl`** contains `X-Goog-Signature`.

### 11. Optional: local `.env` for staging

- Add `cloud-sql-credentials.staging.local.env` (gitignored) mirroring the example file pattern; document connection name for the **staging** instance.

---

## Quick reference: production connection name (example)

Replace with your own for each environment:

`crowdandcult-prod:asia-south1:crowd-cult-prod-sql`
