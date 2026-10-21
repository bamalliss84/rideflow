import ar from "./ar";
import en, { type Dictionary } from "./en";

export type Locale = "ar" | "en";
export const LOCALES: Locale[] = ["ar", "en"];
export const LOCALE_COOKIE = "rf_locale";
export const DEFAULT_LOCALE: Locale = "ar";

export function resolveLocale(value: string | undefined | null): Locale {
  return value === "en" || value === "ar" ? value : DEFAULT_LOCALE;
}

export function dirFor(locale: Locale): "rtl" | "ltr" {
  return locale === "ar" ? "rtl" : "ltr";
}

export function getDictionary(locale: Locale): Dictionary {
  return locale === "en" ? en : ar;
}

/** "{count} results" + {count: 3} → "3 results" */
export function tpl(text: string, vars: Record<string, string | number>): string {
  return text.replace(/\{(\w+)\}/g, (_, key: string) => String(vars[key] ?? `{${key}}`));
}

export type { Dictionary };
