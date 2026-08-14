-- Invoke notify-booking-push whenever a row is inserted into public.push_events.
-- Uses pg_net (async HTTP) so the inserting transaction is not blocked on FCM.
--
-- Recursion safety: the Edge Function must be called with from_push_event=true so it
-- sends FCM/APNs without inserting another push_events row.
--
-- Auth: looks up a service-role (or publishable) key from Vault / app.settings.
-- If missing, set one (see comments at bottom of this file / SQL Editor paste).

create extension if not exists pg_net with schema extensions;

alter table public.push_events
  add column if not exists delivered_at timestamptz;

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
  -- Only handle known customer/driver alert events.
  if NEW.event = 'inspection_ready_preTrip' then
    phase := 'preTrip';
  elsif NEW.event = 'inspection_ready_postTrip' then
    phase := 'postTrip';
  elsif NEW.event in ('driver_pickup_approved', 'driver_return_approved') then
    phase := null;
  else
    return NEW;
  end if;

  -- Project URL: prefer Vault / GUC, else this project's hosted URL.
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

  -- Prefer service role; publishable/anon also works (function verify_jwt=false + apikey check).
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
      'push_events_invoke_notify_booking_push: no Vault/GUC API key found; Edge call will 401. Store service_role_key (or anon_key) in Vault.';
    return NEW;
  end if;

  if phase is not null then
    payload := jsonb_build_object(
      'booking_id', NEW.booking_id,
      'phase', phase,
      'push_event_id', NEW.id,
      'from_push_event', true
    );
  else
    payload := jsonb_build_object(
      'booking_id', NEW.booking_id,
      'event', NEW.event,
      'push_event_id', NEW.id,
      'from_push_event', true
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
    timeout_milliseconds := 5000
  )
  into req_id;

  return NEW;
exception
  when others then
    -- Never block the insert if HTTP enqueue fails.
    raise warning 'push_events_invoke_notify_booking_push failed: %', SQLERRM;
    return NEW;
end;
$$;

comment on function public.push_events_invoke_notify_booking_push() is
  'After INSERT on push_events, async HTTP POST to notify-booking-push (from_push_event=true).';

drop trigger if exists push_events_notify_booking_push on public.push_events;
create trigger push_events_notify_booking_push
  after insert on public.push_events
  for each row
  execute function public.push_events_invoke_notify_booking_push();

-- Optional: keep Realtime publication (customer in-app listeners).
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'push_events'
  ) then
    alter publication supabase_realtime add table public.push_events;
  end if;
end $$;
