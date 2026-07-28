-- Production hardening and transactional APIs for MyMember.

create or replace function public.has_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where role = 'admin' and is_active); $$;

grant execute on function public.has_admin() to anon, authenticated;

create or replace function public.handle_first_admin()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(73012026);
  if not exists (select 1 from public.profiles) then
    insert into public.profiles(id, role, user_input)
    values (new.id, 'admin', new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_first_admin();

create or replace function public.touch_audit_fields()
returns trigger language plpgsql set search_path = public
as $$
begin
  new.user_edit := auth.uid();
  new.time_edit := now();
  return new;
end;
$$;

create or replace function public.write_audit_log()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  rid text;
  action_name text;
begin
  rid := coalesce(to_jsonb(new)->>'id', to_jsonb(old)->>'id',
    to_jsonb(new)->>'member_id', to_jsonb(old)->>'member_id', 'unknown');
  action_name := lower(tg_op);
  if tg_op = 'UPDATE' and to_jsonb(old)->>'status' = 'deleted'
      and to_jsonb(new)->>'status' <> 'deleted' then
    action_name := 'restore';
  end if;
  insert into public.audit_logs(table_name, record_id, action, changed_by, old_data, new_data)
  values (tg_table_name, rid, action_name, auth.uid(),
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end);
  return coalesce(new, old);
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['member_types','members','member_field_definitions','events'] loop
    execute format('drop trigger if exists %I_touch on public.%I', t, t);
    execute format('create trigger %I_touch before update on public.%I for each row execute function public.touch_audit_fields()', t, t);
    execute format('drop trigger if exists %I_audit on public.%I', t, t);
    execute format('create trigger %I_audit after insert or update or delete on public.%I for each row execute function public.write_audit_log()', t, t);
  end loop;
end $$;

drop trigger if exists attendance_audit on public.attendance;
create trigger attendance_audit after insert or update or delete on public.attendance
for each row execute function public.write_audit_log();

create table if not exists public.event_participants (
  event_id bigint not null references public.events(id) on delete cascade,
  member_id bigint not null references public.members(id),
  member_type_id bigint not null references public.member_types(id),
  snapshot_name text not null,
  snapshot_user_id varchar(10) not null,
  created_at timestamptz not null default now(),
  primary key(event_id, member_id)
);

alter table public.event_participants enable row level security;
drop policy if exists event_participants_admin_only on public.event_participants;
create policy event_participants_admin_only on public.event_participants for all
using (public.is_admin()) with check (public.is_admin());

create or replace function public.create_member(
  p_member_type_id bigint, p_name text, p_nik text default null,
  p_email text default null, p_phone text default null,
  p_status text default 'active', p_role text default 'member',
  p_photo_path text default null, p_custom_values jsonb default '{}'::jsonb
) returns public.members
language plpgsql security invoker set search_path = public
as $$
declare
  next_id bigint;
  code char(1);
  uid varchar(10);
  result public.members;
  field record;
begin
  if not public.is_admin() then raise exception 'Unauthorized'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Nama wajib diisi'; end if;
  select type_code into code from public.member_types where id=p_member_type_id and is_active;
  if code is null then raise exception 'Tipe member tidak valid'; end if;
  next_id := nextval(pg_get_serial_sequence('public.members','id'));
  if next_id > 99999 then raise exception 'ID member melewati batas 99999'; end if;
  uid := code || lpad(next_id::text,5,'0') || to_char(current_date,'DDMM');
  insert into public.members(id, role, member_type_id, user_id, barcode_value,
    name, nik, email, phone, photo_path, status)
  values(next_id, p_role, p_member_type_id, uid,
    'MYMEMBER:MEMBER:'||uid||':v1', trim(p_name), nullif(trim(p_nik),''),
    nullif(trim(p_email),''), nullif(trim(p_phone),''), p_photo_path, p_status)
  returning * into result;

  for field in select id, is_required from public.member_field_definitions where is_active loop
    if field.is_required and nullif(p_custom_values->>field.id::text,'') is null then
      raise exception 'Custom field wajib belum diisi';
    end if;
    if p_custom_values ? field.id::text then
      insert into public.member_field_values(member_id,field_definition_id,value)
      values(next_id,field.id,p_custom_values->>field.id::text);
    end if;
  end loop;
  return result;
end;
$$;

create or replace function public.refresh_event_participants(p_event_id bigint)
returns integer language plpgsql security invoker set search_path = public
as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'Unauthorized'; end if;
  if exists(select 1 from public.attendance where event_id=p_event_id and status='present') then
    raise exception 'Peserta tidak bisa diubah setelah presensi dimulai';
  end if;
  delete from public.event_participants where event_id=p_event_id;
  insert into public.event_participants(event_id,member_id,member_type_id,snapshot_name,snapshot_user_id)
  select p_event_id,m.id,m.member_type_id,m.name,m.user_id from public.members m
  join public.event_member_types emt on emt.member_type_id=m.member_type_id and emt.event_id=p_event_id
  where m.status='active';
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.check_in_member(p_event_id bigint, p_barcode text)
returns jsonb language plpgsql security invoker set search_path = public
as $$
declare m public.members; a public.attendance;
begin
  if not public.is_admin() then raise exception 'Unauthorized'; end if;
  select * into m from public.members where barcode_value=p_barcode;
  if m.id is null then raise exception 'Barcode/member tidak ditemukan'; end if;
  if m.status <> 'active' then raise exception 'Member tidak aktif'; end if;
  if not exists(select 1 from public.event_participants where event_id=p_event_id and member_id=m.id) then
    raise exception 'Member tidak eligible untuk event ini';
  end if;
  insert into public.attendance(event_id,member_id,status)
  values(p_event_id,m.id,'present')
  on conflict(event_id,member_id) do update set status='present', checked_in_at=now(), checked_in_by=auth.uid()
  where attendance.status='cancelled'
  returning * into a;
  if a.id is null then raise exception 'Member sudah tercatat hadir'; end if;
  return jsonb_build_object('member_id',m.id,'name',m.name,'user_id',m.user_id,'checked_in_at',a.checked_in_at);
end;
$$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('member-photos','member-photos',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,
allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists member_photos_admin_select on storage.objects;
drop policy if exists member_photos_admin_insert on storage.objects;
drop policy if exists member_photos_admin_update on storage.objects;
drop policy if exists member_photos_admin_delete on storage.objects;
create policy member_photos_admin_select on storage.objects for select to authenticated
using(bucket_id='member-photos' and public.is_admin());
create policy member_photos_admin_insert on storage.objects for insert to authenticated
with check(bucket_id='member-photos' and public.is_admin());
create policy member_photos_admin_update on storage.objects for update to authenticated
using(bucket_id='member-photos' and public.is_admin()) with check(bucket_id='member-photos' and public.is_admin());
create policy member_photos_admin_delete on storage.objects for delete to authenticated
using(bucket_id='member-photos' and public.is_admin());

insert into public.member_types(name,type_code,user_input)
select 'Regular','1',id from public.profiles order by time_input limit 1
on conflict(name) do nothing;

grant select,insert,update,delete on all tables in schema public to authenticated;
grant usage,select on all sequences in schema public to authenticated;
grant execute on function public.create_member(bigint,text,text,text,text,text,text,text,jsonb) to authenticated;
grant execute on function public.refresh_event_participants(bigint) to authenticated;
grant execute on function public.check_in_member(bigint,text) to authenticated;
