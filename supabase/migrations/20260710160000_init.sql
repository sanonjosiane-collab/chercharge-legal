-- Chercharge customer MVP schema
-- profiles, vehicles, bookings + RLS + realtime

create extension if not exists "pgcrypto";

create type public.booking_status as enum (
  'requested',
  'driverEnRoute',
  'driverArrived',
  'awaitingCustomerApproval',
  'pickedUp',
  'charging',
  'returning',
  'awaitingPostTripInspection',
  'delivered'
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  role text not null default 'customer' check (role in ('customer', 'driver')),
  created_at timestamptz not null default now()
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  make text not null,
  model text not null,
  license_plate text not null,
  current_charge_percent integer not null check (current_charge_percent between 0 and 100),
  created_at timestamptz not null default now()
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id),
  status public.booking_status not null default 'requested',
  pickup_name text not null,
  pickup_address text not null,
  pickup_lat double precision not null,
  pickup_lng double precision not null,
  station_name text not null,
  station_address text not null,
  station_lat double precision not null,
  station_lng double precision not null,
  target_charge_percent integer not null check (target_charge_percent between 0 and 100),
  starting_charge_percent integer not null check (starting_charge_percent between 0 and 100),
  estimated_price numeric(10, 2) not null,
  estimated_minutes integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index bookings_customer_id_idx on public.bookings (customer_id);
create index bookings_status_idx on public.bookings (status);
create index vehicles_owner_id_idx on public.vehicles (owner_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger bookings_set_updated_at
before update on public.bookings
for each row
execute function public.set_updated_at();

-- New users get a profile + two sample vehicles
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    'customer'
  );

  insert into public.vehicles (owner_id, name, make, model, license_plate, current_charge_percent)
  values
    (new.id, 'Daily Driver', 'Tesla', 'Model 3', '7XYZ123', 28),
    (new.id, 'Family SUV', 'Tesla', 'Model Y', '8ABC456', 35);

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.vehicles enable row level security;
alter table public.bookings enable row level security;

create policy "Users can view own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Users can view own vehicles"
  on public.vehicles for select
  using (auth.uid() = owner_id);

create policy "Users can insert own vehicles"
  on public.vehicles for insert
  with check (auth.uid() = owner_id);

create policy "Users can update own vehicles"
  on public.vehicles for update
  using (auth.uid() = owner_id);

create policy "Users can view own bookings"
  on public.bookings for select
  using (auth.uid() = customer_id);

create policy "Users can create own bookings"
  on public.bookings for insert
  with check (auth.uid() = customer_id);

create policy "Users can update own bookings"
  on public.bookings for update
  using (auth.uid() = customer_id);

-- Realtime for live tracking
alter publication supabase_realtime add table public.bookings;
