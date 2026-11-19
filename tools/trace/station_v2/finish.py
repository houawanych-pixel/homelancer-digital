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
G["elevators"] = [{"decks": decks, "at": at, "label": "LIFT", "need": {"upper2": 3} if "upper2" in decks else {}} for at in LIFT_AT]
G["deck_names"] = {"main": "MAIN HUB DECK", "lower": "ENGINEERING DECK", "lower2": "HANGAR DECK", "upper": "HABITAT DECK", "upper2": "COMMAND DECK"}
G["deck_names"] = {k: v for k, v in G["deck_names"].items() if k in decks}
json.dump(G, open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
py(os.path.join(TR, "to_deck_json.py"), os.path.join("tools", "trace", "fleet_" + sid), "--decks", "--out", os.path.join("assets", "holodeck", sid + ".json"))
py(os.path.join(TR, "station_ship_deck.py"), sid)
