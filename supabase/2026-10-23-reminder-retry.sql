-- 2026-10-23: retry Telegram sends that time out or fail. Safe to run more than once.
-- Why: the 12:30 reminder on 2026-10-23 was lost because Telegram did not answer within pg_net's
-- 5 s default timeout, and bot_tick marked the reminder sent before knowing whether Telegram took it.
-- Now: 20 s timeout; each sent row remembers its pg_net request id; the every-minute tick re-sends any
-- row from the last 15 minutes whose response is missing a 200, up to 3 attempts in total.

alter table public.bot_sent
  add column if not exists request_id bigint,
  add column if not exists attempts int not null default 1;

create or replace function public.bot_send(msg text) returns bigint
language plpgsql security definer set search_path = public as $$
declare tok text; chat text; rid bigint;
begin
  select value into tok  from public.bot_config where key = 'telegram_token';
  select value into chat from public.bot_config where key = 'chat_id';
  if tok is null or chat is null then raise exception 'bot_config needs telegram_token and chat_id'; end if;
  select net.http_post(
    url := 'https://api.telegram.org/bot' || tok || '/sendMessage',
    body := jsonb_build_object('chat_id', chat, 'text', msg),
    headers := '{"Content-Type":"application/json"}'::jsonb,
    timeout_milliseconds := 20000
  ) into rid;
  return rid;
end $$;

create or replace function public.bot_tick() returns int
language plpgsql security definer set search_path = public as $$
declare shift int; local_now timestamp; r record; f record; rid bigint; n int := 0;
begin
  if coalesce((select value from public.bot_config where key = 'enabled'), 'true') <> 'true' then return 0; end if;
  shift := coalesce((select value::int from public.bot_config where key = 'shift_minutes'), 0);
  local_now := (now() at time zone 'Asia/Kolkata') - make_interval(mins => shift);

  -- 1. Due reminders not yet sent today.
  for r in
    select * from public.bot_reminders
    where enabled
      and extract(dow from local_now)::int = any(days)
      and time_ist <= local_now::time
      and time_ist >  (local_now - interval '10 minutes')::time   -- catch-up window if cron lagged
      and not exists (select 1 from public.bot_sent s where s.reminder_id = bot_reminders.id and s.sent_on = local_now::date)
  loop
    rid := public.bot_send(r.message);
    insert into public.bot_sent (reminder_id, sent_on, request_id) values (r.id, local_now::date, rid);
    n := n + 1;
  end loop;

  -- 2. Recent sends whose Telegram response is a timeout or an error: send again.
  --    A request still in flight has no response row yet and is left alone.
  for f in
    select s.reminder_id, s.sent_on, s.attempts, rm.message
    from public.bot_sent s
    join public.bot_reminders rm on rm.id = s.reminder_id
    join net._http_response h on h.id = s.request_id
    where s.sent_at > now() - interval '15 minutes'
      and s.attempts < 3
      and (h.status_code is null or h.status_code <> 200)
  loop
    rid := public.bot_send(f.message);
    update public.bot_sent set request_id = rid, attempts = f.attempts + 1
      where reminder_id = f.reminder_id and sent_on = f.sent_on;
    n := n + 1;
  end loop;

  return n;
end $$;

-- Read-only view of recent deliveries for scripts/reminders.sh log (service key).
create or replace function public.bot_log(hours int default 24)
returns table (sent_on date, sent_at_ist timestamp, label text, attempts int, status int, error text)
language sql security definer set search_path = public as $$
  select s.sent_on, (s.sent_at at time zone 'Asia/Kolkata')::timestamp(0), rm.label, s.attempts,
         h.status_code, h.error_msg
  from public.bot_sent s
  join public.bot_reminders rm on rm.id = s.reminder_id
  left join net._http_response h on h.id = s.request_id
  where s.sent_at > now() - make_interval(hours => hours)
  order by s.sent_at desc
$$;
revoke all on function public.bot_log(int) from public, anon, authenticated;
grant execute on function public.bot_log(int) to service_role;
