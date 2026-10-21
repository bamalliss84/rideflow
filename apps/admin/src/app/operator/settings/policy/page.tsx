"use client";

import { History, Save } from "lucide-react";
import { useMemo, useState } from "react";

import { EnumBadge, JsonView } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader } from "@/components/ui/Card";
import { ConfirmDialog } from "@/components/ui/Dialog";
import { Input, Switch, Textarea } from "@/components/ui/Form";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import type { Page, Schemas } from "@/lib/api/client";
import { useAction, useApi } from "@/lib/api/hooks";

type Config = Schemas["EffectiveConfig"];
type Param = Schemas["PolicyParam"];
type Version = Schemas["ConfigVersion"];

function same(a: unknown, b: unknown) {
  return JSON.stringify(a) === JSON.stringify(b);
}

export default function PolicyPage() {
  const { t, tpl } = useI18n();
  const { fmt, can } = useSession();
  const p = t.policy;
  const editable = can("config.manage");
  const q = useApi<Config>("admin/config");
  const versions = useApi<Page<Version>>("admin/config/versions", { page_size: 20 });
  const [draft, setDraft] = useState<Record<string, unknown>>({});
  const [jsonErrors, setJsonErrors] = useState<Record<string, boolean>>({});
  const [confirming, setConfirming] = useState(false);
  const save = useAction<{ params: Record<string, unknown>; note: string }, Version>("POST", "admin/config", {
    invalidate: ["admin/config"],
    inlineErrors: true,
  });

  const groups = useMemo(() => {
    const out: Record<string, Param[]> = {};
    for (const param of q.data?.parameters ?? []) {
      const g = param.key.split(".")[0] ?? "other";
      (out[g] ??= []).push(param);
    }
    return out;
  }, [q.data]);

  if (q.isPending) return <PageSkeleton />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />;
  const cfg = q.data;
  const changed = Object.keys(draft).filter((k) => !same(draft[k], cfg.effective[k]));
  const hasJsonError = Object.values(jsonErrors).some(Boolean);

  const valueOf = (key: string) => (key in draft ? draft[key] : cfg.effective[key]);
  const set = (key: string, value: unknown) => setDraft((d) => ({ ...d, [key]: value }));

  const renderInput = (param: Param) => {
    const value = valueOf(param.key);
    const label = (p.params as Record<string, string>)[param.key] ?? param.key;
    if (!editable) {
      return typeof value === "object" && value !== null ? <JsonView value={value} /> : <span className="font-medium ltr-nums">{typeof value === "boolean" ? (value ? t.common.yes : t.common.no) : String(value)}</span>;
    }
    if (param.type === "bool") return <Switch checked={Boolean(value)} onChange={(v) => set(param.key, v)} label={label} />;
    if (param.type === "int" || param.type === "float") {
      return (
        <Input
          type="number"
          aria-label={label}
          dir="ltr"
          className="w-40"
          min={param.min ?? undefined}
          max={param.max ?? undefined}
          step={param.type === "float" ? "0.1" : "1"}
          value={String(value ?? "")}
          onChange={(e) => set(param.key, e.target.value === "" ? "" : param.type === "int" ? Math.trunc(Number(e.target.value)) : Number(e.target.value))}
        />
      );
    }
    if (param.type === "str") return <Input aria-label={label} dir="ltr" className="w-40" value={String(value ?? "")} onChange={(e) => set(param.key, e.target.value)} />;
    return (
      <Textarea
        aria-label={label}
        dir="ltr"
        rows={2}
        className={`font-mono text-xs ${jsonErrors[param.key] ? "border-coral-400" : ""}`}
        defaultValue={JSON.stringify(value)}
        onChange={(e) => {
          try {
            set(param.key, JSON.parse(e.target.value));
            setJsonErrors((j) => ({ ...j, [param.key]: false }));
          } catch {
            setJsonErrors((j) => ({ ...j, [param.key]: true }));
          }
        }}
      />
    );
  };

  return (
    <>
      <PageHeader
        title={p.title}
        subtitle={p.subtitle}
        meta={<Badge tone="info">{cfg.version ? tpl(p.version, { v: cfg.version }) : p.noVersion}</Badge>}
        actions={
          editable ? (
            <Button icon={<Save className="size-4" aria-hidden />} disabled={!changed.length || hasJsonError} onClick={() => setConfirming(true)}>
              {p.saveVersion}
              {changed.length ? ` (${tpl(p.changed, { n: changed.length })})` : ""}
            </Button>
          ) : null
        }
      />
      <p className="mb-5 text-xs text-muted">{editable ? p.statusHint : p.readOnly}</p>
      <div className="grid gap-6 xl:grid-cols-3">
        <div className="space-y-6 xl:col-span-2">
          {Object.entries(groups).map(([group, params]) => (
            <Card key={group} padded={false}>
              <CardHeader title={(p.groups as Record<string, string>)[group] ?? group} />
              <ul className="divide-y divide-line">
                {params.map((param) => {
                  const dirty = param.key in draft && !same(draft[param.key], cfg.effective[param.key]);
                  return (
                    <li key={param.key} className={`grid gap-3 px-5 py-3.5 sm:grid-cols-[1fr_auto] sm:items-center ${dirty ? "bg-amber-50/50" : ""}`}>
                      <div className="min-w-0">
                        <p className="flex flex-wrap items-center gap-2 text-sm font-medium">
                          {(p.params as Record<string, string>)[param.key] ?? param.key}
                          <EnumBadge group="policyStatus" value={param.status} />
                        </p>
                        <p className="mt-0.5 text-xs text-muted">
                          <code className="ltr-nums">{param.key}</code> · {p.defaultValue}: <span className="ltr-nums">{JSON.stringify(param.default)}</span>
                        </p>
                      </div>
                      <div className="sm:justify-self-end">{renderInput(param)}</div>
                    </li>
                  );
                })}
              </ul>
            </Card>
          ))}
        </div>
        <Card padded={false} className="self-start">
          <CardHeader title={p.history} icon={<History className="size-4" />} />
          <ol className="divide-y divide-line">
            {(versions.data?.results ?? []).map((v) => (
              <li key={v.id} className="px-5 py-3 text-sm">
                <p className="font-medium">{tpl(p.version, { v: v.version })}</p>
                <p className="text-xs text-muted">{fmt.dateTime(v.effective_from)}</p>
                {v.note ? <p className="mt-1 text-xs">{v.note}</p> : null}
                <p className="mt-1 text-xs text-muted ltr-nums">{Object.keys(v.params as object).join(", ") || "—"}</p>
              </li>
            ))}
            {!versions.isPending && !versions.data?.results.length ? <li className="px-5 py-6 text-center text-sm text-muted">{p.noVersion}</li> : null}
          </ol>
        </Card>
      </div>
      <ConfirmDialog
        open={confirming}
        onClose={() => setConfirming(false)}
        title={p.saveVersion}
        message={
          <span className="block space-y-1">
            {changed.map((k) => (
              <span key={k} className="block text-xs">
                <strong>{(p.params as Record<string, string>)[k] ?? k}</strong>: <span className="ltr-nums">{JSON.stringify(cfg.effective[k])} → {JSON.stringify(draft[k])}</span>
              </span>
            ))}
          </span>
        }
        confirmLabel={p.saveVersion}
        note={{ label: p.changeNote }}
        onConfirm={async (note) => {
          const params = Object.fromEntries(changed.map((k) => [k, draft[k]]));
          const version = await save.mutateAsync({ params, note });
          setDraft({});
          await versions.refetch();
          return version;
        }}
      />
    </>
  );
}
