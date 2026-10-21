"use client";

import { useState, type FormEvent } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { Button } from "@/components/ui/Button";
import { Field, Input, Select } from "@/components/ui/Form";
import { InlineError } from "@/components/ui/States";
import { ApiError, type Schemas } from "@/lib/api/client";

type Tenant = Schemas["Tenant"];

export const TIME_ZONES = ["Asia/Aden", "Asia/Riyadh", "Asia/Dubai", "Asia/Muscat", "Asia/Qatar", "Asia/Kuwait", "Asia/Bahrain", "Africa/Cairo", "Europe/London", "UTC"];

export function TenantForm({ initial, onSubmit, submitLabel, onCancel }: {
  initial?: Partial<Tenant>;
  onSubmit: (body: Record<string, unknown>) => Promise<unknown>;
  submitLabel: string;
  onCancel: () => void;
}) {
  const { t } = useI18n();
  const p = t.platform;
  const editing = Boolean(initial?.id);
  const [form, setForm] = useState({
    name: initial?.name ?? "",
    slug: initial?.slug ?? "",
    currency: initial?.currency ?? "",
    currency_minor_units: String(initial?.currency_minor_units ?? 2),
    time_zone: initial?.time_zone ?? "Asia/Aden",
    locale: initial?.locale ?? "ar",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const fieldErrors = error instanceof ApiError ? error.fieldErrors() : {};
  const set = (k: keyof typeof form) => (e: { target: { value: string } }) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const body: Record<string, unknown> = { name: form.name.trim(), time_zone: form.time_zone, locale: form.locale };
      if (!editing) {
        body.slug = form.slug.trim();
        body.currency = form.currency.trim().toUpperCase();
        body.currency_minor_units = Number(form.currency_minor_units);
      }
      await onSubmit(body);
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-4">
      <Field label={p.name} required error={fieldErrors.name}>
        {(f) => <Input {...f} value={form.name} onChange={set("name")} required maxLength={160} />}
      </Field>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={p.slug} hint={editing ? undefined : p.slugHint} required error={fieldErrors.slug}>
          {(f) => <Input {...f} value={form.slug} onChange={set("slug")} disabled={editing} dir="ltr" pattern="[a-z0-9-]+" required />}
        </Field>
        <Field label={p.currency} hint={editing ? p.currencyLocked : undefined} required error={fieldErrors.currency}>
          {(f) => <Input {...f} value={form.currency} onChange={set("currency")} disabled={editing} dir="ltr" maxLength={3} placeholder="YER" required />}
        </Field>
        <Field label={p.minorUnits} required error={fieldErrors.currency_minor_units}>
          {(f) => <Input {...f} type="number" min={0} max={3} value={form.currency_minor_units} onChange={set("currency_minor_units")} disabled={editing} dir="ltr" />}
        </Field>
        <Field label={p.timeZone} required error={fieldErrors.time_zone}>
          {(f) => (
            <Select {...f} value={form.time_zone} onChange={set("time_zone")}>
              {[...new Set([form.time_zone, ...TIME_ZONES])].map((z) => (
                <option key={z} value={z}>
                  {z}
                </option>
              ))}
            </Select>
          )}
        </Field>
        <Field label={p.locale} error={fieldErrors.locale}>
          {(f) => (
            <Select {...f} value={form.locale} onChange={set("locale")}>
              <option value="ar">العربية</option>
              <option value="en">English</option>
            </Select>
          )}
        </Field>
      </div>
      {Object.keys(fieldErrors).length === 0 ? <InlineError error={error} /> : null}
      <div className="flex justify-end gap-2 pt-1">
        <Button variant="secondary" onClick={onCancel} disabled={busy}>
          {t.common.cancel}
        </Button>
        <Button type="submit" loading={busy}>
          {submitLabel}
        </Button>
      </div>
    </form>
  );
}
