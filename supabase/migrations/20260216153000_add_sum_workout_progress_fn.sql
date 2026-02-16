create or replace function public.sum_evaluation_workout_progress(
  p_org_id uuid,
  p_athlete_id uuid
) returns table (
  total_reps bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(progress), 0)::bigint as total_reps
  from public.evaluation_workout_progress
  where org_id = p_org_id
    and athlete_id = p_athlete_id;
$$;
