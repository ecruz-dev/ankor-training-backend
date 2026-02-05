import { badRequest, json, notFound, serverError } from "../utils/responses.ts";
import { getSkillById, listSkills } from "../services/skills.service.ts";
import type { RequestContext } from "../routes/router.ts";
import { isUuid } from "../utils/uuid.ts";

export async function handleSkillsList(
  req: Request,
  origin: string | null,
  _params?: Record<string, string>,
  ctx?: RequestContext,
) {
  if (req.method !== "GET") return badRequest("Method not allowed", origin);

  const url = new URL(req.url);
  const org_id = ctx?.org_id ?? url.searchParams.get("org_id") ?? "";
  const sport_id = url.searchParams.get("sport_id") ?? "";
  const category = (url.searchParams.get("category") ?? "").trim();
  const q = (url.searchParams.get("q") ?? "").trim();
  const limit = Math.min(Math.max(parseInt(url.searchParams.get("limit") ?? "50", 10) || 50, 1), 200);
  const offset = Math.max(parseInt(url.searchParams.get("offset") ?? "0", 10) || 0, 0);

  if (!isUuid(org_id)) return badRequest("org_id (UUID) is required", origin);
  if (sport_id && !isUuid(sport_id)) return badRequest("sport_id must be a UUID if provided", origin);

  const { data, count, error } = await listSkills({
    org_id,
    sport_id: sport_id || undefined,
    category: category || undefined,
    q,
    limit,
    offset,
  });
  if (error) return serverError(error.message, origin);

  return json({ ok: true, count, items: data ?? [] }, origin, 200);
}

export async function handleSkillById(
  req: Request,
  origin: string | null,
  params?: Record<string, string>,
  ctx?: RequestContext,
) {
  if (req.method !== "GET") return badRequest("Method not allowed", origin);

  const skill_id = params?.id ?? "";
  if (!isUuid(skill_id)) return badRequest("id (UUID) is required", origin);

  const url = new URL(req.url);
  const org_id = ctx?.org_id ?? url.searchParams.get("org_id") ?? "";
  if (!isUuid(org_id)) return badRequest("org_id (UUID) is required", origin);

  const { data, error } = await getSkillById({ skill_id, org_id });
  if (error) {
    const message = error instanceof Error ? error.message : String(error);
    return serverError(message, origin);
  }

  if (!data) return notFound("Skill not found", origin);

  return json({ ok: true, skill: data }, origin, 200);
}
