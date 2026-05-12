# Variable reference — what to change and where

## Backend (Kubernetes)

| If you need to change… | Where | After change |
|------------------------|--------|--------------|
| DB host/port/name/user/password | Secret `crowd-cult-backend-secret` keys `DATABASE__*` | `kubectl apply` secret → **rollout restart** backend |
| GCP project / bucket / signing SA | Secret: `GCP__PROJECT_ID`, `GCP__STORAGE_BUCKET`, `GCP__SIGNING_SERVICE_ACCOUNT`, `GCP__KEY_FILENAME` | Apply + **restart** backend |
| JWT, encryption, Google OAuth, email | Secret keys per `secrets.template.yaml` | Apply + **restart** backend |
| `NODE_ENV`, server bind, cookie secure | ConfigMap `crowd-cult-backend-config` | Apply + **restart** if app reads at startup only |

Mapping to Node config: `crowd-cult-backend/config/custom-environment-variables.json`.

## Frontend & admin (Kubernetes)

| If you need to change… | Where | After change |
|------------------------|--------|--------------|
| **API URL the browser calls** | Rebuild image with `NEXT_PUBLIC_API_URL` (**Dockerfile ARG** or `docker build --build-arg`) | Push image → **rollout restart** frontend/admin |
| Runtime server `PORT`, `NODE_ENV` only | ConfigMap `crowd-cult-frontend-config` / `crowd-cult-admin-config` | Apply + restart |

Changing only the ConfigMap **does not** change `NEXT_PUBLIC_*` in the already-built JS bundle.

## Jobs (migrate / seed)

| If you need to change… | Where |
|------------------------|--------|
| Cloud SQL instance | `k8s/base/backend-migrate-job.yaml` and `backend-seed-job.yaml` env `CLOUD_SQL_INSTANCE_CONNECTION_NAME` |
| Namespace | **Always** `kubectl apply -f ... -n <namespace>` |

## Infra / IAM (GCP Console or gcloud)

| If you need to change… | Where |
|------------------------|--------|
| Which GSA the pod uses | KSA annotation in `k8s/base/backend-serviceaccount.yaml` + `gcloud iam` WI binding |
| GCS upload/read permissions | Bucket IAM + GSA roles (see [DEPLOYMENT-OVERVIEW.md](./DEPLOYMENT-OVERVIEW.md)) |
| DNS / TLS hosts | `k8s/prod/ingress.yaml`, ManagedCertificate, DNS A records |

## Local developer (not in cluster)

| If you need… | Where |
|----------------|--------|
| Local DB connection hints | `k8s/prod/cloud-sql-credentials.local.env.example` → copy to gitignored `*.local.env` |

See [LOCAL-DATABASE-AND-STAGING.md](./LOCAL-DATABASE-AND-STAGING.md).
