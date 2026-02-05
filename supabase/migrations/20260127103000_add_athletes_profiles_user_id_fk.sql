-- Link athletes.user_id to profiles.user_id for PostgREST embeds.
-- Also backfill profiles.user_id to match profiles.id for existing rows.

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
      on delete set null;
  end if;
end $$;
