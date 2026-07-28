-- Allow public signup only until the first administrator has been claimed.
create or replace function public.hook_restrict_signup(event jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if public.has_admin() then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Pembuatan akun baru sudah ditutup'
    ));
  end if;
  return '{}'::jsonb;
end;
$$;

grant execute on function public.hook_restrict_signup(jsonb) to supabase_auth_admin;
revoke execute on function public.hook_restrict_signup(jsonb) from anon, authenticated, public;
grant usage on schema public to supabase_auth_admin;
