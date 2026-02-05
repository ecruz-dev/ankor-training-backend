import { sbAdmin } from "./supabase.ts";
import {
  EvaluationInput,
  EvaluationWithItems,
} from "../schemas/evaluations.ts";
import {
  EvaluationDetailDto,
   type EvaluationMatrixUpdateDto,
  toEvaluationDetailDto,
} from "../dtos/evaluations.dto.ts";

type SubmitEvaluationResult =
  | { ok: true; data: { id: string; status: string } }
  | { ok: false; error: unknown };

export type LatestEvaluationRow = {
  evaluation_id: string;
  created_at: string | null;
  scorecard_name: string | null;
  coach_name: string | null;
  athlete_id: string;
  athlete_full_name: string | null;
};

export type LatestEvaluationsFilters = {
  org_id: string;
  athlete_id?: string;
  athlete_name?: string;
  user_id?: string;
  limit: number;
  offset: number;
  scorecard_name?: string;
  coach_name?: string;
  coach_id?: string;
  date_from?: string;
  date_to?: string;
};

export type EvaluationAthleteRow = {
  evaluation_id: string;
  created_at: string | null;
  scorecard_name: string | null;
  coach_name: string | null;
  athlete_id: string;
  athlete_full_name: string | null;
  athletes_name: string | null;
};

export type EvaluationAthletesByIdFilters = {
  org_id: string;
  evaluation_id: string;
  athlete_id?: string;
  limit: number;
  offset: number;
};

export type EvaluationImprovementSkillRow = {
  evaluation_id: string;
  skill_id: string;
  skill_name: string | null;
  rating: number | null;
};

export type EvaluationImprovementSkillFilters = {
  org_id: string;
  evaluation_id: string;
  athlete_id: string;
  limit: number;
  offset: number;
  rating_max: number;
};

export type EvaluationSkillVideoRow = {
  evaluation_id: string;
  skill_id: string;
  title: string | null;
  object_path: string | null;
  rating: number | null;
};

export type EvaluationSkillVideoFilters = {
  org_id: string;
  evaluation_id: string;
  athlete_id: string;
  rating_max: number;
};

export type EvaluationSubskillRatingRow = {
  evaluation_id: string;
  skill_id: string;
  skill_descrip: string | null;
  category_id: string;
  category_descrip: string | null;
  rating: number | null;
};

export type EvaluationSubskillRatingFilters = {
  org_id: string;
  evaluation_id: string;
  athlete_id: string;
  rating_max: number;
};

export type EvaluationWorkoutProgressRow = {
  id: string;
  org_id: string;
  evaluation_id: string;
  athlete_id: string;
  progress: number | null;
  level: number | null;
  maxWorkoutReps: number | null;
};

export type EvaluationWorkoutProgressFilters = {
  org_id: string;
  athlete_id: string;
  evaluation_id?: string;
  limit?: number;
  offset?: number;
};

export type EvaluationWorkoutProgressUpdateInput = {
  org_id: string;
  athlete_id: string;
  evaluation_id: string;
};

export type EvaluationWorkoutDrillsFilters = {
  org_id: string;
  athlete_id: string;
  evaluation_id: string;
};

export type EvaluationWorkoutDrillVideo = {
  id: string;
  title: string;
  duration: string;
  thumbnailUrl: string | null;
};

export type EvaluationWorkoutDrillLevel = {
  level: number;
  title: string;
  targetReps: number | null;
  drills: EvaluationWorkoutDrillVideo[];
};


export async function rpcBulkCreateEvaluations(args: {
  evaluations: EvaluationInput[];
}): Promise<{ data: EvaluationWithItems[] | null; error: unknown }> {
  const { data, error } = await sbAdmin!.rpc(
    "evaluations_bulk_create_tx",
    args,
  );

  if (error) {
    return { data: null, error };
  }

  const mapped: EvaluationWithItems[] | null = (data as any[] | null)?.map(
    (row: any) => {
      const {
        template_id,
        teams_id,
        evaluation_items,
        // keep everything else (id, org_id, coach_id, notes, created_at, sport_id, etc.)
        ...rest
      } = row;

      const mappedItems =
        (evaluation_items as any[] | undefined)?.map((item: any) => {
          const { subskill_id, comment, ...itemRest } = item;
          return {
            ...itemRest,
            // DB → TS schema mapping
            skill_id: subskill_id,
            comments: comment,
          };
        }) ?? [];

      return {
        ...rest,
        // DB → TS schema mapping
        scorecard_template_id: template_id,
        team_id: teams_id,
        evaluation_items: mappedItems,
      } as EvaluationWithItems;
    },
  ) ?? null;

  return {
    data: mapped,
    error: null,
  };
}


export async function listEvaluations(org_id?: string): Promise<{
  data: any[] | null;
  error: unknown;
}> {
  let query = sbAdmin!
    .from('evaluations')
    .select(
      `
      id,
      org_id,
      template_id,
      teams_id,
      coach_id,
      notes,
      created_at,
      status
      team:teams!inner (
        id,
        name
      ),
      template:scorecard_templates!inner (
        id,
        name
      )
    `,
    )
    .neq('status', 'completed')
    .order('created_at', { ascending: false })

  if (org_id) {
    query = query.eq('org_id', org_id)
  }

  const { data, error } = await query

  if (error) {
    return { data: null, error }
  }

  const mapped = (data ?? []).map((row: any) => {
  const { template_id, team, template, ...rest } = row

    // ---- team name ----
  const team_name: string | null = team?.name ?? null

    // ---- template name ----
  const scorecard_template_name: string | null = template?.name ?? null

  return {
      ...rest,
      scorecard_template_id: template_id,
      scorecard_template_name,
      team_name,
    }
  })

  return { data: mapped, error: null }
}

export async function listLatestEvaluationsByAthlete(
  filters: LatestEvaluationsFilters,
): Promise<{ data: LatestEvaluationRow[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const {
    org_id,
    athlete_id,
    athlete_name,
    user_id,
    limit,
    offset,
    scorecard_name,
    coach_name,
    coach_id,
    date_from,
    date_to,
  } = filters;

   let query = client
    .from("evaluation_items")
    .select(
      `
      evaluation_id,
      evaluation:evaluations!inner (
        id,
        org_id,
        created_at,
        coach:coaches!inner (
          id,
          full_name
        ),
        scorecard_template:scorecard_templates!inner (
          id,
          name
        )
      ),
      athlete:athletes!inner (
        id,
        full_name
      )
    `,
    )
    .eq("evaluations.org_id", org_id);

  if (user_id) {
    const { data: guardianRow, error: guardianError } = await client
      .from("guardian_contacts")
      .select("id")
      .eq("org_id", org_id)
      .eq("user_id", user_id)
      .maybeSingle();

    if (guardianError) {
      return { data: [], count: 0, error: guardianError };
    }

    const guardianId = guardianRow?.id ?? null;
    if (!guardianId) {
      return { data: [], count: 0, error: null };
    }

    const { data: guardianLinks, error: guardianLinksError } = await client
      .from("athlete_guardians")
      .select("athlete_id")
      .eq("guardian_id", guardianId);

    if (guardianLinksError) {
      return { data: [], count: 0, error: guardianLinksError };
    }

    const athleteIds = Array.from(
      new Set(
        (guardianLinks ?? [])
          .map((row: any) => row?.athlete_id)
          .filter((id: unknown): id is string => typeof id === "string" && id.length > 0),
      ),
    );

    if (athleteIds.length === 0) {
      return { data: [], count: 0, error: null };
    }

    if (athlete_id && !athleteIds.includes(athlete_id)) {
      return { data: [], count: 0, error: null };
    }

    query = query.in("athlete_id", athleteIds);
  }

  if (athlete_id) {
    query = query.eq("athlete_id", athlete_id);
  }
  if (athlete_name) {
    query = query.ilike("athletes.full_name", `%${athlete_name}%`);
  }
  if (coach_id) {
    query = query.eq("evaluations.coach_id", coach_id);
  }
  if (coach_name) {
    query = query.ilike("coaches.full_name", `%${coach_name}%`);
  }
  if (date_from) {
    query = query.gte("evaluations.created_at", date_from);
  }
  if (date_to) {
    query = query.lte("evaluations.created_at", date_to);
  }


  const { data, error } = await query;
  if (error) {
    return { data: [], count: 0, error };
  }

  const scorecardQuery = scorecard_name
    ? scorecard_name.toLowerCase()
    : null;
  const grouped = new Map<string, LatestEvaluationRow>();

  for (const row of data ?? []) {
    const evaluation = row?.evaluation ?? null;
    if (!evaluation) continue;
    if (evaluation.org_id && evaluation.org_id !== org_id) continue;
    if (scorecardQuery) {
      const templateName = evaluation.scorecard_template?.name ?? "";
      if (!templateName.toLowerCase().includes(scorecardQuery)) {
        continue;
      }
    }

    const athlete = row?.athlete ?? null;
    const athleteId = athlete?.id ?? athlete_id;
    const evaluationId = row?.evaluation_id ?? evaluation?.id;
    if (!evaluationId || !athleteId) continue;

    const key = `${evaluationId}:${athleteId}`;
    if (grouped.has(key)) continue;

    grouped.set(key, {
      evaluation_id: evaluationId,
      created_at: evaluation.created_at ?? null,
      scorecard_name: evaluation.scorecard_template?.name ?? null,
      coach_name: evaluation.coach?.full_name ?? null,
      athlete_id: athleteId,
      athlete_full_name: athlete?.full_name ?? null,
    });
  }

  const allItems = Array.from(grouped.values());
  allItems.sort((a, b) => {
    const aTime = a.created_at ? Date.parse(a.created_at) : 0;
    const bTime = b.created_at ? Date.parse(b.created_at) : 0;
    return bTime - aTime;
  });

  const paged = allItems.slice(offset, offset + limit);

  return { data: paged, count: allItems.length, error: null };
}

export async function listEvaluationAthletesById(
  filters: EvaluationAthletesByIdFilters,
): Promise<{ data: EvaluationAthleteRow[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const { org_id, evaluation_id, athlete_id, limit, offset } = filters;

  let query = client
    .from("evaluation_items")
    .select(
      `
      evaluation_id,
      evaluation:evaluation_id (
        id,
        org_id,
        created_at,
        coach:coach_id (
          id,
          full_name
        ),
        scorecard_template:template_id (
          id,
          name
        )
      ),
      athlete:athlete_id (
        id,
        full_name
      )
    `,
    )
    .eq("evaluation_id", evaluation_id);

  if (athlete_id) {
    query = query.eq("athlete_id", athlete_id);
  }

  const { data, error } = await query;

  if (error) {
    return { data: [], count: 0, error };
  }
  if (!data || data.length === 0) {
    return { data: [], count: 0, error: null };
  }

  const scopedRows = (data ?? []).filter(
    (row: any) => row?.evaluation?.org_id === org_id,
  );
  if (scopedRows.length === 0) {
    return { data: [], count: 0, error: null };
  }

  const athleteMap = new Map<string, { id: string; full_name: string | null }>();
  for (const row of scopedRows) {
    const athleteId = row?.athlete?.id;
    if (!athleteId) continue;
    if (!athleteMap.has(athleteId)) {
      athleteMap.set(athleteId, {
        id: athleteId,
        full_name: row?.athlete?.full_name ?? null,
      });
    }
  }

  const evaluation = scopedRows[0]?.evaluation ?? null;
  const allItems = Array.from(athleteMap.values()).map((athlete) => ({
    evaluation_id: evaluation?.id ?? evaluation_id,
    created_at: evaluation?.created_at ?? null,
    scorecard_name: evaluation?.scorecard_template?.name ?? null,
    coach_name: evaluation?.coach?.full_name ?? null,
    athlete_id: athlete.id,
    athlete_full_name: athlete.full_name ?? null,
    athletes_name: athlete.full_name ?? null,
  }));

  const paged = allItems.slice(offset, offset + limit);

  return { data: paged, count: allItems.length, error: null };
}

export async function listEvaluationImprovementSkills(
  filters: EvaluationImprovementSkillFilters,
): Promise<{ data: EvaluationImprovementSkillRow[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const { org_id, evaluation_id, athlete_id, limit, offset, rating_max } = filters;

  const { data, error } = await client
    .from("evaluations")
    .select(
      `
      id,
      created_at,
      template:scorecard_templates!inner (
        id
      ),
      evaluation_items!inner (
        evaluation_id,
        athlete_id,
        subskill_id,
        rating
      )
    `,
    )
    .eq("id", evaluation_id)
    .eq("org_id", org_id)
    .eq("evaluation_items.athlete_id", athlete_id)
    .lt("evaluation_items.rating", rating_max)
    .order("created_at", { ascending: false });

  if (error) {
    return { data: [], count: 0, error };
  }

  const rawItems: Array<{
    evaluation_id: string;
    subskill_id: string;
    rating: number | null;
    created_at: string | null;
  }> = [];

  for (const row of data ?? []) {
    const created_at = row?.created_at ?? null;
    const evaluationId = row?.id ?? evaluation_id;
    const items = Array.isArray(row?.evaluation_items)
      ? row.evaluation_items
      : row?.evaluation_items
      ? [row.evaluation_items]
      : [];

    for (const item of items) {
      const subskillId = item?.subskill_id;
      if (!subskillId) continue;
      rawItems.push({
        evaluation_id: item?.evaluation_id ?? evaluationId,
        subskill_id: subskillId,
        rating: item?.rating ?? null,
        created_at,
      });
    }
  }

  if (rawItems.length === 0) {
    return { data: [], count: 0, error: null };
  }

  const skillIds = Array.from(
    new Set(rawItems.map((item) => item.subskill_id).filter(Boolean)),
  );
  if (skillIds.length === 0) {
    return { data: [], count: 0, error: null };
  }

  // Manual join: evaluation_items.subskill_id -> scorecard_subskills.skill_id.
  const { data: subskills, error: subskillError } = await client
    .from("scorecard_subskills")
    .select("skill_id")
    .in("skill_id", skillIds);

  if (subskillError) {
    return { data: [], count: 0, error: subskillError };
  }

  const subskillSkillIds = new Set(
    (subskills ?? [])
      .map((row: any) => row?.skill_id)
      .filter((value: unknown): value is string =>
        typeof value === "string" && value.length > 0
      ),
  );

  if (subskillSkillIds.size === 0) {
    return { data: [], count: 0, error: null };
  }

  const { data: skills, error: skillsError } = await client
    .from("skills")
    .select("id, title")
    .in("id", Array.from(subskillSkillIds));

  if (skillsError) {
    return { data: [], count: 0, error: skillsError };
  }

  const skillNameById = new Map<string, string | null>();
  for (const skill of skills ?? []) {
    const id = skill?.id;
    if (typeof id !== "string" || !id) continue;
    skillNameById.set(id, skill?.title ?? null);
  }

  const joined = rawItems
    .filter((item) => subskillSkillIds.has(item.subskill_id))
    .filter((item) => skillNameById.has(item.subskill_id))
    .map((item) => ({
      evaluation_id: item.evaluation_id,
      skill_id: item.subskill_id,
      skill_name: skillNameById.get(item.subskill_id) ?? null,
      rating: item.rating ?? null,
      created_at: item.created_at ?? null,
    }));

  joined.sort((a, b) => {
    const aTime = a.created_at ? Date.parse(a.created_at) : 0;
    const bTime = b.created_at ? Date.parse(b.created_at) : 0;
    return bTime - aTime;
  });

  const paged = joined.slice(offset, offset + limit);

  return {
    data: paged.map(({ created_at, ...rest }) => rest),
    count: joined.length,
    error: null,
  };
}

export async function listEvaluationSkillVideos(
  filters: EvaluationSkillVideoFilters,
): Promise<{ data: EvaluationSkillVideoRow[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const { org_id, evaluation_id, athlete_id, rating_max } = filters;

  const { data, error } = await client
    .from("evaluations")
    .select(
      `
      id,
      created_at,
      template:scorecard_templates!inner (
        id
      ),
      evaluation_items!inner (
        evaluation_id,
        athlete_id,
        subskill_id,
        rating
      )
    `,
    )
    .eq("id", evaluation_id)
    .eq("org_id", org_id)
    .eq("evaluation_items.athlete_id", athlete_id)
    .lt("evaluation_items.rating", rating_max)
    .order("created_at", { ascending: false });

  if (error) {
    return { data: [], count: 0, error };
  }

  const rawItems: Array<{
    evaluation_id: string;
    skill_id: string;
    created_at: string | null;
    rating: number | null;
  }> = [];

  for (const row of data ?? []) {
    const created_at = row?.created_at ?? null;
    const evaluationId = row?.id ?? evaluation_id;
    const items = Array.isArray(row?.evaluation_items)
      ? row.evaluation_items
      : row?.evaluation_items
      ? [row.evaluation_items]
      : [];

    for (const item of items) {
      const skillId = item?.subskill_id;
      if (!skillId) continue;
      rawItems.push({
        evaluation_id: item?.evaluation_id ?? evaluationId,
        skill_id: skillId,
        created_at,
        rating: item?.rating ?? null,
      });
    }
  }

  if (rawItems.length === 0) {
    return { data: [], count: 0, error: null };
  }

  const skillIds = Array.from(
    new Set(rawItems.map((item) => item.skill_id).filter(Boolean)),
  );
  if (skillIds.length === 0) {
    return { data: [], count: 0, error: null };
  }

  const { data: subskills, error: subskillError } = await client
    .from("scorecard_subskills")
    .select("skill_id")
    .in("skill_id", skillIds);

  if (subskillError) {
    return { data: [], count: 0, error: subskillError };
  }

  const subskillSkillIds = new Set(
    (subskills ?? [])
      .map((row: any) => row?.skill_id)
      .filter((value: unknown): value is string =>
        typeof value === "string" && value.length > 0
      ),
  );

  if (subskillSkillIds.size === 0) {
    return { data: [], count: 0, error: null };
  }

  const { data: skills, error: skillsError } = await client
    .from("skills")
    .select("id, title")
    .in("id", Array.from(subskillSkillIds));

  if (skillsError) {
    return { data: [], count: 0, error: skillsError };
  }

  const titleById = new Map<string, string | null>();
  for (const skill of skills ?? []) {
    const id = skill?.id;
    if (typeof id !== "string" || !id) continue;
    titleById.set(id, skill?.title ?? null);
  }

  if (titleById.size === 0) {
    return { data: [], count: 0, error: null };
  }

  const { data: videoRows, error: videoError } = await client
    .from("skill_video_map")
    .select("skill_id, object_path")
    .in("skill_id", Array.from(titleById.keys()));

  if (videoError) {
    return { data: [], count: 0, error: videoError };
  }

  const videosBySkill = new Map<string, Array<string | null>>();
  for (const row of videoRows ?? []) {
    const skillId = row?.skill_id;
    if (typeof skillId !== "string" || !skillId) continue;
    if (!videosBySkill.has(skillId)) {
      videosBySkill.set(skillId, []);
    }
    videosBySkill.get(skillId)!.push(row?.object_path ?? null);
  }

  const filtered = rawItems.filter(
    (item) => subskillSkillIds.has(item.skill_id) && titleById.has(item.skill_id),
  );

  const results: Array<EvaluationSkillVideoRow & { created_at: string | null }> = [];
  for (const item of filtered) {
    const videos = videosBySkill.get(item.skill_id);
    if (!videos || videos.length === 0) continue;
    const title = titleById.get(item.skill_id) ?? null;
    for (const object_path of videos) {
      results.push({
        evaluation_id: item.evaluation_id,
        skill_id: item.skill_id,
        title,
        object_path,
        rating: item.rating ?? null,
        created_at: item.created_at ?? null,
      });
    }
  }

  results.sort((a, b) => {
    const aTime = a.created_at ? Date.parse(a.created_at) : 0;
    const bTime = b.created_at ? Date.parse(b.created_at) : 0;
    return bTime - aTime;
  });

  return {
    data: results.map(({ created_at, ...rest }) => rest),
    count: results.length,
    error: null,
  };
}

export async function listEvaluationSubskillRatings(
  filters: EvaluationSubskillRatingFilters,
): Promise<{ data: EvaluationSubskillRatingRow[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const { org_id, evaluation_id, athlete_id, rating_max } = filters;

  const { data, error } = await client
    .from("evaluations")
    .select(
      `
      id,
      created_at,
      template:scorecard_templates!inner (
        id
      ),
      evaluation_items!inner (
        evaluation_id,
        athlete_id,
        subskill_id,
        rating
      )
    `,
    )
    .eq("id", evaluation_id)
    .eq("org_id", org_id)
    .eq("evaluation_items.athlete_id", athlete_id)   
    .order("created_at", { ascending: false });

  if (error) {
    return { data: [], count: 0, error };
  }

  const rawItems: Array<{
    evaluation_id: string;
    skill_id: string;
    rating: number | null;
    created_at: string | null;
  }> = [];

  for (const row of data ?? []) {
    const created_at = row?.created_at ?? null;
    const evaluationId = row?.id ?? evaluation_id;
    const items = Array.isArray(row?.evaluation_items)
      ? row.evaluation_items
      : row?.evaluation_items
      ? [row.evaluation_items]
      : [];

    for (const item of items) {
      const skillId = item?.subskill_id;
      if (!skillId) continue;
      rawItems.push({
        evaluation_id: item?.evaluation_id ?? evaluationId,
        skill_id: skillId,
        rating: item?.rating ?? null,
        created_at,
      });
    }
  }

  if (rawItems.length === 0) {
    return { data: [], count: 0, error: null };
  }

  const skillIds = Array.from(
    new Set(rawItems.map((item) => item.skill_id).filter(Boolean)),
  );
  if (skillIds.length === 0) {
    return { data: [], count: 0, error: null };
  }

  const { data: subskills, error: subskillError } = await client
    .from("scorecard_subskills")
    .select("skill_id, category_id")
    .in("skill_id", skillIds);

  if (subskillError) {
    return { data: [], count: 0, error: subskillError };
  }

  const categoryIdsBySkill = new Map<string, Set<string>>();
  const categoryIds = new Set<string>();
  for (const row of subskills ?? []) {
    const skillId = row?.skill_id;
    const categoryId = row?.category_id;
    if (typeof skillId !== "string" || !skillId) continue;
    if (typeof categoryId !== "string" || !categoryId) continue;
    if (!categoryIdsBySkill.has(skillId)) {
      categoryIdsBySkill.set(skillId, new Set<string>());
    }
    categoryIdsBySkill.get(skillId)!.add(categoryId);
    categoryIds.add(categoryId);
  }

  if (categoryIdsBySkill.size === 0 || categoryIds.size === 0) {
    return { data: [], count: 0, error: null };
  }

  const { data: skills, error: skillsError } = await client
    .from("skills")
    .select("id, title")
    .in("id", Array.from(categoryIdsBySkill.keys()));

  if (skillsError) {
    return { data: [], count: 0, error: skillsError };
  }

  const skillTitleById = new Map<string, string | null>();
  for (const skill of skills ?? []) {
    const id = skill?.id;
    if (typeof id !== "string" || !id) continue;
    skillTitleById.set(id, skill?.title ?? null);
  }

  const { data: categories, error: categoriesError } = await client
    .from("scorecard_categories")
    .select("id, name")
    .in("id", Array.from(categoryIds));

  if (categoriesError) {
    return { data: [], count: 0, error: categoriesError };
  }

  const categoryNameById = new Map<string, string | null>();
  for (const category of categories ?? []) {
    const id = category?.id;
    if (typeof id !== "string" || !id) continue;
    categoryNameById.set(id, category?.name ?? null);
  }

  const results: Array<EvaluationSubskillRatingRow & { created_at: string | null }> = [];
  for (const item of rawItems) {
    const categoriesForSkill = categoryIdsBySkill.get(item.skill_id);
    const skillTitle = skillTitleById.get(item.skill_id);
    if (!categoriesForSkill || !skillTitleById.has(item.skill_id)) continue;

    for (const categoryId of categoriesForSkill) {
      if (!categoryNameById.has(categoryId)) continue;
      results.push({
        evaluation_id: item.evaluation_id,
        skill_id: item.skill_id,
        skill_descrip: skillTitle ?? null,
        category_id: categoryId,
        category_descrip: categoryNameById.get(categoryId) ?? null,
        rating: item.rating ?? null,
        created_at: item.created_at ?? null,
      });
    }
  }

  results.sort((a, b) => {
    const aTime = a.created_at ? Date.parse(a.created_at) : 0;
    const bTime = b.created_at ? Date.parse(b.created_at) : 0;
    return bTime - aTime;
  });

  return {
    data: results.map(({ created_at, ...rest }) => rest),
    count: results.length,
    error: null,
  };
}

export async function listEvaluationWorkoutProgress(
  filters: EvaluationWorkoutProgressFilters,
): Promise<{ data: EvaluationWorkoutProgressRow[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const {
    org_id,
    athlete_id,
    evaluation_id,
    limit = 200,
    offset = 0,
  } = filters;

  let query = client
    .from("evaluation_workout_progress")
    .select(
      `
      id,
      org_id,
      evaluation_id,
      athlete_id,
      progress,
      level,
      organizations!inner (
        maxWorkoutReps
      )
    `,
      { count: "exact" },
    )
    .eq("org_id", org_id)
    .eq("athlete_id", athlete_id);

  if (evaluation_id) {
    query = query.eq("evaluation_id", evaluation_id);
  }

  const rangeTo = offset + (limit - 1);
  const { data, error, count } = await query.range(offset, rangeTo);
  if (error) {
    return { data: [], count: 0, error };
  }

  const mapped = (data ?? []).map((row: any) => {
    const organization = Array.isArray(row?.organizations)
      ? row.organizations[0]
      : row?.organizations;

    return {
      id: row?.id,
      org_id: row?.org_id,
      evaluation_id: row?.evaluation_id,
      athlete_id: row?.athlete_id,
      progress: row?.progress ?? null,
      level: row?.level ?? null,
      maxWorkoutReps: organization?.maxWorkoutReps ?? null,
    };
  });

  return { data: mapped, count: count ?? mapped.length, error: null };
}

export async function incrementEvaluationWorkoutProgress(
  input: EvaluationWorkoutProgressUpdateInput,
): Promise<{ data: EvaluationWorkoutProgressRow | null; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: null, error: new Error("Supabase client not initialized") };
  }

  const { org_id, athlete_id, evaluation_id } = input;

  const { data: row, error } = await client
    .from("evaluation_workout_progress")
    .select(
      `
      id,
      org_id,
      evaluation_id,
      athlete_id,
      progress,
      level,
      organizations!inner (
        maxWorkoutReps
      )
    `,
    )
    .eq("org_id", org_id)
    .eq("athlete_id", athlete_id)
    .eq("evaluation_id", evaluation_id)
    .maybeSingle();

  if (error) {
    return { data: null, error };
  }

  if (!row?.id) {
    return { data: null, error: new Error("Workout progress not found") };
  }

  const organization = Array.isArray(row?.organizations)
    ? row.organizations[0]
    : row?.organizations;
  const maxWorkoutRepsRaw = organization?.maxWorkoutReps;
  const maxWorkoutReps = Number(maxWorkoutRepsRaw);

  if (!Number.isFinite(maxWorkoutReps) || maxWorkoutReps <= 0) {
    return {
      data: null,
      error: new Error("maxWorkoutReps must be a positive number"),
    };
  }

  const progressValue = Number.isFinite(Number(row.progress))
    ? Number(row.progress)
    : 0;
  const levelValue = Number.isFinite(Number(row.level))
    ? Number(row.level)
    : 0;

  const maxProgress = maxWorkoutReps * 10;
  let nextProgress = progressValue + 1;
  let nextLevel = levelValue;

  if (nextProgress >= maxProgress) {
    nextProgress = 1;
    nextLevel = levelValue + 1;
  }

  const { data: updated, error: updateError } = await client
    .from("evaluation_workout_progress")
    .update({ progress: nextProgress, level: nextLevel })
    .eq("id", row.id)
    .select("id, org_id, evaluation_id, athlete_id, progress, level")
    .maybeSingle();

  if (updateError) {
    return { data: null, error: updateError };
  }

  if (!updated) {
    return { data: null, error: new Error("Workout progress not found") };
  }

  return {
    data: {
      id: updated.id,
      org_id: updated.org_id,
      evaluation_id: updated.evaluation_id,
      athlete_id: updated.athlete_id,
      progress: updated.progress ?? null,
      level: updated.level ?? null,
      maxWorkoutReps,
    },
    error: null,
  };
}

export async function listEvaluationWorkoutDrills(
  filters: EvaluationWorkoutDrillsFilters,
): Promise<{ data: EvaluationWorkoutDrillLevel[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const { org_id, athlete_id, evaluation_id } = filters;

  const { data: progressRow, error: progressError } = await client
    .from("evaluation_workout_progress")
    .select("level, progress")
    .eq("org_id", org_id)
    .eq("athlete_id", athlete_id)
    .eq("evaluation_id", evaluation_id)
    .maybeSingle();

  if (progressError) {
    return { data: [], count: 0, error: progressError };
  }

  const level =
    typeof progressRow?.level === "number" && Number.isFinite(progressRow.level)
      ? progressRow.level
      : null;

  if (level === null) {
    return { data: [], count: 0, error: null };
  }

  const { data: drillRows, error: drillsError } = await client
    .from("evaluation_workout_drills")
    .select("drill_id, level")
    .eq("org_id", org_id)
    .eq("athlete_id", athlete_id)
    .eq("evaluation_id", evaluation_id)
    .eq("level", level);

  if (drillsError) {
    return { data: [], count: 0, error: drillsError };
  }

  const rows = Array.isArray(drillRows) ? drillRows : [];
  if (rows.length === 0) {
    return { data: [], count: 0, error: null };
  }

  const drillIds = Array.from(
    new Set(
      rows
        .map((row: any) => row?.drill_id)
        .filter((id: unknown): id is string => typeof id === "string" && id.length > 0),
    ),
  );

  const mediaByDrill = new Map<string, { title: string; thumbnailUrl: string | null }>();
  if (drillIds.length > 0) {
    const { data: mediaRows, error: mediaError } = await client
      .from("drill_media")
      .select("drill_id, title, thumbnail_url, sort_order, media_type")
      .in("drill_id", drillIds)
      .order("sort_order", { ascending: true });

    if (mediaError) {
      return { data: [], count: 0, error: mediaError };
    }

    for (const row of mediaRows ?? []) {
      const drillId = row?.drill_id;
      if (!drillId || mediaByDrill.has(drillId)) continue;
      mediaByDrill.set(drillId, {
        title: typeof row?.title === "string" ? row.title : "",
        thumbnailUrl: row?.thumbnail_url ?? null,
      });
    }
  }

  const targetReps =
    typeof progressRow?.progress === "number" && Number.isFinite(progressRow.progress)
      ? progressRow.progress
      : null;

  const drills: EvaluationWorkoutDrillVideo[] = rows
    .map((row: any) => {
      const drillId = row?.drill_id;
      if (typeof drillId !== "string" || !drillId) return null;
      const media = mediaByDrill.get(drillId);
      return {
        id: drillId,
        title: media?.title ?? "",
        duration: "30",
        thumbnailUrl: media?.thumbnailUrl ?? null,
      };
    })
    .filter((item: EvaluationWorkoutDrillVideo | null): item is EvaluationWorkoutDrillVideo =>
      Boolean(item)
    );

  return {
    data: [
      {
        level,
        title: `Level ${level}`,
        targetReps,
        drills,
      },
    ],
    count: 1,
    error: null,
  };
}

export async function getEvaluationById(
  evaluationId: string,
  org_id: string,
): Promise<EvaluationDetailDto | null> {
  if (!sbAdmin) {
    throw new Error("Supabase admin client is not configured");
  }

  const { data, error } = await sbAdmin
    .from("evaluations")
    .select(
      `
      id,
      org_id,
      template_id,
      coach_id,
      teams_id,
      notes,
      created_at,
      status,
      teams:teams_id (
        id,
        name
      ),
      scorecard_templates:template_id (
        id,
        name,
        scorecard_categories (
          id,
          template_id,
          name,
          description,
          position
        )
      ),
      evaluation_items (
        id,
        evaluation_id,
        athlete_id,
        subskill_id,
        rating,
        comment,
        created_at,
        athletes:athlete_id (
          id,
          first_name,
          last_name
        )
      )
    `,
    )
    .eq("id", evaluationId)
    .eq("org_id", org_id)
    .maybeSingle();

  if (error) {
    console.error("[getEvaluationByIdService] Supabase error", error);
    throw error;
  }

  if (!data) {
    return null;
  }

  return toEvaluationDetailDto(data);
}


export async function applyEvaluationMatrixUpdateService(
  dto: EvaluationMatrixUpdateDto,
): Promise<EvaluationDetailDto> {
  if (!sbAdmin) {
    throw new Error("Supabase admin client is not configured");
  }

  const evaluationId = dto.evaluation_id;
  const org_id = dto.org_id;
  if (!org_id) {
    throw new Error("org_id (UUID) is required");
  }

  const { data: evaluationRow, error: evaluationError } = await sbAdmin
    .from("evaluations")
    .select("id")
    .eq("id", evaluationId)
    .eq("org_id", org_id)
    .maybeSingle();

  if (evaluationError) {
    throw evaluationError;
  }

  if (!evaluationRow) {
    throw new Error("Evaluation not found");
  }

  // 1) Optionally patch the evaluation header row
  const patch: Record<string, unknown> = {};
  if (dto.org_id !== undefined) patch.org_id = dto.org_id;
  if (dto.template_id !== undefined) patch.template_id = dto.template_id;
  if (dto.team_id !== undefined) patch.teams_id = dto.team_id;
  if (dto.coach_id !== undefined) patch.coach_id = dto.coach_id;
  if (dto.notes !== undefined) patch.notes = dto.notes;

  if (Object.keys(patch).length > 0) {
    const { error: headerError } = await sbAdmin
      .from("evaluations")
      .update(patch)
      .eq("id", evaluationId)
      .eq("org_id", org_id);

    if (headerError) {
      console.error(
        "[applyEvaluationMatrixUpdateService] header update error",
        headerError,
      );
      throw headerError;
    }
  }

  // 2) Apply item-level operations
  for (const op of dto.operations) {
    if (op.type === "remove_athlete") {
      const { error } = await sbAdmin
        .from("evaluation_items")
        .delete()
        .eq("evaluation_id", evaluationId)
        .eq("athlete_id", op.athlete_id);

      if (error) {
        console.error(
          "[applyEvaluationMatrixUpdateService] remove_athlete error",
          error,
        );
        throw error;
      }
      continue;
    }

    if (op.type === "upsert_rating") {
      // rating null => delete row for this (evaluation, athlete, subskill)
      if (
        op.rating === null ||
        op.rating === undefined ||
        Number.isNaN(Number(op.rating))
      ) {
        const { error } = await sbAdmin
          .from("evaluation_items")
          .delete()
          .eq("evaluation_id", evaluationId)
          .eq("athlete_id", op.athlete_id)
          .eq("subskill_id", op.subskill_id);

        if (error) {
          console.error(
            "[applyEvaluationMatrixUpdateService] delete rating error",
            error,
          );
          throw error;
        }
        continue;
      }

      const rating = Number(op.rating);

      // Check if item exists
      const { data: existing, error: selectError } = await sbAdmin
        .from("evaluation_items")
        .select("id")
        .eq("evaluation_id", evaluationId)
        .eq("athlete_id", op.athlete_id)
        .eq("subskill_id", op.subskill_id)
        .maybeSingle();

      if (selectError) {
        console.error(
          "[applyEvaluationMatrixUpdateService] select existing item error",
          selectError,
        );
        throw selectError;
      }

      if (existing) {
        // UPDATE existing
        const { error: updateError } = await sbAdmin
          .from("evaluation_items")
          .update({
            rating,
            comment: op.comments ?? null,
          })
          .eq("id", existing.id);

        if (updateError) {
          console.error(
            "[applyEvaluationMatrixUpdateService] update rating error",
            updateError,
          );
          throw updateError;
        }
      } else {
        // INSERT new
        const { error: insertError } = await sbAdmin.from("evaluation_items").insert({
          evaluation_id: evaluationId,
          athlete_id: op.athlete_id,
          subskill_id: op.subskill_id,
          rating,
          comment: op.comments ?? null,
          recommended_skill_id: null,
        });

        if (insertError) {
          console.error(
            "[applyEvaluationMatrixUpdateService] insert rating error",
            insertError,
          );
          throw insertError;
        }
      }
    }
  }

  // 3) Return the fresh evaluation detail (same shape as GET /eval/:id)
  const updated = await getEvaluationById(evaluationId, org_id);
  if (!updated) {
    throw new Error("Evaluation not found after matrix update");
  }

  return updated;
}

export async function submitEvaluation(
  evaluationId: string,
  org_id: string,
): Promise<SubmitEvaluationResult> {
  // 1) Update only if it isn't already completed (idempotent)
  const { data: updated, error: updateErr } = await sbAdmin!
    .from('evaluations')
    .update({ status: 'completed' })
    .eq('id', evaluationId)
    .eq('org_id', org_id)
    .in('status', ['not_started', 'in_progress'])
    .select('id, status');

  if (updateErr) return { ok: false, error: updateErr };

  if (updated && updated.length > 0) {
    return { ok: true, data: updated[0] };
  }

  // 2) If nothing updated, fetch existing row (already completed or not found)
  const { data: existingRows, error: getErr } = await sbAdmin!
    .from('evaluations')
    .select('id, status')
    .eq('id', evaluationId)
    .eq('org_id', org_id);

  if (getErr) return { ok: false, error: getErr };

  const existing = (existingRows ?? [])[0] ?? null;
  if (!existing) return { ok: false, error: new Error('Evaluation not found') };

  return { ok: true, data: existing };
}
