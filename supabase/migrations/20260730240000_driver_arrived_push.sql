-- Enqueue customer pushes when driver arrives / en route, and invoke Edge for those events.
-- Also treat awaitingPostTripInspection like return-inspection ready for push enqueue.

create or replace function public.enqueue_status_push(
  p_booking_id uuid,
  p_event text,
  p_title text,
  p_body text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  event_id uuid;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found then
    raise exception 'booking not found';
  end if;

  if auth.uid() is not null
     and auth.uid() is distinct from b.driver_id
     and auth.uid() is distinct from b.customer_id then
    raise exception 'not allowed';
  end if;

  if b.customer_id is null then
    raise exception 'booking has no customer_id';
  end if;

  select id into event_id
  from public.push_events
  where booking_id = b.id
    and event = p_event
    and created_at > now() - interval '3 minutes'
  order by created_at desc
  limit 1;

  if event_id is not null then
    return event_id;
  end if;

  insert into public.push_events (booking_id, recipient_user_id, event, title, body)
  values (b.id, b.customer_id, p_event, p_title, p_body)
  returning id into event_id;

  return event_id;
end;
$$;

revoke all on function public.enqueue_status_push(uuid, text, text, text) from public;
grant execute on function public.enqueue_status_push(uuid, text, text, text) to authenticated;
grant execute on function public.enqueue_status_push(uuid, text, text, text) to service_role;

create or replace function public.bookings_enqueue_inspection_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  vehicle text;
begin
  vehicle := coalesce(
    nullif(NEW.vehicle_name, ''),
    nullif(trim(both from coalesce(NEW.vehicle_make, '') || ' ' || coalesce(NEW.vehicle_model, '')), ''),
    'your EV'
  );

  if TG_OP = 'UPDATE'
     and OLD.status is distinct from NEW.status then
    if NEW.status::text = 'driverEnRoute' then
      perform public.enqueue_status_push(
        NEW.id,
        'driver_en_route',
        'Pickup update',
        'Your Chercharge concierge is on the way to pick up ' || vehicle || '.'
      );
    elsif NEW.status::text = 'driverArrived' then
      perform public.enqueue_status_push(
        NEW.id,
        'driver_arrived',
        'Concierge arrived',
        'Your concierge is with ' || vehicle || '. You’ll be notified when the inspection is ready to review.'
      );
    elsif NEW.status::text = 'awaitingCustomerApproval' then
      perform public.enqueue_inspection_push(NEW.id, 'preTrip');
    elsif NEW.status::text in ('awaitingReturnApproval', 'awaitingPostTripInspection') then
      perform public.enqueue_inspection_push(NEW.id, 'postTrip');
    end if;
  end if;

  if TG_OP = 'UPDATE'
     and OLD.post_trip_inspection is null
     and NEW.post_trip_inspection is not null
     and NEW.customer_approved_return_at is null then
    perform public.enqueue_inspection_push(NEW.id, 'postTrip');
  end if;

  return NEW;
end;
$$;

create or replace function public.push_events_invoke_notify_booking_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, net, vault
as $$
declare
  phase text;
  payload jsonb;
  req_id bigint;
  fn_url text;
  api_key text;
  project_url text;
begin
  if NEW.event = 'inspection_ready_preTrip' then
    phase := 'preTrip';
  elsif NEW.event = 'inspection_ready_postTrip' then
    phase := 'postTrip';
  elsif NEW.event in (
    'driver_pickup_approved',
    'driver_return_approved',
    'driver_arrived',
    'driver_en_route'
  ) then
    phase := null;
  else
    return NEW;
  end if;

  select decrypted_secret
    into project_url
  from vault.decrypted_secrets
  where name = any (array[
    'project_url',
    'supabase_url',
    'SUPABASE_URL'
  ])
  limit 1;

  if project_url is null or length(trim(project_url)) = 0 then
    project_url := nullif(current_setting('app.settings.supabase_url', true), '');
  end if;

  if project_url is null or length(trim(project_url)) = 0 then
    project_url := 'https://kjzbiiechaiodwdxstfz.supabase.co';
  end if;

  fn_url := rtrim(project_url, '/') || '/functions/v1/notify-booking-push';

  select decrypted_secret
    into api_key
  from vault.decrypted_secrets
  where name = any (array[
    'service_role_key',
    'SUPABASE_SERVICE_ROLE_KEY',
    'service_role',
    'anon_key',
    'SUPABASE_ANON_KEY',
    'publishable_key',
    'SUPABASE_PUBLISHABLE_KEY'
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
    api_key := nullif(current_setting('app.settings.anon_key', true), '');
  end if;

  if api_key is null or length(trim(api_key)) = 0 then
    raise warning
      'push_events_invoke_notify_booking_push: no Vault API key — HTTP POST skipped.';
    return NEW;
  end if;

  if phase is not null then
    payload := jsonb_build_object(
      'booking_id', NEW.booking_id,
      'push_event_id', NEW.id,
      'from_push_event', true,
      'event', NEW.event,
      'phase', phase
    );
  else
    payload := jsonb_build_object(
      'booking_id', NEW.booking_id,
      'push_event_id', NEW.id,
      'from_push_event', true,
      'event', NEW.event
    );
  end if;

  select net.http_post(
    url := fn_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || api_key,
      'apikey', api_key
    ),
    body := payload,
    timeout_milliseconds := 10000
  )
  into req_id;

  begin
    update public.push_events
      set invoke_request_id = req_id
    where id = NEW.id;
  exception
    when others then
      null;
  end;

  return NEW;
exception
  when others then
    raise warning 'push_events_invoke_notify_booking_push failed: %', SQLERRM;
    return NEW;
end;
$$;
