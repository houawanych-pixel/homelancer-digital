#!/usr/bin/env python3
"""Liberty Hub main deck in the SAME STYLE as the fleet ship maps (owner, Nov 18 2026: "look at the ships, the maps need to
be the same style"): one room per district block (like BRIDGE, HANGAR BAY ... on the Unity Capital), the clean red
walkways as the halls, the hub as a round room with its ring, doors where a room meets a hall; written as a planlib
plan.json on the owner's map art (concept2/source.png, x3) so the ship tools run unchanged:
  fleet_ways.py (red mech ways / blue pilot rooms, door squares, legend) and fleet_formula.py (cards).
Output: ../eng/plan.json, ../source.jpg (the art x3), ../eng/overrides.json kinds."""
import json, os, pickle, sys
import cv2, numpy as np
from shapely.geometry import Point, mapping, Polygon
from shapely.ops import unary_union
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__)); ENG = os.path.join(HERE, "..", "eng")
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import planlib
K = 3.0
B = pickle.load(open(os.path.join(HERE, "blocks.pkl"), "rb")); Z = B["Z"]
sc = lambda g: affinity.scale(g, K / Z, K / Z, origin=(0, 0))
src = cv2.imread(os.path.join(HERE, "source.png"))
cv2.imwrite(os.path.join(HERE, "..", "source.jpg"), cv2.resize(src, None, fx=K, fy=K, interpolation=cv2.INTER_CUBIC), [cv2.IMWRITE_JPEG_QUALITY, 90])
T = planlib.T
ways = sc(B["ways"]).buffer(6, join_style=2).buffer(-6, join_style=2)   # fuse the mirror seam down the middle
from shapely.ops import nearest_points as _nps
_gs = sorted(getattr(ways, "geoms", [ways]), key=lambda g: -g.area); MAINW = _gs[0]; JOIN = []
for g in _gs[1:]:                                          # every loose walkway piece joins the main network
    a, b = _nps(g, MAINW); JOIN.append(planlib.hall((a.x, a.y), (b.x, b.y), w=10 * K))
ways = unary_union([ways] + JOIN)
hub = sc(B["hub"])
LAB = {k: sc(p) for k, p in B["lab"].items()}
MECH = ("Cargo", "Repair", "Shipyard", "Manufacturing", "Workshops", "Life Support", "Docking", "Arrival", "Crew & Staff", "Transit")
R = {"Central Hub (Atrium)": hub.difference(ways)}
if R["Central Hub (Atrium)"].geom_type != "Polygon": R["Central Hub (Atrium)"] = max(R["Central Hub (Atrium)"].geoms, key=lambda q_: q_.area)
used = set(); n = 0
for b in sorted(B["blocks"], key=lambda g: (round(g.centroid.y / 60), g.centroid.x)):
    g = sc(b).buffer(4 * K * 1.0, join_style=2).difference(ways).intersection(sc(B["floor"])).simplify(2.0)   # rooms meet the halls (as on the ships)
    if g.geom_type != "Polygon" and not g.is_empty: g = max(g.geoms, key=lambda q_: q_.area)
    if g.area < 2500 or g.geom_type != "Polygon": continue
    nm = next((k for k, p in LAB.items() if k not in used and g.buffer(40).contains(p)), None)
    if nm is None:
        n += 1; nm = "%s %d" % ("Dock Bay" if g.centroid.distance(hub.centroid) > 330 * K else "Service Room", n)
    used.add(nm); R[nm] = g
# doors: one per room, at the middle of its longest contact with the halls (rooms sit a band off the halls: bridge it)
DOORS, STUBS = [], []
from shapely.ops import nearest_points
def orient(p, q): return "h" if abs(q.y - p.y) >= abs(q.x - p.x) else "v"
for k, g in R.items():
    touch = g.exterior.intersection(ways.buffer(T))
    segs = sorted([q_ for q_ in getattr(touch, "geoms", [touch]) if not q_.is_empty and q_.length > 0], key=lambda q_: -q_.length)
    if not segs:
        p, q = nearest_points(g.exterior, ways); STUBS.append(planlib.hall((q.x, q.y), (p.x, p.y), w=planlib.DOOR + 8)); seg_p = p
        d = g.exterior.project(p)
    else:
        for sg in (segs[:4] if k.startswith("Central Hub") else segs[:1])[1:]:
            pp = sg.interpolate(0.5, normalized=True); dd = g.exterior.project(pp)
            a2, b2 = g.exterior.interpolate(max(0, dd - 6)), g.exterior.interpolate(dd + 6)
            DOORS.append((round(pp.x, 1), round(pp.y, 1), "h" if abs(b2.x - a2.x) >= abs(b2.y - a2.y) else "v"))
        seg_p = segs[0].interpolate(0.5, normalized=True); d = g.exterior.project(seg_p)
    a_, b_ = g.exterior.interpolate(max(0, d - 6)), g.exterior.interpolate(d + 6)
    DOORS.append((round(seg_p.x, 1), round(seg_p.y, 1), "h" if abs(b_.x - a_.x) >= abs(b_.y - a_.y) else "v"))
halls = [h for h in getattr(ways, "geoms", [ways])] + STUBS
H_, W_ = src.shape[0] * K, src.shape[1] * K
AX = 553 * K
sp = MAINW.representative_point(); start = (sp.x, sp.y)
S = planlib.Ship("station_veranthos_customs", ENG, os.path.join(HERE, "..", "source.jpg"), AX, R, halls, DOORS, start=start, center_y=hub.centroid.y)
bad = planlib.run(S)
if bad:                                             # a block no walkway reaches stays service space (as on the ships)
    print("service space:", bad)
    for k in bad: R.pop(k, None)
    DOORS[:] = [d for d in DOORS if any(g.distance(Point(d[0], d[1])) < 3 for g in R.values())]
    S = planlib.Ship("station_veranthos_customs", ENG, os.path.join(HERE, "..", "source.jpg"), AX, R, halls, DOORS, start=start, center_y=hub.centroid.y)
    bad = planlib.run(S)
P = json.load(open(os.path.join(ENG, "plan.json"))); P["px_per_m"] = 10.0 * K / 4.0; json.dump(P, open(os.path.join(ENG, "plan.json"), "w"))
ov = json.load(open(os.path.join(ENG, "overrides.json"))) if os.path.exists(os.path.join(ENG, "overrides.json")) else {}
ov["kinds"] = {k: ("mech" if k.startswith(MECH) or k.startswith("Central Hub") else "pilot") for k in R}
json.dump(ov, open(os.path.join(ENG, "overrides.json"), "w"), indent=1)
pt = lambda k: [int(R[k].representative_point().x), int(R[k].representative_point().y)]
docks = [k for k in R if k.startswith(("Dock", "Cargo"))]
G = {"entry": {"room": docks[-1], "at": pt(docks[-1])}, "locks": [], "guards": [], "wreck": [], "lifts": [], "patrols": [],
     "targets": {"sabotage": {"room": "Central Hub (Atrium)", "at": pt("Central Hub (Atrium)"), "key": 3}},
     "room_guards": {k: 1 for k in R}, "note": "Liberty Hub main deck (PROPOSED)"}
json.dump(G, open(os.path.join(ENG, "gameplay.json"), "w"), indent=1)
g1 = os.path.join(ENG, "gameplay_v1.json")
if os.path.exists(g1): os.remove(g1)
print(len(R), "rooms; unreachable", bad)
