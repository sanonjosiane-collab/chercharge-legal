-- 15s customer approval deadlines + helpers for server/driver auto-approve.

alter table public.bookings
  add column if not exists customer_approval_deadline timestamptz,
  add column if not exists return_approval_deadline timestamptz;

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

-- Auto-approve overdue pickup / return inspections (idempotent).
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
