#!/usr/bin/env python3
"""Run the full route test inside the WEB build (as on GitHub Pages), optionally on the throttled phone profile.

  python3 tools/perf/web_route.py build/web [--profile desktop|phone4g]

Prints the route results plus the game's own [profile] / [memory] / [packs] log lines.
"""
import argparse, json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from measure_web import serve, PROFILES
from playwright.sync_api import sync_playwright

ap = argparse.ArgumentParser()
ap.add_argument("root")
ap.add_argument("--profile", default="desktop")
a = ap.parse_args()
srv = serve(os.path.abspath(a.root))
url = "http://127.0.0.1:%d/index.html?autotest" % srv.server_address[1]
exe = [os.path.join(dp, "chrome") for dp, _, fs in os.walk("/opt/pw-browsers") if "chrome" in fs and "headless" not in dp][0]
logs = []
with sync_playwright() as pw:
    b = pw.chromium.launch(executable_path=exe, args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
    ctx = b.new_context(viewport={"width": 915, "height": 412}, is_mobile=a.profile != "desktop", has_touch=True)
    page = ctx.new_page()
    cdp = ctx.new_cdp_session(page)
    p = PROFILES[a.profile]
    if p["net"]:
        cdp.send("Network.enable")
        cdp.send("Network.emulateNetworkConditions", {"offline": False, "downloadThroughput": p["net"]["download"], "uploadThroughput": p["net"]["upload"], "latency": p["net"]["latency"]})
    cdp.send("Emulation.setCPUThrottlingRate", {"rate": p["cpu"]})
    page.on("console", lambda m: logs.append(m.text))
    t = time.time()
    page.goto(url)
    try:
        page.wait_for_function("window.__hl && window.__hl.done", timeout=3000000, polling=1000)
    except Exception as e:
        print("TIMEOUT", e)
    res = page.evaluate("window.__hl ? window.__hl.results : []")
    b.close()
ok = sum(1 for r in res if r["pass"])
for r in res:
    if not r["pass"]: print("FAIL", r["name"], r["detail"])
for l in logs:
    if l.startswith(("[profile]", "[memory]", "[packs]", "[load timing]")) or "ERROR" in l or "SCRIPT" in l: print(l)
print("WEB RESULT %d/%d PASS in %.0f s" % (ok, len(res), time.time() - t))
