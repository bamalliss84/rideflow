"use client";

import { useEffect, useRef, useState } from "react";

import { GeoPreview, type GeoPoint } from "@/components/charts/GeoPreview";

/**
 * Map adapter. The provider is configuration, not code: any XYZ raster tile service works through
 * NEXT_PUBLIC_MAP_TILE_URL (a `{z}/{x}/{y}` template) and NEXT_PUBLIC_MAP_ATTRIBUTION (required by most
 * providers' terms). Whatever is in the URL is visible to the browser, so a provider key placed there must be a
 * public, referrer-restricted key. Without configuration the page says so and falls back to the schematic
 * preview instead of pretending to be a street map.
 */
export const mapConfig = {
  tileUrl: process.env.NEXT_PUBLIC_MAP_TILE_URL ?? "",
  attribution: process.env.NEXT_PUBLIC_MAP_ATTRIBUTION ?? "",
};
export const mapConfigured = /\{z\}.*\{x\}.*\{y\}/.test(mapConfig.tileUrl);

const TILE = 256;
const MAX_ZOOM = 18;

// Web Mercator, in pixels at zoom z.
const px = (lng: number, z: number) => ((lng + 180) / 360) * TILE * 2 ** z;
const py = (lat: number, z: number) => {
  const s = Math.sin((Math.max(-85, Math.min(85, lat)) * Math.PI) / 180);
  return (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * TILE * 2 ** z;
};

const markerColor: Record<NonNullable<GeoPoint["tone"]>, string> = {
  pickup: "#0F766E",
  dropoff: "#10243A",
  evidence: "#E9A23B",
  driver: "#0D9488",
  center: "#E45858",
};

export function MapView({ points, height = 380, label, notConfiguredHint }: { points: GeoPoint[]; height?: number; label: string; notConfiguredHint: string }) {
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => e && setWidth(Math.round(e.contentRect.width)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  if (!mapConfigured) {
    return (
      <div>
        <GeoPreview height={height} label={label} points={points} />
        <p className="mt-2 text-xs text-muted" data-testid="map-not-configured">
          {notConfiguredHint}
        </p>
      </div>
    );
  }

  const pts = points.length ? points : [];
  const lats = pts.map((p) => p.lat);
  const lngs = pts.map((p) => p.lng);
  const [minLat, maxLat, minLng, maxLng] = [Math.min(...lats), Math.max(...lats), Math.min(...lngs), Math.max(...lngs)];
  // Highest zoom at which every point fits with a margin.
  let z = MAX_ZOOM;
  const margin = 48;
  while (z > 2 && width > 0 && (px(maxLng, z) - px(minLng, z) > width - 2 * margin || py(minLat, z) - py(maxLat, z) > height - 2 * margin)) z--;
  if (pts.length === 1) z = Math.min(z, 15);
  const cx = (px(minLng, z) + px(maxLng, z)) / 2;
  const cy = (py(minLat, z) + py(maxLat, z)) / 2;
  const left = cx - width / 2;
  const top = cy - height / 2;
  const n = 2 ** z;
  const tiles: { x: number; y: number; key: string }[] = [];
  if (width > 0 && pts.length) {
    for (let tx = Math.floor(left / TILE); tx <= Math.floor((left + width) / TILE); tx++) {
      for (let ty = Math.floor(top / TILE); ty <= Math.floor((top + height) / TILE); ty++) {
        if (ty < 0 || ty >= n) continue;
        tiles.push({ x: tx, y: ty, key: `${z}/${tx}/${ty}` });
      }
    }
  }
  const src = (x: number, y: number) =>
    mapConfig.tileUrl.replace("{z}", String(z)).replace("{x}", String(((x % n) + n) % n)).replace("{y}", String(y));

  return (
    <div ref={box} role="img" aria-label={label} className="relative w-full overflow-hidden rounded-xl border border-line bg-navy-50" style={{ height }} dir="ltr">
      {tiles.map((t) => (
        // eslint-disable-next-line @next/next/no-img-element -- raw tiles from the configured provider
        <img
          key={t.key}
          src={src(t.x, t.y)}
          alt=""
          width={TILE}
          height={TILE}
          draggable={false}
          className="pointer-events-none absolute max-w-none select-none"
          style={{ left: t.x * TILE - left, top: t.y * TILE - top }}
        />
      ))}
      {width > 0 &&
        pts.map((p, i) => (
          <span
            key={i}
            title={p.label}
            className="absolute -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-white shadow"
            style={{
              left: px(p.lng, z) - left,
              top: py(p.lat, z) - top,
              width: p.tone === "center" ? 12 : 16,
              height: p.tone === "center" ? 12 : 16,
              background: markerColor[p.tone ?? "driver"],
            }}
          />
        ))}
      {mapConfig.attribution ? (
        <span className="absolute right-1 bottom-1 rounded bg-white/85 px-1.5 py-0.5 text-[10px] text-slate-700">{mapConfig.attribution}</span>
      ) : null}
    </div>
  );
}
