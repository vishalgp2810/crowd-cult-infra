# crowd-cult-infra

Kubernetes manifests, environment templates, and **documentation** for deploying Crowd & Cult on GCP (GKE, Cloud SQL, GCS, Artifact Registry).

## Documentation index

All guides: **[docs/README.md](./docs/README.md)**

Highlights:

- **[DEPLOYMENT-OVERVIEW.md](./docs/DEPLOYMENT-OVERVIEW.md)** — full flow, pitfalls we fixed, architecture
- **[LOCAL-DATABASE-AND-STAGING.md](./docs/LOCAL-DATABASE-AND-STAGING.md)** — Cloud SQL from your machine + **new staging env checklist**
- **Per-repo manuals:** [backend](./docs/repo-crowd-cult-backend.md), [frontend](./docs/repo-crowd-cult-frontend.md), [admin](./docs/repo-crowd-cult-admin.md)

## Layout

- `k8s/base/` — Deployments, Services, Jobs, ServiceAccount, secret **template**
- `k8s/prod/` — Production ConfigMaps, Ingress, etc.

Each application repo also has a short `DEPLOYMENT.md` pointing back here.
