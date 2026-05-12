# GCP Prerequisites (Artifact Registry + GKE + Cloud SQL)

## 1) APIs to enable

Linux/macOS (bash):

```bash
gcloud services enable \
  artifactregistry.googleapis.com \
  container.googleapis.com \
  compute.googleapis.com \
  dns.googleapis.com \
  sqladmin.googleapis.com \
  iamcredentials.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com
```

Windows PowerShell:

```powershell
gcloud services enable `
  artifactregistry.googleapis.com `
  container.googleapis.com `
  compute.googleapis.com `
  dns.googleapis.com `
  sqladmin.googleapis.com `
  iamcredentials.googleapis.com `
  secretmanager.googleapis.com `
  iam.googleapis.com `
  cloudresourcemanager.googleapis.com
```

Windows one-line alternative:

```powershell
gcloud services enable artifactregistry.googleapis.com container.googleapis.com compute.googleapis.com dns.googleapis.com sqladmin.googleapis.com iamcredentials.googleapis.com secretmanager.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com
```

If you get `PERMISSION_DENIED`, your account does not have enough rights on the selected project. Ask project owner/admin for one of these roles:
- `roles/owner`, or
- `roles/editor` + `roles/serviceusage.serviceUsageAdmin`

## 2) Artifact Registry

Create one repository per workload:

Linux/macOS (bash):

```bash
gcloud artifacts repositories create crowd-cult-backend \
  --repository-format=docker --location=REGION

gcloud artifacts repositories create crowd-cult-frontend \
  --repository-format=docker --location=REGION

gcloud artifacts repositories create crowd-cult-admin \
  --repository-format=docker --location=REGION
```

Windows PowerShell:

```powershell
gcloud artifacts repositories create crowd-cult-backend `
  --repository-format=docker --location=REGION

gcloud artifacts repositories create crowd-cult-frontend `
  --repository-format=docker --location=REGION

gcloud artifacts repositories create crowd-cult-admin `
  --repository-format=docker --location=REGION
```

## 3) GKE clusters

Recommended:
- `crowd-cult-dev` cluster
- `crowd-cult-prod` cluster

Or single cluster with namespace separation if budget is constrained.

**Workload Identity:** enable on the cluster. For each node pool that runs workloads using WI, set:

```bash
gcloud container node-pools update NODE_POOL \
  --cluster=CLUSTER_NAME --zone=ZONE \
  --workload-metadata=GKE_METADATA
```

Without `GKE_METADATA`, pods may get **limited node OAuth scopes** and Cloud SQL Proxy / IAM calls can fail with `ACCESS_TOKEN_SCOPE_INSUFFICIENT`.

## 4) Cloud SQL

Provision:
- one SQL instance for dev
- one SQL instance for prod

Networking:
- prefer private IP + VPC native cluster
- allow only GKE workloads/subnets

## 5) DNS and static IP

Reserve global static IPs:
- `crowd-cult-dev-ip`
- `crowd-cult-prod-ip`

Set DNS A records:
- `api.dev.<domain>` -> dev ingress IP
- `app.dev.<domain>` -> dev ingress IP
- `admin.dev.<domain>` -> dev ingress IP
- `api.<domain>` -> prod ingress IP
- `app.<domain>` -> prod ingress IP
- `admin.<domain>` -> prod ingress IP

## 6) TLS

Choose one:
- GKE ManagedCertificate
- cert-manager with Google Cloud DNS solver

## 7) IAM for GitHub Actions

Prefer Workload Identity Federation.

Minimum roles for CI service account:
- `roles/artifactregistry.writer`
- `roles/container.developer`
- `roles/container.clusterViewer`
- `roles/secretmanager.secretAccessor` (only if CI reads secrets)
- `roles/iam.workloadIdentityUser` (binding for federation)

## 8) Secrets

Store sensitive values in Secret Manager:
- DB host/user/password/name
- OAuth client secrets
- JWT/session secrets

Sync pattern:
- CI fetches and applies runtime K8s secrets per environment
- never commit plaintext secrets into git
