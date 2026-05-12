# Crowd & Cult Operations Runbook

## Release flow

1. Build and push images for backend/frontend/admin.
2. Apply config + base manifests in target namespace.
3. Run migration job (always set **namespace**; otherwise the Job lands in `default`):
   ```bash
   kubectl -n <namespace> delete job crowd-cult-backend-migrate --ignore-not-found
   kubectl -n <namespace> apply -f k8s/base/backend-migrate-job.yaml
   kubectl -n <namespace> wait --for=condition=complete job/crowd-cult-backend-migrate --timeout=300s
   kubectl -n <namespace> logs job/crowd-cult-backend-migrate
   ```
4. Optional — seed job (idempotent seeders; same namespace rule):
   ```bash
   kubectl -n <namespace> delete job crowd-cult-backend-seed --ignore-not-found
   kubectl -n <namespace> apply -f k8s/base/backend-seed-job.yaml
   kubectl -n <namespace> wait --for=condition=complete job/crowd-cult-backend-seed --timeout=300s
   ```
5. Roll deployments with desired image tags (or `kubectl rollout restart` if using `:latest` and a fresh pull is enough).
6. Validate health and endpoints.

## Rollback procedure

### App rollback

```bash
kubectl -n <namespace> rollout undo deployment/crowd-cult-backend
kubectl -n <namespace> rollout undo deployment/crowd-cult-frontend
kubectl -n <namespace> rollout undo deployment/crowd-cult-admin
```

### Migration rollback

If migration introduced regression:

```bash
kubectl -n <namespace> run db-rollback \
  --rm -i --tty \
  --image=<backend-image> \
  --env-from=configmap/crowd-cult-backend-config \
  --env-from=secret/crowd-cult-backend-secret \
  -- npm run migrate:undo
```

Use `migrate:undo:all` only with explicit approval.

## Secret management

- Source of truth: Google Secret Manager.
- Sync to K8s secret at deploy time.
- Never commit live secrets in git.
- Rotation:
  1. update secret in Secret Manager
  2. apply updated Kubernetes secret
  3. restart backend deployment

## Monitoring and alerting baseline

Create alerts for:
- Backend HTTP 5xx > 2% (5m)
- Pod restart count spikes
- CPU > 80% sustained (10m)
- Memory > 85% sustained (10m)
- Ingress latency p95 degradation

## Go-live checklist

- [ ] DNS records resolve to ingress IP
- [ ] TLS certificates valid on all subdomains
- [ ] `/health` endpoint healthy
- [ ] Frontend and admin can call backend successfully
- [ ] Cloud SQL connectivity verified
- [ ] GKE node pool uses `--workload-metadata=GKE_METADATA` if using Workload Identity
- [ ] Backend Secret includes `GCP__SIGNING_SERVICE_ACCOUNT` (same email as WI GSA) for private GCS + signed `readUrl`
- [ ] Migration job completed successfully
- [ ] HPA targets active
- [ ] Logging visible in Cloud Logging
- [ ] Rollback command tested in dev
