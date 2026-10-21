"use client";

import { AppWindow, KeyRound, Pencil, Plus, ShieldCheck, UserPlus } from "lucide-react";
import { useParams } from "next/navigation";
import { useState, type FormEvent } from "react";

import { CopyText, EnumBadge, Phone } from "@/components/domain/Display";
import { TenantForm } from "@/components/domain/TenantForm";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader, KeyValues } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { ConfirmDialog, Dialog } from "@/components/ui/Dialog";
import { Field, Input, Select } from "@/components/ui/Form";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, InlineError, PageSkeleton } from "@/components/ui/States";
import { api, ApiError, type Schemas } from "@/lib/api/client";
import { useAction, useApi } from "@/lib/api/hooks";

type Tenant = Schemas["Tenant"];
type App = Schemas["TenantApplication"];
type Member = Schemas["Membership"];

export default function TenantDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { t } = useI18n();
  const { fmt } = useSession();
  const p = t.platform;
  const base = `platform/tenants/${id}`;
  const tenant = useApi<Tenant>(base);
  const apps = useApi<App[]>(`${base}/applications`);
  const admins = useApi<Member[]>(`${base}/admins`);
  const [editing, setEditing] = useState(false);
  const [statusDialog, setStatusDialog] = useState(false);
  const [appDialog, setAppDialog] = useState(false);
  const [adminDialog, setAdminDialog] = useState(false);
  const [resetTarget, setResetTarget] = useState<Member | null>(null);

  const invalidate = [base, "platform/overview", "platform/tenants"];
  const setStatus = useAction<undefined, Tenant>("POST", () => `${base}/${tenant.data?.status === "active" ? "suspend" : "activate"}`, { invalidate, inlineErrors: true });
  const resetMfa = useAction<{ id: string }>("POST", (v) => `${base}/admins/${v.id}/reset-mfa`, { invalidate: [`${base}/admins`], inlineErrors: true });

  if (tenant.isPending) return <PageSkeleton />;
  if (tenant.error) return <ErrorState error={tenant.error} onRetry={() => void tenant.refetch()} />;
  const d = tenant.data;
  const active = d.status === "active";

  return (
    <>
      <PageHeader
        title={d.name}
        meta={<EnumBadge group="tenantStatus" value={d.status} />}
        crumbs={[{ label: t.nav.tenants, href: "/platform/tenants" }, { label: d.name }]}
        actions={
          <>
            <Button variant="secondary" icon={<Pencil className="size-4" aria-hidden />} onClick={() => setEditing(true)}>
              {t.common.edit}
            </Button>
            <Button variant={active ? "outline-danger" : "accent"} onClick={() => setStatusDialog(true)}>
              {active ? p.suspend : p.activate}
            </Button>
          </>
        }
      />
      <div className="grid gap-6 xl:grid-cols-3">
        <Card className="xl:col-span-1">
          <h2 className="mb-4 text-sm font-semibold">{p.profile}</h2>
          <KeyValues
            columns={1}
            items={[
              { label: p.slug, value: <span className="ltr-nums">{d.slug}</span> },
              { label: p.currency, value: <span className="ltr-nums">{d.currency} · {d.currency_minor_units}</span> },
              { label: p.timeZone, value: <span className="ltr-nums">{d.time_zone}</span> },
              { label: p.locale, value: d.locale === "ar" ? "العربية" : "English" },
              { label: t.common.created, value: fmt.dateTime(d.created_at) },
            ]}
          />
        </Card>
        <div className="space-y-6 xl:col-span-2">
          <Card padded={false}>
            <CardHeader
              title={p.apps}
              subtitle={p.appsHint}
              icon={<AppWindow className="size-4" />}
              actions={
                <Button size="sm" variant="secondary" icon={<Plus className="size-4" aria-hidden />} onClick={() => setAppDialog(true)}>
                  {p.newApp}
                </Button>
              }
            />
            <DataTable<App>
              rows={apps.data}
              loading={apps.isPending}
              error={apps.error}
              rowKey={(r) => r.id}
              columns={[
                { key: "name", header: p.appName, cell: (r) => <span className="font-medium">{r.name}</span> },
                { key: "type", header: t.common.type, cell: (r) => <Badge tone="info" dot={false}>{t.enums.appType[r.app_type as keyof typeof t.enums.appType] ?? r.app_type}</Badge> },
                { key: "client", header: p.clientId, cell: (r) => <CopyText value={r.client_id} /> },
                { key: "active", header: t.common.status, hideBelow: "md", cell: (r) => <Badge tone={r.is_active ? "success" : "neutral"}>{r.is_active ? t.common.active : t.common.inactive}</Badge> },
              ]}
            />
          </Card>
          <Card padded={false}>
            <CardHeader
              title={p.admins}
              icon={<ShieldCheck className="size-4" />}
              actions={
                <Button size="sm" variant="secondary" icon={<UserPlus className="size-4" aria-hidden />} onClick={() => setAdminDialog(true)}>
                  {p.newAdmin}
                </Button>
              }
            />
            <DataTable<Member>
              rows={admins.data}
              loading={admins.isPending}
              error={admins.error}
              rowKey={(r) => r.id}
              columns={[
                { key: "name", header: t.common.name, cell: (r) => <span className="font-medium">{r.full_name || "—"}</span> },
                { key: "phone", header: t.common.phone, cell: (r) => <Phone value={r.phone} /> },
                { key: "role", header: t.common.role, cell: (r) => (t.roles as Record<string, string>)[r.role] ?? r.role },
                {
                  key: "mfa",
                  header: t.members.mfa,
                  hideBelow: "md",
                  cell: (r) => <Badge tone={r.mfa_enrolled ? "success" : "warning"}>{r.mfa_enrolled ? t.members.mfaOn : t.members.mfaOff}</Badge>,
                },
                {
                  key: "actions",
                  header: <span className="sr-only">{t.common.actions}</span>,
                  align: "end",
                  cell: (r) =>
                    r.mfa_enrolled ? (
                      <Button size="sm" variant="ghost" icon={<KeyRound className="size-4" aria-hidden />} onClick={() => setResetTarget(r)}>
                        {p.resetMfa}
                      </Button>
                    ) : null,
                },
              ]}
            />
          </Card>
        </div>
      </div>

      <Dialog open={editing} onClose={() => setEditing(false)} title={t.common.edit} size="lg">
        <TenantForm
          initial={d}
          submitLabel={t.common.save}
          onCancel={() => setEditing(false)}
          onSubmit={async (body) => {
            await api(base, { method: "PATCH", body });
            await tenant.refetch();
            setEditing(false);
          }}
        />
      </Dialog>
      <ConfirmDialog
        open={statusDialog}
        onClose={() => setStatusDialog(false)}
        title={active ? p.suspend : p.activate}
        message={active ? p.suspendConfirm : p.activateConfirm}
        confirmLabel={active ? p.suspend : p.activate}
        tone={active ? "danger" : "accent"}
        onConfirm={() => setStatus.mutateAsync(undefined)}
      />
      <ConfirmDialog
        open={resetTarget !== null}
        onClose={() => setResetTarget(null)}
        title={p.resetMfa}
        message={`${p.resetConfirm} (${resetTarget?.full_name || resetTarget?.phone || ""})`}
        confirmLabel={p.resetMfa}
        tone="danger"
        onConfirm={() => resetMfa.mutateAsync({ id: resetTarget!.id })}
      />
      <AppDialog open={appDialog} onClose={() => setAppDialog(false)} path={`${base}/applications`} onDone={() => void apps.refetch()} />
      <AdminDialog open={adminDialog} onClose={() => setAdminDialog(false)} path={`${base}/admins`} onDone={() => void admins.refetch()} />
    </>
  );
}

function AppDialog({ open, onClose, path, onDone }: { open: boolean; onClose: () => void; path: string; onDone: () => void }) {
  const { t } = useI18n();
  const p = t.platform;
  const [name, setName] = useState("");
  const [type, setType] = useState("admin");
  const action = useAction<{ name: string; app_type: string }>("POST", path, { inlineErrors: true });
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    await action.mutateAsync({ name: name.trim(), app_type: type });
    onDone();
    setName("");
    onClose();
  };
  return (
    <Dialog open={open} onClose={onClose} title={p.newApp}>
      <form onSubmit={(e) => void submit(e).catch(() => null)} className="space-y-4">
        <Field label={p.appName} required>
          {(f) => <Input {...f} value={name} onChange={(e) => setName(e.target.value)} required maxLength={120} />}
        </Field>
        <Field label={t.common.type} required>
          {(f) => (
            <Select {...f} value={type} onChange={(e) => setType(e.target.value)}>
              {(["admin", "rider", "driver"] as const).map((v) => (
                <option key={v} value={v}>
                  {t.enums.appType[v]}
                </option>
              ))}
            </Select>
          )}
        </Field>
        <InlineError error={action.error} />
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>
            {t.common.cancel}
          </Button>
          <Button type="submit" loading={action.isPending} disabled={!name.trim()}>
            {t.common.create}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

function AdminDialog({ open, onClose, path, onDone }: { open: boolean; onClose: () => void; path: string; onDone: () => void }) {
  const { t } = useI18n();
  const [form, setForm] = useState({ phone: "", full_name: "", role: "owner" });
  const action = useAction<typeof form>("POST", path, { inlineErrors: true });
  const fieldErrors = action.error instanceof ApiError ? action.error.fieldErrors() : {};
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    await action.mutateAsync({ ...form, phone: form.phone.trim() });
    onDone();
    setForm({ phone: "", full_name: "", role: "owner" });
    onClose();
  };
  return (
    <Dialog open={open} onClose={onClose} title={t.platform.newAdmin}>
      <form onSubmit={(e) => void submit(e).catch(() => null)} className="space-y-4">
        <Field label={t.common.phone} hint={t.auth.phoneHint} required error={fieldErrors.phone}>
          {(f) => <Input {...f} value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} type="tel" dir="ltr" required />}
        </Field>
        <Field label={t.members.fullName}>
          {(f) => <Input {...f} value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} maxLength={120} />}
        </Field>
        <Field label={t.common.role} required>
          {(f) => (
            <Select {...f} value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
              <option value="owner">{t.roles.owner}</option>
              <option value="admin">{t.roles.admin}</option>
            </Select>
          )}
        </Field>
        {!fieldErrors.phone ? <InlineError error={action.error} /> : null}
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>
            {t.common.cancel}
          </Button>
          <Button type="submit" loading={action.isPending} disabled={!form.phone.trim()}>
            {t.common.add}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}

