-- Harden Founding Access / pre-order foundation:
-- 1) Align reserve pricing with two-tier ($10 / $30 / $49.99)
-- 2) Count pending + completed toward slot inventory (reduce races)
-- 3) Persist agreement acceptance + terms version + tier
-- 4) Cancel stale pending reservations so abandoned checkouts don't lock spots

alter table public.preorders
  add column if not exists agreement_accepted_at timestamptz,
  add column if not exists terms_version text,
  add column if not exists tier text
    check (tier is null or tier in ('lifetime', 'year', 'standard'));

-- Current terms bundle shown in the iOS Pre-order notice.
-- Bump this string in app + Edge Functions when legal copy changes.
comment on column public.preorders.terms_version is
  'Legal bundle version accepted at checkout, e.g. founding-access-v1';

create or replace function public.cancel_stale_preorder_reservations(
  p_campaign_id text,
  p_max_age_minutes integer default 30
)
returns table (stripe_payment_intent_id text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with stale as (
    update public.preorders
    set status = 'cancelled'
    where campaign_id = p_campaign_id
      and status = 'pending'
      and created_at < now() - make_interval(mins => greatest(p_max_age_minutes, 1))
    returning preorders.stripe_payment_intent_id
  )
  select stale.stripe_payment_intent_id
  from stale
  where stale.stripe_payment_intent_id is not null;
end;
$$;

-- Return type gains `tier`; Postgres requires drop before recreate.
drop function if exists public.get_preorder_quote(text, uuid);

create function public.get_preorder_quote(p_campaign_id text, p_user_id uuid)
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
  preorder_credit_consumed boolean,
  tier text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign public.promo_campaigns%rowtype;
  v_claimed_count integer;
  v_existing public.preorders%rowtype;
  v_profile public.profiles%rowtype;
  v_tier text;
  v_tier_price integer;
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
  where campaign_id = p_campaign_id and user_id = p_user_id
  order by created_at desc
  limit 1;

  -- Inventory: pending holds + completed purchases (failed/cancelled free the slot).
  select count(*)::integer into v_claimed_count
  from public.preorders
  where campaign_id = p_campaign_id
    and status in ('pending', 'completed');

  -- If this user already holds a pending row, don't let that hold inflate "others" inventory
  -- for their own quote display beyond the hold itself (claimed already includes them).
  slots_remaining := greatest(0, v_campaign.max_slots - v_claimed_count);
  max_slots := v_campaign.max_slots;
  standard_price_cents := v_campaign.standard_price_cents;
  already_preordered := v_existing.id is not null
    and v_existing.status in ('pending', 'completed');
  existing_status := v_existing.status;
  account_credit_cents := coalesce(v_profile.account_credit_cents, 0);
  preorder_credit_consumed := coalesce(v_profile.preorder_credit_consumed, false);

  if v_existing.status = 'completed' then
    price_cents := v_existing.amount_cents;
    promo_applied := v_existing.promo_applied;
    discount_cents := greatest(0, v_campaign.standard_price_cents - v_existing.amount_cents);
    tier := coalesce(
      v_existing.tier,
      case
        when v_existing.amount_cents <= v_campaign.lifetime_price_cents then 'lifetime'
        when v_existing.promo_applied
          and v_existing.amount_cents <= v_campaign.year_price_cents then 'year'
        else 'standard'
      end
    );
    return next;
    return;
  end if;

  -- Price the next open slot from current claimed inventory.
  if v_claimed_count < v_campaign.lifetime_slots then
    v_tier := 'lifetime';
    v_tier_price := v_campaign.lifetime_price_cents;
    promo_applied := true;
  elsif v_claimed_count < v_campaign.max_slots then
    v_tier := 'year';
    v_tier_price := v_campaign.year_price_cents;
    promo_applied := true;
  else
    v_tier := 'standard';
    v_tier_price := v_campaign.standard_price_cents;
    promo_applied := false;
  end if;

  -- If user already has a pending reservation, return that locked price/tier.
  if v_existing.status = 'pending' then
    price_cents := v_existing.amount_cents;
    promo_applied := v_existing.promo_applied;
    discount_cents := greatest(0, v_campaign.standard_price_cents - v_existing.amount_cents);
    tier := coalesce(v_existing.tier, v_tier);
    return next;
    return;
  end if;

  price_cents := v_tier_price;
  discount_cents := greatest(0, v_campaign.standard_price_cents - v_tier_price);
  tier := v_tier;
  return next;
end;
$$;

-- Replace 5-arg reserve with agreement + tier signature.
drop function if exists public.reserve_preorder_slot(text, uuid, integer, boolean, text);

create function public.reserve_preorder_slot(
  p_campaign_id text,
  p_user_id uuid,
  p_amount_cents integer,
  p_promo_applied boolean,
  p_payment_intent_id text,
  p_tier text default null,
  p_agreement_accepted_at timestamptz default null,
  p_terms_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign public.promo_campaigns%rowtype;
  v_claimed_count integer;
  v_expected_price integer;
  v_expected_tier text;
  v_expected_promo boolean;
  v_preorder_id uuid;
begin
  if p_agreement_accepted_at is null then
    raise exception 'Agreement acceptance is required';
  end if;

  if p_terms_version is null or length(trim(p_terms_version)) = 0 then
    raise exception 'Terms version is required';
  end if;

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

  select count(*)::integer into v_claimed_count
  from public.preorders
  where campaign_id = p_campaign_id
    and status in ('pending', 'completed');

  if v_claimed_count < v_campaign.lifetime_slots then
    v_expected_tier := 'lifetime';
    v_expected_price := v_campaign.lifetime_price_cents;
    v_expected_promo := true;
  elsif v_claimed_count < v_campaign.max_slots then
    v_expected_tier := 'year';
    v_expected_price := v_campaign.year_price_cents;
    v_expected_promo := true;
  else
    v_expected_tier := 'standard';
    v_expected_price := v_campaign.standard_price_cents;
    v_expected_promo := false;
  end if;

  if p_amount_cents <> v_expected_price then
    raise exception 'Price mismatch';
  end if;

  if p_promo_applied is distinct from v_expected_promo then
    raise exception 'Promo mismatch';
  end if;

  if p_tier is not null and p_tier <> v_expected_tier then
    raise exception 'Tier mismatch';
  end if;

  if v_claimed_count >= v_campaign.max_slots and v_expected_tier <> 'standard' then
    raise exception 'No founding spots remaining';
  end if;

  insert into public.preorders (
    campaign_id,
    user_id,
    status,
    amount_cents,
    promo_applied,
    stripe_payment_intent_id,
    tier,
    agreement_accepted_at,
    terms_version
  )
  values (
    p_campaign_id,
    p_user_id,
    'pending',
    p_amount_cents,
    p_promo_applied,
    p_payment_intent_id,
    v_expected_tier,
    p_agreement_accepted_at,
    trim(p_terms_version)
  )
  returning id into v_preorder_id;

  return v_preorder_id;
end;
$$;
