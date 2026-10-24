"use client";

import { Download } from "lucide-react";
import Link from "next/link";

import { enumLabel } from "@/components/domain/Display";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { FilterSelect, PageHeader, Toolbar } from "@/components/ui/Page";
import type { Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";
import { downloadText, toCsv } from "@/lib/format";

type Entry = Schemas["LedgerEntry"];
const TYPES = ["subscription_payment", "trial_grant", "discount", "compensation_credit", "reversal"] as const;

export default function LedgerPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const s = t.subscriptions;
  const { filters, setFilters, page, setPage } = useListState<{ entry_type: string }>({ entry_type: "" });
  const q = useApiPage<Entry>("admin/subscription-ledger", filters, page, 50);
  const exportPage = () => {
    const rows = (q.data?.results ?? []).map((e) => ({
      date: e.created_at,
      driver: e.driver_name ?? "",
      type: enumLabel(t, "ledgerType", e.entry_type),
      amount_minor: e.amount_minor,
      currency: e.currency,
      days: e.days,
      reference: e.reference,
      note: e.note,
      by: e.created_by_name ?? "",
    }));
    downloadText(
      `rideflow-ledger-page-${page}.csv`,
      toCsv(rows, [
        { key: "date", label: t.common.date },
        { key: "driver", label: t.common.driver },
        { key: "type", label: s.entry },
        { key: "amount_minor", label: t.common.amount },
        { key: "currency", label: t.organization.currency },
        { key: "days", label: s.days },
        { key: "reference", label: s.reference },
        { key: "note", label: t.common.note },
        { key: "by", label: s.by },
      ]),
    );
  };
  return (
    <>
      <PageHeader
        title={s.ledgerTitle}
        subtitle={s.ledgerSubtitle}
        actions={
          <Button variant="secondary" icon={<Download className="size-4" aria-hidden />} onClick={exportPage} disabled={!q.data?.results.length}>
            {t.common.exportCsv}
          </Button>
        }
      />
      <Card padded={false}>
        <Toolbar>
          <FilterSelect label={s.entry} value={filters.entry_type} onChange={(entry_type) => setFilters({ entry_type })} options={TYPES.map((v) => ({ value: v, label: t.enums.ledgerType[v] }))} />
        </Toolbar>
        <DataTable<Entry>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(e) => e.id}
          columns={[
            { key: "date", header: t.common.date, cell: (e) => fmt.dateTime(e.created_at) },
            {
              key: "driver",
              header: t.common.driver,
              cell: (e) => (
                <Link href={`/operator/drivers/${e.driver}`} className="hover:underline">
                  {e.driver_name || "—"}
                </Link>
              ),
            },
            { key: "type", header: s.entry, cell: (e) => enumLabel(t, "ledgerType", e.entry_type) },
            { key: "amount", header: t.common.amount, align: "end", cell: (e) => <bdi>{e.amount_minor ? fmt.money(e.amount_minor, e.currency) : "—"}</bdi> },
            { key: "days", header: s.days, align: "end", hideBelow: "sm", cell: (e) => (e.days ? fmt.number(e.days) : "—") },
            { key: "ref", header: s.reference, hideBelow: "md", cell: (e) => <span className="ltr-nums">{e.reference || "—"}</span> },
            { key: "by", header: s.by, hideBelow: "lg", cell: (e) => e.created_by_name || "—" },
          ]}
        />
        <Pagination page={page} pageSize={50} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
    </>
  );
}
