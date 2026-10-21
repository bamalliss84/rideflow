"use client";

import { ChevronDown } from "lucide-react";
import { useState } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { SearchInput, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

import { humanize, JsonView } from "./Display";

type Event = Schemas["AuditEvent"];

/** Immutable audit trail table (operator or platform scope, decided by `path`). */
export function AuditLog({ path }: { path: string }) {
  const { t } = useI18n();
  const { fmt } = useSession();
  const { filters, setFilters, page, setPage } = useListState<{ action: string }>({ action: "" });
  const q = useApiPage<Event>(path, filters, page, 30);
  const [open, setOpen] = useState<string | null>(null);
  return (
    <Card padded={false}>
      <Toolbar>
        <SearchInput value={filters.action} onChange={(action) => setFilters({ action })} placeholder={t.audit.actionPrefix} />
      </Toolbar>
      <DataTable<Event>
        rows={q.data?.results}
        loading={q.isPending}
        error={q.error}
        onRetry={() => void q.refetch()}
        rowKey={(r) => r.id}
        empty={undefined}
        columns={[
          { key: "time", header: t.common.date, className: "whitespace-nowrap", cell: (r) => <span className="text-muted">{fmt.dateTime(r.created_at)}</span> },
          { key: "actor", header: t.audit.actor, cell: (r) => r.actor_name || (r.actor ? "—" : t.audit.system) },
          {
            key: "action",
            header: t.audit.action,
            cell: (r) => (
              <span className="flex flex-col">
                <span className="font-medium">{humanize(r.action)}</span>
                <code className="text-[0.7rem] text-subtle ltr-nums">{r.action}</code>
              </span>
            ),
          },
          { key: "target", header: t.audit.target, hideBelow: "md", cell: (r) => (r.target_type ? humanize(r.target_type) : "—") },
          {
            key: "data",
            header: t.audit.data,
            hideBelow: "sm",
            cell: (r) =>
              r.data && Object.keys(r.data as object).length ? (
                <div>
                  <button
                    type="button"
                    className="inline-flex items-center gap-1 text-xs font-medium text-teal-700 hover:underline"
                    aria-expanded={open === r.id}
                    onClick={() => setOpen(open === r.id ? null : r.id)}
                  >
                    {t.common.details}
                    <ChevronDown className={`size-3.5 transition-transform ${open === r.id ? "rotate-180" : ""}`} aria-hidden />
                  </button>
                  {open === r.id ? (
                    <div className="mt-2 max-w-md">
                      <JsonView value={r.data} />
                    </div>
                  ) : null}
                </div>
              ) : (
                <span className="text-subtle">—</span>
              ),
          },
        ]}
      />
      <Pagination page={page} pageSize={30} count={q.data?.count ?? 0} onPage={setPage} />
    </Card>
  );
}
