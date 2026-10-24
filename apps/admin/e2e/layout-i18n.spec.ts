import { expect, test } from "@playwright/test";

import { noHorizontalOverflow, statePath } from "./support";

test.use({ storageState: statePath("owner") });

const ROUTES = [
  "/operator",
  "/operator/drivers",
  "/operator/rides",
  "/operator/subscriptions/plans",
  "/operator/trust/disputes",
  "/operator/reports",
  "/operator/notifications",
  "/operator/audit",
  "/operator/members",
  "/operator/settings/policy",
  "/operator/settings/organization",
];

test("Arabic is RTL by default and English switches to LTR", async ({ page }) => {
  await page.goto("/operator");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(page.locator("html")).toHaveAttribute("lang", "ar");
  await page.getByRole("button", { name: "اللغة" }).click();
  await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Operations dashboard");
  await page.getByRole("button", { name: "Language" }).click();
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
});

for (const width of [375, 768, 1280, 1440]) {
  test(`no page-level horizontal overflow at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    const offenders: string[] = [];
    for (const route of ROUTES) {
      await page.goto(route);
      await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
      await page.waitForLoadState("networkidle");
      const overflow = await noHorizontalOverflow(page);
      if (overflow > 0) offenders.push(`${route}: ${overflow}px`);
    }
    expect(offenders).toEqual([]);
  });
}

test("mobile navigation opens as a drawer and closes after navigating", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/operator");
  await expect(page.getByRole("navigation", { name: "primary" })).toBeHidden();
  await page.getByRole("button", { name: "القائمة" }).click();
  const drawer = page.getByRole("dialog");
  await drawer.getByRole("link", { name: "التقارير" }).click();
  await expect(page).toHaveURL(/\/operator\/reports$/);
  await expect(drawer).toBeHidden();
});

test("keyboard: modal dialogs keep focus away from the page behind and close with Escape", async ({ page }) => {
  await page.goto("/operator/members");
  await page.getByRole("button", { name: "إضافة عضو" }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  for (let i = 0; i < 8; i++) {
    await page.keyboard.press("Tab");
    // Native modal <dialog>: focus stays in the dialog or moves to browser chrome (body), never to the page behind it.
    expect(await dialog.evaluate((d) => d.contains(document.activeElement) || document.activeElement === document.body)).toBe(true);
  }
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();
});
