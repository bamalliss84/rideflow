"use client";

import { Copy, Download, KeyRound, LifeBuoy, LogOut, ShieldCheck, UserRound } from "lucide-react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { useToast } from "@/components/providers/ToastProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader, KeyValues } from "@/components/ui/Card";
import { Field, Input } from "@/components/ui/Form";
import { PageHeader } from "@/components/ui/Page";
import { Dialog } from "@/components/ui/Dialog";
import { InlineError } from "@/components/ui/States";
import { api, authCall } from "@/lib/api/client";
import { downloadText } from "@/lib/format";

interface RecoveryStatus {
  remaining: number;
  total: number;
  generated_at: string | null;
}

/**
 * One-time MFA recovery codes. Managed only in a session verified with the authenticator; generating a new
 * set needs a fresh authenticator code and invalidates the previous set. Codes are shown once, never stored here.
 */
function RecoveryCodes() {
  const { t, tpl } = useI18n();
  const { me, fmt } = useSession();
  const a = t.account;
  const verified = Boolean(me.mfa.session_verified);
  const status = useQuery({
    queryKey: ["mfa-recovery-codes"],
    queryFn: () => authCall<RecoveryStatus>("recovery-codes", undefined, "GET"),
    enabled: verified,
  });
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [codes, setCodes] = useState<string[] | null>(null);

  const close = () => {
    setOpen(false);
    setCodes(null);
    setCode("");
    setError(null);
    void status.refetch();
  };
  const generate = async (e: FormEvent) => {
    e.preventDefault();
    if (busy || code.length !== 6) return;
    setBusy(true);
    setError(null);
    try {
      const res = await authCall<RecoveryStatus & { codes: string[] }>("recovery-codes", { code });
      setCodes(res.codes);
    } catch (err) {
      setError(err);
      setCode("");
    } finally {
      setBusy(false);
    }
  };
  const text = codes ? ["RideFlow — " + me.user.phone, ...codes, ""].join("\n") : "";
  const s = status.data;

  return (
    <div className="space-y-3 border-t border-line pt-4">
      <p className="flex items-center gap-2 font-medium text-ink">
        <LifeBuoy className="size-4 text-teal-700" aria-hidden />
        {a.recoveryTitle}
      </p>
      <p className="text-xs leading-relaxed text-muted">{a.recoveryIntro}</p>
      {!verified ? (
        <p className="rounded-md bg-surface px-3 py-2 text-xs text-muted">{a.recoveryNeedsVerified}</p>
      ) : (
        <>
          <p className={`text-sm ${s && s.total && s.remaining <= 3 ? "font-medium text-amber-800" : "text-ink"}`}>
            {s ? (s.total ? tpl(a.recoveryRemaining, { n: s.remaining, total: s.total }) : a.recoveryNone) : "…"}
            {s?.generated_at ? (
              <span className="ms-2 text-xs text-muted">
                (<bdi>{fmt.dateTime(s.generated_at)}</bdi>)
              </span>
            ) : null}
          </p>
          {s && s.total && s.remaining <= 3 ? <p className="text-xs text-amber-800">{a.recoveryLow}</p> : null}
          <Button variant="secondary" size="sm" onClick={() => setOpen(true)}>
            {s?.total ? a.recoveryRegenerate : a.recoveryGenerate}
          </Button>
        </>
      )}
      {open ? (
        <Dialog open onClose={close} title={a.recoveryTitle}>
          {codes ? (
            <div className="space-y-4">
              <p className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs leading-relaxed text-amber-900">{a.recoveryWarning}</p>
              <ol dir="ltr" className="grid grid-cols-2 gap-2 rounded-lg border border-line bg-surface p-3 font-mono text-sm">
                {codes.map((c) => (
                  <li key={c} className="text-center">
                    {c}
                  </li>
                ))}
              </ol>
              <div className="flex flex-wrap justify-end gap-2">
                <Button variant="secondary" size="sm" icon={<Copy className="size-4" aria-hidden />} onClick={() => void navigator.clipboard?.writeText(text)}>
                  {a.recoveryCopy}
                </Button>
                <Button variant="secondary" size="sm" icon={<Download className="size-4" aria-hidden />} onClick={() => downloadText("rideflow-recovery-codes.txt", text, "text/plain;charset=utf-8")}>
                  {a.recoveryDownload}
                </Button>
                <Button size="sm" onClick={close}>
                  {a.recoveryDone}
                </Button>
              </div>
            </div>
          ) : (
            <form onSubmit={generate} className="space-y-4">
              <p className="text-sm text-muted">{s?.total ? a.recoveryReplaceNote : a.recoveryIntro}</p>
              <Field label={t.auth.mfaCode} hint={a.recoveryConfirmCode} required>
                {(p) => (
                  <Input
                    {...p}
                    value={code}
                    onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                    inputMode="numeric"
                    autoComplete="one-time-code"
                    autoFocus
                    dir="ltr"
                    className="text-center tracking-[0.4em]"
                  />
                )}
              </Field>
              <InlineError error={error} />
              <div className="flex justify-end gap-2">
                <Button variant="secondary" onClick={close}>
                  {t.common.cancel}
                </Button>
                <Button type="submit" loading={busy} disabled={code.length !== 6}>
                  {s?.total ? a.recoveryRegenerate : a.recoveryGenerate}
                </Button>
              </div>
            </form>
          )}
        </Dialog>
      ) : null}
    </div>
  );
}

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
            {me.mfa.enrolled ? <RecoveryCodes /> : null}
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
