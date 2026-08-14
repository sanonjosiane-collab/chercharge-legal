-- Fix: preorders has UNIQUE (campaign_id, user_id) for all statuses.
-- Failed/cancelled rows blocked new inserts with duplicate key errors.
-- reserve_preorder_slot now reuses the existing row when not completed.

create or replace function public.reserve_preorder_slot(
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
  v_existing public.preorders%rowtype;
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

  select * into v_existing
  from public.preorders
  where campaign_id = p_campaign_id
    and user_id = p_user_id
  for update;

  if found and v_existing.status = 'completed' then
    raise exception 'Preorder already exists for this user';
  end if;

  -- Count inventory. If this user already holds a pending row, exclude it so
  -- recreating their own PaymentIntent does not look like the campaign is fuller.
  select count(*)::integer into v_claimed_count
  from public.preorders
  where campaign_id = p_campaign_id
    and status in ('pending', 'completed')
    and not (user_id = p_user_id and status = 'pending');

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

  if found then
    update public.preorders
    set
      status = 'pending',
      amount_cents = p_amount_cents,
      promo_applied = p_promo_applied,
      stripe_payment_intent_id = p_payment_intent_id,
      tier = v_expected_tier,
      agreement_accepted_at = p_agreement_accepted_at,
      terms_version = trim(p_terms_version)
    where id = v_existing.id
    returning id into v_preorder_id;
  else
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
  end if;

  return v_preorder_id;
end;
$$;
