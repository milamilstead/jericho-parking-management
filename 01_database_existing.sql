-- Jericho Residences parking management: initial secure schema
-- Run once in Supabase SQL Editor on a NEW project.
create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role text not null default 'employee' check (role in ('manager','employee')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.parking_spots (
  id uuid primary key default gen_random_uuid(),
  spot_number text not null unique,
  section text not null check (section in ('P1','P2','P3','P4')),
  spot_type text not null default 'standard' check (spot_type in ('standard','accessible','visitor','loading','other')),
  status text not null default 'available' check (status in ('available','reserved','unavailable')),
  map_x numeric(8,5),
  map_y numeric(8,5),
  notes text,
  created_at timestamptz not null default now(),
  constraint coordinates_pair check ((map_x is null and map_y is null) or (map_x between 0 and 100 and map_y between 0 and 100))
);

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  spot_id uuid not null references public.parking_spots(id) on delete restrict,
  apartment_number text not null,
  notes text,
  assigned_by uuid not null references public.profiles(id),
  assigned_at timestamptz not null default now(),
  released_by uuid references public.profiles(id),
  released_at timestamptz,
  constraint release_pair check ((released_at is null and released_by is null) or (released_at is not null and released_by is not null))
);
create unique index assignments_one_active_per_spot on public.assignments(spot_id) where released_at is null;

create table public.activity_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index parking_spots_section_idx on public.parking_spots(section);
create index assignments_apartment_idx on public.assignments(apartment_number);
create index activity_logs_time_idx on public.activity_logs(occurred_at desc);

-- This checks the caller's role using a security-definer function,
-- avoiding recursive profile RLS evaluation.
create function public.is_active_staff()
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists(select 1 from public.profiles p where p.id = (select auth.uid()) and p.active);
$$;
create function public.is_manager()
returns boolean language sql stable security definer
set search_path = '' as $$
  select exists(select 1 from public.profiles p where p.id = (select auth.uid()) and p.active and p.role = 'manager');
$$;

-- Only trusted server-side code can change profiles and spot layouts.
-- Never expose the service_role key in browser JavaScript.
alter table public.profiles enable row level security;
alter table public.parking_spots enable row level security;
alter table public.assignments enable row level security;
alter table public.activity_logs enable row level security;

create policy profiles_read on public.profiles for select to authenticated
using (id = (select auth.uid()) or (select public.is_manager()));

create policy spots_read on public.parking_spots for select to authenticated
using ((select public.is_active_staff()));

create policy assignments_read on public.assignments for select to authenticated
using ((select public.is_active_staff()));

create policy logs_manager_read on public.activity_logs for select to authenticated
using ((select public.is_manager()));

-- Do not grant direct write access to these tables from client accounts.
-- Assignment changes will be exposed through an audited database function in step 2.
revoke all on public.profiles, public.parking_spots, public.assignments, public.activity_logs from anon;
revoke insert, update, delete on public.profiles, public.parking_spots, public.assignments, public.activity_logs from authenticated;
grant select on public.profiles, public.parking_spots, public.assignments, public.activity_logs to authenticated;
revoke all on function public.is_active_staff() from public, anon;
revoke all on function public.is_manager() from public, anon;
grant execute on function public.is_active_staff(), public.is_manager() to authenticated;
