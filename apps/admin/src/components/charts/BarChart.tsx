"use client";

import { useI18n } from "@/components/providers/I18nProvider";

/** One colour per ride status everywhere (dashboard, reports, exports legend). */
export const STATUS_SERIES = {
  requested: { color: "bg-navy-300", hover: "group-hover:bg-navy-400" },
  matched: { color: "bg-navy-600", hover: "group-hover:bg-navy-700" },
  completed: { color: "bg-teal-600", hover: "group-hover:bg-teal-700" },
  cancelled: { color: "bg-amber-500", hover: "group-hover:bg-amber-600" },
  no_show: { color: "bg-coral-500", hover: "group-hover:bg-coral-600" },
  neutral: { color: "bg-navy-500", hover: "group-hover:bg-navy-600" },
} as const;

export interface ChartSeries {
  key: string;
  label: string;
  tone: keyof typeof STATUS_SERIES;
}
export interface ChartDatum {
  label: string;
  values: Record<string, number>;
}

/** Four equal, whole-number intervals (step 1/2/5 × 10^n) so a single small value never fills the whole plot. */
function niceStep(peak: number) {
  const raw = Math.max(1, peak / 4);
  const magnitude = 10 ** Math.floor(Math.log10(raw));
  return ([1, 2, 5, 10].find((s) => s * magnitude >= raw) ?? 10) * magnitude;
}

/**
 * Accessible grouped bar chart (HTML/CSS, no chart library). The time axis always runs left → right, as in
 * the approved reference design, while legends and captions follow the page direction. The y axis uses a
 * fixed, rounded scale with gridlines so sparse data reads as low volume rather than as a tall spike.
 */
export function BarChart({ data, series, height = 200, format = (v) => String(v), emptyLabel }: {
  data: ChartDatum[];
  series: ChartSeries[];
  height?: number;
  format?: (v: number) => string;
  emptyLabel?: string;
}) {
  const { t } = useI18n();
  const peak = Math.max(0, ...data.flatMap((d) => series.map((s) => d.values[s.key] ?? 0)));
  if (!data.length || peak === 0) {
    return <p className="flex items-center justify-center rounded-lg border border-dashed border-line-strong py-12 text-sm text-muted" style={{ minHeight: height / 1.5 }}>{emptyLabel ?? t.dashboard.noData}</p>;
  }
  const step = niceStep(peak);
  const max = step * 4;
  const ticks = [4, 3, 2, 1, 0].map((i) => i * step);
  const labelEvery = Math.max(1, Math.ceil(data.length / 10));
  const groupMin = series.length > 1 ? 18 : 12;
  return (
    <figure className="min-w-0">
      <div dir="ltr" className="flex gap-2">
        <div className="flex shrink-0 flex-col justify-between text-end text-[0.65rem] text-subtle ltr-nums" style={{ height }} aria-hidden>
          {ticks.map((v) => (
            <span key={v} className="-my-1.5 leading-3">{format(v)}</span>
          ))}
        </div>
        <div className="scroll-thin min-w-0 flex-1 overflow-x-auto pb-1">
          <div style={{ minWidth: data.length * groupMin }}>
            <div className="relative" style={{ height }}>
              <div className="pointer-events-none absolute inset-0 flex flex-col justify-between" aria-hidden>
                {ticks.map((v) => (
                  <div key={v} className={`border-t ${v === 0 ? "border-line-strong" : "border-dashed border-line-strong/70"}`} />
                ))}
              </div>
              <div className="relative flex h-full items-end" role="list" aria-label={series.map((s) => s.label).join(", ")}>
                {data.map((d) => (
                  <div
                    key={d.label}
                    role="listitem"
                    aria-label={`${d.label}: ${series.map((s) => `${s.label} ${format(d.values[s.key] ?? 0)}`).join(", ")}`}
                    className="group relative flex h-full flex-1 items-end justify-center gap-px px-[2px]"
                  >
                    {series.map((s) => {
                      const v = d.values[s.key] ?? 0;
                      return (
                        <div
                          key={s.key}
                          className={`w-full max-w-4 rounded-t-sm transition-colors ${STATUS_SERIES[s.tone].color} ${STATUS_SERIES[s.tone].hover}`}
                          style={{ height: v ? `max(2px, ${(v / max) * 100}%)` : 0 }}
                        />
                      );
                    })}
                    <div className="pointer-events-none absolute bottom-full z-10 mb-1 hidden rounded-md bg-navy-900 px-2 py-1.5 text-[0.7rem] whitespace-nowrap text-white shadow-pop group-hover:block">
                      <p className="mb-0.5 font-semibold">{d.label}</p>
                      {series.map((s) => (
                        <p key={s.key} className="flex items-center gap-1.5">
                          <span className={`size-2 rounded-sm ${STATUS_SERIES[s.tone].color}`} aria-hidden />
                          <bdi>{s.label}</bdi>
                          <span className="ms-auto ps-2 font-semibold ltr-nums">{format(d.values[s.key] ?? 0)}</span>
                        </p>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
            <div className="mt-1.5 flex text-[0.65rem] text-muted" aria-hidden>
              {data.map((d, i) => (
                <span key={d.label} className="flex-1 overflow-visible text-center whitespace-nowrap">
                  {i % labelEvery === 0 ? d.label : ""}
                </span>
              ))}
            </div>
          </div>
        </div>
      </div>
      <figcaption className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
        {series.map((s) => (
          <span key={s.key} className="flex items-center gap-1.5">
            <span className={`size-2.5 rounded-sm ${STATUS_SERIES[s.tone].color}`} aria-hidden />
            {s.label}
          </span>
        ))}
      </figcaption>
    </figure>
  );
}

/**
 * The daily report lists only days that had rides. Expand it to every calendar day of the requested range
 * (in the operator's time zone) so the axis is honest: a day without rows had zero rides.
 */
export function fillDays<R extends { day: string }>(rows: R[], from: string, to: string, timeZone: string, empty: (day: string) => R): R[] {
  let key: (d: Date) => string;
  try {
    const f = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" });
    key = (d) => f.format(d);
  } catch {
    key = (d) => d.toISOString().slice(0, 10);
  }
  const byDay = new Map(rows.map((r) => [r.day, r]));
  const start = key(new Date(from));
  const end = key(new Date(new Date(to).getTime() - 1));
  const out: R[] = [];
  const cursor = new Date(`${start}T00:00:00Z`);
  for (let i = 0; i < 400; i++) {
    const day = cursor.toISOString().slice(0, 10);
    if (day > end) break;
    out.push(byDay.get(day) ?? empty(day));
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  return out;
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
