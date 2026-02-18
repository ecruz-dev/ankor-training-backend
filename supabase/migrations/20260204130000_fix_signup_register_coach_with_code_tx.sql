drop function if exists public.signup_register_coach_with_code_tx(
  uuid,
  text,
  text,
  text,
  text,
  text,
  boolean
);

create or replace function public.signup_register_coach_with_code_tx(
  p_user_id uuid,
  p_code text,
  p_first_name text,
  p_last_name text,
  p_email text,
  p_cell_number text,
  p_terms_accepted boolean
) returns table (
  org_id uuid,
  team_id uuid,
  coach_id uuid,
  profile_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_profile_id     uuid;
  v_coach_id       uuid;
  v_org_id         uuid;
  v_team_id        uuid;
  v_has_uses_count boolean := false;
begin
  -- Validate
  if p_first_name is null or btrim(p_first_name) = '' then
    raise exception 'FIRST_NAME_REQUIRED' using errcode='P0001';
  end if;
  if p_last_name is null or btrim(p_last_name) = '' then
    raise exception 'LAST_NAME_REQUIRED' using errcode='P0001';
  end if;
  if p_email is null or position('@' in p_email) = 0 then
    raise exception 'EMAIL_REQUIRED' using errcode='P0001';
  end if;
  if not p_terms_accepted then
    raise exception 'TERMS_REQUIRED' using errcode='P0001';
  end if;

  -- Resolve join code -> org/team
  select jc.org_id, jc.team_id
    into v_org_id, v_team_id
  from public.join_codes as jc
  where jc.code::text = p_code
  for update;
  if not found then
    raise exception 'INVALID_JOIN_CODE' using errcode='P0001';
  end if;

  -- profiles (upsert)
  insert into public.profiles as pr
      (id,        user_id,   first_name,          last_name,          full_name,                              default_org_id, email,         phone,                             role,     terms_accepted, terms_accepted_at)
  values
      (p_user_id, p_user_id, btrim(p_first_name), btrim(p_last_name), btrim(p_first_name||' '||p_last_name), v_org_id,        lower(p_email), nullif(btrim(p_cell_number), ''), 'coach', p_terms_accepted, case when p_terms_accepted then now() else null end)
  on conflict (id) do update
    set first_name        = excluded.first_name,
        last_name         = excluded.last_name,
        full_name         = excluded.full_name,
        email             = excluded.email,
        phone             = excluded.phone,
        role              = 'coach',
        user_id           = excluded.user_id,
        terms_accepted    = excluded.terms_accepted,
        terms_accepted_at = excluded.terms_accepted_at
  returning pr.id into v_profile_id;

  -- org membership
  insert into public.org_memberships (org_id, user_id, role, is_active)
  values (v_org_id, p_user_id, 'coach', true)
  on conflict (org_id, user_id) do update
    set role = excluded.role,
        is_active = true;

  -- coaches: update existing row if present, otherwise insert
  select c.id
    into v_coach_id
  from public.coaches as c
  where c.org_id = v_org_id
    and c.user_id = p_user_id
  limit 1;

  if v_coach_id is null then
    insert into public.coaches as c
        (org_id,
         user_id,
         full_name,
         email,
         phone,
         cell_number)
    values
        (v_org_id,
         p_user_id,
         btrim(p_first_name || ' ' || p_last_name),
         lower(p_email),
         nullif(btrim(p_cell_number), ''),
         nullif(btrim(p_cell_number), ''))
    returning c.id into v_coach_id;
  else
    update public.coaches as c
      set org_id      = v_org_id,
          full_name   = btrim(p_first_name || ' ' || p_last_name),
          email       = lower(p_email),
          phone       = nullif(btrim(p_cell_number), ''),
          cell_number = nullif(btrim(p_cell_number), '')
    where c.id = v_coach_id;
  end if;

  -- team membership for coach (link coach to chosen team)
  if v_team_id is not null then
    update public.team_memberships as tm
      set coach_id = v_coach_id
    where tm.team_id = v_team_id
      and tm.coach_id is null;

    insert into public.team_memberships (team_id, coach_id, created_at)
    select v_team_id, v_coach_id, now()
    where not exists (
      select 1
      from public.team_memberships
      where team_id = v_team_id
        and coach_id = v_coach_id
    );
  end if;

  -- bump uses_count if that column exists
  select exists (
    select 1
    from information_schema.columns c
    where c.table_schema='public'
      and c.table_name='join_codes'
      and c.column_name='uses_count'
  ) into v_has_uses_count;

  if v_has_uses_count then
    update public.join_codes as jc
    set uses_count = coalesce(jc.uses_count, 0) + 1
    where jc.code = p_code;
  end if;

  return query select v_org_id, v_team_id, v_coach_id, v_profile_id;
end;
$$;
