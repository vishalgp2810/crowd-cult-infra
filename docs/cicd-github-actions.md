# GitHub Actions CI/CD Guide

## Workflows

- App repositories:
  - `crowd-cult-backend/.github/workflows/build-and-push.yml`
  - `crowd-cult-frontend/.github/workflows/build-and-push.yml`
  - `crowd-cult-admin/.github/workflows/build-and-push.yml`
- Infra repository:
  - `crowd-cult-infra/.github/workflows/deploy-gke.yml`

## Required GitHub secrets

- `GCP_WORKLOAD_IDENTITY_PROVIDER`
- `GCP_SERVICE_ACCOUNT`
- `GCP_PROJECT_ID`
- `GCP_REGION`
- `GKE_LOCATION`
- `GKE_CLUSTER_DEV`
- `GKE_CLUSTER_PROD`

## Branch policy

- `develop` pushes build/push images used for dev deployments
- `main` pushes build/push images used for prod deployments
- infra deployment is manual (`workflow_dispatch`) with explicit image tags

## Deploy steps in infra workflow

1. Authenticate to GCP via workload identity federation.
2. Fetch cluster credentials for dev/prod.
3. Apply namespace, configmaps, base manifests, ingress.
4. Update deployment image tags with `kubectl set image`.
5. Wait for rollout completion and fail if unhealthy.

## Recommended protections

- Require pull request review for `main`.
- Protect workflow environments with approvers.
- Restrict who can run prod deployment workflow.
