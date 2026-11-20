#!/usr/bin/env python3
"""game_kit.py: the room library (kit.json) for the game's planetary facilities -> assets/holodeck/room_kit.json
(owner, Nov 19 2026: "wire the existing room library randomizer into the planetary facility map generator so each
planet gets a different randomized facility layout"). tools/ is not in the game (.gdignore, export filter), so the
facility generator (scripts/boarding.gd, Boarding.facility) reads this copy. The same pieces the station v2 builder
fits along its walkways (station_v2/station_build.py KIT: outer wall only, simplified, no spindly shapes), each
outline centred on its box and scaled to -1..1 (x = map x, y = map y -> the game's z), so a hall can stretch it to
its own size. Rerun after lego.py rebuilds kit.json:  python3 tools/trace/room_library/game_kit.py"""
import json, os
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "..", "assets", "holodeck", "room_kit.json")
pieces = []
for p in json.load(open(os.path.join(HERE, "kit.json")))["pieces"]:
    g = Polygon(p["poly"]).buffer(0)
    if g.geom_type != "Polygon": g = max(g.geoms, key=lambda q: q.area)
    g = Polygon(g.exterior).simplify(0.12)
    x0, y0, x1, y1 = g.bounds
    if min(x1 - x0, y1 - y0) < 1.5: continue
    if g.area / ((x1 - x0) * (y1 - y0)) < 0.62: continue      # (spindly shapes make slivers when stretched to a hall)
    g = orient(g, 1.0)                                          # (corners in the same turn as Boarding._make_poly)
    cx, cy, hw, hh = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    pts = [[round((x - cx) / hw, 3), round((y - cy) / hh, 3)] for x, y in list(g.exterior.coords)[:-1]]
    pieces.append({"id": p["id"], "ar": round(hw / hh, 3), "m2": p["area_m2"], "poly": pts})
json.dump({"source": "tools/trace/room_library/kit.json", "note": "poly in -1..1 of the room's box (y = z); ar = width / depth",
           "count": len(pieces), "pieces": pieces}, open(OUT, "w"), separators=(",", ":"))
print("room kit for the game:", len(pieces), "pieces ->", os.path.normpath(OUT))
