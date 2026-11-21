#!/usr/bin/env python3
"""Station v2, after station_build.py: the boarding pass and the game file, the same steps as Liberty Hub.
  fleet_ways (mech / pilot ways), fleet_formula (cards, objective, way out), the elevators (the four shafts through all
  five decks, COMMAND needs RED) and deck names, to_deck_json --decks -> assets/holodeck/<sid>.json, station_ship_deck.
usage (from the repo root): python3 -I tools/trace/station_v2/finish.py <sid>"""
import json, os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); TR = os.path.join(HERE, ".."); REPO = os.path.abspath(os.path.join(TR, "..", ".."))
sys.path.insert(0, HERE)
from station_build import LIFT_AT
sid = sys.argv[1]
eng = os.path.join(TR, "fleet_" + sid, "eng")
py = lambda *a: subprocess.run([sys.executable, "-I"] + list(a), cwd=REPO, check=True)
g1 = os.path.join(eng, "gameplay_v1.json")
if os.path.exists(g1): json.dump(json.load(open(g1)), open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
py(os.path.join(TR, "fleet_ways.py"), sid)
py(os.path.join(TR, "fleet_formula.py"), sid)
G = json.load(open(os.path.join(eng, "gameplay.json")))
decks = [d for d in ("lower2", "lower", "main", "upper", "upper2") if d == "main" or os.path.exists(os.path.join(eng, "deck_%s.json" % d))]
# v13.248 (owner: "elevators in different places ... like a real building"): each shaft stops at only some decks.
# North: HANGAR-ENGINEERING-MAIN HUB, South: ENGINEERING-MAIN HUB, East: MAIN HUB-HABITAT, West: HABITAT-COMMAND (RED)
SERVE = [("NORTH LIFT", ["lower2", "lower", "main"]), ("SOUTH LIFT", ["lower", "main"]), ("EAST LIFT", ["main", "upper"]), ("WEST LIFT", ["upper", "upper2"])]
G["elevators"] = []
PL = json.load(open(os.path.join(eng, "plan.json")))["rooms"]
from shapely.geometry import shape as _shape
def _at(i, nm):   # (the station's own lift room on the main deck; Liberty Hub's south shaft sits lower than the rest)
    for k, v in PL.items():
        if k.lower() == ("lift (%s)" % nm).lower(): c = _shape(v).centroid; return [round(c.x), round(c.y)]
    return LIFT_AT[i]
for i, (label, ds) in enumerate(SERVE):
    at = _at(i, label.split()[0])
    ds = [x for x in ds if x in decks]
    if len(ds) >= 2: G["elevators"].append({"decks": ds, "at": at, "label": label, "need": {"upper2": 3} if "upper2" in ds else {"main": 0}})   # (an empty need would make HABITAT ask for YELLOW: it stays open, as before)
G["deck_names"] = {"main": "MAIN HUB DECK", "lower": "ENGINEERING DECK", "lower2": "HANGAR DECK", "upper": "HABITAT DECK", "upper2": "COMMAND DECK"}
G["deck_names"] = {k: v for k, v in G["deck_names"].items() if k in decks}
json.dump(G, open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
py(os.path.join(TR, "to_deck_json.py"), os.path.join("tools", "trace", "fleet_" + sid), "--decks", "--out", os.path.join("assets", "holodeck", sid + ".json"))
py(os.path.join(TR, "station_ship_deck.py"), sid)

# the lift rooms on decks their shaft does not stop at: a plain room (the shaft runs behind its wall)
p = os.path.join(REPO, "assets", "holodeck", sid + ".json"); D = json.load(open(p)); b = D["board"]
served = {k for e in b["fleet"].get("elev", []) for k in e["rooms"]}
n = 0
for k, r in b["rooms"].items():
    if "lift__" in k and k not in served and str(r.get("label", "")).startswith("LIFT"):
        r["label"] = "SHAFT ACCESS"; r.pop("kind", None) if r.get("kind") == "lift" else None; n += 1
json.dump(D, open(p, "w"), separators=(",", ":"))
print(sid, "lifts:", [(e["label"], len(e["rooms"])) for e in b["fleet"].get("elev", [])], "- shaft rooms with no stop:", n)
