do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'org_memberships_role_check'
  ) then
    alter table public.org_memberships
      drop constraint org_memberships_role_check;
  end if;

  alter table public.org_memberships
    add constraint org_memberships_role_check
    check (
      role = any (
        array[
          'owner'::text,
          'admin'::text,
          'coach'::text,
          'athlete'::text,
          'parent'::text
        ]
      )
    );
end $$;
