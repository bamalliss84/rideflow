"use client";

import { useI18n } from "@/components/providers/I18nProvider";

export interface BarDatum {
  label: string;
  value: number;
  secondary?: number;
}

/**
 * Lightweight accessible bar chart (HTML/CSS). Bars are flex items, so the time axis follows the document
 * direction automatically (right-to-left in Arabic). Each bar exposes its value to assistive tech.
 */
export function BarChart({ data, height = 180, primaryLabel, secondaryLabel, format = (v) => String(v) }: {
  data: BarDatum[];
  height?: number;
  primaryLabel: string;
  secondaryLabel?: string;
  format?: (v: number) => string;
}) {
  const { t } = useI18n();
  const max = Math.max(1, ...data.map((d) => Math.max(d.value, d.secondary ?? 0)));
  if (!data.length) return <p className="py-10 text-center text-sm text-muted">{t.dashboard.noData}</p>;
  return (
    <figure>
      <div className="flex items-end gap-1.5 overflow-x-auto pb-1" style={{ height }} role="list" aria-label={primaryLabel}>
        {data.map((d) => (
          <div
            key={d.label}
            role="listitem"
            aria-label={`${d.label}: ${primaryLabel} ${format(d.value)}${secondaryLabel && d.secondary !== undefined ? `, ${secondaryLabel} ${format(d.secondary)}` : ""}`}
            className="group relative flex h-full min-w-6 flex-1 items-end justify-center gap-0.5"
          >
            <div className="w-full max-w-7 rounded-t bg-navy-200 transition-colors group-hover:bg-navy-300" style={{ height: `${(d.value / max) * 100}%` }} />
            {d.secondary !== undefined ? (
              <div className="w-full max-w-7 rounded-t bg-teal-600 transition-colors group-hover:bg-teal-700" style={{ height: `${(d.secondary / max) * 100}%` }} />
            ) : null}
            <div className="pointer-events-none absolute -top-9 z-10 hidden rounded bg-navy-900 px-2 py-1 text-[0.7rem] whitespace-nowrap text-white shadow group-hover:block">
              {d.label}: {format(d.value)}
              {d.secondary !== undefined ? ` / ${format(d.secondary)}` : ""}
            </div>
          </div>
        ))}
      </div>
      <div className="mt-1 flex gap-1.5 overflow-hidden text-[0.65rem] text-muted" aria-hidden>
        {data.map((d, i) => (
          <span key={d.label} className="min-w-6 flex-1 truncate text-center">
            {i % Math.ceil(data.length / 8) === 0 ? d.label : ""}
          </span>
        ))}
      </div>
      <figcaption className="mt-3 flex flex-wrap gap-4 text-xs text-muted">
        <span className="flex items-center gap-1.5">
          <span className="size-2.5 rounded-sm bg-navy-200" aria-hidden />
          {primaryLabel}
        </span>
        {secondaryLabel ? (
          <span className="flex items-center gap-1.5">
            <span className="size-2.5 rounded-sm bg-teal-600" aria-hidden />
            {secondaryLabel}
          </span>
        ) : null}
      </figcaption>
    </figure>
  );
}

/** Horizontal proportion bar for rates (0..1). */
export function RateBar({ label, value, tone = "teal" }: { label: string; value: number | null | undefined; tone?: "teal" | "amber" | "coral" }) {
  const pct = value === null || value === undefined ? null : Math.max(0, Math.min(1, value));
  const color = { teal: "bg-teal-600", amber: "bg-amber-500", coral: "bg-coral-500" }[tone];
  return (
    <div>
      <div className="mb-1 flex items-baseline justify-between gap-2 text-sm">
        <span className="text-muted">{label}</span>
        <span className="font-semibold text-ink ltr-nums">{pct === null ? "—" : `${(pct * 100).toFixed(1)}%`}</span>
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-navy-100" role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct === null ? undefined : Math.round(pct * 100)}>
        <div className={`h-full rounded-full ${color}`} style={{ width: `${(pct ?? 0) * 100}%` }} />
      </div>
    </div>
  );
}
