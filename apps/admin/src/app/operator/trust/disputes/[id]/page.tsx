"use client";

import { CalendarClock, FileText, Gavel, MessageSquare, Route, Scale, UserRound } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState, type FormEvent } from "react";

import { EnumBadge, enumLabel, MetaLine, PersonRole, SafetyFlag } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card, CardHeader, KeyValues } from "@/components/ui/Card";
import { Dialog } from "@/components/ui/Dialog";
import { Field, Select, Textarea } from "@/components/ui/Form";
import { PageHeader } from "@/components/ui/Page";
import { ErrorState, InlineError, PageSkeleton } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useAction, useApi } from "@/lib/api/hooks";

type Dispute = Schemas["Dispute"];
const KINDS = ["complaint_upheld", "price_non_compliance", "safety", "rider_late_cancellation", "driver_late_cancellation", "driver_no_arrival", "rider_no_show"] as const;

export default function DisputeDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { t } = useI18n();
  const { fmt, can } = useSession();
  const tr = t.trust;
  const base = `admin/disputes/${id}`;
  const q = useApi<Dispute>(base);
  const [note, setNote] = useState("");
  const [resolving, setResolving] = useState(false);
  const addNote = useAction<{ note: string }>("POST", `${base}/notes`, { invalidate: [base] });

  if (q.isPending) return <PageSkeleton />;
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />;
  const d = q.data;
  const open = d.status === "open" || d.status === "under_review";

  const submitNote = async (e: FormEvent) => {
    e.preventDefault();
    if (!note.trim()) return;
    try {
      await addNote.mutateAsync({ note: note.trim() });
      setNote("");
    } catch {
      /* toast already shown */
    }
  };

  return (
    <>
      <PageHeader
        title={enumLabel(t, "disputeCategory", d.category)}
        meta={
          <>
            <EnumBadge group="disputeStatus" value={d.status} />
            {d.is_safety ? <SafetyFlag /> : null}
          </>
        }
        crumbs={[{ label: t.nav.disputes, href: "/operator/trust/disputes" }, { label: fmt.dateTime(d.created_at) }]}
        actions={
          open && can("disputes.review") ? (
            <Button icon={<Gavel className="size-4" aria-hidden />} onClick={() => setResolving(true)}>
              {tr.resolve}
            </Button>
          ) : null
        }
      />
      <div className="grid gap-6 lg:grid-cols-3">
        <div className="min-w-0 space-y-6 lg:col-span-2">
          {!open ? (
            <Card padded={false}>
              <CardHeader title={tr.resolution} icon={<Scale className="size-4" />} actions={<EnumBadge group="disputeStatus" value={d.status} />} />
              <div className="space-y-4 p-5">
                <p className="rounded-lg border border-line bg-surface px-4 py-3 text-sm leading-relaxed break-words whitespace-pre-wrap">
                  <bdi>{d.resolution_note || "—"}</bdi>
                </p>
                <KeyValues
                  columns={2}
                  items={[
                    { label: tr.decidedBy, value: <bdi className="font-medium">{d.resolved_by_name || "—"}</bdi> },
                    { label: tr.decidedAt, value: <bdi>{fmt.dateTime(d.resolved_at)}</bdi> },
                  ]}
                />
              </div>
            </Card>
          ) : null}
          <Card padded={false}>
            <CardHeader title={tr.caseDetails} icon={<FileText className="size-4" />} />
            <div className="space-y-5 p-5">
              <KeyValues
                columns={3}
                items={[
                  { label: tr.openedBy, value: <PersonRole name={d.opened_by_name} role={d.opened_by_role} /> },
                  { label: tr.against, value: d.against_name || d.against_role ? <PersonRole name={d.against_name} role={d.against_role} /> : "—" },
                  { label: t.common.status, value: <EnumBadge group="disputeStatus" value={d.status} /> },
                  { label: t.common.created, value: <bdi>{fmt.dateTime(d.created_at)}</bdi> },
                  { label: tr.category, value: enumLabel(t, "disputeCategory", d.category) },
                  {
                    label: tr.relatedRide,
                    value: can("rides.view") ? (
                      <Link href={`/operator/rides/${d.ride}`} className="inline-flex items-center gap-1 font-medium text-teal-700 hover:underline">
                        <Route className="size-4" aria-hidden />
                        {tr.viewRide}
                      </Link>
                    ) : (
                      "—"
                    ),
                  },
                ]}
              />
              <div>
                <h3 className="mb-1.5 text-xs font-medium text-muted">{tr.description}</h3>
                <p className="rounded-lg bg-surface px-4 py-3 text-sm leading-relaxed break-words whitespace-pre-wrap">
                  <bdi>{d.description}</bdi>
                </p>
              </div>
            </div>
          </Card>
        </div>
        <Card padded={false} className="self-start">
          <CardHeader title={tr.notes} subtitle={d.notes.length ? String(d.notes.length) : undefined} icon={<MessageSquare className="size-4" />} />
          <ol className="space-y-3 px-5 py-4">
            {d.notes.length ? (
              d.notes.map((n) => (
                <li key={n.id} className="rounded-lg border border-line px-3 py-2.5">
                  <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
                    <span className="inline-flex min-w-0 items-center gap-1.5 text-xs">
                      <UserRound className="size-3.5 shrink-0 text-subtle" aria-hidden />
                      <MetaLine className="text-xs text-ink" parts={[<span key="n" className="font-medium">{n.author_name || "—"}</span>, <span key="r" className="text-muted">{enumLabel(t, "actorRole", n.author_role)}</span>]} />
                    </span>
                    <span className="inline-flex items-center gap-1 text-[0.7rem] text-muted">
                      <CalendarClock className="size-3.5" aria-hidden />
                      <bdi>{fmt.dateTime(n.created_at)}</bdi>
                    </span>
                  </div>
                  <p className="mt-1.5 text-sm leading-relaxed break-words whitespace-pre-wrap">
                    <bdi>{n.note}</bdi>
                  </p>
                </li>
              ))
            ) : (
              <li className="py-4 text-center text-sm text-muted">{tr.noNotes}</li>
            )}
          </ol>
          {open && can("disputes.review") ? (
            <form onSubmit={submitNote} className="space-y-2 border-t border-line px-5 py-4">
              <Field label={tr.addNote}>
                {(f) => <Textarea {...f} value={note} onChange={(e) => setNote(e.target.value)} placeholder={tr.notePlaceholder} maxLength={2000} rows={3} />}
              </Field>
              <div className="flex justify-end">
                <Button type="submit" size="sm" loading={addNote.isPending} disabled={!note.trim()}>
                  {tr.addNote}
                </Button>
              </div>
            </form>
          ) : null}
        </Card>
      </div>
      {resolving ? <ResolveDialog base={base} onClose={() => setResolving(false)} /> : null}
    </>
  );
}

function ResolveDialog({ base, onClose }: { base: string; onClose: () => void }) {
  const { t } = useI18n();
  const tr = t.trust;
  const [uphold, setUphold] = useState<boolean | null>(null);
  const [note, setNote] = useState("");
  const [kind, setKind] = useState("");
  const action = useAction<{ uphold: boolean; note: string; violation_kind?: string | null }>("POST", `${base}/resolve`, {
    invalidate: ["admin/disputes", "admin/violations", "admin/dashboard"],
    inlineErrors: true,
    success: tr.resolution,
  });
  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (uphold === null || !note.trim()) return;
    try {
      await action.mutateAsync({ uphold, note: note.trim(), violation_kind: uphold && kind ? kind : null });
      onClose();
    } catch {
      /* shown inline */
    }
  };
  return (
    <Dialog open onClose={onClose} title={tr.resolve}>
      <form onSubmit={submit} className="space-y-4">
        <div role="radiogroup" aria-label={tr.resolution} className="grid grid-cols-2 gap-2">
          {[
            { v: true, label: tr.uphold },
            { v: false, label: tr.rejectCase },
          ].map((o) => (
            <button
              key={String(o.v)}
              type="button"
              role="radio"
              aria-checked={uphold === o.v}
              onClick={() => setUphold(o.v)}
              className={`rounded-md border px-3 py-2.5 text-sm font-medium transition-colors ${uphold === o.v ? "border-navy-900 bg-navy-900 text-white" : "border-line-strong hover:bg-navy-50"}`}
            >
              {o.label}
            </button>
          ))}
        </div>
        {uphold ? (
          <Field label={tr.violationKind} hint={tr.violationKindHint}>
            {(f) => (
              <Select {...f} value={kind} onChange={(e) => setKind(e.target.value)}>
                <option value="">—</option>
                {KINDS.map((k) => (
                  <option key={k} value={k}>
                    {t.enums.violationKind[k]}
                  </option>
                ))}
              </Select>
            )}
          </Field>
        ) : null}
        <Field label={t.common.reason} required>
          {(f) => <Textarea {...f} value={note} onChange={(e) => setNote(e.target.value)} maxLength={1000} required />}
        </Field>
        <p className="text-xs text-muted">{t.common.irreversible}</p>
        <InlineError error={action.error} />
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose}>
            {t.common.cancel}
          </Button>
          <Button type="submit" loading={action.isPending} disabled={uphold === null || !note.trim()}>
            {t.common.confirm}
          </Button>
        </div>
      </form>
    </Dialog>
  );
}
