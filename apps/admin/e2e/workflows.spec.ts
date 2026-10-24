import { randomUUID } from "node:crypto";

import { expect, test, type Page } from "@playwright/test";

import { Actor, apiContext, completedRide, readyDriver, seed, staffToken, statePath, submittedDriver, uniquePng, useEnglish } from "./support";

const data = seed();

async function confirm(page: Page, label: string, note?: string) {
  const dialog = page.getByRole("dialog");
  if (note !== undefined) await dialog.getByRole("textbox").fill(note);
  await dialog.getByRole("button", { name: label, exact: true }).click();
  await expect(dialog).toBeHidden();
}

test.describe("driver verification (reviewer)", () => {
  test.use({ storageState: statePath("reviewer") });

  test("approve documents and vehicle, then the driver application", async ({ page, context }) => {
    await useEnglish(context);
    const api = await apiContext();
    const d = await submittedDriver(api, data);
    await page.goto("/operator/drivers/verification");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await page.goto(`/operator/drivers/${d.driverId}`);
    await expect(page.getByText("Under review").first()).toBeVisible();

    // approving the driver before the documents is refused by the backend and explained
    await page.getByRole("button", { name: "Approve driver" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Approve driver" }).click();
    await expect(page.getByRole("dialog").getByRole("alert")).toBeVisible();
    await page.getByRole("dialog").getByRole("button", { name: "Cancel" }).click();

    const rowApprove = page.getByRole("main").getByRole("button", { name: "Approve", exact: true });
    await expect(rowApprove).toHaveCount(4); // three documents + one vehicle
    for (let i = 0; i < 4; i++) {
      await rowApprove.first().click();
      await confirm(page, "Approve");
      await expect(rowApprove).toHaveCount(3 - i);
    }
    await page.getByRole("button", { name: "Approve driver" }).click();
    await confirm(page, "Approve driver");
    await expect(page.getByRole("banner").or(page.locator("header")).getByText("Approved").first()).toBeVisible();

    const status = await new Actor(api, staffToken("reviewer"), data.apps.admin).get(`admin/drivers/${d.driverId}`);
    expect(status.status).toBe("approved");
    await api.dispose();
  });

  test("rejecting a document requires a reason", async ({ page, context }) => {
    await useEnglish(context);
    const api = await apiContext();
    const d = await submittedDriver(api, data);
    await page.goto(`/operator/drivers/${d.driverId}`);
    await page.getByRole("main").getByRole("button", { name: "Reject", exact: true }).first().click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("button", { name: "Reject", exact: true }).click();
    await expect(dialog.getByText("A reason is required for this decision.")).toBeVisible();
    await confirm(page, "Reject", "Blurry photo (e2e)");
    await expect(page.getByText("Rejected").first()).toBeVisible();
    await api.dispose();
  });
});

test.describe("deposit review (finance)", () => {
  test.use({ storageState: statePath("finance") });

  test("approving a receipt activates the subscription and writes the ledger", async ({ page, context }) => {
    await useEnglish(context);
    const api = await apiContext();
    const d = await readyDriver(api, data, false);
    const reference = `E2E-${randomUUID().slice(0, 8).toUpperCase()}`;
    const claim = await d.actor.upload("driver/deposit-claims", {
      plan_id: data.monthly_plan_id,
      deposit_account_id: data.deposit_account_id,
      amount_minor: String(data.monthly_price_minor),
      reference,
      deposited_on: new Date().toISOString().slice(0, 10),
      receipt: { name: "receipt.png", mimeType: "image/png", buffer: uniquePng() },
    });
    expect((await d.actor.get("driver/subscription")).entitled).toBe(false);

    await page.goto("/operator/subscriptions/deposits");
    await expect(page.getByText(reference)).toBeVisible();
    await page.goto(`/operator/subscriptions/deposits/${String(claim.id)}`);
    await page.getByRole("button", { name: "Approve deposit" }).click();
    await confirm(page, "Approve");
    await expect(page.getByText("Approved").first()).toBeVisible();
    await expect(page.getByRole("button", { name: "Approve deposit" })).toHaveCount(0);

    expect((await d.actor.get("driver/subscription")).entitled).toBe(true);
    // a second approval of the same claim is a conflict, not a second subscription
    const finance = new Actor(api, staffToken("finance"), data.apps.admin);
    await finance.post(`admin/deposit-claims/${String(claim.id)}/approve`, { note: "" }, 409);
    const ledger = await finance.get("admin/subscription-ledger", { driver: d.driverId });
    expect(ledger.results?.length).toBe(1);
    expect(ledger.results?.[0]?.amount_minor).toBe(data.monthly_price_minor);
    await page.goto("/operator/subscriptions/ledger");
    await expect(page.getByRole("table")).toBeVisible();
    await api.dispose();
  });
});

test.describe("trust: disputes and notifications (reviewer)", () => {
  test.use({ storageState: statePath("reviewer") });

  test("a rider dispute notifies staff, deep-links to the case and is resolved with a recorded violation", async ({ page, context }) => {
    await useEnglish(context);
    const api = await apiContext();
    const { rideId, rider } = await completedRide(api, data);
    const dispute = await rider.post(`rides/${rideId}/disputes`, { category: "fare", description: "Driver asked for more than agreed (e2e)." });

    await page.goto("/operator/notifications");
    await page.getByRole("tab", { name: /Unread/ }).click();
    const item = page.getByRole("button", { name: /Dispute opened \(Unread\)/ }).first();
    await expect(item).toBeVisible();
    await item.click();
    await expect(page).toHaveURL(new RegExp(`/operator/trust/disputes/${String(dispute.id)}$`));
    await expect(page.getByText("Driver asked for more than agreed (e2e).")).toBeVisible();

    await page.getByRole("button", { name: "Resolve" }).click();
    const dialog = page.getByRole("dialog");
    await dialog.getByRole("radio", { name: "Uphold" }).click();
    await dialog.getByLabel(/Violation to record/).selectOption("price_non_compliance");
    await dialog.getByLabel(/Reason/).fill("Fare above the agreed offer (e2e).");
    await dialog.getByRole("button", { name: "Confirm" }).click();
    await expect(dialog).toBeHidden();
    await expect(page.getByText("Fare above the agreed offer (e2e).")).toBeVisible();
    await expect(page.getByRole("button", { name: "Resolve" })).toHaveCount(0);

    const reviewer = new Actor(api, staffToken("reviewer"), data.apps.admin);
    const violations = await reviewer.get("admin/violations", { ride: rideId });
    expect(violations.results?.length).toBe(1);
    await page.goto("/operator/trust/violations");
    await expect(page.getByRole("table")).toBeVisible();
    await api.dispose();
  });
});
