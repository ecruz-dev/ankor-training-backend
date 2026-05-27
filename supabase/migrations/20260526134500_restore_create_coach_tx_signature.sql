drop function if exists public.create_coach_tx(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text
);

create or replace function public.create_coach_tx(
  p_user_id uuid,
  p_org_id uuid,
  p_first_name text,
  p_last_name text,
  p_full_name text,
  p_email text,
  p_phone text,
  p_cell_number text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text;
  v_coach_id uuid;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;
  if p_org_id is null then
    raise exception 'p_org_id is required';
  end if;

  v_full_name := nullif(trim(coalesce(p_full_name, '')), '');
  if v_full_name is null then
    v_full_name := nullif(trim(concat_ws(' ', p_first_name, p_last_name)), '');
  end if;

  insert into public.profiles (
    id,
    user_id,
    full_name,
    default_org_id,
    phone,
    first_name,
    last_name,
    email,
    role
  )
  values (
    p_user_id,
    p_user_id,
    v_full_name,
    p_org_id,
    coalesce(nullif(trim(p_phone), ''), nullif(trim(p_cell_number), '')),
    nullif(trim(p_first_name), ''),
    nullif(trim(p_last_name), ''),
    nullif(trim(p_email), ''),
    'coach'
  )
  on conflict (id) do update
    set
      full_name = excluded.full_name,
      default_org_id = excluded.default_org_id,
      phone = excluded.phone,
      first_name = excluded.first_name,
      last_name = excluded.last_name,
      email = excluded.email,
      role = excluded.role;

  update public.org_memberships om
  set role = 'coach',
      is_active = true
  where om.org_id = p_org_id
    and om.user_id = p_user_id;

  if not found then
    insert into public.org_memberships (org_id, user_id, role, is_active)
    values (p_org_id, p_user_id, 'coach', true);
  end if;

  insert into public.coaches (
    org_id,
    user_id,
    full_name,
    email,
    phone,
    cell_number
  )
  values (
    p_org_id,
    p_user_id,
    v_full_name,
    nullif(trim(p_email), ''),
    nullif(trim(p_phone), ''),
    nullif(trim(p_cell_number), '')
  )
  returning id into v_coach_id;

  return v_coach_id;
end;
$$;

notify pgrst, 'reload schema';
