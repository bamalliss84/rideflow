import type { ReactNode } from "react";

/** `min-w-0` lets a card shrink inside grid/flex parents, so wide tables scroll inside it instead of widening the page. */
export function Card({ children, className = "", padded = true }: { children: ReactNode; className?: string; padded?: boolean }) {
  return <section className={`min-w-0 rounded-xl border border-line bg-white shadow-card ${padded ? "p-5" : ""} ${className}`}>{children}</section>;
}

export function CardHeader({ title, subtitle, actions, icon }: { title: ReactNode; subtitle?: ReactNode; actions?: ReactNode; icon?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 border-b border-line px-5 py-3.5">
      <div className="flex min-w-0 items-center gap-2.5">
        {icon ? <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-teal-50 text-teal-700">{icon}</span> : null}
        <div className="min-w-0">
          <h2 className="text-[0.95rem] font-semibold text-ink">{title}</h2>
          {subtitle ? <p className="mt-0.5 text-xs text-muted">{subtitle}</p> : null}
        </div>
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}

export function KeyValues({ items, columns = 2 }: { items: { label: ReactNode; value: ReactNode; hidden?: boolean }[]; columns?: 1 | 2 | 3 | 4 }) {
  const grid = { 1: "", 2: "sm:grid-cols-2", 3: "sm:grid-cols-2 lg:grid-cols-3", 4: "sm:grid-cols-2 xl:grid-cols-4" }[columns];
  return (
    <dl className={`grid gap-x-6 gap-y-4 ${grid}`}>
      {items
        .filter((i) => !i.hidden)
        .map((item, idx) => (
          <div key={idx} className="min-w-0">
            <dt className="text-xs font-medium text-muted">{item.label}</dt>
            <dd className="mt-1 text-sm break-words text-ink">{item.value}</dd>
          </div>
        ))}
    </dl>
  );
}

const TILE = {
  default: "bg-navy-50 text-navy-500",
  accent: "bg-teal-50 text-teal-700",
  warning: "bg-amber-50 text-amber-700",
  danger: "bg-coral-50 text-coral-600",
};

/** KPI tile (reference design: tinted icon square, large figure, short caption). */
export function StatCard({ label, value, hint, tone = "default", icon }: {
  label: ReactNode;
  value: ReactNode;
  hint?: ReactNode;
  tone?: "default" | "accent" | "warning" | "danger";
  icon?: ReactNode;
}) {
  return (
    <div className="flex min-w-0 items-start gap-3 rounded-xl border border-line bg-white p-3.5 shadow-card sm:p-4">
      <div className="min-w-0 flex-1">
        <p className="truncate text-xs font-medium text-muted">{label}</p>
        <p className="mt-1.5 truncate text-xl font-semibold tracking-tight text-ink sm:text-2xl">
          <bdi>{value}</bdi>
        </p>
        {hint ? <p className="mt-0.5 text-xs text-muted">{hint}</p> : null}
      </div>
      {icon ? <span className={`hidden size-10 shrink-0 items-center justify-center rounded-lg min-[400px]:flex ${TILE[tone]}`}>{icon}</span> : null}
    </div>
  );
}

/** A labelled section inside a card (used by long settings forms). */
export function SectionTitle({ children, hint }: { children: ReactNode; hint?: ReactNode }) {
  return (
    <div className="mb-3">
      <h3 className="text-sm font-semibold text-ink">{children}</h3>
      {hint ? <p className="mt-0.5 text-xs text-muted">{hint}</p> : null}
    </div>
  );
}
