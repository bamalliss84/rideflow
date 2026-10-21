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
import { Field, Input, Switch, Textarea } from "@/components/ui/Form";
import { PageHeader } from "@/components/ui/Page";
import { InlineError } from "@/components/ui/States";
import { api, ApiError, newIdempotencyKey, type Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

type Account = Schemas["DepositAccount"];

export default function AccountsPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const s = t.subscriptions;
  const q = useApi<Account[]>("admin/deposit-accounts");
  const [dialog, setDialog] = useState<Account | "new" | null>(null);
  const editable = can("subscriptions.manage");
  return (
    <>
      <PageHeader
        title={s.accountsTitle}
        subtitle={s.accountsSubtitle}
        actions={
          editable ? (
            <Button icon={<Plus className="size-4" aria-hidden />} onClick={() => setDialog("new")}>
              {s.newAccount}
            </Button>
          ) : null
        }
      />
      <Card padded={false}>
        <DataTable<Account>
          rows={q.data}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(a) => a.id}
          columns={[
            { key: "bank", header: s.bank, cell: (a) => <span className="font-medium">{a.bank_name}</span> },
            { key: "name", header: s.accountName, cell: (a) => a.account_name },
            { key: "number", header: s.accountNumber, cell: (a) => <span className="ltr-nums">{a.account_number}</span> },
            { key: "instructions", header: s.instructions, hideBelow: "lg", cell: (a) => <span className="line-clamp-2 max-w-80 text-xs text-muted">{a.instructions || "—"}</span> },
            { key: "active", header: t.common.status, cell: (a) => <Badge tone={a.is_active ? "success" : "neutral"}>{a.is_active ? t.common.active : t.common.inactive}</Badge> },
            {
              key: "edit",
              header: <span className="sr-only">{t.common.actions}</span>,
              align: "end",
              cell: (a) =>
                editable ? (
                  <Button size="sm" variant="ghost" icon={<Pencil className="size-4" aria-hidden />} onClick={() => setDialog(a)}>
                    {t.common.edit}
                  </Button>
                ) : null,
            },
          ]}
        />
      </Card>
      {dialog ? <AccountDialog account={dialog === "new" ? null : dialog} onClose={() => setDialog(null)} onSaved={() => void q.refetch()} /> : null}
    </>
  );
}

function AccountDialog({ account, onClose, onSaved }: { account: Account | null; onClose: () => void; onSaved: () => void }) {
  const { t } = useI18n();
  const s = t.subscriptions;
  const [form, setForm] = useState({
    bank_name: account?.bank_name ?? "",
    account_name: account?.account_name ?? "",
    account_number: account?.account_number ?? "",
    instructions: account?.instructions ?? "",
    is_active: account?.is_active ?? true,
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
      if (account) await api(`admin/deposit-accounts/${account.id}`, { method: "PATCH", body: form });
      else await api("admin/deposit-accounts", { method: "POST", body: form, idempotencyKey: key });
      onSaved();
      onClose();
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog open onClose={onClose} title={account ? s.editAccount : s.newAccount}>
      <form onSubmit={submit} className="space-y-4">
        <Field label={s.bank} required error={fe.bank_name}>
          {(f) => <Input {...f} value={form.bank_name} onChange={(e) => setForm({ ...form, bank_name: e.target.value })} required />}
        </Field>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label={s.accountName} required error={fe.account_name}>
            {(f) => <Input {...f} value={form.account_name} onChange={(e) => setForm({ ...form, account_name: e.target.value })} required />}
          </Field>
          <Field label={s.accountNumber} required error={fe.account_number}>
            {(f) => <Input {...f} value={form.account_number} onChange={(e) => setForm({ ...form, account_number: e.target.value })} dir="ltr" required />}
          </Field>
        </div>
        <Field label={s.instructions} error={fe.instructions}>
          {(f) => <Textarea {...f} value={form.instructions} onChange={(e) => setForm({ ...form, instructions: e.target.value })} rows={3} />}
        </Field>
        <label className="flex items-center gap-3 text-sm">
          <Switch checked={form.is_active} onChange={(v) => setForm({ ...form, is_active: v })} label={t.common.active} />
          {t.common.active}
        </label>
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
