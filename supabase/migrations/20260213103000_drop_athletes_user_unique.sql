do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'athletes_user_unique'
  ) then
    alter table public.athletes
      drop constraint athletes_user_unique;
  end if;

  if exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'athletes_user_unique'
  ) then
    drop index public.athletes_user_unique;
  end if;
end $$;
