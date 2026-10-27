// WebSocket stability soak against the local stack (Phase 4 P0 verification).
// Holds one authenticated /ws/v1/events/ connection like the driver app (Origin = API origin, ping every 25 s),
// counts disconnects for SOAK_SECONDS, then triggers a real event and waits for the hint.
//   node scripts/ws_soak.mjs            (defaults: 300 s, http://127.0.0.1:8010, app e2e-qa-rider)
const API = process.env.API_URL ?? "http://127.0.0.1:8010";
const APP = process.env.APP_CLIENT_ID ?? "e2e-qa-rider";
const SOAK = Number(process.env.SOAK_SECONDS ?? 300);
const phone = `+96778${String(Date.now()).slice(-7)}`;

async function call(path, body, token) {
  const r = await fetch(`${API}/api/v1/${path}`, {
    method: body ? "POST" : "GET",
    headers: { "Content-Type": "application/json", "X-RideFlow-App": APP, "Idempotency-Key": crypto.randomUUID(), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, data: await r.json().catch(() => null) };
}

await call("auth/otp/request", { phone });
const login = await call("auth/otp/verify", { phone, code: "000000" });
if (login.status !== 200) throw new Error(`login failed ${login.status}`);
const token = login.data.access;

const started = Date.now();
let disconnects = 0, hints = [], connectedAt = null;
const url = `${API.replace("http", "ws")}/ws/v1/events/?token=${token}`;
const ws = new WebSocket(url, { headers: { Origin: API } });
const hinted = new Promise((resolve) => {
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.type === "hello") ws.send(JSON.stringify({ type: "resume", cursor: msg.cursor }));
    if (msg.type === "hint") {
      hints.push({ kind: msg.kind, at: ((Date.now() - started) / 1000).toFixed(1) });
      resolve(msg);
    }
  };
});
ws.onopen = () => (connectedAt = Date.now());
ws.onclose = (e) => {
  disconnects++;
  console.log(`DISCONNECT after ${((Date.now() - started) / 1000).toFixed(1)}s code=${e.code}`);
};
const ping = setInterval(() => ws.readyState === 1 && ws.send(JSON.stringify({ type: "ping" })), 25_000);

for (let s = 0; s < SOAK; s += 30) {
  await new Promise((r) => setTimeout(r, Math.min(30, SOAK - s) * 1000));
  console.log(`t=${Math.min(s + 30, SOAK)}s open=${ws.readyState === 1} disconnects=${disconnects}`);
}
// Real event: the rider's own ride request produces a hint on this connection.
const center = { lat: 14.7, lng: 49.35 };
const ride = await call("rides", { pickup: center, pickup_landmark: "WS soak", dropoff: { lat: 14.72, lng: 49.37 }, dropoff_landmark: "WS soak end" }, token);
const t0 = Date.now();
const hint = await Promise.race([hinted, new Promise((r) => setTimeout(() => r(null), 15_000))]);
clearInterval(ping);
const cancel = await call(`rides/${ride.data?.id}/cancel`, { expected_version: ride.data?.version, reason: "ws soak cleanup" }, token);
ws.close();
console.log(JSON.stringify({
  soak_seconds: SOAK,
  open_for_seconds: connectedAt ? Math.round((Date.now() - connectedAt) / 1000) : 0,
  disconnects_during_soak: disconnects,
  ride_created: ride.status,
  hint: hint ? { kind: hint.kind, latency_ms: Date.now() - t0 } : null,
  hints,
  cleanup_cancel: cancel.status,
}));
