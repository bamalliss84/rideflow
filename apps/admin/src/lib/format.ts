import type { Locale } from "./i18n";

/** Arabic UI with Latin digits: dense operational tables stay unambiguous for phone numbers and amounts. */
export function intlLocale(locale: Locale) {
  return locale === "ar" ? "ar-u-nu-latn" : "en-GB";
}

export interface FormatContext {
  locale: Locale;
  timeZone?: string | null;
  currency?: string | null;
  minorUnits?: number | null;
}

export function createFormatters(ctx: FormatContext) {
  const tag = intlLocale(ctx.locale);
  const timeZone = ctx.timeZone || undefined;
  const safe = <T>(fn: () => T, fallback: T): T => {
    try {
      return fn();
    } catch {
      return fallback;
    }
  };
  const dateTimeFmt = safe(
    () => new Intl.DateTimeFormat(tag, { dateStyle: "medium", timeStyle: "short", timeZone }),
    new Intl.DateTimeFormat(tag, { dateStyle: "medium", timeStyle: "short" }),
  );
  const dateFmt = safe(() => new Intl.DateTimeFormat(tag, { dateStyle: "medium", timeZone }), new Intl.DateTimeFormat(tag));
  const timeFmt = safe(() => new Intl.DateTimeFormat(tag, { timeStyle: "medium", timeZone }), new Intl.DateTimeFormat(tag));
  const numberFmt = new Intl.NumberFormat(tag);
  const percentFmt = new Intl.NumberFormat(tag, { style: "percent", maximumFractionDigits: 1 });
  const relFmt = new Intl.RelativeTimeFormat(tag, { numeric: "auto" });

  const parse = (value: string | Date | null | undefined) => (value ? new Date(value) : null);

  return {
    dateTime: (v: string | Date | null | undefined) => {
      const d = parse(v);
      return d ? dateTimeFmt.format(d) : "—";
    },
    date: (v: string | Date | null | undefined) => {
      const d = parse(v);
      return d ? dateFmt.format(d) : "—";
    },
    time: (v: string | Date | null | undefined) => {
      const d = parse(v);
      return d ? timeFmt.format(d) : "—";
    },
    /** Calendar day strings (YYYY-MM-DD) are not shifted by time zone. */
    day: (v: string | null | undefined) => {
      if (!v) return "—";
      const [y, m, d] = v.split("-").map(Number);
      return new Intl.DateTimeFormat(tag, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(Date.UTC(y ?? 0, (m ?? 1) - 1, d ?? 1)));
    },
    /** Compact calendar-day label for chart axes, e.g. "22/10" — not shifted by time zone. */
    shortDay: (v: string | null | undefined) => {
      if (!v) return "—";
      // Plain "DD/MM" (Latin digits, no bidi marks) so axis labels never reorder inside the LTR chart.
      const [, m, d] = v.split("-");
      return `${d}/${m}`;
    },
    relative: (v: string | Date | null | undefined) => {
      const d = parse(v);
      if (!d) return "—";
      const seconds = Math.round((d.getTime() - Date.now()) / 1000);
      const abs = Math.abs(seconds);
      if (abs < 60) return relFmt.format(seconds, "second");
      if (abs < 3600) return relFmt.format(Math.round(seconds / 60), "minute");
      if (abs < 86400) return relFmt.format(Math.round(seconds / 3600), "hour");
      return relFmt.format(Math.round(seconds / 86400), "day");
    },
    number: (v: number | null | undefined) => (v === null || v === undefined ? "—" : numberFmt.format(v)),
    percent: (v: number | null | undefined) => (v === null || v === undefined ? "—" : percentFmt.format(v)),
    /** Integer minor units → localized currency string (no floating point storage anywhere). */
    money: (minor: number | null | undefined, currency?: string | null) => {
      if (minor === null || minor === undefined) return "—";
      const cur = currency || ctx.currency || "";
      const units = ctx.minorUnits ?? 2;
      const value = minor / 10 ** units;
      if (!cur) return numberFmt.format(value);
      return safe(
        () => new Intl.NumberFormat(tag, { style: "currency", currency: cur, minimumFractionDigits: 0, maximumFractionDigits: units }).format(value),
        `${numberFmt.format(value)} ${cur}`,
      );
    },
    /** Plain decimal amount for CSV exports (no grouping, no symbol): spreadsheet-friendly and exact. */
    amount: (minor: number | null | undefined) => {
      if (minor === null || minor === undefined) return "";
      const units = ctx.minorUnits ?? 2;
      return (minor / 10 ** units).toFixed(units);
    },
    duration: (seconds: number | null | undefined) => {
      if (seconds === null || seconds === undefined) return "—";
      const unit = (value: number, u: "second" | "minute" | "hour") =>
        new Intl.NumberFormat(tag, { style: "unit", unit: u, unitDisplay: "short", maximumFractionDigits: 1 }).format(value);
      if (seconds < 60) return unit(Math.round(seconds), "second");
      if (seconds < 3600) return unit(Math.round((seconds / 60) * 10) / 10, "minute");
      return unit(Math.round((seconds / 3600) * 10) / 10, "hour");
    },
    distance: (meters: number | null | undefined) => {
      if (meters === null || meters === undefined) return "—";
      const fmtUnit = (value: number, u: "meter" | "kilometer") =>
        new Intl.NumberFormat(tag, { style: "unit", unit: u, unitDisplay: "short", maximumFractionDigits: 1 }).format(value);
      return meters >= 1000 ? fmtUnit(meters / 1000, "kilometer") : fmtUnit(Math.round(meters), "meter");
    },
  };
}

export type Formatters = ReturnType<typeof createFormatters>;

export function toCsv(rows: Record<string, unknown>[], columns: { key: string; label: string }[]): string {
  const esc = (v: unknown) => {
    const s = v === null || v === undefined ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [columns.map((c) => esc(c.label)).join(","), ...rows.map((r) => columns.map((c) => esc(r[c.key])).join(","))].join("\n");
}

export function downloadText(filename: string, text: string, type = "text/csv;charset=utf-8") {
  const blob = new Blob(["﻿", text], { type });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
