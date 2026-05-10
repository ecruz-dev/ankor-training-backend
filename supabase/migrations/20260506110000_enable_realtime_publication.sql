-- Enable Supabase Realtime Postgres Changes for application tables.
--
-- This adds selected public tables to the supabase_realtime publication.
-- RLS is intentionally not changed here; add table-specific RLS policies before
-- exposing these channels directly to untrusted clients.

do $$
declare
  v_table_name text;
  realtime_tables text[] := array[
    'notifications',
    'evaluations',
    'evaluation_items',
    'evaluation_workout_progress',
    'evaluation_workout_drills',
    'practice_plans',
    'practice_plan_items',
    'practice_plan_members',
    'practice_plan_invitations',
    'athletes',
    'coaches',
    'teams',
    'team_athletes',
    'guardian_contacts',
    'athlete_guardians',
    'drills',
    'drill_media',
    'skills',
    'skill_media',
    'scorecard_templates',
    'scorecard_categories',
    'scorecard_subskills',
    'join_codes'
  ];
begin
  if not exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    create publication supabase_realtime;
  end if;

  foreach v_table_name in array realtime_tables
  loop
    if exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = v_table_name
    ) and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = v_table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', v_table_name);
    end if;

    if exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = v_table_name
    ) then
      execute format('alter table public.%I replica identity full', v_table_name);
    end if;
  end loop;
end $$;
