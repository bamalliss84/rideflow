/**
 * Server-only session helpers for the BFF (backend-for-frontend).
 *
 * The browser never sees JWTs: access/refresh tokens live in HttpOnly, SameSite=Strict cookies and are
 * attached to backend calls by Next.js route handlers. Mutations additionally require a double-submit CSRF
 * token (readable `rf_csrf` cookie echoed in the `x-rf-csrf` header) and a same-origin `Origin`.
 */
import { randomBytes, timingSafeEqual } from "node:crypto";
import { NextResponse, type NextRequest } from "next/server";

export const API_BASE = (process.env.API_INTERNAL_URL || "http://127.0.0.1:8010").replace(/\/$/, "");

export const COOKIE = {
  access: "rf_at",
  refresh: "rf_rt",
  scope: "rf_scope",
  csrf: "rf_csrf",
  workspace: "rf_ws",
} as const;

export type Scope = "tenant" | "platform";

const secure = process.env.COOKIE_SECURE !== "false";
const ACCESS_MAX_AGE = Number(process.env.SESSION_ACCESS_MAX_AGE || 15 * 60);
const REFRESH_MAX_AGE = Number(process.env.SESSION_MAX_AGE || 12 * 60 * 60);

const base = { httpOnly: true, secure, sameSite: "strict" as const, path: "/" };

export interface TokenPair {
  access: string;
  refresh: string;
}

export function setSessionCookies(res: NextResponse, tokens: TokenPair, scope?: Scope) {
  res.cookies.set(COOKIE.access, tokens.access, { ...base, maxAge: ACCESS_MAX_AGE });
  res.cookies.set(COOKIE.refresh, tokens.refresh, { ...base, maxAge: REFRESH_MAX_AGE });
  if (scope) {
    res.cookies.set(COOKIE.scope, scope, { ...base, maxAge: REFRESH_MAX_AGE });
    // Readable by scripts on purpose (double-submit CSRF token); it grants nothing on its own.
    res.cookies.set(COOKIE.csrf, randomBytes(32).toString("hex"), { ...base, httpOnly: false, maxAge: REFRESH_MAX_AGE });
  }
}

export function clearSessionCookies(res: NextResponse) {
  for (const name of [COOKIE.access, COOKIE.refresh, COOKIE.scope, COOKIE.csrf]) {
    res.cookies.set(name, "", { ...base, httpOnly: name !== COOKIE.csrf, maxAge: 0 });
  }
}

export function json(body: unknown, status = 200) {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

export function sameOrigin(req: NextRequest): boolean {
  const origin = req.headers.get("origin");
  if (!origin) return req.headers.get("sec-fetch-site") === "same-origin";
  const host = req.headers.get("x-forwarded-host") || req.headers.get("host");
  try {
    return new URL(origin).host === host;
  } catch {
    return false;
  }
}

export function csrfValid(req: NextRequest): boolean {
  const cookie = req.cookies.get(COOKIE.csrf)?.value;
  const header = req.headers.get("x-rf-csrf");
  if (!cookie || !header || cookie.length !== header.length) return false;
  return timingSafeEqual(Buffer.from(cookie), Buffer.from(header));
}

export function forwardedFor(req: NextRequest): Record<string, string> {
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || req.headers.get("x-real-ip") || "";
  return ip ? { "X-Forwarded-For": ip } : {};
}

export async function backend(path: string, init: RequestInit & { headers?: Record<string, string> } = {}) {
  return fetch(`${API_BASE}/api/v1/${path}`, { ...init, cache: "no-store", redirect: "manual" });
}

export async function refreshTokens(refresh: string): Promise<TokenPair | null> {
  const res = await backend("auth/token/refresh", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh }),
  });
  if (!res.ok) return null;
  const data = (await res.json()) as Partial<TokenPair>;
  return data.access && data.refresh ? { access: data.access, refresh: data.refresh } : null;
}

export async function readJson(res: Response): Promise<Record<string, unknown>> {
  try {
    return (await res.json()) as Record<string, unknown>;
  } catch {
    return {};
  }
}
