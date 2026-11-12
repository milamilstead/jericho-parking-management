-- Jericho Residences: Run this next in Supabase SQL Editor.
-- Requires the previously installed 01_database.sql and 02_secure_assignments.sql.
-- Lets managers create and edit verified physical spaces; regular employees cannot.
-- Existing assignment functions continue to control reserving and releasing.

create or replace function public.manager_create_spot(
  p_spot_number text, p_section text, p_spot_type text,
  p_status text, p_map_x numeric, p_map_y numeric,
  p_notes text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_spot_id uuid;
  v_number text := btrim(coalesce(p_spot_number,''));
begin
  if v_actor is null or not public.is_manager() then
    raise exception 'Only active managers can change parking layouts';
  end if;
  if v_number = '' or length(v_number) > 50 then
    raise exception 'Spot number is required (max 50 characters)';
  end if;
  if p_section not in ('P1','P2','P3','P4') then
    raise exception 'Invalid parking section';
  end if;
  if p_spot_type not in ('standard','accessible','visitor','loading','other') then
    raise exception 'Invalid spot type';
  end if;
  if p_status not in ('available','unavailable') then
    raise exception 'New spots must start available or unavailable';
  end if;
  if p_map_x is null or p_map_y is null or
     p_map_x < 0 or p_map_x > 100 or p_map_y < 0 or p_map_y > 100 then
    raise exception 'Map position must be between 0 and 100';
  end if;
  if length(coalesce(p_notes,'')) > 2000 then
    raise exception 'Notes are too long';
  end if;

  insert into public.parking_spots
    (spot_number,section,spot_type,status,map_x,map_y,notes)
  values
    (v_number,p_section,p_spot_type,p_status,p_map_x,p_map_y,
     nullif(btrim(coalesce(p_notes,'')),''))
  returning id into v_spot_id;

  insert into public.activity_logs (actor_id,action,entity_type,entity_id,details)
  values (v_actor,'spot_created','parking_spot',v_spot_id,
          jsonb_build_object('spot_number',v_number,'section',p_section));
  return v_spot_id;
end;
$$;

create or replace function public.manager_update_spot(
  p_spot_id uuid, p_spot_number text, p_section text,
  p_spot_type text, p_status text, p_map_x numeric,
  p_map_y numeric, p_notes text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_spot public.parking_spots%rowtype;
  v_number text := btrim(coalesce(p_spot_number,''));
begin
  if v_actor is null or not public.is_manager() then
    raise exception 'Only active managers can change parking layouts';
  end if;
  if v_number = '' or length(v_number) > 50 or
     p_section not in ('P1','P2','P3','P4') or
     p_spot_type not in ('standard','accessible','visitor','loading','other') or
     p_status not in ('available','unavailable','reserved') or
     p_map_x is null or p_map_y is null or
     p_map_x < 0 or p_map_x > 100 or p_map_y < 0 or p_map_y > 100 or
     length(coalesce(p_notes,'')) > 2000 then
    raise exception 'Invalid spot details';
  end if;

  select * into v_spot from public.parking_spots
  where id = p_spot_id for update;
  if not found then raise exception 'Parking space not found'; end if;

  -- Assignment status can ONLY be changed by the assign/release functions.
  if (v_spot.status = 'reserved' and p_status <> 'reserved') or
     (v_spot.status <> 'reserved' and p_status = 'reserved') then
    raise exception 'Use Assign or Release to change a reservation';
  end if;
  if v_spot.status = 'reserved' and p_spot_type in ('visitor','loading') then
    raise exception 'Cannot turn an assigned space into visitor/loading';
  end if;
  update public.parking_spots
  set spot_number=v_number, section=p_section, spot_type=p_spot_type,
      status=p_status, map_x=p_map_x, map_y=p_map_y,
      notes=nullif(btrim(coalesce(p_notes,'')),'')
  where id=p_spot_id;

  insert into public.activity_logs (actor_id,action,entity_type,entity_id,details)
  values (v_actor,'spot_updated','parking_spot',p_spot_id,
          jsonb_build_object('spot_number',v_number,'old_spot_number',v_spot.spot_number));
  return p_spot_id;
end;
$$;

revoke all on function public.manager_create_spot(text,text,text,text,numeric,numeric,text) from public, anon;
revoke all on function public.manager_update_spot(uuid,text,text,text,text,numeric,numeric,text) from public, anon;
grant execute on function public.manager_create_spot(text,text,text,text,numeric,numeric,text) to authenticated;
grant execute on function public.manager_update_spot(uuid,text,text,text,text,numeric,numeric,text) to authenticated;

-- Audited manager-only changes do not rely on browser-side role restrictions.
