#!/usr/bin/env python3
"""One fleet ship, plan PNG -> walkable three-deck boarding stage, start to finish (v13.03 batch build).

  python3 build_ship.py <HL_<Faction><Class>_HoloDeck_..png> [debug_dir]

Runs the steps in README.md in order: auto_seeds (OCR first pass; kept if seeds/<id>.json already exists, so a
hand-fixed seed file is never overwritten) -> extract -> the plan copied to assets/holodeck as .jpg -> trace ->
decks. Prints one line of gates: labelled rooms, rooms cut off, auto-links, decks, deck missions. A ship passes
when the start is good, no labelled room is cut off and it has at least the sabotage and capture missions.
"""
import json, os, re, subprocess, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
def run(*a):
    p = subprocess.run([sys.executable] + list(a), capture_output=True, text=True, cwd=ROOT)
    return p.returncode, (p.stdout + p.stderr).strip()
def main(png, dbg=None):
    m = re.match(r"HL_([A-Z][a-z]+)([A-Za-z]+)_HoloDeck_", os.path.basename(png))
    sid = "%s_%s" % (m.group(1).lower(), m.group(2).lower())
    seeds = os.path.join(HERE, "seeds", sid + ".json"); out = os.path.join(ROOT, "assets", "holodeck", sid + ".json")
    dbg = dbg or "/tmp"; res = {"id": sid, "ok": False}
    if not os.path.exists(seeds):
        rc, o = run(os.path.join(HERE, "auto_seeds.py"), png, seeds)
        if rc: res["fail"] = "auto_seeds: " + o[-200:]; print(json.dumps(res)); return res
    rc, o = run(os.path.join(HERE, "extract.py"), png, seeds, out, os.path.join(dbg, sid + "_extract.png"))
    if rc: res["fail"] = "extract: " + o[-300:]; print(json.dumps(res)); return res
    jpg = os.path.join(ROOT, "assets", "holodeck", os.path.basename(png)[:-4] + ".jpg")
    Image.open(png).convert("RGB").save(jpg, quality=88)
    rc, o = run(os.path.join(HERE, "trace.py"), png, out, os.path.join(dbg, sid + "_trace.png"), seeds)
    if rc: res["fail"] = "trace: " + o[-300:]; print(json.dumps(res)); return res
    tr = json.loads(o.splitlines()[-1])
    rc, o = run(os.path.join(HERE, "decks.py"), out, os.path.join(ROOT, "assets", "holodeck"), os.path.join(dbg, sid + "_decks.jpg"))
    if rc: res["fail"] = "decks: " + o[-300:]; print(json.dumps(res)); return res
    dk = json.loads(o.splitlines()[-1]); d = json.load(open(out))
    res.update({"rooms_main": len(d["rooms"]), "names": [r["name"] for r in d["rooms"]], "cut_off": tr["cut_off"], "links": tr["links"], "start_ok": tr["start_ok"],
                "decks": dk["decks"], "missions": sorted(dk["objectives"].keys())})
    res["ok"] = bool(tr["start_ok"]) and not tr["cut_off"] and {"sabotage", "capture"} <= set(dk["objectives"].keys()) and len(d["rooms"]) >= 6
    print(json.dumps(res)); return res
if __name__ == "__main__": main(*sys.argv[1:3])
