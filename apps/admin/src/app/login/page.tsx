import { cookies } from "next/headers";
import { Suspense } from "react";

import { OperatorLogin } from "@/components/auth/OperatorLogin";

const WORKSPACE_RE = /^[A-Za-z0-9_-]{3,64}$/;

/** Operator sign-in. A white-label deployment can pin its workspace with DEFAULT_WORKSPACE. */
export default async function LoginPage() {
  const saved = decodeURIComponent((await cookies()).get("rf_ws")?.value ?? "");
  const pinned = process.env.DEFAULT_WORKSPACE ?? "";
  const initial = [saved, pinned].find((w) => WORKSPACE_RE.test(w)) ?? "";
  return (
    <Suspense>
      <OperatorLogin initialWorkspace={initial} />
    </Suspense>
  );
}
