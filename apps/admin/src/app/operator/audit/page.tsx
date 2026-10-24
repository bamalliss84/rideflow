"use client";

import { AuditLog } from "@/components/domain/AuditLog";
import { useI18n } from "@/components/providers/I18nProvider";
import { PageHeader } from "@/components/ui/Page";
import { OPERATOR_AUDIT_DOMAINS } from "@/lib/audit";

export default function OperatorAuditPage() {
  const { t } = useI18n();
  return (
    <>
      <PageHeader title={t.audit.title} subtitle={t.audit.subtitle} />
      <AuditLog path="admin/audit-events" domains={OPERATOR_AUDIT_DOMAINS} />
    </>
  );
}
