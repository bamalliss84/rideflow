"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useMemo, type ReactNode } from "react";

import { ApiError, authCall, refreshSession, SESSION_EXPIRED_EVENT, type Schemas } from "@/lib/api/client";
import type { Formatters } from "@/lib/format";

import { useFormat } from "./I18nProvider";

export type Me = Schemas["Me"];

interface SessionValue {
  me: Me;
  scope: "tenant" | "platform";
  can: (permission: string) => boolean;
  hasRole: (role: string) => boolean;
  fmt: Formatters;
  signOut: () => Promise<void>;
}

const SessionContext = createContext<SessionValue | null>(null);

async function loadSession(): Promise<Me> {
  try {
    return await authCall<Me>("session", undefined, "GET");
  } catch (err) {
    if (err instanceof ApiError && err.status === 401 && (await refreshSession())) {
      return authCall<Me>("session", undefined, "GET");
    }
    throw err;
  }
}

export function SessionProvider({ scope, loginPath, children, fallback }: {
  scope: "tenant" | "platform";
  loginPath: string;
  children: ReactNode;
  fallback: ReactNode;
}) {
  const router = useRouter();
  const queryClient = useQueryClient();
  const { data, error, isPending } = useQuery({ queryKey: ["session", scope], queryFn: loadSession, retry: false, staleTime: 60_000 });

  const expire = useCallback(() => {
    queryClient.clear();
    router.replace(`${loginPath}?expired=1`);
  }, [queryClient, router, loginPath]);

  useEffect(() => {
    window.addEventListener(SESSION_EXPIRED_EVENT, expire);
    return () => window.removeEventListener(SESSION_EXPIRED_EVENT, expire);
  }, [expire]);

  useEffect(() => {
    if (error) expire();
    else if (data && data.scope !== scope) expire();
  }, [error, data, scope, expire]);

  const signOut = useCallback(async () => {
    await authCall("logout").catch(() => null);
    queryClient.clear();
    router.replace(`${loginPath}?signed_out=1`);
  }, [queryClient, router, loginPath]);

  const fmt = useFormat({ timeZone: data?.time_zone, currency: data?.currency, minorUnits: data?.currency_minor_units });

  const value = useMemo<SessionValue | null>(() => {
    if (!data) return null;
    const perms = new Set(data.permissions);
    const roles = new Set(data.tenant?.roles ?? []);
    return {
      me: data,
      scope,
      can: (p: string) => (scope === "platform" ? data.is_platform_admin : perms.has(p)),
      hasRole: (r: string) => roles.has(r),
      fmt,
      signOut,
    };
  }, [data, scope, fmt, signOut]);

  if (isPending || !value) return <>{fallback}</>;
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionValue {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error("useSession outside SessionProvider");
  return ctx;
}
