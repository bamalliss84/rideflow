"use client";

import { Pencil, Plus } from "lucide-react";
import { useState, type FormEvent } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { Dialog } from "@/components/ui/Dialog";
import { Field, Input, Switch } from "@/components/ui/Form";
import { PageHeader } from "@/components/ui/Page";
import { InlineError } from "@/components/ui/States";
import { api, ApiError, newIdempotencyKey, type Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";
import { fromMinor, toMinor } from "@/lib/money";

type Plan = Schemas["SubscriptionPlan"];

export default function PlansPage() {
  const { t } = useI18n();
  const { fmt, can } = useSession();
  const s = t.subscriptions;
  const q = useApi<Plan[]>("admin/subscription-plans");
  const [dialog, setDialog] = useState<Plan | "new" | null>(null);
  const editable = can("subscriptions.manage");
  return (
    <>
      <PageHeader
        title={s.plansTitle}
        subtitle={s.plansSubtitle}
        actions={
          editable ? (
            <Button icon={<Plus className="size-4" aria-hidden />} onClick={() => setDialog("new")}>
              {s.newPlan}
            </Button>
          ) : null
        }
      />
      <Card padded={false}>
        <DataTable<Plan>
          rows={q.data}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(p) => p.id}
          columns={[
            { key: "name", header: t.common.name, cell: (p) => <span className="font-medium">{p.name}</span> },
            { key: "code", header: s.code, hideBelow: "sm", cell: (p) => <span className="text-muted ltr-nums">{p.code}</span> },
            { key: "price", header: s.price, align: "end", cell: (p) => <bdi className="font-medium">{fmt.money(p.price_minor)}</bdi> },
            { key: "duration", header: s.duration, align: "end", cell: (p) => fmt.number(p.duration_days) },
            { key: "trial", header: s.trial, hideBelow: "md", cell: (p) => (p.is_trial ? <Badge tone="info">{s.trial}</Badge> : "—") },
            { key: "active", header: t.common.status, cell: (p) => <Badge tone={p.is_active ? "success" : "neutral"}>{p.is_active ? t.common.active : t.common.inactive}</Badge> },
            {
              key: "edit",
              header: <span className="sr-only">{t.common.actions}</span>,
              align: "end",
              cell: (p) =>
                editable ? (
                  <Button size="sm" variant="ghost" icon={<Pencil className="size-4" aria-hidden />} onClick={() => setDialog(p)}>
                    {t.common.edit}
                  </Button>
                ) : null,
            },
          ]}
        />
      </Card>
      {dialog ? <PlanDialog plan={dialog === "new" ? null : dialog} onClose={() => setDialog(null)} onSaved={() => void q.refetch()} /> : null}
    </>
  );
}

function PlanDialog({ plan, onClose, onSaved }: { plan: Plan | null; onClose: () => void; onSaved: () => void }) {
  const { t, tpl } = useI18n();
  const { me } = useSession();
  const s = t.subscriptions;
  const units = me.currency_minor_units ?? 2;
  const [form, setForm] = useState({
    name: plan?.name ?? "",
    code: plan?.code ?? "",
    price: plan ? fromMinor(plan.price_minor, units) : "",
    duration_days: String(plan?.duration_days ?? 30),
    is_trial: plan?.is_trial ?? false,
    is_active: plan?.is_active ?? true,
    sort_order: String(plan?.sort_order ?? 0),
  });
  const [key] = useState(newIdempotencyKey);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const priceMinor = toMinor(form.price, units);
  const fe = error instanceof ApiError ? error.fieldErrors() : {};
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (priceMinor === null) return;
    setBusy(true);
    setError(null);
    try {
      const body = {
        name: form.name.trim(),
        code: form.code.trim(),
        price_minor: priceMinor,
        duration_days: Number(form.duration_days),
        is_trial: form.is_trial,
        is_active: form.is_active,
        sort_order: Number(form.sort_order),
      };
      if (plan) await api(`admin/subscription-plans/${plan.id}`, { method: "PATCH", body });
      else await api("admin/subscription-plans", { method: "POST", body, idempotencyKey: key });
      onSaved();
      onClose();
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog open onClose={onClose} title={plan ? s.editPlan : s.newPlan}>
      <form onSubmit={submit} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label={t.common.name} required error={fe.name}>
            {(f) => <Input {...f} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required />}
          </Field>
          <Field label={s.code} required error={fe.code}>
            {(f) => <Input {...f} value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} dir="ltr" pattern="[a-z0-9-_]+" required />}
          </Field>
          <Field label={s.price} required hint={tpl(s.priceMinorHint, { currency: me.currency ?? "" })} error={form.price && priceMinor === null ? t.errors.validation : fe.price_minor}>
            {(f) => <Input {...f} value={form.price} onChange={(e) => setForm({ ...form, price: e.target.value })} inputMode="decimal" dir="ltr" required />}
          </Field>
          <Field label={s.duration} required error={fe.duration_days}>
            {(f) => <Input {...f} type="number" min={1} value={form.duration_days} onChange={(e) => setForm({ ...form, duration_days: e.target.value })} dir="ltr" required />}
          </Field>
          <Field label={s.sortOrder}>
            {(f) => <Input {...f} type="number" min={0} value={form.sort_order} onChange={(e) => setForm({ ...form, sort_order: e.target.value })} dir="ltr" />}
          </Field>
          <div className="space-y-3 pt-1">
            <label className="flex items-center gap-3 text-sm">
              <Switch checked={form.is_trial} onChange={(v) => setForm({ ...form, is_trial: v })} label={s.trial} />
              {s.trial}
            </label>
            <label className="flex items-center gap-3 text-sm">
              <Switch checked={form.is_active} onChange={(v) => setForm({ ...form, is_active: v })} label={t.common.active} />
              {t.common.active}
            </label>
          </div>
        </div>
        <InlineError error={Object.keys(fe).length ? null : error} />
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={busy}>
            {t.common.cancel}
          </Button>
          <Button type="submit" loading={busy} disabled={priceMinor === null}>
            {t.common.save}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}
