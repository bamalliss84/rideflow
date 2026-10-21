"use client";

import { useInfiniteQuery } from "@tanstack/react-query";
import { Bell, CheckCheck } from "lucide-react";
import Link from "next/link";

import { humanize } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { useToast } from "@/components/providers/ToastProvider";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { PageHeader } from "@/components/ui/Page";
import { EmptyState, ErrorState, Skeleton } from "@/components/ui/States";
import { api, type Schemas } from "@/lib/api/client";

type PageT = Schemas["NotificationPage"];
type Item = Schemas["NotificationItem"];

function linkFor(item: Item): string | null {
  const p = item.payload as Record<string, string>;
  if (item.kind === "staff.driver_submitted" && p.driver_id) return `/operator/drivers/${p.driver_id}`;
  if (item.kind === "staff.deposit_submitted" && p.claim_id) return `/operator/subscriptions/deposits/${p.claim_id}`;
  if (item.kind === "staff.dispute_opened" && p.dispute_id) return `/operator/trust/disputes/${p.dispute_id}`;
  if (item.kind === "staff.appeal_filed") return "/operator/trust/appeals";
  if (item.kind === "staff.incident_recorded") return "/operator/trust/violations";
  if (p.ride_id) return `/operator/rides/${p.ride_id}`;
  return null;
}

/** Newest-first view over the cursor-ordered notification feed (pages of 50, loaded backwards). */
export default function NotificationsPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const notify = useToast();
  const n = t.notifications;
  // The API pages forward by cursor; we first find the latest cursor, then read windows backwards.
  const q = useInfiniteQuery({
    queryKey: ["notifications-feed"],
    initialPageParam: 0,
    queryFn: async ({ pageParam }) => api<PageT>("notifications", { query: { after: pageParam, limit: 200 } }),
    getNextPageParam: (last) => (last.has_more ? last.next_cursor : undefined),
  });
  const items = (q.data?.pages.flatMap((p) => p.items) ?? []).slice().reverse();
  const latest = items[0]?.cursor ?? 0;

  const markAll = async () => {
    await api("notifications/read", { method: "POST", body: { up_to: latest } });
    notify(n.markAllRead);
  };

  return (
    <>
      <PageHeader
        title={n.title}
        subtitle={n.subtitle}
        actions={
          <Button variant="secondary" icon={<CheckCheck className="size-4" aria-hidden />} onClick={() => void markAll()} disabled={!latest}>
            {n.markAllRead}
          </Button>
        }
      />
      <Card padded={false}>
        {q.error ? (
          <ErrorState error={q.error} onRetry={() => void q.refetch()} />
        ) : q.isPending ? (
          <div className="space-y-3 p-5">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-12" />
            ))}
          </div>
        ) : items.length ? (
          <ul className="divide-y divide-line">
            {items.map((item) => {
              const href = linkFor(item);
              const label = (n.kinds as Record<string, string>)[item.kind] ?? (item.kind.startsWith("staff.") ? humanize(item.kind.slice(6)) : n.other);
              const body = (
                <div className="flex items-start gap-3 px-5 py-3.5">
                  <span className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-navy-50 text-navy-500">
                    <Bell className="size-4" aria-hidden />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm font-medium">{label}</span>
                    <span className="block text-xs text-muted">{fmt.dateTime(item.created_at)}</span>
                  </span>
                </div>
              );
              return <li key={item.cursor}>{href ? <Link href={href} className="block hover:bg-navy-50/60">{body}</Link> : body}</li>;
            })}
          </ul>
        ) : (
          <EmptyState />
        )}
        {q.hasNextPage ? (
          <div className="border-t border-line p-3 text-center">
            <Button variant="ghost" onClick={() => void q.fetchNextPage()} loading={q.isFetchingNextPage}>
              {t.common.loadMore}
            </Button>
          </div>
        ) : null}
      </Card>
    </>
  );
}
