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
