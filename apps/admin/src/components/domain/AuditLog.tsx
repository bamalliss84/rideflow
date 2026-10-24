"use client";

import { ChevronDown } from "lucide-react";
import { useMemo, useState } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge, type Tone } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, rangeFromPreset, SearchInput, Toolbar, type RangePreset } from "@/components/ui/Page";
import { EmptyState } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";
import { auditActionLabel, auditDataKeyLabel, auditDomain, auditTargetLabel } from "@/lib/audit";

import { CopyText, MetaLine } from "./Display";

type Event = Schemas["AuditEvent"];

const DOMAIN_TONE: Record<string, Tone> = { auth: "info", platform: "info", ride: "accent", driver: "success", subscription: "warning", trust: "danger", tenant: "neutral", geo: "neutral" };

function Details({ event }: { event: Event }) {
  const { t } = useI18n();
  const a = t.audit;
  const data = (event.data ?? {}) as Record<string, unknown>;
  const entries = Object.entries(data);
  return (
    <div className="grid gap-4 text-xs md:grid-cols-2">
      <div>
        <p className="mb-1.5 font-semibold text-muted">{a.eventData}</p>
        {entries.length ? (
          <dl className="grid grid-cols-[minmax(7rem,auto)_1fr] gap-x-4 gap-y-1 rounded-lg border border-line bg-white px-3 py-2">
            {entries.map(([k, v]) => (
              <div key={k} className="contents">
                <dt className="text-muted">{auditDataKeyLabel(t, k)}</dt>
                <dd className="break-all text-ink">
                  {typeof v === "boolean" ? (v ? t.common.yes : t.common.no) : <bdi className="ltr-nums">{typeof v === "object" && v !== null ? JSON.stringify(v) : String(v)}</bdi>}
                </dd>
              </div>
            ))}
          </dl>
        ) : (
          <p className="text-subtle">—</p>
        )}
      </div>
      <div>
        <p className="mb-1.5 font-semibold text-muted">{a.technical}</p>
        <dl className="grid grid-cols-[minmax(7rem,auto)_1fr] items-center gap-x-4 gap-y-1.5 rounded-lg border border-line bg-white px-3 py-2">
          <dt className="text-muted">{a.code}</dt>
          <dd>
            <CopyText value={event.action} />
          </dd>
          {event.target_id ? (
            <>
              <dt className="text-muted">{a.targetId}</dt>
              <dd>
                <CopyText value={event.target_id} />
              </dd>
            </>
          ) : null}
          {event.request_id ? (
            <>
              <dt className="text-muted">{a.requestId}</dt>
              <dd>
                <CopyText value={event.request_id} />
              </dd>
            </>
          ) : null}
        </dl>
      </div>
    </div>
  );
}

/** Immutable audit trail (operator or platform scope, decided by `path`). Read-only: nothing here edits records. */
export function AuditLog({ path, domains }: { path: string; domains?: readonly string[] }) {
  const { t } = useI18n();
  const { fmt } = useSession();
  const a = t.audit;
  const { filters, setFilters, page, setPage } = useListState<{ domain: string; code: string; period: string }>({ domain: "", code: "", period: "" });
  // Backend filters: `action` (startswith) and created_from / created_to.
  const query = useMemo(() => {
    const range = filters.period ? rangeFromPreset(filters.period as RangePreset) : null;
    return {
      action: filters.code || (filters.domain ? `${filters.domain}.` : ""),
      created_from: range?.date_from ?? "",
      created_to: range?.date_to ?? "",
    };
  }, [filters]);
  const q = useApiPage<Event>(path, query, page, 30);
  const [open, setOpen] = useState<string | null>(null);
  const filtered = Boolean(filters.domain || filters.code || filters.period);
  return (
    <Card padded={false}>
      <Toolbar>
        {domains?.length ? (
          <FilterSelect
            label={a.category}
            value={filters.domain}
            onChange={(domain) => setFilters({ domain, code: "" })}
            options={domains.map((d) => ({ value: d, label: (a.domains as Record<string, string>)[d] ?? d }))}
          />
        ) : null}
        <FilterSelect
          label={a.period}
          value={filters.period as "" | RangePreset}
          onChange={(period) => setFilters({ period })}
          options={[
            { value: "1", label: t.common.today },
            { value: "7", label: t.common.last7 },
            { value: "30", label: t.common.last30 },
            { value: "90", label: t.common.last90 },
          ]}
        />
        <div className="flex min-w-0 flex-col gap-1 text-xs font-medium text-muted">
          <span>{a.codeSearch}</span>
          <SearchInput value={filters.code} onChange={(code) => setFilters({ code: code.trim() })} placeholder={a.codePlaceholder} />
        </div>
      </Toolbar>
      <DataTable<Event>
        rows={q.data?.results}
        loading={q.isPending}
        error={q.error}
        onRetry={() => void q.refetch()}
        rowKey={(r) => r.id}
        caption={a.title}
        empty={<EmptyState filtered={filtered} />}
        expanded={(r) => (open === r.id ? <Details event={r} /> : null)}
        columns={[
          {
            key: "time",
            header: t.common.date,
            className: "whitespace-nowrap",
            cell: (r) => (
              <span className="flex flex-col">
                <bdi className="text-ink">{fmt.dateTime(r.created_at)}</bdi>
                <span className="text-xs text-muted">{fmt.relative(r.created_at)}</span>
              </span>
            ),
          },
          {
            key: "action",
            header: a.action,
            cell: (r) => (
              <span className="flex min-w-48 flex-col items-start gap-1">
                <span className="font-medium text-ink">{auditActionLabel(t, r.action)}</span>
                <Badge tone={DOMAIN_TONE[auditDomain(r.action)] ?? "neutral"} dot={false}>
                  {(a.domains as Record<string, string>)[auditDomain(r.action)] ?? auditDomain(r.action)}
                </Badge>
              </span>
            ),
          },
          {
            key: "actor",
            header: a.actor,
            cell: (r) =>
              r.actor ? (
                <span className="flex min-w-0 flex-col">
                  <bdi className="self-start font-medium text-ink">{r.actor_name || a.unnamed}</bdi>
                  {(r.actor_roles as string[] | null)?.length ? (
                    <MetaLine parts={(r.actor_roles as string[]).map((role) => (t.roles as Record<string, string>)[role] ?? role)} />
                  ) : null}
                </span>
              ) : (
                <span className="text-muted">{a.system}</span>
              ),
          },
          { key: "target", header: a.target, hideBelow: "md", cell: (r) => <span className="text-ink">{auditTargetLabel(t, r.target_type)}</span> },
          {
            key: "details",
            header: <span className="sr-only">{t.common.details}</span>,
            align: "end",
            cell: (r) => (
              <button
                type="button"
                className="inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium whitespace-nowrap text-teal-700 hover:bg-teal-50"
                aria-expanded={open === r.id}
                onClick={() => setOpen(open === r.id ? null : r.id)}
              >
                {t.common.details}
                <ChevronDown className={`size-3.5 transition-transform ${open === r.id ? "rotate-180" : ""}`} aria-hidden />
              </button>
            ),
          },
        ]}
      />
      <Pagination page={page} pageSize={30} count={q.data?.count ?? 0} onPage={setPage} />
    </Card>
  );
}
