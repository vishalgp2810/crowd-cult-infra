# Manual: `crowd-cult-frontend`

## Build-time vs runtime (critical)

Next.js inlines any **`NEXT_PUBLIC_*`** variable when you run **`next build`**.  
Values in the Kubernetes ConfigMap **after** build **do not** change the JavaScript bundle the browser already downloaded.

So: **the API base URL must be correct at Docker build time** (or you must rebuild when the API host changes).

## Dockerfile pattern

The `builder` stage sets:

- `ARG NEXT_PUBLIC_API_URL=https://api.example.com` (default in repo targets production host)
- `ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL`
- Optional: `NEXT_PUBLIC_SITE_URL` for OAuth / site-origin fallbacks

Then `RUN npm run build`.

### Override for another environment (e.g. staging)

Pass build args when building locally:

```bash
docker build \
  --build-arg NEXT_PUBLIC_API_URL=https://api.staging.example.com \
  --build-arg NEXT_PUBLIC_SITE_URL=https://staging.example.com \
  -t frontend:staging .
```

With Cloud Build, use a `cloudbuild.yaml` that passes `--build-arg`, or maintain a staging-specific Dockerfile / substitution.

## Cloud Build (typical)

From **frontend repo root** (replace `YOUR_PROJECT_ID` for staging / other envs).

> **Shell note**: bash uses `\` for line continuation, PowerShell uses backtick `` ` ``. The simplest portable form is a **single-line** command — use that if you copy from a PowerShell-style mistake.

**bash / zsh:**

```bash
gcloud builds submit \
  --tag asia-south1-docker.pkg.dev/YOUR_PROJECT_ID/crowd-cult-frontend/crowd-cult-frontend:latest \
  .
```

**PowerShell:**

```powershell
gcloud builds submit `
  --tag asia-south1-docker.pkg.dev/YOUR_PROJECT_ID/crowd-cult-frontend/crowd-cult-frontend:latest `
  .
```

**Single-line (any shell):**

```bash
gcloud builds submit --tag asia-south1-docker.pkg.dev/YOUR_PROJECT_ID/crowd-cult-frontend/crowd-cult-frontend:latest .
```

### Production (`crowdandcultprod`)

bash / zsh:

```bash
gcloud config set project crowdandcultprod

gcloud builds submit \
  --tag asia-south1-docker.pkg.dev/crowdandcultprod/crowd-cult-frontend/crowd-cult-frontend:latest \
  .
```

PowerShell (Windows):

```powershell
gcloud config set project crowdandcultprod

gcloud builds submit `
  --tag asia-south1-docker.pkg.dev/crowdandcultprod/crowd-cult-frontend/crowd-cult-frontend:latest `
  .
```

Single-line (any shell):

```bash
gcloud builds submit --tag asia-south1-docker.pkg.dev/crowdandcultprod/crowd-cult-frontend/crowd-cult-frontend:latest .
```

## Kubernetes

- Deployment uses **standalone** Next output (`node server.js`).
- ConfigMap can set `NODE_ENV`, `PORT`, and **runtime** server vars only — **not** a substitute for rebuilding with the right `NEXT_PUBLIC_API_URL`.

After a new image (template):

```bash
kubectl rollout restart deployment/crowd-cult-frontend -n YOUR_NAMESPACE
kubectl rollout status  deployment/crowd-cult-frontend -n YOUR_NAMESPACE
```

### Production rollout (`crowd-cult-prod` namespace)

```bash
kubectl rollout restart deployment/crowd-cult-frontend -n crowd-cult-prod
kubectl rollout status  deployment/crowd-cult-frontend -n crowd-cult-prod
```

## Client code contract

- API client: `src/lib/api/client.ts` uses `process.env.NEXT_PUBLIC_API_URL`.
- Upload responses: use **`readUrl`** for images, **`url`** for DB persistence (see backend manual).

See also: [DEPLOYMENT-OVERVIEW.md](./DEPLOYMENT-OVERVIEW.md).
