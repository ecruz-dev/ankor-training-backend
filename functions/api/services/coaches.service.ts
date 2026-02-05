import { sbAdmin } from "./supabase.ts";
import type {
  CoachDto,
  CoachListFilterInput,
  CreateCoachInput,
  UpdateCoachInput,
} from "../dtos/coaches.dto.ts";

function buildFullName(first?: string | null, last?: string | null): string | null {
  const parts = [first?.trim(), last?.trim()].filter((part) => part && part.length > 0) as string[];
  if (parts.length === 0) return null;
  return parts.join(" ");
}

function mapCoachRow(row: any): CoachDto {
  const profile = row.profile ?? null;
  return {
    id: row.id,
    org_id: row.org_id ?? null,
    user_id: row.user_id ?? null,
    first_name: profile?.first_name ?? null,
    last_name: profile?.last_name ?? null,
    full_name: row.full_name ?? profile?.full_name ?? null,
    email: profile?.email ?? row.email ?? null,
    phone: row.phone ?? null,
    cell_number: row.cell_number ?? null,
  };
}

export async function listCoaches(
  filters: CoachListFilterInput,
): Promise<{ data: CoachDto[]; count: number; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: [], count: 0, error: new Error("Supabase client not initialized") };
  }

  const { org_id, name, email, limit, offset } = filters;
  const rangeTo = offset + (limit - 1);

  let query = client
    .from("coaches")
    .select(
      `
      id,
      org_id,
      user_id,
      email,
      full_name,
      phone,
      cell_number,
      profile:profiles(email, first_name, last_name, full_name)
    `,
      { count: "exact" },
    )
    .eq("org_id", org_id)
    .range(offset, rangeTo)
    .order("full_name", { ascending: true });

  if (name) {
    query = query.ilike("full_name", `%${name}%`);
  }
  if (email) {
    query = query.ilike("profiles.email", `%${email}%`);
  }

  const { data, error, count } = await query;
  if (error) return { data: [], count: 0, error };

  const items = (data ?? []).map((row: any) => mapCoachRow(row));
  return { data: items, count: count ?? items.length, error: null };
}

export async function getCoachById(
  coach_id: string,
  org_id: string,
): Promise<{ data: CoachDto | null; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: null, error: new Error("Supabase client not initialized") };
  }

  const { data, error } = await client
    .from("coaches")
    .select(
      `
      id,
      org_id,
      user_id,
      email,
      full_name,
      phone,
      cell_number,
      profile:profiles(email, first_name, last_name, full_name)
    `,
    )
    .eq("id", coach_id)
    .eq("org_id", org_id)
    .maybeSingle();

  if (error) return { data: null, error };

  return { data: data ? mapCoachRow(data) : null, error: null };
}

export async function createCoach(
  input: CreateCoachInput,
): Promise<{ data: CoachDto | null; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: null, error: new Error("Supabase client not initialized") };
  }

  const full_name = input.full_name?.trim() || null;

  const { data: created, error: createErr } = await client.auth.admin.createUser({
    email: input.email,
    password: input.password,
    user_metadata: {
      full_name,
      cell_number: input.cell_number ?? null,
    },
    app_metadata: { role: "coach" },
    email_confirm: true,
  });

  if (createErr) {
    return { data: null, error: createErr };
  }

  const userId = created.user?.id ?? null;
  if (!userId) {
    return { data: null, error: new Error("User was not returned by Supabase") };
  }

  const { data: txData, error: txErr } = await client.rpc("create_coach_tx", {
    p_user_id: userId,
    p_org_id: input.org_id,
    p_first_name: null,
    p_last_name: null,
    p_full_name: full_name,
    p_email: input.email,
    p_phone: input.phone ?? null,
    p_cell_number: input.cell_number ?? null,
  });

  if (txErr) {
    await client.auth.admin.deleteUser(userId).catch(() => {});
    return { data: null, error: txErr };
  }

  const coachId =
    typeof txData === "string"
      ? txData
      : Array.isArray(txData)
      ? txData[0]?.coach_id ?? null
      : (txData as any)?.coach_id ?? null;

  if (!coachId) {
    await client.auth.admin.deleteUser(userId).catch(() => {});
    return { data: null, error: new Error("Failed to create coach") };
  }

  const coachResult = await getCoachById(coachId, input.org_id);
  if (coachResult.error || !coachResult.data) {
    await client
      .from("coaches")
      .delete()
      .eq("id", coachId)
      .eq("org_id", input.org_id)
      .catch(() => {});
    await client.auth.admin.deleteUser(userId).catch(() => {});
    return {
      data: null,
      error: coachResult.error ?? new Error("Failed to load created coach"),
    };
  }

  return coachResult;
}

export async function updateCoach(
  coach_id: string,
  org_id: string,
  input: UpdateCoachInput,
): Promise<{ data: CoachDto | null; error: unknown }> {
  const client = sbAdmin;
  if (!client) {
    return { data: null, error: new Error("Supabase client not initialized") };
  }

  const patch: Record<string, unknown> = {};
  if (input.user_id !== undefined) patch.user_id = input.user_id;
  if (input.full_name !== undefined) patch.full_name = input.full_name;
  if (input.phone !== undefined) patch.phone = input.phone;
  if (input.cell_number !== undefined) patch.cell_number = input.cell_number;

  if (Object.keys(patch).length > 0) {
    const { data, error } = await client
      .from("coaches")
      .update(patch)
      .eq("id", coach_id)
      .eq("org_id", org_id)
      .select("id");

    if (error) return { data: null, error };
    if (!data || data.length === 0) {
      return { data: null, error: new Error("Coach not found") };
    }
  } else {
    const { data, error } = await client
      .from("coaches")
      .select("id")
      .eq("id", coach_id)
      .eq("org_id", org_id);

    if (error) return { data: null, error };
    if (!data || data.length === 0) {
      return { data: null, error: new Error("Coach not found") };
    }
  }

  return await getCoachById(coach_id, org_id);
}
