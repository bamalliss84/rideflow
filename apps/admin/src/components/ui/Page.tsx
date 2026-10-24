"use client";

import { ChevronLeft, Search } from "lucide-react";
import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";

import { useI18n } from "@/components/providers/I18nProvider";

export interface Crumb {
  label: string;
  href?: string;
}

export function PageHeader({ title, subtitle, crumbs, actions, meta }: {
  title: ReactNode;
  subtitle?: ReactNode;
  crumbs?: Crumb[];
  actions?: ReactNode;
  meta?: ReactNode;
}) {
  return (
    <header className="mb-5">
      {crumbs?.length ? (
        <nav aria-label="breadcrumb" className="mb-2">
          <ol className="flex flex-wrap items-center gap-1 text-xs text-muted">
            {crumbs.map((c, i) => (
              <li key={i} className="flex items-center gap-1">
                {c.href ? (
                  <Link href={c.href} className="hover:text-ink hover:underline">
                    {c.label}
                  </Link>
                ) : (
                  <span aria-current="page" className="text-ink">
                    {c.label}
                  </span>
                )}
                {i < crumbs.length - 1 ? <ChevronLeft className="size-3.5 ltr:rotate-180" aria-hidden /> : null}
              </li>
            ))}
          </ol>
        </nav>
      ) : null}
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2.5">
            <h1 className="text-xl font-semibold tracking-tight text-ink sm:text-2xl">{title}</h1>
            {meta}
          </div>
          {subtitle ? <p className="mt-1 max-w-3xl text-sm text-muted">{subtitle}</p> : null}
        </div>
        {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
      </div>
    </header>
  );
}

export function Tabs<V extends string>({ value, onChange, items, label }: {
  value: V;
  onChange: (v: V) => void;
  items: { value: V; label: string; count?: number | null }[];
  label: string;
}) {
  return (
    <div role="tablist" aria-label={label} className="scroll-thin flex gap-1 overflow-x-auto overflow-y-hidden border-b border-line px-3">
      {items.map((item) => {
        const active = item.value === value;
        return (
          <button
            key={item.value}
            role="tab"
            type="button"
            aria-selected={active}
            onClick={() => onChange(item.value)}
            className={`flex shrink-0 items-center gap-1.5 px-3 py-3 text-sm font-medium whitespace-nowrap transition-colors ${
              active ? "text-ink shadow-[inset_0_-2px_0_var(--color-teal-600)]" : "text-muted hover:text-ink"
            }`}
          >
            {item.label}
            {item.count !== undefined && item.count !== null ? (
              <span className={`rounded-full px-1.5 text-[0.7rem] ${active ? "bg-teal-50 text-teal-800" : "bg-navy-50 text-navy-600"}`}>{item.count}</span>
            ) : null}
          </button>
        );
      })}
    </div>
  );
}

/** Debounced search box (300 ms) — keeps typing smooth and requests few. */
export function SearchInput({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder?: string }) {
  const { t } = useI18n();
  const [text, setText] = useState(value);
  const [synced, setSynced] = useState(value);
  if (value !== synced) {
    // Parent changed the value (e.g. filters cleared): adopt it (derived-state pattern, no effect).
    setSynced(value);
    setText(value);
  }
  useEffect(() => {
    const id = setTimeout(() => {
      if (text !== value) onChange(text);
    }, 300);
    return () => clearTimeout(id);
  }, [text, value, onChange]);
  return (
    <div className="relative w-full sm:w-72">
      <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-subtle" aria-hidden />
      <input
        type="search"
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder={placeholder ?? t.common.search}
        aria-label={placeholder ?? t.common.search}
        className="h-9 w-full rounded-lg border border-line-strong bg-white ps-9 pe-3 text-sm placeholder:text-subtle focus:border-teal-600 focus:ring-2 focus:ring-teal-600/30 focus:outline-none"
      />
    </div>
  );
}

export function Toolbar({ children }: { children: ReactNode }) {
  return <div className="flex flex-wrap items-end gap-x-3 gap-y-2.5 border-b border-line px-4 py-3">{children}</div>;
}

export function FilterSelect<V extends string>({ value, onChange, options, label, allowAll = true }: {
  value: V | "";
  onChange: (v: V | "") => void;
  options: { value: V; label: string }[];
  label: string;
  allowAll?: boolean;
}) {
  const { t } = useI18n();
  return (
    <label className="flex min-w-36 flex-col gap-1 text-xs font-medium text-muted">
      <span className="whitespace-nowrap">{label}</span>
      <select
        value={value}
        aria-label={label}
        onChange={(e) => onChange(e.target.value as V | "")}
        className="h-9 rounded-lg border border-line-strong bg-white ps-2.5 pe-8 text-sm text-ink focus:border-teal-600 focus:ring-2 focus:ring-teal-600/30 focus:outline-none"
      >
        {allowAll ? <option value="">{t.common.all}</option> : null}
        {options.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </label>
  );
}

export type RangePreset = "1" | "7" | "30" | "90";

export function rangeFromPreset(preset: RangePreset): { date_from: string; date_to: string } {
  const to = new Date();
  const from = new Date(to.getTime() - Number(preset) * 86400_000);
  if (preset === "1") from.setHours(0, 0, 0, 0);
  return { date_from: from.toISOString(), date_to: to.toISOString() };
}

export function RangePicker({ value, onChange }: { value: RangePreset; onChange: (v: RangePreset) => void }) {
  const { t } = useI18n();
  const options: { value: RangePreset; label: string }[] = [
    { value: "1", label: t.common.today },
    { value: "7", label: t.common.last7 },
    { value: "30", label: t.common.last30 },
    { value: "90", label: t.common.last90 },
  ];
  return (
    <div role="radiogroup" aria-label={t.dashboard.period} className="scroll-thin inline-flex max-w-full overflow-x-auto rounded-lg border border-line-strong bg-white p-0.5">
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={value === o.value}
          onClick={() => onChange(o.value)}
          className={`h-8 shrink-0 rounded-md px-3 text-[0.8125rem] font-medium whitespace-nowrap transition-colors ${value === o.value ? "bg-navy-900 text-white" : "text-muted hover:text-ink"}`}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}
