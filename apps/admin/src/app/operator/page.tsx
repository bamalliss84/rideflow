"use client";

import { AlertTriangle, ArrowUpRight, Car, Clock3, Gavel, MessageSquareWarning, Radio, Receipt, Route, ShieldAlert, UserCheck, Wallet } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState, type ReactNode } from "react";

import { BarChart, RateBar } from "@/components/charts/BarChart";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card, CardHeader, StatCard } from "@/components/ui/Card";
import { PageHeader, RangePicker, rangeFromPreset, type RangePreset } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import { useApi } from "@/lib/api/hooks";
import { filterNav, operatorNav } from "@/lib/nav";

interface Dashboard {
  currency: string;
  drivers: { total: number; approved: number; under_review: number; online: number; with_active_subscription: number };
  rides: Record<string, number>;
  rates: Record<string, number | null>;
  timing_seconds: { median_time_to_first_bid: number | null; median_assignment_to_arrival: number | null };
  riders: { repeat_riders: number; unique_riders: number };
  live: { requests_open: number; awaiting_driver_confirmation: number; on_trip: number; open_bids: number };
  queues: Record<string, number>;
}
interface Daily {
  rows: { day: string; requested: number; completed: number }[];
}

function QueueLink({ href, label, count, icon, urgent }: { href: string; label: string; count: number; icon: ReactNode; urgent?: boolean }) {
  return (
    <Link href={href} className="group flex items-center gap-3 rounded-md px-3 py-2.5 transition-colors hover:bg-navy-50">
      <span className={`flex size-8 items-center justify-center rounded-md ${count && urgent ? "bg-coral-50 text-coral-600" : count ? "bg-amber-50 text-amber-700" : "bg-navy-50 text-navy-400"}`}>{icon}</span>
      <span className="flex-1 text-sm text-ink">{label}</span>
      <span className={`text-sm font-semibold ltr-nums ${count ? "text-ink" : "text-subtle"}`}>{count}</span>
      <ArrowUpRight className="size-4 text-subtle opacity-0 transition-opacity group-hover:opacity-100 rtl:-scale-x-100" aria-hidden />
    </Link>
  );
}

export default function OperatorDashboard() {
  const { t } = useI18n();
  const { fmt, can } = useSession();
  const router = useRouter();
  const [preset, setPreset] = useState<RangePreset>("7");
  const range = useMemo(() => rangeFromPreset(preset), [preset]);
  const allowed = can("reports.view");
  const dash = useApi<Dashboard>(allowed ? "admin/dashboard" : null, range, { refetchInterval: 60_000 });
  const daily = useApi<Daily>(allowed ? "admin/reports/rides-daily" : null, range);

  useEffect(() => {
    if (!allowed) {
      const first = filterNav(operatorNav(t), can).flatMap((g) => g.items).find((i) => i.href !== "/operator");
      router.replace(first?.href ?? "/operator/account");
    }
  }, [allowed, can, router, t]);

  if (!allowed || dash.isPending) return <PageSkeleton />;
  if (dash.error) return <ErrorState error={dash.error} onRetry={() => void dash.refetch()} />;
  const d = dash.data;
  const ds = t.dashboard;

  return (
    <>
      <PageHeader title={ds.title} subtitle={ds.subtitle} actions={<RangePicker value={preset} onChange={setPreset} />} />

      <section aria-labelledby="live-h" className="mb-6">
        <h2 id="live-h" className="mb-3 flex items-center gap-2 text-sm font-semibold text-ink">
          <span className="relative flex size-2.5">
            <span className="absolute inline-flex size-full animate-ping rounded-full bg-teal-500 opacity-60" />
            <span className="relative inline-flex size-2.5 rounded-full bg-teal-600" />
          </span>
          {ds.live}
        </h2>
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard label={ds.openRequests} value={fmt.number(d.live.requests_open)} icon={<Radio className="size-4" />} tone="accent" />
          <StatCard label={ds.awaitingConfirmation} value={fmt.number(d.live.awaiting_driver_confirmation)} icon={<Clock3 className="size-4" />} tone="warning" />
          <StatCard label={ds.onTrip} value={fmt.number(d.live.on_trip)} icon={<Route className="size-4" />} tone="accent" />
          <StatCard label={ds.openBids} value={fmt.number(d.live.open_bids)} icon={<Wallet className="size-4" />} />
        </div>
      </section>

      <div className="grid gap-6 xl:grid-cols-3">
        <div className="space-y-6 xl:col-span-2">
          <Card padded={false}>
            <CardHeader title={ds.period} subtitle={ds.cashNote} />
            <div className="grid grid-cols-2 gap-px bg-line sm:grid-cols-3 lg:grid-cols-6">
              {[
                [ds.requested, d.rides.requested],
                [ds.matched, d.rides.matched],
                [ds.completed, d.rides.completed],
                [ds.cancelled, d.rides.cancelled],
                [ds.noShow, d.rides.no_show],
              ].map(([label, value]) => (
                <div key={String(label)} className="bg-white px-4 py-3">
                  <p className="text-xs text-muted">{label}</p>
                  <p className="mt-1 text-xl font-semibold ltr-nums">{fmt.number(Number(value ?? 0))}</p>
                </div>
              ))}
              <div className="bg-white px-4 py-3">
                <p className="text-xs text-muted">{ds.fareTotal}</p>
                <p className="mt-1 text-xl font-semibold ltr-nums">{fmt.money(d.rides.fare_total_minor ?? 0, d.currency)}</p>
              </div>
            </div>
            <div className="border-t border-line p-5">
              <h3 className="mb-4 text-sm font-semibold">{ds.dailyTrend}</h3>
              {daily.error ? (
                <ErrorState error={daily.error} compact />
              ) : (
                <BarChart
                  data={(daily.data?.rows ?? []).map((r) => ({ label: fmt.day(r.day), value: r.requested, secondary: r.completed }))}
                  primaryLabel={ds.requested}
                  secondaryLabel={ds.completed}
                  format={(v) => fmt.number(v)}
                />
              )}
            </div>
          </Card>
          <div className="grid gap-6 md:grid-cols-2">
            <Card>
              <h3 className="mb-4 text-sm font-semibold">{ds.rates}</h3>
              <div className="space-y-4">
                <RateBar label={ds.bidCoverage} value={d.rates.bid_coverage} />
                <RateBar label={ds.matchRate} value={d.rates.match_rate} />
                <RateBar label={ds.completionRate} value={d.rates.completion_rate} />
                <RateBar label={ds.cancelAfterMatch} value={d.rates.cancellation_after_match_rate} tone="amber" />
                <RateBar label={ds.noShowRate} value={d.rates.no_show_rate} tone="coral" />
              </div>
            </Card>
            <Card>
              <h3 className="mb-4 text-sm font-semibold">{ds.timing}</h3>
              <dl className="space-y-3 text-sm">
                <div className="flex justify-between gap-3">
                  <dt className="text-muted">{ds.firstBid}</dt>
                  <dd className="font-semibold ltr-nums">{fmt.duration(d.timing_seconds.median_time_to_first_bid)}</dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="text-muted">{ds.toArrival}</dt>
                  <dd className="font-semibold ltr-nums">{fmt.duration(d.timing_seconds.median_assignment_to_arrival)}</dd>
                </div>
              </dl>
              <h3 className="mt-6 mb-3 text-sm font-semibold">{ds.riders}</h3>
              <dl className="space-y-3 text-sm">
                <div className="flex justify-between gap-3">
                  <dt className="text-muted">{ds.uniqueRiders}</dt>
                  <dd className="font-semibold ltr-nums">{fmt.number(d.riders.unique_riders)}</dd>
                </div>
                <div className="flex justify-between gap-3">
                  <dt className="text-muted">{ds.repeatRiders}</dt>
                  <dd className="font-semibold ltr-nums">{fmt.number(d.riders.repeat_riders)}</dd>
                </div>
              </dl>
            </Card>
          </div>
        </div>

        <div className="space-y-6">
          <Card padded={false}>
            <CardHeader title={ds.queues} />
            <div className="p-2">
              <QueueLink href="/operator/drivers/verification" label={ds.queueDrivers} count={d.queues.drivers_under_review ?? 0} icon={<UserCheck className="size-4" />} />
              <QueueLink href="/operator/subscriptions/deposits" label={ds.queueDeposits} count={d.queues.deposit_claims_pending ?? 0} icon={<Receipt className="size-4" />} />
              <QueueLink href="/operator/trust/disputes" label={ds.queueDisputes} count={d.queues.disputes_open ?? 0} icon={<MessageSquareWarning className="size-4" />} />
              <QueueLink href="/operator/trust/disputes" label={ds.queueSafety} count={d.queues.safety_disputes_open ?? 0} icon={<AlertTriangle className="size-4" />} urgent />
              <QueueLink href="/operator/trust/violations" label={ds.queueViolations} count={d.queues.violations_pending_review ?? 0} icon={<ShieldAlert className="size-4" />} />
              <QueueLink href="/operator/trust/appeals" label={ds.queueAppeals} count={d.queues.appeals_pending ?? 0} icon={<Gavel className="size-4" />} />
            </div>
          </Card>
          <Card>
            <h3 className="mb-4 flex items-center gap-2 text-sm font-semibold">
              <Car className="size-4 text-navy-400" aria-hidden />
              {ds.supply}
            </h3>
            <dl className="space-y-3 text-sm">
              {[
                [ds.driversApproved, d.drivers.approved],
                [ds.driversOnline, d.drivers.online],
                [ds.driversSubscribed, d.drivers.with_active_subscription],
                [ds.driversReview, d.drivers.under_review],
              ].map(([label, value]) => (
                <div key={String(label)} className="flex justify-between gap-3">
                  <dt className="text-muted">{label}</dt>
                  <dd className="font-semibold ltr-nums">{fmt.number(Number(value))}</dd>
                </div>
              ))}
            </dl>
          </Card>
        </div>
      </div>
    </>
  );
}
