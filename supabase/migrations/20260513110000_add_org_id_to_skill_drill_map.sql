alter table public.skill_drill_map
  add column if not exists org_id uuid;

update public.skill_drill_map map
set org_id = drills.org_id
from public.drills drills
where map.drill_id = drills.id
  and map.org_id is null;

alter table public.skill_drill_map
  alter column org_id set not null;

alter table public.skill_drill_map
  drop constraint if exists skill_drill_map_org_id_fkey;

alter table public.skill_drill_map
  add constraint skill_drill_map_org_id_fkey
  foreign key (org_id) references public.organizations(id) on delete cascade;

create index if not exists idx_skill_drill_map_org_id
  on public.skill_drill_map(org_id);

create index if not exists idx_skill_drill_map_org_skill
  on public.skill_drill_map(org_id, skill_id);
