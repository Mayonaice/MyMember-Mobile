-- Complete audit metadata and seed the default member type when the first admin is created.

create or replace function public.handle_first_admin()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform pg_advisory_xact_lock(73012026);
  if not exists (select 1 from public.profiles) then
    insert into public.profiles(id, role, user_input)
    values (new.id, 'admin', new.id);
    insert into public.member_types(name, type_code, user_input)
    values ('Regular', '1', new.id)
    on conflict(name) do nothing;
  end if;
  return new;
end;
$$;

alter table public.member_field_values
  add column if not exists user_input uuid default auth.uid(),
  add column if not exists time_input timestamptz not null default now(),
  add column if not exists user_edit uuid,
  add column if not exists time_edit timestamptz;

alter table public.event_member_types
  add column if not exists user_input uuid default auth.uid(),
  add column if not exists time_input timestamptz not null default now(),
  add column if not exists user_edit uuid,
  add column if not exists time_edit timestamptz;

alter table public.event_participants
  add column if not exists user_input uuid default auth.uid(),
  add column if not exists time_input timestamptz not null default now(),
  add column if not exists user_edit uuid,
  add column if not exists time_edit timestamptz;

alter table public.attendance
  add column if not exists user_input uuid default auth.uid(),
  add column if not exists time_input timestamptz not null default now(),
  add column if not exists user_edit uuid,
  add column if not exists time_edit timestamptz;

do $$
declare t text;
begin
  foreach t in array array['member_field_values','event_member_types','event_participants','attendance'] loop
    execute format('drop trigger if exists %I_touch on public.%I', t, t);
    execute format('create trigger %I_touch before update on public.%I for each row execute function public.touch_audit_fields()', t, t);
  end loop;
end $$;

drop trigger if exists member_field_values_audit on public.member_field_values;
create trigger member_field_values_audit after insert or update or delete on public.member_field_values
for each row execute function public.write_audit_log();
drop trigger if exists event_member_types_audit on public.event_member_types;
create trigger event_member_types_audit after insert or update or delete on public.event_member_types
for each row execute function public.write_audit_log();

