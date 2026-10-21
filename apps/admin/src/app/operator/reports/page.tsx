"use client";

import { Download } from "lucide-react";
import { useMemo, useState } from "react";

import { BarChart } from "@/components/charts/BarChart";
import { enumLabel } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader, StatCard } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { PageHeader, RangePicker, rangeFromPreset, type RangePreset } from "@/components/ui/Page";
import { ErrorState } from "@/components/ui/States";
import { useApi } from "@/lib/api/hooks";
import { downloadText, toCsv } from "@/lib/format";

interface DailyRow {
  day: string;
  requested: number;
  matched: number;
  completed: number;
  cancelled: number;
  no_show: number;
  fare_total_minor: number;
}
interface Daily {
  currency: string;
  time_zone: string;
  rows: DailyRow[];
}
interface Subs {
  currency: string;
  claims_by_status: Record<string, number>;
  approved_total_minor: number;
  approved_by_plan: { plan__code: string; plan__name: string; n: number; total_minor: number }[];
}

export default function ReportsPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const r = t.reports;
  const [preset, setPreset] = useState<RangePreset>("30");
  const range = useMemo(() => rangeFromPreset(preset), [preset]);
  const daily = useApi<Daily>("admin/reports/rides-daily", range);
  const subs = useApi<Subs>("admin/reports/subscriptions", range);

  const exportDaily = () => {
    if (!daily.data) return;
    downloadText(
      `rideflow-rides-daily-${preset}d.csv`,
      toCsv(
        daily.data.rows.map((row) => ({ ...row, fare: fmt.money(row.fare_total_minor, daily.data?.currency) })),
        [
          { key: "day", label: r.day },
          { key: "requested", label: t.dashboard.requested },
          { key: "matched", label: t.dashboard.matched },
          { key: "completed", label: t.dashboard.completed },
          { key: "cancelled", label: t.dashboard.cancelled },
          { key: "no_show", label: t.dashboard.noShow },
          { key: "fare", label: t.dashboard.fareTotal },
        ],
      ),
    );
  };

  return (
    <>
      <PageHeader title={r.title} subtitle={r.subtitle} actions={<RangePicker value={preset} onChange={setPreset} />} />
      <div className="space-y-6">
        <Card padded={false}>
          <CardHeader
            title={r.ridesDaily}
            subtitle={daily.data ? `${daily.data.time_zone}` : undefined}
            actions={
              <Button size="sm" variant="secondary" icon={<Download className="size-4" aria-hidden />} onClick={exportDaily} disabled={!daily.data?.rows.length}>
                {t.common.exportCsv}
              </Button>
            }
          />
          {daily.error ? (
            <ErrorState error={daily.error} onRetry={() => void daily.refetch()} />
          ) : (
            <>
              <div className="p-5">
                <BarChart
                  data={(daily.data?.rows ?? []).map((row) => ({ label: fmt.day(row.day), value: row.requested, secondary: row.completed }))}
                  primaryLabel={t.dashboard.requested}
                  secondaryLabel={t.dashboard.completed}
                  format={(v) => fmt.number(v)}
                />
              </div>
              <DataTable<DailyRow>
                rows={daily.data?.rows}
                loading={daily.isPending}
                rowKey={(row) => row.day}
                columns={[
                  { key: "day", header: r.day, cell: (row) => fmt.day(row.day) },
                  { key: "requested", header: t.dashboard.requested, align: "end", cell: (row) => fmt.number(row.requested) },
                  { key: "matched", header: t.dashboard.matched, align: "end", hideBelow: "sm", cell: (row) => fmt.number(row.matched) },
                  { key: "completed", header: t.dashboard.completed, align: "end", cell: (row) => fmt.number(row.completed) },
                  { key: "cancelled", header: t.dashboard.cancelled, align: "end", hideBelow: "md", cell: (row) => fmt.number(row.cancelled) },
                  { key: "no_show", header: t.dashboard.noShow, align: "end", hideBelow: "md", cell: (row) => fmt.number(row.no_show) },
                  { key: "fare", header: t.dashboard.fareTotal, align: "end", hideBelow: "lg", cell: (row) => <span className="ltr-nums">{fmt.money(row.fare_total_minor, daily.data?.currency)}</span> },
                ]}
              />
            </>
          )}
        </Card>

        <Card padded={false}>
          <CardHeader title={r.subscriptions} />
          {subs.error ? (
            <ErrorState error={subs.error} onRetry={() => void subs.refetch()} />
          ) : (
            <div className="grid gap-6 p-5 lg:grid-cols-3">
              <div className="space-y-4">
                <StatCard label={r.approvedTotal} value={fmt.money(subs.data?.approved_total_minor ?? 0, subs.data?.currency)} tone="accent" />
                <div>
                  <h3 className="mb-2 text-xs font-medium text-muted">{r.byStatus}</h3>
                  <dl className="space-y-2 text-sm">
                    {(["submitted", "first_approved", "approved", "rejected"] as const).map((s) => (
                      <div key={s} className="flex justify-between gap-3">
                        <dt>{enumLabel(t, "claimStatus", s)}</dt>
                        <dd className="font-semibold ltr-nums">{fmt.number(subs.data?.claims_by_status[s] ?? 0)}</dd>
                      </div>
                    ))}
                  </dl>
                </div>
              </div>
              <div className="lg:col-span-2">
                <h3 className="mb-2 text-xs font-medium text-muted">{r.byPlan}</h3>
                <div className="rounded-md border border-line">
                  <DataTable
                    rows={subs.data?.approved_by_plan}
                    loading={subs.isPending}
                    rowKey={(row) => row.plan__code}
                    columns={[
                      { key: "plan", header: t.subscriptions.plan, cell: (row) => row.plan__name },
                      { key: "n", header: r.count, align: "end", cell: (row) => fmt.number(row.n) },
                      { key: "total", header: r.total, align: "end", cell: (row) => <span className="ltr-nums">{fmt.money(row.total_minor, subs.data?.currency)}</span> },
                    ]}
                  />
                </div>
              </div>
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
