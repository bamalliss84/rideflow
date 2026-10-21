"use client";

import { Check, Copy, ShieldAlert, Star } from "lucide-react";
import { useState, type ReactNode } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { Badge, type Tone } from "@/components/ui/Badge";
import type { Dictionary } from "@/lib/i18n";

type EnumGroup = keyof Dictionary["enums"];

const TONES: Record<string, Tone> = {
  // rides
  requested: "info",
  bidding: "info",
  match_pending: "warning",
  assigned: "accent",
  en_route: "accent",
  arrived: "accent",
  in_progress: "accent",
  completed: "success",
  cancelled: "neutral",
  no_show: "danger",
  disputed: "danger",
  // generic review / claims / people
  pending: "warning",
  pending_documents: "warning",
  under_review: "warning",
  submitted: "warning",
  first_approved: "info",
  approved: "success",
  rejected: "danger",
  suspended: "danger",
  active: "success",
  // trust
  pending_review: "warning",
  verified: "danger",
  dismissed: "neutral",
  overturned: "success",
  open: "warning",
  upheld: "success",
  proposed: "warning",
  revoked: "neutral",
  // bids
  withdrawn: "neutral",
  expired: "neutral",
  selected: "info",
  accepted: "success",
  declined: "neutral",
  lost: "neutral",
  // policy
  APPROVED: "success",
  PROPOSED: "warning",
  PROVISIONAL: "neutral",
};

/** Localized, colour-coded status/enumeration badge. Unknown values fall back to a readable label. */
export function EnumBadge({ group, value, tone }: { group: EnumGroup; value: string | null | undefined; tone?: Tone }) {
  const { t } = useI18n();
  if (!value) return <span className="text-subtle">—</span>;
  const labels = t.enums[group] as Record<string, string>;
  return <Badge tone={tone ?? TONES[value] ?? "neutral"}>{labels[value] ?? humanize(value)}</Badge>;
}

export function enumLabel(t: Dictionary, group: EnumGroup, value: string | null | undefined) {
  if (!value) return "—";
  return (t.enums[group] as Record<string, string>)[value] ?? humanize(value);
}

export function humanize(value: string) {
  return value.replace(/[._]/g, " ").replace(/^\w/, (c) => c.toUpperCase());
}

export function Person({ name, phone, sub }: { name?: string | null; phone?: string | null; sub?: ReactNode }) {
  return (
    <span className="flex min-w-0 flex-col">
      <span className="truncate font-medium text-ink">{name || phone || "—"}</span>
      {phone && name ? <span className="text-xs text-muted ltr-nums">{phone}</span> : null}
      {sub ? <span className="text-xs text-muted">{sub}</span> : null}
    </span>
  );
}

export function Phone({ value }: { value?: string | null }) {
  return value ? <span className="ltr-nums">{value}</span> : <span className="text-subtle">—</span>;
}

export function Stars({ value }: { value: number }) {
  return (
    <span className="inline-flex items-center gap-0.5" aria-label={`${value}/5`}>
      {[1, 2, 3, 4, 5].map((i) => (
        <Star key={i} className={`size-3.5 ${i <= value ? "fill-amber-400 text-amber-500" : "text-navy-200"}`} aria-hidden />
      ))}
    </span>
  );
}

export function SafetyFlag() {
  const { t } = useI18n();
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-coral-600 px-2 py-0.5 text-xs font-semibold text-white">
      <ShieldAlert className="size-3.5" aria-hidden />
      {t.trust.safety}
    </span>
  );
}

export function CopyText({ value, className = "" }: { value: string; className?: string }) {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);
  return (
    <span className={`inline-flex items-center gap-1.5 ${className}`}>
      <code className="rounded bg-navy-50 px-1.5 py-0.5 font-mono text-[0.8rem] text-navy-800 ltr-nums">{value}</code>
      <button
        type="button"
        className="rounded p-1 text-muted hover:bg-navy-50 hover:text-ink"
        aria-label={copied ? t.common.copied : t.common.copy}
        title={copied ? t.common.copied : t.common.copy}
        onClick={() => {
          void navigator.clipboard?.writeText(value).then(() => {
            setCopied(true);
            setTimeout(() => setCopied(false), 1500);
          });
        }}
      >
        {copied ? <Check className="size-3.5 text-teal-700" aria-hidden /> : <Copy className="size-3.5" aria-hidden />}
      </button>
    </span>
  );
}

/** Readable key/value rendering of evidence / audit JSON (no raw blobs for operators). */
export function JsonView({ value }: { value: unknown }) {
  if (value === null || value === undefined || (typeof value === "object" && Object.keys(value as object).length === 0)) {
    return <span className="text-subtle">—</span>;
  }
  if (typeof value !== "object") return <span className="ltr-nums">{String(value)}</span>;
  return (
    <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 rounded-md bg-surface px-3 py-2 text-xs">
      {Object.entries(value as Record<string, unknown>).map(([k, v]) => (
        <div key={k} className="contents">
          <dt className="font-medium text-muted">{humanize(k)}</dt>
          <dd className="break-all text-ink ltr-nums" dir="ltr">
            {typeof v === "object" && v !== null ? JSON.stringify(v) : String(v)}
          </dd>
        </div>
      ))}
    </dl>
  );
}
