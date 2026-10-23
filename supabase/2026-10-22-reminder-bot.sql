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

-- The schedule: summer times, one message at every block boundary, every day incl. Sunday. Food slots carry the weekly rotation from PLAN.md section 5 (lunch eggs Sun/Mon/Wed/Fri, paneer Tue/Thu/Sat; dinner 3 or 2 eggs; snack chana/makhana/walnuts/pistachios/pumpkin seeds).
delete from public.bot_sent; delete from public.bot_reminders;
insert into public.bot_reminders (label, time_ist, days, message) values
  ('wake', '06:00', '{0,1,2,3,4,5,6}', E'6:00. Good morning. Water, toilet, brush, then weigh in. Log the weight and yesterday''s steps in the app.'),
  ('kuhu-am', '06:30', '{0,1,2,3,4,5,6}', E'6:30 to 7:00. Kuhu: her breakfast, then walk and talk till she leaves. Black coffee or americano if you want it.'),
  ('workout', '07:00', '{0,1,2,3,4,5,6}', E'7:00 to 8:00. Workout, fasted.'),
  ('get-ready', '08:00', '{0,1,2,3,4,5,6}', E'8:00 to 8:30. Shower, get ready. Make the omelette.'),
  ('job-flex', '08:30', '{0,1,2,3,4,5,6}', E'8:30 to 12:30. Job, flexible 4 hours.\nSlot 1 now: 1 scoop whey in water, 2-egg omelette.'),
  ('slot2', '11:30', '{0,1,2,3,4,5,6}', E'11:30. Slot 2: 200 g Amul dahi with berries or one chopped fruit.'),
  ('projects-1', '12:30', '{0,1,2,3,4,5,6}', E'12:30 to 3:00. Personal projects. First 15 minutes: today''s journey clip or photo.'),
  ('slot3-eggs', '15:00', '{0,1,3,5}', E'3:00 to 3:30. Slot 3, lunch with Kuhu: salad and 2 boiled eggs first, then 1 roti, 1 cup dal, sabzi.'),
  ('slot3-paneer', '15:00', '{2,4,6}', E'3:00 to 3:30. Slot 3, lunch with Kuhu: salad and 100 g FruBon paneer cubes first, then 1 roti, 1 cup dal, sabzi.'),
  ('kuhu-pm', '15:30', '{0,1,2,3,4,5,6}', E'3:30 to 4:00. Kuhu: walk and talk.'),
  ('projects-2', '16:00', '{0,1,2,3,4,5,6}', E'4:00 to 5:30. Personal projects. No caffeine from now.'),
  ('slot4', '17:30', '{0,1,2,3,4,5,6}', E'5:30 to 6:30. Slot 4: 1 scoop whey in water. Then Kuhu''s studies.'),
  ('job-fixed', '18:30', '{0,1,2,3,4,5,6}', E'6:30 to 10:30. Job, fixed 4 hours.'),
  ('slot5-2eggs', '20:30', '{2,4,6}', E'8:30. Slot 5: 100 g FruBon paneer with salt, pepper and salad, 2 boiled eggs.'),
  ('slot5-3eggs', '20:30', '{0,1,3,5}', E'8:30. Slot 5: 100 g FruBon paneer with salt, pepper and salad, 3 boiled eggs.'),
  ('shutdown-chana', '22:30', '{1,6}', E'10:30. Shut down, screens off.\nSlot 6: 30 g roasted chana, and tea.\nThen the walk and family time till 11:00.'),
  ('shutdown-makhana', '22:30', '{2,0}', E'10:30. Shut down, screens off.\nSlot 6: 30 g roasted makhana, and tea.\nThen the walk and family time till 11:00.'),
  ('shutdown-pista', '22:30', '{4}', E'10:30. Shut down, screens off.\nSlot 6: 20 g pistachios, and tea.\nThen the walk and family time till 11:00.'),
  ('shutdown-pumpkin', '22:30', '{5}', E'10:30. Shut down, screens off.\nSlot 6: 20 g pumpkin seeds, and tea.\nThen the walk and family time till 11:00.'),
  ('shutdown-walnuts', '22:30', '{3}', E'10:30. Shut down, screens off.\nSlot 6: 20 g walnuts, 5 halves, and tea.\nThen the walk and family time till 11:00.'),
  ('lights-out', '23:00', '{0,1,2,3,4,5,6}', E'11:00. Lights out.');

select cron.unschedule('bot-tick') where exists (select 1 from cron.job where jobname = 'bot-tick');
select cron.schedule('bot-tick', '* * * * *', 'select public.bot_tick()');
