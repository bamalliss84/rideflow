"use client";

import type { ReactNode } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { SessionProvider } from "@/components/providers/SessionProvider";
import { AppShell, FullPageLoading } from "@/components/shell/AppShell";
import { platformNav } from "@/lib/nav";

export default function PlatformLayout({ children }: { children: ReactNode }) {
  const { t } = useI18n();
  return (
    <SessionProvider scope="platform" loginPath="/platform/login" fallback={<FullPageLoading />}>
      <AppShell nav={platformNav(t)} portalLabel={t.nav.platformPortal} contextLabel="RideFlow" accountHref="/platform/account">
        {children}
      </AppShell>
    </SessionProvider>
  );
}
