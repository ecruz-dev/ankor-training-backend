// src/routes/skills.router.ts
import { Router } from "./router.ts";
import { handleSkillById, handleSkillsList } from "../controllers/skills.controller.ts";
import { orgRoleGuardFromQuery } from "../utils/guards.ts";

export function createSkillsRouter(): Router {
  const router = new Router();

  // GET /api/skills/list
  router.add(
    "GET",
    "list",
    handleSkillsList,
    [orgRoleGuardFromQuery("org_id", ["coach", "athlete", "parent"])],
  );
  router.add(
    "GET",
    ":id",
    handleSkillById,
    [orgRoleGuardFromQuery("org_id", ["coach", "athlete", "parent"])],
  );

  return router;
}

