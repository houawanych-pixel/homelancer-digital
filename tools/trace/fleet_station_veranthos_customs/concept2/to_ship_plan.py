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
# the hub is one open plaza (owner: "the centre is the hub, it needs to be clear") with the main lift in its middle,
# the same lift square on every deck (as the ships' lifts)
from shapely.geometry import box as _bx
ways = unary_union([ways, hub]).buffer(0)
hc = hub.centroid; LH = 33
R = {"Lift (main)": _bx(hc.x - LH, hc.y - LH, hc.x + LH, hc.y + LH)}
ways = ways.difference(R["Lift (main)"])
used = set(); n = 0
AX = 553 * K
# ---- COMPACT ROOMS (owner, Nov 18: same construction as the ships): every district block is cut on one station grid
# (G px, square to the mirror line and the hub) into ship-size rooms; the grid lines inside a block are its PILOT ways
# (a hall PW wide between the rooms, running out to the red walkways). A piece that fills under FILL of its own box is
# a sliver along a slanted wall: service space. Every room's box then sits in its own grid cell (no two overlap).
G, PW, FILL = 132.0, 18.0, 0.55
def gridlines(g):
    x0, y0, x1, y1 = g.bounds; out = []
    i0, i1 = int((x0 - AX) // G) - 1, int((x1 - AX) // G) + 2
    j0, j1 = int((y0 - hc.y) // G) - 1, int((y1 - hc.y) // G) + 2
    for i in range(i0, i1): out.append(_bx(AX + i * G - PW / 2, y0 - 10, AX + i * G + PW / 2, y1 + 10))
    for j in range(j0, j1): out.append(_bx(x0 - 10, hc.y + j * G - PW / 2, x1 + 10, hc.y + j * G + PW / 2))
    return unary_union(out)
PH = []
for b in sorted(B["blocks"], key=lambda g: (round(g.centroid.y / 60), g.centroid.x)):
    g = sc(b).buffer(4 * K * 1.0, join_style=2).difference(ways).intersection(sc(B["floor"])).simplify(2.0)
    g = g.difference(unary_union(list(R.values())).buffer(T)) if R else g
    if g.is_empty or g.area < 2500: continue
    gl = gridlines(g)
    pieces = g.difference(gl)
    halls_here = g.intersection(gl)
    base = next((k for k, p in LAB.items() if k not in used and g.buffer(40).contains(p)), None)
    if base: used.add(base)
    m_ = 0
    for q_ in sorted([q for q in getattr(pieces, "geoms", [pieces]) if q.geom_type == "Polygon"], key=lambda q: -q.area):
        x0, y0, x1, y1 = q_.bounds
        if q_.area < 1800 or q_.area < FILL * (x1 - x0) * (y1 - y0): continue
        q_ = q_.simplify(1.5)
        m_ += 1
        if base: nm = base if m_ == 1 else "%s %d" % (base, m_)
        else:
            n += 1; nm = "%s %d" % ("Dock Bay" if q_.centroid.distance(hub.centroid) > 330 * K else "Service Room", n)
        R[nm] = q_
    PH += [h for h in getattr(halls_here, "geoms", [halls_here]) if h.geom_type == "Polygon" and h.area > 200]
ways = unary_union([ways] + PH).buffer(0)
PILOT_WAYS = unary_union(PH) if PH else None
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
        for sg in (segs[:1])[1:]:
            pp = sg.interpolate(0.5, normalized=True); dd = g.exterior.project(pp)
            a2, b2 = g.exterior.interpolate(max(0, dd - 6)), g.exterior.interpolate(dd + 6)
            DOORS.append((round(pp.x, 1), round(pp.y, 1), "h" if abs(b2.x - a2.x) >= abs(b2.y - a2.y) else "v"))
        seg_p = segs[0].interpolate(0.5, normalized=True); d = g.exterior.project(seg_p)
    a_, b_ = g.exterior.interpolate(max(0, d - 6)), g.exterior.interpolate(d + 6)
    DOORS.append((round(seg_p.x, 1), round(seg_p.y, 1), "h" if abs(b_.x - a_.x) >= abs(b_.y - a_.y) else "v"))
halls = [h for h in getattr(ways, "geoms", [ways])] + STUBS
H_, W_ = src.shape[0] * K, src.shape[1] * K
AX = 553 * K
start = (hc.x, hc.y - 120)
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
ov["kinds"] = {k: ("lift" if k.startswith("Lift") else "mech" if k.startswith(MECH) else "pilot") for k in R}
json.dump(ov, open(os.path.join(ENG, "overrides.json"), "w"), indent=1)
pt = lambda k: [int(R[k].representative_point().x), int(R[k].representative_point().y)]
docks = [k for k in R if k.startswith(("Dock", "Cargo"))]
G = {"entry": {"room": docks[-1], "at": pt(docks[-1])}, "locks": [], "guards": [], "wreck": [], "patrols": [],
     "targets": {}, "lifts": [{"room": "Lift (main)", "at": pt("Lift (main)")}],
     "room_guards": {k: 1 for k in R}, "note": "Liberty Hub main deck (PROPOSED)"}
json.dump(G, open(os.path.join(ENG, "gameplay.json"), "w"), indent=1)
g1 = os.path.join(ENG, "gameplay_v1.json")
if os.path.exists(g1): os.remove(g1)
print(len(R), "rooms; unreachable", bad)
