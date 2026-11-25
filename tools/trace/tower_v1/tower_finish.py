#!/usr/bin/env python3
"""Tower v1, after tower_build.py (the facility finish, for a city tower): fleet_ways, fleet_formula (the cards, the
way out by the Sky Exit), the lift and the stairs through all ten floors, to_deck_json --decks --pilot-h 16 ->
assets/facilities/<tid>.json (+ each floor's map picture), then the tower marks: info.tower, every room a pilot room,
the floors' names, and the TARGET moved down into a room on a lower floor (owner: "looking for someone in a certain
room ... once you get it, you leave").
usage (from the repo root): python3 -I tools/trace/tower_v1/tower_finish.py <tid>"""
import json, os, shutil, subprocess, sys, hashlib
HERE = os.path.dirname(os.path.abspath(__file__)); TR = os.path.join(HERE, ".."); REPO = os.path.abspath(os.path.join(TR, "..", ".."))
tid = sys.argv[1]
eng = os.path.join(TR, "fleet_" + tid, "eng")
py = lambda *a: subprocess.run([sys.executable, "-I"] + list(a), cwd=REPO, check=True)
g1 = os.path.join(eng, "gameplay_v1.json")
json.dump(json.load(open(g1)), open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
py(os.path.join(TR, "fleet_ways.py"), tid)
py(os.path.join(TR, "fleet_formula.py"), tid)
T = json.load(open(os.path.join(eng, "tower.json")))
n = int(T["floors"])
G = json.load(open(os.path.join(eng, "gameplay.json")))
SH = json.load(open(os.path.join(eng, "shafts.json")))
G["elevators"] = [{"decks": sh["decks"], "at": sh["at"], "label": sh["label"], "need": {}} for sh in SH if sh["at"]]
G["deck_names"] = dict(T["names"])
json.dump(G, open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
out = os.path.join("assets", "facilities", tid + ".json")
py(os.path.join(TR, "to_deck_json.py"), os.path.join("tools", "trace", "fleet_" + tid), "--decks", "--pilot-h", str(T["pilot_h"]), "--out", out)
for dn in T["names"]:
    src_ = os.path.join(REPO, "assets", "holodeck", "%s_%s.jpg" % (tid, dn))
    if os.path.exists(src_): shutil.move(src_, os.path.join(REPO, "assets", "facilities", "%s_%s.jpg" % (tid, dn)))
p = os.path.join(REPO, out); D = json.load(open(p)); b = D["board"]
DY = 170.0
pre = {"main": "", "lower": "l_"}
for i in range(2, 10): pre["lower%d" % i] = "l%d_" % i
ys = {"main": 0.0, "lower": -DY}
for i in range(2, 10): ys["lower%d" % i] = -i * DY
b["info"]["facility"] = True
b["info"]["tower"] = True
b["info"]["station"] = False
b["info"]["difficulty"] = 1
b["info"]["deck_names"] = sorted([[ys[k], v] for k, v in T["names"].items()], key=lambda x: x[0])
# every room a pilot room (no mech fits in a building)
for k, r in b["rooms"].items():
    if r.get("kind") != "lift" and not r.get("pilot") and not k.endswith("r_roof_dock"):   # (the roof dock: the mech lands and parks there)
        r["pilot"] = True; r["h"] = min(float(r.get("h", 100.0)), max(float(T["pilot_h"]), 16.0)) if r.get("label") not in ("CORRIDOR",) else float(T["pilot_h"])
# the target: a room on a lower floor (picked by the tower's id; the game may re-pick per run)
f = b["fleet"]
h = int(hashlib.md5(tid.encode()).hexdigest(), 16)
dk = "lower%d" % (2 + h % (n - 3)) if n > 4 else "lower"
cand = sorted(k for k, v in b["rooms"].items() if k.startswith(pre[dk] + "r_") and v.get("kind") != "lift" and "lift" not in k and "stairs" not in k)
if cand:
    kt = cand[(h // 7) % len(cand)]; rr = b["rooms"][kt]["r"]; yy = float(b["rooms"][kt]["y"][0])
    for t in f["targets"].values():
        t["room"] = kt; t["at"] = [(rr[0] + rr[1]) / 2, yy, (rr[2] + rr[3]) / 2]
    print(tid, "target in", kt, "on", T["names"][dk])
shutil.copy(os.path.join(TR, "fleet_" + tid, "source.jpg"), os.path.join(REPO, "assets", "facilities", tid + "_map.jpg"))
files = {T["names"]["main"]: tid + "_map.jpg"}
for k, v in T["names"].items():
    if k != "main": files[v] = "%s_%s.jpg" % (tid, k)
b["info"]["deck_maps"] = {k: v for k, v in files.items() if os.path.exists(os.path.join(REPO, "assets", "facilities", v))}
json.dump(D, open(p, "w"), separators=(",", ":"))
print(tid, "tower floors:", len(b["info"]["deck_names"]), "maps:", len(b["info"]["deck_maps"]), "%.1f MB" % (os.path.getsize(p) / 1e6))
