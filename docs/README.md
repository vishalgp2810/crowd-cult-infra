# Crowd & Cult infrastructure documentation

Start here, then open the topic you need.

| Document | Purpose |
|----------|---------|
| [DEPLOYMENT-OVERVIEW.md](./DEPLOYMENT-OVERVIEW.md) | End-to-end architecture, what we implemented, known pitfalls, and links to repo-specific steps |
| [repo-crowd-cult-backend.md](./repo-crowd-cult-backend.md) | Backend: Docker, Cloud Build, env vars, DB jobs, GCS, Workload Identity |
| [repo-crowd-cult-frontend.md](./repo-crowd-cult-frontend.md) | Frontend: Docker, Cloud Build, `NEXT_PUBLIC_*` at build time |
| [repo-crowd-cult-admin.md](./repo-crowd-cult-admin.md) | Admin app: same patterns as frontend |
| [LOCAL-DATABASE-AND-STAGING.md](./LOCAL-DATABASE-AND-STAGING.md) | Connect to Cloud SQL from your laptop; checklist for a new stage (e.g. `staging`) |
| [VARIABLE-REFERENCE.md](./VARIABLE-REFERENCE.md) | Where each kind of setting lives (Secret vs ConfigMap vs rebuild) |
| [gcp-prerequisites.md](./gcp-prerequisites.md) | GCP APIs, Artifact Registry, GKE, DNS, IAM baselines |
| [operations-runbook.md](./operations-runbook.md) | Releases, rollback, secrets, monitoring |
| [cicd-github-actions.md](./cicd-github-actions.md) | GitHub Actions deploy workflow (if used) |
