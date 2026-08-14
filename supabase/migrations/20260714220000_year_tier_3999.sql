-- Year early-bird tier: $30 → $39.99 per charge

update public.promo_campaigns
set
  year_price_cents = 3999,
  name = 'Early-bird 50 (lifetime + year)'
where id = 'early_bird_50';
