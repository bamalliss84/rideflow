"use client";

import { Banknote, CircleDot, Info, MapPin, Navigation, Timer } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";

import { GeoPreview, type GeoPoint } from "@/components/charts/GeoPreview";
import { enumLabel, EnumBadge, humanize, JsonView, Person } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Card, CardHeader, KeyValues } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

type Ride = Schemas["AdminRide"];
type Event = Schemas["RideEvent"];
type Bid = Schemas["Bid"];
interface Evidence {
  kind: string;
  lat: number;
  lng: number;
  accuracy_m: number;
  device_ts: string | null;
  server_ts: string;
}

export default function RideDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { t, dir } = useI18n();
  const { fmt } = useSession();
  const r = t.rides;
  const base = `admin/rides/${id}`;
  const ride = useApi<Ride>(base);
  const events = useApi<Event[]>(`${base}/events`);
  const bids = useApi<Bid[]>(`${base}/bids`);
  const evidence = useApi<Evidence[]>(`${base}/evidence`);

  if (ride.isPending) return <PageSkeleton />;
  if (ride.error) return <ErrorState error={ride.error} onRetry={() => void ride.refetch()} />;
  const d = ride.data;
  const points: GeoPoint[] = [
    { lat: d.pickup.lat, lng: d.pickup.lng, tone: "pickup", label: `${r.pickup}: ${d.pickup_landmark}` },
    { lat: d.dropoff.lat, lng: d.dropoff.lng, tone: "dropoff", label: `${r.dropoff}: ${d.dropoff_landmark}` },
    ...(evidence.data ?? []).map((e) => ({ lat: e.lat, lng: e.lng, tone: "evidence" as const, label: `${enumLabel(t, "evidenceKind", e.kind)} · ${fmt.dateTime(e.server_ts)}` })),
  ];

  return (
    <>
      <PageHeader
        title={`${d.pickup_landmark} ${dir === "rtl" ? "←" : "→"} ${d.dropoff_landmark}`}
        meta={<EnumBadge group="rideStatus" value={d.status} />}
        crumbs={[{ label: t.nav.rides, href: "/operator/rides" }, { label: fmt.dateTime(d.created_at) }]}
      />
      <p className="mb-5 flex items-start gap-2 rounded-md border border-navy-100 bg-navy-50 px-3 py-2 text-xs text-navy-800">
        <Info className="mt-0.5 size-4 shrink-0" aria-hidden />
        {r.readOnlyNote}
      </p>
      <div className="grid gap-6 xl:grid-cols-3">
        <div className="space-y-6 xl:col-span-2">
          <Card>
            <KeyValues
              columns={3}
              items={[
                { label: t.common.rider, value: <Person name={d.rider_name} phone={d.rider_phone} /> },
                { label: t.common.driver, value: d.driver_name ? <Person name={d.driver_name} phone={d.driver_phone} /> : "—" },
                { label: t.common.city, value: d.city_name },
                {
                  label: r.fare,
                  value:
                    d.agreed_fare_minor !== null ? (
                      <span className="font-semibold ltr-nums">{fmt.money(d.agreed_fare_minor, d.currency)}</span>
                    ) : (
                      <span className="ltr-nums">
                        {t.common.estimate}: {fmt.money(d.estimate_min_minor, d.currency)} – {fmt.money(d.estimate_max_minor, d.currency)}
                      </span>
                    ),
                },
                { label: r.distance, value: <span className="ltr-nums">{fmt.distance(d.estimated_distance_m)}</span> },
                { label: r.waves, value: fmt.number(d.wave_count) },
                { label: r.geofence, value: d.arrival_within_geofence === null ? "—" : d.arrival_within_geofence ? t.common.yes : t.common.no },
                { label: r.configVersion, value: <span className="ltr-nums">v{d.config_version}</span> },
                { label: t.common.created, value: fmt.dateTime(d.created_at) },
              ]}
            />
          </Card>

          <Card padded={false}>
            <CardHeader title={r.route} subtitle={r.mapLegend} icon={<Navigation className="size-4" />} />
            <div className="p-4">
              <GeoPreview points={points} label={r.route} />
              <div className="mt-3 flex flex-wrap gap-4 text-xs text-muted">
                <span className="flex items-center gap-1.5">
                  <span className="size-2.5 rounded-full bg-teal-700" />
                  {r.pickup}
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="size-2.5 rounded-full bg-navy-900" />
                  {r.dropoff}
                </span>
                <span className="flex items-center gap-1.5">
                  <span className="size-2.5 rounded-full bg-amber-500" />
                  {r.evidence}
                </span>
              </div>
            </div>
          </Card>

          <Card padded={false}>
            <CardHeader title={r.bids} />
            <DataTable<Bid>
              rows={bids.data}
              loading={bids.isPending}
              error={bids.error}
              rowKey={(b) => b.id}
              columns={[
                { key: "driver", header: t.common.driver, cell: (b) => b.driver?.display_name ?? "—" },
                { key: "amount", header: t.common.amount, cell: (b) => <span className="font-medium ltr-nums">{fmt.money(b.amount_minor, b.currency)}</span> },
                { key: "eta", header: r.eta, hideBelow: "sm", cell: (b) => <span className="ltr-nums">{fmt.duration(b.eta_seconds)}</span> },
                { key: "status", header: t.common.status, cell: (b) => <EnumBadge group="bidStatus" value={b.status} /> },
                { key: "created", header: t.common.created, hideBelow: "md", cell: (b) => fmt.time(b.created_at) },
              ]}
            />
          </Card>

          {evidence.data?.length ? (
            <Card padded={false}>
              <CardHeader title={r.evidence} icon={<MapPin className="size-4" />} />
              <DataTable<Evidence>
                rows={evidence.data}
                rowKey={(e) => `${e.server_ts}-${e.lat}`}
                columns={[
                  { key: "kind", header: t.common.type, cell: (e) => enumLabel(t, "evidenceKind", e.kind) },
                  { key: "time", header: t.common.date, cell: (e) => fmt.dateTime(e.server_ts) },
                  { key: "accuracy", header: r.accuracy, cell: (e) => <span className="ltr-nums">± {fmt.distance(e.accuracy_m)}</span> },
                  { key: "pos", header: r.route, hideBelow: "md", cell: (e) => <span className="text-xs text-muted ltr-nums">{e.lat.toFixed(5)}, {e.lng.toFixed(5)}</span> },
                ]}
              />
            </Card>
          ) : null}
        </div>

        <div className="space-y-6">
          <Card padded={false}>
            <CardHeader title={r.timeline} icon={<Timer className="size-4" />} />
            {events.error ? (
              <ErrorState error={events.error} compact />
            ) : (
              <ol className="relative space-y-4 px-5 py-4">
                {(events.data ?? []).map((e) => (
                  <li key={e.seq} className="relative flex gap-3">
                    <CircleDot className={`mt-0.5 size-4 shrink-0 ${e.to_status ? "text-teal-700" : "text-navy-300"}`} aria-hidden />
                    <div className="min-w-0">
                      <p className="text-sm font-medium">{(t.enums.rideEvent as Record<string, string>)[e.event_type] ?? humanize(e.event_type)}</p>
                      <p className="text-xs text-muted">
                        {fmt.dateTime(e.created_at)} · {enumLabel(t, "actorRole", e.actor_role)}
                      </p>
                      {e.to_status ? (
                        <p className="mt-1">
                          <EnumBadge group="rideStatus" value={e.to_status} />
                        </p>
                      ) : null}
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </Card>

          {d.cancelled_at ? (
            <Card>
              <h3 className="mb-3 text-sm font-semibold">{r.cancellation}</h3>
              <KeyValues
                columns={1}
                items={[
                  { label: r.cancelledBy, value: enumLabel(t, "actorRole", d.cancelled_by_role) },
                  { label: t.common.reason, value: d.cancel_reason || "—" },
                  { label: r.late, value: d.cancellation_late ? <Badge tone="warning">{t.common.yes}</Badge> : t.common.no },
                  { label: t.common.date, value: fmt.dateTime(d.cancelled_at) },
                ]}
              />
            </Card>
          ) : null}
          {d.no_show_evidence ? (
            <Card>
              <h3 className="mb-3 text-sm font-semibold">{r.noShowEvidence}</h3>
              <JsonView value={d.no_show_evidence} />
            </Card>
          ) : null}
          {d.completed_at ? (
            <Card>
              <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold">
                <Banknote className="size-4 text-navy-400" aria-hidden />
                {r.cash}
              </h3>
              <KeyValues
                columns={1}
                items={[
                  { label: r.cashDriver, value: d.cash_driver_confirmed_at ? fmt.dateTime(d.cash_driver_confirmed_at) : "—" },
                  { label: r.cashRider, value: d.cash_rider_confirmed_at ? fmt.dateTime(d.cash_rider_confirmed_at) : "—" },
                ]}
              />
            </Card>
          ) : null}
          {d.status === "disputed" ? (
            <Link href={`/operator/trust/disputes?ride=${d.id}`} className="block text-sm font-medium text-teal-700 hover:underline">
              {t.nav.disputes} →
            </Link>
          ) : null}
        </div>
      </div>
    </>
  );
}
