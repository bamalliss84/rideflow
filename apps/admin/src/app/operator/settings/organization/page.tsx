"use client";

import { Building2, CalendarDays, Clock, Coins, Hash, Languages, Lock, Ruler, type LucideIcon } from "lucide-react";
import type { ReactNode } from "react";

import { CopyText, EnumBadge } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

function Info({ icon: Icon, label, children, hint }: { icon: LucideIcon; label: string; children: ReactNode; hint?: ReactNode }) {
  return (
    <div className="flex min-w-0 items-start gap-3 rounded-xl border border-line bg-white p-4 shadow-card">
      <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-navy-50 text-navy-500">
        <Icon className="size-4" aria-hidden />
      </span>
      <div className="min-w-0">
        <p className="text-xs font-medium text-muted">{label}</p>
        <div className="mt-1 text-sm font-semibold break-words text-ink">{children}</div>
        {hint ? <p className="mt-0.5 text-xs text-muted">{hint}</p> : null}
      </div>
    </div>
  );
}

/** Read-only: these fields are controlled by the RideFlow platform team (no operator editing). */
export default function OrganizationPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const o = t.organization;
  const q = useApi<Schemas["Tenant"]>("admin/tenant");
  if (q.isPending) return <PageSkeleton />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />;
  const d = q.data;
  return (
    <>
      <PageHeader title={o.title} subtitle={o.subtitle} />
      <Card className="mb-5">
        <div className="flex flex-wrap items-center gap-4">
          <span className="flex size-12 items-center justify-center rounded-xl bg-navy-900 text-white">
            <Building2 className="size-6" aria-hidden />
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-xs text-muted">{o.name}</p>
            <h2 className="truncate text-lg font-semibold text-ink">
              <bdi>{d.name}</bdi>
            </h2>
          </div>
          <div className="flex flex-col items-end gap-1">
            <span className="text-xs text-muted">{t.common.status}</span>
            <EnumBadge group="tenantStatus" value={d.status} />
          </div>
        </div>
      </Card>
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Info icon={Hash} label={o.slug} hint={o.slugHint}>
          <CopyText value={d.slug} />
        </Info>
        <Info icon={Coins} label={o.currency}>
          <span className="ltr-nums">{d.currency}</span>
        </Info>
        <Info icon={Ruler} label={o.minorUnits} hint={o.minorUnitsHint}>
          <span className="ltr-nums">{fmt.number(d.currency_minor_units)}</span>
        </Info>
        <Info icon={Clock} label={o.timeZone}>
          <span className="ltr-nums">{d.time_zone}</span>
        </Info>
        <Info icon={Languages} label={o.locale}>
          {d.locale === "ar" ? "العربية" : "English"}
        </Info>
        <Info icon={CalendarDays} label={t.common.created}>
          <bdi>{fmt.dateTime(d.created_at)}</bdi>
        </Info>
      </div>
      <p className="mt-5 flex items-center gap-2 text-xs text-muted">
        <Lock className="size-3.5" aria-hidden />
        {o.managedNote}
      </p>
    </>
  );
}
