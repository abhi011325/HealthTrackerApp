-- Migration: earned day (rule-based rest day) + per-user goal weight. Safe to run more than once.
-- Run in Supabase > SQL Editor. New projects just run schema.sql.

alter table public.profiles add column if not exists goal_kg numeric(5,1) check (goal_kg > 20 and goal_kg < 400);

create table if not exists public.earned_days (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,                 -- the day he tapped "Take today"
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,   -- same-day undo
  primary key (user_id, date)
);
create index if not exists earned_days_user_updated on public.earned_days (user_id, updated_at);
alter table public.earned_days enable row level security;
drop policy if exists "own earned_days" on public.earned_days;
create policy "own earned_days" on public.earned_days for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.reset_my_data() returns timestamptz language plpgsql security definer set search_path = public as $$
declare ts timestamptz := now();
begin
  delete from public.weights     where user_id = auth.uid();
  delete from public.gaps        where user_id = auth.uid();
  delete from public.reasons     where user_id = auth.uid();
  delete from public.steps       where user_id = auth.uid();
  delete from public.earned_days where user_id = auth.uid();
  update public.profiles set reset_at = ts where id = auth.uid();
  return ts;
end $$;
