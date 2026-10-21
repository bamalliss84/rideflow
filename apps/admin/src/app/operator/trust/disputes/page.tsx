"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense } from "react";

import { EnumBadge, enumLabel, SafetyFlag } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, Tabs, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Dispute = Schemas["Dispute"];
const CATEGORIES = ["fare", "behavior", "safety", "no_show_contest", "cancellation", "other"] as const;

function DisputesList() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const tr = t.trust;
  const params = useSearchParams();
  const { filters, setFilters, page, setPage } = useListState<{ status: string; category: string; is_safety: string; ride: string }>({
    status: "open",
    category: "",
    is_safety: "",
    ride: params.get("ride") ?? "",
  });
  const q = useApiPage<Dispute>("admin/disputes", { ...filters, ordering: filters.status === "open" ? "created_at" : "-created_at" }, page);
  return (
    <>
      <PageHeader title={tr.disputesTitle} subtitle={tr.disputesSubtitle} />
      <Card padded={false}>
        <Tabs
          label={t.common.status}
          value={filters.status}
          onChange={(status) => setFilters({ status })}
          items={[...(["open", "under_review", "upheld", "rejected"] as const).map((v) => ({ value: v as string, label: t.enums.disputeStatus[v] })), { value: "", label: t.common.all }]}
        />
        <Toolbar>
          <FilterSelect label={tr.category} value={filters.category} onChange={(category) => setFilters({ category })} options={CATEGORIES.map((c) => ({ value: c, label: t.enums.disputeCategory[c] }))} />
          <FilterSelect label={tr.safety} value={filters.is_safety as "" | "true"} onChange={(v) => setFilters({ is_safety: v })} options={[{ value: "true", label: tr.safety }]} />
        </Toolbar>
        <DataTable<Dispute>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(d) => d.id}
          rowHref={(d) => `/operator/trust/disputes/${d.id}`}
          columns={[
            {
              key: "category",
              header: tr.category,
              cell: (d) => (
                <Link href={`/operator/trust/disputes/${d.id}`} className="flex flex-wrap items-center gap-2 font-medium hover:underline">
                  {enumLabel(t, "disputeCategory", d.category)}
                  {d.is_safety ? <SafetyFlag /> : null}
                </Link>
              ),
            },
            { key: "opened", header: tr.openedBy, cell: (d) => `${d.opened_by_name || "—"} · ${enumLabel(t, "actorRole", d.opened_by_role)}` },
            { key: "against", header: tr.against, hideBelow: "md", cell: (d) => (d.against_name ? `${d.against_name} · ${enumLabel(t, "actorRole", d.against_role)}` : "—") },
            { key: "description", header: tr.description, hideBelow: "lg", cell: (d) => <span className="line-clamp-2 max-w-72 text-xs text-muted">{d.description}</span> },
            { key: "created", header: t.common.created, hideBelow: "sm", cell: (d) => fmt.relative(d.created_at) },
            { key: "status", header: t.common.status, cell: (d) => <EnumBadge group="disputeStatus" value={d.status} /> },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}

export default function DisputesPage() {
  return (
    <Suspense>
      <DisputesList />
    </Suspense>
  );
}
