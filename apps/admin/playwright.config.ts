import { defineConfig, devices } from "@playwright/test";

/**
 * End-to-end suite against the running local Docker stack (docker compose up -d --build).
 * Data lives in the dedicated `e2e-qa` tenant (manage.py seed_e2e); the owner's demo tenants are never touched.
 * Runs serially (one worker) to keep load on the developer machine bounded and results deterministic.
 */
export default defineConfig({
  testDir: "./e2e",
  globalSetup: "./e2e/global-setup.ts",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: [["list"], ["json", { outputFile: "e2e/.results/results.json" }]],
  outputDir: "e2e/.results/artifacts",
  use: {
    baseURL: process.env.E2E_BASE_URL || "http://localhost:3000",
    channel: process.env.E2E_BROWSER_CHANNEL || "chrome",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    ...devices["Desktop Chrome"],
    viewport: { width: 1280, height: 860 },
  },
});
