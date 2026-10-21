/**
 * Browser API client. All calls go to the same-origin BFF (/api/proxy/* → Django /api/v1/*).
 * - Never touches tokens (HttpOnly cookies); sends the CSRF double-submit header on mutations.
 * - On 401 performs ONE shared (single-flight) session refresh, then retries once.
 */
import type { components } from "./schema";

export type Schemas = components["schemas"];

export interface Page<T> {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
}

export class ApiError extends Error {
  status: number;
  code: string;
  detail: unknown;
  errors: Record<string, unknown> | null;

  constructor(status: number, body: Record<string, unknown> | null) {
    const detail = body?.detail;
    super(typeof detail === "string" ? detail : `HTTP ${status}`);
    this.status = status;
    this.code = typeof body?.code === "string" ? body.code : status === 0 ? "network" : `http_${status}`;
    this.detail = detail ?? null;
    this.errors = body && typeof body.errors === "object" && body.errors !== null ? (body.errors as Record<string, unknown>) : null;
  }

  /** Field → first message, for inline form errors. */
  fieldErrors(): Record<string, string> {
    const out: Record<string, string> = {};
    const walk = (value: unknown, prefix: string) => {
      if (Array.isArray(value)) {
        const first = value[0];
        if (typeof first === "string") out[prefix] = first;
        else if (first !== undefined) walk(first, prefix);
      } else if (value && typeof value === "object") {
        for (const [k, v] of Object.entries(value)) walk(v, prefix ? `${prefix}.${k}` : k);
      } else if (typeof value === "string") out[prefix] = value;
    };
    walk(this.errors, "");
    if (this.detail && typeof this.detail === "object") walk(this.detail, "");
    return out;
  }
}

export const SESSION_EXPIRED_EVENT = "rf:session-expired";

function csrfToken(): string {
  const match = document.cookie.match(/(?:^|;\s*)rf_csrf=([^;]+)/);
  return match?.[1] ? decodeURIComponent(match[1]) : "";
}

let refreshing: Promise<boolean> | null = null;

export function refreshSession(): Promise<boolean> {
  if (!refreshing) {
    refreshing = fetch("/api/auth/refresh", { method: "POST", headers: { "x-rf-csrf": csrfToken() }, credentials: "same-origin" })
      .then((r) => r.ok)
      .catch(() => false)
      .finally(() => {
        setTimeout(() => {
          refreshing = null;
        }, 0);
      });
  }
  return refreshing;
}

export type Query = Record<string, string | number | boolean | null | undefined | string[]>;

export function buildQuery(query?: Query): string {
  if (!query) return "";
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null || value === "") continue;
    if (Array.isArray(value)) value.forEach((v) => params.append(key, v));
    else params.set(key, String(value));
  }
  const qs = params.toString();
  return qs ? `?${qs}` : "";
}

export interface RequestOptions {
  method?: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
  query?: Query;
  body?: unknown;
  idempotencyKey?: string;
  signal?: AbortSignal;
}

async function send(url: string, opts: RequestOptions): Promise<Response> {
  const method = opts.method || "GET";
  const headers: Record<string, string> = { Accept: "application/json" };
  let body: BodyInit | undefined;
  if (method !== "GET") {
    headers["x-rf-csrf"] = csrfToken();
    if (opts.idempotencyKey) headers["Idempotency-Key"] = opts.idempotencyKey;
    if (opts.body instanceof FormData) body = opts.body;
    else if (opts.body !== undefined) {
      headers["Content-Type"] = "application/json";
      body = JSON.stringify(opts.body);
    }
  }
  return fetch(url, { method, headers, body, credentials: "same-origin", cache: "no-store", signal: opts.signal });
}

async function request(path: string, opts: RequestOptions = {}): Promise<Response> {
  const url = `/api/proxy/${path.replace(/^\//, "")}${buildQuery(opts.query)}`;
  let res: Response;
  try {
    res = await send(url, opts);
    if (res.status === 401 && (await refreshSession())) res = await send(url, opts);
  } catch (err) {
    if (err instanceof DOMException && err.name === "AbortError") throw err;
    throw new ApiError(0, { code: "network", detail: "Network error" });
  }
  if (res.status === 401) window.dispatchEvent(new Event(SESSION_EXPIRED_EVENT));
  if (!res.ok) {
    let payload: Record<string, unknown> | null = null;
    try {
      payload = (await res.json()) as Record<string, unknown>;
    } catch {
      payload = null;
    }
    throw new ApiError(res.status, payload);
  }
  return res;
}

export async function api<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const res = await request(path, opts);
  if (res.status === 204 || res.status === 205) return undefined as T;
  const text = await res.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

export async function apiBlob(path: string): Promise<Blob> {
  const res = await request(path);
  return res.blob();
}

export function newIdempotencyKey(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Calls the same-origin auth endpoints (login steps). */
export async function authCall<T>(action: string, body?: unknown, method: "GET" | "POST" = "POST", query?: Query): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`/api/auth/${action}${buildQuery(query)}`, {
      method,
      headers: method === "POST" ? { "Content-Type": "application/json", "x-rf-csrf": csrfToken() } : {},
      body: method === "POST" ? JSON.stringify(body ?? {}) : undefined,
      credentials: "same-origin",
      cache: "no-store",
    });
  } catch {
    throw new ApiError(0, { code: "network" });
  }
  const text = await res.text();
  const data = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  if (!res.ok) throw new ApiError(res.status, data);
  return data as T;
}
