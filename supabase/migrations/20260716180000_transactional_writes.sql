create or replace function public.save_event(p_id bigint, p_data jsonb, p_type_ids bigint[])
returns bigint language plpgsql security invoker set search_path = public as $$
declare eid bigint;
begin
  if not public.is_admin() then raise exception 'Unauthorized'; end if;
  if nullif(trim(p_data->>'name'),'') is null then raise exception 'Nama event wajib diisi'; end if;
  if coalesce(array_length(p_type_ids,1),0)=0 then raise exception 'Pilih minimal satu tipe member'; end if;
  if p_id is not null and exists(select 1 from public.attendance where event_id=p_id and status='present') then raise exception 'Event tidak bisa diubah setelah presensi dimulai'; end if;
  if p_id is null then
    insert into public.events(name,description,location,start_at,end_at,status)
    values(trim(p_data->>'name'),nullif(trim(p_data->>'description'),''),nullif(trim(p_data->>'location'),''),(p_data->>'start_at')::timestamptz,(p_data->>'end_at')::timestamptz,p_data->>'status') returning id into eid;
  else
    eid:=p_id;
    update public.events set name=trim(p_data->>'name'),description=nullif(trim(p_data->>'description'),''),location=nullif(trim(p_data->>'location'),''),start_at=(p_data->>'start_at')::timestamptz,end_at=(p_data->>'end_at')::timestamptz,status=p_data->>'status' where id=eid;
    if not found then raise exception 'Event tidak ditemukan'; end if;
  end if;
  delete from public.event_member_types where event_id=eid;
  insert into public.event_member_types(event_id,member_type_id) select eid,x from unnest(p_type_ids) x join public.member_types mt on mt.id=x and mt.is_active;
  perform public.refresh_event_participants(eid);
  return eid;
end; $$;
grant execute on function public.save_event(bigint,jsonb,bigint[]) to authenticated;

create or replace function public.update_member(p_id bigint, p_data jsonb, p_custom_values jsonb)
returns void language plpgsql security invoker set search_path = public as $$
declare field record;
begin
  if not public.is_admin() then raise exception 'Unauthorized'; end if;
  if nullif(trim(p_data->>'name'),'') is null then raise exception 'Nama wajib diisi'; end if;
  update public.members set member_type_id=(p_data->>'member_type_id')::bigint,name=trim(p_data->>'name'),nik=nullif(trim(p_data->>'nik'),''),email=nullif(trim(p_data->>'email'),''),phone=nullif(trim(p_data->>'phone'),''),role=p_data->>'role',status=p_data->>'status',photo_path=nullif(p_data->>'photo_path','') where id=p_id;
  if not found then raise exception 'Member tidak ditemukan'; end if;
  for field in select id,is_required from public.member_field_definitions where is_active loop
    if field.is_required and nullif(p_custom_values->>field.id::text,'') is null then raise exception 'Custom field wajib belum diisi'; end if;
    insert into public.member_field_values(member_id,field_definition_id,value) values(p_id,field.id,p_custom_values->>field.id::text)
    on conflict(member_id,field_definition_id) do update set value=excluded.value;
  end loop;
end; $$;
grant execute on function public.update_member(bigint,jsonb,jsonb) to authenticated;
