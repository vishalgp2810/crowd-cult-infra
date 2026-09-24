# Razorpay Route (Crowd&Cult backend)

## Environment variables

Map to `node-config` via [`crowd-cult-backend/config/custom-environment-variables.json`](../crowd-cult-backend/config/custom-environment-variables.json).

| Variable | Config path | Required | Notes |
|----------|-------------|----------|--------|
| `RAZORPAY__KEY_ID` | `RAZORPAY.KEY_ID` | Yes | Test or live key from Razorpay Dashboard |
| `RAZORPAY__KEY_SECRET` | `RAZORPAY.KEY_SECRET` | Yes | **Secret** — store only in Secret Manager / K8s Secret |
| `RAZORPAY__WEBHOOK_SECRET` | `RAZORPAY.WEBHOOK_SECRET` | Yes (prod) | Must match the secret configured for the webhook in Razorpay |
| `RAZORPAY__BASE_URL` | `RAZORPAY.BASE_URL` | Optional | Default `https://api.razorpay.com/v1` |
| `RAZORPAY__BASE_URL_V2` | `RAZORPAY.BASE_URL_V2` | Optional | Default `https://api.razorpay.com/v2` (linked accounts) |
| `RAZORPAY__CURRENCY` | `RAZORPAY.CURRENCY` | Optional | Default `INR` |
| `RAZORPAY__ON_HOLD_DAYS` | `RAZORPAY.ON_HOLD_DAYS` | Optional | Escrow hold window (default in app config) |
| `RAZORPAY__ACCOUNT_NUMBER` | `RAZORPAY.ACCOUNT_NUMBER` | No | Reserved for future settlement wiring; not read by transfer/order code today |

Kubernetes: add the `RAZORPAY__*` keys to `crowd-cult-backend-secret` (see [`k8s/base/secrets.template.yaml`](../k8s/base/secrets.template.yaml)), then rollout restart the backend.

## Webhook URL

1. In **Razorpay Dashboard** → **Webhooks**, add an endpoint:
   - **URL:** `https://<your-api-host>/webhooks/razorpay`
   - **Secret:** generate a strong random string; set the same value as `RAZORPAY__WEBHOOK_SECRET`.
2. Subscribe to events your deployment uses (payments, orders, transfers, refunds, linked accounts) — the backend stores all received events in `webhookEvent` and dispatches known types in `src/Services/Payment/webhookService.js`.
3. Razorpay expects a **2xx** response within a few seconds. Signature verification uses the **raw request body**; the Fastify webhook plugin must not JSON-parse the body before HMAC verification.

## Linked account business category / subcategory

Razorpay validates **`profile.category`** and **`profile.subcategory`** as a matching pair on `POST /v2/accounts` and `PATCH /v2/accounts/:id`. Allowed values are in the [Route integration guide](https://razorpay.com/docs/payments/route/integration-guide/) (Business Category / Business Sub-Category). Examples:

- **Not valid as category:** `entertainment`, `professional_services` (these were wrong guesses in early UI).
- **Valid examples:** `services` + `consulting`, `services` + `bands_orchestras_and_miscellaneous_entertainers`, `media_and_entertainment` + `ticketing`, `healthcare` + `clinic`, `financial_services` + `accounting`.

The artist Vault ([`VaultSection`](../../crowd-cult-frontend/src/components/artist/VaultSection.jsx)) defaults to **`services` / `bands_orchestras_and_miscellaneous_entertainers`**. `linkedAccountService.normalizeKycProfile` remaps legacy `entertainment` → `media_and_entertainment` and `professional_services` → `services`, plus old subcategory slugs.

Authoritative enums: [Route integration guide — Appendix](https://razorpay.com/docs/payments/route/integration-guide/#kyc-requirements) (business type, category, sub-category tables).

## KYC requirements (linked account onboarding)

Crowd&Cult artists typically use **`business_type: individual`**. Per Razorpay’s [KYC table](https://razorpay.com/docs/payments/route/integration-guide/#kyc-requirements):

| Requirement | API | Individual |
|-------------|-----|------------|
| Owner / signatory PAN | Stakeholder (`POST/PATCH …/stakeholders`) | **Yes** — Vault collects stakeholder PAN |
| Business PAN | Linked account (`POST/PATCH /v2/accounts` `legal_info.pan`) | **N/A** — optional in UI; proprietorship+ may need it |
| Bank account | Product configuration (`POST/PATCH …/products`) | **Yes** — Vault collects IFSC + account |
| GST | Linked account `legal_info.gst` | **N/A** for individual — optional field in Vault |

Flow in code: `POST /v2/accounts` → stakeholder → `POST /v2/accounts/:id/products` (route) → `PATCH` product with settlements + `tnc_accepted`. See `linkedAccountService.js`.

## Artist payout API (Crowd&Cult)

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/artists/me/payout-account` | Full onboarding submit (validates payload, runs all Razorpay steps) |
| `POST` | `/artists/me/payout-account/link` | Attach existing `acc_…` only; sets **`INCOMPLETE`** until submit |
| `GET` | `/artists/me/payout-account?sync=true` | Read status; optional Razorpay sync (discovers product id if missing locally) |

### `kycStatus` values

| Status | Meaning |
|--------|---------|
| `NOT_STARTED` | No linked account |
| `INCOMPLETE` | `acc_…` exists but `stakeholderId` and/or `productConfigurationId` missing in `kycMeta` |
| `SUBMITTED` / `UNDER_REVIEW` | Full API onboarding done; Razorpay reviewing |
| `ACTIVATED` | Route product active — **required before booking payments** |
| `NEEDS_CLARIFICATION` / `REJECTED` | Razorpay blocked or rejected; resubmit from Vault |

Response `payoutAccount.meta` includes `onboardingComplete`, `missingSteps` (`stakeholder`, `bank_product`), `requirements` from Razorpay when present, `canAcceptBookings` (true only when `kycStatus` is `ACTIVATED`), and `activationVerification` (steps to confirm activation in Razorpay Dashboard while local status is `SUBMITTED` / `UNDER_REVIEW`).

### Required submit payload

Validated in `kycPayloadValidation.js` before any Razorpay call:

- Contact: `email`, `phone`, `legalBusinessName`, `contactName`, `businessType`
- `profile.category`, `profile.subcategory`, `profile.addresses.registered` (street1, city, state, postal_code, country)
- `legalInfo.pan` — **only** for non-individual business types (omit on linked account for `individual`)
- `stakeholder` (name, email, phone, `kyc.pan`) — **required**; genuine PAN (no server-side substitution)
- `bank` (`ifsc_code`, `account_number`, `beneficiary_name`) — **beneficiary_name must match `legalBusinessName`** (case-insensitive, normalized whitespace)
- `tncAccepted: true`
- Genuine email (not `@example.com` / `@test.` placeholders in test mode)

**Link does not replace submit.** After link, artist must complete the Vault form and `POST /payout-account`.

**Phone shapes:** On [create linked account](https://razorpay.com/docs/api/payments/route/create-linked-account/), `phone` is a scalar (8–15 digits). On [create stakeholder](https://razorpay.com/docs/api/payments/route/create-stakeholder/), `phone` must be `{ "primary": "…", "secondary": "…" }` — a plain string returns `400` (“The phone must be an array.”). The backend maps Vault’s string to that object in `linkedAccountService.js`.

## Local development

- Expose the API with a tunnel (e.g. ngrok) if you want the dashboard to deliver webhooks to your laptop.
- Alternatively, rely on **Checkout callback + confirm** flow and poll Razorpay for debugging; webhooks are still recommended for transfer/refund/account sync.

## Route transfer methods (ticket #19152305)

| Razorpay method | Crowd&Cult |
|-----------------|------------|
| Order ID — `transfers` on order create | **Yes** — `paymentOrderService.createBookingOrder` |
| Payment ID — split after capture | **No** — not required for escrow marketplace |
| Direct transfer — balance → linked account | **No** — not required |

Post-create lifecycle: `PATCH /v1/transfers/:id` (release `on_hold`), reversals on refund — see `transferService.js`.

## Activation verification (ticket #19152305)

Before replying to Razorpay support, confirm activation in **both** places:

1. **API** — `GET /artists/me/payout-account?sync=true` → `kycStatus: ACTIVATED`, `meta.canAcceptBookings: true`.
2. **Dashboard** — Route → Linked accounts → open `acc_…` → status **Activated** (not only `created` / `under_review`).

Vault shows `activationVerification` steps when onboarding is API-complete but Razorpay has not activated yet.

## Manual onboarding test matrix

1. **Fresh artist** — Vault with **genuine** PAN, bank, email → Submit → `meta.onboardingComplete: true`; **Refresh status** until `ACTIVATED`.
2. **Beneficiary mismatch** — `400` if `bank.beneficiary_name` ≠ `legalBusinessName`.
3. **Submit without bank** — `400` from API before Razorpay; no orphan `acc_`.
4. **Link only** — `POST /link` with `acc_…` → `kycStatus: INCOMPLETE`, Vault checklist + form visible.
5. **Orphan reference_id** — Link then Submit completes stakeholder + product.
6. **Booking gate** — Payment blocked until `ACTIVATED` (unchanged).
7. **Backfill** — Rows with `acc_` but missing `kycMeta` ids migrate to `INCOMPLETE`.

## Post-deployment checks

1. Create a **test** Razorpay order with Route transfers (artist linked account must be **activated**).
2. Complete Checkout and confirm payment; booking should reach **ESCROWED** and `webhookEvent` should show related events.
3. Optional: trigger a test webhook from the dashboard and confirm **200** and a new `webhookEvent` row.

## Admin refund API

Platform admins can call:

`POST /admin/bookings/:bookingId/refund`

Body (JSON, all optional except implied payment):

- `razorpayPaymentId` — omit to use the latest **CAPTURED** `paymentTransaction` for the booking.
- `amount` — rupees; omit for **full** refund.
- `reason` — stored on the refund notes / record.

Requires JWT with role `PLATFORM_ADMIN` or `ADMIN`.
