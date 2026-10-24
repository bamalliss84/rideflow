import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { request, type APIRequestContext, type BrowserContext, type Page } from "@playwright/test";

export const BASE = process.env.E2E_BASE_URL || "http://localhost:3000";
export const API = process.env.E2E_API_URL || "http://localhost:8010";
export const DEV_OTP = process.env.E2E_DEV_OTP || "000000";
export const PLATFORM_PHONE = process.env.DEMO_PLATFORM_ADMIN_PHONE || "+967700000000";
export const PLATFORM_PASSWORD = process.env.DEMO_PLATFORM_ADMIN_PASSWORD || "change-me-local-only";
const ROOT = path.resolve(__dirname, "..", "..", "..");
const DIR = path.join(__dirname, ".auth");

export interface SeedData {
  tenant_id: string;
  apps: { rider: string; driver: string; admin: string };
  center: { lng: number; lat: number };
  monthly_plan_id: string;
  monthly_price_minor: number;
  deposit_account_id: string;
  staff: Record<"owner" | "reviewer" | "finance" | "reviewer_two" | "support" | "login_owner", string>;
  login_phones: string[];
}

/** A login-test owner phone that changes every 10 minutes (keeps repeated runs under the per-phone OTP limit). */
export const loginPhone = (data: SeedData, offset = 0) =>
  data.login_phones[(Math.floor(Date.now() / 600_000) + offset) % data.login_phones.length] as string;
export type Role = Exclude<keyof SeedData["staff"], "login_owner">;

export function seed(): SeedData {
  const file = path.join(DIR, "seed.json");
  if (existsSync(file)) return JSON.parse(readFileSync(file, "utf-8")) as SeedData;
  const out = execSync("docker compose exec -T api python manage.py seed_e2e --json", { cwd: ROOT, encoding: "utf-8" });
  const data = JSON.parse(out.trim().split("\n").pop() as string) as SeedData;
  mkdirSync(DIR, { recursive: true });
  writeFileSync(file, JSON.stringify(data));
  return data;
}

export const statePath = (role: Role) => path.join(DIR, `${role}.json`);

/** Operator sign-in through the BFF exactly as the login page does (workspace + phone + development OTP). */
export async function bffLogin(ctx: APIRequestContext, workspace: string, phone: string) {
  const headers = { Origin: BASE };
  const r1 = await ctx.post("/api/auth/otp-request", { data: { workspace, phone }, headers });
  if (!r1.ok()) throw new Error(`otp-request ${phone}: ${r1.status()} ${await r1.text()}`);
  const r2 = await ctx.post("/api/auth/otp-verify", { data: { workspace, phone, code: DEV_OTP }, headers });
  const body = (await r2.json()) as Record<string, unknown>;
  if (!r2.ok() || body.dev_mfa_bypass !== true) throw new Error(`otp-verify ${phone}: ${r2.status()} ${JSON.stringify(body)}`);
}

/**
 * Reuses a saved session (OTP requests are rate-limited per phone) but always rotates it first: refresh tokens
 * are single-use (rotation + blacklist), so a token saved by an earlier run may already have been consumed.
 */
export async function ensureState(role: Role, data: SeedData) {
  const file = statePath(role);
  if (existsSync(file)) {
    const ctx = await request.newContext({ baseURL: BASE, storageState: file });
    const csrf = (await ctx.storageState()).cookies.find((c) => c.name === "rf_csrf")?.value ?? "";
    const ok = (await ctx.post("/api/auth/refresh", { headers: { Origin: BASE, "x-rf-csrf": csrf } })).ok();
    if (ok) {
      await ctx.storageState({ path: file });
      await ctx.dispose();
      return;
    }
    await ctx.dispose();
  }
  const ctx = await request.newContext({ baseURL: BASE });
  await bffLogin(ctx, data.apps.admin, data.staff[role]);
  await ctx.storageState({ path: file });
  await ctx.dispose();
}

/** Bearer token of a stored staff session, for fast API-side setup steps (the backend still authorises it). */
export function staffToken(role: Role): string {
  const state = JSON.parse(readFileSync(statePath(role), "utf-8")) as { cookies: { name: string; value: string }[] };
  return state.cookies.find((c) => c.name === "rf_at")?.value ?? "";
}

export async function useEnglish(context: BrowserContext) {
  await context.addCookies([{ name: "rf_locale", value: "en", url: BASE }]);
}

export async function noHorizontalOverflow(page: Page) {
  return page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
}

// ---------------------------------------------------------------- direct API actors (rider / driver apps)

export const uniquePhone = () => `+9677${String(Date.now()).slice(-7)}${Math.floor(Math.random() * 10)}`.slice(0, 13);
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(64)]);
export const uniquePng = () => Buffer.concat([PNG, Buffer.from(randomUUID())]);

export class Actor {
  constructor(
    readonly api: APIRequestContext,
    readonly token: string,
    readonly app: string,
  ) {}

  private headers(extra: Record<string, string> = {}) {
    return { Authorization: `Bearer ${this.token}`, "X-RideFlow-App": this.app, "Idempotency-Key": randomUUID(), ...extra };
  }

  async get(url: string, params?: Record<string, string>) {
    const r = await this.api.get(`/api/v1/${url}`, { headers: this.headers(), params });
    if (!r.ok()) throw new Error(`GET ${url}: ${r.status()} ${await r.text()}`);
    return (await r.json()) as Record<string, unknown> & { results?: Record<string, unknown>[] };
  }

  async post(url: string, data: unknown = {}, expect = 0) {
    const r = await this.api.post(`/api/v1/${url}`, { headers: this.headers(), data });
    if (expect ? r.status() !== expect : !r.ok()) throw new Error(`POST ${url}: ${r.status()} ${await r.text()}`);
    return (r.status() === 204 ? {} : await r.json()) as Record<string, unknown>;
  }

  async upload(url: string, multipart: Record<string, string | { name: string; mimeType: string; buffer: Buffer }>) {
    const r = await this.api.post(`/api/v1/${url}`, { headers: this.headers(), multipart });
    if (!r.ok()) throw new Error(`UPLOAD ${url}: ${r.status()} ${await r.text()}`);
    return (await r.json()) as Record<string, unknown>;
  }
}

export async function apiContext() {
  return request.newContext({ baseURL: API });
}

/** Rider/driver app sign-in with the development OTP (driver app sign-in creates the driver profile). */
export async function appLogin(api: APIRequestContext, app: string, phone = uniquePhone()) {
  const headers = { "X-RideFlow-App": app };
  const r1 = await api.post("/api/v1/auth/otp/request", { headers, data: { phone } });
  if (!r1.ok()) throw new Error(`otp/request: ${r1.status()} ${await r1.text()}`);
  const r2 = await api.post("/api/v1/auth/otp/verify", { headers, data: { phone, code: DEV_OTP } });
  if (!r2.ok()) throw new Error(`otp/verify: ${r2.status()} ${await r2.text()}`);
  const body = (await r2.json()) as { access: string };
  return { actor: new Actor(api, body.access, app), phone };
}

/** A driver application under review: vehicle + three documents submitted through the driver API. */
export async function submittedDriver(api: APIRequestContext, data: SeedData) {
  const { actor, phone } = await appLogin(api, data.apps.driver);
  const plate = `E2E ${randomUUID().slice(0, 6).toUpperCase()}`;
  const vehicle = await actor.post("driver/vehicles", { plate_number: plate, make: "Toyota", model: "Hilux", color: "White" });
  const doc = (doc_type: string, extra: Record<string, string> = {}) =>
    actor.upload("driver/documents", {
      doc_type,
      number: randomUUID().slice(0, 8),
      expires_at: "2030-01-01",
      file: { name: `${doc_type}.png`, mimeType: "image/png", buffer: uniquePng() },
      ...extra,
    });
  await doc("national_id");
  await doc("driving_license");
  await doc("vehicle_registration", { vehicle_id: String(vehicle.id) });
  const submitted = await actor.post("driver/submit");
  return { actor, phone, driverId: String(submitted.id), vehicleId: String(vehicle.id), plate };
}

/** Fully approved, subscribed (trial), located and online driver: setup through the authorised staff API. */
export async function readyDriver(api: APIRequestContext, data: SeedData, subscribe = true) {
  const d = await submittedDriver(api, data);
  const reviewer = new Actor(api, staffToken("reviewer"), data.apps.admin);
  const docs = await reviewer.get("admin/driver-documents", { driver: d.driverId });
  for (const doc of docs.results ?? []) await reviewer.post(`admin/driver-documents/${String(doc.id)}/approve`, { note: "" });
  await reviewer.post(`admin/vehicles/${d.vehicleId}/approve`, { note: "" });
  await reviewer.post(`admin/drivers/${d.driverId}/decide`, { decision: "approve", note: "" });
  if (subscribe) {
    await d.actor.post("driver/subscription/trial", {}, 201);
    await d.actor.post("driver/location", { lat: data.center.lat, lng: data.center.lng, accuracy_m: 8 });
    await d.actor.post("driver/availability", { online: true });
  }
  return d;
}

/** Completed cash ride between a fresh rider and a ready driver, through the public ride API. */
export async function completedRide(api: APIRequestContext, data: SeedData) {
  const driver = await readyDriver(api, data);
  const { actor: rider, phone: riderPhone } = await appLogin(api, data.apps.rider);
  const { lat, lng } = data.center;
  let ride = await rider.post("rides", {
    pickup: { lat, lng },
    pickup_landmark: "E2E pickup",
    dropoff: { lat: lat + 0.02, lng: lng + 0.02 },
    dropoff_landmark: "E2E dropoff",
  });
  const id = String(ride.id);
  const bid = await driver.actor.post(`rides/${id}/bids`, { amount_minor: 150000, eta_seconds: 180 });
  ride = await rider.post(`rides/${id}/select`, { bid_id: bid.id, expected_version: ride.version });
  ride = await driver.actor.post(`rides/${id}/confirm`, { expected_version: ride.version });
  ride = await driver.actor.post(`rides/${id}/arrive`, { expected_version: ride.version, lat, lng, accuracy_m: 5 });
  ride = await driver.actor.post(`rides/${id}/start`, { expected_version: ride.version });
  ride = await driver.actor.post(`rides/${id}/complete`, { expected_version: ride.version });
  return { rideId: id, ride, rider, riderPhone, driver };
}
