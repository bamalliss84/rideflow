// Rider side of the end-to-end driver-app journey (local stack only).
// Requests a ride at PICKUP (default: emulator GPS in Mukalla), waits for a driver bid, selects it, then
// follows the ride to completion and confirms cash as the rider. Prints a JSON timeline.
//   node scripts/rider_flow.mjs
const API = process.env.API_URL ?? "http://127.0.0.1:8010";
const APP = process.env.RIDER_APP ?? "demo-mukalla-rider";
const PHONE = process.env.RIDER_PHONE ?? "+967711000001";
const [lat, lng] = (process.env.PICKUP ?? "14.5426,49.1242").split(",").map(Number);
const WAIT_BID_S = Number(process.env.WAIT_BID_SECONDS ?? 300);
const t0 = Date.now();
const log = (event, data = {}) => console.log(JSON.stringify({ t: ((Date.now() - t0) / 1000).toFixed(1), event, ...data }));

async function call(path, body, token) {
  const r = await fetch(`${API}/api/v1/${path}`, {
    method: body ? "POST" : "GET",
    headers: { "Content-Type": "application/json", "X-RideFlow-App": APP, "Idempotency-Key": crypto.randomUUID(), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, data: await r.json().catch(() => null) };
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Reuse the last session while it is valid: re-runs stay within the OTP rate limit (5 requests/hour/phone).
const { existsSync, readFileSync, writeFileSync } = await import("node:fs");
const { tmpdir } = await import("node:os");
const cacheFile = `${tmpdir()}/rideflow_rider_e2e_${APP}.json`;
let token = existsSync(cacheFile) ? JSON.parse(readFileSync(cacheFile, "utf8")).access : null;
if (!token || (await call("me", null, token)).status !== 200) {
  await call("auth/otp/request", { phone: PHONE });
  const login = await call("auth/otp/verify", { phone: PHONE, code: "000000" });
  if (login.status !== 200) throw new Error(`rider login ${login.status} ${JSON.stringify(login.data)}`);
  token = login.data.access;
  writeFileSync(cacheFile, JSON.stringify({ access: token }));
}

// Clean up a leftover active ride of this demo rider (one active ride per rider).
for (const r of (await call("rides?page_size=50", null, token)).data?.results ?? []) {
  if (r.allowed_actions?.includes("rider_cancel")) {
    await call(`rides/${r.id}/cancel`, { expected_version: r.version, reason: "e2e cleanup" }, token);
  }
}

const ride = await call("rides", { pickup: { lat, lng }, pickup_landmark: "قرب جامع المحضار، الشرج", dropoff: { lat: lat + 0.012, lng: lng + 0.015 }, dropoff_landmark: "سوق المكلا المركزي" }, token);
if (ride.status !== 201) throw new Error(`create ride ${ride.status} ${JSON.stringify(ride.data)}`);
const id = ride.data.id;
log("ride_requested", { id, status: ride.data.status });

let bid = null;
for (let i = 0; i < WAIT_BID_S && !bid; i += 2) {
  const bids = await call(`rides/${id}/bids`, null, token);
  bid = (bids.data?.results ?? bids.data ?? []).find((b) => b.status === "open") ?? null;
  if (!bid) await sleep(2000);
}
if (!bid) throw new Error("no bid received");
log("bid_received", { amount_minor: bid.amount_minor, eta_seconds: bid.eta_seconds });
await sleep(2500);
const snap = await call(`rides/${id}`, null, token);
const sel = await call(`rides/${id}/select`, { bid_id: bid.id, expected_version: snap.data.version }, token);
log("selected", { status: sel.status, ride_status: sel.data?.status, version: sel.data?.version });

let last = "";
for (let i = 0; i < 240; i++) {
  const r = (await call(`rides/${id}`, null, token)).data;
  if (r.status !== last) {
    last = r.status;
    log("status", { status: r.status, version: r.version });
  }
  if (r.status === "completed") {
    const cash = await call(`rides/${id}/cash-confirm`, {}, token);
    log("rider_cash_confirm", { status: cash.status });
    break;
  }
  if (["cancelled", "no_show"].includes(r.status)) break;
  await sleep(1500);
}
const events = (await call(`rides/${id}/events`, null, token)).data;
log("events", { list: (events?.results ?? events ?? []).map((e) => `${e.event_type}:${e.to_status || ""}`) });
