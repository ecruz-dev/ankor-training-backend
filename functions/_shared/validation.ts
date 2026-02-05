// supabase/functions/_shared/validation.ts
import { z } from "https://esm.sh/zod@3.23.8";

export const passwordSchema = z
  .string()
  .min(8, "Password must be at least 8 characters")
  .regex(/[A-Za-z]/, "Password must include letters")
  .regex(/[0-9]/, "Password must include numbers");

export function dateNotInFuture(dateStr: string) {
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return false;
  return d <= new Date();
}
