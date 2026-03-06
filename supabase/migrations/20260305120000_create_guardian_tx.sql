create or replace function public.create_guardian_tx(
  p_user_id uuid,
  p_org_id uuid,
  p_athlete_ids uuid[],
  p_full_name text,
  p_email text,
  p_phone text,
  p_address_line1 text,
  p_address_line2 text,
  p_city text,
  p_region text,
  p_postal_code text,
  p_country text,
  p_relationship text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_guardian_id uuid;
begin
  insert into public.guardian_contacts (
    org_id,
    user_id,
    full_name,
    email,
    phone,
    address_line1,
    address_line2,
    city,
    region,
    postal_code,
    country
  )
  values (
    p_org_id,
    p_user_id,
    p_full_name,
    p_email,
    p_phone,
    p_address_line1,
    p_address_line2,
    p_city,
    p_region,
    p_postal_code,
    p_country
  )
  returning id into v_guardian_id;

  insert into public.org_memberships (org_id, user_id, role, is_active)
  values (p_org_id, p_user_id, 'parent', true)
  on conflict (org_id, user_id) do update
    set role = excluded.role,
        is_active = true;

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
    p_user_id,
    p_user_id,
    p_full_name,
    p_org_id,
    p_phone,
    p_email,
    'parent'
  );

  insert into public.athlete_guardians (athlete_id, guardian_id, relationship)
  select distinct unnest(p_athlete_ids), v_guardian_id, p_relationship
  on conflict (athlete_id, guardian_id) do update
    set relationship = excluded.relationship;

  return v_guardian_id;
end;
$$;
