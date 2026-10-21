"use client";

import { useState } from "react";

import { EnumBadge } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { ConfirmDialog } from "@/components/ui/Dialog";
import { PageHeader, Tabs } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useAction, useApiPage, useListState } from "@/lib/api/hooks";

type Appeal = Schemas["Appeal"];

export default function AppealsPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const tr = t.trust;
  const { filters, setFilters, page, setPage } = useListState<{ status: string }>({ status: "pending" });
  const q = useApiPage<Appeal>("admin/appeals", filters, page);
  const [target, setTarget] = useState<{ a: Appeal; uphold: boolean } | null>(null);
  const decide = useAction<{ id: string; body: { uphold: boolean; note: string } }>("POST", (v) => `admin/appeals/${v.id}/decide`, {
    invalidate: ["admin/appeals", "admin/violations", "admin/enforcement-actions", "admin/dashboard"],
    inlineErrors: true,
    success: tr.decide,
  });
  return (
    <>
      <PageHeader title={tr.appealsTitle} subtitle={tr.appealsSubtitle} />
      <Card padded={false}>
        <Tabs
          label={t.common.status}
          value={filters.status}
          onChange={(status) => setFilters({ status })}
          items={[...(["pending", "upheld", "rejected"] as const).map((v) => ({ value: v as string, label: t.enums.appealStatus[v] })), { value: "", label: t.common.all }]}
        />
        <DataTable<Appeal>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(a) => a.id}
          columns={[
            { key: "appellant", header: tr.appellant, cell: (a) => <span className="font-medium">{a.appellant_name || "—"}</span> },
            { key: "reason", header: t.common.reason, cell: (a) => <span className="line-clamp-3 max-w-96 text-sm">{a.reason}</span> },
            { key: "created", header: t.common.created, hideBelow: "sm", cell: (a) => fmt.relative(a.created_at) },
            { key: "decision", header: tr.resolution, hideBelow: "lg", cell: (a) => (a.decided_at ? `${a.decided_by_name ?? "—"} — ${a.decision_note}` : "—") },
            { key: "status", header: t.common.status, cell: (a) => <EnumBadge group="appealStatus" value={a.status} /> },
            {
              key: "actions",
              header: <span className="sr-only">{t.common.actions}</span>,
              align: "end",
              cell: (a) =>
                a.status === "pending" ? (
                  <span className="inline-flex flex-wrap justify-end gap-1.5">
                    <Button size="sm" variant="accent" onClick={() => setTarget({ a, uphold: true })}>
                      {tr.upholdAppeal}
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => setTarget({ a, uphold: false })}>
                      {tr.rejectAppeal}
                    </Button>
                  </span>
                ) : null,
            },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
      <ConfirmDialog
        open={target !== null}
        onClose={() => setTarget(null)}
        title={target?.uphold ? tr.upholdAppeal : tr.rejectAppeal}
        message={tr.appealsSubtitle}
        confirmLabel={target?.uphold ? tr.upholdAppeal : tr.rejectAppeal}
        tone={target?.uphold ? "accent" : "primary"}
        note={{ label: t.common.reason, required: true }}
        onConfirm={(note) => decide.mutateAsync({ id: target!.a.id, body: { uphold: target!.uphold, note } })}
      />
    </>
  );
}
