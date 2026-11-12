-- Jericho Residences: secure parking assignment functions
-- Run AFTER 01_database.sql and after creating the first manager profile.
-- Uses the authenticated Supabase user's identity; never pass an employee ID from the browser.

create or replace function public.assign_parking_spot(
  p_spot_id uuid,
  p_apartment_number text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_spot public.parking_spots%rowtype;
  v_assignment_id uuid;
  v_apartment text := btrim(coalesce(p_apartment_number, ''));
begin
  if v_actor is null or not public.is_active_staff() then
    raise exception 'Not authorized to assign parking spaces';
  end if;
  if v_apartment = '' or length(v_apartment) > 40 then
    raise exception 'Enter a valid apartment number (1 to 40 characters)';
  end if;
  if length(coalesce(p_notes, '')) > 2000 then
    raise exception 'Notes are too long';
  end if;

  -- Lock the physical spot row so competing assignments serialize.
  select * into v_spot
  from public.parking_spots
  where id = p_spot_id
  for update;
  if not found then
    raise exception 'Parking space not found';
  end if;
  if v_spot.status <> 'available' then
    raise exception 'This parking space is not available';
  end if;
  if v_spot.spot_type in ('visitor', 'loading') then
    raise exception 'Visitor and loading spaces cannot be assigned to apartments';
  end if;

  insert into public.assignments (spot_id, apartment_number, notes, assigned_by)
  values (p_spot_id, v_apartment, nullif(btrim(coalesce(p_notes, '')), ''), v_actor)
  returning id into v_assignment_id;

  update public.parking_spots set status = 'reserved' where id = p_spot_id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_actor, 'assigned', 'parking_spot', p_spot_id,
          jsonb_build_object('assignment_id', v_assignment_id, 'spot_number', v_spot.spot_number, 'apartment_number', v_apartment));

  return v_assignment_id;
end;
$$;

create or replace function public.release_parking_spot(p_spot_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_spot public.parking_spots%rowtype;
  v_assignment_id uuid;
  v_apartment text;
begin
  if v_actor is null or not public.is_active_staff() then
    raise exception 'Not authorized to release parking spaces';
  end if;

  select * into v_spot
  from public.parking_spots
  where id = p_spot_id
  for update;
  if not found then
    raise exception 'Parking space not found';
  end if;

  update public.assignments
  set released_by = v_actor, released_at = now()
  where spot_id = p_spot_id and released_at is null
  returning id, apartment_number into v_assignment_id, v_apartment;
  if v_assignment_id is null then
    raise exception 'No active assignment exists for this parking space';
  end if;

  update public.parking_spots set status = 'available' where id = p_spot_id;

  insert into public.activity_logs (actor_id, action, entity_type, entity_id, details)
  values (v_actor, 'released', 'parking_spot', p_spot_id,
          jsonb_build_object('assignment_id', v_assignment_id, 'spot_number', v_spot.spot_number, 'apartment_number', v_apartment));

  return v_assignment_id;
end;
$$;

-- Only logged-in users can call these functions. Each function also checks
-- for an active employee/manager profile at execution time.
revoke all on function public.assign_parking_spot(uuid, text, text) from public, anon;
revoke all on function public.release_parking_spot(uuid) from public, anon;
grant execute on function public.assign_parking_spot(uuid, text, text) to authenticated;
grant execute on function public.release_parking_spot(uuid) to authenticated;
