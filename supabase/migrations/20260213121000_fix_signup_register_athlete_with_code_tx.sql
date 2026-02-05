drop function if exists public.signup_register_athlete_with_code_tx(
  uuid,
  uuid,
  text,
  text,
  text,
  smallint,
  text,
  text[],
  boolean
);

create or replace function public.signup_register_athlete_with_code_tx(
  p_user_id uuid,
  p_code text,
  p_first_name text,
  p_last_name text,
  p_email text,
  p_graduation_year integer,
  p_cell_number text,
  p_positions public.lax_position[],
  p_terms_accepted boolean
) returns table (
  org_id uuid,
  team_id uuid,
  athlete_id uuid,
  profile_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id     uuid;
  v_athlete_id     uuid;
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
  if p_graduation_year is null then
    raise exception 'GRADUATION_YEAR_REQUIRED' using errcode='P0001';
  end if;
  if p_positions is null or array_length(p_positions, 1) is null then
    raise exception 'POSITION_REQUIRED' using errcode='P0001';
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
      (id,        user_id,   first_name,          last_name,          full_name,                              email,         phone,                             role,      terms_accepted, terms_accepted_at)
  values
      (p_user_id, p_user_id, btrim(p_first_name), btrim(p_last_name), btrim(p_first_name||' '||p_last_name), lower(p_email), nullif(btrim(p_cell_number), ''), 'athlete', p_terms_accepted, case when p_terms_accepted then now() else null end)
  on conflict (id) do update
    set first_name        = excluded.first_name,
        last_name         = excluded.last_name,
        full_name         = excluded.full_name,
        email             = excluded.email,
        phone             = excluded.phone,
        role              = 'athlete',
        user_id           = excluded.user_id,
        terms_accepted    = excluded.terms_accepted,
        terms_accepted_at = excluded.terms_accepted_at
  returning pr.id into v_profile_id;

  -- athletes: update existing row if present, otherwise insert
  select a.id
    into v_athlete_id
  from public.athletes as a
  where a.org_id = v_org_id
    and a.user_id = p_user_id
  limit 1;

  if v_athlete_id is null then
    insert into public.athletes as a
        (org_id,
         user_id,
         graduation_year,
         cell_number,
         first_name,
         last_name,
         full_name,
         phone)
    values
        (v_org_id,
         p_user_id,
         p_graduation_year,
         nullif(btrim(p_cell_number), ''),
         btrim(p_first_name),
         btrim(p_last_name),
         btrim(p_first_name || ' ' || p_last_name),
         nullif(btrim(p_cell_number), ''))
    returning a.id into v_athlete_id;
  else
    update public.athletes as a
      set org_id          = v_org_id,
          graduation_year = p_graduation_year,
          cell_number     = nullif(btrim(p_cell_number), ''),
          first_name      = btrim(p_first_name),
          last_name       = btrim(p_last_name),
          full_name       = btrim(p_first_name || ' ' || p_last_name),
          phone           = nullif(btrim(p_cell_number), '')
    where a.id = v_athlete_id;
  end if;

  -- positions: delete/insert with explicit aliasing
  delete from public.athlete_positions as ap
  where ap.athlete_id = v_athlete_id;

  with pos as (
    select unnest(p_positions) as position
  )
  insert into public.athlete_positions (athlete_id, position)
  select v_athlete_id, pos.position
  from pos;

  -- team membership (keep team_memberships AND add team_athletes)
  if v_team_id is not null then
    insert into public.team_memberships (team_id, athlete_id, created_at)
    select v_team_id, v_athlete_id, now()
    where not exists (
      select 1
      from public.team_memberships as tm
      where tm.team_id = v_team_id
        and tm.athlete_id = v_athlete_id
    );

    insert into public.team_athletes (team_id, athlete_id, status)
    values (v_team_id, v_athlete_id, 'active')
    on conflict do nothing;
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

  return query select v_org_id, v_team_id, v_athlete_id, v_profile_id;
end;
$$;
