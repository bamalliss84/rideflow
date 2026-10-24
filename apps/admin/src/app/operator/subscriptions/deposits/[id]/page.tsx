"use client";

import { CheckCircle2, Users, XCircle } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState } from "react";

import { EnumBadge, MetaLine, Person } from "@/components/domain/Display";
import { FilePreviewButton } from "@/components/domain/FilePreview";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card, KeyValues } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/Dialog";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useAction, useApi } from "@/lib/api/hooks";

type Claim = Schemas["DepositClaim"];
type Config = Schemas["EffectiveConfig"];

export default function DepositDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { t, tpl } = useI18n();
  const { fmt, can, me } = useSession();
  const s = t.subscriptions;
  const base = `admin/deposit-claims/${id}`;
  const q = useApi<Claim>(base);
  const config = useApi<Config>(can("reports.view") ? "admin/config" : null);
  const [mode, setMode] = useState<"approve" | "reject" | null>(null);
  const invalidate = ["admin/deposit-claims", "admin/subscriptions", "admin/subscription-ledger", "admin/dashboard"];
  const approve = useAction<{ note: string }>("POST", `${base}/approve`, { invalidate, inlineErrors: true, success: s.approveClaim });
  const reject = useAction<{ note: string }>("POST", `${base}/reject`, { invalidate, inlineErrors: true, success: s.rejectClaim });

  if (q.isPending) return <PageSkeleton />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />;
  const c = q.data;
  const open = c.status === "submitted" || c.status === "first_approved";
  const dual = config.data?.effective["subscriptions.dual_approval"] === true;
  const isFirstStep = dual && c.status === "submitted";
  const sameApprover = c.status === "first_approved" && c.first_approved_by === me.user.id;

  return (
    <>
      <PageHeader
        title={<span className="ltr-nums">{c.reference}</span>}
        meta={<EnumBadge group="claimStatus" value={c.status} />}
        crumbs={[{ label: t.nav.deposits, href: "/operator/subscriptions/deposits" }, { label: c.reference }]}
        actions={
          open && can("subscriptions.review") ? (
            <>
              <Button variant="accent" icon={<CheckCircle2 className="size-4" aria-hidden />} onClick={() => setMode("approve")} disabled={sameApprover}>
                {s.approveClaim}
              </Button>
              <Button variant="outline-danger" icon={<XCircle className="size-4" aria-hidden />} onClick={() => setMode("reject")}>
                {s.rejectClaim}
              </Button>
            </>
          ) : null
        }
      />
      {dual && open ? (
        <p className="mb-5 flex items-start gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-800">
          <Users className="mt-0.5 size-4 shrink-0" aria-hidden />
          {sameApprover ? t.errors.codes.same_approver : tpl(s.makerChecker, { step: isFirstStep ? s.stepFirst : s.stepFinal })}
        </p>
      ) : null}
      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <KeyValues
            columns={2}
            items={[
              {
                label: t.common.driver,
                value: (
                  <Link href={`/operator/drivers/${c.driver_id}`} className="hover:underline">
                    <Person name={c.driver_name} phone={c.driver_phone} />
                  </Link>
                ),
              },
              { label: s.plan, value: <MetaLine className="text-sm text-ink" parts={[c.plan.name, tpl(s.planDays, { n: fmt.number(c.plan.duration_days) })]} /> },
              { label: t.common.amount, value: <bdi className="text-lg font-semibold">{fmt.money(c.amount_minor, c.currency)}</bdi> },
              { label: s.expected, value: <bdi>{fmt.money(c.expected_amount_minor, c.currency)}</bdi> },
              { label: s.discount, value: c.discount_pct ? `${c.discount_pct}%` : "—" },
              { label: s.account, value: c.deposit_account_label ?? "—" },
              { label: s.depositedOn, value: fmt.day(c.deposited_on) },
              { label: t.common.created, value: fmt.dateTime(c.created_at) },
              { label: s.firstApproval, value: c.first_approved_at ? <MetaLine className="text-sm text-ink" parts={[c.first_approved_by_name ?? "—", <bdi key="d" className="text-muted">{fmt.dateTime(c.first_approved_at)}</bdi>]} /> : "—" },
              { label: s.decision, value: c.decided_at ? <MetaLine className="text-sm text-ink" parts={[c.decided_by_name ?? "—", <bdi key="d" className="text-muted">{fmt.dateTime(c.decided_at)}</bdi>]} /> : "—" },
              { label: t.common.note, value: c.decision_note || "—" },
            ]}
          />
        </Card>
        <Card>
          <h2 className="mb-3 text-sm font-semibold">{s.receipt}</h2>
          <p className="mb-4 text-xs leading-relaxed text-muted">{s.approveConfirm}</p>
          <FilePreviewButton path={`${base}/receipt`} contentType={c.receipt_content_type} title={`${s.receipt} · ${c.reference}`} label={`${t.common.preview} ${s.receipt}`} />
        </Card>
      </div>
      <ConfirmDialog
        open={mode !== null}
        onClose={() => setMode(null)}
        title={mode === "approve" ? s.approveClaim : s.rejectClaim}
        message={mode === "approve" ? s.approveConfirm : undefined}
        confirmLabel={mode === "approve" ? t.common.approve : t.common.reject}
        tone={mode === "approve" ? "accent" : "danger"}
        note={{ label: mode === "approve" ? `${t.common.note} (${t.common.optional})` : t.common.reason, required: mode === "reject" }}
        onConfirm={(note) => (mode === "approve" ? approve : reject).mutateAsync({ note })}
      />
    </>
  );
}
