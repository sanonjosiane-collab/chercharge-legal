-- Customer device tokens for FCM → APNs push (inspection ready, etc.).

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.profiles (id) on delete cascade,
  customer_email text not null,
  fcm_token text not null,
  platform text not null default 'ios',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint device_tokens_email_nonempty check (length(trim(customer_email)) > 3),
  constraint device_tokens_token_nonempty check (length(trim(fcm_token)) > 20),
  constraint device_tokens_fcm_token_unique unique (fcm_token)
);

create index if not exists device_tokens_customer_id_idx
  on public.device_tokens (customer_id);

create index if not exists device_tokens_customer_email_idx
  on public.device_tokens (lower(customer_email));

alter table public.device_tokens enable row level security;

-- Edge Functions use the service role; no direct client RLS policies required.
