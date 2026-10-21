"use client";

import Link from "next/link";

import { EnumBadge, Person } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, SearchInput, Tabs, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Driver = Schemas["AdminDriver"];
const STATUSES = ["under_review", "approved", "pending_documents", "rejected", "suspended"] as const;

export default function DriversPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const dr = t.drivers;
  const { filters, setFilters, page, setPage } = useListState<{ status: string; q: string; is_online: string }>({ status: "", q: "", is_online: "" });
  const q = useApiPage<Driver>("admin/drivers", filters, page);

  return (
    <>
      <PageHeader title={dr.title} subtitle={dr.subtitle} />
      <Card padded={false}>
        <Tabs
          label={t.common.status}
          value={filters.status}
          onChange={(status) => setFilters({ status })}
          items={[{ value: "", label: t.common.all }, ...STATUSES.map((s) => ({ value: s, label: t.enums.driverStatus[s] }))]}
        />
        <Toolbar>
          <SearchInput value={filters.q} onChange={(v) => setFilters({ q: v })} placeholder={dr.searchPlaceholder} />
          <FilterSelect
            label={dr.availability}
            value={filters.is_online as "" | "true" | "false"}
            onChange={(v) => setFilters({ is_online: v })}
            options={[
              { value: "true", label: t.common.online },
              { value: "false", label: t.common.offline },
            ]}
          />
        </Toolbar>
        <DataTable<Driver>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(r) => r.id}
          rowHref={(r) => `/operator/drivers/${r.id}`}
          empty={undefined}
          columns={[
            {
              key: "name",
              header: t.common.driver,
              cell: (r) => (
                <Link href={`/operator/drivers/${r.id}`} className="hover:underline">
                  <Person name={r.full_name} phone={r.phone} />
                </Link>
              ),
            },
            { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="driverStatus" value={r.status} /> },
            {
              key: "online",
              header: dr.availability,
              hideBelow: "sm",
              cell: (r) => <Badge tone={r.is_online ? "success" : "neutral"}>{r.is_online ? t.common.online : t.common.offline}</Badge>,
            },
            {
              key: "vehicle",
              header: dr.vehicle,
              hideBelow: "md",
              cell: (r) => {
                const v = r.vehicles[0];
                return v ? (
                  <span className="flex flex-col">
                    <span>
                      {v.make} {v.model} · {v.color}
                    </span>
                    <span className="text-xs text-muted ltr-nums">{v.plate_number}</span>
                  </span>
                ) : (
                  <span className="text-subtle">—</span>
                );
              },
            },
            { key: "docs", header: dr.documents, hideBelow: "lg", align: "end", cell: (r) => <span className="ltr-nums">{fmt.number(r.documents.length)}</span> },
            { key: "submitted", header: dr.submitted, hideBelow: "lg", cell: (r) => fmt.date(r.submitted_at) },
            { key: "created", header: t.common.created, hideBelow: "md", cell: (r) => fmt.date(r.created_at) },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}
