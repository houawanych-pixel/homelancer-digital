#!/usr/bin/env python3
"""A station built with the SHIP tools (station_fleet.py -> fleet_station_<id>/, fleet_compose decks, fleet_ways,
fleet_formula, to_deck_json --decks -> assets/holodeck/<id>.json) is marked as a station for the game: info.station
(calm visits, 360 service rooms by name) and its deck names (the ship decks: main 0, upper +170, lower -170 ...).
Nothing else changes: the deck is the ship deck.   usage: python3 -I tools/trace/station_ship_deck.py station_liberty_hub"""
import json, os, sys
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
NAMES = {-340.0: "HANGAR DECK", -170.0: "ENGINEERING DECK", 0.0: "MAIN HUB DECK", 170.0: "HABITAT DECK", 340.0: "COMMAND DECK"}
for sid in sys.argv[1:]:
    p = os.path.join(REPO, "assets", "holodeck", sid + ".json"); d = json.load(open(p)); b = d["board"]
    ys = sorted({float(r["y"][0]) for r in b["rooms"].values()})
    b["info"]["station"] = True
    b["info"]["deck_names"] = [[y, NAMES[y]] for y in ys if y in NAMES]   # (sloped floors are not decks)
    # the decks' map pictures, as the ships': the main deck's plan picture (the silhouette sheet) and the composed decks'
    import shutil
    shutil.copy(os.path.join(REPO, "tools", "trace", "fleet_" + sid, "source.jpg"), os.path.join(REPO, "assets", "holodeck", sid + "_map.jpg"))
    files = {"MAIN HUB DECK": sid + "_map.jpg", "HABITAT DECK": sid + "_upper.jpg", "ENGINEERING DECK": sid + "_lower.jpg",
             "COMMAND DECK": sid + "_upper2.jpg", "HANGAR DECK": sid + "_lower2.jpg"}
    b["info"]["deck_maps"] = {k: v for k, v in files.items() if os.path.exists(os.path.join(REPO, "assets", "holodeck", v))}
    json.dump(d, open(p, "w"), separators=(",", ":"))
    print(sid, "station decks:", b["info"]["deck_names"])
