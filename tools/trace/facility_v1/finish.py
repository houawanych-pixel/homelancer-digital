#!/usr/bin/env python3
"""Facility v1, after facility_build.py: the boarding pass and the game file (the station v2 steps).
  fleet_ways, fleet_formula (cards, the objective in the Command Center, the way out), the elevators (the four shafts
  through the three floors), the floor names, to_deck_json --decks -> assets/holodeck/<fid>.json, then the facility
  marks (info.facility, difficulty, the floors' names and map pictures).
usage (from the repo root): python3 -I tools/trace/facility_v1/finish.py <fid> <difficulty>"""
import json, os, shutil, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); TR = os.path.join(HERE, ".."); REPO = os.path.abspath(os.path.join(TR, "..", ".."))
sys.path.insert(0, os.path.join(TR, "station_v2"))
from station_build import LIFT_AT
fid, d = sys.argv[1], int(sys.argv[2])
eng = os.path.join(TR, "fleet_" + fid, "eng")
py = lambda *a: subprocess.run([sys.executable, "-I"] + list(a), cwd=REPO, check=True)
g1 = os.path.join(eng, "gameplay_v1.json")
if os.path.exists(g1): json.dump(json.load(open(g1)), open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
py(os.path.join(TR, "fleet_ways.py"), fid)
py(os.path.join(TR, "fleet_formula.py"), fid)
G = json.load(open(os.path.join(eng, "gameplay.json")))
decks = ["lower2", "lower", "main"]
PURPLE = d >= 3   # (owner: "3 to 4 key method", by difficulty: the hard facilities add the PURPLE card)
G["elevators"] = [{"decks": decks, "at": at, "label": "LIFT", "need": {"lower2": 4} if PURPLE else {}} for at in LIFT_AT]
G["deck_names"] = {"main": "ENTRY LEVEL", "lower": "SUB-LEVEL 1", "lower2": "SUB-LEVEL 2"}
json.dump(G, open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
out = os.path.join("assets", "facilities", fid + ".json")   # (the facilities' own download pack)
py(os.path.join(TR, "to_deck_json.py"), os.path.join("tools", "trace", "fleet_" + fid), "--decks", "--out", out)
for dn in ("lower", "lower2"):   # (to_deck_json writes the floors' map pictures into assets/holodeck: they go with the facility)
    src_ = os.path.join(REPO, "assets", "holodeck", "%s_%s.jpg" % (fid, dn))
    if os.path.exists(src_): shutil.move(src_, os.path.join(REPO, "assets", "facilities", "%s_%s.jpg" % (fid, dn)))
# the facility marks (as station_ship_deck.py does for a station)
p = os.path.join(REPO, out); D = json.load(open(p)); b = D["board"]
NAMES = {-340.0: "SUB-LEVEL 2", -170.0: "SUB-LEVEL 1", 0.0: "ENTRY LEVEL"}
ys = sorted({float(r["y"][0]) for r in b["rooms"].values()})
b["info"]["facility"] = True
b["info"]["station"] = False   # (to_deck_json marks every named-deck build a station: a facility is not one)
f = b["fleet"]
if PURPLE:
    # the PURPLE card: carried by someone behind the RED doors on the entry level (the game picks the room each run
    # among the red-level rooms); the lift down to SUB-LEVEL 2 needs it, and the objective is down there, in the
    # Reactor Hall
    lv = f.get("levels", {})
    reds = sorted([k for k, v in lv.items() if int(v) == 3 and not k.startswith(("l_", "l2_", "u_")) and k in b["rooms"] and b["rooms"][k].get("kind") != "lift"])
    k4 = reds[len(reds) // 2] if reds else f["cards"][-1]["room"]
    r4 = b["rooms"][k4]["r"]
    f["cards"].append({"room": k4, "key": 4, "at": [(r4[0] + r4[1]) / 2, 0.0, (r4[2] + r4[3]) / 2]})
    hub2 = next(k for k in b["rooms"] if k.startswith("l2_") and "reactor_hall" in k)
    rh = b["rooms"][hub2]["r"]; yh = float(b["rooms"][hub2]["y"][0])
    for t in f["targets"].values():
        t["room"] = hub2; t["at"] = [(rh[0] + rh[1]) / 2, yh, (rh[2] + rh[3]) / 2]; t["key"] = 4
    for t in D.get("objectives", {}).values(): t["need"] = 4
    print(fid, "PURPLE card in", k4, "- objective in", hub2)
b["info"]["difficulty"] = d
b["info"]["deck_names"] = [[y, NAMES[y]] for y in ys if y in NAMES]
shutil.copy(os.path.join(TR, "fleet_" + fid, "source.jpg"), os.path.join(REPO, "assets", "facilities", fid + "_map.jpg"))
files = {"ENTRY LEVEL": fid + "_map.jpg", "SUB-LEVEL 1": fid + "_lower.jpg", "SUB-LEVEL 2": fid + "_lower2.jpg"}
b["info"]["deck_maps"] = {k: v for k, v in files.items() if os.path.exists(os.path.join(REPO, "assets", "facilities", v))}
json.dump(D, open(p, "w"), separators=(",", ":"))
print(fid, "facility floors:", b["info"]["deck_names"], "maps:", list(b["info"]["deck_maps"]))
