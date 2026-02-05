// src/dtos/team.dto.ts
import { z } from "https://esm.sh/zod@3.23.8";
import { RE_UUID } from "../utils/uuid.ts";

const uuid = () => z.string().regex(RE_UUID, "Invalid UUID");

export const CreateTeamSchema = z.object({
  org_id: uuid(),
  sport_id: uuid().optional().nullable(),
  name: z.string().trim().min(1, "name is required"),
  is_active: z.boolean().optional().default(true),
});

export const UpdateTeamSchema = z
  .object({
    sport_id: uuid().optional().nullable(),
    name: z.string().trim().min(1).optional(),
    is_active: z.boolean().optional(),
  })
  .superRefine((value, ctx) => {
    const hasUpdates = Object.values(value).some((val) => val !== undefined);
    if (!hasUpdates) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "No updates provided",
      });
    }
  });

export const GetTeamByIdSchema = z.object({
  team_id: uuid(),
});

export type CreateTeamInput = z.infer<typeof CreateTeamSchema>;
export type UpdateTeamInput = z.infer<typeof UpdateTeamSchema>;
export type GetTeamByIdInput = z.infer<typeof GetTeamByIdSchema>;

export type TeamDTO = {
  id: string;
  org_id: string;
  sport_id: string | null;
  name: string;
  is_active: boolean;
  created_at?: string | null;
  updated_at?: string | null;
};
