"use client";

import { Building2 } from "lucide-react";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";

import { AuthFrame } from "@/components/auth/AuthFrame";
import { MfaStep, type Challenge } from "@/components/auth/MfaStep";
import { useI18n } from "@/components/providers/I18nProvider";
import { Button } from "@/components/ui/Button";
import { Field, Input } from "@/components/ui/Form";
import { InlineError } from "@/components/ui/States";
import { ApiError, authCall } from "@/lib/api/client";

type Step = "phone" | "code" | "mfa";

function safeNext(value: string | null, fallback: string) {
  return value && value.startsWith("/operator") && !value.startsWith("//") ? value : fallback;
}

export function OperatorLogin({ initialWorkspace }: { initialWorkspace: string }) {
  const { t, tpl } = useI18n();
  const router = useRouter();
  const params = useSearchParams();
  const [step, setStep] = useState<Step>("phone");
  const [workspace, setWorkspace] = useState(initialWorkspace);
  const [resolved, setResolved] = useState<{ workspace: string; name: string | null }>({ workspace: "", name: null });
  const tenantName = resolved.workspace === workspace.trim() ? resolved.name : null;
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [challenge, setChallenge] = useState<Challenge | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    const ws = workspace.trim();
    if (ws.length < 3) return;
    const id = setTimeout(() => {
      authCall<{ tenant_name: string }>("context", undefined, "GET", { workspace: ws })
        .then((r) => setResolved({ workspace: ws, name: r.tenant_name }))
        .catch(() => setResolved({ workspace: ws, name: null }));
    }, 350);
    return () => clearTimeout(id);
  }, [workspace]);

  const run = async (fn: () => Promise<void>) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };

  const requestCode = (e?: FormEvent) => {
    e?.preventDefault();
    void run(async () => {
      await authCall("otp-request", { workspace: workspace.trim(), phone: phone.trim() });
      setCode("");
      setStep("code");
    });
  };

  const verifyCode = (e: FormEvent) => {
    e.preventDefault();
    void run(async () => {
      const res = await authCall<Challenge | { dev_mfa_bypass: true }>("otp-verify", { workspace: workspace.trim(), phone: phone.trim(), code });
      if ("dev_mfa_bypass" in res) {
        // Session already established by the BFF because the backend authorized a local-dev session.
        router.replace(safeNext(params.get("next"), "/operator"));
        router.refresh();
        return;
      }
      setChallenge(res);
      setStep("mfa");
    });
  };

  const restart = () => {
    setChallenge(null);
    setCode("");
    setError(null);
    setStep("phone");
  };

  const notice = params.get("expired") ? t.errors.sessionExpired : params.get("signed_out") ? t.auth.signedOut : null;
  const phoneError = error instanceof ApiError ? error.fieldErrors().phone : undefined;

  return (
    <AuthFrame title={t.auth.operatorTitle} subtitle={t.auth.operatorSubtitle} notice={notice} switchHref="/platform/login" switchLabel={t.auth.platformLink}>
      {step === "phone" ? (
        <form onSubmit={requestCode} className="space-y-4" noValidate>
          <Field label={t.auth.workspace} hint={tenantName ? undefined : t.auth.workspaceHint} required>
            {(p) => (
              <Input {...p} value={workspace} onChange={(e) => setWorkspace(e.target.value)} autoComplete="organization" dir="ltr" spellCheck={false} required />
            )}
          </Field>
          {tenantName ? (
            <p className="-mt-2 flex items-center gap-2 text-sm font-medium text-teal-800">
              <Building2 className="size-4" aria-hidden />
              {tpl(t.auth.workspaceFound, { name: tenantName })}
            </p>
          ) : null}
          <Field label={t.auth.phone} hint={t.auth.phoneHint} error={phoneError} required>
            {(p) => (
              <Input {...p} value={phone} onChange={(e) => setPhone(e.target.value)} type="tel" inputMode="tel" autoComplete="tel" dir="ltr" placeholder="+967…" required />
            )}
          </Field>
          {!phoneError ? <InlineError error={error} /> : null}
          <Button type="submit" className="w-full" loading={busy} disabled={!workspace.trim() || !phone.trim()}>
            {t.auth.sendCode}
          </Button>
        </form>
      ) : null}

      {step === "code" ? (
        <form onSubmit={verifyCode} className="space-y-4">
          <p className="text-sm text-muted">{tpl(t.auth.codeSent, { phone })}</p>
          <Field label={t.auth.code} required>
            {(p) => (
              <Input
                {...p}
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 8))}
                inputMode="numeric"
                autoComplete="one-time-code"
                autoFocus
                dir="ltr"
                className="text-center text-lg tracking-[0.4em]"
              />
            )}
          </Field>
          <InlineError error={error} />
          <Button type="submit" className="w-full" loading={busy} disabled={code.length < 4}>
            {t.auth.continue}
          </Button>
          <div className="flex justify-between text-sm">
            <button type="button" className="font-medium text-teal-700 hover:underline" onClick={restart}>
              {t.auth.changeNumber}
            </button>
            <button type="button" className="font-medium text-teal-700 hover:underline disabled:opacity-50" disabled={busy} onClick={() => requestCode()}>
              {t.auth.resend}
            </button>
          </div>
        </form>
      ) : null}

      {step === "mfa" && challenge ? (
        <MfaStep
          challenge={challenge}
          onRestart={restart}
          onDone={() => {
            router.replace(safeNext(params.get("next"), "/operator"));
            router.refresh();
          }}
        />
      ) : null}
    </AuthFrame>
  );
}
