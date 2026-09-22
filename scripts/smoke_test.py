#!/usr/bin/env python3
"""
Smoke test the deployed contact-form app end to end.

Port-forwards the Service and exercises the real HTTP endpoints:
  * GET  /healthz     -> liveness
  * GET  /readyz      -> DB connectivity (readiness)
  * POST /contact     -> writes a row to PostgreSQL
  * GET  /submissions -> reads it back

Usage: ./smoke_test.py -n contact-app
"""
import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def port_forward(namespace, svc, local_port, remote_port):
    proc = subprocess.Popen(
        ["kubectl", "-n", namespace, "port-forward",
         f"svc/{svc}", f"{local_port}:{remote_port}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    time.sleep(4)
    return proc


def _request(req_or_url):
    try:
        with urllib.request.urlopen(req_or_url, timeout=10) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        # A non-2xx response is a valid observation, not a crash.
        return e.code, e.read().decode(errors="replace")


def get(url):
    return _request(url)


def post_form(url, data):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body, method="POST")
    return _request(req)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", "--namespace", default="contact-app")
    ap.add_argument("--service", default="contact-app")
    ap.add_argument("--port", type=int, default=18080)
    args = ap.parse_args()

    base = f"http://127.0.0.1:{args.port}"
    pf = port_forward(args.namespace, args.service, args.port, 80)
    failures = []
    try:
        code, _ = get(f"{base}/healthz")
        print(f"[healthz] {code}")
        failures += [] if code == 200 else ["healthz"]

        code, _ = get(f"{base}/readyz")
        print(f"[readyz]  {code}")
        failures += [] if code == 200 else ["readyz"]

        marker = f"smoke-{int(time.time())}"
        code, _ = post_form(f"{base}/contact", {
            "name": "Smoke Test", "email": "smoke@example.com",
            "message": marker,
        })
        print(f"[contact] {code}")

        code, body = get(f"{base}/submissions")
        rows = json.loads(body).get("submissions", [])
        found = any(r.get("message") == marker for r in rows)
        print(f"[submissions] {code} rows={len(rows)} round-trip={'OK' if found else 'MISSING'}")
        if not found:
            failures.append("round-trip")
    finally:
        pf.terminate()

    if failures:
        sys.exit(f"SMOKE TEST FAILED: {', '.join(failures)}")
    print("\nSMOKE TEST PASSED")


if __name__ == "__main__":
    main()
