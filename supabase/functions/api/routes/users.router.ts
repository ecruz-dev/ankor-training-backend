import { Router } from "./router.ts";
import { listOrgUsersController } from "../controllers/users.controller.ts";
import { orgRoleGuardFromQuery } from "../utils/guards.ts";

export function createUsersRouter(): Router {
  const router = new Router();

  router.add(
    "GET",
    "list",
    listOrgUsersController,
    [orgRoleGuardFromQuery("org_id", ["coach", "athlete", "parent"])],
  );

  return router;
}

