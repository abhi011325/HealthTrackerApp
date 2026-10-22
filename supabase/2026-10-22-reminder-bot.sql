-- Telegram reminder bot, entirely inside Supabase. Safe to run more than once.
-- pg_cron fires public.bot_tick() every minute; it posts any due reminder to Telegram via pg_net.
-- Tables live in public with RLS on and NO policies, so the app's anon/authenticated roles see nothing;
-- the service key (scripts/reminders.sh on the Mac) and the cron job (postgres) manage them.

create extension if not exists pg_cron;
create extension if not exists pg_net;

create table if not exists public.bot_config (
  key text primary key,            -- 'telegram_token', 'chat_id', 'shift_minutes' (60 in winter, 0 in summer), 'enabled'
  value text not null
);
create table if not exists public.bot_reminders (
  id serial primary key,
  label text not null,
  time_ist time not null,          -- summer time; shift_minutes is added at send time
  days int[] not null default '{0,1,2,3,4,5,6}',   -- 0 = Sunday … 6 = Saturday
  message text not null,
  enabled boolean not null default true
);
create table if not exists public.bot_sent (
  reminder_id int not null references public.bot_reminders(id) on delete cascade,
  sent_on date not null,
  sent_at timestamptz not null default now(),
  primary key (reminder_id, sent_on)
);

alter table public.bot_config    enable row level security;
alter table public.bot_reminders enable row level security;
alter table public.bot_sent      enable row level security;
revoke all on public.bot_config, public.bot_reminders, public.bot_sent from anon, authenticated;

insert into public.bot_config (key, value) values ('shift_minutes', '0'), ('enabled', 'true')
on conflict (key) do nothing;

-- Send one message now. Used by the tick and for tests.
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
    headers := '{"Content-Type":"application/json"}'::jsonb
  ) into rid;
  return rid;
end $$;

-- Runs every minute. "Local" = IST minus the seasonal shift, so a reminder stored at 08:30 fires at 09:30 when shift_minutes = 60.
create or replace function public.bot_tick() returns int
language plpgsql security definer set search_path = public as $$
declare shift int; local_now timestamp; r record; n int := 0;
begin
  if coalesce((select value from public.bot_config where key = 'enabled'), 'true') <> 'true' then return 0; end if;
  shift := coalesce((select value::int from public.bot_config where key = 'shift_minutes'), 0);
  local_now := (now() at time zone 'Asia/Kolkata') - make_interval(mins => shift);
  for r in
    select * from public.bot_reminders
    where enabled
      and extract(dow from local_now)::int = any(days)
      and time_ist <= local_now::time
      and time_ist >  (local_now - interval '10 minutes')::time   -- catch-up window if cron lagged
      and not exists (select 1 from public.bot_sent s where s.reminder_id = bot_reminders.id and s.sent_on = local_now::date)
  loop
    insert into public.bot_sent (reminder_id, sent_on) values (r.id, local_now::date);
    perform public.bot_send(r.message);
    n := n + 1;
  end loop;
  return n;
end $$;

revoke all on function public.bot_send(text) from public, anon, authenticated;
revoke all on function public.bot_tick() from public, anon, authenticated;
grant execute on function public.bot_send(text) to service_role;   -- scripts/reminders.sh test

-- The schedule: summer times. Mon–Sat = {1,2,3,4,5,6}; daily = default.
delete from public.bot_sent; delete from public.bot_reminders;
insert into public.bot_reminders (label, time_ist, days, message) values
  ('wake',        '06:00', '{0,1,2,3,4,5,6}', 'Good morning. Water, then weigh in. Log it and yesterday''s steps in the app.'),
  ('kuhu-am',     '06:30', '{1,2,3,4,5,6}',   'Kuhu: breakfast, then walk and talk till she leaves. Coffee if you want it.'),
  ('workout',     '07:00', '{1,2,3,4,5,6}',   'Workout. Fasted. Go.'),
  ('slot1',       '08:30', '{1,2,3,4,5,6}',   'Slot 1: whey in water + 2-egg omelette. Job hours start.'),
  ('slot2',       '11:30', '{0,1,2,3,4,5,6}', 'Slot 2: 200 g dahi, salt and jeera.'),
  ('projects',    '12:30', '{1,2,3,4,5,6}',   'Personal projects till 3. First 15 minutes: today''s journey clip or photo.'),
  ('slot3',       '15:00', '{0,1,2,3,4,5,6}', 'Slot 3, lunch with Kuhu: salad and 2 boiled eggs first, then 1 roti, dal, sabzi.'),
  ('kuhu-pm',     '15:30', '{1,2,3,4,5,6}',   'Kuhu: walk and talk.'),
  ('no-caffeine', '16:00', '{0,1,2,3,4,5,6}', 'No caffeine from now.'),
  ('slot4',       '17:30', '{0,1,2,3,4,5,6}', 'Slot 4: whey in water. Then Kuhu''s studies till 6:30.'),
  ('shift',       '18:30', '{1,2,3,4,5,6}',   'Fixed job hours start. Till 10:30.'),
  ('slot5',       '20:30', '{0,1,2,3,4,5,6}', 'Slot 5: 100 g paneer with salt, pepper and salad, 3 boiled eggs.'),
  ('bedtime',     '22:30', '{0,1,2,3,4,5,6}', 'Bedtime alarm. Screens off. Slot 6: chana, makhana or walnuts, and tea. Then the walk.'),
  ('lights-out',  '23:00', '{0,1,2,3,4,5,6}', 'Lights out.'),
  ('review',      '19:00', '{0}',             'Sunday review, 15 minutes: open the app. 7-day average vs last week, waist, workouts done, sleep nights held, floor or full week.'),
  ('eggs-sun',    '10:00', '{0}',             'Boil 15 eggs for the week. Roast the makhana if it''s this week''s snack.'),
  ('eggs-wed',    '10:00', '{3}',             'Boil the second 15 eggs.');

select cron.unschedule('bot-tick') where exists (select 1 from cron.job where jobname = 'bot-tick');
select cron.schedule('bot-tick', '* * * * *', 'select public.bot_tick()');
