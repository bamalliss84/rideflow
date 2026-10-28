"use client";

import { RefreshCw } from "lucide-react";
import Link from "next/link";
import { useState } from "react";

import { MapView } from "@/components/map/MapView";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, Toolbar } from "@/components/ui/Page";
import { EmptyState } from "@/components/ui/States";
import type { Page, Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

type City = Schemas["City"];
type Item = Schemas["NearbyAdminItem"];
const RADII = ["2000", "5000", "10000", "20000"] as const;

export default function LiveDriversPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const cities = useApi<Page<City>>("admin/cities", { is_active: true, page_size: 100 });
  const [picked, setCityId] = useState("");
  const [radius, setRadius] = useState<(typeof RADII)[number]>("5000");
  const cityId = picked || cities.data?.results[0]?.id || "";
  const city = cities.data?.results.find((c) => c.id === cityId);
  const q = useApi<Item[]>(city ? "admin/drivers-nearby" : null, city ? { lat: city.center.lat, lng: city.center.lng, radius_m: radius } : undefined, {
    refetchInterval: 20_000,
  });

  return (
    <>
      <PageHeader
        title={t.live.title}
        subtitle={t.live.subtitle}
        actions={
          <Button variant="secondary" icon={<RefreshCw className="size-4" aria-hidden />} onClick={() => void q.refetch()} loading={q.isFetching}>
            {t.common.refresh}
          </Button>
        }
      />
      <Card padded={false}>
        <Toolbar>
          <FilterSelect allowAll={false} label={t.common.city} value={cityId} onChange={(v) => setCityId(v)} options={(cities.data?.results ?? []).map((c) => ({ value: c.id, label: c.name }))} />
          <FilterSelect
            label={t.live.radius}
            allowAll={false}
            value={radius}
            onChange={(v) => setRadius((v || "5000") as (typeof RADII)[number])}
            options={RADII.map((r) => ({ value: r, label: fmt.distance(Number(r)) }))}
          />
        </Toolbar>
        {city ? (
          <div className="grid gap-0 lg:grid-cols-5">
            <div className="border-b border-line p-4 lg:col-span-2 lg:border-e lg:border-b-0">
              <div className="mb-3 flex items-baseline justify-between">
                <span className="text-sm text-muted">{t.live.online}</span>
                <span className="ltr-nums text-2xl font-bold" data-testid="live-count">
                  {q.data?.length ?? "—"}
                </span>
              </div>
              <MapView
                height={380}
                label={t.live.title}
                notConfiguredHint={t.live.mapNotConfigured}
                points={[
                  { lat: city.center.lat, lng: city.center.lng, tone: "center", label: city.name },
                  ...(q.data ?? []).map((d) => ({ lat: d.location.lat, lng: d.location.lng, tone: "driver" as const, label: d.full_name })),
                ]}
              />
            </div>
            <div className="lg:col-span-3">
              <DataTable<Item>
                rows={q.data}
                loading={q.isPending}
                error={q.error}
                rowKey={(d) => d.driver_id}
                empty={<EmptyState title={t.live.none} hint="" />}
                columns={[
                  {
                    key: "name",
                    header: t.common.driver,
                    cell: (d) => (
                      <Link href={`/operator/drivers/${d.driver_id}`} className="font-medium hover:underline">
                        {d.full_name || "—"}
                      </Link>
                    ),
                  },
                  { key: "distance", header: t.rides.distance, cell: (d) => <span className="ltr-nums">{fmt.distance(d.distance_m)}</span> },
                  { key: "accuracy", header: t.rides.accuracy, hideBelow: "sm", cell: (d) => <span className="ltr-nums">± {fmt.distance(d.accuracy_m)}</span> },
                  { key: "seen", header: t.live.lastSeen, cell: (d) => fmt.relative(d.server_ts) },
                ]}
              />
            </div>
          </div>
        ) : (
          <EmptyState title={t.geo.cities} hint={t.geo.subtitle} />
        )}
      </Card>
    </>
  );
}
