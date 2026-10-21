import type { ReactNode } from "react";

export type Tone = "neutral" | "success" | "warning" | "danger" | "info" | "accent";

const tones: Record<Tone, string> = {
  neutral: "bg-navy-50 text-navy-700 ring-navy-200/70",
  success: "bg-teal-50 text-teal-800 ring-teal-200",
  warning: "bg-amber-50 text-amber-800 ring-amber-200",
  danger: "bg-coral-50 text-coral-700 ring-coral-200",
  info: "bg-navy-100/60 text-navy-800 ring-navy-200",
  accent: "bg-navy-900 text-white ring-navy-900",
};
const dots: Record<Tone, string> = {
  neutral: "bg-navy-400",
  success: "bg-teal-600",
  warning: "bg-amber-500",
  danger: "bg-coral-500",
  info: "bg-navy-600",
  accent: "bg-teal-300",
};

export function Badge({ tone = "neutral", children, dot = true }: { tone?: Tone; children: ReactNode; dot?: boolean }) {
  return (
    <span className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap ring-1 ring-inset ${tones[tone]}`}>
      {dot ? <span className={`size-1.5 rounded-full ${dots[tone]}`} aria-hidden /> : null}
      {children}
    </span>
  );
}
