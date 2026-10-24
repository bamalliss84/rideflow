import { humanize } from "@/components/domain/Display";

import type { Dictionary } from "./i18n";

/**
 * Presentation layer for immutable audit events. Records keep their machine codes (`ride.cancelled`); the UI
 * shows a localized name for every code the backend emits and a readable fallback for anything new.
 */
export function auditDomain(action: string) {
  return action.split(".")[0] ?? "";
}

export function auditActionLabel(t: Dictionary, action: string): string {
  const known = (t.audit.actions as Record<string, string>)[action];
  if (known) return known;
  const domain = (t.audit.domains as Record<string, string>)[auditDomain(action)];
  const rest = humanize(action.split(".").slice(1).join(" "));
  return domain ? `${domain}: ${rest}` : humanize(action);
}

export function auditTargetLabel(t: Dictionary, targetType: string | null | undefined): string {
  if (!targetType) return "—";
  return (t.audit.targets as Record<string, string>)[targetType] ?? humanize(targetType.replace(/([a-z])([A-Z])/g, "$1 $2"));
}

export function auditDataKeyLabel(t: Dictionary, key: string): string {
  return (t.audit.dataKeys as Record<string, string>)[key] ?? humanize(key);
}

/** Domain prefixes the operator audit log can be filtered by (backend `action` startswith filter). */
export const OPERATOR_AUDIT_DOMAINS = ["auth", "ride", "driver", "subscription", "trust", "tenant", "geo"] as const;
