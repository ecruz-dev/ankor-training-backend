create or replace function public.signup_register_org_tx(
  p_user_id uuid,
  p_first_name text,
  p_last_name text,
  p_email text,
  p_phone text,
  p_org_name text,
  p_program_gender text,
  p_team_names text[]
) returns table (
  org_id uuid,
  profile_id uuid,
  team_ids uuid[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_team_ids uuid[] := '{}';
  v_base text;
  v_slug text;
  v_i integer := 2;
  v_full_name text;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required';
  end if;
  if coalesce(trim(p_org_name), '') = '' then
    raise exception 'Organization name is required';
  end if;
  if p_program_gender not in ('girls','boys','coed') then
    raise exception 'program_gender must be one of girls|boys|coed';
  end if;

  v_base := slugify(p_org_name);
  v_slug := v_base;
  while exists (select 1 from public.organizations where slug = v_slug) loop
    v_slug := v_base || '-' || v_i;
    v_i := v_i + 1;
  end loop;

  insert into organizations(name, program_gender, slug)
  values (trim(p_org_name), p_program_gender, v_slug)
  returning id into v_org_id;

  v_full_name := nullif(trim(concat_ws(' ', p_first_name, p_last_name)), '');

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
    v_org_id,
    nullif(trim(p_phone), ''),
    nullif(trim(p_first_name), ''),
    nullif(trim(p_last_name), ''),
    nullif(trim(p_email), ''),
    'admin'
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

  profile_id := p_user_id;

  if p_team_names is not null then
    with cleaned as (
      select distinct on (trim(t)) trim(t) as team_name
      from unnest(p_team_names) as t
      where coalesce(trim(t), '') <> ''
    ), ins as (
      insert into teams (org_id, name)
      select v_org_id, c.team_name from cleaned c
      returning id
    )
    select coalesce(array_agg(id), '{}') into v_team_ids from ins;
  end if;

  org_id := v_org_id;
  team_ids := v_team_ids;
  return next;
end;
$$;
