"use client";

import { enumLabel, Person, Stars } from "@/components/domain/Display";
import { TIER_TONE } from "@/components/domain/TrustSummary";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, Tabs, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Snapshot = Schemas["TrustSnapshot"];

export default function ScoresPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const tr = t.trust;
  const { filters, setFilters, page, setPage } = useListState<{ role: string; tier: string; ordering: string }>({ role: "driver", tier: "", ordering: "-score" });
  const q = useApiPage<Snapshot>("admin/trust-snapshots", filters, page);
  return (
    <>
      <PageHeader title={tr.scoresTitle} subtitle={tr.scoresSubtitle} />
      <Card padded={false}>
        <Tabs
          label={t.common.role}
          value={filters.role}
          onChange={(role) => setFilters({ role })}
          items={[
            { value: "driver", label: t.nav.drivers },
            { value: "rider", label: t.nav.riders },
          ]}
        />
        <Toolbar>
          <FilterSelect
            label={tr.tier}
            value={filters.tier}
            onChange={(tier) => setFilters({ tier })}
            options={(["new", "bronze", "silver", "gold", "diamond"] as const).map((v) => ({ value: v, label: t.enums.tier[v] }))}
          />
          <FilterSelect
            label={t.common.sortBy}
            allowAll={false}
            value={filters.ordering}
            onChange={(ordering) => setFilters({ ordering: ordering || "-score" })}
            options={[
              { value: "-score", label: tr.score },
              { value: "-rating_avg", label: tr.ratingAvg },
              { value: "-completed_rides", label: tr.completedRides },
            ]}
          />
        </Toolbar>
        <DataTable<Snapshot>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(s) => `${s.user}-${s.role}`}
          columns={[
            { key: "user", header: tr.subject, cell: (s) => <Person name={s.user_name} phone={s.user_phone} /> },
            { key: "score", header: tr.score, align: "end", cell: (s) => <span className="text-base font-semibold ltr-nums">{fmt.number(s.score)}</span> },
            { key: "tier", header: tr.tier, cell: (s) => <Badge tone={TIER_TONE[s.tier] ?? "neutral"}>{enumLabel(t, "tier", s.tier)}</Badge> },
            {
              key: "rating",
              header: tr.ratingAvg,
              hideBelow: "sm",
              cell: (s) => (
                <span className="flex items-center gap-2">
                  <Stars value={Math.round(s.rating_avg)} />
                  <span className="text-xs text-muted ltr-nums">
                    {s.rating_avg.toFixed(2)} ({fmt.number(s.rating_count)})
                  </span>
                </span>
              ),
            },
            { key: "completed", header: tr.completedRides, align: "end", hideBelow: "md", cell: (s) => fmt.number(s.completed_rides) },
            { key: "completion", header: tr.completionRate, align: "end", hideBelow: "lg", cell: (s) => fmt.percent(s.completion_rate) },
            { key: "updated", header: t.common.updated, hideBelow: "lg", cell: (s) => fmt.relative(s.updated_at) },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}
