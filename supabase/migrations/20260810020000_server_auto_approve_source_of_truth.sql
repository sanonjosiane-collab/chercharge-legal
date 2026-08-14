-- Backend is source of truth for inspection approval.
-- Deadlines live on bookings; auto-approve runs server-side even if apps are closed.

alter table public.bookings
  add column if not exists customer_approval_deadline timestamptz,
  add column if not exists return_approval_deadline timestamptz,
  add column if not exists pickup_approval_method text,
  add column if not exists return_approval_method text;

comment on column public.bookings.customer_approval_deadline is
  'When awaitingCustomerApproval, auto-approve pickup at this timestamptz (15s window).';
comment on column public.bookings.return_approval_deadline is
  'When return inspection is ready, auto-approve return at this timestamptz (15s window).';
comment on column public.bookings.pickup_approval_method is
  'manual | auto — how pickup was approved.';
comment on column public.bookings.return_approval_method is
  'manual | auto — how return was approved.';

-- Stamp 15s deadlines when inspection becomes ready for review.
create or replace function public.bookings_set_approval_deadlines()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE' and OLD.status is distinct from NEW.status then
    if NEW.status::text = 'awaitingCustomerApproval' then
      NEW.customer_approval_deadline := coalesce(
        NEW.customer_approval_deadline,
        now() + interval '15 seconds'
      );
    end if;

    if NEW.status::text in ('awaitingReturnApproval', 'awaitingPostTripInspection')
       and NEW.post_trip_inspection is not null
       and NEW.customer_approved_return_at is null then
      NEW.return_approval_deadline := coalesce(
        NEW.return_approval_deadline,
        now() + interval '15 seconds'
      );
    end if;
  end if;

  -- Post-trip JSON arrived while already in awaitingPostTripInspection.
  if TG_OP = 'UPDATE'
     and OLD.post_trip_inspection is null
     and NEW.post_trip_inspection is not null
     and NEW.customer_approved_return_at is null
     and NEW.status::text in ('awaitingReturnApproval', 'awaitingPostTripInspection') then
    NEW.return_approval_deadline := coalesce(
      NEW.return_approval_deadline,
      now() + interval '15 seconds'
    );
  end if;

  return NEW;
end;
$$;

drop trigger if exists bookings_set_approval_deadlines on public.bookings;
create trigger bookings_set_approval_deadlines
  before update on public.bookings
  for each row
  execute function public.bookings_set_approval_deadlines();

-- Auto-approve one booking when its stored deadline has passed (idempotent).
create or replace function public.auto_approve_due_booking(p_booking_id uuid)
returns table (
  approved boolean,
  action text,
  new_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  now_ts timestamptz := now();
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found then
    return query select false, 'not_found'::text, null::text;
    return;
  end if;

  -- Pre-trip / pickup
  if b.status::text = 'awaitingCustomerApproval'
     and b.customer_approved_pickup_at is null
     and b.pre_trip_inspection is not null
     and (
       (b.customer_approval_deadline is not null and b.customer_approval_deadline <= now_ts)
       or (b.customer_approval_deadline is null and b.updated_at <= now_ts - interval '15 seconds')
     )
  then
    update public.bookings
      set status = 'pickedUp',
          customer_approved_pickup_at = now_ts,
          customer_approval_deadline = null,
          pickup_approval_method = 'auto',
          updated_at = now_ts
    where id = b.id;
    return query select true, 'approve_pickup'::text, 'pickedUp'::text;
    return;
  end if;

  -- Post-trip / return (DB may stay on awaitingPostTripInspection)
  if b.status::text in ('awaitingReturnApproval', 'awaitingPostTripInspection')
     and b.customer_approved_return_at is null
     and b.post_trip_inspection is not null
     and (
       (b.return_approval_deadline is not null and b.return_approval_deadline <= now_ts)
       or (b.return_approval_deadline is null and b.updated_at <= now_ts - interval '15 seconds')
     )
  then
    update public.bookings
      set status = 'delivered',
          customer_approved_return_at = now_ts,
          return_approval_deadline = null,
          return_approval_method = 'auto',
          updated_at = now_ts
    where id = b.id;
    return query select true, 'approve_return'::text, 'delivered'::text;
    return;
  end if;

  return query select false, 'not_due'::text, b.status::text;
end;
$$;

revoke all on function public.auto_approve_due_booking(uuid) from public;
grant execute on function public.auto_approve_due_booking(uuid) to service_role;
grant execute on function public.auto_approve_due_booking(uuid) to authenticated;

-- Sweep every booking whose stored deadline has expired (periodic / cron / edge).
create or replace function public.auto_approve_expired_bookings()
returns table (
  booking_id uuid,
  approved boolean,
  action text,
  new_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  row_result record;
begin
  for r in
    select b.id
    from public.bookings b
    where (
        b.status::text = 'awaitingCustomerApproval'
        and b.customer_approved_pickup_at is null
        and b.pre_trip_inspection is not null
        and (
          (b.customer_approval_deadline is not null and b.customer_approval_deadline <= now())
          or (b.customer_approval_deadline is null and b.updated_at <= now() - interval '15 seconds')
        )
      )
      or (
        b.status::text in ('awaitingReturnApproval', 'awaitingPostTripInspection')
        and b.customer_approved_return_at is null
        and b.post_trip_inspection is not null
        and (
          (b.return_approval_deadline is not null and b.return_approval_deadline <= now())
          or (b.return_approval_deadline is null and b.updated_at <= now() - interval '15 seconds')
        )
      )
    order by b.updated_at
    limit 50
  loop
    for row_result in
      select * from public.auto_approve_due_booking(r.id)
    loop
      booking_id := r.id;
      approved := row_result.approved;
      action := row_result.action;
      new_status := row_result.new_status;
      return next;
    end loop;
  end loop;
end;
$$;

revoke all on function public.auto_approve_expired_bookings() from public;
grant execute on function public.auto_approve_expired_bookings() to service_role;

-- When a deadline is (re)stamped, wake the schedule-auto-approve Edge Function
-- so approval happens ~15s later even if customer + driver apps are closed.
create or replace function public.bookings_invoke_schedule_auto_approve()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, net, vault
as $$
declare
  should_schedule boolean := false;
  phase text;
  deadline timestamptz;
  fn_url text;
  api_key text;
  project_url text;
  req_id bigint;
begin
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  if NEW.customer_approval_deadline is not null
     and NEW.customer_approval_deadline is distinct from OLD.customer_approval_deadline
     and NEW.status::text = 'awaitingCustomerApproval'
     and NEW.customer_approved_pickup_at is null then
    should_schedule := true;
    phase := 'pickup';
    deadline := NEW.customer_approval_deadline;
  elsif NEW.return_approval_deadline is not null
     and NEW.return_approval_deadline is distinct from OLD.return_approval_deadline
     and NEW.customer_approved_return_at is null
     and NEW.status::text in ('awaitingReturnApproval', 'awaitingPostTripInspection')
     and NEW.post_trip_inspection is not null then
    should_schedule := true;
    phase := 'return';
    deadline := NEW.return_approval_deadline;
  end if;

  if not should_schedule then
    return NEW;
  end if;

  select decrypted_secret into project_url
  from vault.decrypted_secrets
  where name = any (array['project_url', 'supabase_url', 'SUPABASE_URL'])
  limit 1;
  if project_url is null or length(trim(project_url)) = 0 then
    project_url := nullif(current_setting('app.settings.supabase_url', true), '');
  end if;
  if project_url is null or length(trim(project_url)) = 0 then
    project_url := 'https://kjzbiiechaiodwdxstfz.supabase.co';
  end if;

  fn_url := rtrim(project_url, '/') || '/functions/v1/schedule-auto-approve';

  select decrypted_secret into api_key
  from vault.decrypted_secrets
  where name = any (array[
    'service_role_key', 'SUPABASE_SERVICE_ROLE_KEY', 'service_role',
    'anon_key', 'SUPABASE_ANON_KEY', 'publishable_key', 'SUPABASE_PUBLISHABLE_KEY'
  ])
  order by case name
    when 'service_role_key' then 0
    when 'SUPABASE_SERVICE_ROLE_KEY' then 1
    when 'service_role' then 2
    else 10
  end
  limit 1;
  if api_key is null or length(trim(api_key)) = 0 then
    api_key := nullif(current_setting('app.settings.service_role_key', true), '');
  end if;
  if api_key is null or length(trim(api_key)) = 0 then
    return NEW;
  end if;

  begin
    select net.http_post(
      url := fn_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || api_key,
        'apikey', api_key
      ),
      body := jsonb_build_object(
        'booking_id', NEW.id,
        'phase', phase,
        'deadline', deadline
      )
    ) into req_id;
  exception when others then
    raise warning 'bookings_invoke_schedule_auto_approve failed: %', SQLERRM;
  end;

  return NEW;
end;
$$;

drop trigger if exists bookings_invoke_schedule_auto_approve on public.bookings;
create trigger bookings_invoke_schedule_auto_approve
  after update on public.bookings
  for each row
  execute function public.bookings_invoke_schedule_auto_approve();

-- Backup sweep every minute (pg_cron). Sub-minute precision comes from schedule-auto-approve.
do $$
begin
  if exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) or exists (
    select 1 from pg_available_extensions where name = 'pg_cron'
  ) then
    create extension if not exists pg_cron with schema extensions;
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'chercharge-auto-approve-expired';
    perform cron.schedule(
      'chercharge-auto-approve-expired',
      '* * * * *',
      $cron$ select public.auto_approve_expired_bookings(); $cron$
    );
  end if;
exception when others then
  raise notice 'pg_cron schedule skipped: %', SQLERRM;
end;
$$;
