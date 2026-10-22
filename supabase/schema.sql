-- HealthTracker schema. Run once in Supabase > SQL Editor (or: psql "$DB_URL" -f supabase/schema.sql).
-- Every table is per-user; row-level security means a signed-in user sees only their own rows.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  reset_at timestamptz,               -- set by "Start fresh"; devices clear local data when they see a newer value
  created_at timestamptz not null default now()
);

create table if not exists public.weights (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,                 -- local calendar day of the entry
  kg numeric(5,1) not null check (kg > 20 and kg < 400),
  evening boolean not null default false,
  logged_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,
  primary key (user_id, date)
);

create table if not exists public.gaps (
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  reason text not null,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,
  primary key (user_id, date)
);

create table if not exists public.reasons (
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  last_used timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted boolean not null default false,
  primary key (user_id, name)
);

create index if not exists weights_user_updated on public.weights (user_id, updated_at);
create index if not exists gaps_user_updated on public.gaps (user_id, updated_at);
create index if not exists reasons_user_updated on public.reasons (user_id, updated_at);

alter table public.profiles enable row level security;
alter table public.weights  enable row level security;
alter table public.gaps     enable row level security;
alter table public.reasons  enable row level security;

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "own weights" on public.weights;
create policy "own weights" on public.weights for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "own gaps" on public.gaps;
create policy "own gaps" on public.gaps for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "own reasons" on public.reasons;
create policy "own reasons" on public.reasons for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- A profile row appears automatically for every account; the name comes from user metadata set at creation.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name) values (new.id, coalesce(new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- "Start fresh": deletes the caller's rows and stamps reset_at so other devices wipe their local copy.
create or replace function public.reset_my_data() returns timestamptz language plpgsql security definer set search_path = public as $$
declare ts timestamptz := now();
begin
  delete from public.weights where user_id = auth.uid();
  delete from public.gaps    where user_id = auth.uid();
  delete from public.reasons where user_id = auth.uid();
  update public.profiles set reset_at = ts where id = auth.uid();
  return ts;
end $$;
