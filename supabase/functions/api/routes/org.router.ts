// src/routes/org.router.ts
import { Router } from "./router.ts";
import {
  getOrganizationByIdController,
  handleOrgSignup,
  listOrganizationsController,
  updateOrganizationController,
} from "../controllers/org.controller.ts";
import { authMiddleware } from "../utils/auth.ts";
import { adminOrSysAdminGuard } from "../utils/guards.ts";

export function createOrgRouter(): Router {
  const router = new Router();
  const requireAuth = authMiddleware();
  const requireAdminOrSysAdmin = adminOrSysAdminGuard();

  // POST /api/org/signup
  router.add("POST", "signup", handleOrgSignup);

  // GET /api/org/list
  router.add("GET", "list", listOrganizationsController, [requireAuth, requireAdminOrSysAdmin]);

  // GET /api/org/:id
  router.add("GET", ":id", getOrganizationByIdController, [requireAuth, requireAdminOrSysAdmin]);

  // PATCH /api/org/:id
  router.add("PATCH", ":id", updateOrganizationController, [requireAuth, requireAdminOrSysAdmin]);

  return router;
}
