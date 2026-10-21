"use client";

import { useState } from "react";

import { EnumBadge, enumLabel, Person } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { ConfirmDialog } from "@/components/ui/Dialog";
import { FilterSelect, PageHeader, Tabs, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useAction, useApiPage, useListState } from "@/lib/api/hooks";

type Action = Schemas["Enforcement"];

export default function EnforcementPage() {
  const { t, tpl } = useI18n();
  const { fmt, can } = useSession();
  const tr = t.trust;
  const manage = can("enforcement.manage");
  const { filters, setFilters, page, setPage } = useListState<{ status: string; action_type: string }>({ status: "proposed", action_type: "" });
  const q = useApiPage<Action>("admin/enforcement-actions", filters, page);
  const [target, setTarget] = useState<{ a: Action; op: "activate" | "revoke" } | null>(null);
  const run = useAction<{ id: string; op: string; body: { note: string } }>("POST", (v) => `admin/enforcement-actions/${v.id}/${v.op}`, {
    invalidate: ["admin/enforcement-actions"],
    inlineErrors: true,
    success: tr.enforcementTitle,
  });
  return (
    <>
      <PageHeader title={tr.enforcementTitle} subtitle={tr.enforcementSubtitle} />
      <Card padded={false}>
        <Tabs
          label={t.common.status}
          value={filters.status}
          onChange={(status) => setFilters({ status })}
          items={[...(["proposed", "active", "revoked"] as const).map((v) => ({ value: v as string, label: t.enums.enforcementStatus[v] })), { value: "", label: t.common.all }]}
        />
        <Toolbar>
          <FilterSelect
            label={tr.action}
            value={filters.action_type}
            onChange={(action_type) => setFilters({ action_type })}
            options={(["warning", "commitment_effect", "restriction", "escalation"] as const).map((v) => ({ value: v, label: t.enums.enforcementType[v] }))}
          />
        </Toolbar>
        <DataTable<Action>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(a) => a.id}
          columns={[
            { key: "subject", header: tr.subject, cell: (a) => <Person name={a.subject_name} sub={enumLabel(t, "actorRole", a.subject_role)} /> },
            { key: "action", header: tr.action, cell: (a) => <span className="font-medium">{enumLabel(t, "enforcementType", a.action_type)}</span> },
            { key: "level", header: tr.level, align: "end", hideBelow: "sm", cell: (a) => <span className="ltr-nums">{a.level || "—"}</span> },
            { key: "duration", header: tr.duration, hideBelow: "md", cell: (a) => (a.duration_hours ? tpl(tr.hours, { n: a.duration_hours }) : "—") },
            { key: "ends", header: tr.ends, hideBelow: "lg", cell: (a) => fmt.dateTime(a.ends_at) },
            { key: "reason", header: t.common.reason, hideBelow: "lg", cell: (a) => <span className="line-clamp-2 max-w-64 text-xs text-muted">{a.reason}</span> },
            { key: "status", header: t.common.status, cell: (a) => <EnumBadge group="enforcementStatus" value={a.status} /> },
            {
              key: "actions",
              header: <span className="sr-only">{t.common.actions}</span>,
              align: "end",
              cell: (a) =>
                manage ? (
                  <span className="inline-flex gap-1.5">
                    {a.status === "proposed" && a.action_type === "restriction" ? (
                      <Button size="sm" variant="danger" onClick={() => setTarget({ a, op: "activate" })}>
                        {tr.activate}
                      </Button>
                    ) : null}
                    {a.status !== "revoked" ? (
                      <Button size="sm" variant="secondary" onClick={() => setTarget({ a, op: "revoke" })}>
                        {tr.revoke}
                      </Button>
                    ) : null}
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
        title={target?.op === "activate" ? tr.activate : tr.revoke}
        message={target?.op === "activate" ? tr.activateConfirm : tr.revokeConfirm}
        confirmLabel={target?.op === "activate" ? tr.activate : tr.revoke}
        tone={target?.op === "activate" ? "danger" : "primary"}
        note={target?.op === "revoke" ? { label: t.common.reason, required: true } : undefined}
        onConfirm={(note) => run.mutateAsync({ id: target!.a.id, op: target!.op, body: { note } })}
      />
    </>
  );
}
