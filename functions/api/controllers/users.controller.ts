import { listOrgUsers } from "../services/users.service.ts";
import {
  badRequest,
  internalError,
  json,
  methodNotAllowed,
} from "../utils/http.ts";
import type { RequestContext } from "../routes/router.ts";
import { RE_UUID } from "../utils/uuid.ts";

export async function listOrgUsersController(
  req: Request,
  _origin?: string | null,
  _params?: Record<string, string>,
  ctx?: RequestContext,
): Promise<Response> {
  if (req.method !== "GET") {
    return methodNotAllowed(["GET"]);
  }

  const url = new URL(req.url);
  const org_id = (ctx?.org_id ?? url.searchParams.get("org_id") ?? "").trim();
  if (!RE_UUID.test(org_id)) {
    return badRequest("org_id (UUID) is required");
  }

  const { data, count, error } = await listOrgUsers(org_id);
  if (error) {
    console.error("[listOrgUsersController] list error", error);
    return internalError(error, "Failed to list users");
  }

  return json(200, { ok: true, count, items: data });
}
