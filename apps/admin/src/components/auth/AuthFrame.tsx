"use client";

import { Info, ShieldCheck } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";

import { LogoMark, Wordmark } from "@/components/brand/Logo";
import { useI18n } from "@/components/providers/I18nProvider";
import { LanguageSwitch } from "@/components/shell/AppShell";

export function AuthFrame({ title, subtitle, children, notice, switchHref, switchLabel }: {
  title: string;
  subtitle: string;
  children: ReactNode;
  notice?: string | null;
  switchHref: string;
  switchLabel: string;
}) {
  const { t } = useI18n();
  return (
    <div className="grid min-h-dvh lg:grid-cols-[1fr_minmax(0,560px)]">
      <aside className="relative hidden overflow-hidden bg-navy-900 lg:block" aria-hidden>
        <svg className="absolute inset-0 h-full w-full opacity-[0.16]" viewBox="0 0 600 800" preserveAspectRatio="xMidYMid slice">
          <path d="M-20 640 C 140 560, 160 420, 300 400 S 520 260, 640 120" fill="none" stroke="#2fb5a7" strokeWidth="2" />
          <path d="M-40 720 C 160 640, 220 520, 340 480 S 560 380, 660 230" fill="none" stroke="#9cb0c8" strokeWidth="1.2" strokeDasharray="6 10" />
          <path d="M-60 520 C 100 470, 180 320, 300 300 S 500 160, 640 40" fill="none" stroke="#9cb0c8" strokeWidth="1" />
          <circle cx="300" cy="400" r="7" fill="#2fb5a7" />
          <circle cx="340" cy="480" r="5" fill="#fff" />
        </svg>
        <div className="relative flex h-full flex-col justify-between p-12">
          <Wordmark inverted />
          <div className="max-w-md">
            <LogoMark inverted className="mb-6 size-12" />
            <p className="text-3xl leading-snug font-semibold text-white">{t.meta.tagline}</p>
            <p className="mt-4 text-sm leading-relaxed text-navy-200">{t.auth.secureNote}</p>
          </div>
          <p className="flex items-center gap-2 text-xs text-navy-300">
            <ShieldCheck className="size-4 text-teal-300" />
            {t.auth.mfaTitle}
          </p>
        </div>
      </aside>
      <main className="flex flex-col bg-white">
        <div className="flex items-center justify-between px-6 py-4">
          <span className="lg:invisible">
            <Wordmark />
          </span>
          <LanguageSwitch />
        </div>
        <div className="flex flex-1 items-center justify-center px-6 pb-12">
          <div className="w-full max-w-sm">
            <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
            <p className="mt-1.5 text-sm text-muted">{subtitle}</p>
            {notice ? (
              <p role="status" className="mt-5 flex items-start gap-2 rounded-md border border-navy-100 bg-navy-50 px-3 py-2 text-sm text-navy-800">
                <Info className="mt-0.5 size-4 shrink-0" aria-hidden />
                {notice}
              </p>
            ) : null}
            <div className="mt-6">{children}</div>
            <p className="mt-8 text-center text-xs text-muted">
              <Link href={switchHref} className="font-medium text-teal-700 hover:underline">
                {switchLabel}
              </Link>
            </p>
          </div>
        </div>
      </main>
    </div>
  );
}
