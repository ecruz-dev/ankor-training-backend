do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'coaches_user_id_profiles_user_id_fkey'
  ) then
    alter table public.coaches
      add constraint coaches_user_id_profiles_user_id_fkey
      foreign key (user_id)
      references public.profiles (user_id)
      on delete set null;
  end if;
end $$;
