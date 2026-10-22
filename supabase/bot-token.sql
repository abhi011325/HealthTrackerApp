-- One-time setup for the Telegram reminder bot. Abhishek runs this himself in Supabase > SQL Editor.
-- 1. In Telegram, message @BotFather, send /newbot, follow the two prompts; it replies with a token like 123456789:AAH...
-- 2. Send your new bot any message (e.g. "hi"), so it has your chat.
-- 3. Open this in a browser, with your token in place of TOKEN:  https://api.telegram.org/botTOKEN/getUpdates
--    In the reply find "chat":{"id":123456789 ...  — that number is your chat id.
-- 4. Put both below, run this file. Then run the last line to get a test message.

insert into public.bot_config (key, value) values
  ('telegram_token', 'PASTE_TOKEN_HERE'),
  ('chat_id',        'PASTE_CHAT_ID_HERE'),
  ('enabled',        'true')
on conflict (key) do update set value = excluded.value;

select public.bot_send('HealthTracker reminders are on. First one comes at the next slot.');
