-- Store raw APNs device tokens so Edge can send via Apple directly when
-- Firebase FCM returns THIRD_PARTY_AUTH_ERROR (missing/invalid APNs .p8 in Console).

alter table public.device_tokens
  add column if not exists apns_token text;

create index if not exists device_tokens_apns_token_idx
  on public.device_tokens (apns_token)
  where apns_token is not null;
