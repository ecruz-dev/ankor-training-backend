// src/routes/skills.router.ts
import { Router } from "./router.ts";
import {
  handleSkillById,
  handleSkillCreate,
  handleSkillMediaCreate,
  handleSkillMediaUploadUrl,
  handleSkillsList,
} from "../controllers/skills.controller.ts";
import { orgRoleGuardFromBody, orgRoleGuardFromQuery } from "../utils/guards.ts";

export function createSkillsRouter(): Router {
  const router = new Router();

  router.add(
    "POST",
    "",
    handleSkillCreate,
    [orgRoleGuardFromBody("org_id", ["coach"])],
  );
  router.add(
    "POST",
    "media/upload-url",
    handleSkillMediaUploadUrl,
    [orgRoleGuardFromBody("org_id", ["coach"])],
  );
  router.add(
    "POST",
    "media",
    handleSkillMediaCreate,
    [orgRoleGuardFromBody("org_id", ["coach"])],
  );
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

