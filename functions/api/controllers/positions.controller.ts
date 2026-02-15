import { badRequest, internalError, json, methodNotAllowed } from "../utils/http.ts";
import type { RequestContext } from "../routes/router.ts";
import { RE_UUID } from "../utils/uuid.ts";
import { listPositionsByOrgId } from "../services/positions.service.ts";

export async function handlePositionsList(
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

  const { data, error } = await listPositionsByOrgId(org_id);
  if (error) {
    console.error("[handlePositionsList] error", error);
    return internalError(error, "Failed to fetch positions");
  }

  const items = data ?? [];
  return json(200, { ok: true, count: items.length, data: items });
}
