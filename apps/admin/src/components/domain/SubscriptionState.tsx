"use client";

import { useState } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { Badge } from "@/components/ui/Badge";
import type { Schemas } from "@/lib/api/client";

export function SubscriptionState({ sub }: { sub: Schemas["DriverSubscription"] }) {
  const { t } = useI18n();
  const [now] = useState(() => Date.now());
  if (sub.is_revoked) return <Badge tone="neutral">{t.subscriptions.revoked}</Badge>;
  if (new Date(sub.ends_at).getTime() < now) return <Badge tone="neutral">{t.subscriptions.expiredLabel}</Badge>;
  if (new Date(sub.starts_at).getTime() > now) return <Badge tone="info">{t.subscriptions.upcoming}</Badge>;
  return <Badge tone="success">{t.subscriptions.current}</Badge>;
}
