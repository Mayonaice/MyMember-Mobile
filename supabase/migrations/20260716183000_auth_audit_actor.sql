create or replace function public.write_audit_log()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  rid text;
  action_name text;
  actor uuid;
begin
  rid := coalesce(to_jsonb(new)->>'id', to_jsonb(old)->>'id',
    to_jsonb(new)->>'member_id', to_jsonb(old)->>'member_id',
    to_jsonb(new)->>'event_id', to_jsonb(old)->>'event_id', 'unknown');
  action_name := lower(tg_op);
  if tg_op = 'UPDATE' and to_jsonb(old)->>'status' = 'deleted'
      and to_jsonb(new)->>'status' <> 'deleted' then
    action_name := 'restore';
  end if;
  actor := coalesce(
    auth.uid(),
    nullif(to_jsonb(new)->>'user_input','')::uuid,
    nullif(to_jsonb(old)->>'user_input','')::uuid
  );
  if actor is not null then
    insert into public.audit_logs(table_name, record_id, action, changed_by, old_data, new_data)
    values (tg_table_name, rid, action_name, actor,
      case when tg_op = 'INSERT' then null else to_jsonb(old) end,
      case when tg_op = 'DELETE' then null else to_jsonb(new) end);
  end if;
  return coalesce(new, old);
end;
$$;
