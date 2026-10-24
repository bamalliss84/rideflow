"use client";

import { useInfiniteQuery, useQueryClient } from "@tanstack/react-query";
import { AlertTriangle, Bell, CheckCheck, ChevronLeft, FileWarning, Gavel, MessageSquareWarning, Receipt, UserCheck, type LucideIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { humanize, MetaLine } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { useToast } from "@/components/providers/ToastProvider";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { PageHeader, Tabs } from "@/components/ui/Page";
import { EmptyState, ErrorState, InlineError, Skeleton } from "@/components/ui/States";
import { api, type Schemas } from "@/lib/api/client";

type PageT = Schemas["NotificationPage"];
type Item = Schemas["NotificationItem"];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const id = (v: unknown) => (typeof v === "string" && UUID.test(v) ? v : null);

/**
 * Internal operator routes only, built from validated ids. Every target page re-reads the record through the
 * tenant-scoped API, so a notification can never reveal or reach another tenant's data.
 */
function linkFor(item: Item, can: (p: string) => boolean): string | null {
  const p = item.payload as Record<string, unknown>;
  if (item.kind === "staff.driver_submitted" && id(p.driver_id) && can("drivers.view")) return `/operator/drivers/${id(p.driver_id)}`;
  if (item.kind === "staff.deposit_submitted" && id(p.claim_id) && can("subscriptions.view")) return `/operator/subscriptions/deposits/${id(p.claim_id)}`;
  if (item.kind === "staff.dispute_opened" && id(p.dispute_id) && can("disputes.review")) return `/operator/trust/disputes/${id(p.dispute_id)}`;
  if (item.kind === "staff.appeal_filed" && can("violations.review")) return "/operator/trust/appeals";
  if (item.kind === "staff.incident_recorded" && can("violations.review")) return "/operator/trust/violations";
  if (id(p.ride_id) && can("rides.view")) return `/operator/rides/${id(p.ride_id)}`;
  return null;
}

const KIND_ICON: Record<string, { icon: LucideIcon; tone: string }> = {
  "staff.driver_submitted": { icon: UserCheck, tone: "bg-teal-50 text-teal-700" },
  "staff.deposit_submitted": { icon: Receipt, tone: "bg-navy-50 text-navy-600" },
  "staff.dispute_opened": { icon: MessageSquareWarning, tone: "bg-amber-50 text-amber-700" },
  "staff.appeal_filed": { icon: Gavel, tone: "bg-amber-50 text-amber-700" },
  "staff.incident_recorded": { icon: AlertTriangle, tone: "bg-coral-50 text-coral-600" },
};

/** Newest-first view over the cursor-ordered notification feed. */
export default function NotificationsPage() {
  const { t, tpl } = useI18n();
  const { fmt, can } = useSession();
  const notify = useToast();
  const router = useRouter();
  const client = useQueryClient();
  const n = t.notifications;
  const [view, setView] = useState<"all" | "unread">("all");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const q = useInfiniteQuery({
    queryKey: ["notifications-feed"],
    initialPageParam: 0,
    queryFn: async ({ pageParam }) => api<PageT>("notifications", { query: { after: pageParam, limit: 200 } }),
    getNextPageParam: (last) => (last.has_more ? last.next_cursor : undefined),
  });
  // The API pages forward (oldest first). Read through to the newest items (bounded) so the list starts at the latest.
  const pages = q.data?.pages.length ?? 0;
  useEffect(() => {
    if (q.hasNextPage && !q.isFetchingNextPage && pages < 10) void q.fetchNextPage();
  }, [q, pages]);
  const all = (q.data?.pages.flatMap((p) => p.items) ?? []).slice().reverse();
  const unread = all.filter((i) => !i.read);
  const items = view === "unread" ? unread : all;
  const latest = all[0]?.cursor ?? 0;

  const markRead = async (body: { up_to: number } | { cursor: number }) => {
    setError(null);
    await api("notifications/read", { method: "POST", body });
    await client.invalidateQueries({ queryKey: ["notifications-feed"] });
  };
  const markAll = async () => {
    setBusy(true);
    try {
      await markRead({ up_to: latest });
      notify(n.allMarked);
    } catch (err) {
      setError(err);
    } finally {
      setBusy(false);
    }
  };
  const open = async (item: Item, href: string | null) => {
    try {
      if (!item.read) await markRead({ cursor: item.cursor });
    } catch (err) {
      setError(err);
      return;
    }
    if (href) router.push(href);
  };

  return (
    <>
      <PageHeader
        title={n.title}
        subtitle={n.subtitle}
        actions={
          <Button variant="secondary" icon={<CheckCheck className="size-4" aria-hidden />} onClick={() => void markAll()} loading={busy} disabled={!unread.length}>
            {n.markAllRead}
          </Button>
        }
      />
      <Card padded={false}>
        <Tabs
          label={n.title}
          value={view}
          onChange={setView}
          items={[
            { value: "all", label: t.common.all, count: q.data ? all.length : null },
            { value: "unread", label: n.unread, count: q.data ? unread.length : null },
          ]}
        />
        {error ? (
          <div className="px-5 pt-4">
            <InlineError error={error} />
          </div>
        ) : null}
        {q.error ? (
          <ErrorState error={q.error} onRetry={() => void q.refetch()} />
        ) : q.isPending ? (
          <div className="space-y-3 p-5" role="status" aria-label={t.common.loading}>
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-14" />
            ))}
          </div>
        ) : items.length ? (
          <ul className="divide-y divide-line">
            {items.map((item) => {
              const href = linkFor(item, can);
              const kind = KIND_ICON[item.kind] ?? { icon: item.kind.includes("deposit") ? FileWarning : Bell, tone: "bg-navy-50 text-navy-500" };
              const Icon = kind.icon;
              const label = (n.kinds as Record<string, string>)[item.kind] ?? (item.kind.startsWith("staff.") ? humanize(item.kind.slice(6)) : n.other);
              const interactive = href !== null || !item.read;
              const body = (
                <>
                  <span className={`relative mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-lg ${kind.tone}`}>
                    <Icon className="size-4" aria-hidden />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className={`flex items-center gap-2 text-sm ${item.read ? "text-muted" : "font-semibold text-ink"}`}>
                      {label}
                      {!item.read ? <span className="rounded-full bg-teal-600 px-1.5 py-px text-[0.65rem] font-semibold text-white">{n.new}</span> : null}
                    </span>
                    <MetaLine parts={[<bdi key="d">{fmt.dateTime(item.created_at)}</bdi>, fmt.relative(item.created_at)]} />
                  </span>
                  {href ? <ChevronLeft className="mt-2 size-4 shrink-0 text-subtle ltr:rotate-180" aria-hidden /> : null}
                </>
              );
              return (
                <li key={item.cursor} className={item.read ? "" : "bg-teal-50/30"}>
                  {interactive ? (
                    <button
                      type="button"
                      onClick={() => void open(item, href)}
                      className="flex w-full items-start gap-3 px-5 py-3.5 text-start transition-colors hover:bg-navy-50/60"
                      aria-label={`${label}${item.read ? "" : ` (${n.unread})`}${href ? "" : ` — ${n.markRead}`}`}
                    >
                      {body}
                    </button>
                  ) : (
                    <div className="flex items-start gap-3 px-5 py-3.5">{body}</div>
                  )}
                </li>
              );
            })}
          </ul>
        ) : (
          <EmptyState
            icon={<Bell className="size-6" aria-hidden />}
            title={view === "unread" && all.length ? n.noUnread : n.emptyTitle}
            hint={view === "unread" && all.length ? tpl(n.noUnreadHint, { count: all.length }) : n.emptyHint}
          />
        )}
      </Card>
    </>
  );
}
