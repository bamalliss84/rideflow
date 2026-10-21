"use client";

import { useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useMemo, type ReactNode } from "react";

import { createFormatters, type Formatters } from "@/lib/format";
import { dirFor, getDictionary, LOCALE_COOKIE, tpl, type Dictionary, type Locale } from "@/lib/i18n";

interface I18nValue {
  locale: Locale;
  dir: "rtl" | "ltr";
  t: Dictionary;
  tpl: typeof tpl;
  setLocale: (locale: Locale) => void;
}

const I18nContext = createContext<I18nValue | null>(null);

export function I18nProvider({ locale, children }: { locale: Locale; children: ReactNode }) {
  const router = useRouter();
  const setLocale = useCallback(
    (next: Locale) => {
      document.cookie = `${LOCALE_COOKIE}=${next}; path=/; max-age=31536000; samesite=strict`;
      document.documentElement.lang = next;
      document.documentElement.dir = dirFor(next);
      router.refresh();
    },
    [router],
  );
  const value = useMemo<I18nValue>(
    () => ({ locale, dir: dirFor(locale), t: getDictionary(locale), tpl, setLocale }),
    [locale, setLocale],
  );
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nValue {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n outside I18nProvider");
  return ctx;
}

/** Formatters bound to locale + (optional) operator time zone / currency. */
export function useFormat(ctx?: { timeZone?: string | null; currency?: string | null; minorUnits?: number | null }): Formatters {
  const { locale } = useI18n();
  return useMemo(
    () => createFormatters({ locale, timeZone: ctx?.timeZone, currency: ctx?.currency, minorUnits: ctx?.minorUnits }),
    [locale, ctx?.timeZone, ctx?.currency, ctx?.minorUnits],
  );
}
