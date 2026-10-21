import {
  Activity,
  BadgeCheck,
  Banknote,
  Bell,
  BookOpenCheck,
  Building2,
  Car,
  ClipboardList,
  FileBarChart,
  Gavel,
  Landmark,
  LayoutDashboard,
  ListChecks,
  Map,
  MapPinned,
  MessageSquareWarning,
  Receipt,
  Route,
  Scale,
  ScrollText,
  Settings2,
  ShieldAlert,
  Star,
  Users,
  UserRound,
  WalletCards,
  type LucideIcon,
} from "lucide-react";

import type { Dictionary } from "./i18n";

export interface NavItem {
  href: string;
  label: string;
  icon: LucideIcon;
  permission?: string;
  exact?: boolean;
}
export interface NavGroup {
  title?: string;
  items: NavItem[];
}

export function operatorNav(t: Dictionary): NavGroup[] {
  const n = t.nav;
  return [
    { items: [{ href: "/operator", label: n.dashboard, icon: LayoutDashboard, permission: "reports.view", exact: true }] },
    {
      title: n.operations,
      items: [
        { href: "/operator/drivers", label: n.drivers, icon: Car, permission: "drivers.view", exact: true },
        { href: "/operator/drivers/verification", label: n.verification, icon: BadgeCheck, permission: "drivers.view" },
        { href: "/operator/riders", label: n.riders, icon: UserRound, permission: "rides.view" },
        { href: "/operator/rides", label: n.rides, icon: Route, permission: "rides.view" },
        { href: "/operator/live", label: n.live, icon: MapPinned, permission: "drivers.view" },
        { href: "/operator/geo", label: n.geography, icon: Map, permission: "rides.view" },
      ],
    },
    {
      title: n.finance,
      items: [
        { href: "/operator/subscriptions/deposits", label: n.deposits, icon: Receipt, permission: "subscriptions.view" },
        { href: "/operator/subscriptions/active", label: n.activeSubscriptions, icon: WalletCards, permission: "subscriptions.view" },
        { href: "/operator/subscriptions/plans", label: n.plans, icon: ClipboardList, permission: "subscriptions.view" },
        { href: "/operator/subscriptions/accounts", label: n.accounts, icon: Landmark, permission: "subscriptions.view" },
        { href: "/operator/subscriptions/ledger", label: n.ledger, icon: Banknote, permission: "subscriptions.view" },
      ],
    },
    {
      title: n.trust,
      items: [
        { href: "/operator/trust/disputes", label: n.disputes, icon: MessageSquareWarning, permission: "disputes.review" },
        { href: "/operator/trust/violations", label: n.violations, icon: ShieldAlert, permission: "violations.review" },
        { href: "/operator/trust/enforcement", label: n.enforcement, icon: Gavel, permission: "violations.review" },
        { href: "/operator/trust/appeals", label: n.appeals, icon: Scale, permission: "violations.review" },
        { href: "/operator/trust/scores", label: n.scores, icon: BookOpenCheck, permission: "reports.view" },
        { href: "/operator/trust/ratings", label: n.ratings, icon: Star, permission: "violations.review" },
      ],
    },
    {
      title: n.insights,
      items: [
        { href: "/operator/reports", label: n.reports, icon: FileBarChart, permission: "reports.view" },
        { href: "/operator/notifications", label: n.notifications, icon: Bell },
        { href: "/operator/audit", label: n.audit, icon: ScrollText, permission: "audit.view" },
      ],
    },
    {
      title: n.administration,
      items: [
        { href: "/operator/members", label: n.members, icon: Users, permission: "members.manage" },
        { href: "/operator/settings/policy", label: n.policy, icon: Settings2, permission: "reports.view" },
        { href: "/operator/settings/organization", label: n.organization, icon: Building2, permission: "reports.view" },
      ],
    },
  ];
}

export function platformNav(t: Dictionary): NavGroup[] {
  const n = t.nav;
  return [
    {
      items: [
        { href: "/platform", label: n.overview, icon: Activity, exact: true },
        { href: "/platform/tenants", label: n.tenants, icon: Building2 },
        { href: "/platform/audit", label: n.platformAudit, icon: ListChecks },
      ],
    },
  ];
}

export function filterNav(groups: NavGroup[], can: (p: string) => boolean): NavGroup[] {
  return groups.map((g) => ({ ...g, items: g.items.filter((i) => !i.permission || can(i.permission)) })).filter((g) => g.items.length);
}
