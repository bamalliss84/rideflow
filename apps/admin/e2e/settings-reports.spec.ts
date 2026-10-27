import { readFileSync } from "node:fs";

import { expect, test } from "@playwright/test";

import { statePath, useEnglish } from "./support";

test.describe("policy settings (owner)", () => {
  test.use({ storageState: statePath("owner") });

  test("validation, unsaved-change guard and saving a new version", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/operator/settings/policy");
    const versionBadge = page.locator("h1 + *").first();
    const before = (await versionBadge.textContent()) ?? "";
    await page.getByRole("navigation", { name: "Policy sections" }).getByRole("button", { name: /Dispatch & matching/ }).click();
    const input = page.getByLabel("Offer validity", { exact: true });
    const current = Number(await input.inputValue());
    const next = current === 130 ? 125 : 130;
    const note = `e2e ${Date.now()}: ${current} -> ${next}`;

    await input.fill("5");
    await expect(page.getByText("Must be between 15 and 3600.")).toBeVisible();
    await expect(page.getByText("1 unsaved change(s)")).toBeVisible();
    await expect(page.getByRole("button", { name: "Save as new version" })).toBeDisabled();

    // leaving with unsaved edits asks for confirmation (beforeunload)
    let prompted = false;
    page.once("dialog", (d) => {
      prompted = d.type() === "beforeunload";
      void d.dismiss();
    });
    await page.close({ runBeforeUnload: true });
    await expect.poll(() => prompted).toBe(true);

    const fresh = await context.newPage();
    await fresh.goto("/operator/settings/policy");
    await fresh.getByRole("navigation", { name: "Policy sections" }).getByRole("button", { name: /Dispatch & matching/ }).click();
    const field = fresh.getByLabel("Offer validity", { exact: true });
    await field.fill(String(next));
    await fresh.getByRole("button", { name: "Save as new version" }).click();
    const dialog = fresh.getByRole("dialog");
    await expect(dialog.getByText("does not change approval status")).toBeVisible();
    await dialog.getByRole("textbox").fill(note);
    await dialog.getByRole("button", { name: "Save as new version" }).click();
    await expect(dialog).toBeHidden();
    await expect(fresh.getByText("unsaved change")).toHaveCount(0);
    await fresh.reload();
    await fresh.getByRole("navigation", { name: "Policy sections" }).getByRole("button", { name: /Dispatch & matching/ }).click();
    await expect(fresh.getByLabel("Offer validity", { exact: true })).toHaveValue(String(next));
    const after = (await fresh.locator("h1 + *").first().textContent()) ?? "";
    expect(Number(after.replace(/\D/g, ""))).toBe(Number(before.replace(/\D/g, "") || 0) + 1);
    await expect(fresh.getByText(note)).toBeVisible(); // version history
  });
});

test.describe("policy settings (reviewer: read-only)", () => {
  test.use({ storageState: statePath("reviewer") });

  test("reviewer sees values but no editors, and the API refuses writes", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/operator/settings/policy");
    await expect(page.getByText("You can view the policy.", { exact: false })).toBeVisible();
    await expect(page.locator('main input[type="number"]')).toHaveCount(0);
    const csrf = (await context.cookies()).find((c) => c.name === "rf_csrf")?.value ?? "";
    const r = await page.request.post("/api/proxy/admin/config", {
      data: { params: { "bids.expiry_seconds": 200 }, note: "forbidden" },
      headers: { "x-rf-csrf": csrf, Origin: "http://localhost:3000", "Idempotency-Key": crypto.randomUUID() },
    });
    expect(r.status()).toBe(403);
  });
});

test.describe("reports and CSV export (owner)", () => {
  test.use({ storageState: statePath("owner") });

  test("date ranges, chart and CSV derived from the server rows", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/operator/reports");
    await page.getByRole("radio", { name: "Last 7 days" }).click();
    await expect(page.getByRole("radio", { name: "Last 7 days" })).toHaveAttribute("aria-checked", "true");
    const api = await page.request.get("/api/proxy/admin/reports/rides-daily", {
      params: { date_from: new Date(Date.now() - 7 * 86400_000).toISOString(), date_to: new Date().toISOString() },
    });
    const rows = ((await api.json()) as { rows: { requested: number }[] }).rows;
    await expect(page.locator("main figure")).toBeVisible();
    await expect(page.getByText(/active days out of 8/)).toBeVisible();
    expect(rows.length).toBeGreaterThan(0); // the suite's own completed rides
    const total = rows.reduce((s, r) => s + r.requested, 0);
    await expect(page.getByText("Requests").first().locator("xpath=following-sibling::*[1]")).toHaveText(String(total));

    const [download] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "Export CSV" }).click()]);
    expect(download.suggestedFilename()).toMatch(/^rideflow-rides-daily_\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}\.csv$/);
    const csv = readFileSync(await download.path(), "utf-8").replace(/^﻿/, "").trim().split("\n");
    expect(csv[0]).toBe("Day,Requests,Matched,Completed,Cancelled,No-shows,Agreed fares (completed),Currency");
    expect(csv.length - 1).toBe(rows.length);
    expect(csv[1]).toMatch(/^\d{4}-\d{2}-\d{2},\d+,\d+,\d+,\d+,\d+,\d+\.\d{2},YER$/);
  });
});

test.describe("loading, error, empty and recovery states (owner)", () => {
  test.use({ storageState: statePath("owner") });

  test("server error shows retry; retry recovers; loading shows skeletons; filtered empty state", async ({ page, context }) => {
    await useEnglish(context);
    let fail = true;
    await page.route("**/api/proxy/admin/drivers?**", async (route) => {
      if (fail) return route.fulfill({ status: 500, contentType: "application/json", body: '{"code":"server_error"}' });
      await new Promise((r) => setTimeout(r, 800));
      // A refetch may already have been answered while delayed; that is not an app failure.
      return route.continue().catch(() => undefined);
    });
    await page.goto("/operator/drivers");
    await expect(page.getByRole("main").getByRole("alert").filter({ hasText: "Something went wrong" })).toBeVisible();
    fail = false;
    await page.getByRole("button", { name: "Try again" }).click();
    await expect(page.locator("main .animate-pulse").first()).toBeVisible();
    await expect(page.getByRole("table")).toBeVisible();
    await expect(page.locator("main tbody tr").first()).toBeVisible();
    await page.unroute("**/api/proxy/admin/drivers?**");

    await page.goto("/operator/trust/ratings");
    await page.getByLabel("Stars").selectOption("1");
    await expect(page.getByText("No results match these filters.")).toBeVisible();
  });

  test("dev-bypass session cannot manage MFA recovery codes", async ({ page, context }) => {
    await useEnglish(context);
    await page.goto("/operator/account");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByRole("button", { name: /recovery codes|new set/i })).toHaveCount(0);
    expect((await page.request.get("/api/auth/recovery-codes")).status()).toBe(403);
  });
});

test.describe("mutation failure handling (reviewer two)", () => {
  test.use({ storageState: statePath("reviewer_two") });

  test("network failure on a mutation shows an inline error, not a fake success", async ({ page, context }) => {
    await useEnglish(context);
    await page.route("**/api/proxy/notifications/read", (route) => route.abort("failed"));
    await page.goto("/operator/notifications");
    const markAll = page.getByRole("button", { name: "Mark all as read" });
    await expect(markAll).toBeEnabled(); // reviewer_two receives dispute notifications and never reads them
    await markAll.click();
    await expect(page.getByRole("main").getByRole("alert")).toBeVisible();
    await expect(page.getByText("All notifications marked as read.")).toHaveCount(0);
  });

});
