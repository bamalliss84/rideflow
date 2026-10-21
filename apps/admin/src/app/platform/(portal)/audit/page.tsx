"use client";

import { AuditLog } from "@/components/domain/AuditLog";
import { useI18n } from "@/components/providers/I18nProvider";
import { PageHeader } from "@/components/ui/Page";

export default function PlatformAuditPage() {
  const { t } = useI18n();
  return (
    <>
      <PageHeader title={t.platform.auditTitle} subtitle={t.platform.auditSubtitle} />
      <AuditLog path="platform/audit-events" />
    </>
  );
}
