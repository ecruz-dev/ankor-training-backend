// src/routes/auth.router.ts
import { Router } from "./router.ts";
import { handleAuthLogin, handleAuthSignup, handleTestWelcomeEmail } from "../controllers/auth.controller.ts";
import { authMiddleware } from "../utils/auth.ts";

export function createAuthRouter(): Router {
  const router = new Router();
  const requireAuth = authMiddleware();

  // POST /api/auth/signup
  router.add("POST", "signup", handleAuthSignup);
  // POST /api/auth/login
  router.add("POST", "login", handleAuthLogin);
  // POST /api/auth/welcome-email/test
  router.add("POST", "welcome-email/test", handleTestWelcomeEmail, [requireAuth]);

  return router;
}
