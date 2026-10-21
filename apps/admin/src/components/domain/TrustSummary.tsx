"use client";

import { Award } from "lucide-react";

import { useI18n } from "@/components/providers/I18nProvider";
import { useSession } from "@/components/providers/SessionProvider";
import { Badge, type Tone } from "@/components/ui/Badge";
import { Card, CardHeader } from "@/components/ui/Card";
import type { Page, Schemas } from "@/lib/api/client";
import { useApi } from "@/lib/api/hooks";

import { enumLabel, Stars } from "./Display";

type Snapshot = Schemas["TrustSnapshot"];

export const TIER_TONE: Record<string, Tone> = { new: "neutral", bronze: "warning", silver: "info", gold: "warning", diamond: "success" };

export function TrustSummary({ userId, role }: { userId: string; role: "driver" | "rider" }) {
  const { t } = useI18n();
  const { fmt } = useSession();
  const q = useApi<Page<Snapshot>>("admin/trust-snapshots", { user: userId, role });
  const s = q.data?.results[0];
  return (
    <Card padded={false}>
      <CardHeader title={t.drivers.trust} icon={<Award className="size-4" />} />
      {s ? (
        <div className="space-y-3 p-5 text-sm">
          <div className="flex items-center justify-between">
            <span className="text-3xl font-semibold ltr-nums">{fmt.number(s.score)}</span>
            <Badge tone={TIER_TONE[s.tier] ?? "neutral"}>{enumLabel(t, "tier", s.tier)}</Badge>
          </div>
          <div className="flex items-center justify-between gap-3">
            <span className="text-muted">{t.trust.ratingAvg}</span>
            <span className="flex items-center gap-2">
              <Stars value={Math.round(s.rating_avg)} />
              <span className="ltr-nums">
                {s.rating_avg.toFixed(2)} ({fmt.number(s.rating_count)})
              </span>
            </span>
          </div>
          <div className="flex justify-between gap-3">
            <span className="text-muted">{t.trust.completedRides}</span>
            <span className="ltr-nums">{fmt.number(s.completed_rides)}</span>
          </div>
          <div className="flex justify-between gap-3">
            <span className="text-muted">{t.trust.completionRate}</span>
            <span className="ltr-nums">{fmt.percent(s.completion_rate)}</span>
          </div>
        </div>
      ) : (
        <p className="px-5 py-6 text-center text-sm text-muted">{q.isPending ? t.common.loading : t.common.emptyTitle}</p>
      )}
    </Card>
  );
}
