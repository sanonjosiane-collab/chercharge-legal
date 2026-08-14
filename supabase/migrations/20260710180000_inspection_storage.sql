-- Inspection flow: storage bucket + booking status gates + inspection JSON on bookings

-- New statuses for customer approval and post-trip inspection gates
alter type public.booking_status add value if not exists 'driverArrived';
alter type public.booking_status add value if not exists 'awaitingCustomerApproval';
alter type public.booking_status add value if not exists 'awaitingPostTripInspection';

alter table public.bookings
  add column if not exists pre_trip_inspection jsonb,
  add column if not exists post_trip_inspection jsonb,
  add column if not exists customer_approved_pickup_at timestamptz;

-- Media bucket
insert into storage.buckets (id, name, public)
values ('inspections', 'inspections', true)
on conflict (id) do nothing;

-- MVP: allow anon uploads/reads for demo. Tighten with auth policies for production.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'Public read inspections'
  ) then
    create policy "Public read inspections"
    on storage.objects for select
    using (bucket_id = 'inspections');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'Anon upload inspections'
  ) then
    create policy "Anon upload inspections"
    on storage.objects for insert
    with check (bucket_id = 'inspections');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and policyname = 'Anon update inspections'
  ) then
    create policy "Anon update inspections"
    on storage.objects for update
    using (bucket_id = 'inspections');
  end if;
end $$;
