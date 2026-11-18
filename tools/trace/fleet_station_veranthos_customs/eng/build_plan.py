#!/usr/bin/env python3
"""Liberty Hub (st3d_veranthos_customs) MAIN DECK inside the LIBERTY HUB SILHOUETTE (owner, Nov 18 2026: "use the
liberty silhouette shapes"): the station model's own main-floor outline (station_silhouette.py -> station_source.py,
source_silhouette.jpg / source_mask.png, 1600 px = 140 m, middle 800, 800), built the capital-ship way (planlib).

The layout is the owner's Liberty Hub sheet (concept v2, build_plan_sheet.py): a round Central Hub (atrium) with its
walkway and a ring of shops, an inner ring, an octagonal outer ring, the cross (top nub down to the bottom), short
spokes between the rings - fitted into the silhouette's round body - and a walkway out along every one of the six
arms to a docking bay at its tip. Every block between walkways is a room; each takes the sheet's district name found at
the same angle and ring band (the sheet's positions turned into angle + band). Mirrored about x 800. One door per room
per walkway it meets."""
import os, sys, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from planlib import *
import cv2, numpy as np
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "source_silhouette.jpg")
AX, CY = 800.0, 800.0
M = mirror(AX)
def polar(a, r): return (AX + r * math.cos(math.radians(a)), CY + r * math.sin(math.radians(a)))
def ring_pts(rx, ry, n=128): return [polar(360 * k / n, 1)[0] * 0 + AX + rx * math.cos(2 * math.pi * k / n) for k in range(0)] or \
    [(AX + rx * math.cos(2 * math.pi * k / n), CY + ry * math.sin(2 * math.pi * k / n)) for k in range(n + 1)]
def octring_pts(r, c=0.41):
    return [(AX - r * c, CY - r), (AX + r * c, CY - r), (AX + r, CY - r * c), (AX + r, CY + r * c), (AX + r * c, CY + r),
            (AX - r * c, CY + r), (AX - r, CY + r * c), (AX - r, CY - r * c), (AX - r * c, CY - r)]

# ---- the silhouette (the model's own main-floor outline), mirror-true already
mk = cv2.imread(os.path.join(HERE, "..", "source_mask.png"), 0) > 127
cs, _ = cv2.findContours(mk.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
OUTLINE = Polygon(cv2.approxPolyDP(max(cs, key=cv2.contourArea), 2.0, True).reshape(-1, 2)).buffer(-14, join_style=2)   # 1.2 m hull

# ---- walkways: the SHEET'S OWN walkway network (sheet_cells.py -> sheet_walk_centre.png, mirror-true), laid on the
# silhouette by one scale + shift (sheet middle 512, 445 -> 800, 800); each centre line becomes a walkway W1 wide
S_ = 1.40
SC = (512.0, 445.0)
RA, R2 = 74 * S_, 300 * S_
W1, W2 = 26, 18
# the sheet's room blocks (sheet_cells.py: clean, mirror-true), moved onto the silhouette; the walkways are the gaps
import json as _json
from shapely import affinity as _af
from shapely.geometry import shape as _shape
def to_sil(g): return _af.affine_transform(g, [S_, 0, 0, S_, AX - S_ * SC[0], CY - S_ * SC[1]])
blocks = []
for cj in _json.load(open(os.path.join(HERE, "sheet_cells.json")))["cells"]:
    g = _shape(cj)
    if g.area < 350 or g.centroid.distance(Point(*SC)) < 80: continue          # specks; the atrium (it is the Central Hub)
    g = to_sil(g.buffer(-3.5, join_style=2)).intersection(OUTLINE)            # half the sheet's walkway width each side
    if not g.is_empty and g.area > 900: blocks.append(g)
core = unary_union([b.buffer(W1, join_style=2) for b in blocks]).buffer(-W1 / 2, join_style=2)
core = Polygon(max(getattr(core, "geoms", [core]), key=lambda q: q.area).exterior)      # the network's own outer edge
ARMS = [239, 212, 141, 128]               # the six arms (+ mirror): measured on the silhouette
def spoke(a, r0, r1, clip, w=W2): return hall(polar(a, r0), polar(a, r1), w=w).intersection(clip)
DOCK_R = {}; LS = []
for a in ARMS:                             # a walkway out along each arm to its docking bay (the arms are not on the sheet)
    t = R2 * 0.8
    while OUTLINE.contains(Point(*polar(a, t + 10))): t += 4
    DOCK_R[a] = t
    LS.append(spoke(a, R2 * 0.6, t - 70, OUTLINE, w=W1))
LS += [M(h) for h in LS]
LS += [hall((AX - 900, CY), (AX + 900, CY), w=W1).intersection(OUTLINE), hall((AX, CY - 900), (AX, CY + 900), w=W1).intersection(OUTLINE)]
ringwalk = core.exterior.buffer(W1 / 2, join_style=2)                         # a walkway round the network's edge
rim = OUTLINE.difference(core).difference(unary_union(LS + [ringwalk]).buffer(T / 2))
blocks += [p for p in getattr(rim, "geoms", [rim]) if p.area > 900]
rooms_all = unary_union(blocks + [circle(AX, CY, RA - W2 / 2 - T)])
net = OUTLINE.difference(rooms_all.buffer(T / 2))
parts = sorted(getattr(net, "geoms", [net]), key=lambda q: -q.area)
net = parts[0]

# ---- names: the sheet's districts by angle and band (0 = shops band, 1 = between the rings, 2 = outside the outer ring)
SHEET_C, SHEET_R2 = (507.0, 447.0), 300.0
SHEET = {"Customs & Security": (420, 128), "Passenger Services": (594, 128), "Crew District A": (365, 215), "Crew District B": (649, 215),
         "Repair & Maintenance Complex (North)": (245, 240), "Shipyard & Overhaul Docks (North)": (769, 240),
         "Residential District (West)": (336, 290), "Commerce District (East)": (678, 290), "Ship Dealer & Showroom": (265, 398),
         "Outfitting & Gear": (749, 398), "Cargo Terminal A (Freight)": (100, 350), "Cargo Terminal C (General)": (914, 350),
         "Cargo Terminal B (Freight)": (100, 545), "Cargo Terminal D (Industrial)": (914, 545), "Medical Complex (Hospital)": (272, 545),
         "Supplies & Administration": (742, 545), "Repair & Maintenance Complex (South)": (196, 694), "Shipyard & Overhaul Docks (South)": (818, 694),
         "Manufacturing & Workshops": (300, 700), "Workshops (East)": (714, 700), "Life Support & Utilities": (420, 790), "Security Control": (594, 790),
         "Atrium Shops (NW)": (430, 370), "Atrium Shops (NE)": (584, 370), "Atrium Shops (SW)": (430, 525), "Atrium Shops (SE)": (584, 525),
         "Commerce District (North)": (537, 200), "Commerce District (North, west wing)": (477, 200),
         "Commerce District (South)": (537, 668), "Commerce District (South, west wing)": (477, 668)}
def to_here(p):
    q = Point(AX + S_ * (p[0] - SC[0]), CY + S_ * (p[1] - SC[1])); a = math.atan2(q.y - CY, q.x - AX); r = math.hypot(q.x - AX, q.y - CY)
    while not OUTLINE.contains(q) and r > 0: r -= 4; q = Point(AX + r * math.cos(a), CY + r * math.sin(a))
    return q
LABELS = {k: to_here(p) for k, p in SHEET.items()}

R = {}
R["Central Hub (Atrium)"] = circle(AX, CY, RA - W2 / 2 - T)
# the arm tips are docking bays
for a in ARMS + [180 - a for a in ARMS]:
    t = DOCK_R[a] if a in DOCK_R else DOCK_R[180 - a]
    side = "W" if math.cos(math.radians(a)) < 0 else "E"
    R["Docking Bay %s%d" % (side, (ARMS.index(a) if a in ARMS else ARMS.index(180 - a)) + 1)] = \
        OUTLINE.intersection(Point(AX, CY).buffer(900).difference(Point(AX, CY).buffer(t - 70 - T))).intersection(
            Polygon([(AX, CY), polar(a - 9, 1200), polar(a + 9, 1200)])).difference(net.buffer(T / 2))
docks = unary_union([g for g in R.values()])
cells = OUTLINE.difference(net.buffer(T / 2)).difference(docks.buffer(T / 2))
n_unnamed = 0; used = set()
for c in sorted(getattr(cells, "geoms", [cells]), key=lambda c: (round(c.centroid.y / 50), c.centroid.x)):
    if c.area < 900: continue
    name = next((k for k, p in LABELS.items() if k not in used and c.contains(p)), None)
    if name is None:
        n_unnamed += 1; name = "Service Block %s%d" % ("W" if c.centroid.x < AX else "E", n_unnamed)
    used.add(name); R[name] = c.simplify(0.8)
for k in list(R):
    if R[k].geom_type != "Polygon":
        parts = [p for p in getattr(R[k], "geoms", []) if p.geom_type == "Polygon"]
        if parts: R[k] = max(parts, key=lambda p: p.area)
        else: del R[k]

# ---- service space (owner, Nov 18: "space behind the walls ... for fuse boxes", like the SWTOR ship / station plans):
# each district block keeps a band of non-walkable service space round its room (conduit, ducts, power, fuse boxes);
# the room is the block pulled in until it covers ~60 % of the block (12..60 px = 1..5 m of service space), and a short
# doorway passage crosses the band from the walkway to the room's door.
COVER, S_MIN, S_MAX = 0.60, 12.0, 60.0
NO_INSET = ("Central Hub", "Cargo Terminal B", "Cargo Terminal D")   # (the two pointed wedges: a band would close their door)
pieces = list(getattr(net, "geoms", [net]))
DOORS, PASS = [], []
def door_pt(g, hp):
    touch = g.exterior.intersection(hp.buffer(T))
    segs = sorted([p for p in getattr(touch, "geoms", [touch]) if not p.is_empty and p.length > 0], key=lambda p: -p.length)
    return segs[0].interpolate(0.5, normalized=True) if segs and segs[0].length >= DOOR else None
def orient(a, b):   # door box across a passage running a -> b
    return "h" if abs(b.y - a.y) >= abs(b.x - a.x) else "v"
SERVICE = []
for k in list(R):
    g = R[k]
    contacts = [p for p in (door_pt(g, hp) for hp in pieces) if p is not None]
    if k.startswith(NO_INSET) or k.startswith("Docking Bay") or g.area < 12000:   # small blocks: no room for a band
        for p in contacts:
            d = g.exterior.project(p); q0, q1 = g.exterior.interpolate(max(0, d - 4)), g.exterior.interpolate(d + 4)
            DOORS.append((round(p.x, 1), round(p.y, 1), "h" if abs(q1.x - q0.x) >= abs(q1.y - q0.y) else "v"))
        continue
    lo, hi = S_MIN, S_MAX
    for _ in range(14):
        mid = (lo + hi) / 2; inner = g.buffer(-mid, join_style=2)
        if inner.is_empty or inner.area / g.area < COVER: hi = mid
        else: lo = mid
    inner = g.buffer(-lo, join_style=2)
    for s_try in (lo, S_MIN, 6.0):                           # thin blocks get a thinner band
        inner = g.buffer(-s_try, join_style=2)
        if not inner.is_empty and inner.area > 1500: break
    if inner.is_empty or inner.area < 800: inner = g          # too thin for service space: keep the block
    if inner.geom_type != "Polygon": inner = max(inner.geoms, key=lambda q: q.area)
    inner = inner.simplify(1.0)
    SERVICE.append(g.difference(inner))
    R[k] = inner
    for p in contacts[:2]:                                   # one or two doors per room
        from shapely.ops import nearest_points as _np
        q = _np(inner.exterior, p)[0]
        L_ = max(1e-6, math.hypot(p.x - q.x, p.y - q.y)); ux, uy = (p.x - q.x) / L_, (p.y - q.y) / L_
        PASS.append(hall((p.x + ux * 12, p.y + uy * 12), (q.x - ux * 2, q.y - uy * 2), w=DOOR + 6))   # runs into the walkway
        DOORS.append((round(q.x, 1), round(q.y, 1), orient(p, q)))
pieces = pieces + PASS

S = Ship("liberty_hub_main", HERE, SRC, AX, R, pieces, DOORS, start=polar(90, R2 + 60), center_y=CY)
if __name__ == "__main__":
    cov = sum(g.area for g in R.values()) / OUTLINE.area
    print("rooms cover %.0f %% of the deck" % (100 * cov)); print("unnamed blocks:", n_unnamed, "| sheet names not placed:", [k for k in SHEET if k not in R])
    bad = run(S)
    sys.exit(1 if bad else 0)
