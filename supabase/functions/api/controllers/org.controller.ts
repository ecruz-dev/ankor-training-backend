import { badRequest, json, serverError } from "../utils/responses.ts";
import { sbAdmin } from "../services/supabase.ts";

type Body = {
  admin: { firstName: string; lastName: string; email: string; phone?: string | null; password: string };
  organization: { name: string; programGender: "girls" | "boys" | "coed" };
  teams?: Array<{ name: string }>;
};

export async function handleOrgSignup(req: Request, origin: string | null) {
  if (req.method !== "POST") return badRequest("Method not allowed", origin);

  const body = (await req.json().catch(() => null)) as Body | null;
  if (!body) return badRequest("Invalid JSON body", origin);

  const admin = body.admin;
  const org = body.organization;
  const teams = body.teams ?? [];
  if (!admin?.firstName || !admin?.lastName || !admin?.email || !admin?.password) {
    return badRequest("Missing admin fields", origin);
  }
  if (!org?.name || !["girls", "boys", "coed"].includes(org.programGender)) {
    return badRequest("Invalid organization data", origin);
  }

  const { data: created, error: createErr } = await sbAdmin!.auth.admin.createUser({
    email: admin.email,
    password: admin.password,
    email_confirm: true,
    user_metadata: {
      first_name: admin.firstName,
      last_name: admin.lastName,
      role: "admin",
    },
  });
  if (createErr || !created?.user) {
    return badRequest(`Could not create user: ${createErr?.message}`, origin);
  }

  const userId = created.user.id;
  const teamNames = teams.map((t) => t?.name?.trim()).filter(Boolean);

  const { data: rpcData, error: rpcErr } = await sbAdmin!.rpc("signup_register_org_tx", {
    p_user_id: userId,
    p_first_name: admin.firstName,
    p_last_name: admin.lastName,
    p_email: admin.email,
    p_phone: admin.phone ?? null,
    p_org_name: org.name,
    p_program_gender: org.programGender,
    p_team_names: teamNames,
  });

  if (rpcErr || !rpcData?.length) {
    await sbAdmin!.auth.admin.deleteUser(userId).catch(() => {});
    return serverError(`Signup failed: ${rpcErr?.message ?? "RPC returned no data"}`, origin);
  }

  const result = rpcData[0];
  return json({ ok: true, userId, orgId: result.org_id, profileId: result.profile_id, teamIds: result.team_ids ?? [] }, origin, 201);
}
