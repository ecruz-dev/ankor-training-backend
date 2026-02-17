create or replace function public.get_coach_summary(
  p_org_id uuid,
  p_coach_id uuid
) returns table (
  total_teams bigint,
  total_athletes bigint,
  total_evaluations bigint,
  total_plans_share bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with coach_teams as (
    select t.id
    from public.teams t
    where t.coach_id = p_coach_id
      and t.org_id = p_org_id
  )
  select
    coalesce((
      select count(*)
      from coach_teams
    ), 0)::bigint as total_teams,
    coalesce((
      select count(*)
      from public.team_memberships tm
      where tm.team_id in (select id from coach_teams)
    ), 0)::bigint as total_athletes,
    coalesce((
      select count(*)
      from public.evaluations e
      where e.coach_id = p_coach_id
        and e.org_id = p_org_id
        and e.status = 'completed'
    ), 0)::bigint as total_evaluations,
    coalesce((
      select count(*)
      from public.practice_plan_invitations ppi
      where ppi.invited_by = p_coach_id
    ), 0)::bigint as total_plans_share;
$$;
