"use client";

import Link from "next/link";

import { enumLabel } from "@/components/domain/Display";
import { SubscriptionState } from "@/components/domain/SubscriptionState";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Sub = Schemas["DriverSubscription"];

export default function ActiveSubscriptionsPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const s = t.subscriptions;
  const { filters, setFilters, page, setPage } = useListState<{ source: string }>({ source: "" });
  const q = useApiPage<Sub>("admin/subscriptions", filters, page);
  return (
    <>
      <PageHeader title={s.activeTitle} subtitle={s.activeSubtitle} />
      <Card padded={false}>
        <Toolbar>
          <FilterSelect
            label={s.source}
            value={filters.source as "" | "deposit" | "trial" | "compensation" | "manual"}
            onChange={(source) => setFilters({ source })}
            options={(["deposit", "trial", "compensation", "manual"] as const).map((v) => ({ value: v, label: t.enums.subscriptionSource[v] }))}
          />
        </Toolbar>
        <DataTable<Sub>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(r) => r.id}
          columns={[
            {
              key: "driver",
              header: t.common.driver,
              cell: (r) => (
                <Link href={`/operator/drivers/${r.driver}`} className="font-medium hover:underline">
                  {r.driver_name || "—"}
                </Link>
              ),
            },
            { key: "plan", header: s.plan, hideBelow: "sm", cell: (r) => r.plan_name ?? "—" },
            { key: "source", header: s.source, cell: (r) => enumLabel(t, "subscriptionSource", r.source) },
            { key: "starts", header: s.starts, hideBelow: "md", cell: (r) => fmt.date(r.starts_at) },
            { key: "ends", header: s.ends, cell: (r) => fmt.date(r.ends_at) },
            { key: "state", header: t.common.status, cell: (r) => <SubscriptionState sub={r} /> },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}
