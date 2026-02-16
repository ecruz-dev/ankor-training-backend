create or replace function public.get_workout_summary(
  p_org_id uuid,
  p_athlete_id uuid,
  p_user_id uuid
) returns table (
  total_evals bigint,
  total_reps bigint,
  total_plans_shares bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce((
      select count(distinct ei.evaluation_id)
      from public.evaluation_items ei
      inner join public.evaluations e
        on e.id = ei.evaluation_id
      where ei.athlete_id = p_athlete_id
        and e.org_id = p_org_id
    ), 0)::bigint as total_evals,
    coalesce((
      select sum(ewp.progress)
      from public.evaluation_workout_progress ewp
      where ewp.org_id = p_org_id
        and ewp.athlete_id = p_athlete_id
    ), 0)::bigint as total_reps,
    coalesce((
      select count(*)
      from public.practice_plan_invitations ppi
      where ppi.invited_by = p_user_id
    ), 0)::bigint as total_plans_shares;
$$;
