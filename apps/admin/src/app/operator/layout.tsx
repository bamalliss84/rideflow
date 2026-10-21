"use client";

import type { ReactNode } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { SessionProvider, useSession } from "@/components/providers/SessionProvider";
import { AppShell, FullPageLoading } from "@/components/shell/AppShell";
import { operatorNav } from "@/lib/nav";

function Frame({ children }: { children: ReactNode }) {
  const { t } = useI18n();
  const { me } = useSession();
  return (
    <AppShell
      nav={operatorNav(t)}
      portalLabel={t.nav.operatorPortal}
      contextLabel={me.tenant?.tenant_name}
      accountHref="/operator/account"
      notificationsHref="/operator/notifications"
    >
      {children}
    </AppShell>
  );
}

export default function OperatorLayout({ children }: { children: ReactNode }) {
  return (
    <SessionProvider scope="tenant" loginPath="/login" fallback={<FullPageLoading />}>
      <Frame>{children}</Frame>
    </SessionProvider>
  );
}
