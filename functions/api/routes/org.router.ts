// src/routes/org.router.ts
import { Router } from "./router.ts";
import { handleOrgSignup } from "../controllers/org.controller.ts";

export function createOrgRouter(): Router {
  const router = new Router();

  // POST /api/org/signup
  router.add("POST", "signup", handleOrgSignup);

  return router;
}
