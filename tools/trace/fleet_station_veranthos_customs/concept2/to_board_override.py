#!/usr/bin/env python3
"""The ship-style Liberty Hub main deck (../eng/plan.json from to_ship_plan.py) -> ../eng/main_deck_override.json for
tools/trace/station_to_board.py (the game's station deck builder): moved into that deck frame (hub at 0, 0), scaled so the
main red walkway is as wide as the old deck's mech way (~33 plan px). Room kinds from ../eng/overrides.json; the MAIN HUB
deck's card (ORANGE, in a pilot room behind a YELLOW door, as the old chain) goes to the pilot room furthest from the hub."""
import json, os
from shapely.geometry import shape, mapping, Point
from shapely.ops import unary_union
from shapely import affinity
HERE = os.path.dirname(os.path.abspath(__file__)); ENG = os.path.join(HERE, "..", "eng")
P = json.load(open(os.path.join(ENG, "plan.json"))); KIND = json.load(open(os.path.join(ENG, "overrides.json")))["kinds"]
R = {k: shape(v) for k, v in P["rooms"].items()}
hub = R["Central Hub (Atrium)"].centroid
SCALE = 33.0 / 30.0                       # plan.json main way = 10 source px x3 = 30 px
tf = lambda g: affinity.scale(affinity.translate(g, -hub.x, -hub.y), SCALE, SCALE, origin=(0, 0))
ways = tf(unary_union([shape(h) for h in P["halls"]]).buffer(0))
outline = tf(shape(P["floor"])).buffer(0)
from shapely.ops import nearest_points
from shapely.geometry import LineString
import math
ps = sorted(getattr(ways, "geoms", [ways]), key=lambda g: -g.area); main = ps[0]; extra = []
for g in ps[1:]:                                        # every loose walkway piece is joined to the network, overlapping both
    a, b = nearest_points(g, main); L = max(1e-6, a.distance(b)); ux, uy = (b.x - a.x) / L, (b.y - a.y) / L
    extra.append(LineString([(a.x - ux * 14, a.y - uy * 14), (b.x + ux * 14, b.y + uy * 14)]).buffer(17, cap_style=2))
# the main lift stands in a small plaza at the very middle of the hub, reached by a walkway across the hub
hubg = tf(R["Central Hub (Atrium)"])
plaza = hubg.buffer(8).convex_hull            # the hub is one open plaza (owner: the hub must be clear); the main lift in its middle
across = LineString([(-hubg.bounds[2] - 20, 0), (hubg.bounds[2] + 20, 0)]).buffer(18, cap_style=2)
ways = unary_union([ways] + extra + [plaza, across]).buffer(0)
print("walkway pieces:", len(getattr(ways, "geoms", [ways])))
rooms = []
far = max((k for k in R if KIND.get(k) == "pilot"), key=lambda k: R[k].centroid.distance(hub))
for k, g in R.items():
    gg = tf(g)
    if k.startswith("Central Hub"): continue
    r = {"name": k, "kind": KIND.get(k, "pilot"), "key": 0, "poly": mapping(gg)}
    if k == far: r.update({"key": 1, "card": 2})
    rooms.append(r)
from shapely.geometry import box as _box
sp = ways.intersection(_box(-20, 0, 20, 1e5)); yb = sp.bounds[3]          # the bottom end of the spine (Transit end)
bay = Point(0, yb - 50).buffer(70, 32).intersection(outline.buffer(-6))
json.dump({"ways": mapping(ways), "outline": mapping(outline), "rooms": rooms, "bay": mapping(bay)}, open(os.path.join(ENG, "main_deck_override.json"), "w"))
print(len(rooms), "rooms; card room:", far, "; outline", [round(v) for v in outline.bounds])
