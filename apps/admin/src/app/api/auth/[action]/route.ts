import { type NextRequest } from "next/server";

import {
  backend,
  clearSessionCookies,
  COOKIE,
  csrfValid,
  forwardedFor,
  json,
  readJson,
  refreshTokens,
  sameOrigin,
  setSessionCookies,
  type Scope,
} from "@/lib/server/session";

export const dynamic = "force-dynamic";

const WORKSPACE_RE = /^[A-Za-z0-9_-]{3,64}$/;

function bad(code: string, detail: string, status = 400) {
  return json({ code, detail }, status);
}

async function body(req: NextRequest): Promise<Record<string, string>> {
  try {
    const data = (await req.json()) as Record<string, unknown>;
    return Object.fromEntries(Object.entries(data).map(([k, v]) => [k, typeof v === "string" ? v : String(v ?? "")]));
  } catch {
    return {};
  }
}

/** The operator workspace is the client id of a registered *admin* application (trusted app context). */
async function adminApp(workspace: string | undefined) {
  if (!workspace || !WORKSPACE_RE.test(workspace)) return null;
  const res = await backend("auth/app-context", { headers: { "X-RideFlow-App": workspace } });
  if (!res.ok) return null;
  const data = await readJson(res);
  return data.app_type === "admin" ? data : null;
}

/**
 * Local development only: the backend may authorize an admin session without TOTP (DEV_ADMIN_MFA_BYPASS,
 * enforced server-side). The BFF additionally requires its own opt-in; otherwise it refuses such sessions.
 */
function devSession(payload: Record<string, unknown>, scope: Scope) {
  const allowed = process.env.DEV_ADMIN_MFA_BYPASS === "1" && process.env.NODE_ENV !== "test";
  if (!allowed || payload.dev_mfa_bypass !== true || typeof payload.access !== "string" || typeof payload.refresh !== "string") return null;
  const out = json({ scope, tenant: payload.tenant ?? null, dev_mfa_bypass: true });
  setSessionCookies(out, { access: payload.access, refresh: payload.refresh }, scope);
  return out;
}

async function pass(res: Response) {
  return json(await readJson(res), res.status);
}

const post = (req: NextRequest, path: string, payload: unknown, extra: Record<string, string> = {}) =>
  backend(path, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...forwardedFor(req), ...extra },
    body: JSON.stringify(payload),
  });

export async function GET(req: NextRequest, ctx: { params: Promise<{ action: string }> }) {
  const { action } = await ctx.params;
  if (action === "context") {
    const app = await adminApp(req.nextUrl.searchParams.get("workspace") || undefined);
    if (!app) return bad("workspace_invalid", "Unknown operator workspace.", 404);
    return json({ tenant_name: app.tenant_name, tenant_status: app.tenant_status, locale: app.locale });
  }
  if (action === "session") {
    const access = req.cookies.get(COOKIE.access)?.value;
    if (!access) {
      return json({ code: req.cookies.has(COOKIE.refresh) ? "access_expired" : "not_authenticated" }, 401);
    }
    const res = await backend("me", { headers: { Authorization: `Bearer ${access}` } });
    return pass(res);
  }
  return bad("not_found", "Not found.", 404);
}

export async function POST(req: NextRequest, ctx: { params: Promise<{ action: string }> }) {
  const { action } = await ctx.params;
  if (!sameOrigin(req)) return bad("csrf_failed", "Request blocked.", 403);
  const data = await body(req);

  switch (action) {
    case "otp-request": {
      if (!(await adminApp(data.workspace))) return bad("workspace_invalid", "Unknown operator workspace.", 404);
      const res = await post(req, "auth/otp/request", { phone: data.phone }, { "X-RideFlow-App": data.workspace as string });
      const out = await pass(res);
      if (res.ok) out.cookies.set(COOKIE.workspace, data.workspace as string, { sameSite: "strict", path: "/", maxAge: 31536000 });
      return out;
    }
    case "otp-verify": {
      if (!(await adminApp(data.workspace))) return bad("workspace_invalid", "Unknown operator workspace.", 404);
      const res = await post(req, "auth/otp/verify", { phone: data.phone, code: data.code }, { "X-RideFlow-App": data.workspace as string });
      const payload = await readJson(res);
      // Defence in depth: tokens without the second factor are accepted only for an explicit dev session.
      if (res.ok && !payload.mfa_required) return devSession(payload, "tenant") ?? bad("mfa_not_enforced", "Administrator MFA is not enabled on the server.", 403);
      return json(payload, res.status);
    }
    case "platform-login": {
      const res = await post(req, "auth/platform/login", { phone: data.phone, password: data.password });
      const payload = await readJson(res);
      if (res.ok && !payload.mfa_required) return devSession(payload, "platform") ?? bad("mfa_not_enforced", "Administrator MFA is not enabled on the server.", 403);
      return json(payload, res.status);
    }
    case "mfa-setup":
      return pass(await post(req, "auth/mfa/setup", { mfa_token: data.mfa_token }));
    case "mfa-verify": {
      const res = await post(req, "auth/mfa/verify", { mfa_token: data.mfa_token, code: data.code });
      const payload = await readJson(res);
      if (!res.ok) return json(payload, res.status);
      const scope = payload.scope as Scope;
      const out = json({ scope, tenant: payload.tenant ?? null });
      setSessionCookies(out, { access: String(payload.access), refresh: String(payload.refresh) }, scope);
      return out;
    }
    case "refresh": {
      if (!csrfValid(req)) return bad("csrf_failed", "Request blocked.", 403);
      const refresh = req.cookies.get(COOKIE.refresh)?.value;
      const tokens = refresh ? await refreshTokens(refresh) : null;
      if (!tokens) {
        const out = json({ code: "not_authenticated", detail: "Session expired." }, 401);
        clearSessionCookies(out);
        return out;
      }
      const out = json({ ok: true });
      setSessionCookies(out, tokens);
      return out;
    }
    case "logout": {
      if (!csrfValid(req)) return bad("csrf_failed", "Request blocked.", 403);
      const access = req.cookies.get(COOKIE.access)?.value;
      const refresh = req.cookies.get(COOKIE.refresh)?.value;
      if (access && refresh) {
        // Best effort server-side revocation of the refresh token.
        await post(req, "auth/logout", { refresh }, { Authorization: `Bearer ${access}` }).catch(() => null);
      }
      const out = json({ ok: true });
      clearSessionCookies(out);
      return out;
    }
    default:
      return bad("not_found", "Not found.", 404);
  }
}
