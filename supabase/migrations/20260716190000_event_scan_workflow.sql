-- Event lifecycle and scan-only attendance workflow.

create or replace function public.refresh_event_participants(p_event_id bigint)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  n integer;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;

  -- Remove members that are no longer eligible, but always preserve anyone
  -- who already has attendance history for this event.
  delete from public.event_participants ep
  where ep.event_id = p_event_id
    and not exists (
      select 1
      from public.attendance a
      where a.event_id = p_event_id
        and a.member_id = ep.member_id
        and a.status = 'present'
    )
    and not exists (
      select 1
      from public.members m
      join public.event_member_types emt
        on emt.event_id = p_event_id
       and emt.member_type_id = m.member_type_id
      where m.id = ep.member_id
        and m.status = 'active'
    );

  -- Add newly eligible members and refresh snapshots for existing members.
  insert into public.event_participants(
    event_id,
    member_id,
    member_type_id,
    snapshot_name,
    snapshot_user_id
  )
  select
    p_event_id,
    m.id,
    m.member_type_id,
    m.name,
    m.user_id
  from public.members m
  join public.event_member_types emt
    on emt.event_id = p_event_id
   and emt.member_type_id = m.member_type_id
  where m.status = 'active'
  on conflict(event_id, member_id) do update
  set member_type_id = excluded.member_type_id,
      snapshot_name = excluded.snapshot_name,
      snapshot_user_id = excluded.snapshot_user_id;

  select count(*)::integer into n
  from public.event_participants
  where event_id = p_event_id;
  return n;
end;
$$;

create or replace function public.save_event(
  p_id bigint,
  p_data jsonb,
  p_type_ids bigint[]
)
returns bigint
language plpgsql
security invoker
set search_path = public
as $$
declare
  eid bigint;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;
  if nullif(trim(p_data->>'name'), '') is null then
    raise exception 'Nama event wajib diisi';
  end if;
  if coalesce(array_length(p_type_ids, 1), 0) = 0 then
    raise exception 'Pilih minimal satu tipe member';
  end if;

  if p_id is null then
    insert into public.events(
      name,
      description,
      location,
      start_at,
      end_at,
      status
    )
    values(
      trim(p_data->>'name'),
      nullif(trim(p_data->>'description'), ''),
      nullif(trim(p_data->>'location'), ''),
      (p_data->>'start_at')::timestamptz,
      (p_data->>'end_at')::timestamptz,
      p_data->>'status'
    )
    returning id into eid;
  else
    eid := p_id;
    update public.events
    set name = trim(p_data->>'name'),
        description = nullif(trim(p_data->>'description'), ''),
        location = nullif(trim(p_data->>'location'), ''),
        start_at = (p_data->>'start_at')::timestamptz,
        end_at = (p_data->>'end_at')::timestamptz,
        status = p_data->>'status'
    where id = eid;
    if not found then
      raise exception 'Event tidak ditemukan';
    end if;
  end if;

  delete from public.event_member_types where event_id = eid;
  insert into public.event_member_types(event_id, member_type_id)
  select eid, x
  from unnest(p_type_ids) x
  join public.member_types mt on mt.id = x and mt.is_active;

  perform public.refresh_event_participants(eid);
  return eid;
end;
$$;

create or replace function public.check_in_member(
  p_event_id bigint,
  p_barcode text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m public.members;
  a public.attendance;
begin
  if not public.is_admin() then
    raise exception 'Unauthorized';
  end if;
  if not exists (
    select 1 from public.events
    where id = p_event_id and status = 'ongoing'
  ) then
    raise exception 'Event belum berjalan atau sudah selesai';
  end if;

  select * into m
  from public.members
  where barcode_value = p_barcode;
  if m.id is null then
    raise exception 'Barcode/member tidak ditemukan';
  end if;
  if m.status <> 'active' then
    raise exception 'Member tidak aktif';
  end if;
  if not exists (
    select 1
    from public.event_participants
    where event_id = p_event_id and member_id = m.id
  ) then
    raise exception 'Member tidak eligible untuk event ini';
  end if;

  insert into public.attendance(event_id, member_id, status)
  values(p_event_id, m.id, 'present')
  on conflict(event_id, member_id) do update
  set status = 'present',
      checked_in_at = now(),
      checked_in_by = auth.uid()
  where attendance.status = 'cancelled'
  returning * into a;

  if a.id is null then
    raise exception 'Member sudah tercatat hadir';
  end if;
  return jsonb_build_object(
    'member_id', m.id,
    'name', m.name,
    'user_id', m.user_id,
    'checked_in_at', a.checked_in_at
  );
end;
$$;

-- Attendance can be read by admins, but writes only happen through the
-- validated QR check-in function above.
drop policy if exists attendance_admin_only on public.attendance;
drop policy if exists attendance_admin_select on public.attendance;
create policy attendance_admin_select
on public.attendance
for select
to authenticated
using (public.is_admin());

revoke insert, update, delete on public.attendance from authenticated;
grant select on public.attendance to authenticated;
grant execute on function public.refresh_event_participants(bigint) to authenticated;
grant execute on function public.save_event(bigint, jsonb, bigint[]) to authenticated;
grant execute on function public.check_in_member(bigint, text) to authenticated;

