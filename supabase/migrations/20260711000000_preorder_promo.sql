-- Pre-launch pre-order with limited early-bird slots.
-- Users pay now; credit is applied to their first charge at launch.

create table public.promo_campaigns (
  id text primary key,
  name text not null,
  max_slots integer not null check (max_slots > 0),
  discount_cents integer not null check (discount_cents >= 0),
  standard_price_cents integer not null check (standard_price_cents > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.promo_campaigns (
  id,
  name,
  max_slots,
  discount_cents,
  standard_price_cents
)
values (
  'early_bird_50',
  'First 50 pre-orders',
  50,
  1000,
  4999
);

alter table public.profiles
  add column if not exists account_credit_cents integer not null default 0 check (account_credit_cents >= 0),
  add column if not exists preorder_credit_consumed boolean not null default false;

create type public.preorder_status as enum (
  'pending',
  'completed',
  'failed',
  'cancelled'
);

create table public.preorders (
  id uuid primary key default gen_random_uuid(),
  campaign_id text not null references public.promo_campaigns (id),
  user_id uuid not null references public.profiles (id) on delete cascade,
  status public.preorder_status not null default 'pending',
  amount_cents integer not null check (amount_cents > 0),
  promo_applied boolean not null default false,
  stripe_payment_intent_id text unique,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (campaign_id, user_id)
);

create index preorders_campaign_status_idx
  on public.preorders (campaign_id, status);

create index preorders_user_id_idx
  on public.preorders (user_id);

alter table public.promo_campaigns enable row level security;
alter table public.preorders enable row level security;

create policy "Anyone can view active promo campaigns"
  on public.promo_campaigns for select
  using (active = true);

create policy "Users can view own preorders"
  on public.preorders for select
  using (auth.uid() = user_id);

-- Server-side helpers (called from Edge Functions with service role).

create or replace function public.get_preorder_quote(p_campaign_id text, p_user_id uuid)
returns table (
  price_cents integer,
  promo_applied boolean,
  slots_remaining integer,
  max_slots integer,
  standard_price_cents integer,
  discount_cents integer,
  already_preordered boolean,
  existing_status public.preorder_status,
  account_credit_cents integer,
  preorder_credit_consumed boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign public.promo_campaigns%rowtype;
  v_redeemed_count integer;
  v_existing public.preorders%rowtype;
  v_profile public.profiles%rowtype;
begin
  select * into v_campaign
  from public.promo_campaigns
  where id = p_campaign_id and active = true;

  if not found then
    raise exception 'Campaign not found';
  end if;

  select * into v_profile
  from public.profiles
  where id = p_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;

  select * into v_existing
  from public.preorders
  where campaign_id = p_campaign_id and user_id = p_user_id;

  select count(*)::integer into v_redeemed_count
  from public.preorders
  where campaign_id = p_campaign_id and status = 'completed';

  slots_remaining := greatest(0, v_campaign.max_slots - v_redeemed_count);
  max_slots := v_campaign.max_slots;
  standard_price_cents := v_campaign.standard_price_cents;
  discount_cents := v_campaign.discount_cents;
  already_preordered := v_existing.id is not null;
  existing_status := v_existing.status;
  account_credit_cents := coalesce(v_profile.account_credit_cents, 0);
  preorder_credit_consumed := coalesce(v_profile.preorder_credit_consumed, false);

  if v_existing.status = 'completed' then
    price_cents := v_existing.amount_cents;
    promo_applied := v_existing.promo_applied;
    return next;
    return;
  end if;

  if v_redeemed_count < v_campaign.max_slots then
    price_cents := v_campaign.standard_price_cents - v_campaign.discount_cents;
    promo_applied := true;
  else
    price_cents := v_campaign.standard_price_cents;
    promo_applied := false;
  end if;

  return next;
end;
$$;

create or replace function public.reserve_preorder_slot(
  p_campaign_id text,
  p_user_id uuid,
  p_amount_cents integer,
  p_promo_applied boolean,
  p_payment_intent_id text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign public.promo_campaigns%rowtype;
  v_redeemed_count integer;
  v_expected_price integer;
  v_preorder_id uuid;
begin
  select * into v_campaign
  from public.promo_campaigns
  where id = p_campaign_id and active = true
  for update;

  if not found then
    raise exception 'Campaign not found';
  end if;

  if exists (
    select 1 from public.preorders
    where campaign_id = p_campaign_id
      and user_id = p_user_id
      and status in ('pending', 'completed')
  ) then
    raise exception 'Preorder already exists for this user';
  end if;

  select count(*)::integer into v_redeemed_count
  from public.preorders
  where campaign_id = p_campaign_id and status = 'completed';

  if v_redeemed_count < v_campaign.max_slots then
    v_expected_price := v_campaign.standard_price_cents - v_campaign.discount_cents;
  else
    v_expected_price := v_campaign.standard_price_cents;
  end if;

  if p_amount_cents <> v_expected_price then
    raise exception 'Price mismatch';
  end if;

  insert into public.preorders (
    campaign_id,
    user_id,
    status,
    amount_cents,
    promo_applied,
    stripe_payment_intent_id
  )
  values (
    p_campaign_id,
    p_user_id,
    'pending',
    p_amount_cents,
    p_promo_applied,
    p_payment_intent_id
  )
  returning id into v_preorder_id;

  return v_preorder_id;
end;
$$;

create or replace function public.complete_preorder(
  p_payment_intent_id text,
  p_user_id uuid
)
returns table (
  preorder_id uuid,
  credit_cents integer,
  promo_applied boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_preorder public.preorders%rowtype;
begin
  select * into v_preorder
  from public.preorders
  where stripe_payment_intent_id = p_payment_intent_id
    and user_id = p_user_id
  for update;

  if not found then
    raise exception 'Preorder not found';
  end if;

  if v_preorder.status = 'completed' then
    preorder_id := v_preorder.id;
    credit_cents := v_preorder.amount_cents;
    promo_applied := v_preorder.promo_applied;
    return next;
    return;
  end if;

  if v_preorder.status <> 'pending' then
    raise exception 'Preorder is not pending';
  end if;

  update public.preorders
  set status = 'completed', completed_at = now()
  where id = v_preorder.id;

  update public.profiles
  set account_credit_cents = account_credit_cents + v_preorder.amount_cents
  where id = p_user_id;

  preorder_id := v_preorder.id;
  credit_cents := v_preorder.amount_cents;
  promo_applied := v_preorder.promo_applied;
  return next;
end;
$$;

create or replace function public.consume_preorder_credit(
  p_user_id uuid,
  p_amount_cents integer
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.profiles%rowtype;
  v_applied integer;
begin
  select * into v_profile
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'Profile not found';
  end if;

  if v_profile.preorder_credit_consumed or v_profile.account_credit_cents <= 0 then
    return 0;
  end if;

  v_applied := least(v_profile.account_credit_cents, p_amount_cents);

  update public.profiles
  set
    account_credit_cents = account_credit_cents - v_applied,
    preorder_credit_consumed = true
  where id = p_user_id;

  return v_applied;
end;
$$;
