"use client";

import { CircleAlert, Inbox, Lock, RefreshCw, SearchX } from "lucide-react";
import type { ReactNode } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { ApiError } from "@/lib/api/client";
import type { Dictionary } from "@/lib/i18n";

export function Spinner({ className = "size-5" }: { className?: string }) {
  return (
    <svg className={`animate-spin text-current ${className}`} viewBox="0 0 24 24" aria-hidden="true">
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeOpacity="0.2" strokeWidth="3" />
      <path d="M21 12a9 9 0 0 0-9-9" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}

export function Skeleton({ className = "h-4 w-full" }: { className?: string }) {
  return <div className={`animate-pulse rounded bg-navy-100/70 ${className}`} aria-hidden="true" />;
}

export function PageSkeleton() {
  const { t } = useI18n();
  return (
    <div className="space-y-4" role="status" aria-label={t.common.loading}>
      <Skeleton className="h-8 w-64" />
      <Skeleton className="h-4 w-96 max-w-full" />
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {[0, 1, 2, 3].map((i) => (
          <Skeleton key={i} className="h-24" />
        ))}
      </div>
      <Skeleton className="h-72" />
    </div>
  );
}

export function EmptyState({ title, hint, icon, action, filtered = false }: { title?: string; hint?: string; icon?: ReactNode; action?: ReactNode; filtered?: boolean }) {
  const { t } = useI18n();
  return (
    <div className="flex flex-col items-center justify-center px-6 py-14 text-center">
      <div className="mb-3 flex size-12 items-center justify-center rounded-full bg-navy-50 text-navy-400">
        {icon ?? (filtered ? <SearchX className="size-6" aria-hidden /> : <Inbox className="size-6" aria-hidden />)}
      </div>
      <p className="font-semibold text-ink">{title ?? (filtered ? t.common.noResults : t.common.emptyTitle)}</p>
      {!filtered || hint ? <p className="mt-1 max-w-md text-sm text-muted">{hint ?? t.common.emptyHint}</p> : null}
      {action ? <div className="mt-4">{action}</div> : null}
    </div>
  );
}

export function errorMessage(err: unknown, t: Dictionary): string {
  if (!(err instanceof ApiError)) return t.errors.network;
  const known = (t.errors.codes as Record<string, string>)[err.code];
  if (known) return known;
  if (err.status === 0) return t.errors.network;
  if (err.status === 401) return t.errors.sessionExpired;
  if (err.status === 403) return err.code === "csrf_failed" ? t.errors.csrf : t.errors.forbidden;
  if (err.status === 404) return t.errors.notFound;
  if (err.status === 409) return t.errors.conflict;
  if (err.status === 400) return t.errors.validation;
  if (err.status === 422) return typeof err.detail === "string" ? err.detail : t.errors.validation;
  if (err.status === 429) return t.errors.rateLimited;
  return t.errors.server;
}

export function ErrorState({ error, onRetry, compact = false }: { error: unknown; onRetry?: () => void; compact?: boolean }) {
  const { t } = useI18n();
  const status = error instanceof ApiError ? error.status : 0;
  const Icon = status === 403 ? Lock : CircleAlert;
  return (
    <div role="alert" className={`flex flex-col items-center justify-center text-center ${compact ? "px-4 py-6" : "px-6 py-14"}`}>
      <div className={`mb-3 flex size-12 items-center justify-center rounded-full ${status === 403 ? "bg-navy-50 text-navy-500" : "bg-coral-50 text-coral-600"}`}>
        <Icon className="size-6" aria-hidden />
      </div>
      <p className="font-semibold text-ink">{status === 403 ? t.errors.forbidden : t.errors.title}</p>
      {status !== 403 ? <p className="mt-1 max-w-md text-sm text-muted">{errorMessage(error, t)}</p> : null}
      {onRetry && status !== 403 && status !== 404 ? (
        <button type="button" onClick={onRetry} className="mt-4 inline-flex items-center gap-1.5 text-sm font-medium text-teal-700 hover:underline">
          <RefreshCw className="size-4" aria-hidden />
          {t.common.retry}
        </button>
      ) : null}
    </div>
  );
}

export function InlineError({ error }: { error: unknown }) {
  const { t } = useI18n();
  if (!error) return null;
  return (
    <p role="alert" className="flex items-start gap-2 rounded-md border border-coral-200 bg-coral-50 px-3 py-2 text-sm text-coral-800">
      <CircleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
      <span>{errorMessage(error, t)}</span>
    </p>
  );
}
