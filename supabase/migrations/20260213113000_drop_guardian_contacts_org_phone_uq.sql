do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'guardian_contacts_org_phone_uq'
  ) then
    alter table public.guardian_contacts
      drop constraint guardian_contacts_org_phone_uq;
  end if;

  if exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'guardian_contacts_org_phone_uq'
  ) then
    drop index public.guardian_contacts_org_phone_uq;
  end if;
end $$;
