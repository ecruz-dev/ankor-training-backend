drop function if exists public.create_athlete_tx(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  smallint
);

drop function if exists public.create_athlete_tx(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  smallint,
  public.lax_position[]
);

drop function if exists public.create_athlete_tx(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  smallint,
  public.lax_position[],
  uuid
);

create or replace function public.create_athlete_tx(
  p_user_id uuid,
  p_org_id uuid,
  p_team_id uuid,
  p_first_name text,
  p_last_name text,
  p_full_name text,
  p_email text,
  p_phone text,
  p_cell_number text,
  p_gender text,
  p_guardian_id uuid,
  p_guardian_user_id uuid,
  p_guardian_full_name text,
  p_guardian_email text,
  p_guardian_phone text,
  p_guardian_relationship text,
  p_graduation_year smallint
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_full_name text;
  v_athlete_id uuid;
  v_guardian_id uuid;
  v_same_email boolean;
  v_has_guardian boolean;
begin
  v_full_name := nullif(trim(coalesce(p_full_name, '')), '');
  if v_full_name is null then
    v_full_name := nullif(trim(concat_ws(' ', p_first_name, p_last_name)), '');
  end if;

  v_same_email := p_guardian_email is not null
    and p_email is not null
    and lower(p_guardian_email) = lower(p_email);

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
    case when v_same_email then p_guardian_full_name else v_full_name end,
    p_org_id,
    case
      when v_same_email then p_guardian_phone
      else coalesce(p_phone, p_cell_number)
    end,
    case when v_same_email then null else p_first_name end,
    case when v_same_email then null else p_last_name end,
    case when v_same_email then p_guardian_email else p_email end,
    case when v_same_email then 'parent' else 'athlete' end
  )
  on conflict (id) do update
    set
      full_name = excluded.full_name,
      phone = excluded.phone,
      first_name = excluded.first_name,
      last_name = excluded.last_name,
      email = excluded.email,
      role = excluded.role
    where excluded.role = 'parent';

  insert into public.org_memberships (org_id, user_id, role, is_active)
  values (p_org_id, p_user_id, 'athlete', true)
  on conflict (org_id, user_id) do update
    set role = case
      when org_memberships.role = 'parent' then org_memberships.role
      else excluded.role
    end,
    is_active = true;

  insert into public.athletes (
    org_id,
    user_id,
    first_name,
    last_name,
    full_name,
    email,
    phone,
    cell_number,
    gender,
    graduation_year
  )
  values (
    p_org_id,
    p_user_id,
    p_first_name,
    p_last_name,
    v_full_name,
    p_email,
    p_phone,
    p_cell_number,
    p_gender,
    p_graduation_year
  )
  returning id into v_athlete_id;

  insert into public.team_memberships (team_id, athlete_id, created_at)
  select p_team_id, v_athlete_id, now()
  where not exists (
    select 1
    from public.team_memberships
    where team_id = p_team_id
      and athlete_id = v_athlete_id
  );

  insert into public.team_athletes (team_id, athlete_id, status)
  values (p_team_id, v_athlete_id, 'active')
  on conflict (team_id, athlete_id) do update
    set status = excluded.status;

  v_has_guardian := p_guardian_id is not null
    or p_guardian_user_id is not null
    or p_guardian_full_name is not null
    or p_guardian_email is not null
    or p_guardian_phone is not null
    or p_guardian_relationship is not null;

  if not v_has_guardian then
    return v_athlete_id;
  end if;

  v_guardian_id := p_guardian_id;
  if v_guardian_id is null then
    if p_guardian_phone is not null then
      select id
      into v_guardian_id
      from public.guardian_contacts
      where org_id = p_org_id
        and phone = p_guardian_phone
      limit 1;
    end if;

    if v_guardian_id is null and p_guardian_email is not null then
      select id
      into v_guardian_id
      from public.guardian_contacts
      where org_id = p_org_id
        and lower(email) = lower(p_guardian_email)
      limit 1;
    end if;
  end if;

  if v_guardian_id is null then
    if p_guardian_user_id is null then
      raise exception 'guardian user id is required';
    end if;

    insert into public.profiles (
      id,
      user_id,
      full_name,
      default_org_id,
      phone,
      email,
      role
    )
    values (
      p_guardian_user_id,
      p_guardian_user_id,
      p_guardian_full_name,
      p_org_id,
      p_guardian_phone,
      p_guardian_email,
      'parent'
    )
    on conflict (id) do nothing;

    if p_guardian_user_id <> p_user_id then
      insert into public.org_memberships (org_id, user_id, role, is_active)
      values (p_org_id, p_guardian_user_id, 'parent', true)
      on conflict (org_id, user_id) do update
        set role = excluded.role,
            is_active = true;
    end if;

    insert into public.guardian_contacts (
      org_id,
      user_id,
      full_name,
      email,
      phone
    )
    values (
      p_org_id,
      p_guardian_user_id,
      p_guardian_full_name,
      p_guardian_email,
      p_guardian_phone
    )
    returning id into v_guardian_id;
  end if;

  insert into public.athlete_guardians (athlete_id, guardian_id, relationship)
  values (v_athlete_id, v_guardian_id, p_guardian_relationship)
  on conflict (athlete_id, guardian_id) do update
    set relationship = excluded.relationship;

  return v_athlete_id;
end;
$$;
