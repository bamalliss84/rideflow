"use client";

import { MapPinned, Pencil, Plus } from "lucide-react";
import { useMemo, useState, type FormEvent } from "react";

import { GeoPreview, ringsOf } from "@/components/charts/GeoPreview";
import { TIME_ZONES } from "@/components/domain/TenantForm";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { Dialog } from "@/components/ui/Dialog";
import { Field, Input, Select, Switch, Textarea } from "@/components/ui/Form";
import { PageHeader } from "@/components/ui/Page";
import { EmptyState, InlineError } from "@/components/ui/States";
import { api, ApiError, newIdempotencyKey, type Page, type Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

type City = Schemas["City"];
type Area = Schemas["ServiceArea"];

export default function GeoPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const g = t.geo;
  const editable = can("geo.manage");
  const cities = useApi<Page<City>>("admin/cities", { page_size: 100 });
  const [picked, setSelected] = useState<string>("");
  const selected = picked || cities.data?.results[0]?.id || "";
  const areas = useApi<Page<Area>>(selected ? "admin/service-areas" : null, { city: selected, page_size: 100 });
  const city = cities.data?.results.find((c) => c.id === selected);
  const [cityDialog, setCityDialog] = useState<City | "new" | null>(null);
  const [areaDialog, setAreaDialog] = useState<Area | "new" | null>(null);

  return (
    <>
      <PageHeader
        title={g.title}
        subtitle={g.subtitle}
        actions={
          editable ? (
            <Button icon={<Plus className="size-4" aria-hidden />} onClick={() => setCityDialog("new")}>
              {g.newCity}
            </Button>
          ) : null
        }
      />
      <div className="grid gap-6 xl:grid-cols-5">
        <Card padded={false} className="xl:col-span-2">
          <CardHeader title={g.cities} />
          <DataTable<City>
            rows={cities.data?.results}
            loading={cities.isPending}
            error={cities.error}
            rowKey={(c) => c.id}
            columns={[
              {
                key: "name",
                header: t.common.name,
                cell: (c) => (
                  <button type="button" onClick={() => setSelected(c.id)} className={`text-start font-medium hover:underline ${c.id === selected ? "text-teal-800" : ""}`} aria-pressed={c.id === selected}>
                    {c.name}
                  </button>
                ),
              },
              { key: "slug", header: g.slug, hideBelow: "sm", cell: (c) => <span className="text-muted ltr-nums">{c.slug}</span> },
              { key: "active", header: t.common.status, cell: (c) => <Badge tone={c.is_active ? "success" : "neutral"}>{c.is_active ? t.common.active : t.common.inactive}</Badge> },
              {
                key: "edit",
                header: <span className="sr-only">{t.common.actions}</span>,
                align: "end",
                cell: (c) =>
                  editable ? (
                    <Button size="sm" variant="ghost" icon={<Pencil className="size-4" aria-hidden />} onClick={() => setCityDialog(c)}>
                      {t.common.edit}
                    </Button>
                  ) : null,
              },
            ]}
          />
        </Card>
        <Card padded={false} className="xl:col-span-3">
          <CardHeader
            title={city ? `${g.areas} · ${city.name}` : g.areas}
            icon={<MapPinned className="size-4" />}
            actions={
              editable && city ? (
                <Button size="sm" variant="secondary" icon={<Plus className="size-4" aria-hidden />} onClick={() => setAreaDialog("new")}>
                  {g.newArea}
                </Button>
              ) : null
            }
          />
          {city ? (
            <div className="space-y-4 p-4">
              <GeoPreview
                height={300}
                label={g.areas}
                polygons={[...ringsOf(city.boundary), ...(areas.data?.results ?? []).flatMap((a) => ringsOf(a.area))]}
                points={[{ lat: city.center.lat, lng: city.center.lng, tone: "center", label: `${g.center}: ${city.name}` }]}
              />
              <DataTable<Area>
                rows={areas.data?.results}
                loading={areas.isPending}
                error={areas.error}
                rowKey={(a) => a.id}
                empty={<EmptyState title={g.noAreas} hint="" />}
                columns={[
                  { key: "name", header: t.common.name, cell: (a) => <span className="font-medium">{a.name}</span> },
                  { key: "active", header: t.common.status, cell: (a) => <Badge tone={a.is_active ? "success" : "neutral"}>{a.is_active ? t.common.active : t.common.inactive}</Badge> },
                  {
                    key: "edit",
                    header: <span className="sr-only">{t.common.actions}</span>,
                    align: "end",
                    cell: (a) =>
                      editable ? (
                        <Button size="sm" variant="ghost" icon={<Pencil className="size-4" aria-hidden />} onClick={() => setAreaDialog(a)}>
                          {t.common.edit}
                        </Button>
                      ) : null,
                  },
                ]}
              />
            </div>
          ) : (
            <EmptyState />
          )}
        </Card>
      </div>
      {cityDialog ? <CityDialog city={cityDialog === "new" ? null : cityDialog} onClose={() => setCityDialog(null)} onSaved={() => void cities.refetch()} /> : null}
      {areaDialog && city ? (
        <AreaDialog area={areaDialog === "new" ? null : areaDialog} city={city} onClose={() => setAreaDialog(null)} onSaved={() => void areas.refetch()} />
      ) : null}
    </>
  );
}

function CityDialog({ city, onClose, onSaved }: { city: City | null; onClose: () => void; onSaved: () => void }) {
  const { t } = useI18n();
  const g = t.geo;
  const [form, setForm] = useState({
    name: city?.name ?? "",
    slug: city?.slug ?? "",
    lat: String(city?.center.lat ?? ""),
    lng: String(city?.center.lng ?? ""),
    time_zone: city?.time_zone ?? "",
    is_active: city?.is_active ?? true,
  });
  const [key] = useState(newIdempotencyKey);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const fe = error instanceof ApiError ? error.fieldErrors() : {};
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const body = { name: form.name.trim(), slug: form.slug.trim(), center: { lat: Number(form.lat), lng: Number(form.lng) }, time_zone: form.time_zone, is_active: form.is_active };
      if (city) await api(`admin/cities/${city.id}`, { method: "PATCH", body });
      else await api("admin/cities", { method: "POST", body, idempotencyKey: key });
      onSaved();
      onClose();
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog open onClose={onClose} title={city ? g.editCity : g.newCity}>
      <form onSubmit={submit} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label={t.common.name} required error={fe.name}>
            {(f) => <Input {...f} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />}
          </Field>
          <Field label={g.slug} required error={fe.slug}>
            {(f) => <Input {...f} value={form.slug} onChange={(e) => setForm({ ...form, slug: e.target.value })} dir="ltr" pattern="[a-z0-9-]+" required />}
          </Field>
          <Field label={g.latitude} required error={fe["center.lat"] ?? fe.center}>
            {(f) => <Input {...f} type="number" step="any" min={-90} max={90} value={form.lat} onChange={(e) => setForm({ ...form, lat: e.target.value })} dir="ltr" required />}
          </Field>
          <Field label={g.longitude} required error={fe["center.lng"]}>
            {(f) => <Input {...f} type="number" step="any" min={-180} max={180} value={form.lng} onChange={(e) => setForm({ ...form, lng: e.target.value })} dir="ltr" required />}
          </Field>
          <Field label={g.timeZone} hint={g.timeZoneHint}>
            {(f) => (
              <Select {...f} value={form.time_zone} onChange={(e) => setForm({ ...form, time_zone: e.target.value })}>
                <option value="">—</option>
                {TIME_ZONES.map((z) => (
                  <option key={z} value={z}>
                    {z}
                  </option>
                ))}
              </Select>
            )}
          </Field>
          <div className="flex items-center gap-3 pt-6">
            <Switch checked={form.is_active} onChange={(v) => setForm({ ...form, is_active: v })} label={t.common.active} />
            <span className="text-sm">{t.common.active}</span>
          </div>
        </div>
        <InlineError error={Object.keys(fe).length ? null : error} />
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={busy}>
            {t.common.cancel}
          </Button>
          <Button type="submit" loading={busy}>
            {t.common.save}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

function rectangle(s: number, w: number, n: number, e: number) {
  return { type: "Polygon", coordinates: [[[w, s], [e, s], [e, n], [w, n], [w, s]]] };
}

function AreaDialog({ area, city, onClose, onSaved }: { area: Area | null; city: City; onClose: () => void; onSaved: () => void }) {
  const { t } = useI18n();
  const g = t.geo;
  const [name, setName] = useState(area?.name ?? "");
  const [active, setActive] = useState(area?.is_active ?? true);
  const [json, setJson] = useState(area ? JSON.stringify(area.area) : "");
  const d = 0.05;
  const [rect, setRect] = useState({ s: city.center.lat - d, w: city.center.lng - d, n: city.center.lat + d, e: city.center.lng + d });
  const [key] = useState(newIdempotencyKey);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const parsed = useMemo(() => {
    try {
      const v = JSON.parse(json) as { type?: string };
      return v && v.type === "Polygon" ? v : null;
    } catch {
      return null;
    }
  }, [json]);
  const fe = error instanceof ApiError ? error.fieldErrors() : {};
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!parsed) return;
    setBusy(true);
    setError(null);
    try {
      const body = { name: name.trim(), city_id: city.id, area: parsed, is_active: active };
      if (area) await api(`admin/service-areas/${area.id}`, { method: "PATCH", body });
      else await api("admin/service-areas", { method: "POST", body, idempotencyKey: key });
      onSaved();
      onClose();
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog open onClose={onClose} title={area ? g.editArea : g.newArea} size="lg">
      <form onSubmit={submit} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-[1fr_auto]">
          <Field label={t.common.name} required error={fe.name}>
            {(f) => <Input {...f} value={name} onChange={(e) => setName(e.target.value)} required />}
          </Field>
          <div className="flex items-center gap-3 sm:pt-6">
            <Switch checked={active} onChange={setActive} label={t.common.active} />
            <span className="text-sm">{t.common.active}</span>
          </div>
        </div>
        <fieldset className="rounded-md border border-line p-3">
          <legend className="px-1 text-xs font-medium text-muted">{g.rectangle}</legend>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {(
              [
                ["s", g.south],
                ["n", g.north],
                ["w", g.west],
                ["e", g.east],
              ] as const
            ).map(([k, label]) => (
              <Field key={k} label={label}>
                {(f) => <Input {...f} type="number" step="any" dir="ltr" value={rect[k]} onChange={(e) => setRect({ ...rect, [k]: Number(e.target.value) })} />}
              </Field>
            ))}
          </div>
          <Button size="sm" variant="secondary" className="mt-3" onClick={() => setJson(JSON.stringify(rectangle(rect.s, rect.w, rect.n, rect.e)))}>
            {g.useRectangle}
          </Button>
        </fieldset>
        <Field label={g.polygon} hint={g.polygonHint} error={json && !parsed ? g.invalidGeoJson : fe.area}>
          {(f) => <Textarea {...f} value={json} onChange={(e) => setJson(e.target.value)} dir="ltr" className="font-mono text-xs" rows={4} />}
        </Field>
        {parsed ? <GeoPreview height={200} label={g.polygon} polygons={ringsOf(parsed)} points={[{ lat: city.center.lat, lng: city.center.lng, tone: "center" }]} /> : null}
        <InlineError error={Object.keys(fe).length ? null : error} />
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={busy}>
            {t.common.cancel}
          </Button>
          <Button type="submit" loading={busy} disabled={!parsed || !name.trim()}>
            {t.common.save}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}
