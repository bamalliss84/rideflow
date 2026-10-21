"use client";

import { Plus } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";

import { EnumBadge } from "@/components/domain/Display";
import { TenantForm } from "@/components/domain/TenantForm";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { useToast } from "@/components/providers/ToastProvider";
import { Button } from "@/components/ui/Button";
import { Card } from "@/components/ui/Card";
import { DataTable, Pagination } from "@/components/ui/DataTable";
import { Dialog } from "@/components/ui/Dialog";
import { FilterSelect, PageHeader, Toolbar } from "@/components/ui/Page";
import { api, newIdempotencyKey, type Schemas } from "@/lib/api/client";
import { useApiPage, useListState } from "@/lib/api/hooks";

type Tenant = Schemas["Tenant"];

export default function TenantsPage() {
  const { t } = useI18n();
  const { fmt } = useSession();
  const router = useRouter();
  const notify = useToast();
  const p = t.platform;
  const { filters, setFilters, page, setPage } = useListState<{ status: string }>({ status: "" });
  const q = useApiPage<Tenant>("platform/tenants", filters, page);
  const [creating, setCreating] = useState(false);
  const [key] = useState(newIdempotencyKey);

  return (
    <>
      <PageHeader
        title={p.tenantsTitle}
        subtitle={p.tenantsSubtitle}
        actions={
          <Button icon={<Plus className="size-4" aria-hidden />} onClick={() => setCreating(true)}>
            {p.newTenant}
          </Button>
        }
      />
      <Card padded={false}>
        <Toolbar>
          <FilterSelect
            label={t.common.status}
            value={filters.status}
            onChange={(status) => setFilters({ status })}
            options={(["active", "suspended"] as const).map((v) => ({ value: v, label: t.enums.tenantStatus[v] }))}
          />
        </Toolbar>
        <DataTable<Tenant>
          rows={q.data?.results}
          loading={q.isPending}
          error={q.error}
          onRetry={() => void q.refetch()}
          rowKey={(r) => r.id}
          rowHref={(r) => `/platform/tenants/${r.id}`}
          columns={[
            {
              key: "name",
              header: p.name,
              cell: (r) => (
                <Link href={`/platform/tenants/${r.id}`} className="font-medium hover:underline">
                  {r.name}
                </Link>
              ),
            },
            { key: "slug", header: p.slug, cell: (r) => <span className="ltr-nums text-muted">{r.slug}</span>, hideBelow: "sm" },
            { key: "status", header: t.common.status, cell: (r) => <EnumBadge group="tenantStatus" value={r.status} /> },
            { key: "currency", header: p.currency, cell: (r) => <span className="ltr-nums">{r.currency}</span>, hideBelow: "md" },
            { key: "tz", header: p.timeZone, cell: (r) => <span className="ltr-nums">{r.time_zone}</span>, hideBelow: "lg" },
            { key: "created", header: t.common.created, cell: (r) => fmt.date(r.created_at), hideBelow: "md" },
          ]}
        />
        <Pagination page={page} pageSize={25} count={q.data?.count ?? 0} onPage={setPage} />
      </Card>
      <Dialog open={creating} onClose={() => setCreating(false)} title={p.newTenant} size="lg">
        <TenantForm
          submitLabel={t.common.create}
          onCancel={() => setCreating(false)}
          onSubmit={async (body) => {
            const tenant = await api<Tenant>("platform/tenants", { method: "POST", body, idempotencyKey: key });
            notify(p.created);
            router.push(`/platform/tenants/${tenant.id}`);
          }}
        />
      </Dialog>
    </>
  );
}
