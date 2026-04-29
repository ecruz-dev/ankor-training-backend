import { internalError, json, methodNotAllowed } from "../utils/http.ts";
import { listSports } from "../services/sports.service.ts";

export async function handleSportsList(req: Request): Promise<Response> {
  if (req.method !== "GET") {
    return methodNotAllowed(["GET"]);
  }

  const { data, error } = await listSports();
  if (error) {
    console.error("[handleSportsList] error", error);
    return internalError(error, "Failed to fetch sports");
  }

  const items = data ?? [];
  return json(200, { ok: true, count: items.length, data: items });
}
