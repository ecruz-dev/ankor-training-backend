// src/routes/org.router.ts
import { Router } from "./router.ts";
import {
  handleOrgSignup,
  listOrganizationsController,
  updateOrganizationController,
} from "../controllers/org.controller.ts";
import { authMiddleware } from "../utils/auth.ts";
import { sysAdminGuard } from "../utils/guards.ts";

export function createOrgRouter(): Router {
  const router = new Router();
  const requireAuth = authMiddleware();
  const requireSysAdmin = sysAdminGuard();

  // POST /api/org/signup
  router.add("POST", "signup", handleOrgSignup);

  // GET /api/org/list
  router.add("GET", "list", listOrganizationsController, [requireAuth, requireSysAdmin]);

  // PATCH /api/org/:id
  router.add("PATCH", ":id", updateOrganizationController, [requireAuth, requireSysAdmin]);

  return router;
}
