"use client";

import Link from "next/link";

import { EnumBadge, Person } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { PageHeader, SearchInput, Tabs, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Claim = Schemas["DepositClaim"];
const STATUSES = ["submitted", "first_approved", "approved", "rejected"] as const;

export default function DepositsPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const s = t.subscriptions;
  const { filters, setFilters, page, setPage } = useListState<{ status: string; reference: string }>({ status: "submitted", reference: "" });
  const q = useApiPage<Claim>("admin/deposit-claims", { ...filters, ordering: filters.status === "submitted" ? "created_at" : "-created_at" }, page);
  return (
    <>
      <PageHeader title={s.claimsTitle} subtitle={s.claimsSubtitle} />
      <Card padded={false}>
        <Tabs
          label={t.common.status}
          value={filters.status}
          onChange={(status) => setFilters({ status })}
          items={[...STATUSES.map((v) => ({ value: v as string, label: t.enums.claimStatus[v] })), { value: "", label: t.common.all }]}
        />
        <Toolbar>
          <SearchInput value={filters.reference} onChange={(reference) => setFilters({ reference })} placeholder={s.reference} />
        </Toolbar>
        <DataTable<Claim>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(r) => r.id}
          rowHref={(r) => `/operator/subscriptions/deposits/${r.id}`}
          columns={[
            {
              key: "ref",
              header: s.reference,
              cell: (r) => (
                <Link href={`/operator/subscriptions/deposits/${r.id}`} className="font-medium hover:underline ltr-nums">
                  {r.reference}
                </Link>
              ),
            },
            { key: "driver", header: t.common.driver, cell: (r) => <Person name={r.driver_name} phone={r.driver_phone} /> },
            { key: "plan", header: s.plan, hideBelow: "md", cell: (r) => r.plan.name },
            { key: "amount", header: t.common.amount, align: "end", cell: (r) => <bdi className="font-medium">{fmt.money(r.amount_minor, r.currency)}</bdi> },
            { key: "deposited", header: s.depositedOn, hideBelow: "lg", cell: (r) => fmt.day(r.deposited_on) },
            { key: "submitted", header: t.common.created, hideBelow: "sm", cell: (r) => fmt.relative(r.created_at) },
            { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="claimStatus" value={r.status} /> },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}
