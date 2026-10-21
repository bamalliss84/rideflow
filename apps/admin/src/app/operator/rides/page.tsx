"use client";

import { X } from "lucide-react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useMemo } from "react";

import { EnumBadge, Person } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, SearchInput, Toolbar } from "@/components/ui/Page";
import type { Page, Schemas } from "@/lib/api/client";
import { useApi, useApiPage, useListState } from "@/lib/api/hooks";

type Ride = Schemas["AdminRide"];
type City = Schemas["City"];
const STATUS_GROUPS: Record<string, string[]> = {
  active: ["requested", "bidding", "match_pending", "assigned", "en_route", "arrived", "in_progress"],
  completed: ["completed"],
  cancelled: ["cancelled"],
  no_show: ["no_show"],
  disputed: ["disputed"],
};

function RidesList() {
  const { t, dir } = useI18n();
  const { fmt } = useSession();
  const router = useRouter();
  const params = useSearchParams();
  const scoped = { driver: params.get("driver") ?? "", rider: params.get("rider") ?? "" };
  const { filters, setFilters, page, setPage } = useListState<{ group: string; rider_phone: string; city: string }>({ group: "", rider_phone: "", city: "" });
  const query = useMemo(
    () => ({ status: filters.group ? STATUS_GROUPS[filters.group] : undefined, rider_phone: filters.rider_phone, city: filters.city, ...scoped }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [filters, scoped.driver, scoped.rider],
  );
  const q = useApiPage<Ride>("admin/rides", query, page);
  const cities = useApi<Page<City>>("admin/cities", { page_size: 100 });
  const groupLabels: Record<string, string> = {
    active: t.dashboard.live,
    completed: t.enums.rideStatus.completed,
    cancelled: t.enums.rideStatus.cancelled,
    no_show: t.enums.rideStatus.no_show,
    disputed: t.enums.rideStatus.disputed,
  };

  return (
    <>
      <PageHeader title={t.rides.title} subtitle={t.rides.subtitle} />
      <Card padded={false}>
        <Toolbar>
          <SearchInput value={filters.rider_phone} onChange={(v) => setFilters({ rider_phone: v })} placeholder={t.rides.riderPhone} />
          <FilterSelect label={t.common.status} value={filters.group} onChange={(group) => setFilters({ group })} options={Object.keys(STATUS_GROUPS).map((k) => ({ value: k, label: groupLabels[k] ?? k }))} />
          <FilterSelect label={t.common.city} value={filters.city} onChange={(city) => setFilters({ city })} options={(cities.data?.results ?? []).map((c) => ({ value: c.id, label: c.name }))} />
          {scoped.driver || scoped.rider ? (
            <button type="button" onClick={() => router.replace("/operator/rides")} className="inline-flex items-center gap-1">
              <Badge tone="info">
                {scoped.driver ? t.common.driver : t.common.rider}
                <X className="size-3" aria-label={t.common.clear} />
              </Badge>
            </button>
          ) : null}
        </Toolbar>
        <DataTable<Ride>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(r) => r.id}
          rowHref={(r) => `/operator/rides/${r.id}`}
          columns={[
            {
              key: "created",
              header: t.common.date,
              className: "whitespace-nowrap",
              cell: (r) => (
                <Link href={`/operator/rides/${r.id}`} className="hover:underline">
                  {fmt.dateTime(r.created_at)}
                </Link>
              ),
            },
            { key: "rider", header: t.common.rider, cell: (r) => <Person name={r.rider_name} phone={r.rider_phone} /> },
            { key: "driver", header: t.common.driver, hideBelow: "md", cell: (r) => (r.driver_name ? <Person name={r.driver_name} phone={r.driver_phone} /> : <span className="text-subtle">—</span>) },
            { key: "city", header: t.common.city, hideBelow: "lg", cell: (r) => r.city_name },
            { key: "route", header: t.rides.route, hideBelow: "lg", cell: (r) => <span className="line-clamp-2 max-w-64 text-xs text-muted">{r.pickup_landmark} {dir === "rtl" ? "←" : "→"} {r.dropoff_landmark}</span> },
            { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="rideStatus" value={r.status} /> },
            {
              key: "fare",
              header: t.rides.fare,
              align: "end",
              cell: (r) =>
                r.agreed_fare_minor !== null ? (
                  <span className="font-medium ltr-nums">{fmt.money(r.agreed_fare_minor, r.currency)}</span>
                ) : (
                  <span className="text-xs text-muted ltr-nums" title={t.common.estimate}>
                    {fmt.money(r.estimate_min_minor, r.currency)} – {fmt.money(r.estimate_max_minor, r.currency)}
                  </span>
                ),
            },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}

export default function RidesPage() {
  return (
    <Suspense>
      <RidesList />
    </Suspense>
  );
}
