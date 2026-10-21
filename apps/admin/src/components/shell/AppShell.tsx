"use client";

import { Bell, ChevronDown, Languages, LogOut, Menu, ShieldCheck, UserRound, X } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState, type ReactNode } from "react";

import { Wordmark } from "@/components/brand/Logo";
import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { filterNav, type NavGroup } from "@/lib/nav";

function NavLinks({ groups, onNavigate }: { groups: NavGroup[]; onNavigate?: () => void }) {
  const pathname = usePathname();
  return (
    <nav className="flex-1 space-y-5 overflow-y-auto px-3 py-4" aria-label="primary">
      {groups.map((group, gi) => (
        <div key={gi}>
          {group.title ? <p className="mb-1.5 px-3 text-[0.68rem] font-semibold tracking-wide text-navy-300 uppercase">{group.title}</p> : null}
          <ul className="space-y-0.5">
            {group.items.map((item) => {
              const active = item.exact ? pathname === item.href : pathname === item.href || pathname.startsWith(`${item.href}/`);
              const Icon = item.icon;
              return (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    onClick={onNavigate}
                    aria-current={active ? "page" : undefined}
                    className={`flex items-center gap-2.5 rounded-md px-3 py-2 text-[0.84rem] font-medium transition-colors ${
                      active ? "bg-white/10 text-white" : "text-navy-200 hover:bg-white/5 hover:text-white"
                    }`}
                  >
                    <Icon className={`size-4 shrink-0 ${active ? "text-teal-300" : "text-navy-300"}`} aria-hidden />
                    <span className="truncate">{item.label}</span>
                    {active ? <span className="ms-auto h-4 w-0.5 rounded-full bg-teal-400" aria-hidden /> : null}
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </nav>
  );
}

function UserMenu({ accountHref }: { accountHref: string }) {
  const { me, signOut, scope } = useSession();
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const onDoc = (e: MouseEvent) => !ref.current?.contains(e.target as Node) && setOpen(false);
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", onDoc);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDoc);
      document.removeEventListener("keydown", onKey);
    };
  }, []);
  const roles = scope === "platform" ? [t.roles.platform] : (me.tenant?.roles ?? []).map((r) => (t.roles as Record<string, string>)[r] ?? r);
  const name = me.user.full_name || me.user.phone;
  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-haspopup="menu"
        className="flex items-center gap-2 rounded-md px-2 py-1.5 text-start hover:bg-navy-50"
      >
        <span className="flex size-8 items-center justify-center rounded-full bg-navy-900 text-xs font-semibold text-white">{name.slice(0, 1).toUpperCase()}</span>
        <span className="hidden min-w-0 flex-col sm:flex">
          <span className="max-w-40 truncate text-sm font-medium text-ink">{name}</span>
          <span className="max-w-40 truncate text-[0.7rem] text-muted">{roles.join("، ")}</span>
        </span>
        <ChevronDown className="size-4 text-muted" aria-hidden />
      </button>
      {open ? (
        <div role="menu" className="absolute end-0 top-full z-40 mt-1 w-64 rounded-lg border border-line bg-white p-1.5 shadow-pop">
          <div className="border-b border-line px-3 py-2">
            <p className="truncate text-sm font-medium">{name}</p>
            <p className="text-xs text-muted ltr-nums">{me.user.phone}</p>
            {me.mfa.session_verified ? (
              <p className="mt-1.5 flex items-center gap-1 text-xs text-teal-700">
                <ShieldCheck className="size-3.5" aria-hidden />
                {t.account.mfaSession}
              </p>
            ) : null}
          </div>
          <Link role="menuitem" href={accountHref} onClick={() => setOpen(false)} className="mt-1 flex items-center gap-2 rounded-md px-3 py-2 text-sm hover:bg-navy-50">
            <UserRound className="size-4 text-muted" aria-hidden />
            {t.nav.account}
          </Link>
          <button role="menuitem" type="button" onClick={() => void signOut()} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm text-coral-700 hover:bg-coral-50">
            <LogOut className="size-4" aria-hidden />
            {t.common.signOut}
          </button>
        </div>
      ) : null}
    </div>
  );
}

export function LanguageSwitch({ className = "" }: { className?: string }) {
  const { t, locale, setLocale } = useI18n();
  return (
    <button
      type="button"
      onClick={() => setLocale(locale === "ar" ? "en" : "ar")}
      className={`inline-flex h-9 items-center gap-1.5 rounded-md px-2.5 text-sm font-medium text-navy-700 hover:bg-navy-50 ${className}`}
      aria-label={t.common.language}
      lang={locale === "ar" ? "en" : "ar"}
    >
      <Languages className="size-4" aria-hidden />
      {t.common.switchLanguage}
    </button>
  );
}

export function AppShell({ nav, portalLabel, contextLabel, accountHref, notificationsHref, children }: {
  nav: NavGroup[];
  portalLabel: string;
  contextLabel?: string;
  accountHref: string;
  notificationsHref?: string;
  children: ReactNode;
}) {
  const { t } = useI18n();
  const { can } = useSession();
  const pathname = usePathname();
  // The drawer belongs to the page it was opened on: navigating closes it without an effect.
  const [drawerPath, setDrawerPath] = useState<string | null>(null);
  const drawer = drawerPath === pathname;
  const setDrawer = (open: boolean) => setDrawerPath(open ? pathname : null);
  const groups = filterNav(nav, can);

  const sidebar = (onNavigate?: () => void) => (
    <div className="flex h-full flex-col bg-navy-900">
      <div className="flex h-16 items-center border-b border-white/10 px-5">
        <Wordmark inverted subtitle={portalLabel} />
      </div>
      {contextLabel ? (
        <div className="border-b border-white/10 px-5 py-3">
          <p className="text-[0.68rem] text-navy-300">{portalLabel}</p>
          <p className="truncate text-sm font-semibold text-white">{contextLabel}</p>
        </div>
      ) : null}
      <NavLinks groups={groups} onNavigate={onNavigate} />
      <p className="border-t border-white/10 px-5 py-3 text-[0.68rem] text-navy-300">{t.meta.tagline}</p>
    </div>
  );

  return (
    <div className="min-h-dvh">
      <a href="#main" className="sr-only z-50 rounded bg-white px-3 py-2 focus:not-sr-only focus:fixed focus:start-3 focus:top-3">
        {t.common.skipToContent}
      </a>
      <aside className="fixed inset-y-0 start-0 z-30 hidden w-64 lg:block">{sidebar()}</aside>
      {drawer ? (
        <div className="fixed inset-0 z-40 lg:hidden" role="dialog" aria-modal="true" aria-label={t.common.menu}>
          <button type="button" className="absolute inset-0 bg-navy-950/50" aria-label={t.common.close} onClick={() => setDrawer(false)} />
          <div className="absolute inset-y-0 start-0 w-72 max-w-[85vw] shadow-pop">
            {sidebar(() => setDrawer(false))}
            <button type="button" onClick={() => setDrawer(false)} className="absolute end-3 top-4 rounded p-1 text-navy-200 hover:text-white" aria-label={t.common.close}>
              <X className="size-5" aria-hidden />
            </button>
          </div>
        </div>
      ) : null}
      <div className="lg:ps-64">
        <header className="sticky top-0 z-20 flex h-16 items-center gap-2 border-b border-line bg-white/90 px-4 backdrop-blur sm:px-6">
          <button type="button" className="rounded-md p-2 text-navy-700 hover:bg-navy-50 lg:hidden" onClick={() => setDrawer(true)} aria-label={t.common.menu}>
            <Menu className="size-5" aria-hidden />
          </button>
          <p className="truncate text-sm font-medium text-muted lg:hidden">{contextLabel ?? portalLabel}</p>
          <div className="ms-auto flex items-center gap-1">
            <LanguageSwitch />
            {notificationsHref ? (
              <Link href={notificationsHref} className="rounded-md p-2 text-navy-700 hover:bg-navy-50" aria-label={t.nav.notifications} title={t.nav.notifications}>
                <Bell className="size-5" aria-hidden />
              </Link>
            ) : null}
            <UserMenu accountHref={accountHref} />
          </div>
        </header>
        <main id="main" className="mx-auto w-full max-w-[1400px] px-4 py-6 sm:px-6 lg:px-8">
          {children}
        </main>
      </div>
    </div>
  );
}

export function FullPageLoading() {
  return (
    <div className="flex min-h-dvh items-center justify-center bg-surface" role="status">
      <div className="flex flex-col items-center gap-4">
        <Wordmark />
        <span className="h-1 w-32 overflow-hidden rounded-full bg-navy-100">
          <span className="block h-full w-1/3 animate-[pulse_1s_ease-in-out_infinite] rounded-full bg-teal-600" />
        </span>
      </div>
    </div>
  );
}
