/**
 * RideFlow mark: a rounded tile with a flowing route between a pickup ring and a drop-off dot.
 * Original artwork drawn in code (no third-party brand assets).
 */
export function LogoMark({ className = "size-8", inverted = false }: { className?: string; inverted?: boolean }) {
  const tile = inverted ? "#ffffff" : "#10243A";
  const route = "#14A394";
  const node = inverted ? "#10243A" : "#ffffff";
  return (
    <svg viewBox="0 0 40 40" className={className} aria-hidden="true" focusable="false">
      <rect width="40" height="40" rx="11" fill={tile} />
      <path d="M11 28c0-6 4.5-7.5 9-8s9-2 9-8" fill="none" stroke={route} strokeWidth="3.4" strokeLinecap="round" />
      <circle cx="11" cy="28" r="3.6" fill={tile} stroke={node} strokeWidth="2.4" />
      <circle cx="29" cy="12" r="3.4" fill={node} />
    </svg>
  );
}

export function Wordmark({ inverted = false, subtitle }: { inverted?: boolean; subtitle?: string }) {
  return (
    <span className="flex items-center gap-2.5" dir="ltr">
      <LogoMark inverted={inverted} />
      <span className="flex flex-col leading-none">
        <span className={`text-[1.05rem] font-bold tracking-tight ${inverted ? "text-white" : "text-navy-900"}`}>
          Ride<span className={inverted ? "text-teal-300" : "text-teal-700"}>Flow</span>
        </span>
        {subtitle ? <span className={`mt-1 text-[0.68rem] font-medium ${inverted ? "text-navy-200" : "text-muted"}`}>{subtitle}</span> : null}
      </span>
    </span>
  );
}
