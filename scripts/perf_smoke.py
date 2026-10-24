"""Bounded local performance smoke for critical API paths (Phase 3, E).

Usage (local Docker stack running, after the Playwright global setup created e2e sessions):
    python scripts/perf_smoke.py [--requests 120] [--concurrency 10]

Load is deliberately small (default 120 requests per endpoint, 10 in flight) so the developer machine and
the running services stay usable, and stays under the per-user API throttle (600/min). It measures latency
of the dockerised dev server on this machine only; it is NOT a capacity or production benchmark.
"""

import argparse
import json
import statistics
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# 127.0.0.1, not localhost: on Windows "localhost" tries ::1 first and the dev port is bound to IPv4 only (+~200 ms).
API = "http://127.0.0.1:8010"
ROOT = Path(__file__).resolve().parent.parent
AUTH = ROOT / "apps" / "admin" / "e2e" / ".auth"


def call(method, path, token=None, app=None, body=None):
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if app:
        headers["X-RideFlow-App"] = app
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, headers=headers, method=method)
    start = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            res.read()
            status = res.status
    except urllib.error.HTTPError as exc:
        exc.read()
        status = exc.code
    except Exception:  # connection reset / timeout
        status = 0
    return status, (time.perf_counter() - start) * 1000


def otp_login(app, phone):
    call("POST", "/api/v1/auth/otp/request", app=app, body={"phone": phone})
    req = urllib.request.Request(
        API + "/api/v1/auth/otp/verify",
        data=json.dumps({"phone": phone, "code": "000000"}).encode(),
        headers={"Content-Type": "application/json", "X-RideFlow-App": app},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.loads(res.read())["access"]


def run(name, fn, n, concurrency):
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        start = time.perf_counter()
        results = list(pool.map(lambda _: fn(), range(n)))
        wall = time.perf_counter() - start
    lat = sorted(ms for _, ms in results)
    codes = {}
    for status, _ in results:
        codes[status] = codes.get(status, 0) + 1
    q = statistics.quantiles(lat, n=100)
    return {
        "endpoint": name,
        "requests": n,
        "concurrency": concurrency,
        "status_counts": codes,
        "p50_ms": round(q[49], 1),
        "p95_ms": round(q[94], 1),
        "max_ms": round(lat[-1], 1),
        "throughput_rps": round(n / wall, 1),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--requests", type=int, default=120)
    parser.add_argument("--concurrency", type=int, default=10)
    args = parser.parse_args()
    seed = json.loads((AUTH / "seed.json").read_text())
    owner = next(c["value"] for c in json.loads((AUTH / "owner.json").read_text())["cookies"] if c["name"] == "rf_at")
    admin_app = seed["apps"]["admin"]
    rider = otp_login(seed["apps"]["rider"], "+967780" + str(int(time.time()))[-6:])
    c = seed["center"]
    estimate = {"pickup": {"lat": c["lat"], "lng": c["lng"]}, "dropoff": {"lat": c["lat"] + 0.02, "lng": c["lng"] + 0.02}}
    cases = [
        ("GET /health/ready", lambda: call("GET", "/health/ready")),
        ("GET /api/v1/me (rider)", lambda: call("GET", "/api/v1/me", rider, seed["apps"]["rider"])),
        ("POST /api/v1/fare-estimate (rider)", lambda: call("POST", "/api/v1/fare-estimate", rider, seed["apps"]["rider"], estimate)),
        ("GET /api/v1/admin/drivers (owner)", lambda: call("GET", "/api/v1/admin/drivers?page_size=25", owner, admin_app)),
        ("GET /api/v1/admin/dashboard (owner)", lambda: call("GET", "/api/v1/admin/dashboard", owner, admin_app)),
        ("GET /api/v1/admin/audit-events (owner)", lambda: call("GET", "/api/v1/admin/audit-events?page_size=30", owner, admin_app)),
    ]
    report = [run(name, fn, args.requests, args.concurrency) for name, fn in cases]
    json.dump(report, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
