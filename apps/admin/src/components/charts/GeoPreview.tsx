"use client";

/**
 * Schematic geographic preview (SVG, no external tiles): projects lon/lat into a box with an equirectangular
 * projection corrected for latitude. Used for zones, ride evidence and live drivers. Not a street map.
 */
export interface GeoPoint {
  lat: number;
  lng: number;
  label?: string;
  tone?: "pickup" | "dropoff" | "evidence" | "driver" | "center";
}

type Ring = [number, number][];

export function GeoPreview({ points = [], polygons = [], height = 260, label }: {
  points?: GeoPoint[];
  polygons?: Ring[];
  height?: number;
  label: string;
}) {
  const coords: [number, number][] = [...points.map((p) => [p.lng, p.lat] as [number, number]), ...polygons.flat()];
  if (!coords.length) return null;
  const lngs = coords.map((c) => c[0]);
  const lats = coords.map((c) => c[1]);
  let [minX, maxX, minY, maxY] = [Math.min(...lngs), Math.max(...lngs), Math.min(...lats), Math.max(...lats)];
  const k = Math.cos((((minY + maxY) / 2) * Math.PI) / 180) || 1;
  const pad = Math.max((maxX - minX) * k, maxY - minY, 0.004) * 0.15;
  minX -= pad / k;
  maxX += pad / k;
  minY -= pad;
  maxY += pad;
  const w = Math.max((maxX - minX) * k, 1e-6);
  const h = Math.max(maxY - minY, 1e-6);
  const W = 1000;
  const H = Math.max(200, Math.min(700, (W * h) / w));
  const sx = (lng: number) => ((lng - minX) * k * W) / w;
  const sy = (lat: number) => H - ((lat - minY) * H) / h;
  const color = { pickup: "#0F766E", dropoff: "#10243A", evidence: "#E9A23B", driver: "#0D9488", center: "#E45858" };

  return (
    <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={label} className="w-full rounded-md border border-line bg-[#f8fafc]" style={{ height }} preserveAspectRatio="xMidYMid meet">
      <defs>
        <pattern id="rf-grid" width="50" height="50" patternUnits="userSpaceOnUse">
          <path d="M50 0H0V50" fill="none" stroke="#e3e8ef" strokeWidth="1" />
        </pattern>
      </defs>
      <rect width={W} height={H} fill="url(#rf-grid)" />
      {polygons.map((ring, i) => (
        <polygon key={i} points={ring.map(([x, y]) => `${sx(x)},${sy(y)}`).join(" ")} fill="#0D948822" stroke="#0F766E" strokeWidth="3" strokeLinejoin="round" />
      ))}
      {points.filter((p) => p.tone === "pickup" || p.tone === "dropoff").length === 2 ? (
        <line
          x1={sx(points.find((p) => p.tone === "pickup")!.lng)}
          y1={sy(points.find((p) => p.tone === "pickup")!.lat)}
          x2={sx(points.find((p) => p.tone === "dropoff")!.lng)}
          y2={sy(points.find((p) => p.tone === "dropoff")!.lat)}
          stroke="#9cb0c8"
          strokeWidth="3"
          strokeDasharray="10 8"
        />
      ) : null}
      {points.map((p, i) => (
        <g key={i}>
          <circle cx={sx(p.lng)} cy={sy(p.lat)} r={p.tone === "evidence" ? 7 : 11} fill={color[p.tone ?? "driver"]} stroke="#fff" strokeWidth="3">
            {p.label ? <title>{p.label}</title> : null}
          </circle>
        </g>
      ))}
    </svg>
  );
}

/** Extracts outer rings from a GeoJSON Polygon/MultiPolygon. */
export function ringsOf(geometry: unknown): Ring[] {
  const g = geometry as { type?: string; coordinates?: unknown } | null;
  if (!g || !Array.isArray(g.coordinates)) return [];
  if (g.type === "Polygon") return [(g.coordinates as Ring[])[0] ?? []];
  if (g.type === "MultiPolygon") return (g.coordinates as Ring[][]).map((poly) => poly[0] ?? []);
  return [];
}
