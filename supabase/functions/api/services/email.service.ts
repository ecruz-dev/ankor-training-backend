import { INVITE_REDIRECT_URL, RESEND_API_KEY, RESEND_FROM } from "../config/env.ts";
import { sbAdmin } from "./supabase.ts";

type AuthLinkType = "invite" | "magiclink" | "recovery" | "signup";

type AuthLinkOptions = {
  type?: AuthLinkType;
  redirectTo?: string;
  data?: Record<string, unknown>;
};

type WelcomeEmailOptions = {
  from?: string;
  subject?: string;
};

function requireValue(value: string, name: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    throw new Error(`${name} is required`);
  }
  return trimmed;
}

function escapeHtml(input: string): string {
  return input.replace(/[&<>"']/g, (char) => {
    switch (char) {
      case "&":
        return "&amp;";
      case "<":
        return "&lt;";
      case ">":
        return "&gt;";
      case "\"":
        return "&quot;";
      case "'":
        return "&#39;";
      default:
        return char;
    }
  });
}

export async function generateAuthLink(
  email: string,
  options: AuthLinkOptions = {},
): Promise<{ actionLink: string; userId: string | null }> {
  const client = sbAdmin;
  if (!client) {
    throw new Error("Supabase client not initialized");
  }

  const emailValue = requireValue(email, "email").toLowerCase();
  const redirectTo = options.redirectTo ?? INVITE_REDIRECT_URL;
  const type: AuthLinkType = options.type ?? "invite";

  const payload: Record<string, unknown> = {
    type,
    email: emailValue,
  };

  const optionsPayload: Record<string, unknown> = {};
  if (redirectTo && redirectTo.trim().length > 0) {
    optionsPayload.redirectTo = redirectTo.trim();
  }
  if (options.data && Object.keys(options.data).length > 0) {
    optionsPayload.data = options.data;
  }
  if (Object.keys(optionsPayload).length > 0) {
    payload.options = optionsPayload;
  }

  const { data, error } = await client.auth.admin.generateLink(payload as any);
  if (error) {
    throw error;
  }

  const actionLink =
    (data as any)?.properties?.action_link ??
    (data as any)?.action_link ??
    "";

  if (!actionLink) {
    throw new Error("Auth link was not returned by Supabase");
  }

  return { actionLink, userId: (data as any)?.user?.id ?? null };
}

export async function generateInviteLink(
  email: string,
  options: Omit<AuthLinkOptions, "type"> = {},
): Promise<{ actionLink: string; userId: string | null }> {
  return await generateAuthLink(email, { ...options, type: "invite" });
}

export async function generateMagicLink(
  email: string,
  options: Omit<AuthLinkOptions, "type"> = {},
): Promise<{ actionLink: string; userId: string | null }> {
  return await generateAuthLink(email, { ...options, type: "magiclink" });
}

export async function sendWelcomeEmail(
  to: string,
  fullName: string | null,
  actionLink: string,
  options: WelcomeEmailOptions = {},
): Promise<void> {
  const apiKey = requireValue(RESEND_API_KEY, "RESEND_API_KEY");
  const from = requireValue(options.from ?? RESEND_FROM, "RESEND_FROM");
  const recipient = requireValue(to, "to");
  const link = requireValue(actionLink, "actionLink");

  const safeName = fullName?.trim() ?? "";
  const nameSuffix = safeName ? `, ${escapeHtml(safeName)}` : "";
  const safeLink = escapeHtml(link);

  const html = `
    <div style="font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial;">
      <h2>Welcome to ANKOR${nameSuffix}</h2>
      <p>Your account is ready. Click below to finish setup:</p>
      <p><a href="${safeLink}" style="display:inline-block;padding:12px 16px;background:#111;color:#fff;border-radius:10px;text-decoration:none">
        Finish setup
      </a></p>
      <p>If the button does not work, copy/paste this link:</p>
      <p>${safeLink}</p>
    </div>
  `;

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      from,
      to: recipient,
      subject: options.subject ?? "Welcome to ANKOR",
      html,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Resend failed: ${res.status} ${body}`);
  }
}

export async function inviteUserAndSendWelcome(
  params: {
    email: string;
    fullName?: string | null;
    redirectTo?: string;
    data?: Record<string, unknown>;
    from?: string;
    subject?: string;
  },
): Promise<{ actionLink: string; userId: string | null }> {
  const { email, fullName, redirectTo, data, from, subject } = params;
  const { actionLink, userId } = await generateInviteLink(email, {
    redirectTo,
    data,
  });
  await sendWelcomeEmail(email, fullName ?? null, actionLink, { from, subject });
  return { actionLink, userId };
}
