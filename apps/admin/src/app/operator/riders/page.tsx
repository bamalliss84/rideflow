"use client";

import Link from "next/link";

import { EnumBadge, Person } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, SearchInput, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Rider = Schemas["Rider"];

export default function RidersPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const r = t.riders;
  const { filters, setFilters, page, setPage } = useListState<{ q: string; status: string; ordering: string }>({ q: "", status: "", ordering: "-created_at" });
  const q = useApiPage<Rider>("admin/riders", filters, page);
  return (
    <>
      <PageHeader title={r.title} subtitle={r.subtitle} />
      <Card padded={false}>
        <Toolbar>
          <SearchInput value={filters.q} onChange={(v) => setFilters({ q: v })} placeholder={t.drivers.searchPlaceholder} />
          <FilterSelect
            label={t.common.status}
            value={filters.status as "" | "active" | "suspended"}
            onChange={(status) => setFilters({ status })}
            options={(["active", "suspended"] as const).map((v) => ({ value: v, label: t.enums.membershipStatus[v] }))}
          />
          <FilterSelect
            label={t.common.sortBy}
            allowAll={false}
            value={filters.ordering as "" | "-created_at" | "-rides_total" | "-last_ride_at"}
            onChange={(ordering) => setFilters({ ordering: ordering || "-created_at" })}
            options={[
              { value: "-created_at", label: r.joined },
              { value: "-rides_total", label: r.ridesTotal },
              { value: "-last_ride_at", label: r.lastRide },
            ]}
          />
        </Toolbar>
        <DataTable<Rider>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(x) => x.id}
          rowHref={(x) => `/operator/riders/${x.id}`}
          columns={[
            {
              key: "name",
              header: t.common.rider,
              cell: (x) => (
                <Link href={`/operator/riders/${x.id}`} className="hover:underline">
                  <Person name={x.full_name} phone={x.phone} />
                </Link>
              ),
            },
            { key: "status", header: t.common.status, cell: (x) => <EnumBadge group="membershipStatus" value={x.status} /> },
            { key: "rides", header: r.ridesTotal, align: "end", cell: (x) => <span className="ltr-nums">{fmt.number(x.rides_total)}</span> },
            { key: "completed", header: r.ridesCompleted, align: "end", hideBelow: "sm", cell: (x) => <span className="ltr-nums">{fmt.number(x.rides_completed)}</span> },
            { key: "last", header: r.lastRide, hideBelow: "md", cell: (x) => (x.last_ride_at ? fmt.relative(x.last_ride_at) : t.common.never) },
            { key: "joined", header: r.joined, hideBelow: "lg", cell: (x) => fmt.date(x.created_at) },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}
