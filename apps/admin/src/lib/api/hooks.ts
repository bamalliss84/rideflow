"use client";

import { keepPreviousData, useMutation, useQuery, useQueryClient, type UseQueryOptions } from "@tanstack/react-query";
import { useCallback, useRef, useState } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { useToast } from "@/components/providers/ToastProvider";
import { errorMessage } from "@/components/ui/States";

import { api, newIdempotencyKey, type Page, type Query, type RequestOptions } from "./client";

export function useApi<T>(path: string | null, query?: Query, options?: Partial<UseQueryOptions<T>>) {
  return useQuery<T>({
    queryKey: [path, query ?? {}],
    queryFn: ({ signal }) => api<T>(path as string, { query, signal }),
    enabled: path !== null,
    ...options,
  });
}

export function useApiPage<T>(path: string, query: Query, page: number, pageSize = 25) {
  return useQuery<Page<T>>({
    queryKey: [path, { ...query, page, page_size: pageSize }],
    queryFn: ({ signal }) => api<Page<T>>(path, { query: { ...query, page, page_size: pageSize }, signal }),
    placeholderData: keepPreviousData,
  });
}

/** List-page state: filters + page reset when filters change. */
export function useListState<F extends Query>(initial: F) {
  const [filters, setFiltersState] = useState<F>(initial);
  const [page, setPage] = useState(1);
  const setFilters = useCallback((next: Partial<F>) => {
    setFiltersState((prev) => ({ ...prev, ...next }));
    setPage(1);
  }, []);
  return { filters, setFilters, page, setPage };
}

export interface ActionOptions {
  /** Query-key prefixes (API paths) to invalidate after success. */
  invalidate?: string[];
  success?: string;
  /** Errors are rendered inline by the caller (e.g. inside a dialog) instead of a toast. */
  inlineErrors?: boolean;
}

/**
 * Mutation with a stable Idempotency-Key per logical submission: retries of the same submission reuse
 * the key (server replays instead of double-applying); a new key is generated after success.
 */
export function useAction<TBody = unknown, TResult = unknown>(
  method: RequestOptions["method"],
  pathOrFn: string | ((vars: TBody) => string),
  options: ActionOptions = {},
) {
  const queryClient = useQueryClient();
  const notify = useToast();
  const { t } = useI18n();
  const keyRef = useRef<string>(newIdempotencyKey());
  const mutation = useMutation<TResult, unknown, TBody>({
    mutationFn: (vars) => {
      const path = typeof pathOrFn === "string" ? pathOrFn : pathOrFn(vars);
      const body = typeof pathOrFn === "string" ? vars : (vars as { body?: unknown })?.body;
      return api<TResult>(path, { method, body, idempotencyKey: keyRef.current });
    },
    onSuccess: async () => {
      keyRef.current = newIdempotencyKey();
      await Promise.all(
        (options.invalidate ?? []).map((prefix) =>
          queryClient.invalidateQueries({ predicate: (q) => typeof q.queryKey[0] === "string" && (q.queryKey[0] as string).startsWith(prefix) }),
        ),
      );
      if (options.success) notify(options.success);
    },
    onError: (err) => {
      // A business/validation answer is final for this payload: allow a corrected resubmission.
      keyRef.current = newIdempotencyKey();
      if (!options.inlineErrors) notify(errorMessage(err, t), "error");
    },
  });
  return mutation;
}
