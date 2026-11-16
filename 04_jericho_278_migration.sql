-- Jericho 278-space integrated layout. Run ONCE after existing 01/02 migrations.
-- Existing parking_spots / assignments are untouched.
-- New layout is separate because the legacy section constraint allows only P1-P4.
create table if not exists public.jericho_spaces (
 id text primary key,
 lot integer not null check(lot in (100,200,300,400,500)),
 section_name text not null,
 display_name text not null,
 geometry jsonb not null default '{}'::jsonb,
 unavailable boolean not null default false,
 updated_at timestamptz not null default now(),
 constraint space_id_pattern check(id ~ '^(100|200|300|400|500)-(L|R|MA|MB|S)[0-9]{2}$')
);
create table if not exists public.jericho_requests (
 id uuid primary key default gen_random_uuid(),
 spot_id text not null references public.jericho_spaces(id),
 resident_name text not null check(length(btrim(resident_name)) between 1 and 100),
 apartment_number text not null check(length(btrim(apartment_number)) between 1 and 30),
 license_plate text not null check(length(btrim(license_plate)) between 1 and 30),
 notes text not null default '' check(length(notes)<=200),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 created_by uuid not null default auth.uid() references public.profiles(id),
 created_at timestamptz not null default now()
);
create unique index if not exists jericho_one_active_request_per_space
 on public.jericho_requests(spot_id) where status in ('pending','approved');
alter table public.jericho_spaces enable row level security;
alter table public.jericho_requests enable row level security;
revoke all on public.jericho_spaces, public.jericho_requests from anon;
revoke all on public.jericho_spaces, public.jericho_requests from authenticated;
grant select on public.jericho_spaces, public.jericho_requests to authenticated;
grant update on public.jericho_spaces to authenticated;
grant insert on public.jericho_requests to authenticated;
grant update(status) on public.jericho_requests to authenticated;
drop policy if exists jericho_spaces_read on public.jericho_spaces;
create policy jericho_spaces_read on public.jericho_spaces for select to authenticated using (public.is_active_staff());
drop policy if exists jericho_spaces_manager_edit on public.jericho_spaces;
create policy jericho_spaces_manager_edit on public.jericho_spaces for update to authenticated
 using(public.is_manager()) with check(public.is_manager());
drop policy if exists jericho_requests_read on public.jericho_requests;
create policy jericho_requests_read on public.jericho_requests for select to authenticated using(public.is_active_staff());
drop policy if exists jericho_requests_insert on public.jericho_requests;
create policy jericho_requests_insert on public.jericho_requests for insert to authenticated
 with check(public.is_active_staff() and created_by=auth.uid() and status='pending'
 and exists(select 1 from public.jericho_spaces s where s.id=spot_id and not s.unavailable)
);
drop policy if exists jericho_requests_manager_update on public.jericho_requests;
create policy jericho_requests_manager_update on public.jericho_requests for update to authenticated
 using(public.is_manager()) with check(public.is_manager());
-- Seed verified IDs and counts, but diagram coordinates remain editable approximations.
-- A manager should verify physical positions before making real assignments.
with defs(lot,section_name,prefix,n) as (values
 (100,'Left','L',14),(100,'Right','R',10),
 (200,'Left','L',24),(200,'Right','R',23),
 (300,'Side street','S',18),
 (400,'Left','L',22),(400,'Right','R',20),
 (500,'Left','L',35),(500,'Middle A','MA',38),(500,'Middle B','MB',38),(500,'Right','R',36))
insert into public.jericho_spaces(id,lot,section_name,display_name)
select lot::text||'-'||prefix||lpad(i::text,2,'0'),lot,section_name,
 lot::text||'-'||prefix||lpad(i::text,2,'0')
from defs cross join lateral generate_series(1,n) i
on conflict(id) do nothing;
-- Expected count: select lot,count(*) from public.jericho_spaces group by lot order by lot;
