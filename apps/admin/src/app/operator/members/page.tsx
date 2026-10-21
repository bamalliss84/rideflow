"use client";

import { KeyRound, UserMinus, UserPlus, UserCheck } from "lucide-react";
import { useState, type FormEvent } from "react";

import { EnumBadge, Person } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { ConfirmDialog, Dialog } from "@/components/ui/Dialog";
import { Field, Input, Select } from "@/components/ui/Form";
import { FilterSelect, PageHeader, Tabs, Toolbar } from "@/components/ui/Page";
import { InlineError } from "@/components/ui/States";
import { ApiError, type Schemas } from "@/lib/api/client";
import { useAction, useApiPage, useListState } from "@/lib/api/hooks";

type Member = Schemas["Membership"];
const STAFF = ["owner", "admin", "reviewer", "finance", "support"] as const;
const ALL_ROLES = [...STAFF, "driver", "rider"] as const;

export default function MembersPage() {
  const { t } = useI18n();
  const { fmt, me, hasRole } = useSession();
  const m = t.members;
  const { filters, setFilters, page, setPage } = useListState<{ group: string; role: string; status: string }>({ group: "staff", role: "", status: "" });
  const role = filters.role ? [filters.role] : filters.group === "staff" ? [...STAFF] : [filters.group];
  const q = useApiPage<Member>("admin/members", { role, status: filters.status }, page);
  const rows = q.data?.results;
  const [inviting, setInviting] = useState(false);
  const [target, setTarget] = useState<{ member: Member; op: "suspend" | "reactivate" | "reset-mfa" } | null>(null);
  const action = useAction<{ id: string; op: string }>("POST", (v) => `admin/members/${v.id}/${v.op}`, { invalidate: ["admin/members"], inlineErrors: true, success: m.title });
  const roleLabel = (r: string) => (t.roles as Record<string, string>)[r] ?? r;

  return (
    <>
      <PageHeader
        title={m.title}
        subtitle={m.subtitle}
        actions={
          <Button icon={<UserPlus className="size-4" aria-hidden />} onClick={() => setInviting(true)}>
            {m.invite}
          </Button>
        }
      />
      <Card padded={false}>
        <Tabs
          label={t.common.role}
          value={filters.group}
          onChange={(group) => setFilters({ group, role: "" })}
          items={[
            { value: "staff", label: m.staffOnly },
            { value: "driver", label: t.nav.drivers },
            { value: "rider", label: t.nav.riders },
          ]}
        />
        <Toolbar>
          {filters.group === "staff" ? (
            <FilterSelect label={t.common.role} value={filters.role} onChange={(r) => setFilters({ role: r })} options={STAFF.map((r) => ({ value: r, label: roleLabel(r) }))} />
          ) : null}
          <FilterSelect
            label={t.common.status}
            value={filters.status as "" | "active" | "suspended"}
            onChange={(status) => setFilters({ status })}
            options={(["active", "suspended"] as const).map((v) => ({ value: v, label: t.enums.membershipStatus[v] }))}
          />
        </Toolbar>
        <DataTable<Member>
          rows={rows}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(r) => r.id}
          columns={[
            { key: "person", header: t.common.name, cell: (r) => <Person name={r.full_name} phone={r.phone} /> },
            { key: "role", header: t.common.role, cell: (r) => <Badge tone="info" dot={false}>{roleLabel(r.role)}</Badge> },
            { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="membershipStatus" value={r.status} /> },
            {
              key: "mfa",
              header: m.mfa,
              hideBelow: "md",
              cell: (r) =>
                (STAFF as readonly string[]).includes(r.role) ? <Badge tone={r.mfa_enrolled ? "success" : "warning"}>{r.mfa_enrolled ? m.mfaOn : m.mfaOff}</Badge> : <span className="text-subtle">—</span>,
            },
            { key: "created", header: t.common.created, hideBelow: "lg", cell: (r) => fmt.date(r.created_at) },
            {
              key: "actions",
              header: <span className="sr-only">{t.common.actions}</span>,
              align: "end",
              cell: (r) => {
                const self = r.user_id === me.user.id;
                const ownerLocked = r.role === "owner" && !hasRole("owner");
                if (self || ownerLocked) return null;
                return (
                  <span className="inline-flex flex-wrap justify-end gap-1">
                    {(STAFF as readonly string[]).includes(r.role) && r.mfa_enrolled ? (
                      <Button size="sm" variant="ghost" icon={<KeyRound className="size-4" aria-hidden />} onClick={() => setTarget({ member: r, op: "reset-mfa" })}>
                        {m.resetMfa}
                      </Button>
                    ) : null}
                    {r.status === "active" ? (
                      <Button size="sm" variant="ghost" className="text-coral-700" icon={<UserMinus className="size-4" aria-hidden />} onClick={() => setTarget({ member: r, op: "suspend" })}>
                        {m.suspend}
                      </Button>
                    ) : (
                      <Button size="sm" variant="ghost" icon={<UserCheck className="size-4" aria-hidden />} onClick={() => setTarget({ member: r, op: "reactivate" })}>
                        {m.reactivate}
                      </Button>
                    )}
                  </span>
                );
              },
            },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
      <ConfirmDialog
        open={target !== null}
        onClose={() => setTarget(null)}
        title={target ? { suspend: m.suspend, reactivate: m.reactivate, "reset-mfa": m.resetMfa }[target.op] : ""}
        message={target ? `${{ suspend: m.suspendConfirm, reactivate: m.reactivateConfirm, "reset-mfa": m.resetConfirm }[target.op]} (${target.member.full_name || target.member.phone} · ${roleLabel(target.member.role)})` : ""}
        confirmLabel={target ? { suspend: m.suspend, reactivate: m.reactivate, "reset-mfa": m.resetMfa }[target.op] : ""}
        tone={target?.op === "reactivate" ? "accent" : "danger"}
        onConfirm={() => action.mutateAsync({ id: target!.member.id, op: target!.op })}
      />
      {inviting ? <InviteDialog onClose={() => setInviting(false)} canOwner={hasRole("owner")} roles={ALL_ROLES} /> : null}
    </>
  );
}

function InviteDialog({ onClose, canOwner, roles }: { onClose: () => void; canOwner: boolean; roles: readonly string[] }) {
  const { t } = useI18n();
  const m = t.members;
  const [form, setForm] = useState({ phone: "", full_name: "", role: "reviewer" });
  const action = useAction<typeof form>("POST", "admin/members", { invalidate: ["admin/members"], inlineErrors: true, success: m.added });
  const fe = action.error instanceof ApiError ? action.error.fieldErrors() : {};
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    try {
      await action.mutateAsync({ ...form, phone: form.phone.trim(), full_name: form.full_name.trim() });
      onClose();
    } catch {
      /* inline */
    }
  };
  return (
    <Dialog open onClose={onClose} title={m.invite}>
      <form onSubmit={submit} className="space-y-4">
        <Field label={t.common.phone} hint={t.auth.phoneHint} required error={fe.phone}>
          {(f) => <Input {...f} value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} type="tel" dir="ltr" required />}
        </Field>
        <Field label={m.fullName} error={fe.full_name}>
          {(f) => <Input {...f} value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} maxLength={120} />}
        </Field>
        <Field label={t.common.role} required error={fe.role}>
          {(f) => (
            <Select {...f} value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value })}>
              {roles
                .filter((r) => r !== "owner" || canOwner)
                .map((r) => (
                  <option key={r} value={r}>
                    {(t.roles as Record<string, string>)[r] ?? r}
                  </option>
                ))}
            </Select>
          )}
        </Field>
        {Object.keys(fe).length ? null : <InlineError error={action.error} />}
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
