-- Two-tier early-bird pre-order pricing:
-- First 5  → $10 / charge (lifetime · 1 car)
-- Next 45  → $30 / charge (1 year · 1 car)
-- After 50 → $49.99 standard

alter table public.promo_campaigns
  add column if not exists lifetime_slots integer not null default 5 check (lifetime_slots >= 0),
  add column if not exists year_slots integer not null default 45 check (year_slots >= 0),
  add column if not exists lifetime_price_cents integer not null default 1000 check (lifetime_price_cents >= 0),
  add column if not exists year_price_cents integer not null default 3000 check (year_price_cents >= 0);

update public.promo_campaigns
set
  name = 'Early-bird 50 (lifetime + year)',
  max_slots = 50,
  lifetime_slots = 5,
  year_slots = 45,
  lifetime_price_cents = 1000,
  year_price_cents = 3000,
  discount_cents = 1999,
  standard_price_cents = 4999
where id = 'early_bird_50';

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
  where campaign_id = p_campaign_id and user_id = p_user_id;

  select count(*)::integer into v_redeemed_count
  from public.preorders
  where campaign_id = p_campaign_id and status = 'completed';

  slots_remaining := greatest(0, v_campaign.max_slots - v_redeemed_count);
  max_slots := v_campaign.max_slots;
  standard_price_cents := v_campaign.standard_price_cents;
  already_preordered := v_existing.id is not null;
  existing_status := v_existing.status;
  account_credit_cents := coalesce(v_profile.account_credit_cents, 0);
  preorder_credit_consumed := coalesce(v_profile.preorder_credit_consumed, false);

  if v_existing.status = 'completed' then
    price_cents := v_existing.amount_cents;
    promo_applied := v_existing.promo_applied;
    discount_cents := greatest(0, v_campaign.standard_price_cents - v_existing.amount_cents);
    return next;
    return;
  end if;

  if v_redeemed_count < v_campaign.lifetime_slots then
    v_tier_price := v_campaign.lifetime_price_cents;
    promo_applied := true;
  elsif v_redeemed_count < v_campaign.max_slots then
    v_tier_price := v_campaign.year_price_cents;
    promo_applied := true;
  else
    v_tier_price := v_campaign.standard_price_cents;
    promo_applied := false;
  end if;

  price_cents := v_tier_price;
  discount_cents := greatest(0, v_campaign.standard_price_cents - v_tier_price);

  return next;
end;
$$;
