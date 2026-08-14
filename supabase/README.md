# Chercharge Supabase Backend

## Setup

1. Create a project at [supabase.com](https://supabase.com).
2. In the SQL editor (or `npx supabase db push`), run migrations in order:
   - [`migrations/20260710160000_init.sql`](migrations/20260710160000_init.sql)
   - [`migrations/20260710180000_inspection_storage.sql`](migrations/20260710180000_inspection_storage.sql)
   - [`migrations/20260711000000_preorder_promo.sql`](migrations/20260711000000_preorder_promo.sql)
   - [`migrations/20260712000000_preorder_two_tier.sql`](migrations/20260712000000_preorder_two_tier.sql)
   - [`migrations/20260714190000_preorder_foundation_hardening.sql`](migrations/20260714190000_preorder_foundation_hardening.sql)
3. Deploy Edge Functions:

```bash
npx supabase login
npx supabase link --project-ref <your-project-ref>
npx supabase functions deploy advance-booking
npx supabase functions deploy create-payment-intent
npx supabase functions deploy create-customer-booking
npx supabase functions deploy get-preorder-status
npx supabase functions deploy create-preorder-payment
npx supabase functions deploy confirm-preorder
npx supabase functions deploy create-setup-intent
npx supabase functions deploy list-payment-methods
npx supabase functions deploy detach-payment-method
npx supabase functions deploy stripe-webhook
npx supabase functions deploy tesla-oauth-callback
npx supabase functions deploy tesla-oauth-exchange
```

4. **Stripe payments (Book a Charge + Pre-order) — live or test**

Chercharge is a **native iOS (SwiftUI)** app + **Supabase Edge Functions** (not Expo). The iOS app never holds a secret key.

Flow:

1. App charges via PaymentSheet (`create-payment-intent`), then calls `create-customer-booking` so the job appears in the driver open-jobs pool
2. Function creates a Stripe PaymentIntent with server-only `STRIPE_SECRET_KEY` (`sk_live_…` or `sk_test_…`)
3. App receives only `{ clientSecret, paymentIntentId }` and presents **Stripe PaymentSheet** with matching `pk_live_…` or `pk_test_…`

### CLIENT (iOS) — where to set

| Variable | Where | Value |
|----------|--------|--------|
| `STRIPE_PUBLISHABLE_KEY` | `Chercharge/Secrets.plist` (gitignored) | **`pk_test_…`** (Test mode on) or **`pk_live_…`** (production) |
| `SUPABASE_URL` | same plist | `https://<project-ref>.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | same plist | `sb_publishable_…` |

Never put `sk_live_`, `sk_test_`, or `whsec_` in the iOS app / plist / git.

Use matching modes: iOS `pk_test_…` with Edge `sk_test_…`, or `pk_live_…` with `sk_live_…`.

### BACKEND (Supabase Edge secrets) — where to set

Enter these in the terminal against your linked project (**do not paste secret keys into Cursor chat**):

```bash
cd /Users/Shared/Chercharge

# 1) Stripe secret — sk_test_… for local testing, or sk_live_… for production
npx supabase secrets set STRIPE_SECRET_KEY=sk_test_YOUR_SECRET_KEY

# 2) After creating the webhook endpoint, set the signing secret:
npx supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_YOUR_WEBHOOK_SIGNING_SECRET

# 3) Redeploy payment + booking functions
npx supabase functions deploy create-payment-intent
npx supabase functions deploy create-customer-booking
npx supabase functions deploy create-preorder-payment
npx supabase functions deploy confirm-preorder
npx supabase functions deploy stripe-webhook
```

| Variable | Where | Value |
|----------|--------|--------|
| `STRIPE_SECRET_KEY` | Supabase Edge secrets (`npx supabase secrets set`) | **`sk_test_…`** or **`sk_live_…`** (match iOS publishable key mode) |
| `STRIPE_WEBHOOK_SECRET` | same | **`whsec_…`** from the Stripe webhook endpoint |
| `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` | auto-injected by Supabase for Edge Functions | do not put in the iOS app |

You can also set secrets in the dashboard:
[Supabase → Project → Edge Functions → Secrets](https://supabase.com/dashboard/project/_/settings/functions)

### LIVE webhook (required for production Founding Access)

There was previously **no** Stripe webhook. You **must** create a **new LIVE-mode** webhook (test-mode webhooks do not deliver live events):

1. Stripe Dashboard → **Developers → Webhooks** → ensure **Test mode is off**
2. **Add endpoint**
3. Endpoint URL:

```
https://<PROJECT_REF>.supabase.co/functions/v1/stripe-webhook
```

4. Events to send: `payment_intent.succeeded`
5. Copy the endpoint **Signing secret** (`whsec_…`) into `STRIPE_WEBHOOK_SECRET` as above
6. Deploy `stripe-webhook` if you have not already

Client-side `confirm-preorder` still works; the webhook is the safety net when the app is killed after a successful charge.

### Go-live checklist

| Item | Where |
|------|--------|
| Stripe account activated | Stripe Dashboard onboarding |
| `STRIPE_PUBLISHABLE_KEY` = `pk_live_…` | `Chercharge/Secrets.plist` |
| `STRIPE_SECRET_KEY` = `sk_live_…` | `npx supabase secrets set` |
| `STRIPE_WEBHOOK_SECRET` = `whsec_…` | `npx supabase secrets set` |
| Payment + webhook functions redeployed | CLI |
| App rebuilt after plist change | Xcode |
| Smoke test with a real card (your own) | Live Dashboard + `preorders` row |

If anything is still a `YOUR_…` placeholder, Stripe PaymentSheet stays off.

#### Historical note — test mode

Test and live keys are both supported. Keep modes matched (`pk_test_` + `sk_test_`, or `pk_live_` + `sk_live_`). For App Store production builds, use live keys.

5. Pre-order promo — deploy the preorder Edge Functions:

```bash
npx supabase functions deploy get-preorder-status
npx supabase functions deploy create-preorder-payment
npx supabase functions deploy confirm-preorder
npx supabase functions deploy stripe-webhook
```

Live pre-orders require **Supabase Auth** (not guest mode) so early-bird slots are tracked per account.

6. Tesla Fleet OAuth — domain **`chercharing.com`**. See [`docs/TESLA_FLEET_SETUP.md`](../docs/TESLA_FLEET_SETUP.md).

Redirect URI must be exactly:

```
https://kjzbiiechaiodwdxstfz.supabase.co/functions/v1/tesla-oauth-callback
```

Allowed Origin: `https://chercharing.com`

Public key URL:

```
https://chercharing.com/.well-known/appspecific/com.tesla.3p.public-key.pem
```

Set **server-only** secrets (never put Client ID or Client Secret in the iOS app or git):

```bash
npx supabase secrets set \
  TESLA_CLIENT_ID=your_client_id \
  TESLA_CLIENT_SECRET=your_client_secret \
  TESLA_REDIRECT_URI=https://kjzbiiechaiodwdxstfz.supabase.co/functions/v1/tesla-oauth-callback \
  TESLA_AUDIENCE=https://fleet-api.prd.na.vn.cloud.tesla.com
```

The iOS app calls `tesla-oauth-exchange` with `action: "authorize_url"` to start OAuth, then exchanges the code via the same function. `tesla-oauth-callback` bridges Tesla’s HTTPS redirect to `chercharge://oauth/tesla`.

Optional in iOS `Secrets.plist`: `TESLA_AUDIENCE` (defaults to NA Fleet API). Do **not** add `TESLA_CLIENT_ID` or `TESLA_CLIENT_SECRET` to the plist.

7. Copy iOS secrets:

```bash
cp Chercharge/Secrets.example.plist Chercharge/Secrets.plist
```

Fill in:

- **Project URL** and **publishable key** (`sb_publishable_…`) from Supabase → Project Settings → API Keys
  - Prefer the new publishable key. Legacy `anon` JWT still works if you keep `SUPABASE_ANON_KEY` in the plist instead.
  - New keys must go in the `apikey` header only (the app handles this). Do not use them as `Authorization: Bearer`.
- **STRIPE_PUBLISHABLE_KEY** = `pk_live_…` for production. Never put `sk_` here.
- **TESLA_*** keys as above when using live Fleet OAuth

After changing to `sb_publishable_…`, redeploy functions that authorize via `apikey` (JWT verify is off for these):

```bash
npx supabase functions deploy create-payment-intent
npx supabase functions deploy tesla-oauth-exchange
```

Stripe PaymentSheet is active only when both Supabase and the Stripe publishable key are real (not placeholders).

8. In Supabase Auth settings, disable “Confirm email” for local MVP testing (already reflected in `config.toml` for local).

## Inspection media storage

1. Run [`migrations/20260710180000_inspection_storage.sql`](migrations/20260710180000_inspection_storage.sql) to create the `inspections` bucket.
2. Pre-trip and post-trip media upload via the Supabase Storage API when `Secrets.plist` is configured.
3. Inspection files are always kept on the booking record locally as well.

## Remote push (direct APNs + FCM)

Customer inspection-ready / driver-arrived alerts when the app is quit use **direct APNs** (preferred) with **FCM as fallback**.

`THIRD_PARTY_AUTH_ERROR` from FCM means Firebase Console is missing a valid Apple `.p8` — Edge bypasses that by talking to Apple with `APNS_*` secrets.

### One-time Apple setup

1. In [Apple Developer](https://developer.apple.com/account/resources/authkeys/list) create an **Apple Push Notifications** key (`.p8`).
2. Xcode: enable **Push Notifications** (entitlements already include `aps-environment` = development for Debug).
3. Use a **physical iPhone** for real APNs (Simulator often cannot receive remote pushes).
4. Optional (so FCM works too): Firebase Console → **chercharge-5ff77-6566e** → Cloud Messaging → upload the same `.p8`, Key ID, Team ID for bundle `Chercharge.Chercharge`.

### Supabase

```bash
# Preferred path when Firebase APNs auth fails: direct Apple Push
npx supabase secrets set APNS_AUTH_KEY="$(cat path/to/AuthKey_XXXX.p8)"
npx supabase secrets set APNS_KEY_ID=XXXX
npx supabase secrets set APNS_TEAM_ID=7N56AZ3JBJ
npx supabase secrets set APNS_BUNDLE_ID=Chercharge.Chercharge
npx supabase secrets set APNS_PRODUCTION=false   # true for TestFlight/App Store

# Also keep FCM aligned with GoogleService-Info.plist (chercharge-5ff77-6566e)
npx supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat path/to/service-account.json)"
npx supabase secrets set FIREBASE_PROJECT_ID=chercharge-5ff77-6566e

npx supabase functions deploy register-device-token
npx supabase functions deploy notify-booking-push
```

Apply `device_tokens.apns_token` (migration `20260730250000_device_tokens_apns.sql`) if not already present.

**Critical Firebase alignment (SenderId mismatch) when using FCM:**
- iOS `GoogleService-Info.plist` → project `chercharge-5ff77-6566e`, sender `917525221485`
- Edge `FIREBASE_SERVICE_ACCOUNT_JSON` must be from **that same project**

Debug trigger HTTP + push result:
```sql
select * from public.push_events_invoke_status limit 10;
select * from net._http_response order by created desc limit 10;
select customer_email, left(fcm_token,12) as fcm, left(apns_token,12) as apns, updated_at
from public.device_tokens order by updated_at desc limit 10;
```

Flow:
1. Customer app allows notifications → uploads **FCM + APNs** tokens via `register-device-token`
2. Driver submits inspection / arrives → inserts `push_events` (and/or calls `notify-booking-push`)
3. Trigger `push_events_notify_booking_push` POSTs to `notify-booking-push` with `from_push_event: true`
4. Edge looks up `device_tokens` and sends via **direct APNs** when `apns_token` + `APNS_*` secrets exist (else FCM)

Apply the trigger (migration or SQL Editor paste):
- Migration: `supabase/migrations/20260730230000_fix_push_events_invoke.sql`
- Paste script: `supabase/sql/push_events_notify_trigger_paste.sql`
- Vault must contain `service_role_key` (or publishable) so `pg_net` can authorize the Edge call
- Note: `delivered_at` is set by the customer status poll (local alert ack), not by FCM success — use `fcm_sent_at` / `push_events_invoke_status` for remote delivery

## Inspection auto-approve (server source of truth)

Pickup / return inspections auto-approve **15 seconds** after the booking becomes ready for review.

- Deadlines are stored on `bookings.customer_approval_deadline` / `return_approval_deadline` (DB trigger).
- `auto_approve_due_booking(id)` advances one booking when its deadline has passed (`pickup_approval_method` / `return_approval_method` = `auto`).
- `auto_approve_expired_bookings()` sweeps all due rows (pg_cron every minute when available).
- Edge `schedule-auto-approve` is invoked by trigger when a deadline is stamped — waits until the deadline, then approves even if both apps are closed.
- Customer app polls `create-customer-booking` `action: "status"` every ~3s and mirrors server status / deadlines (does not invent the window for cloud trips).

Apply:
1. SQL Editor → paste `supabase/sql/server_auto_approve_source_of_truth_paste.sql`
2. Deploy functions:
   - `npx supabase functions deploy schedule-auto-approve --no-verify-jwt`
   - `npx supabase functions deploy create-customer-booking --no-verify-jwt`
3. Vault must contain `service_role_key` (same as push invoke) so `pg_net` can call `schedule-auto-approve`

## What this provides

- Email/password accounts (`profiles` + seeded Tesla vehicles)
- Bookings with RLS (customers only see their own)
- Realtime updates on `bookings.status`
- `advance-booking` Edge Function advances status every 3s for demos (no driver app yet)
- If the Edge Function is not deployed yet, the iOS app falls back to advancing status via authenticated updates so Tracking still works
- Inspection media bucket + customer approval gate before pickup
- `create-payment-intent` Edge Function — Stripe PaymentIntents for Book a Charge (PaymentSheet on iOS)
- `create-setup-intent` / `list-payment-methods` / `detach-payment-method` — save cards on Payment methods (SetupIntent)
- `get-preorder-status` / `create-preorder-payment` / `confirm-preorder` — pay-now pre-launch orders with two-tier early-bird pricing ($10 lifetime / $39.99 year / $49.99 standard)
- `stripe-webhook` — live `payment_intent.succeeded` → `complete_preorder` for Founding Access
- `tesla-oauth-callback` / `tesla-oauth-exchange` — Tesla Fleet OAuth bridge + token exchange

### Pre-order pricing

| Slots | Locked rate | Terms |
|-------|-------------|-------|
| First **5** | **$10** / charge | Lifetime · **1 car only** (until that car is no longer in service) |
| Next **45** | **$39.99** / charge | **1 year** · **1 car only** |
| After 50 | **$49.99** / charge | Standard per-booking rate |

### Test cards

| Card | Result |
|------|--------|
| `4242 4242 4242 4242` | Success |
| `4000 0000 0000 0002` | Declined |

Use any future expiry and any 3-digit CVC.
