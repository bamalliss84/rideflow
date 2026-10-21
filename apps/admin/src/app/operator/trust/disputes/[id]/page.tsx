"use client";

import { Gavel, MessageSquare, Route } from "lucide-react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useState, type FormEvent } from "react";

import { EnumBadge, enumLabel, SafetyFlag } from "@/components/domain/Display";
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
      <div className="grid gap-6 xl:grid-cols-3">
        <div className="space-y-6 xl:col-span-2">
          <Card>
            <KeyValues
              columns={2}
              items={[
                { label: tr.openedBy, value: `${d.opened_by_name || "—"} · ${enumLabel(t, "actorRole", d.opened_by_role)}` },
                { label: tr.against, value: d.against_name ? `${d.against_name} · ${enumLabel(t, "actorRole", d.against_role)}` : "—" },
                { label: t.common.created, value: fmt.dateTime(d.created_at) },
                {
                  label: t.nav.rides,
                  value: can("rides.view") ? (
                    <Link href={`/operator/rides/${d.ride}`} className="inline-flex items-center gap-1 font-medium text-teal-700 hover:underline">
                      <Route className="size-4" aria-hidden />
                      {t.common.open}
                    </Link>
                  ) : (
                    "—"
                  ),
                },
              ]}
            />
            <h3 className="mt-5 mb-1.5 text-xs font-medium text-muted">{tr.description}</h3>
            <p className="rounded-md bg-surface px-3 py-2 text-sm leading-relaxed whitespace-pre-wrap">{d.description}</p>
            {!open ? (
              <>
                <h3 className="mt-5 mb-1.5 text-xs font-medium text-muted">{tr.resolution}</h3>
                <p className="text-sm">
                  {d.resolution_note} <span className="text-muted">· {d.resolved_by_name ?? "—"} · {fmt.dateTime(d.resolved_at)}</span>
                </p>
              </>
            ) : null}
          </Card>
        </div>
        <Card padded={false}>
          <CardHeader title={tr.notes} icon={<MessageSquare className="size-4" />} />
          <ol className="space-y-3 px-5 py-4">
            {d.notes.length ? (
              d.notes.map((n) => (
                <li key={n.id} className="rounded-md border border-line px-3 py-2">
                  <p className="text-xs text-muted">
                    {n.author_name || "—"} · {enumLabel(t, "actorRole", n.author_role)} · {fmt.dateTime(n.created_at)}
                  </p>
                  <p className="mt-1 text-sm whitespace-pre-wrap">{n.note}</p>
                </li>
              ))
            ) : (
              <li className="text-center text-sm text-muted">{t.common.emptyTitle}</li>
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
