create or replace function public.hook_restrict_signup(event jsonb)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  -- Touch the hook payload so schema lint can verify the expected signature.
  if event is null then
    raise exception 'Invalid auth hook payload';
  end if;
  if public.has_admin() then
    return jsonb_build_object('error', jsonb_build_object(
      'http_code', 403,
      'message', 'Pembuatan akun baru sudah ditutup'
    ));
  end if;
  return '{}'::jsonb;
end;
$$;
