"use client";

import { ChevronDown } from "lucide-react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";

import { EnumBadge, enumLabel, JsonView, Person } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { ConfirmDialog } from "@/components/ui/Dialog";
import { FilterSelect, PageHeader, Tabs, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useAction, useApiPage, useListState } from "@/lib/api/hooks";

type Violation = Schemas["Violation"];
const KINDS = ["rider_no_show", "rider_late_cancellation", "driver_late_cancellation", "driver_no_arrival", "complaint_upheld", "price_non_compliance", "safety"] as const;

function ViolationsList() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const tr = t.trust;
  const params = useSearchParams();
  const { filters, setFilters, page, setPage } = useListState<{ status: string; kind: string; subject: string }>({
    status: "pending_review",
    kind: "",
    subject: params.get("subject") ?? "",
  });
  const q = useApiPage<Violation>("admin/violations", filters, page);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [review, setReview] = useState<{ v: Violation; verify: boolean } | null>(null);
  const action = useAction<{ id: string; body: { verify: boolean; note: string } }>("POST", (v) => `admin/violations/${v.id}/review`, {
    invalidate: ["admin/violations", "admin/enforcement-actions", "admin/dashboard", "admin/trust-snapshots"],
    inlineErrors: true,
    success: tr.review,
  });

  return (
    <>
      <PageHeader title={tr.violationsTitle} subtitle={tr.violationsSubtitle} />
      <Card padded={false}>
        <Tabs
          label={t.common.status}
          value={filters.status}
          onChange={(status) => setFilters({ status })}
          items={[...(["pending_review", "verified", "dismissed", "overturned"] as const).map((v) => ({ value: v as string, label: t.enums.violationStatus[v] })), { value: "", label: t.common.all }]}
        />
        <Toolbar>
          <FilterSelect label={tr.kind} value={filters.kind} onChange={(kind) => setFilters({ kind })} options={KINDS.map((k) => ({ value: k, label: t.enums.violationKind[k] }))} />
        </Toolbar>
        <DataTable<Violation>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(v) => v.id}
          columns={[
            { key: "subject", header: tr.subject, cell: (v) => <Person name={v.subject_name} phone={v.subject_phone} sub={enumLabel(t, "actorRole", v.subject_role)} /> },
            { key: "kind", header: tr.kind, cell: (v) => <span className="font-medium">{enumLabel(t, "violationKind", v.kind)}</span> },
            {
              key: "evidence",
              header: tr.evidence,
              hideBelow: "md",
              cell: (v) => (
                <div>
                  <button
                    type="button"
                    className="inline-flex items-center gap-1 text-xs font-medium text-teal-700 hover:underline"
                    aria-expanded={expanded === v.id}
                    onClick={() => setExpanded(expanded === v.id ? null : v.id)}
                  >
                    {t.common.details}
                    <ChevronDown className={`size-3.5 ${expanded === v.id ? "rotate-180" : ""}`} aria-hidden />
                  </button>
                  {expanded === v.id ? (
                    <div className="mt-2 max-w-md space-y-2">
                      <JsonView value={v.evidence} />
                      {v.ride ? (
                        <Link href={`/operator/rides/${v.ride}`} className="text-xs font-medium text-teal-700 hover:underline">
                          {t.nav.rides} →
                        </Link>
                      ) : null}
                      {v.review_note ? <p className="text-xs text-muted">{tr.reviewedBy}: {v.reviewed_by_name} — {v.review_note}</p> : null}
                    </div>
                  ) : null}
                </div>
              ),
            },
            { key: "created", header: t.common.created, hideBelow: "sm", cell: (v) => fmt.relative(v.created_at) },
            { key: "status", header: t.common.status, cell: (v) => <EnumBadge group="violationStatus" value={v.status} /> },
            {
              key: "actions",
              header: <span className="sr-only">{t.common.actions}</span>,
              align: "end",
              cell: (v) =>
                v.status === "pending_review" ? (
                  <span className="inline-flex gap-1.5">
                    <Button size="sm" variant="danger" onClick={() => setReview({ v, verify: true })}>
                      {tr.verify}
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => setReview({ v, verify: false })}>
                      {tr.dismiss}
                    </Button>
                  </span>
                ) : null,
            },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
      <ConfirmDialog
        open={review !== null}
        onClose={() => setReview(null)}
        title={review ? `${review.verify ? tr.verify : tr.dismiss} · ${enumLabel(t, "violationKind", review.v.kind)}` : ""}
        message={review?.verify ? tr.verifyConfirm : undefined}
        confirmLabel={review?.verify ? tr.verify : tr.dismiss}
        tone={review?.verify ? "danger" : "primary"}
        note={{ label: t.common.reason, required: true }}
        onConfirm={(note) => action.mutateAsync({ id: review!.v.id, body: { verify: review!.verify, note } })}
      />
    </>
  );
}

export default function ViolationsPage() {
  return (
    <Suspense>
      <ViolationsList />
    </Suspense>
  );
}
