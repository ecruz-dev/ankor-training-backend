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

notify pgrst, 'reload schema';
