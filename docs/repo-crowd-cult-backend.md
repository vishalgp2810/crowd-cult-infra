# Manual: `crowd-cult-backend`

## What this service is

- **Fastify** API, **Sequelize** + MySQL, file uploads to **GCS**, Google OAuth, cookies/JWT.
- Runtime config uses **`node-config`**: `config/default.json` + environment variables (see `config/custom-environment-variables.json`).

## Build and push (Cloud Build)

From the **backend repo root** (where the `Dockerfile` lives).

> **Shell note**: bash uses `\` for line continuation, PowerShell uses backtick `` ` ``. Use the **single-line** form if your shell complains.
>
> **Windows PowerShell tip:** if you see `Missing expression after unary operator '--'`, you likely used bash-style `\`. Use backtick or single-line.

Template — bash / zsh:

```bash
gcloud config set project YOUR_PROJECT_ID

gcloud builds submit \
  --tag asia-south1-docker.pkg.dev/YOUR_PROJECT_ID/crowd-cult-backend/crowd-cult-backend:latest \
  .
```

Template — PowerShell:

```powershell
gcloud config set project YOUR_PROJECT_ID

gcloud builds submit `
  --tag asia-south1-docker.pkg.dev/YOUR_PROJECT_ID/crowd-cult-backend/crowd-cult-backend:latest `
  .
```

Template — single-line (any shell):

```bash
gcloud builds submit --tag asia-south1-docker.pkg.dev/YOUR_PROJECT_ID/crowd-cult-backend/crowd-cult-backend:latest .
```

### Production (`crowdandcultprod`)

bash / zsh:

```bash
gcloud config set project crowdandcultprod

gcloud builds submit \
  --tag asia-south1-docker.pkg.dev/crowdandcultprod/crowd-cult-backend/crowd-cult-backend:latest \
  .
```

PowerShell (Windows):

```powershell
gcloud config set project crowdandcultprod

gcloud builds submit `
  --tag asia-south1-docker.pkg.dev/crowdandcultprod/crowd-cult-backend/crowd-cult-backend:latest `
  .
```

Single-line (any shell):

```bash
gcloud builds submit --tag asia-south1-docker.pkg.dev/crowdandcultprod/crowd-cult-backend/crowd-cult-backend:latest .
```

PowerShell quick copy (recommended):

```powershell
gcloud config set project crowdandcultprod
gcloud builds submit --tag asia-south1-docker.pkg.dev/crowdandcultprod/crowd-cult-backend/crowd-cult-backend:latest .
```

- Uses the multi-stage **Dockerfile**: `npm ci`, production image includes **Cloud SQL Proxy** binary and **ca-certificates** (for proxy TLS to Google APIs).
- The **migrate/seed Jobs** use `/app/scripts/run-with-cloud-sql-proxy.sh` (generated in the image) so the Job pod can **exit** after the task (no stuck sidecar).

## Run on GKE

- **Deployment:** `k8s/base/backend-deployment.yaml` — **two containers**: `cloud-sql-proxy` sidecar + `backend` app; `serviceAccountName: crowd-cult-backend-sa`.
- **Image:** point to your Artifact Registry image; `imagePullPolicy: Always` if you reuse `:latest`.

Roll out after a new image (template):

```bash
kubectl rollout restart deployment/crowd-cult-backend -n YOUR_NAMESPACE
kubectl rollout status  deployment/crowd-cult-backend -n YOUR_NAMESPACE
```

PowerShell (same commands):

```powershell
kubectl rollout restart deployment/crowd-cult-backend -n YOUR_NAMESPACE
kubectl rollout status deployment/crowd-cult-backend -n YOUR_NAMESPACE
```

### Production rollout (`crowd-cult-prod` namespace)

```bash
kubectl rollout restart deployment/crowd-cult-backend -n crowd-cult-prod
kubectl rollout status  deployment/crowd-cult-backend -n crowd-cult-prod
```

PowerShell quick copy (recommended):

```powershell
kubectl rollout restart deployment/crowd-cult-backend -n crowd-cult-prod
kubectl rollout status deployment/crowd-cult-backend -n crowd-cult-prod
```

## Environment variables (how they get into the pod)

The Deployment uses:

```yaml
envFrom:
  - configMapRef:
      name: crowd-cult-backend-config
  - secretRef:
      name: crowd-cult-backend-secret
```

### Changing a variable

1. Edit the **ConfigMap** and/or **Secret** (never commit live secrets to git).
2. `kubectl apply -f ...` (or `kubectl patch`).
3. **Restart** the backend Deployment so processes reload env:

   ```bash
   kubectl rollout restart deployment/crowd-cult-backend -n YOUR_NAMESPACE
   ```

### Important backend keys (Secret / ConfigMap)

| Env var (K8s) | Config path | Notes |
|---------------|-------------|--------|
| `DATABASE__DB_HOST` | `DATABASE.DB_HOST` | Use `127.0.0.1` with proxy sidecar |
| `DATABASE__DB_PORT` | `DATABASE.DB_PORT` | Usually `3306` |
| `DATABASE__DB_NAME` | `DATABASE.DB_NAME` | |
| `DATABASE__DB_USER` / `DATABASE__DB_PASS` | | App DB user |
| `GCP__PROJECT_ID` | `GCP.PROJECT_ID` | Required for GCS signing / client |
| `GCP__STORAGE_BUCKET` | `GCP.STORAGE_BUCKET` | Media bucket name |
| `GCP__KEY_FILENAME` | `GCP.KEY_FILENAME` | Empty on GKE (use WI, not JSON key) |
| `GCP__SIGNING_SERVICE_ACCOUNT` | `GCP.SIGNING_SERVICE_ACCOUNT` | **Same email** as WI GSA on `crowd-cult-backend-sa` — required for V4 **signed read URLs** |
| `JWT__JWT_SECRET`, `ENCRYPTION__KEY`, etc. | | See `k8s/base/secrets.template.yaml` |

Template for a fresh secret: `crowd-cult-infra/k8s/base/secrets.template.yaml`.

## Database migrations and seeds (Kubernetes Jobs)

Manifests:

- `crowd-cult-infra/k8s/base/backend-migrate-job.yaml`
- `crowd-cult-infra/k8s/base/backend-seed-job.yaml`

**Always** pass the target namespace (avoid applying into `default`):

```bash
kubectl delete job crowd-cult-backend-migrate crowd-cult-backend-seed -n YOUR_NAMESPACE --ignore-not-found

kubectl apply -f k8s/base/backend-migrate-job.yaml -n YOUR_NAMESPACE
kubectl wait --for=condition=complete job/crowd-cult-backend-migrate -n YOUR_NAMESPACE --timeout=300s

kubectl apply -f k8s/base/backend-seed-job.yaml -n YOUR_NAMESPACE
kubectl wait --for=condition=complete job/crowd-cult-backend-seed -n YOUR_NAMESPACE --timeout=300s
```

Jobs use the **same** `serviceAccountName` and **Cloud SQL instance** connection name as in the YAML (update for staging).

## Workload Identity and GCS

- Kubernetes **ServiceAccount** `crowd-cult-backend-sa` is annotated with  
  `iam.gke.io/gcp-service-account: <GSA_EMAIL>@....iam.gserviceaccount.com`.
- That **GSA** must have at minimum:
  - **`roles/cloudsql.client`** on the project (or appropriate for Cloud SQL).
  - **`roles/storage.objectAdmin`** on the **media bucket** (upload + read for signing).
  - **`roles/iam.serviceAccountTokenCreator`** on **itself** (principal = that GSA) so `signBlob` works for signed URLs.
- Enable **`iamcredentials.googleapis.com`** on the project.

## Upload API response shape

`POST /media/upload` returns:

- **`url`**: canonical GCS URL — **persist in DB only**.
- **`readUrl`**: V4 signed URL — use in `<img src>`; **do not** store (expires).

If `readUrl` equals `url`, signing failed — check pod logs and `GCP__SIGNING_SERVICE_ACCOUNT`.

## Local development (short)

Use Cloud SQL Auth Proxy + local env; see [LOCAL-DATABASE-AND-STAGING.md](./LOCAL-DATABASE-AND-STAGING.md).
