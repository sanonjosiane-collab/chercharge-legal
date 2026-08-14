# Tesla Fleet API — chercharing.com

Your Tesla partner domain is **`chercharing.com`**.

Public key (hosted):

```
https://chercharing.com/.well-known/appspecific/com.tesla.3p.public-key.pem
```

Private key (local only, never commit): `.tesla-keys/private-key.pem`

## 1. Point the domain at this site

If you use **GitHub Pages** for the `docs/` folder:

1. Repo Settings → Pages → Deploy from branch → `/docs` (or your usual Pages source).
2. Custom domain: `chercharing.com`
3. DNS at your registrar:
   - **A** records for GitHub Pages, or
   - **CNAME** `www` → `YOUR_USER.github.io` and apex as GitHub documents
4. Wait until `https://chercharing.com` loads, then open the public-key URL above — you must see `-----BEGIN PUBLIC KEY-----`.

If you use **Cloudflare / Vercel / Netlify** instead, upload/sync the `docs/` contents (including `.well-known/`) and attach `chercharing.com`.

## 2. Tesla developer portal

For app Client ID `00ec10b5-73b4-4123-9254-32d91d31c0ca`:

| Setting | Value |
|--------|--------|
| Allowed Origin(s) | `https://chercharing.com` |
| Redirect URI | `https://kjzbiiechaiodwdxstfz.supabase.co/functions/v1/tesla-oauth-callback` |

## 3. Register partner account (fixes 412)

```bash
# Partner token (NA)
curl -s -X POST 'https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials' \
  -d 'client_id=YOUR_CLIENT_ID' \
  -d 'client_secret=YOUR_CLIENT_SECRET' \
  -d 'audience=https://fleet-api.prd.na.vn.cloud.tesla.com' \
  -d 'scope=openid vehicle_device_data vehicle_cmds vehicle_location'
```

Then:

```bash
curl -s -X POST 'https://fleet-api.prd.na.vn.cloud.tesla.com/api/1/partner_accounts' \
  -H "Authorization: Bearer PARTNER_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"domain":"chercharing.com"}'
```

Verify:

```bash
curl -s 'https://fleet-api.prd.na.vn.cloud.tesla.com/api/1/partner_accounts/public_key?domain=chercharing.com' \
  -H "Authorization: Bearer PARTNER_ACCESS_TOKEN"
```

Recommended: also register EU with audience / base URL `https://fleet-api.prd.eu.vn.cloud.tesla.com`.

## 4. Retry Connect Tesla in the Chercharge app
