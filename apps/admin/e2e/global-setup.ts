import { rmSync } from "node:fs";
import path from "node:path";

import { ensureState, seed, type Role } from "./support";

/** Seeds the dedicated e2e tenant (idempotent) and prepares one signed-in session per staff role. */
export default async function globalSetup() {
  rmSync(path.join(__dirname, ".auth", "seed.json"), { force: true });
  const data = seed();
  for (const role of ["owner", "reviewer", "finance", "reviewer_two", "support"] as Role[]) {
    await ensureState(role, data);
  }
}
