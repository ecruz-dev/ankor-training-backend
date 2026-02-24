import { sbAdmin } from "./supabase.ts";
import {
  type CreateSkillInput,
  type SkillMediaCreateInput,
  type SkillMediaRecordDto,
  type SkillMediaUploadInput,
  type SkillMediaUploadResult,
} from "../dtos/skills.dto.ts";
import { SKILLS_MEDIA_BUCKET } from "../config/env.ts";

function toNullableTrimmed(value?: string | null): string | null {
  if (value === undefined || value === null) return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

const EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  "video/mp4": ".mp4",
  "video/quicktime": ".mov",
  "video/webm": ".webm",
  "video/ogg": ".ogv",
  "image/jpeg": ".jpg",
  "image/png": ".png",
  "image/webp": ".webp",
  "application/pdf": ".pdf",
};

function sanitizeFileName(name: string): string {
  const base = name.trim().split(/[\\/]/).pop() ?? "upload";
  const safe = base.replace(/[^a-zA-Z0-9._-]/g, "_");
  return safe.length ? safe : "upload";
}

function inferExtension(fileName: string, contentType: string): string {
  const match = fileName.match(/\.([a-z0-9]{1,10})$/i);
  if (match) {
    return `.${match[1].toLowerCase()}`;
  }

  const mapped = EXTENSION_BY_CONTENT_TYPE[contentType.toLowerCase()];
  return mapped ?? ".bin";
}

function buildSkillMediaPath(input: {
  org_id: string;
  skill_id: string;
  file_name: string;
  content_type: string;
}): string {
  const safeName = sanitizeFileName(input.file_name);
  const extension = inferExtension(safeName, input.content_type);
  const fileId = crypto.randomUUID();
  return `orgs/${input.org_id}/skills/${input.skill_id}/${fileId}${extension}`;
}

function resolveSkillsBucket(value?: string | null): string | null {
  if (!value) return SKILLS_MEDIA_BUCKET;
  const trimmed = value.trim();
  if (!trimmed) return SKILLS_MEDIA_BUCKET;

  const normalized = trimmed.toLowerCase();
  const target = SKILLS_MEDIA_BUCKET.toLowerCase();
  if (normalized === target) return SKILLS_MEDIA_BUCKET;
  if (normalized === "skills_media" || normalized === "skills-media") {
    return SKILLS_MEDIA_BUCKET;
  }
  if (trimmed.toUpperCase() === "SKILLS_MEDIA") return SKILLS_MEDIA_BUCKET;

  return null;
}

async function ensureSkillOrg(
  skill_id: string,
  org_id: string,
): Promise<{ error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { error: new Error("Supabase client not initialized") };
  }

  const { data, error } = await client
    .from("skills")
    .select("id")
    .eq("id", skill_id)
    .eq("org_id", org_id)
    .maybeSingle();

  if (error) {
    return { error };
  }

  if (!data) {
    return { error: new Error("Skill not found") };
  }

  return { error: null };
}

function mapSkillMediaRow(
  row: any,
  fallbackBucket: string | null,
): SkillMediaRecordDto {
  const bucket = typeof row?.bucket === "string" ? row.bucket : fallbackBucket;
  const position = typeof row?.position === "number"
    ? row.position
    : typeof row?.sort_order === "number"
    ? row.sort_order
    : null;

  return {
    id: row?.id ?? "",
    skill_id: row?.skill_id ?? "",
    bucket: bucket ?? null,
    object_path: row?.object_path ?? "",
    title: row?.title ?? null,
    description: row?.description ?? null,
    thumbnail_url: row?.thumbnail_url ?? null,
    position,
  };
}

export async function listSkills(params: {
  org_id: string;
  sport_id?: string;
  category?: string;
  q?: string;
  limit?: number;
  offset?: number;
}) {
  const { org_id, sport_id, category, q, limit = 50, offset = 0 } = params;

  let query = sbAdmin!
    .from("skills")
    .select(
      "id, org_id, sport_id, category, title, description, level, visibility, status, created_at, updated_at",
      { count: "exact" }
    )
    .eq("org_id", org_id)
    .order("title", { ascending: true })
    .range(offset, offset + (limit - 1));

  if (sport_id) query = query.eq("sport_id", sport_id);
  if (category?.trim()) query = query.ilike("category", category.trim());
  if (q?.trim()) query = query.or(`title.ilike.%${q}%,category.ilike.%${q}%`);

  return await query;
}

export async function getSkillById(params: {
  skill_id: string;
  org_id: string;
}) {
  const { skill_id, org_id } = params;

  return await sbAdmin!
    .from("skills")
    .select(
      "id, org_id, sport_id, category, title, description, level, visibility, status, created_at, updated_at",
    )
    .eq("id", skill_id)
    .eq("org_id", org_id)
    .maybeSingle();
}

export async function createSkill(
  input: CreateSkillInput,
): Promise<{ data: any | null; error: unknown }> {
  if (!sbAdmin) {
    return { data: null, error: new Error("Supabase client not initialized") };
  }

  const payload = {
    org_id: input.org_id,
    sport_id: input.sport_id ?? null,
    category: input.category.trim(),
    title: input.title.trim(),
    description: toNullableTrimmed(input.description),
    level: toNullableTrimmed(input.level),
    visibility: toNullableTrimmed(input.visibility),
    status: toNullableTrimmed(input.status),
  };

  const { data, error } = await sbAdmin
    .from("skills")
    .insert(payload)
    .select(
      "id, org_id, sport_id, category, title, description, level, visibility, status, created_at, updated_at",
    )
    .maybeSingle();

  if (error) return { data: null, error };
  if (!data) return { data: null, error: new Error("Failed to create skill") };

  return { data, error: null };
}

export async function createSkillMediaUploadUrl(
  input: SkillMediaUploadInput,
): Promise<{ data: SkillMediaUploadResult | null; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: null, error: new Error("Supabase client not initialized") };
  }

  const { error: skillError } = await ensureSkillOrg(input.skill_id, input.org_id);
  if (skillError) {
    return { data: null, error: skillError };
  }

  const path = buildSkillMediaPath(input);
  const bucket = SKILLS_MEDIA_BUCKET;

  const { data, error } = await client.storage
    .from(bucket)
    .createSignedUploadUrl(path);

  if (error || !data?.signedUrl || !data.token) {
    return { data: null, error: error ?? new Error("Failed to create upload URL") };
  }

  const publicResult = client.storage.from(bucket).getPublicUrl(path);
  const public_url = publicResult.data?.publicUrl ?? "";

  return {
    data: {
      bucket,
      object_path: path,
      signed_url: data.signedUrl,
      token: data.token,
      public_url,
    },
    error: null,
  };
}

export async function createSkillMedia(
  input: SkillMediaCreateInput,
): Promise<{ data: SkillMediaRecordDto | null; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: null, error: new Error("Supabase client not initialized") };
  }

  const { error: skillError } = await ensureSkillOrg(input.skill_id, input.org_id);
  if (skillError) {
    return { data: null, error: skillError };
  }

  const bucket = resolveSkillsBucket(input.bucket);
  if (!bucket) {
    return { data: null, error: new Error("Invalid bucket") };
  }

  const payload: Record<string, unknown> = {
    skill_id: input.skill_id,
    bucket,
    object_path: input.object_path.trim(),
  };

  if (input.title !== undefined) payload.title = input.title ?? null;
  if (input.description !== undefined) payload.description = input.description ?? null;
  if (input.thumbnail_url !== undefined) payload.thumbnail_url = input.thumbnail_url ?? null;
  if (input.position !== undefined) payload.position = input.position ?? null;

  const optionalColumns = ["bucket", "title", "description", "thumbnail_url", "position"];
  let attemptPayload = { ...payload };

  for (let i = 0; i <= optionalColumns.length; i += 1) {
    const { data, error } = await client
      .from("skill_video_map")
      .insert(attemptPayload)
      .select("*")
      .maybeSingle();

    if (!error) {
      return { data: data ? mapSkillMediaRow(data, bucket) : null, error: null };
    }

    const message = error instanceof Error ? error.message : String(error);
    const missing = optionalColumns.find((col) => message.includes(`column "${col}"`));
    if (!missing) {
      return { data: null, error };
    }
    const { [missing]: _removed, ...rest } = attemptPayload;
    attemptPayload = rest;
  }

  return { data: null, error: new Error("Failed to create skill media") };
}
