-- Flag bookings where the customer smokes/vapes in the vehicle (driver awareness).
-- Paste in Supabase SQL Editor if migrations are not applied via CLI.

alter table public.bookings
  add column if not exists smoking_in_vehicle boolean not null default false;

comment on column public.bookings.smoking_in_vehicle is
  'True when anyone smokes or vapes inside the customer vehicle — shown on driver open requests.';
