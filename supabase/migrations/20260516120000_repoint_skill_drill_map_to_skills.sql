alter table public.skill_drill_map
  drop constraint if exists skill_drill_map_skill_id_fkey;

alter table public.skill_drill_map
  add constraint skill_drill_map_skill_id_fkey
  foreign key (skill_id) references public.skills(id) on delete cascade;
