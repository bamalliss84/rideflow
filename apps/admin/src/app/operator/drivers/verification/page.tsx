"use client";

import { CarFront, FileText, UserCheck } from "lucide-react";
import Link from "next/link";

import { EnumBadge, MetaLine, Person } from "@/components/domain/Display";
import { FilePreviewButton } from "@/components/domain/FilePreview";
import { ReviewActions } from "@/components/domain/ReviewActions";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { LinkButton } from "@/components/ui/Button";
import { Card, CardHeader } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { PageHeader } from "@/components/ui/Page";
import { EmptyState } from "@/components/ui/States";
import type { Page, Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

type Driver = Schemas["AdminDriver"];
type Doc = Schemas["DriverDocument"];
type Vehicle = Schemas["Vehicle"];

export default function VerificationQueuePage() {
  const { t } = useI18n();
  const { fmt, can } = useSession();
  const dr = t.drivers;
  const reviewer = can("drivers.review");
  const apps = useApi<Page<Driver>>("admin/drivers", { status: "under_review", ordering: "submitted_at", page_size: 50 });
  const docs = useApi<Page<Doc>>("admin/driver-documents", { status: "pending", submitted: "true", page_size: 100 });
  const vehicles = useApi<Page<Vehicle>>("admin/vehicles", { status: "pending", submitted: "true", page_size: 100 });
  const invalidate = ["admin/driver-documents", "admin/vehicles", "admin/drivers"];
  const today = new Date().toISOString().slice(0, 10);
  const nothing = <EmptyState title={dr.noPending} hint="" />;

  return (
    <>
      <PageHeader title={dr.queueTitle} subtitle={dr.queueSubtitle} crumbs={[{ label: t.nav.drivers, href: "/operator/drivers" }, { label: dr.queueTitle }]} />
      <div className="space-y-6">
        <Card padded={false}>
          <CardHeader title={`${dr.pendingApplications} (${apps.data?.count ?? "…"})`} icon={<UserCheck className="size-4" />} />
          <DataTable<Driver>
            rows={apps.data?.results}
            loading={apps.isPending}
            error={apps.error}
            rowKey={(r) => r.id}
            rowHref={(r) => `/operator/drivers/${r.id}`}
            empty={nothing}
            columns={[
              { key: "name", header: t.common.driver, cell: (r) => <Person name={r.full_name} phone={r.phone} /> },
              { key: "submitted", header: dr.submitted, cell: (r) => <MetaLine className="text-sm text-ink" parts={[<bdi key="d">{fmt.dateTime(r.submitted_at)}</bdi>, <span key="r" className="text-muted">{fmt.relative(r.submitted_at)}</span>]} /> },
              {
                key: "docs",
                header: dr.documents,
                hideBelow: "md",
                cell: (r) => {
                  const approved = r.documents.filter((d) => d.status === "approved").length;
                  return <span className="ltr-nums">{approved}/{r.documents.length}</span>;
                },
              },
              {
                key: "open",
                header: <span className="sr-only">{t.common.actions}</span>,
                align: "end",
                cell: (r) => (
                  <LinkButton href={`/operator/drivers/${r.id}`} size="sm">
                    {t.common.open}
                  </LinkButton>
                ),
              },
            ]}
          />
        </Card>

        <Card padded={false}>
          <CardHeader title={`${dr.pendingDocuments} (${docs.data?.count ?? "…"})`} icon={<FileText className="size-4" />} />
          <DataTable<Doc>
            rows={docs.data?.results}
            loading={docs.isPending}
            error={docs.error}
            rowKey={(r) => r.id}
            empty={nothing}
            columns={[
              {
                key: "driver",
                header: t.common.driver,
                cell: (r) => (
                  <Link href={`/operator/drivers/${r.driver}`} className="font-medium hover:underline">
                    {r.driver_name || "—"}
                  </Link>
                ),
              },
              { key: "type", header: t.common.type, cell: (r) => t.enums.docType[r.doc_type as keyof typeof t.enums.docType] ?? r.doc_type },
              { key: "number", header: dr.number, hideBelow: "lg", cell: (r) => <span className="ltr-nums">{r.number || "—"}</span> },
              {
                key: "expires",
                header: dr.expires,
                hideBelow: "md",
                cell: (r) => (r.expires_at ? <span className={r.expires_at < today ? "font-medium text-coral-700" : ""}>{fmt.day(r.expires_at)}</span> : "—"),
              },
              { key: "uploaded", header: t.common.created, hideBelow: "lg", cell: (r) => fmt.relative(r.created_at) },
              {
                key: "actions",
                header: <span className="sr-only">{t.common.actions}</span>,
                align: "end",
                cell: (r) => (
                  <span className="inline-flex flex-wrap justify-end gap-1.5">
                    <FilePreviewButton path={`admin/driver-documents/${r.id}/file`} contentType={r.content_type} title={`${r.driver_name ?? ""} · ${t.enums.docType[r.doc_type as keyof typeof t.enums.docType] ?? r.doc_type}`} />
                    {reviewer ? <ReviewActions base={`admin/driver-documents/${r.id}`} approveLabel={dr.approveDocument} rejectLabel={dr.rejectDocument} invalidate={invalidate} /> : null}
                  </span>
                ),
              },
            ]}
          />
        </Card>

        <Card padded={false}>
          <CardHeader title={`${dr.pendingVehicles} (${vehicles.data?.count ?? "…"})`} icon={<CarFront className="size-4" />} />
          <DataTable<Vehicle>
            rows={vehicles.data?.results}
            loading={vehicles.isPending}
            error={vehicles.error}
            rowKey={(r) => r.id}
            empty={nothing}
            columns={[
              { key: "driver", header: t.common.driver, cell: (r) => <span className="font-medium">{r.driver_name || "—"}</span> },
              { key: "vehicle", header: dr.vehicle, cell: (r) => <MetaLine className="text-sm text-ink" parts={[`${r.make} ${r.model}`, r.color]} /> },
              { key: "plate", header: dr.plate, cell: (r) => <span className="ltr-nums">{r.plate_number}</span> },
              { key: "status", header: t.common.status, hideBelow: "md", cell: (r) => <EnumBadge group="reviewStatus" value={r.status} /> },
              {
                key: "actions",
                header: <span className="sr-only">{t.common.actions}</span>,
                align: "end",
                cell: (r) => (reviewer ? <ReviewActions base={`admin/vehicles/${r.id}`} approveLabel={dr.approveVehicle} rejectLabel={dr.rejectVehicle} invalidate={invalidate} /> : null),
              },
            ]}
          />
        </Card>
      </div>
    </>
  );
}
