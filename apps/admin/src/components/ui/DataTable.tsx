"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { useRouter } from "next/navigation";
import type { ReactNode } from "react";

import { useI18n } from "@/components/providers/I18nProvider";

import { EmptyState, ErrorState, Skeleton } from "./States";

export interface Column<T> {
  key: string;
  header: ReactNode;
  cell: (row: T) => ReactNode;
  className?: string;
  /** Hide on small screens to keep the table readable. */
  hideBelow?: "sm" | "md" | "lg";
  align?: "start" | "end";
}

const hide = { sm: "hidden sm:table-cell", md: "hidden md:table-cell", lg: "hidden lg:table-cell" };

export function DataTable<T>({
  columns,
  rows,
  rowKey,
  loading,
  error,
  onRetry,
  rowHref,
  empty,
  caption,
}: {
  columns: Column<T>[];
  rows: T[] | undefined;
  rowKey: (row: T) => string;
  loading?: boolean;
  error?: unknown;
  onRetry?: () => void;
  rowHref?: (row: T) => string | undefined;
  empty?: ReactNode;
  caption?: string;
}) {
  const router = useRouter();
  if (error) return <ErrorState error={error} onRetry={onRetry} />;
  const colClass = (c: Column<T>) => `${c.hideBelow ? hide[c.hideBelow] : ""} ${c.align === "end" ? "text-end" : "text-start"} ${c.className ?? ""}`;
  return (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-sm">
        {caption ? <caption className="sr-only">{caption}</caption> : null}
        <thead>
          <tr className="border-b border-line bg-surface/70">
            {columns.map((c) => (
              <th key={c.key} scope="col" className={`px-4 py-2.5 text-xs font-semibold whitespace-nowrap text-muted ${colClass(c)}`}>
                {c.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {loading
            ? Array.from({ length: 6 }, (_, i) => (
                <tr key={i} className="border-b border-line last:border-0">
                  {columns.map((c) => (
                    <td key={c.key} className={`px-4 py-3 ${colClass(c)}`}>
                      <Skeleton className="h-4 w-3/4" />
                    </td>
                  ))}
                </tr>
              ))
            : rows?.map((row) => {
                const href = rowHref?.(row);
                return (
                  <tr
                    key={rowKey(row)}
                    className={`border-b border-line last:border-0 ${href ? "cursor-pointer hover:bg-navy-50/60" : ""}`}
                    onClick={
                      href
                        ? (e) => {
                            if ((e.target as HTMLElement).closest("a,button,input,select,textarea")) return;
                            router.push(href);
                          }
                        : undefined
                    }
                  >
                    {columns.map((c) => (
                      <td key={c.key} className={`px-4 py-3 align-middle ${colClass(c)}`}>
                        {c.cell(row)}
                      </td>
                    ))}
                  </tr>
                );
              })}
        </tbody>
      </table>
      {!loading && rows && rows.length === 0 ? empty ?? <EmptyState /> : null}
    </div>
  );
}

export function Pagination({ page, pageSize, count, onPage }: { page: number; pageSize: number; count: number; onPage: (p: number) => void }) {
  const { t, tpl } = useI18n();
  const pages = Math.max(1, Math.ceil(count / pageSize));
  if (count <= pageSize) {
    return count ? <p className="border-t border-line px-4 py-2.5 text-xs text-muted">{tpl(t.common.results, { count })}</p> : null;
  }
  return (
    <nav className="flex items-center justify-between gap-3 border-t border-line px-4 py-2.5 text-xs text-muted" aria-label="pagination">
      <span>{tpl(t.common.results, { count })}</span>
      <div className="flex items-center gap-1">
        <button
          type="button"
          className="inline-flex h-8 items-center gap-1 rounded-md px-2 font-medium text-navy-700 hover:bg-navy-50 disabled:opacity-40"
          disabled={page <= 1}
          onClick={() => onPage(page - 1)}
        >
          <ChevronRight className="size-4 ltr:rotate-180" aria-hidden />
          {t.common.previous}
        </button>
        <span className="px-2 ltr-nums">{tpl(t.common.pageOf, { page, pages })}</span>
        <button
          type="button"
          className="inline-flex h-8 items-center gap-1 rounded-md px-2 font-medium text-navy-700 hover:bg-navy-50 disabled:opacity-40"
          disabled={page >= pages}
          onClick={() => onPage(page + 1)}
        >
          {t.common.next}
          <ChevronLeft className="size-4 ltr:rotate-180" aria-hidden />
        </button>
      </div>
    </nav>
  );
}
