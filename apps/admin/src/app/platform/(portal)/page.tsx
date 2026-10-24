"use client";

import { AppWindow, Building2, CirclePause, CirclePlay, ShieldCheck } from "lucide-react";
import Link from "next/link";

import { BarChart } from "@/components/charts/BarChart";
import { EnumBadge } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card, CardHeader, StatCard } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

type Overview = Schemas["PlatformOverview"];
type Row = Schemas["PlatformTenantSummary"];

export default function PlatformOverviewPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const q = useApi<Overview>("platform/overview");
  if (q.isPending) return <PageSkeleton />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />;
  const o = q.data;
  const p = t.platform;
  const months = o.tenants_created_by_month.map((m) => ({ label: String(m.month).slice(0, 7), values: { count: Number(m.count) } }));

  return (
    <>
      <PageHeader title={p.overviewTitle} subtitle={p.overviewSubtitle} />
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <StatCard label={p.tenantsTotal} value={fmt.number(o.tenants.total)} icon={<Building2 className="size-4" />} />
        <StatCard label={p.tenantsActive} value={fmt.number(o.tenants.active ?? 0)} tone="accent" icon={<CirclePlay className="size-4" />} />
        <StatCard label={p.tenantsSuspended} value={fmt.number(o.tenants.suspended ?? 0)} tone="danger" icon={<CirclePause className="size-4" />} />
        <StatCard label={p.applications} value={fmt.number(o.applications)} icon={<AppWindow className="size-4" />} />
        <StatCard label={p.platformAdmins} value={fmt.number(o.platform_admins)} icon={<ShieldCheck className="size-4" />} />
      </div>
      <div className="mt-6 grid gap-6 xl:grid-cols-3">
        <Card padded={false} className="xl:col-span-2">
          <CardHeader title={p.perTenant} subtitle={`${fmt.dateTime(o.generated_at)}`} />
          <DataTable<Row>
            rows={o.per_tenant}
            rowKey={(r) => r.id}
            rowHref={(r) => `/platform/tenants/${r.id}`}
            columns={[
              {
                key: "name",
                header: p.name,
                cell: (r) => (
                  <Link href={`/platform/tenants/${r.id}`} className="font-medium text-ink hover:underline">
                    {r.name}
                  </Link>
                ),
              },
              { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="tenantStatus" value={r.status} /> },
              { key: "drivers", header: p.drivers, align: "end", cell: (r) => <span className="ltr-nums">{fmt.number(r.drivers)} <span className="text-xs text-muted">({fmt.number(r.drivers_approved)} {p.approved})</span></span> },
              { key: "riders", header: p.riders, align: "end", hideBelow: "md", cell: (r) => fmt.number(r.riders) },
              { key: "rides", header: p.rides30, align: "end", cell: (r) => fmt.number(r.rides_30d) },
              { key: "completed", header: p.completed30, align: "end", hideBelow: "lg", cell: (r) => fmt.number(r.rides_completed_30d) },
              { key: "subs", header: p.subscriptions, align: "end", hideBelow: "lg", cell: (r) => fmt.number(r.active_driver_subscriptions) },
            ]}
          />
        </Card>
        <Card padded={false}>
          <CardHeader title={p.growth} />
          <div className="p-5">
            <BarChart data={months} series={[{ key: "count", label: p.tenantsTotal, tone: "neutral" }]} format={(v) => fmt.number(v)} />
          </div>
        </Card>
      </div>
      <p className="mt-6 text-xs text-muted">{p.noOperatorData}</p>
    </>
  );
}
