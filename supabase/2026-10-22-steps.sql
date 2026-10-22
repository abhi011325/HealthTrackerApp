-- Migration for projects created before 2026-10-22: adds daily steps. Safe to run more than once.
-- Run in Supabase > SQL Editor. New projects just run schema.sql.

alter table public.profiles add column if not exists steps_goal integer not null default 10000 check (steps_goal > 0 and steps_goal < 100000);

create table if not exists public.steps (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  count integer not null check (count >= 0 and count < 100000),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,
  primary key (user_id, date)
);
create index if not exists steps_user_updated on public.steps (user_id, updated_at);
alter table public.steps enable row level security;
drop policy if exists "own steps" on public.steps;
create policy "own steps" on public.steps for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.reset_my_data() returns timestamptz language plpgsql security definer set search_path = public as $$
declare ts timestamptz := now();
begin
  delete from public.weights where user_id = auth.uid();
  delete from public.gaps    where user_id = auth.uid();
  delete from public.reasons where user_id = auth.uid();
  delete from public.steps   where user_id = auth.uid();
  update public.profiles set reset_at = ts where id = auth.uid();
  return ts;
end $$;
