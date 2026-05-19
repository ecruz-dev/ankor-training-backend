alter table public.evaluation_items
  drop constraint if exists evaluation_items_subskill_id_fkey;

update public.evaluation_items ei
set subskill_id = ss.skill_id
from public.scorecard_subskills ss
where ei.subskill_id = ss.id
  and ss.skill_id is not null;

do $$
begin
  if exists (
    select 1
    from public.evaluation_items ei
    left join public.skills s
      on s.id = ei.subskill_id
    where s.id is null
  ) then
    raise exception 'EVALUATION_ITEMS_SUBSKILL_SKILL_REPOINT_FAILED'
      using errcode = 'P0001',
            detail = 'Some evaluation_items.subskill_id values do not match public.skills.id after migration.';
  end if;
end;
$$;

alter table public.evaluation_items
  add constraint evaluation_items_subskill_id_fkey
  foreign key (subskill_id) references public.skills(id) on delete cascade;
