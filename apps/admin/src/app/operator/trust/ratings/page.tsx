"use client";

import { ArrowLeft, Star } from "lucide-react";
import Link from "next/link";

import { enumLabel, PersonRole, Stars } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, Toolbar } from "@/components/ui/Page";
import { EmptyState } from "@/components/ui/States";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Rating = Schemas["Rating"];
type Ordering = "-created_at" | "created_at" | "stars" | "-stars";

export default function RatingsPage() {
  const { t } = useI18n();
  const { fmt, can } = useSession();
  const tr = t.trust;
  // Filters map 1:1 to the API: ratee_role, stars and DRF ordering (created_at, stars).
  const { filters, setFilters, page, setPage } = useListState<{ ratee_role: string; stars: string; ordering: string }>({ ratee_role: "", stars: "", ordering: "-created_at" });
  const q = useApiPage<Rating>("admin/ratings", filters, page);
  const filtered = Boolean(filters.ratee_role || filters.stars);
  return (
    <>
      <PageHeader title={tr.ratingsTitle} subtitle={tr.ratingsSubtitle} />
      <Card padded={false}>
        <Toolbar>
          <FilterSelect
            label={tr.direction}
            value={filters.ratee_role as "" | "driver" | "rider"}
            onChange={(ratee_role) => setFilters({ ratee_role })}
            options={[
              { value: "driver", label: tr.riderToDriver },
              { value: "rider", label: tr.driverToRider },
            ]}
          />
          <FilterSelect
            label={tr.stars}
            value={filters.stars as "" | "1" | "2" | "3" | "4" | "5"}
            onChange={(stars) => setFilters({ stars })}
            options={(["5", "4", "3", "2", "1"] as const).map((v) => ({ value: v, label: `${"★".repeat(Number(v))} (${v})` }))}
          />
          <FilterSelect<Ordering>
            label={t.common.sortBy}
            allowAll={false}
            value={filters.ordering as Ordering}
            onChange={(ordering) => setFilters({ ordering: ordering || "-created_at" })}
            options={[
              { value: "-created_at", label: tr.sortNewest },
              { value: "created_at", label: tr.sortOldest },
              { value: "stars", label: tr.sortLowest },
              { value: "-stars", label: tr.sortHighest },
            ]}
          />
        </Toolbar>
        <DataTable<Rating>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(r) => r.id}
          caption={tr.ratingsTitle}
          empty={<EmptyState filtered={filtered} icon={filtered ? undefined : <Star className="size-6" aria-hidden />} title={filtered ? undefined : tr.noRatings} hint={filtered ? undefined : tr.noRatingsHint} />}
          columns={[
            { key: "date", header: t.common.date, className: "whitespace-nowrap", cell: (r) => <bdi className="text-muted">{fmt.dateTime(r.created_at)}</bdi> },
            {
              key: "direction",
              header: `${tr.rater} / ${tr.ratee}`,
              cell: (r) => (
                <span className="flex min-w-48 items-center gap-2">
                  <PersonRole name={r.rater_name} role={r.rater_role} />
                  <ArrowLeft className="size-4 shrink-0 text-subtle ltr:rotate-180" aria-label={tr.ratedArrow} />
                  <PersonRole name={r.ratee_name} role={r.ratee_role} />
                </span>
              ),
            },
            { key: "stars", header: tr.stars, className: "whitespace-nowrap", cell: (r) => <Stars value={r.stars} showValue /> },
            {
              key: "tags",
              header: tr.tags,
              hideBelow: "md",
              cell: (r) => {
                const tags = (r.tags as string[] | null) ?? [];
                return tags.length ? (
                  <span className="flex max-w-72 flex-wrap gap-1">
                    {tags.map((tag) => (
                      <Badge key={tag} dot={false} tone={r.stars <= 2 ? "warning" : "neutral"}>
                        {enumLabel(t, "ratingTag", tag)}
                      </Badge>
                    ))}
                  </span>
                ) : (
                  <span className="text-subtle">—</span>
                );
              },
            },
            {
              key: "comment",
              header: tr.comment,
              hideBelow: "lg",
              cell: (r) =>
                r.comment ? (
                  <bdi className="line-clamp-2 block max-w-72 text-xs leading-relaxed text-ink" title={r.comment}>
                    {r.comment}
                  </bdi>
                ) : (
                  <span className="text-subtle">—</span>
                ),
            },
            {
              key: "ride",
              header: <span className="sr-only">{t.nav.rides}</span>,
              align: "end",
              cell: (r) =>
                can("rides.view") ? (
                  <Link className="text-xs font-medium whitespace-nowrap text-teal-700 hover:underline" href={`/operator/rides/${r.ride}`}>
                    {tr.viewRide}
                  </Link>
                ) : null,
            },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}
