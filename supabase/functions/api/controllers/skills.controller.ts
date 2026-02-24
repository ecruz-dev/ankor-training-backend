import { badRequest, json, notFound, serverError } from "../utils/responses.ts";
import {
  CreateSkillSchema,
  SkillMediaCreateSchema,
  SkillMediaUploadSchema,
} from "../dtos/skills.dto.ts";
import {
  createSkill,
  createSkillMedia,
  createSkillMediaUploadUrl,
  getSkillById,
  listSkills,
} from "../services/skills.service.ts";
import type { RequestContext } from "../routes/router.ts";
import { isUuid } from "../utils/uuid.ts";

function inferSkillMediaType(contentType: string): "video" | "image" | "document" {
  const normalized = contentType.toLowerCase();
  if (normalized.startsWith("video/")) return "video";
  if (normalized.startsWith("image/")) return "image";
  return "document";
}

export async function handleSkillCreate(
  req: Request,
  origin: string | null,
  _params?: Record<string, string>,
  ctx?: RequestContext,
) {
  if (req.method !== "POST") return badRequest("Method not allowed", origin);

  const raw = await req.json().catch(() => null);
  if (!raw || typeof raw !== "object") {
    return badRequest("Invalid JSON payload", origin);
  }

  const parsed = CreateSkillSchema.safeParse(raw);
  if (!parsed.success) {
    const message = parsed.error.issues.map((issue) => issue.message).join("; ");
    return badRequest(message, origin);
  }

  if (ctx?.org_id && ctx.org_id !== parsed.data.org_id) {
    return badRequest("org_id does not match authorized organization", origin);
  }

  const { data, error } = await createSkill(parsed.data);
  if (error) {
    const message = error instanceof Error ? error.message : String(error);
    return serverError(message, origin);
  }

  return json({ ok: true, skill: data }, origin, 201);
}

export async function handleSkillMediaUploadUrl(
  req: Request,
  origin: string | null,
  _params?: Record<string, string>,
  ctx?: RequestContext,
) {
  if (req.method !== "POST") return badRequest("Method not allowed", origin);

  const raw = await req.json().catch(() => null);
  if (!raw || typeof raw !== "object") {
    return badRequest("Invalid JSON payload", origin);
  }

  const parsed = SkillMediaUploadSchema.safeParse(raw);
  if (!parsed.success) {
    const message = parsed.error.issues.map((issue) => issue.message).join("; ");
    return badRequest(message, origin);
  }

  if (ctx?.org_id && ctx.org_id !== parsed.data.org_id) {
    return badRequest("org_id does not match authorized organization", origin);
  }

  const { data, error } = await createSkillMediaUploadUrl(parsed.data);
  if (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.toLowerCase().includes("not found")) {
      return notFound("Skill not found", origin);
    }
    return serverError(message, origin);
  }

  const media = {
    type: inferSkillMediaType(parsed.data.content_type),
    url: data!.public_url,
    title: parsed.data.title ?? null,
    description: parsed.data.description ?? null,
    thumbnail_url: parsed.data.thumbnail_url ?? null,
    position: parsed.data.position ?? null,
  };

  return json({ ok: true, upload: data, media }, origin, 201);
}

export async function handleSkillMediaCreate(
  req: Request,
  origin: string | null,
  _params?: Record<string, string>,
  ctx?: RequestContext,
) {
  if (req.method !== "POST") return badRequest("Method not allowed", origin);

  const raw = await req.json().catch(() => null);
  if (!raw || typeof raw !== "object") {
    return badRequest("Invalid JSON payload", origin);
  }

  const parsed = SkillMediaCreateSchema.safeParse(raw);
  if (!parsed.success) {
    const message = parsed.error.issues.map((issue) => issue.message).join("; ");
    return badRequest(message, origin);
  }

  if (ctx?.org_id && ctx.org_id !== parsed.data.org_id) {
    return badRequest("org_id does not match authorized organization", origin);
  }

  const { data, error } = await createSkillMedia(parsed.data);
  if (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.toLowerCase().includes("not found")) {
      return notFound("Skill not found", origin);
    }
    return serverError(message, origin);
  }

  return json({ ok: true, media: data }, origin, 201);
}

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
