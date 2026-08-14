-- Customer vehicle documents for admin review (registration photo + policy number).
-- Mirrors Chercharge Driver migration so both repos stay aligned on the shared project.

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('customer', 'driver', 'admin'));

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create table if not exists public.customer_vehicle_documents (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles (id) on delete cascade,
  local_vehicle_id uuid not null,
  customer_name text,
  customer_email text,
  vehicle_display_name text not null,
  license_plate text,
  make text,
  model text,
  year integer,
  insurance_policy text not null default '',
  insurance_company_name text,
  registration_expiration date,
  policy_expiration date,
  registration_storage_path text,
  registration_file_name text,
  registration_content_type text,
  insurance_card_storage_path text,
  status text not null default 'pendingReview' check (
    status in ('pendingReview', 'approved', 'rejected')
  ),
  priority_score integer not null default 200,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles (id),
  reviewer_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (customer_id, local_vehicle_id)
);

create index if not exists customer_vehicle_documents_status_idx
  on public.customer_vehicle_documents (status, priority_score desc, submitted_at asc);

create index if not exists customer_vehicle_documents_customer_id_idx
  on public.customer_vehicle_documents (customer_id);

drop trigger if exists customer_vehicle_documents_set_updated_at on public.customer_vehicle_documents;
create trigger customer_vehicle_documents_set_updated_at
before update on public.customer_vehicle_documents
for each row
execute function public.set_updated_at();

alter table public.customer_vehicle_documents enable row level security;

drop policy if exists "Customers view own vehicle documents" on public.customer_vehicle_documents;
create policy "Customers view own vehicle documents"
  on public.customer_vehicle_documents for select
  using (auth.uid() = customer_id or public.is_admin());

drop policy if exists "Customers insert own vehicle documents" on public.customer_vehicle_documents;
create policy "Customers insert own vehicle documents"
  on public.customer_vehicle_documents for insert
  with check (auth.uid() = customer_id);

drop policy if exists "Customers update own pending vehicle documents" on public.customer_vehicle_documents;
create policy "Customers update own pending vehicle documents"
  on public.customer_vehicle_documents for update
  using (
    public.is_admin()
    or auth.uid() = customer_id
  )
  with check (
    public.is_admin()
    or (
      auth.uid() = customer_id
      and status = 'pendingReview'
    )
  );

insert into storage.buckets (id, name, public)
values ('customer-vehicle-docs', 'customer-vehicle-docs', false)
on conflict (id) do update set public = false;

drop policy if exists "Customers upload own vehicle docs" on storage.objects;
create policy "Customers upload own vehicle docs"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'customer-vehicle-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Customers update own vehicle docs" on storage.objects;
create policy "Customers update own vehicle docs"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'customer-vehicle-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Customers and admins read vehicle docs" on storage.objects;
create policy "Customers and admins read vehicle docs"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'customer-vehicle-docs'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
    )
  );

drop policy if exists "Admins delete customer vehicle docs" on storage.objects;
create policy "Admins delete customer vehicle docs"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'customer-vehicle-docs' and public.is_admin());

do $$
begin
  begin
    alter publication supabase_realtime add table public.customer_vehicle_documents;
  exception
    when duplicate_object then null;
  end;
end $$;
