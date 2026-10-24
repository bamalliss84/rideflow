"use client";

import { Banknote, CalendarRange, CheckCircle2, Download, Inbox, Route, XCircle } from "lucide-react";
import { useMemo, useState } from "react";

import { BarChart, fillDays } from "@/components/charts/BarChart";
import { EnumBadge, MetaLine } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader, StatCard } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { PageHeader, RangePicker, rangeFromPreset, type RangePreset } from "@/components/ui/Page";
import { EmptyState, ErrorState, Skeleton } from "@/components/ui/States";
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
  range: { from: string; to: string };
  rows: DailyRow[];
}
interface Subs {
  currency: string;
  claims_by_status: Record<string, number>;
  approved_total_minor: number;
  approved_by_plan: { plan__code: string; plan__name: string; n: number; total_minor: number }[];
}

const COUNTS = ["requested", "matched", "completed", "cancelled", "no_show"] as const;
const emptyRow = (day: string): DailyRow => ({ day, requested: 0, matched: 0, completed: 0, cancelled: 0, no_show: 0, fare_total_minor: 0 });

export default function ReportsPage() {
  const { t, tpl } = useI18n();
  const { fmt } = useSession();
  const r = t.reports;
  const ds = t.dashboard;
  const [preset, setPreset] = useState<RangePreset>("30");
  const range = useMemo(() => rangeFromPreset(preset), [preset]);
  const daily = useApi<Daily>("admin/reports/rides-daily", range);
  const subs = useApi<Subs>("admin/reports/subscriptions", range);

  // Every figure below is a sum of rows returned by the server for this range; nothing is estimated.
  const totals = useMemo(() => {
    const sum = { ...emptyRow("") };
    for (const row of daily.data?.rows ?? []) {
      for (const k of COUNTS) sum[k] += row[k];
      sum.fare_total_minor += row.fare_total_minor;
    }
    return sum;
  }, [daily.data]);
  const days = useMemo(
    () => (daily.data ? fillDays(daily.data.rows, daily.data.range.from, daily.data.range.to, daily.data.time_zone, emptyRow) : []),
    [daily.data],
  );
  const labels: Record<(typeof COUNTS)[number], string> = {
    requested: ds.requested,
    matched: ds.matched,
    completed: ds.completed,
    cancelled: ds.cancelled,
    no_show: ds.noShow,
  };

  const exportDaily = () => {
    const data = daily.data;
    if (!data) return;
    const first = days[0]?.day ?? "";
    const last = days[days.length - 1]?.day ?? "";
    downloadText(
      `rideflow-rides-daily_${first}_${last}.csv`,
      toCsv(
        data.rows.map((row) => ({ ...row, fare: fmt.amount(row.fare_total_minor), currency: data.currency })),
        [
          { key: "day", label: r.day },
          ...COUNTS.map((k) => ({ key: k, label: labels[k] })),
          { key: "fare", label: ds.fareTotal },
          { key: "currency", label: r.currency },
        ],
      ),
    );
  };

  const rangeText = daily.data ? (
    <MetaLine
      parts={[
        <span key="r" className="inline-flex items-center gap-1">
          <CalendarRange className="size-3.5" aria-hidden />
          <bdi>{fmt.day(days[0]?.day)}</bdi>
          <span aria-hidden>–</span>
          <bdi>{fmt.day(days[days.length - 1]?.day)}</bdi>
        </span>,
        <span key="tz">
          {r.timeZone}: <span className="ltr-nums">{daily.data.time_zone}</span>
        </span>,
      ]}
    />
  ) : null;

  return (
    <>
      <PageHeader title={r.title} subtitle={r.subtitle} actions={<RangePicker value={preset} onChange={setPreset} />} />
      <div className="space-y-6">
        {daily.error ? (
          <Card padded={false}>
            <ErrorState error={daily.error} onRetry={() => void daily.refetch()} />
          </Card>
        ) : (
          <>
            <div className="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4">
              {daily.isPending ? (
                [0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-[84px] rounded-xl" />)
              ) : (
                <>
                  <StatCard label={ds.requested} value={fmt.number(totals.requested)} icon={<Route className="size-5" />} />
                  <StatCard
                    label={ds.completed}
                    value={fmt.number(totals.completed)}
                    hint={
                      totals.requested ? (
                        <>
                          <bdi>{fmt.percent(totals.completed / totals.requested)}</bdi> {r.ofRequested}
                        </>
                      ) : undefined
                    }
                    icon={<CheckCircle2 className="size-5" />}
                    tone="accent"
                  />
                  <StatCard
                    label={`${ds.cancelled} / ${ds.noShow}`}
                    value={
                      <span className="inline-flex items-baseline gap-1.5">
                        {fmt.number(totals.cancelled)}
                        <span className="text-base text-subtle">/</span>
                        {fmt.number(totals.no_show)}
                      </span>
                    }
                    icon={<XCircle className="size-5" />}
                    tone="warning"
                  />
                  <StatCard label={ds.fareTotal} value={fmt.money(totals.fare_total_minor, daily.data?.currency)} hint={r.fareNote} icon={<Banknote className="size-5" />} />
                </>
              )}
            </div>

            <Card padded={false}>
              <CardHeader
                title={r.ridesDaily}
                subtitle={rangeText}
                actions={
                  <Button size="sm" variant="secondary" icon={<Download className="size-4" aria-hidden />} onClick={exportDaily} disabled={!daily.data?.rows.length}>
                    {t.common.exportCsv}
                  </Button>
                }
              />
              <div className="p-5">
                {daily.isPending ? (
                  <Skeleton className="h-[230px]" />
                ) : (
                  <>
                    <BarChart
                      data={days.map((row) => ({ label: fmt.shortDay(row.day), values: { requested: row.requested, matched: row.matched, completed: row.completed } }))}
                      series={[
                        { key: "requested", label: ds.requested, tone: "requested" },
                        { key: "matched", label: ds.matched, tone: "matched" },
                        { key: "completed", label: ds.completed, tone: "completed" },
                      ]}
                      format={(v) => fmt.number(v)}
                      emptyLabel={r.noRides}
                    />
                    {daily.data?.rows.length ? (
                      <p className="mt-2 text-xs text-muted">{tpl(r.activeDays, { n: daily.data.rows.length, total: days.length })}</p>
                    ) : null}
                  </>
                )}
              </div>
              <div className="border-t border-line">
                <DataTable<DailyRow>
                  rows={daily.data?.rows.slice().reverse()}
                  loading={daily.isPending}
                  rowKey={(row) => row.day}
                  caption={r.ridesDaily}
                  empty={<EmptyState icon={<Inbox className="size-6" aria-hidden />} title={r.noRides} hint={r.noRidesHint} />}
                  columns={[
                    { key: "day", header: r.day, className: "whitespace-nowrap", cell: (row) => <bdi>{fmt.day(row.day)}</bdi> },
                    ...COUNTS.map((k) => ({
                      key: k,
                      header: labels[k],
                      align: "end" as const,
                      hideBelow: k === "matched" ? ("sm" as const) : k === "cancelled" || k === "no_show" ? ("md" as const) : undefined,
                      cell: (row: DailyRow) => <span className={`ltr-nums ${row[k] ? "" : "text-subtle"}`}>{fmt.number(row[k])}</span>,
                    })),
                    { key: "fare", header: ds.fareTotal, align: "end", hideBelow: "lg", cell: (row) => <bdi className="whitespace-nowrap">{fmt.money(row.fare_total_minor, daily.data?.currency)}</bdi> },
                  ]}
                />
              </div>
            </Card>
          </>
        )}

        <Card padded={false}>
          <CardHeader title={r.subscriptions} subtitle={r.subscriptionsHint} />
          {subs.error ? (
            <ErrorState error={subs.error} onRetry={() => void subs.refetch()} />
          ) : (
            <div className="grid gap-6 p-5 lg:grid-cols-3">
              <div className="space-y-4">
                <StatCard label={r.approvedTotal} value={subs.isPending ? "…" : fmt.money(subs.data?.approved_total_minor ?? 0, subs.data?.currency)} tone="accent" icon={<Banknote className="size-5" />} />
                <div className="rounded-xl border border-line p-4">
                  <h3 className="mb-3 text-xs font-semibold text-muted">{r.byStatus}</h3>
                  <dl className="space-y-2.5 text-sm">
                    {(["submitted", "first_approved", "approved", "rejected"] as const).map((s) => (
                      <div key={s} className="flex items-center justify-between gap-3">
                        <dt>
                          <EnumBadge group="claimStatus" value={s} />
                        </dt>
                        <dd className="font-semibold ltr-nums">{fmt.number(subs.data?.claims_by_status[s] ?? 0)}</dd>
                      </div>
                    ))}
                  </dl>
                </div>
              </div>
              <div className="min-w-0 lg:col-span-2">
                <h3 className="mb-2 text-xs font-semibold text-muted">{r.byPlan}</h3>
                <div className="overflow-hidden rounded-xl border border-line">
                  <DataTable
                    rows={subs.data?.approved_by_plan}
                    loading={subs.isPending}
                    rowKey={(row) => row.plan__code}
                    empty={<EmptyState title={r.noApproved} hint={r.noApprovedHint} />}
                    columns={[
                      { key: "plan", header: t.subscriptions.plan, cell: (row) => <bdi className="font-medium">{row.plan__name}</bdi> },
                      { key: "n", header: r.count, align: "end", cell: (row) => <span className="ltr-nums">{fmt.number(row.n)}</span> },
                      { key: "total", header: r.total, align: "end", cell: (row) => <bdi className="whitespace-nowrap">{fmt.money(row.total_minor, subs.data?.currency)}</bdi> },
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
