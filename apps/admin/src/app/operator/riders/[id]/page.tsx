"use client";

import Link from "next/link";
import { useParams } from "next/navigation";

import { EnumBadge, Phone } from "@/components/domain/Display";
import { TrustSummary } from "@/components/domain/TrustSummary";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card, CardHeader, KeyValues } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

type Detail = Schemas["RiderDetail"];
type Ride = Schemas["AdminRide"];

export default function RiderDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { t } = useI18n();
  const { fmt, can } = useSession();
  const q = useApi<Detail>(`admin/riders/${id}`);
  if (q.isPending) return <PageSkeleton />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />;
  const r = q.data;
  const rides = r.recent_rides as unknown as Ride[];
  return (
    <>
      <PageHeader
        title={r.full_name || r.phone}
        meta={<EnumBadge group="membershipStatus" value={r.status} />}
        crumbs={[{ label: t.nav.riders, href: "/operator/riders" }, { label: r.full_name || r.phone }]}
      />
      <div className="grid gap-6 xl:grid-cols-3">
        <div className="space-y-6 xl:col-span-2">
          <Card>
            <KeyValues
              columns={3}
              items={[
                { label: t.common.phone, value: <Phone value={r.phone} /> },
                { label: t.riders.joined, value: fmt.dateTime(r.created_at) },
                { label: t.riders.lastRide, value: r.last_ride_at ? fmt.dateTime(r.last_ride_at) : t.common.never },
                { label: t.riders.ridesTotal, value: fmt.number(r.rides_total) },
                { label: t.riders.ridesCompleted, value: fmt.number(r.rides_completed) },
                {
                  label: t.riders.openIncidents,
                  value: r.open_violations ? (
                    can("violations.review") ? (
                      <Link href={`/operator/trust/violations?subject=${r.user_id}`} className="font-medium text-coral-700 hover:underline">
                        {fmt.number(r.open_violations)}
                      </Link>
                    ) : (
                      fmt.number(r.open_violations)
                    )
                  ) : (
                    "0"
                  ),
                },
              ]}
            />
          </Card>
          <Card padded={false}>
            <CardHeader title={t.drivers.recentRides} actions={<Link className="text-sm font-medium text-teal-700 hover:underline" href={`/operator/rides?rider=${r.user_id}`}>{t.common.viewAll}</Link>} />
            <DataTable<Ride>
              rows={rides}
              rowKey={(x) => x.id}
              rowHref={(x) => `/operator/rides/${x.id}`}
              columns={[
                { key: "created", header: t.common.date, cell: (x) => fmt.dateTime(x.created_at) },
                { key: "driver", header: t.common.driver, cell: (x) => x.driver_name || "—" },
                { key: "status", header: t.common.status, cell: (x) => <EnumBadge group="rideStatus" value={x.status} /> },
                { key: "fare", header: t.rides.fare, align: "end", cell: (x) => <span className="ltr-nums">{fmt.money(x.agreed_fare_minor, x.currency)}</span> },
              ]}
            />
          </Card>
        </div>
        {can("reports.view") ? <TrustSummary userId={r.user_id} role="rider" /> : null}
      </div>
    </>
  );
}
