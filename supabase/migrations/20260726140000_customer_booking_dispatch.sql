-- Ensure open-job denormalized columns exist for customer → driver dispatch.
-- Mirrors Chercharge Driver migration 20260724120000_driver_open_jobs.sql (shared project).

alter table public.bookings
  add column if not exists driver_id uuid references public.profiles (id),
  add column if not exists customer_name text,
  add column if not exists vehicle_name text,
  add column if not exists vehicle_make text,
  add column if not exists vehicle_model text,
  add column if not exists vehicle_year integer,
  add column if not exists vehicle_plate text;

create index if not exists bookings_driver_id_idx on public.bookings (driver_id);
create index if not exists bookings_open_requested_idx
  on public.bookings (created_at desc)
  where status = 'requested' and driver_id is null;
