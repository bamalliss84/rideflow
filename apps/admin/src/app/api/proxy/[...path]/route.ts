import { NextResponse, type NextRequest } from "next/server";

import { backend, COOKIE, csrfValid, forwardedFor, json, sameOrigin } from "@/lib/server/session";

export const dynamic = "force-dynamic";

const PASS_REQUEST = ["content-type", "idempotency-key", "accept-language", "x-request-id"];
const PASS_RESPONSE = ["content-type", "content-disposition", "idempotent-replay", "x-request-id"];

/**
 * Authenticated pass-through to the Django API (/api/v1/*). Token refresh is NOT done here: the browser
 * client performs one single-flight refresh (POST /api/auth/refresh) on 401 and retries, which avoids
 * concurrent refresh-token rotations invalidating each other.
 */
async function handle(req: NextRequest, ctx: { params: Promise<{ path: string[] }> }) {
  const { path } = await ctx.params;
  const subpath = path.map((p) => encodeURIComponent(p)).join("/");
  if (subpath.startsWith("auth")) return json({ code: "not_found", detail: "Not found." }, 404);

  const method = req.method.toUpperCase();
  const mutating = method !== "GET" && method !== "HEAD";
  if (mutating && (!sameOrigin(req) || !csrfValid(req))) {
    return json({ code: "csrf_failed", detail: "Request blocked (CSRF)." }, 403);
  }
  const access = req.cookies.get(COOKIE.access)?.value;
  if (!access) {
    const renewable = req.cookies.has(COOKIE.refresh);
    return json({ code: renewable ? "access_expired" : "not_authenticated", detail: "Session expired." }, 401);
  }

  const headers: Record<string, string> = { Accept: "application/json", Authorization: `Bearer ${access}`, ...forwardedFor(req) };
  for (const name of PASS_REQUEST) {
    const value = req.headers.get(name);
    if (value) headers[name] = value;
  }
  const res = await backend(`${subpath}${req.nextUrl.search}`, {
    method,
    headers,
    body: mutating ? await req.arrayBuffer() : undefined,
  });
  const outHeaders = new Headers({ "Cache-Control": "no-store" });
  for (const name of PASS_RESPONSE) {
    const value = res.headers.get(name);
    if (value) outHeaders.set(name, value);
  }
  const empty = res.status === 204 || res.status === 205;
  return new NextResponse(empty ? null : res.body, { status: res.status, headers: outHeaders });
}

export { handle as GET, handle as POST, handle as PATCH, handle as PUT, handle as DELETE };
