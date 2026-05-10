-- PostgREST embeds used by the API require FK relationships from
-- athletes/coaches.user_id to profiles.user_id.
--
-- Use NOT VALID so this can be applied to restored historical data even if
-- some auth/profile rows are missing. New/updated rows are still checked.

update public.profiles
set user_id = id
where user_id is null;

create unique index if not exists profiles_user_id_unique
  on public.profiles (user_id);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'athletes_user_id_profiles_user_id_fkey'
  ) then
    alter table public.athletes
      add constraint athletes_user_id_profiles_user_id_fkey
      foreign key (user_id)
      references public.profiles (user_id)
      on delete set null
      not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'coaches_user_id_profiles_user_id_fkey'
  ) then
    alter table public.coaches
      add constraint coaches_user_id_profiles_user_id_fkey
      foreign key (user_id)
      references public.profiles (user_id)
      on delete set null
      not valid;
  end if;
end $$;

notify pgrst, 'reload schema';
