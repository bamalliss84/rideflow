"use client";

import { KeyRound, LogOut, ShieldCheck, UserRound } from "lucide-react";
import { useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { useToast } from "@/components/providers/ToastProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader, KeyValues } from "@/components/ui/Card";
import { Field, Input } from "@/components/ui/Form";
import { PageHeader } from "@/components/ui/Page";
import { InlineError } from "@/components/ui/States";
import { api } from "@/lib/api/client";

export function AccountPanel() {
  const { t } = useI18n();
  const { me, signOut, scope } = useSession();
  const notify = useToast();
  const queryClient = useQueryClient();
  const [name, setName] = useState(me.user.full_name ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const a = t.account;

  const save = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api("me", { method: "PATCH", body: { full_name: name.trim() } });
      await queryClient.invalidateQueries({ queryKey: ["session"] });
      notify(a.saved);
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };

  const roles = scope === "platform" ? [t.roles.platform] : (me.tenant?.roles ?? []).map((r) => (t.roles as Record<string, string>)[r] ?? r);

  return (
    <>
      <PageHeader title={a.title} subtitle={a.subtitle} />
      <div className="grid max-w-5xl gap-6 lg:grid-cols-2">
        <Card padded={false}>
          <CardHeader title={a.profile} icon={<UserRound className="size-4" />} />
          <form onSubmit={save} className="space-y-4 p-5">
            <Field label={a.fullName}>{(f) => <Input {...f} value={name} onChange={(e) => setName(e.target.value)} maxLength={120} />}</Field>
            <KeyValues
              items={[
                { label: t.common.phone, value: <span className="ltr-nums">{me.user.phone}</span> },
                { label: t.common.role, value: roles.join("، ") },
                { label: t.nav.organization, value: me.tenant?.tenant_name ?? "RideFlow", hidden: scope === "platform" },
              ]}
            />
            <InlineError error={error} />
            <div className="flex justify-end">
              <Button type="submit" loading={busy} disabled={name.trim() === (me.user.full_name ?? "")}>
                {t.common.save}
              </Button>
            </div>
          </form>
        </Card>
        <Card padded={false}>
          <CardHeader title={a.security} icon={<ShieldCheck className="size-4" />} />
          <div className="space-y-4 p-5 text-sm">
            <p className="flex items-center gap-2">
              <KeyRound className="size-4 text-teal-700" aria-hidden />
              {me.mfa.enrolled ? a.mfaEnabled : t.members.mfaOff}
            </p>
            {me.mfa.session_verified ? <Badge tone="success">{a.mfaSession}</Badge> : null}
            <p className="text-muted">{a.lostDevice}</p>
            <Button variant="outline-danger" icon={<LogOut className="size-4" aria-hidden />} onClick={() => void signOut()}>
              {t.common.signOut}
            </Button>
          </div>
        </Card>
        {scope === "tenant" ? (
          <Card className="lg:col-span-2">
            <h2 className="mb-3 text-sm font-semibold">{a.permissions}</h2>
            <div className="flex flex-wrap gap-1.5">
              {me.permissions.map((p) => (
                <Badge key={p} tone="info" dot={false}>
                  <span className="ltr-nums">{p}</span>
                </Badge>
              ))}
            </div>
          </Card>
        ) : null}
      </div>
    </>
  );
}
