import type { Middleware, RequestContext } from "../routes/router.ts";
import { sbAdmin, sbAnon } from "../services/supabase.ts";
import { forbidden, unauthorized } from "./http.ts";

const ORG_ROLES = ["owner", "admin", "coach", "athlete", "parent"] as const;
export type OrgRole = (typeof ORG_ROLES)[number];

export type AuthUser = {
  id: string;
  email: string | null;
};

function getBearerToken(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  return match[1].trim() || null;
}

export function isAdminRole(role: OrgRole): boolean {
  return role === "owner" || role === "admin";
}

export async function requireAuthUser(
  req: Request,
): Promise<{ user: AuthUser } | { response: Response }> {
  const token = getBearerToken(req);
  if (!token) return { response: unauthorized("Missing bearer token") };
  if (!sbAnon) return { response: unauthorized("Auth client not configured") };

  const { data, error } = await sbAnon.auth.getUser(token);
  if (error || !data?.user) {
    return { response: unauthorized("Invalid or expired token") };
  }

  return {
    user: {
      id: data.user.id,
      email: data.user.email ?? null,
    },
  };
}

async function ensureUser(
  req: Request,
  ctx: RequestContext,
): Promise<{ user: AuthUser } | { response: Response }> {
  if (ctx.user) return { user: ctx.user };
  const auth = await requireAuthUser(req);
  if ("response" in auth) return auth;
  ctx.user = auth.user;
  return auth;
}

export function authMiddleware(): Middleware {
  return async (req, _origin, _params, ctx) => {
    const auth = await ensureUser(req, ctx);
    if ("response" in auth) return auth.response;
    return null;
  };
}

async function getOrgRole(
  userId: string,
  orgId: string,
): Promise<OrgRole | null> {
  const client = sbAdmin;
  if (!client) return null;

  const { data, error } = await client
    .from("org_memberships")
    .select("role, is_active")
    .eq("org_id", orgId)
    .eq("user_id", userId)
    .eq("is_active", true)
    .maybeSingle();

  if (error || !data?.role || !data.is_active) return null;
  if (!ORG_ROLES.includes(data.role as OrgRole)) return null;
  return data.role as OrgRole;
}

function hasRoleAccess(role: OrgRole, allowedRoles: OrgRole[]): boolean {
  if (isAdminRole(role)) return true;
  return allowedRoles.includes(role);
}

export async function requireOrgRole(
  userId: string,
  orgId: string,
  allowedRoles: OrgRole[],
): Promise<{ role: OrgRole } | { response: Response }> {
  const role = await getOrgRole(userId, orgId);
  if (!role) {
    return { response: forbidden("No access to this organization") };
  }
  if (!hasRoleAccess(role, allowedRoles)) {
    return { response: forbidden("Insufficient role for this action") };
  }
  return { role };
}
