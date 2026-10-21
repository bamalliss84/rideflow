"use client";

import Link from "next/link";

import { enumLabel, Stars } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge } from "@/components/ui/Badge";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Rating = Schemas["Rating"];

export default function RatingsPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const tr = t.trust;
  const { filters, setFilters, page, setPage } = useListState<{ ratee_role: string; stars: string }>({ ratee_role: "", stars: "" });
  const q = useApiPage<Rating>("admin/ratings", filters, page);
  return (
    <>
      <PageHeader title={tr.ratingsTitle} subtitle={tr.ratingsSubtitle} />
      <Card padded={false}>
        <Toolbar>
          <FilterSelect
            label={tr.ratee}
            value={filters.ratee_role as "" | "driver" | "rider"}
            onChange={(ratee_role) => setFilters({ ratee_role })}
            options={[
              { value: "driver", label: t.roles.driver },
              { value: "rider", label: t.roles.rider },
            ]}
          />
          <FilterSelect
            label={tr.stars}
            value={filters.stars as "" | "1" | "2" | "3" | "4" | "5"}
            onChange={(stars) => setFilters({ stars })}
            options={(["1", "2", "3", "4", "5"] as const).map((v) => ({ value: v, label: "★".repeat(Number(v)) }))}
          />
        </Toolbar>
        <DataTable<Rating>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(r) => r.id}
          columns={[
            { key: "date", header: t.common.date, cell: (r) => fmt.dateTime(r.created_at) },
            { key: "rater", header: tr.rater, cell: (r) => `${r.rater_name || "—"} · ${enumLabel(t, "actorRole", r.rater_role)}` },
            { key: "ratee", header: tr.ratee, cell: (r) => `${r.ratee_name || "—"} · ${enumLabel(t, "actorRole", r.ratee_role)}` },
            { key: "stars", header: tr.stars, cell: (r) => <Stars value={r.stars} /> },
            {
              key: "tags",
              header: tr.tags,
              hideBelow: "md",
              cell: (r) => (
                <span className="flex flex-wrap gap-1">
                  {((r.tags as string[] | null) ?? []).map((tag) => (
                    <Badge key={tag} dot={false}>
                      {enumLabel(t, "ratingTag", tag)}
                    </Badge>
                  ))}
                </span>
              ),
            },
            { key: "comment", header: tr.comment, hideBelow: "lg", cell: (r) => <span className="line-clamp-2 max-w-64 text-xs text-muted">{r.comment || "—"}</span> },
            {
              key: "ride",
              header: <span className="sr-only">{t.nav.rides}</span>,
              align: "end",
              cell: (r) => (
                <Link className="text-xs font-medium text-teal-700 hover:underline" href={`/operator/rides/${r.ride}`}>
                  {t.common.open}
                </Link>
              ),
            },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}
