"use client";

import { Ban, CarFront, CheckCircle2, FileText, RotateCcw, Wallet, XCircle } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState, type ReactNode } from "react";

import { EnumBadge, MetaLine, Phone } from "@/components/domain/Display";
import { FilePreviewButton } from "@/components/domain/FilePreview";
import { ReviewActions } from "@/components/domain/ReviewActions";
import { SubscriptionState } from "@/components/domain/SubscriptionState";
import { TrustSummary } from "@/components/domain/TrustSummary";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader, KeyValues } from "@/components/ui/Card";
import { DataTable } from "@/components/ui/DataTable";
import { ConfirmDialog } from "@/components/ui/Dialog";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, PageSkeleton } from "@/components/ui/States";
import type { Page, Schemas } from "@/lib/api/client";
import { useAction, useApi } from "@/lib/api/hooks";

type Driver = Schemas["AdminDriver"];
type Doc = Schemas["DriverDocument"];
type Vehicle = Schemas["Vehicle"];
type Sub = Schemas["DriverSubscription"];
type Ride = Schemas["AdminRide"];
type Decision = "approve" | "reject" | "suspend" | "reinstate";

const DECISIONS: Record<string, Decision[]> = {
  under_review: ["approve", "reject"],
  rejected: ["approve"],
  approved: ["suspend"],
  suspended: ["reinstate"],
  pending_documents: [],
};

export default function DriverDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { t } = useI18n();
  const { fmt, can } = useSession();
  const dr = t.drivers;
  const base = `admin/drivers/${id}`;
  const q = useApi<Driver>(base);
  const subs = useApi<Page<Sub>>(can("subscriptions.view") ? "admin/subscriptions" : null, { driver: id, page_size: 5 });
  const rides = useApi<Page<Ride>>(can("rides.view") ? "admin/rides" : null, { driver: id, page_size: 5 });
  const [decision, setDecision] = useState<Decision | null>(null);
  const decide = useAction<{ decision: Decision; note: string }>("POST", `${base}/decide`, {
    invalidate: ["admin/drivers", "admin/dashboard"],
    inlineErrors: true,
  });

  if (q.isPending) return <PageSkeleton />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />;
  const d = q.data;
  const reviewer = can("drivers.review");
  const today = new Date().toISOString().slice(0, 10);
  const meta: Record<Decision, { label: string; confirm: string; tone: "accent" | "danger"; icon: ReactNode }> = {
    approve: { label: dr.approveDriver, confirm: dr.approveConfirm, tone: "accent", icon: <CheckCircle2 className="size-4" aria-hidden /> },
    reject: { label: dr.rejectDriver, confirm: dr.rejectConfirm, tone: "danger", icon: <XCircle className="size-4" aria-hidden /> },
    suspend: { label: dr.suspendDriver, confirm: dr.suspendConfirm, tone: "danger", icon: <Ban className="size-4" aria-hidden /> },
    reinstate: { label: dr.reinstateDriver, confirm: dr.reinstateConfirm, tone: "accent", icon: <RotateCcw className="size-4" aria-hidden /> },
  };
  const invalidate = [base, "admin/driver-documents", "admin/vehicles"];
  // Draft uploads are not reviewable until the driver submits the application (backend: application_not_submitted).
  const submitted = d.status === "under_review" || d.status === "approved" || d.status === "suspended";

  return (
    <>
      <PageHeader
        title={d.full_name || d.phone}
        meta={
          <>
            <EnumBadge group="driverStatus" value={d.status} />
            <Badge tone={d.is_online ? "success" : "neutral"}>{d.is_online ? t.common.online : t.common.offline}</Badge>
          </>
        }
        crumbs={[{ label: t.nav.drivers, href: "/operator/drivers" }, { label: d.full_name || d.phone }]}
        actions={
          reviewer
            ? (DECISIONS[d.status] ?? []).map((k) => (
                <Button key={k} variant={meta[k].tone === "danger" ? "outline-danger" : "accent"} icon={meta[k].icon} onClick={() => setDecision(k)}>
                  {meta[k].label}
                </Button>
              ))
            : null
        }
      />
      <div className="grid gap-6 xl:grid-cols-3">
        <div className="space-y-6 xl:col-span-2">
          <Card>
            <h2 className="mb-4 text-sm font-semibold">{dr.profile}</h2>
            <KeyValues
              columns={3}
              items={[
                { label: t.common.phone, value: <Phone value={d.phone} /> },
                { label: dr.submitted, value: fmt.dateTime(d.submitted_at) },
                { label: dr.reviewed, value: fmt.dateTime(d.reviewed_at) },
                { label: t.common.created, value: fmt.dateTime(d.created_at) },
                { label: dr.availability, value: d.online_since ? <MetaLine className="text-sm text-ink" parts={[t.common.online, fmt.relative(d.online_since)]} /> : t.common.offline },
                { label: dr.reviewNote, value: d.review_note || "—" },
              ]}
            />
          </Card>

          <Card padded={false}>
            <CardHeader title={dr.documents} icon={<FileText className="size-4" />} />
            <DataTable<Doc>
              rows={d.documents}
              rowKey={(r) => r.id}
              columns={[
                { key: "type", header: t.common.type, cell: (r) => <span className="font-medium">{t.enums.docType[r.doc_type as keyof typeof t.enums.docType] ?? r.doc_type}</span> },
                { key: "number", header: dr.number, hideBelow: "md", cell: (r) => <span className="ltr-nums">{r.number || "—"}</span> },
                {
                  key: "expires",
                  header: dr.expires,
                  cell: (r) =>
                    r.expires_at ? (
                      <MetaLine
                        className={`text-sm ${r.expires_at < today ? "font-medium text-coral-700" : ""}`}
                        parts={[<bdi key="d">{fmt.day(r.expires_at)}</bdi>, r.expires_at < today ? dr.expired : null]}
                      />
                    ) : (
                      "—"
                    ),
                },
                { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="reviewStatus" value={r.status} /> },
                {
                  key: "actions",
                  header: <span className="sr-only">{t.common.actions}</span>,
                  align: "end",
                  cell: (r) => (
                    <span className="inline-flex flex-wrap justify-end gap-1.5">
                      <FilePreviewButton path={`admin/driver-documents/${r.id}/file`} contentType={r.content_type} title={t.enums.docType[r.doc_type as keyof typeof t.enums.docType] ?? r.doc_type} />
                      {reviewer && submitted && r.status === "pending" ? (
                        <ReviewActions base={`admin/driver-documents/${r.id}`} approveLabel={dr.approveDocument} rejectLabel={dr.rejectDocument} invalidate={invalidate} />
                      ) : null}
                    </span>
                  ),
                },
              ]}
            />
          </Card>

          <Card padded={false}>
            <CardHeader title={dr.vehicles} icon={<CarFront className="size-4" />} />
            <DataTable<Vehicle>
              rows={d.vehicles}
              rowKey={(r) => r.id}
              columns={[
                { key: "vehicle", header: dr.vehicle, cell: (r) => <MetaLine className="text-sm font-medium text-ink" parts={[`${r.make} ${r.model}`, r.color]} /> },
                { key: "plate", header: dr.plate, cell: (r) => <span className="ltr-nums">{r.plate_number}</span> },
                { key: "year", header: dr.year, hideBelow: "md", cell: (r) => <span className="ltr-nums">{r.year ?? "—"}</span> },
                { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="reviewStatus" value={r.status} /> },
                {
                  key: "actions",
                  header: <span className="sr-only">{t.common.actions}</span>,
                  align: "end",
                  cell: (r) =>
                    reviewer && submitted && r.status === "pending" ? (
                      <ReviewActions base={`admin/vehicles/${r.id}`} approveLabel={dr.approveVehicle} rejectLabel={dr.rejectVehicle} invalidate={invalidate} />
                    ) : null,
                },
              ]}
            />
          </Card>

          {can("rides.view") ? (
            <Card padded={false}>
              <CardHeader title={dr.recentRides} actions={<Link className="text-sm font-medium text-teal-700 hover:underline" href={`/operator/rides?driver=${d.id}`}>{t.common.viewAll}</Link>} />
              <DataTable<Ride>
                rows={rides.data?.results}
                loading={rides.isPending}
                error={rides.error}
                rowKey={(r) => r.id}
                rowHref={(r) => `/operator/rides/${r.id}`}
                columns={[
                  { key: "created", header: t.common.date, cell: (r) => fmt.dateTime(r.created_at) },
                  { key: "rider", header: t.common.rider, cell: (r) => r.rider_name || r.rider_phone },
                  { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="rideStatus" value={r.status} /> },
                  { key: "fare", header: t.rides.fare, align: "end", cell: (r) => <bdi>{fmt.money(r.agreed_fare_minor, r.currency)}</bdi> },
                ]}
              />
            </Card>
          ) : null}
        </div>

        <div className="space-y-6">
          {can("reports.view") ? <TrustSummary userId={d.user_id} role="driver" /> : null}
          {can("subscriptions.view") ? (
            <Card padded={false}>
              <CardHeader title={dr.subscriptions} icon={<Wallet className="size-4" />} />
              <ul className="divide-y divide-line">
                {subs.data?.results.length ? (
                  subs.data.results.map((s) => (
                    <li key={s.id} className="flex items-center justify-between gap-3 px-5 py-3 text-sm">
                      <span className="flex flex-col">
                        <span className="font-medium">{s.plan_name ?? t.enums.subscriptionSource[s.source as keyof typeof t.enums.subscriptionSource] ?? s.source}</span>
                        <span className="text-xs text-muted">
                          {fmt.date(s.starts_at)} → {fmt.date(s.ends_at)}
                        </span>
                      </span>
                      <SubscriptionState sub={s} />
                    </li>
                  ))
                ) : (
                  <li className="px-5 py-6 text-center text-sm text-muted">{subs.isPending ? t.common.loading : t.common.emptyTitle}</li>
                )}
              </ul>
            </Card>
          ) : null}
        </div>
      </div>

      <ConfirmDialog
        open={decision !== null}
        onClose={() => setDecision(null)}
        title={decision ? meta[decision].label : ""}
        message={decision ? meta[decision].confirm : ""}
        confirmLabel={decision ? meta[decision].label : ""}
        tone={decision ? meta[decision].tone : "primary"}
        note={
          decision === "reject" || decision === "suspend"
            ? { label: t.common.reason, required: true }
            : { label: `${t.common.note} (${t.common.optional})` }
        }
        onConfirm={(note) => decide.mutateAsync({ decision: decision!, note })}
      />
    </>
  );
}
