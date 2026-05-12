# Manual: `crowd-cult-admin`

This app follows the **same rules** as the frontend.

## `NEXT_PUBLIC_*` at build time

- Set `NEXT_PUBLIC_API_URL` in the Dockerfile **builder** stage **before** `npm run build`.
- Default in the repo Dockerfile should match your **admin** + **API** deployment (e.g. `https://api.yourdomain.com`).

## Cloud Build

From **admin repo root**:

```bash
gcloud builds submit \
  --tag asia-south1-docker.pkg.dev/YOUR_PROJECT_ID/crowd-cult-admin/crowd-cult-admin:latest \
  .
```

## Staging / multiple APIs

Rebuild with `--build-arg NEXT_PUBLIC_API_URL=...` pointing at the **staging** API host; do not rely on runtime ConfigMap alone to switch API hosts in the browser bundle.

## Kubernetes

```bash
kubectl rollout restart deployment/crowd-cult-admin -n YOUR_NAMESPACE
```

For more context: [repo-crowd-cult-frontend.md](./repo-crowd-cult-frontend.md) and [DEPLOYMENT-OVERVIEW.md](./DEPLOYMENT-OVERVIEW.md).
