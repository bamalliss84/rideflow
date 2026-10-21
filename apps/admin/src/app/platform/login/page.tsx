"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useState, type FormEvent } from "react";

import { AuthFrame } from "@/components/auth/AuthFrame";
import { MfaStep, type Challenge } from "@/components/auth/MfaStep";
import { useI18n } from "@/components/providers/I18nProvider";
import { Button } from "@/components/ui/Button";
import { Field, Input } from "@/components/ui/Form";
import { InlineError } from "@/components/ui/States";
import { authCall } from "@/lib/api/client";

function PlatformLogin() {
  const { t } = useI18n();
  const router = useRouter();
  const params = useSearchParams();
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [challenge, setChallenge] = useState<Challenge | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      setChallenge(await authCall<Challenge>("platform-login", { phone: phone.trim(), password }));
      setPassword("");
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };

  const notice = params.get("expired") ? t.errors.sessionExpired : params.get("signed_out") ? t.auth.signedOut : null;
  const next = params.get("next");

  return (
    <AuthFrame title={t.auth.platformTitle} subtitle={t.auth.platformSubtitle} notice={notice} switchHref="/login" switchLabel={t.auth.operatorLink}>
      {challenge ? (
        <MfaStep
          challenge={challenge}
          onRestart={() => setChallenge(null)}
          onDone={() => {
            router.replace(next && next.startsWith("/platform") && !next.startsWith("//") ? next : "/platform");
            router.refresh();
          }}
        />
      ) : (
        <form onSubmit={submit} className="space-y-4">
          <Field label={t.auth.phone} hint={t.auth.phoneHint} required>
            {(p) => <Input {...p} value={phone} onChange={(e) => setPhone(e.target.value)} type="tel" autoComplete="username" dir="ltr" required />}
          </Field>
          <Field label={t.auth.password} required>
            {(p) => <Input {...p} value={password} onChange={(e) => setPassword(e.target.value)} type="password" autoComplete="current-password" dir="ltr" required />}
          </Field>
          <InlineError error={error} />
          <Button type="submit" className="w-full" loading={busy} disabled={!phone.trim() || !password}>
            {t.auth.signIn}
          </Button>
        </form>
      )}
    </AuthFrame>
  );
}

export default function PlatformLoginPage() {
  return (
    <Suspense>
      <PlatformLogin />
    </Suspense>
  );
}
