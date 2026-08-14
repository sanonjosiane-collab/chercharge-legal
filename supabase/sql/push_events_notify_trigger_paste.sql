-- =============================================================================
-- PASTE INTO SUPABASE SQL EDITOR (updated)
-- Fixes push_events → notify-booking-push invoke + pg_net tracing
-- =============================================================================
--
-- 1) REQUIRED: store an API key Vault uses for Authorization/apikey headers.
--    Prefer the service_role JWT from Dashboard → Settings → API.
--    Publishable key also works (Edge validates apikey).
--
--   select vault.create_secret(
--     'YOUR_SERVICE_ROLE_OR_PUBLISHABLE_KEY',
--     'service_role_key',
--     'API key for push_events pg_net → notify-booking-push'
--   );
--
-- 2) After a test insert, inspect:
--   select * from public.push_events_invoke_status limit 10;
--   select * from net._http_response order by created desc limit 10;
--
-- 3) FCM must use the SAME Firebase project as the iOS app:
--    GoogleService-Info.plist → PROJECT_ID=chercharge-5ff77 / GCM_SENDER_ID=600283319476
--    Set Edge secret FIREBASE_SERVICE_ACCOUNT_JSON from that project's service account.
-- =============================================================================

create extension if not exists pg_net with schema extensions;

alter table public.push_events
  add column if not exists delivered_at timestamptz,
  add column if not exists invoke_request_id bigint,
  add column if not exists fcm_sent_at timestamptz;

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
  elsif NEW.event in ('driver_pickup_approved', 'driver_return_approved') then
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
      'push_events_invoke_notify_booking_push: no Vault API key — HTTP POST skipped. Run vault.create_secret for service_role_key.';
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
      raise warning 'push_events_invoke_notify_booking_push: could not store request id %', req_id;
  end;

  return NEW;
exception
  when others then
    raise warning 'push_events_invoke_notify_booking_push failed: %', SQLERRM;
    return NEW;
end;
$$;

drop trigger if exists push_events_notify_booking_push on public.push_events;
create trigger push_events_notify_booking_push
  after insert on public.push_events
  for each row
  execute function public.push_events_invoke_notify_booking_push();

create or replace view public.push_events_invoke_status as
select
  pe.id as push_event_id,
  pe.booking_id,
  pe.event,
  pe.created_at as push_created_at,
  pe.invoke_request_id,
  pe.fcm_sent_at,
  pe.delivered_at,
  r.status_code,
  r.timed_out,
  r.error_msg,
  left(r.content, 1000) as response_content,
  r.created as http_responded_at
from public.push_events pe
left join net._http_response r on r.id = pe.invoke_request_id
order by pe.created_at desc;

grant select on public.push_events_invoke_status to authenticated, service_role;
