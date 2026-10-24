import { expect, test } from "@playwright/test";

import { API, BASE, loginPhone, PLATFORM_PASSWORD, PLATFORM_PHONE, seed, statePath, useEnglish } from "./support";

const data = seed();

test.describe("operator authentication", () => {
  test("login via UI with dev OTP skips TOTP (local dev bypass), then logout ends the session", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/login");
    await page.getByLabel("Operator workspace").fill(data.apps.admin);
    await page.getByLabel("Mobile number").fill(loginPhone(data));
    await page.getByRole("button", { name: "Send code" }).click();
    await page.getByLabel("Verification code").fill("000000");
    await page.getByRole("button", { name: "Continue" }).click();
    await expect(page).toHaveURL(/\/operator$/);
    await expect(page.getByText("Authenticator code")).toHaveCount(0);
    const session = await (await page.request.get("/api/auth/session")).json();
    expect(session.mfa.dev_bypass).toBe(true); // backend-authorised local session, never a frontend switch
    expect(session.mfa.session_verified).toBe(false);

    await page.getByRole("button", { name: /E2E Login Owner/ }).click();
    await page.getByRole("menuitem", { name: "Sign out" }).click();
    await expect(page).toHaveURL(/\/login/);
    expect((await page.request.get("/api/auth/session")).status()).toBe(401);
    await page.goto("/operator/drivers");
    await expect(page).toHaveURL(/\/login\?next=/);
  });

  test("wrong OTP is rejected with a message and no session", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/login");
    await page.getByLabel("Operator workspace").fill(data.apps.admin);
    await page.getByLabel("Mobile number").fill(loginPhone(data, 3));
    await page.getByRole("button", { name: "Send code" }).click();
    await page.getByLabel("Verification code").fill("123456");
    await page.getByRole("button", { name: "Continue" }).click();
    await expect(page.getByRole("alert")).toBeVisible();
    await expect(page).toHaveURL(/\/login/);
  });
});

test.describe("sessions", () => {
  test.use({ storageState: statePath("owner") });

  test("expired access cookie is renewed transparently with the refresh token", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/operator/drivers");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    const before = (await context.cookies()).find((c) => c.name === "rf_rt")?.value;
    await context.clearCookies({ name: "rf_at" });
    await page.goto("/operator/riders");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByRole("table")).toBeVisible();
    const cookies = await context.cookies();
    expect(cookies.find((c) => c.name === "rf_at")?.value).toBeTruthy();
    expect(cookies.find((c) => c.name === "rf_rt")?.value).not.toBe(before); // rotated
    for (const c of cookies.filter((x) => x.name === "rf_at" || x.name === "rf_rt")) {
      expect(c.httpOnly).toBe(true);
      expect(c.sameSite).toBe("Strict");
    }
  });

  test("mutating proxy calls without the CSRF header are refused", async ({ page }) => {
    await page.goto("/operator");
    const r = await page.request.post("/api/proxy/notifications/read", { data: { up_to: 0 }, headers: { Origin: BASE } });
    expect(r.status()).toBe(403);
    expect((await r.json()).code).toBe("csrf_failed");
  });
});

test.describe("authorization", () => {
  test.use({ storageState: statePath("support") });

  test("support role does not see or reach member management and policy editing", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/operator");
    const nav = page.getByRole("navigation", { name: "primary" });
    await expect(nav.getByRole("link", { name: "Members & roles" })).toHaveCount(0);
    await page.goto("/operator/members");
    await expect(page.getByText("You do not have permission to view or change this.")).toBeVisible();
    const r = await page.request.get("/api/proxy/admin/members");
    expect(r.status()).toBe(403);
  });
});

test.describe("platform separation", () => {
  test("platform admin signs in with password, cannot open operator data", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/platform/login");
    await page.getByLabel("Mobile number").fill(PLATFORM_PHONE);
    await page.getByLabel("Password").fill(PLATFORM_PASSWORD);
    await page.getByRole("button", { name: "Sign in" }).click();
    await expect(page).toHaveURL(/\/platform$/);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText("Platform overview");
    await page.goto("/operator/members");
    await expect(page).toHaveURL(/\/platform/);
    expect((await page.request.get("/api/proxy/admin/members")).status()).toBe(403);
    // platform aggregates only: the e2e tenant is listed without operational records
    expect((await page.request.get(`/api/proxy/platform/tenants/${data.tenant_id}`)).status()).toBe(200);
  });

  test("operator session cannot use platform APIs", async ({ browser }) => {
    const ctx = await browser.newContext({ storageState: statePath("owner") });
    const r = await ctx.request.get(`${BASE}/api/proxy/platform/overview`);
    expect(r.status()).toBe(403);
    await ctx.close();
  });

  test("backend API rejects unauthenticated and forged tokens directly", async ({ request }) => {
    expect((await request.get(`${API}/api/v1/me`)).status()).toBe(401);
    expect((await request.get(`${API}/api/v1/admin/members`, { headers: { Authorization: "Bearer x.y.z" } })).status()).toBe(401);
  });
});
