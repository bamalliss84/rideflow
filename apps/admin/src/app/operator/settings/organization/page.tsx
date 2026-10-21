"use client";

import { Building2 } from "lucide-react";

import { EnumBadge } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card, CardHeader, KeyValues } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

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
      <Card padded={false} className="max-w-3xl">
        <CardHeader title={d.name} icon={<Building2 className="size-4" />} actions={<EnumBadge group="tenantStatus" value={d.status} />} />
        <div className="p-5">
          <KeyValues
            items={[
              { label: o.slug, value: <span className="ltr-nums">{d.slug}</span> },
              { label: o.currency, value: <span className="ltr-nums">{d.currency}</span> },
              { label: o.minorUnits, value: <span className="ltr-nums">{d.currency_minor_units}</span> },
              { label: o.timeZone, value: <span className="ltr-nums">{d.time_zone}</span> },
              { label: o.locale, value: d.locale === "ar" ? "العربية" : "English" },
              { label: t.common.created, value: fmt.dateTime(d.created_at) },
            ]}
          />
          <p className="mt-5 text-xs text-muted">{o.managedNote}</p>
        </div>
      </Card>
    </>
  );
}
