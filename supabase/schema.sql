create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.slugify(value text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(lower(coalesce(value, '')), '[^a-z0-9]+', '-', 'g'));
$$;

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'lax_position'
  ) then
    create type public.lax_position as enum (
      'attack',
      'midfield',
      'defense',
      'goalie',
      'draw',
      'faceoff',
      'lsm',
      'fogo'
    );
  end if;
end $$;

create table if not exists public.sports (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.positions (
  id uuid primary key default gen_random_uuid(),
  sport_id uuid not null references public.sports(id) on delete cascade,
  code text not null,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sport_id, code)
);

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  sport_mode text null,
  program_gender text not null default 'coed' check (program_gender in ('girls', 'boys', 'coed')),
  "maxBelowThresholdRatingsAllowed" integer null,
  "maxWorkoutReps" integer null,
  sport_id uuid null references public.sports(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key,
  full_name text null,
  default_org_id uuid null references public.organizations(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  phone text null,
  terms_accepted boolean null default false,
  terms_accepted_at timestamptz null,
  first_name text null,
  last_name text null,
  email text null,
  role text null,
  user_id uuid null
);

create unique index if not exists profiles_user_id_unique
  on public.profiles(user_id);

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.users (
  id uuid primary key,
  email text null,
  full_name text null,
  role_id uuid null references public.roles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.org_memberships (
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null,
  role text not null check (role in ('owner', 'admin', 'coach', 'athlete', 'parent', 'staff', 'viewer')),
  is_active boolean not null default true,
  primary key (org_id, user_id)
);

create table if not exists public.org_members (
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null,
  role text not null,
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

create table if not exists public.coaches (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid null,
  sport_id uuid null references public.sports(id),
  full_name text null,
  email text null,
  phone text null,
  title text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cell_number text null
);

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  sport_id uuid null references public.sports(id),
  name text not null,
  is_active boolean not null default true,
  coach_id uuid null references public.coaches(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.athletes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid null,
  sport_id uuid null references public.sports(id),
  primary_position_id uuid null references public.positions(id) on delete set null,
  jersey_number text null,
  dominant_hand text null,
  height_cm integer null,
  weight_kg integer null,
  graduation_year integer null,
  school text null,
  birthdate date null,
  notes text null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cell_number text null,
  first_name text null,
  last_name text null,
  full_name text null,
  phone text null,
  email text null,
  gender text null
);

create table if not exists public.team_athletes (
  team_id uuid not null references public.teams(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  primary key (team_id, athlete_id)
);

create table if not exists public.team_memberships (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  athlete_id uuid null references public.athletes(id) on delete cascade,
  coach_id uuid null references public.coaches(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.athlete_positions (
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  position text null,
  position_id uuid null,
  primary key (athlete_id, position_id)
);

create table if not exists public.guardian_contacts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid null,
  full_name text null,
  email text null,
  phone text null,
  address_line1 text null,
  address_line2 text null,
  city text null,
  region text null,
  postal_code text null,
  country text null,
  is_verified boolean not null default false,
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.athlete_guardians (
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  guardian_id uuid not null references public.guardian_contacts(id) on delete cascade,
  relationship text null,
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (athlete_id, guardian_id)
);

create table if not exists public.join_codes (
  code text primary key,
  org_id uuid not null references public.organizations(id) on delete cascade,
  team_id uuid null references public.teams(id) on delete set null,
  max_uses integer not null default 1,
  used_count integer not null default 0,
  expires_at timestamptz null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  uses_count integer not null default 0,
  disabled boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.skills (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  sport_id uuid null references public.sports(id),
  category text null,
  title text not null,
  description text null,
  level text null,
  coaching_points text null,
  visibility text null default 'private',
  status text null default 'active',
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.skill_media (
  id uuid primary key default gen_random_uuid(),
  skill_id uuid not null references public.skills(id) on delete cascade,
  media_type text not null default 'video',
  title text null,
  url text not null,
  storage_path text null,
  thumbnail_url text null,
  sort_order integer null,
  created_at timestamptz not null default now()
);

create table if not exists public.skill_video_map (
  skill_id uuid not null references public.skills(id) on delete cascade,
  bucket text not null,
  object_path text not null,
  title text null,
  description text null,
  thumbnail_url text null,
  position integer null,
  created_at timestamptz not null default now(),
  primary key (skill_id, bucket, object_path)
);

create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null
);

create table if not exists public.skill_tags (
  skill_id uuid not null references public.skills(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  primary key (skill_id, tag_id)
);

create table if not exists public.skill_positions (
  skill_id uuid not null references public.skills(id) on delete cascade,
  position_id uuid not null references public.positions(id) on delete cascade,
  primary key (skill_id, position_id)
);

create table if not exists public.segments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid null references public.organizations(id) on delete cascade,
  name text not null,
  description text null,
  position integer null,
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.drills (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  segment_id uuid null references public.segments(id) on delete set null,
  sport_id uuid null references public.sports(id),
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  name text not null,
  description text null,
  objective text null,
  coaching_points text null,
  min_players integer null,
  max_players integer null,
  duration_min integer null,
  level text null,
  visibility text null default 'private',
  is_archived boolean not null default false,
  search_tsv tsvector null,
  min_age integer null,
  max_age integer null
);

create table if not exists public.drill_media (
  id uuid primary key default gen_random_uuid(),
  drill_id uuid not null references public.drills(id) on delete cascade,
  media_type text not null default 'video',
  title text null,
  url text not null,
  storage_path text null,
  thumbnail_url text null,
  sort_order integer null,
  created_at timestamptz not null default now()
);

create table if not exists public.drill_tags (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  sport_id uuid null references public.sports(id),
  name text not null,
  created_at timestamptz not null default now(),
  unique (org_id, name)
);

create table if not exists public.drill_tag_map (
  drill_id uuid not null references public.drills(id) on delete cascade,
  tag_id uuid not null references public.drill_tags(id) on delete cascade,
  primary key (drill_id, tag_id)
);

create table if not exists public.drill_steps (
  id uuid primary key default gen_random_uuid(),
  drill_id uuid not null references public.drills(id) on delete cascade,
  position integer null,
  title text null,
  instruction text null,
  duration_sec integer null,
  created_at timestamptz not null default now()
);

create table if not exists public.drill_skills (
  drill_id uuid not null references public.drills(id) on delete cascade,
  skill_id uuid not null references public.skills(id) on delete cascade,
  primary key (drill_id, skill_id)
);

create table if not exists public.scorecard_templates (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  sport_id uuid null references public.sports(id),
  name text not null,
  description text null,
  is_active boolean not null default true,
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.scorecard_categories (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.scorecard_templates(id) on delete cascade,
  name text not null,
  position integer not null default 0,
  description text null,
  created_at timestamptz not null default now()
);

create table if not exists public.scorecard_subskills (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.scorecard_categories(id) on delete cascade,
  name text not null,
  description text null,
  position integer not null default 0,
  rating_min integer null default 1,
  rating_max integer null default 5,
  skill_id uuid null references public.skills(id) on delete set null,
  priority integer null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subskill_skill_links (
  subskill_id uuid not null references public.scorecard_subskills(id) on delete cascade,
  skill_id uuid not null references public.skills(id) on delete cascade,
  priority integer null,
  primary key (subskill_id, skill_id)
);

create table if not exists public.drill_subskills (
  drill_id uuid not null references public.drills(id) on delete cascade,
  subskill_id uuid not null references public.scorecard_subskills(id) on delete cascade,
  weight numeric null,
  primary key (drill_id, subskill_id)
);

create table if not exists public.skill_drill_map (
  org_id uuid not null references public.organizations(id) on delete cascade,
  skill_id uuid not null references public.skills(id) on delete cascade,
  drill_id uuid not null references public.drills(id) on delete cascade,
  level integer null,
  created_at timestamptz not null default now(),
  primary key (skill_id, drill_id)
);

create table if not exists public.evaluations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  sport_id uuid null references public.sports(id),
  template_id uuid null references public.scorecard_templates(id) on delete set null,
  teams_id uuid null references public.teams(id) on delete set null,
  coach_id uuid null references public.coaches(id) on delete set null,
  notes text null,
  created_at timestamptz not null default now(),
  status text not null default 'not_started'
);

create table if not exists public.evaluation_items (
  id uuid primary key default gen_random_uuid(),
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  subskill_id uuid not null references public.skills(id) on delete cascade,
  rating numeric null,
  comment text null,
  recommended_skill_id uuid null references public.skills(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.athlete_evaluation_results (
  id uuid primary key default gen_random_uuid(),
  evaluation_id uuid null references public.evaluations(id) on delete cascade,
  org_id uuid null references public.organizations(id) on delete cascade,
  athlete_id uuid null references public.athletes(id) on delete cascade,
  scorecard_template_id uuid null references public.scorecard_templates(id) on delete set null,
  coach_id uuid null references public.coaches(id) on delete set null,
  evaluated_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.athlete_evaluation_result_items (
  id uuid primary key default gen_random_uuid(),
  result_id uuid references public.athlete_evaluation_results(id) on delete cascade,
  org_id uuid null references public.organizations(id) on delete cascade,
  skill_id uuid null references public.skills(id) on delete set null,
  rating numeric null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.evaluation_workout_progress (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  progress integer null default 0,
  level integer null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, evaluation_id, athlete_id)
);

create table if not exists public.evaluation_workout_drills (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  evaluation_id uuid not null references public.evaluations(id) on delete cascade,
  athlete_id uuid not null references public.athletes(id) on delete cascade,
  skill_id uuid null,
  drill_id uuid null references public.drills(id) on delete cascade,
  rate numeric null,
  level integer null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.practice_plans (
  id uuid primary key default gen_random_uuid(),
  org_id uuid null references public.organizations(id) on delete cascade,
  owner_user_id uuid not null,
  name text not null,
  description text null,
  visibility text not null default 'private',
  status text not null default 'draft',
  tags jsonb not null default '[]'::jsonb,
  estimated_minutes integer null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  type text not null default 'custom'
);

create table if not exists public.practice_plan_items (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.practice_plans(id) on delete cascade,
  section_title text null,
  section_order integer null,
  position integer null,
  item_type text not null default 'drill',
  drill_id uuid null references public.drills(id) on delete set null,
  title text null,
  instructions text null,
  sets integer null,
  reps integer null,
  duration_seconds integer null,
  rest_seconds integer null,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  duration_min integer null
);

create table if not exists public.practice_plan_members (
  plan_id uuid not null references public.practice_plans(id) on delete cascade,
  user_id uuid not null,
  role text not null default 'viewer',
  added_by uuid null,
  created_at timestamptz not null default now(),
  primary key (plan_id, user_id)
);

create table if not exists public.practice_plan_invitations (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.practice_plans(id) on delete cascade,
  invited_by uuid not null,
  invited_email text not null,
  invited_user_id uuid null,
  role text not null default 'viewer',
  status text not null default 'pending',
  token text not null default encode(gen_random_bytes(24), 'hex'),
  expires_at timestamptz null,
  created_at timestamptz not null default now(),
  responded_at timestamptz null
);

create table if not exists public.practice_plan_assignments (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid references public.practice_plans(id) on delete cascade,
  org_id uuid references public.organizations(id) on delete cascade,
  team_id uuid references public.teams(id) on delete cascade,
  athlete_id uuid references public.athletes(id) on delete cascade,
  assigned_by uuid null,
  scheduled_for timestamptz null,
  status text null,
  notes text null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  org_id uuid null references public.organizations(id) on delete cascade,
  user_id uuid null,
  type text not null,
  evaluation_id uuid null references public.evaluations(id) on delete cascade,
  payload jsonb null,
  created_at timestamptz not null default now(),
  read_at timestamptz null
);

create table if not exists public.org_branding (
  org_id uuid primary key references public.organizations(id) on delete cascade,
  logo_url text null,
  primary_color text null,
  secondary_color text null,
  custom_domain text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recommendation_rules (
  org_id uuid not null references public.organizations(id) on delete cascade,
  sport_id uuid not null references public.sports(id) on delete cascade,
  threshold numeric not null default 3,
  primary key (org_id, sport_id)
);

create table if not exists public.video_assets (
  id uuid primary key default gen_random_uuid(),
  org_id uuid null references public.organizations(id) on delete cascade,
  sport_id uuid null references public.sports(id),
  title text not null,
  description text null,
  storage_bucket text null,
  storage_path text null,
  duration_sec integer null,
  visibility text null,
  status text null,
  created_by uuid null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.drill_media_import (
  drill_name text,
  youtube_url text,
  title text,
  sort_order integer
);

create table if not exists public.athlete_positionsbk (
  athlete_id uuid,
  position text,
  position_id uuid
);

create table if not exists public.drill_tag_map_bk (
  drill_id uuid,
  tag_id uuid
);

create table if not exists public.drill_tag_map_bk2 (
  drill_id uuid,
  tag_id uuid
);

create table if not exists public.evaluation_itemsbk27mar2026 (like public.evaluation_items including defaults);
create table if not exists public.evaluation_workout_drills_bk (like public.evaluation_workout_drills including defaults);
create table if not exists public.evaluation_workout_drillsbk27mar2026 (like public.evaluation_workout_drills including defaults);
create table if not exists public.evaluation_workout_progress_bk (like public.evaluation_workout_progress including defaults);
create table if not exists public.evaluation_workout_progressbk27mar2026 (like public.evaluation_workout_progress including defaults);
create table if not exists public.evaluationsbk27mar2026 (like public.evaluations including defaults);
create table if not exists public.drillsbk07abr2026 (like public.drills including defaults);
create table if not exists public.skill_drill_mapbk27mar2026 (like public.skill_drill_map including defaults);
create table if not exists public.skill_mediabk27mar2026 (like public.skill_media including defaults);
create table if not exists public.skill_tags27mar2026 (like public.skill_tags including defaults);
create table if not exists public.skills27mar2026 (like public.skills including defaults);
create table if not exists public.skills_27mar2026 (like public.skills including defaults);

create index if not exists idx_profiles_user_id on public.profiles(user_id);
create index if not exists idx_athletes_org_id on public.athletes(org_id);
create index if not exists idx_athletes_user_id on public.athletes(user_id);
create index if not exists idx_coaches_org_id on public.coaches(org_id);
create index if not exists idx_coaches_user_id on public.coaches(user_id);
create index if not exists idx_teams_org_id on public.teams(org_id);
create index if not exists idx_guardian_contacts_org_id on public.guardian_contacts(org_id);
create index if not exists idx_skills_org_id on public.skills(org_id);
create index if not exists idx_drills_org_id on public.drills(org_id);
create index if not exists idx_skill_drill_map_org_id on public.skill_drill_map(org_id);
create index if not exists idx_skill_drill_map_org_skill on public.skill_drill_map(org_id, skill_id);
create index if not exists idx_evaluations_org_id on public.evaluations(org_id);
create index if not exists idx_evaluation_items_evaluation_id on public.evaluation_items(evaluation_id);
create index if not exists idx_practice_plans_org_id on public.practice_plans(org_id);

drop trigger if exists set_sports_updated_at on public.sports;
create trigger set_sports_updated_at before update on public.sports for each row execute function public.set_updated_at();
drop trigger if exists set_positions_updated_at on public.positions;
create trigger set_positions_updated_at before update on public.positions for each row execute function public.set_updated_at();
drop trigger if exists set_organizations_updated_at on public.organizations;
create trigger set_organizations_updated_at before update on public.organizations for each row execute function public.set_updated_at();
drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
drop trigger if exists set_teams_updated_at on public.teams;
create trigger set_teams_updated_at before update on public.teams for each row execute function public.set_updated_at();
drop trigger if exists set_athletes_updated_at on public.athletes;
create trigger set_athletes_updated_at before update on public.athletes for each row execute function public.set_updated_at();
drop trigger if exists set_coaches_updated_at on public.coaches;
create trigger set_coaches_updated_at before update on public.coaches for each row execute function public.set_updated_at();
drop trigger if exists set_guardian_contacts_updated_at on public.guardian_contacts;
create trigger set_guardian_contacts_updated_at before update on public.guardian_contacts for each row execute function public.set_updated_at();
drop trigger if exists set_skills_updated_at on public.skills;
create trigger set_skills_updated_at before update on public.skills for each row execute function public.set_updated_at();
drop trigger if exists set_drills_updated_at on public.drills;
create trigger set_drills_updated_at before update on public.drills for each row execute function public.set_updated_at();
drop trigger if exists set_scorecard_templates_updated_at on public.scorecard_templates;
create trigger set_scorecard_templates_updated_at before update on public.scorecard_templates for each row execute function public.set_updated_at();
drop trigger if exists set_practice_plans_updated_at on public.practice_plans;
create trigger set_practice_plans_updated_at before update on public.practice_plans for each row execute function public.set_updated_at();

create or replace function public.rpc_create_drill(
  p_drill jsonb,
  p_media jsonb default '[]'::jsonb,
  p_skill_tags uuid[] default '{}'
) returns table (drill_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_drill_id uuid;
  v_duration_seconds integer;
  v_media jsonb;
  v_tag uuid;
begin
  if p_drill is null or coalesce(trim(p_drill->>'name'), '') = '' then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;

  v_duration_seconds := nullif(p_drill->>'duration_seconds', '')::integer;

  insert into public.drills (
    org_id,
    segment_id,
    sport_id,
    name,
    description,
    coaching_points,
    level,
    min_age,
    max_age,
    duration_min,
    created_by
  )
  values (
    (p_drill->>'org_id')::uuid,
    nullif(p_drill->>'segment_id', '')::uuid,
    nullif(p_drill->>'sport_id', '')::uuid,
    trim(p_drill->>'name'),
    nullif(p_drill->>'description', ''),
    nullif(p_drill->>'instructions', ''),
    nullif(p_drill->>'level', ''),
    nullif(p_drill->>'min_age', '')::integer,
    nullif(p_drill->>'max_age', '')::integer,
    case when v_duration_seconds is null then null else ceil(v_duration_seconds / 60.0)::integer end,
    nullif(p_drill->>'created_by', '')::uuid
  )
  returning id into v_drill_id;

  for v_media in select value from jsonb_array_elements(coalesce(p_media, '[]'::jsonb))
  loop
    insert into public.drill_media (
      drill_id,
      media_type,
      url,
      title,
      thumbnail_url,
      sort_order
    )
    values (
      v_drill_id,
      coalesce(nullif(v_media->>'type', ''), 'video'),
      v_media->>'url',
      nullif(v_media->>'title', ''),
      nullif(v_media->>'thumbnail_url', ''),
      nullif(v_media->>'position', '')::integer
    );
  end loop;

  foreach v_tag in array coalesce(p_skill_tags, '{}')
  loop
    insert into public.drill_tag_map (drill_id, tag_id)
    values (v_drill_id, v_tag)
    on conflict do nothing;
  end loop;

  return query select v_drill_id;
end;
$$;

create or replace function public.create_scorecard_template_tx(
  p_template jsonb,
  p_created_by uuid default null
) returns table (template_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_template_id uuid;
  v_category jsonb;
  v_subskill jsonb;
  v_category_id uuid;
begin
  if p_template is null then
    raise exception 'TEMPLATE_REQUIRED' using errcode = 'P0001';
  end if;
  if nullif(p_template->>'org_id', '') is null then
    raise exception 'ORG_REQUIRED' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_template->>'name'), '') = '' then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;
  if jsonb_typeof(coalesce(p_template->'categories', '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_template->'categories', '[]'::jsonb)) = 0 then
    raise exception 'AT_LEAST_ONE_CATEGORY_REQUIRED' using errcode = 'P0001';
  end if;

  insert into public.scorecard_templates (
    org_id,
    sport_id,
    name,
    description,
    is_active,
    created_by
  )
  values (
    (p_template->>'org_id')::uuid,
    nullif(p_template->>'sport_id', '')::uuid,
    trim(p_template->>'name'),
    nullif(p_template->>'description', ''),
    coalesce((p_template->>'isActive')::boolean, true),
    p_created_by
  )
  returning id into v_template_id;

  for v_category in select value from jsonb_array_elements(p_template->'categories')
  loop
    if jsonb_typeof(coalesce(v_category->'subskills', '[]'::jsonb)) <> 'array'
       or jsonb_array_length(coalesce(v_category->'subskills', '[]'::jsonb)) = 0 then
      raise exception 'CATEGORY_NEEDS_ONE_SUBSKILL' using errcode = 'P0001';
    end if;

    insert into public.scorecard_categories (
      template_id,
      name,
      description,
      position
    )
    values (
      v_template_id,
      trim(v_category->>'name'),
      nullif(v_category->>'description', ''),
      coalesce(nullif(v_category->>'position', '')::integer, 1)
    )
    returning id into v_category_id;

    for v_subskill in select value from jsonb_array_elements(v_category->'subskills')
    loop
      if nullif(v_subskill->>'skill_id', '') is null then
        raise exception 'SUBSKILL_SKILL_REQUIRED' using errcode = 'P0001';
      end if;

      insert into public.scorecard_subskills (
        category_id,
        name,
        description,
        position,
        skill_id,
        rating_min,
        rating_max
      )
      values (
        v_category_id,
        trim(v_subskill->>'name'),
        nullif(v_subskill->>'description', ''),
        coalesce(nullif(v_subskill->>'position', '')::integer, 1),
        (v_subskill->>'skill_id')::uuid,
        1,
        5
      );
    end loop;
  end loop;

  return query select v_template_id;
end;
$$;

create or replace function public.evaluations_bulk_create_tx(
  evaluations jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eval jsonb;
  v_item jsonb;
  v_item_id uuid;
  v_item_rating numeric;
  v_item_comment text;
  v_item_created_at timestamptz;
  v_evaluation_id uuid;
  v_result jsonb := '[]'::jsonb;
  v_items jsonb;
begin
  if evaluations is null or jsonb_typeof(evaluations) <> 'array' then
    raise exception 'EVALUATIONS_ARRAY_REQUIRED' using errcode = 'P0001';
  end if;

  for v_eval in select value from jsonb_array_elements(evaluations)
  loop
    insert into public.evaluations (
      org_id,
      template_id,
      teams_id,
      coach_id,
      notes,
      status
    )
    values (
      (v_eval->>'org_id')::uuid,
      (v_eval->>'scorecard_template_id')::uuid,
      nullif(v_eval->>'team_id', '')::uuid,
      (v_eval->>'coach_id')::uuid,
      nullif(v_eval->>'notes', ''),
      'not_started'
    )
    returning id into v_evaluation_id;

    v_items := '[]'::jsonb;
    for v_item in select value from jsonb_array_elements(coalesce(v_eval->'evaluation_items', '[]'::jsonb))
    loop
      insert into public.evaluation_items (
        evaluation_id,
        athlete_id,
        subskill_id,
        rating,
        comment
      )
      values (
        v_evaluation_id,
        (v_eval->>'athlete_id')::uuid,
        (v_item->>'skill_id')::uuid,
        nullif(v_item->>'rating', '')::numeric,
        nullif(coalesce(v_item->>'comments', v_item->>'comment'), '')
      )
      returning id, rating, comment, created_at
        into v_item_id, v_item_rating, v_item_comment, v_item_created_at;

      v_items := v_items || jsonb_build_array(jsonb_build_object(
        'id', v_item_id,
        'evaluation_id', v_evaluation_id,
        'athlete_id', v_eval->>'athlete_id',
        'subskill_id', v_item->>'skill_id',
        'rating', v_item_rating,
        'comment', v_item_comment,
        'created_at', v_item_created_at
      ));
    end loop;

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'id', v_evaluation_id,
      'org_id', v_eval->>'org_id',
      'template_id', v_eval->>'scorecard_template_id',
      'teams_id', nullif(v_eval->>'team_id', ''),
      'coach_id', v_eval->>'coach_id',
      'notes', nullif(v_eval->>'notes', ''),
      'created_at', now(),
      'evaluation_items', v_items
    ));
  end loop;

  return v_result;
end;
$$;

create or replace function public.list_evaluation_skill_videos(
  p_evaluation_id uuid,
  p_org_id uuid,
  p_athlete_id uuid,
  p_rating_max numeric default 3
) returns table (
  evaluation_id uuid,
  skill_id uuid,
  title text,
  url text,
  rating numeric,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    items.evaluation_id,
    media.skill_id,
    skills.title,
    media.url,
    items.rating::numeric as rating,
    items.created_at
  from public.evaluations evals
  inner join public.evaluation_items items
    on evals.id = items.evaluation_id
  left join public.scorecard_subskills subskills
    on items.subskill_id = subskills.id
  inner join public.skill_media media
    on media.skill_id = coalesce(subskills.skill_id, items.subskill_id)
  inner join public.skills skills
    on media.skill_id = skills.id
  where evals.id = p_evaluation_id
    and evals.org_id = p_org_id
    and items.athlete_id = p_athlete_id
    and items.rating < p_rating_max
    and media.media_type = 'video'
  order by items.created_at desc, media.sort_order asc nulls last;
$$;

create or replace function public.submit_evaluation_tx(
  p_evaluation_id uuid,
  p_org_id uuid
) returns table (
  id uuid,
  status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  perform 1
  from public.evaluations as evals
  where evals.id = p_evaluation_id
    and evals.org_id = p_org_id;

  if not found then
    raise exception 'Evaluation not found';
  end if;

  update public.evaluations as evals
  set status = 'completed'
  where evals.id = p_evaluation_id
    and evals.org_id = p_org_id
    and evals.status in ('not_started', 'in_progress')
  returning evals.status into v_status;

  if v_status is null then
    select evals.status
      into v_status
    from public.evaluations as evals
    where evals.id = p_evaluation_id
      and evals.org_id = p_org_id
    limit 1;
  end if;

  insert into public.evaluation_workout_progress (
    org_id,
    evaluation_id,
    athlete_id,
    progress,
    level,
    created_at,
    updated_at
  )
  select
    items.org_id,
    items.evaluation_id,
    items.athlete_id,
    0 as progress,
    1 as level,
    now() as created_at,
    now() as updated_at
  from (
    select
      evals.org_id,
      evals.id as evaluation_id,
      eval_items.athlete_id
    from public.evaluation_items eval_items
    inner join public.evaluations evals
      on eval_items.evaluation_id = evals.id
    where eval_items.evaluation_id = p_evaluation_id
      and evals.org_id = p_org_id
    group by evals.org_id, evals.id, eval_items.athlete_id
  ) as items
  on conflict (org_id, evaluation_id, athlete_id) do nothing;

  insert into public.evaluation_workout_drills (
    org_id,
    evaluation_id,
    athlete_id,
    skill_id,
    drill_id,
    rate,
    level,
    created_at,
    updated_at
  )
  select
    evals.org_id,
    evals.id as evaluation_id,
    items.athlete_id,
    drills.skill_id,
    drills.drill_id,
    items.rating,
    drills.level,
    now() as created_at,
    now() as updated_at
  from public.evaluations evals
  inner join public.evaluation_items items
    on evals.id = items.evaluation_id
  inner join public.skill_drill_map drills
    on items.subskill_id = drills.skill_id
  where evals.id = p_evaluation_id
    and evals.org_id = p_org_id
    and items.rating < 3
    and drills.level is not null
  order by items.athlete_id, drills.skill_id, drills.level;

  return query select p_evaluation_id as id, v_status as status;
end;
$$;

create or replace function public.signup_register_parent_with_code_tx(
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
  guardian_id uuid,
  profile_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_team_id uuid;
  v_guardian_id uuid;
  v_full_name text;
begin
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

  select jc.org_id, jc.team_id
    into v_org_id, v_team_id
  from public.join_codes as jc
  where jc.code::text = p_code
    and coalesce(jc.is_active, true)
    and not coalesce(jc.disabled, false)
    and (jc.expires_at is null or jc.expires_at > now())
  for update;

  if not found then
    raise exception 'INVALID_JOIN_CODE' using errcode='P0001';
  end if;

  v_full_name := nullif(trim(concat_ws(' ', p_first_name, p_last_name)), '');

  insert into public.profiles (
    id,
    user_id,
    first_name,
    last_name,
    full_name,
    default_org_id,
    email,
    phone,
    role,
    terms_accepted,
    terms_accepted_at
  )
  values (
    p_user_id,
    p_user_id,
    btrim(p_first_name),
    btrim(p_last_name),
    v_full_name,
    v_org_id,
    lower(p_email),
    nullif(btrim(p_cell_number), ''),
    'parent',
    p_terms_accepted,
    case when p_terms_accepted then now() else null end
  )
  on conflict (id) do update
    set first_name = excluded.first_name,
        last_name = excluded.last_name,
        full_name = excluded.full_name,
        default_org_id = excluded.default_org_id,
        email = excluded.email,
        phone = excluded.phone,
        role = 'parent',
        user_id = excluded.user_id,
        terms_accepted = excluded.terms_accepted,
        terms_accepted_at = excluded.terms_accepted_at;

  insert into public.org_memberships (org_id, user_id, role, is_active)
  values (v_org_id, p_user_id, 'parent', true)
  on conflict (org_id, user_id) do update
    set role = excluded.role,
        is_active = true;

  insert into public.guardian_contacts (
    org_id,
    user_id,
    full_name,
    email,
    phone
  )
  values (
    v_org_id,
    p_user_id,
    v_full_name,
    lower(p_email),
    nullif(btrim(p_cell_number), '')
  )
  on conflict do nothing;

  select id
    into v_guardian_id
  from public.guardian_contacts
  where org_id = v_org_id
    and user_id = p_user_id
  limit 1;

  update public.join_codes
  set uses_count = coalesce(uses_count, 0) + 1,
      used_count = coalesce(used_count, 0) + 1
  where code = p_code;

  return query select v_org_id, v_team_id, v_guardian_id, p_user_id;
end;
$$;
