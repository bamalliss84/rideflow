"use client";

import { Check, X } from "lucide-react";
import { useState } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { Button } from "@/components/ui/Button";
import { ConfirmDialog } from "@/components/ui/Dialog";
import { useAction } from "@/lib/api/hooks";

/** Approve / reject pair for a review endpoint (`{base}/approve`, `{base}/reject`). Reject needs a reason. */
export function ReviewActions({ base, approveLabel, rejectLabel, invalidate, size = "sm" }: {
  base: string;
  approveLabel: string;
  rejectLabel: string;
  invalidate: string[];
  size?: "sm" | "md";
}) {
  const { t } = useI18n();
  const [mode, setMode] = useState<"approve" | "reject" | null>(null);
  const approve = useAction<{ note: string }>("POST", `${base}/approve`, { invalidate, inlineErrors: true, success: approveLabel });
  const reject = useAction<{ note: string }>("POST", `${base}/reject`, { invalidate, inlineErrors: true, success: rejectLabel });
  return (
    <span className="inline-flex flex-wrap gap-1.5">
      <Button size={size} variant="accent" icon={<Check className="size-4" aria-hidden />} onClick={() => setMode("approve")}>
        {t.common.approve}
      </Button>
      <Button size={size} variant="outline-danger" icon={<X className="size-4" aria-hidden />} onClick={() => setMode("reject")}>
        {t.common.reject}
      </Button>
      <ConfirmDialog
        open={mode !== null}
        onClose={() => setMode(null)}
        title={mode === "approve" ? approveLabel : rejectLabel}
        confirmLabel={mode === "approve" ? t.common.approve : t.common.reject}
        tone={mode === "approve" ? "accent" : "danger"}
        note={{ label: mode === "approve" ? `${t.common.note} (${t.common.optional})` : t.common.reason, required: mode === "reject" }}
        onConfirm={(note) => (mode === "approve" ? approve : reject).mutateAsync({ note })}
      />
    </span>
  );
}
