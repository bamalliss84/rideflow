"use client";

import { CircleAlert, History, RotateCcw, Save } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { EnumBadge } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/Dialog";
import { Input, Switch } from "@/components/ui/Form";
import { PageHeader, Tabs } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import { ApiError, type Page, type Schemas } from "@/lib/api/client";
import { useAction, useApi } from "@/lib/api/hooks";
import type { Dictionary } from "@/lib/i18n";

type Config = Schemas["EffectiveConfig"];
type Param = Schemas["PolicyParam"];
type Version = Schemas["ConfigVersion"];

/** Business sections over the backend's technical parameter groups (key prefix). Order = display order. */
const SECTIONS = [
  { id: "pricing", groups: ["fare"] },
  { id: "dispatch", groups: ["dispatch", "bids", "match", "rides", "presence"] },
  { id: "attendance", groups: ["cancellation", "noshow"] },
  { id: "trust", groups: ["ratings", "trust"] },
  { id: "cases", groups: ["enforcement", "appeals", "disputes"] },
  { id: "drivers", groups: ["drivers", "subscriptions"] },
  { id: "rewards", groups: ["rewards", "compensation"] },
  { id: "operator", groups: ["tenant"] },
] as const;
type SectionId = (typeof SECTIONS)[number]["id"];

const DOC_TYPES = ["national_id", "driving_license", "vehicle_registration", "vehicle_photo", "driver_photo", "insurance"] as const;
const TIERS = ["silver", "gold", "diamond"] as const;

function same(a: unknown, b: unknown) {
  return JSON.stringify(a) === JSON.stringify(b);
}

type UnitKey = keyof Dictionary["policy"]["units"];
function unitOf(key: string): UnitKey | null {
  if (key.endsWith("_minor")) return "minor";
  if (key.endsWith("_seconds")) return "seconds";
  if (key.endsWith("_m")) return "meters";
  if (key.endsWith("_pct")) return "percent";
  if (key.endsWith("_days") || key.includes("_days_") || key.includes(".days_")) return "days";
  if (key.endsWith("_hours")) return "hours";
  if (key === "ratings.prior_mean") return "stars";
  return null;
}

/** Client-side mirror of the backend validation (apps/tenancy/policy.validate_overrides); the server still decides. */
function validate(param: Param, value: unknown, p: Dictionary["policy"], tpl: (s: string, v: Record<string, string | number>) => string): string | null {
  const num = param.type === "int" || param.type === "float";
  if (num) {
    if (value === "" || typeof value !== "number" || Number.isNaN(value)) return p.errors.number;
    if (param.type === "int" && !Number.isInteger(value)) return p.errors.integer;
    if ((param.min !== null && param.min !== undefined && value < param.min) || (param.max !== null && param.max !== undefined && value > param.max)) {
      return tpl(p.errors.range, { min: param.min ?? "—", max: param.max ?? "—" });
    }
  }
  if (param.key.endsWith("_weights") && value && typeof value === "object") {
    const values = Object.values(value as Record<string, unknown>);
    if (values.some((v) => typeof v !== "number" || !Number.isInteger(v) || v < 0)) return p.errors.weights;
    if (values.reduce<number>((a, v) => a + Number(v), 0) <= 0) return p.errors.weightsZero;
  }
  if (param.key === "trust.tier_thresholds" && value && typeof value === "object") {
    const v = value as Record<string, number>;
    if (!(0 <= v.silver! && v.silver! <= v.gold! && v.gold! <= v.diamond! && v.diamond! <= 100)) return p.errors.tiers;
  }
  return null;
}

export default function PolicyPage() {
  const { t, tpl } = useI18n();
  const { fmt, can } = useSession();
  const p = t.policy;
  const editable = can("config.manage");
  const q = useApi<Config>("admin/config");
  const versions = useApi<Page<Version>>("admin/config/versions", { page_size: 20 });
  const [draft, setDraft] = useState<Record<string, unknown>>({});
  const [section, setSection] = useState<SectionId>("pricing");
  const [advanced, setAdvanced] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const save = useAction<{ params: Record<string, unknown>; note: string }, Version>("POST", "admin/config", {
    invalidate: ["admin/config"],
    inlineErrors: true,
  });
  const serverErrors = save.error instanceof ApiError ? save.error.fieldErrors() : {};

  const byGroup = useMemo(() => {
    const out: Record<string, Param[]> = {};
    for (const param of q.data?.parameters ?? []) (out[param.key.split(".")[0] ?? "other"] ??= []).push(param);
    return out;
  }, [q.data]);
  const sections = useMemo(() => {
    const known = new Set<string>(SECTIONS.flatMap((s) => s.groups));
    const list = SECTIONS.map((s) => ({ id: s.id as string, params: s.groups.flatMap((g) => byGroup[g] ?? []) }));
    const other = Object.entries(byGroup).filter(([g]) => !known.has(g)).flatMap(([, ps]) => ps);
    if (other.length) list.push({ id: "other", params: other });
    return list.filter((s) => s.params.length);
  }, [byGroup]);

  const cfg = q.data;
  const changed = cfg ? Object.keys(draft).filter((k) => !same(draft[k], cfg.effective[k])) : [];
  // Warn before leaving the page with unsaved edits.
  useEffect(() => {
    if (!changed.length) return;
    const onLeave = (e: BeforeUnloadEvent) => e.preventDefault();
    window.addEventListener("beforeunload", onLeave);
    return () => window.removeEventListener("beforeunload", onLeave);
  }, [changed.length]);

  if (q.isPending) return <PageSkeleton />;
  if (q.error || !cfg) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />;

  const params = cfg.parameters;
  const valueOf = (key: string) => (key in draft ? draft[key] : cfg.effective[key]);
  const set = (key: string, value: unknown) => setDraft((d) => ({ ...d, [key]: value }));
  const label = (key: string) => (p.params as Record<string, string>)[key] ?? key;
  const errors = Object.fromEntries(params.map((param) => [param.key, validate(param, valueOf(param.key), p, tpl)]));
  const invalid = changed.some((k) => errors[k]);
  const active = sections.find((s) => s.id === section) ?? sections[0];
  const sectionLabel = (id: string) => (p.sections as Record<string, string>)[id] ?? id;

  const display = (param: Param, value: unknown) => {
    if (typeof value === "boolean") return value ? p.enabled : p.disabled;
    if (Array.isArray(value)) return value.map((v) => (t.enums.docType as Record<string, string>)[String(v)] ?? String(v)).join("، ") || "—";
    if (value && typeof value === "object") {
      return Object.entries(value as Record<string, unknown>)
        .map(([k, v]) => `${(p.weightKeys as Record<string, string>)[k] ?? (t.enums.tier as Record<string, string>)[k] ?? k}: ${String(v)}`)
        .join("، ");
    }
    const unit = unitOf(param.key);
    if (unit === "minor" && typeof value === "number") return fmt.money(value);
    return `${fmt.number(Number(value))}${unit && unit !== "minor" ? ` ${p.units[unit]}` : ""}`;
  };

  const renderInput = (param: Param) => {
    const value = valueOf(param.key);
    const name = label(param.key);
    const err = errors[param.key];
    if (!editable) return <span className="text-sm font-semibold text-ink">{display(param, value)}</span>;
    if (param.type === "bool") {
      return (
        <span className="inline-flex items-center gap-2 text-sm">
          <Switch checked={Boolean(value)} onChange={(v) => set(param.key, v)} label={name} />
          <span className={value ? "font-medium text-teal-700" : "text-muted"}>{value ? p.enabled : p.disabled}</span>
        </span>
      );
    }
    if (param.type === "int" || param.type === "float") {
      const unit = unitOf(param.key);
      return (
        <div className="flex flex-col items-stretch gap-1 sm:items-end">
          <div className="flex items-center gap-2">
            <Input
              type="number"
              inputMode={param.type === "int" ? "numeric" : "decimal"}
              aria-label={name}
              aria-invalid={err ? true : undefined}
              dir="ltr"
              className="w-36 text-end"
              min={param.min ?? undefined}
              max={param.max ?? undefined}
              step={param.type === "float" ? "0.1" : "1"}
              value={value === "" ? "" : String(value ?? "")}
              onChange={(e) => set(param.key, e.target.value === "" ? "" : Number(e.target.value))}
            />
            <span className="w-20 text-xs text-muted">{unit ? p.units[unit] : ""}</span>
          </div>
          {unit === "minor" && typeof value === "number" && !err ? <span className="text-xs text-muted">
              = <bdi>{fmt.money(value)}</bdi>
            </span> : null}
        </div>
      );
    }
    if (param.key === "drivers.required_documents" && Array.isArray(value)) {
      const list = value as string[];
      return (
        <fieldset className="grid gap-1.5 sm:grid-cols-2">
          <legend className="sr-only">{name}</legend>
          {DOC_TYPES.map((doc) => (
            <label key={doc} className="flex items-center gap-2 text-sm">
              <input
                type="checkbox"
                className="size-4 accent-teal-700"
                checked={list.includes(doc)}
                onChange={(e) => set(param.key, e.target.checked ? [...list, doc] : list.filter((d) => d !== doc))}
              />
              {t.enums.docType[doc]}
            </label>
          ))}
        </fieldset>
      );
    }
    if (value && typeof value === "object" && !Array.isArray(value)) {
      const obj = value as Record<string, number>;
      const keys = param.key === "trust.tier_thresholds" ? [...TIERS] : Object.keys(obj);
      const total = param.key.endsWith("_weights") ? Object.values(obj).reduce((a, v) => a + (Number(v) || 0), 0) : null;
      return (
        <div className="space-y-2">
          <div className="grid gap-2 sm:grid-cols-3">
            {keys.map((k) => (
              <label key={k} className="flex flex-col gap-1 text-xs text-muted">
                {(p.weightKeys as Record<string, string>)[k] ?? (t.enums.tier as Record<string, string>)[k] ?? k}
                <Input
                  type="number"
                  dir="ltr"
                  min={0}
                  max={param.key === "trust.tier_thresholds" ? 100 : undefined}
                  step="1"
                  className="h-9 text-end"
                  value={obj[k] === undefined ? "" : String(obj[k])}
                  onChange={(e) => set(param.key, { ...obj, [k]: e.target.value === "" ? "" : Number(e.target.value) })}
                />
              </label>
            ))}
          </div>
          {total !== null ? <p className="text-xs text-muted">{tpl(p.weightsTotal, { n: total })}</p> : null}
        </div>
      );
    }
    return <span className="text-sm font-semibold">{display(param, value)}</span>;
  };

  const wide = (param: Param) => param.type === "dict" || param.type === "list";

  return (
    <>
      <PageHeader
        title={p.title}
        subtitle={p.subtitle}
        meta={<Badge tone="info">{cfg.version ? tpl(p.version, { v: cfg.version }) : p.noVersion}</Badge>}
        actions={
          <label className="flex items-center gap-2 text-xs text-muted">
            <Switch checked={advanced} onChange={setAdvanced} label={p.advanced} />
            {p.advanced}
          </label>
        }
      />

      <div className="mb-5 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-xl border border-line bg-white px-4 py-3 text-xs text-muted shadow-card">
        <span className="font-medium text-ink">{p.legendTitle}</span>
        <span className="inline-flex items-center gap-1.5">
          <EnumBadge group="policyStatus" value="APPROVED" /> {p.legend.APPROVED}
        </span>
        <span className="inline-flex items-center gap-1.5">
          <EnumBadge group="policyStatus" value="PROPOSED" /> {p.legend.PROPOSED}
        </span>
        <span className="inline-flex items-center gap-1.5">
          <EnumBadge group="policyStatus" value="PROVISIONAL" /> {p.legend.PROVISIONAL}
        </span>
        {!editable ? <span className="basis-full text-muted">{p.readOnly}</span> : null}
      </div>

      <div className="grid gap-6 lg:grid-cols-[14rem_minmax(0,1fr)] xl:grid-cols-[14rem_minmax(0,1fr)_18rem]">
        {/* Section navigator: a vertical list on large screens, a scrollable tab strip below. */}
        <nav aria-label={p.sectionsLabel} className="hidden self-start lg:sticky lg:top-20 lg:block">
          <ul className="space-y-0.5 rounded-xl border border-line bg-white p-1.5 shadow-card">
            {sections.map((s) => {
              const dirty = s.params.some((x) => changed.includes(x.key));
              const pending = s.params.filter((x) => x.status !== "APPROVED").length;
              return (
                <li key={s.id}>
                  <button
                    type="button"
                    onClick={() => setSection(s.id as SectionId)}
                    aria-current={active?.id === s.id ? "true" : undefined}
                    className={`flex w-full items-center gap-2 rounded-lg px-3 py-2 text-start text-sm transition-colors ${active?.id === s.id ? "bg-teal-50 font-semibold text-teal-800" : "text-ink hover:bg-navy-50"}`}
                  >
                    <span className="flex-1 truncate">{sectionLabel(s.id)}</span>
                    {dirty ? <span className="size-2 rounded-full bg-amber-500" aria-label={p.unsaved} /> : null}
                    <span className="text-[0.7rem] text-subtle ltr-nums" title={tpl(p.pendingCount, { n: pending })}>
                      {s.params.length}
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
        </nav>
        <div className="min-w-0 lg:hidden">
          <Card padded={false}>
            <Tabs
              label={p.sectionsLabel}
              value={(active?.id ?? "pricing") as SectionId}
              onChange={setSection}
              items={sections.map((s) => ({ value: s.id as SectionId, label: sectionLabel(s.id) }))}
            />
          </Card>
        </div>

        {active ? (
          <Card padded={false} className="self-start">
            <CardHeader title={sectionLabel(active.id)} subtitle={(p.sectionHints as Record<string, string>)[active.id]} />
            <ul className="divide-y divide-line">
              {active.params.map((param) => {
                const dirty = changed.includes(param.key);
                const err = (dirty ? errors[param.key] : null) ?? serverErrors[`params.${param.key}`];
                const hint = (p.hints as Record<string, string>)[param.key];
                return (
                  <li
                    key={param.key}
                    className={`grid gap-3 px-5 py-4 ${wide(param) ? "" : "sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center"} ${dirty ? "bg-amber-50/60" : ""}`}
                  >
                    <div className="min-w-0">
                      <p className="flex flex-wrap items-center gap-2 text-sm font-medium text-ink">
                        {label(param.key)}
                        <EnumBadge group="policyStatus" value={param.status} />
                        {dirty ? <Badge tone="warning" dot={false}>{p.modified}</Badge> : null}
                      </p>
                      {hint ? <p className="mt-1 max-w-xl text-xs leading-relaxed text-muted">{hint}</p> : null}
                      {param.min !== null && param.min !== undefined && editable ? (
                        <p className="mt-1 text-[0.7rem] text-subtle">{tpl(p.allowedRange, { min: fmt.number(param.min), max: fmt.number(param.max ?? null) })}</p>
                      ) : null}
                      {advanced ? (
                        <p className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-[0.7rem] text-subtle">
                          <code className="rounded bg-navy-50 px-1.5 py-0.5 ltr-nums">{param.key}</code>
                          <span>
                            {p.defaultValue}: <bdi className="ltr-nums">{display(param, param.default)}</bdi>
                          </span>
                          {param.source ? <bdi>{param.source}</bdi> : null}
                        </p>
                      ) : null}
                      {err ? (
                        <p className="mt-1.5 flex items-center gap-1 text-xs font-medium text-coral-700" role="alert">
                          <CircleAlert className="size-3.5" aria-hidden />
                          {err}
                        </p>
                      ) : null}
                    </div>
                    <div className={wide(param) ? "" : "sm:justify-self-end"}>{renderInput(param)}</div>
                  </li>
                );
              })}
            </ul>
          </Card>
        ) : null}

        <Card padded={false} className="self-start lg:col-span-2 xl:col-span-1">
          <CardHeader title={p.history} icon={<History className="size-4" />} />
          <ol className="scroll-thin max-h-[32rem] divide-y divide-line overflow-y-auto">
            {(versions.data?.results ?? []).map((v) => (
              <li key={v.id} className="px-5 py-3 text-sm">
                <p className="flex items-center justify-between gap-2">
                  <span className="font-medium">{tpl(p.version, { v: v.version })}</span>
                  <bdi className="text-xs text-muted">{fmt.dateTime(v.effective_from)}</bdi>
                </p>
                {v.note ? (
                  <p className="mt-1 text-xs break-words text-ink">
                    <bdi>{v.note}</bdi>
                  </p>
                ) : null}
                <p className="mt-1 text-xs text-muted">{Object.keys(v.params as object).map(label).join("، ") || "—"}</p>
              </li>
            ))}
            {!versions.isPending && !versions.data?.results.length ? <li className="px-5 py-6 text-center text-sm text-muted">{p.noVersion}</li> : null}
          </ol>
        </Card>
      </div>

      {editable && changed.length ? (
        <div className="sticky bottom-4 z-10 mt-6 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-amber-200 bg-white px-4 py-3 shadow-pop">
          <p className="flex items-center gap-2 text-sm font-medium text-amber-800">
            <span className="size-2 rounded-full bg-amber-500" aria-hidden />
            {tpl(p.unsavedCount, { n: changed.length })}
            {invalid ? <span className="text-coral-700">· {p.fixErrors}</span> : null}
          </p>
          <div className="flex gap-2">
            <Button variant="secondary" icon={<RotateCcw className="size-4" aria-hidden />} onClick={() => setDraft({})}>
              {p.discard}
            </Button>
            <Button icon={<Save className="size-4" aria-hidden />} disabled={invalid} onClick={() => setConfirming(true)}>
              {p.saveVersion}
            </Button>
          </div>
        </div>
      ) : null}

      <ConfirmDialog
        open={confirming}
        onClose={() => setConfirming(false)}
        title={p.saveVersion}
        message={
          <span className="block space-y-3">
            <span className="block divide-y divide-line rounded-lg border border-line">
              {changed.map((k) => {
                const param = params.find((x) => x.key === k)!;
                return (
                  <span key={k} className="block px-3 py-2 text-xs">
                    <strong className="block text-ink">{label(k)}</strong>
                    <span className="mt-0.5 flex flex-wrap items-center gap-1.5 text-muted">
                      <bdi>{display(param, cfg.effective[k])}</bdi>
                      <span aria-hidden className="inline-block ltr:-scale-x-100">←</span>
                      <bdi className="font-semibold text-ink">{display(param, draft[k])}</bdi>
                    </span>
                  </span>
                );
              })}
            </span>
            <span className="block text-xs text-muted">{p.statusUnchanged}</span>
          </span>
        }
        confirmLabel={p.saveVersion}
        note={{ label: p.changeNote }}
        onConfirm={async (note) => {
          const changes = Object.fromEntries(changed.map((k) => [k, draft[k]]));
          const version = await save.mutateAsync({ params: changes, note });
          setDraft({});
          await versions.refetch();
          return version;
        }}
      />
    </>
  );
}
