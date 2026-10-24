"use client";

import { KeyRound, QrCode } from "lucide-react";
import QRCode from "qrcode";
import { useEffect, useState, type FormEvent } from "react";

import { CopyText } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { Button } from "@/components/ui/Button";
import { Field, Input } from "@/components/ui/Form";
import { InlineError } from "@/components/ui/States";
import { authCall } from "@/lib/api/client";

export interface Challenge {
  mfa_token: string;
  mfa_enrolled: boolean;
}

interface Setup {
  secret: string;
  otpauth_uri: string;
}

/** Second factor: verify with an enrolled authenticator, or enrol one (QR + manual key) and verify. */
export function MfaStep({ challenge, onDone, onRestart }: { challenge: Challenge; onDone: (scope: string) => void; onRestart: () => void }) {
  const { t } = useI18n();
  const [setup, setSetup] = useState<Setup | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [code, setCode] = useState("");
  // Lost-device path: a one-time recovery code replaces the authenticator code (first factor already passed).
  const [recovery, setRecovery] = useState(false);
  const [recoveryCode, setRecoveryCode] = useState("");
  const recoveryValid = /^[0-9a-f]{5}-?[0-9a-f]{5}$/i.test(recoveryCode.trim());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    if (setup) QRCode.toDataURL(setup.otpauth_uri, { margin: 1, width: 200, color: { dark: "#10243A", light: "#ffffff" } }).then(setQr, () => setQr(null));
  }, [setup]);

  const startSetup = async () => {
    setBusy(true);
    setError(null);
    try {
      setSetup(await authCall<Setup>("mfa-setup", { mfa_token: challenge.mfa_token }));
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };

  const verify = async (e: FormEvent) => {
    e.preventDefault();
    if (busy || (recovery ? !recoveryValid : code.length !== 6)) return;
    setBusy(true);
    setError(null);
    try {
      const factor = recovery ? { recovery_code: recoveryCode.trim() } : { code };
      const res = await authCall<{ scope: string }>("mfa-verify", { mfa_token: challenge.mfa_token, ...factor });
      onDone(res.scope);
    } catch (err) {
      setError(err);
      setCode("");
      setRecoveryCode("");
      setBusy(false);
    }
  };

  const needsEnrolment = !challenge.mfa_enrolled;

  return (
    <div className="space-y-5">
      <div className="flex items-start gap-3 rounded-lg border border-teal-100 bg-teal-50/60 px-4 py-3">
        <KeyRound className="mt-0.5 size-5 shrink-0 text-teal-700" aria-hidden />
        <div>
          <p className="text-sm font-semibold text-ink">{needsEnrolment ? t.auth.enrollTitle : t.auth.mfaTitle}</p>
          <p className="mt-0.5 text-xs leading-relaxed text-muted">{needsEnrolment ? t.auth.enrollIntro : t.auth.mfaPrompt}</p>
        </div>
      </div>

      {needsEnrolment && !setup ? (
        <Button className="w-full" variant="accent" onClick={startSetup} loading={busy} icon={<QrCode className="size-4" aria-hidden />}>
          {t.auth.enrollStart}
        </Button>
      ) : null}

      {setup ? (
        <ol className="space-y-4 text-sm">
          <li>
            <p className="mb-2 text-muted">1. {t.auth.enrollStep1}</p>
            <div className="flex justify-center rounded-lg border border-line bg-white p-3">
              {qr ? (
                // eslint-disable-next-line @next/next/no-img-element -- locally generated data URL
                <img src={qr} alt="QR" width={200} height={200} />
              ) : (
                <div className="size-[200px] animate-pulse rounded bg-navy-50" />
              )}
            </div>
          </li>
          <li>
            <p className="mb-1.5 text-muted">2. {t.auth.enrollStep2}</p>
            <CopyText value={setup.secret.replace(/(.{4})/g, "$1 ").trim()} />
          </li>
          <li className="text-muted">3. {t.auth.enrollStep3}</li>
        </ol>
      ) : null}

      {!needsEnrolment || setup ? (
        <form onSubmit={verify} className="space-y-4">
          {recovery ? (
            <Field label={t.auth.recoveryCode} hint={t.auth.recoveryHint} required>
              {(p) => (
                <Input
                  {...p}
                  value={recoveryCode}
                  onChange={(e) => setRecoveryCode(e.target.value.slice(0, 12))}
                  autoComplete="off"
                  autoFocus
                  spellCheck={false}
                  dir="ltr"
                  className="text-center font-mono text-lg tracking-widest"
                  placeholder="xxxxx-xxxxx"
                />
              )}
            </Field>
          ) : (
          <Field label={t.auth.mfaCode} required>
            {(p) => (
              <Input
                {...p}
                value={code}
                onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                inputMode="numeric"
                autoComplete="one-time-code"
                autoFocus
                dir="ltr"
                className="text-center text-lg tracking-[0.5em]"
                placeholder="••••••"
              />
            )}
          </Field>
          )}
          <InlineError error={error} />
          <Button type="submit" className="w-full" loading={busy} disabled={recovery ? !recoveryValid : code.length !== 6}>
            {t.auth.verify}
          </Button>
          {!needsEnrolment ? (
            <button
              type="button"
              className="w-full text-center text-xs font-medium text-teal-700 hover:underline"
              onClick={() => {
                setRecovery((v) => !v);
                setError(null);
              }}
            >
              {recovery ? t.auth.useAuthenticator : t.auth.useRecovery}
            </button>
          ) : null}
        </form>
      ) : (
        <InlineError error={error} />
      )}
      {!needsEnrolment ? <p className="rounded-md bg-surface px-3 py-2 text-xs leading-relaxed text-muted">{t.auth.lostAuthenticator}</p> : null}
      <p className="text-center text-xs text-muted">
        {t.auth.expiresIn}{" "}
        <button type="button" onClick={onRestart} className="font-medium text-teal-700 hover:underline">
          {t.auth.changeNumber}
        </button>
      </p>
    </div>
  );
}
