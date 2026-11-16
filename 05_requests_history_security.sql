-- Run in Supabase SQL Editor AFTER 04_jericho_278_migration.sql.
-- Transaction-safe request approval, history and account profile synchronization.
begin;
alter table public.jericho_requests add column if not exists reviewed_at timestamptz;
alter table public.jericho_requests add column if not exists reviewed_by uuid references public.profiles(id);
create index if not exists jericho_requests_status_created on public.jericho_requests(status,created_at desc);
-- Approval is the only allowed way to change request status.
revoke update on public.jericho_requests from authenticated;
drop policy if exists jericho_requests_manager_update on public.jericho_requests;
create or replace function public.jericho_review_request(p_request_id uuid,p_decision text)
returns void language plpgsql security definer set search_path='' as $$
declare r public.jericho_requests%rowtype; s public.jericho_spaces%rowtype;
begin
 if not public.is_manager() then raise exception 'Managers only'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into r from public.jericho_requests where id=p_request_id for update;
 if not found then raise exception 'Request not found'; end if;
 if r.status<>'pending' then raise exception 'Request already reviewed'; end if;
 select * into s from public.jericho_spaces where id=r.spot_id for update;
 if not found then raise exception 'Space not found'; end if;
 if p_decision='approved' then
   if s.unavailable then raise exception 'Space is unavailable'; end if;
   if exists(select 1 from public.jericho_requests where spot_id=r.spot_id and status='approved') then raise exception 'Space already assigned'; end if;
   update public.jericho_spaces set unavailable=true,updated_at=now() where id=r.spot_id;
 end if;
 update public.jericho_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id;
 insert into public.activity_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'jericho_request_'||p_decision,'jericho_request',p_request_id,
 jsonb_build_object('spot_id',r.spot_id,'resident_name',r.resident_name,'apartment_number',r.apartment_number,'license_plate',r.license_plate));
end;$$;
revoke all on function public.jericho_review_request(uuid,text) from public,anon;
grant execute on function public.jericho_review_request(uuid,text) to authenticated;
-- Approved spots remain unavailable even if layout editor submits an outdated value.
create or replace function public.jericho_protect_approved_space()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.jericho_requests where spot_id=new.id and status='approved') then
   new.unavailable=true;
 end if;
 return new;
end;$$;
drop trigger if exists jericho_protect_approved_space on public.jericho_spaces;
create trigger jericho_protect_approved_space before update on public.jericho_spaces
for each row execute function public.jericho_protect_approved_space();
-- Audit manager layout changes (not every refresh).
create or replace function public.jericho_log_space_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.geometry is distinct from new.geometry or old.display_name is distinct from new.display_name or old.unavailable is distinct from new.unavailable then
  insert into public.activity_logs(actor_id,action,entity_type,details)
  values(auth.uid(),'parking_space_updated','jericho_space',jsonb_build_object('spot_id',new.id,'old_unavailable',old.unavailable,'new_unavailable',new.unavailable,'old_name',old.display_name,'new_name',new.display_name,'geometry_changed',old.geometry is distinct from new.geometry));
 end if;
 return new;
end;$$;
drop trigger if exists jericho_log_space_change on public.jericho_spaces;
create trigger jericho_log_space_change after update on public.jericho_spaces
for each row execute function public.jericho_log_space_change();
-- Keep profiles.email in sync with Supabase Auth email confirmations and admin changes.
create or replace function public.jericho_sync_profile_email()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.email is distinct from old.email then
  update public.profiles set email=new.email where id=new.id;
 end if;
 return new;
end;$$;
drop trigger if exists jericho_sync_profile_email on auth.users;
create trigger jericho_sync_profile_email after update of email on auth.users
for each row execute function public.jericho_sync_profile_email();
commit;
-- Add support for releasing completed parking assignments.
begin;
alter table public.jericho_requests drop constraint if exists jericho_requests_status_check;
alter table public.jericho_requests add constraint jericho_requests_status_check check(status in ('pending','approved','rejected','released'));
create or replace function public.jericho_release_assignment(p_request_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare r public.jericho_requests%rowtype;
begin
 if not public.is_manager() then raise exception 'Managers only'; end if;
 select * into r from public.jericho_requests where id=p_request_id for update;
 if not found or r.status<>'approved' then raise exception 'No active assignment for this request'; end if;
 update public.jericho_requests set status='released',reviewed_at=now(),reviewed_by=auth.uid() where id=r.id;
 update public.jericho_spaces set unavailable=false,updated_at=now() where id=r.spot_id;
 insert into public.activity_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'jericho_assignment_released','jericho_request',r.id,jsonb_build_object('spot_id',r.spot_id,'resident_name',r.resident_name,'apartment_number',r.apartment_number));
end;$$;
revoke all on function public.jericho_release_assignment(uuid) from public,anon;
grant execute on function public.jericho_release_assignment(uuid) to authenticated;
commit;
