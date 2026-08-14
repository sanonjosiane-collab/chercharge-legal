alter table public.push_events
  add column if not exists delivered_at timestamptz;
