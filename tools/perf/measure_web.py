#!/usr/bin/env python3
"""Measure the Homelancer web build the way a player gets it: cold and warm loads, on desktop and on a throttled
'phone' profile, with every network request listed.

  python3 tools/perf/measure_web.py build/web [--profiles desktop,phone4g,phone3g] [--out report.json]

The build is served like GitHub Pages does it (gzip for wasm/js/html/pck when the browser asks for it).
Load phases come from the loading screen (window.__loadTiming: download / engine start / scene build).
'phone' profiles = CPU slowed 4x + a mobile network; they are an estimate, a real phone's GPU and browser differ.
"""
import argparse, gzip, http.server, io, json, os, socketserver, threading, time
from playwright.sync_api import sync_playwright

GZIP_TYPES = (".wasm", ".js", ".html", ".pck")
PROFILES = {
    "desktop": {"cpu": 1, "net": None},
    "phone4g": {"cpu": 4, "net": {"download": 9e6 / 8, "upload": 1.5e6 / 8, "latency": 85}},     # typical LTE
    "phone3g": {"cpu": 4, "net": {"download": 1.6e6 / 8, "upload": 0.75e6 / 8, "latency": 150}},  # weak signal
}


def serve(root):
    class H(http.server.SimpleHTTPRequestHandler):
        def __init__(s, *a, **k): super().__init__(*a, directory=root, **k)
        def log_message(s, *a): pass
        def send_head(s):
            path = s.translate_path(s.path.split("?")[0])
            if os.path.isdir(path): path = os.path.join(path, "index.html")
            if path.endswith(GZIP_TYPES) and "gzip" in s.headers.get("Accept-Encoding", "") and os.path.exists(path):
                raw = open(path, "rb").read()
                gz = _gz_cache.get(path) or gzip.compress(raw, 6)
                _gz_cache[path] = gz
                s.send_response(200)
                s.send_header("Content-Type", s.guess_type(path))
                s.send_header("Content-Encoding", "gzip")
                s.send_header("Content-Length", str(len(gz)))
                s.send_header("Cache-Control", "max-age=600")   # what GitHub Pages sends
                s.end_headers()
                return io.BytesIO(gz)
            return super().send_head()
        def end_headers(s):
            if not any(h.startswith(b"Cache-Control") for h in getattr(s, "_headers_buffer", [])):
                s.send_header("Cache-Control", "max-age=600")
            super().end_headers()
    H.extensions_map[".wasm"] = "application/wasm"
    srv = socketserver.ThreadingTCPServer(("127.0.0.1", 0), H)
    srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


_gz_cache = {}


def run(url, prof, pw, exe, args):
    # a real on-disk profile, so the warm load uses the browser's HTTP cache like a phone would
    import tempfile
    ctx = pw.chromium.launch_persistent_context(tempfile.mkdtemp(), executable_path=exe, args=args,
        viewport={"width": 915, "height": 412}, is_mobile=prof != "desktop", has_touch=prof != "desktop", device_scale_factor=1)
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    cdp = ctx.new_cdp_session(page)
    cdp.send("Network.enable")
    p = PROFILES[prof]
    if p["net"]:
        cdp.send("Network.emulateNetworkConditions", {"offline": False, "downloadThroughput": p["net"]["download"],
                 "uploadThroughput": p["net"]["upload"], "latency": p["net"]["latency"]})
    cdp.send("Emulation.setCPUThrottlingRate", {"rate": p["cpu"]})
    out = {}
    for kind in ["cold", "warm"]:
        reqs = {}
        def on_resp(ev, reqs=reqs):
            r = ev["response"]
            reqs[ev["requestId"]] = {"url": r["url"].split("/")[-1] or "/", "status": r["status"], "cached": r.get("fromDiskCache", False) or r.get("fromMemoryCache", False)}
        def on_cache(ev, reqs=reqs):
            reqs.setdefault(ev["requestId"], {"url": "?"})["cached"] = True
        def on_done(ev, reqs=reqs):
            if ev["requestId"] in reqs: reqs[ev["requestId"]]["transfer"] = ev["encodedDataLength"]
        def on_fail(ev, reqs=reqs):
            reqs.setdefault(ev["requestId"], {"url": "?"})["failed"] = ev.get("errorText")
        cdp.on("Network.responseReceived", on_resp)
        cdp.on("Network.loadingFinished", on_done)
        cdp.on("Network.loadingFailed", on_fail)
        cdp.on("Network.requestServedFromCache", on_cache)
        t = time.time()
        if kind == "cold": page.goto(url)
        else: page.goto("about:blank"); page.goto(url)   # come back later = a new visit, not a forced reload
        try:
            page.wait_for_function("window.__loadTiming !== undefined || document.getElementById('error').textContent.length > 0", timeout=600000, polling=500)
        except Exception as e:
            out[kind] = {"error": "timeout " + str(e)[:80]}
            continue
        lt = page.evaluate("window.__loadTiming || null")
        err = page.evaluate("document.getElementById('error').textContent")
        heap = cdp.send("Performance.getMetrics") if False else None
        out[kind] = {"wall_s": round(time.time() - t, 1), "phases_ms": lt, "error": err,
                     "requests": len(reqs), "failed": [r for r in reqs.values() if r.get("failed")],
                     "transfer_MB": round(sum(r.get("transfer", 0) for r in reqs.values() if not r.get("cached")) / 1e6, 2),
                     "files": sorted(reqs.values(), key=lambda r: -r.get("transfer", 0))[:8]}
        time.sleep(1.0)
    ctx.close()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("--profiles", default="desktop,phone4g,phone3g")
    ap.add_argument("--out")
    a = ap.parse_args()
    srv = serve(os.path.abspath(a.root))
    url = "http://127.0.0.1:%d/index.html" % srv.server_address[1]
    exe = [os.path.join(dp, "chrome") for dp, _, fs in os.walk("/opt/pw-browsers") if "chrome" in fs and "headless" not in dp][0]
    res = {}
    with sync_playwright() as pw:
        for prof in a.profiles.split(","):
            res[prof] = run(url, prof, pw, exe, ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
            print(prof, json.dumps({k: {kk: v[kk] for kk in ("wall_s", "phases_ms", "requests", "transfer_MB", "failed", "error") if kk in v} for k, v in res[prof].items()}))
    if a.out: json.dump(res, open(a.out, "w"), indent=1)


if __name__ == "__main__":
    main()
