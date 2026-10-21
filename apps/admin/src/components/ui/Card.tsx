import type { ReactNode } from "react";

export function Card({ children, className = "", padded = true }: { children: ReactNode; className?: string; padded?: boolean }) {
  return <section className={`rounded-lg border border-line bg-white shadow-card ${padded ? "p-5" : ""} ${className}`}>{children}</section>;
}

export function CardHeader({ title, subtitle, actions, icon }: { title: ReactNode; subtitle?: ReactNode; actions?: ReactNode; icon?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-start justify-between gap-3 border-b border-line px-5 py-3.5">
      <div className="flex min-w-0 items-start gap-2.5">
        {icon ? <span className="mt-0.5 text-navy-400">{icon}</span> : null}
        <div className="min-w-0">
          <h2 className="text-[0.95rem] font-semibold text-ink">{title}</h2>
          {subtitle ? <p className="mt-0.5 text-xs text-muted">{subtitle}</p> : null}
        </div>
      </div>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </div>
  );
}

export function KeyValues({ items, columns = 2 }: { items: { label: ReactNode; value: ReactNode; hidden?: boolean }[]; columns?: 1 | 2 | 3 }) {
  const grid = columns === 3 ? "sm:grid-cols-2 lg:grid-cols-3" : columns === 2 ? "sm:grid-cols-2" : "";
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

export function StatCard({ label, value, hint, tone = "default", icon }: {
  label: ReactNode;
  value: ReactNode;
  hint?: ReactNode;
  tone?: "default" | "accent" | "warning" | "danger";
  icon?: ReactNode;
}) {
  const accent = { default: "text-navy-400", accent: "text-teal-700", warning: "text-amber-700", danger: "text-coral-700" }[tone];
  return (
    <div className="rounded-lg border border-line bg-white px-4 py-3.5 shadow-card">
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs font-medium text-muted">{label}</p>
        {icon ? <span className={accent}>{icon}</span> : null}
      </div>
      <p className="mt-1.5 text-2xl font-semibold tracking-tight text-ink ltr-nums">{value}</p>
      {hint ? <p className="mt-0.5 text-xs text-muted">{hint}</p> : null}
    </div>
  );
}
