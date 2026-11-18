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
from shapely.ops import unary_union, substring as _sub

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
rooms_all = unary_union(blocks + [circle(AX, CY, RA - W2 / 2 - T)])
gaps = core.buffer(W1 / 2).intersection(OUTLINE).difference(rooms_all)

# ---- EVEN walkways (owner, Nov 18: "the walkways need to be more evenly parallel"): the centre line of every gap
# between the sheet's blocks is traced as a graph, each run straightened (0 / 45 / 90 deg kept dead straight, curves
# smoothed), short dead-end stubs dropped, and every run redrawn at ONE width
from skimage.morphology import skeletonize as _sk
gm = np.zeros((1600, 1600), np.uint8)
for p in getattr(gaps, "geoms", [gaps]):
    if p.geom_type != "Polygon": continue
    m1 = np.zeros_like(gm); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 1)
    for rr_ in p.interiors: cv2.fillPoly(m1, [np.array(rr_.coords, np.int32)], 0)
    gm |= m1
sk = _sk(gm > 0).astype(np.uint8)
NB8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
def nbrs(y, x): return [(y + dy, x + dx) for dy, dx in NB8 if 0 <= y + dy < 1600 and 0 <= x + dx < 1600 and sk[y + dy, x + dx]]
deg = cv2.filter2D(sk, -1, np.ones((3, 3)), borderType=0) - 1
pix = set(map(tuple, np.argwhere(sk > 0)))
node = {p for p in pix if deg[p] != 2}
seen = set(); runs = []
def walk_from(a, b):
    path = [a, b]; prev, cur = a, b
    while cur not in node:
        nx = [q for q in nbrs(*cur) if q != prev and (min(cur, q), max(cur, q)) not in seen]
        if not nx: break
        seen.add((min(cur, nx[0]), max(cur, nx[0]))); prev, cur = cur, nx[0]; path.append(cur)
        if cur == a: break
    return path
for a in node:
    for b in nbrs(*a):
        e = (min(a, b), max(a, b))
        if e in seen: continue
        seen.add(e); runs.append(walk_from(a, b))
for p in pix:                                   # rings with no junction on them
    if p in node or any((min(p, q), max(p, q)) in seen for q in nbrs(*p)): continue
    q = nbrs(*p)
    if q: seen.add((min(p, q[0]), max(p, q[0]))); runs.append(walk_from(p, q[0]))
def straighten(pts):
    a = np.array([(x, y) for y, x in pts], np.float32).reshape(-1, 1, 2)
    p = cv2.approxPolyDP(a, 3.0, False).reshape(-1, 2).astype(float)
    for k in range(len(p) - 1):                 # snap near-0 / 45 / 90 legs
        d = p[k + 1] - p[k]; L = math.hypot(*d)
        if L < 10: continue
        ang = math.degrees(math.atan2(d[1], d[0])); sn = round(ang / 45) * 45
        if abs(ang - sn) < 8 and 0 < k + 1 < len(p) - 1:
            p[k + 1] = p[k] + L * np.array([math.cos(math.radians(sn)), math.sin(math.radians(sn))])
    return [tuple(q) for q in p]
lines_ = []
for r_ in runs:
    if len(r_) < 3: continue
    ends_free = sum(1 for q in (r_[0], r_[-1]) if deg[q] <= 1)
    if ends_free and len(r_) < 45: continue     # a short dead-end stub
    lines_.append(LineString(straighten(r_)))
walkway = unary_union([l.buffer(W1 / 2, cap_style=1, join_style=2) for l in lines_] + [ringwalk])

# ---- DOCK ARMS (owner: "a straight line big enough for mechs ... points where multiple ships can dock and unload, a wide
# area to unload, a big travelling lane with sections like an airport"): a straight mech lane down the middle of every
# arm, airport GATES off both sides of it (each a wide unloading bay reaching the hull, where a ship docks), and a big
# docking PLATFORM at the tip. The rest of the arm is structure / service space.
LANE, GATE_W, GATE_GAP = 56, 80, 30
DOCKS = {}
arm_lanes = []
from shapely.ops import nearest_points as _nps
# the arm tips: the outline's sharp points far out from the middle (measured on the silhouette, mirror-true)
oc = np.array(OUTLINE.exterior.coords)[:-1]
rad = np.hypot(oc[:, 0] - AX, oc[:, 1] - CY)
tips = []
for k in range(len(oc)):
    if rad[k] < 600: continue
    if rad[k] >= max(rad[(k + d) % len(oc)] for d in range(-2, 3)):
        if all(math.hypot(*(oc[k] - q)) > 120 for q in tips): tips.append(oc[k])
tips = [q for q in tips if q[0] <= AX + 1]                    # left side; the right is the mirror
tips = sorted(tips, key=lambda q: q[1])
from collections import deque as _dq
armreg = OUTLINE.difference(core.buffer(W1 / 2))
am = np.zeros((1600, 1600), np.uint8)
for p in getattr(armreg, "geoms", [armreg]):
    cv2.fillPoly(am, [np.array(p.exterior.coords, np.int32)], 1)
ask = _sk(am > 0).astype(np.uint8)
skp = np.argwhere(ask > 0)
coremask = np.zeros_like(am); cv2.fillPoly(coremask, [np.array(core.exterior.coords, np.int32)], 1)
cdist = cv2.distanceTransform(1 - coremask, cv2.DIST_L2, 5)
def arm_path(tp):
    """the arm's own centre line from its tip to where it meets the district network (BFS on the arm skeleton)"""
    s0 = tuple(skp[np.argmin(np.hypot(skp[:, 1] - tp[0], skp[:, 0] - tp[1]))])
    par = {s0: None}; q = _dq([s0]); best = s0
    while q:
        y, x = q.popleft()
        if cdist[y, x] < cdist[best]: best = (y, x)
        for dy, dx in NB8:
            nb_ = (y + dy, x + dx)
            if 0 <= nb_[0] < 1600 and 0 <= nb_[1] < 1600 and ask[nb_] and nb_ not in par: par[nb_] = (y, x); q.append(nb_)
    path = []; c_ = best
    while c_ is not None: path.append((c_[1], c_[0])); c_ = par[c_]
    return path                                 # from the network end to the tip
for n_, tp in enumerate(tips + [np.array([2 * AX - q[0], q[1]]) for q in tips if abs(q[0] - AX) > 2]):
    side = "W" if tp[0] < AX - 1 else ("E" if tp[0] > AX + 1 else "N")
    idx = (n_ % max(1, len(tips))) + 1
    pth = arm_path(tp)
    if len(pth) < 20: continue
    pl = cv2.approxPolyDP(np.array(pth, np.float32).reshape(-1, 1, 2), 8.0, False).reshape(-1, 2).astype(float)
    d0 = pl[0] - pl[1]; d0 /= max(1e-6, np.hypot(*d0)); pl = np.vstack([pl[0] + d0 * (W1 + cdist[pth[0][1], pth[0][0]]), pl])  # into the network
    spine = LineString([tuple(p) for p in pl])
    Ls = spine.length
    lane_line = _sub(spine, 0, max(10, Ls - 150))
    lane = lane_line.buffer(LANE / 2, cap_style=2, join_style=2).intersection(OUTLINE)
    arm_lanes.append(lane)
    tpa = np.array(spine.coords[-1]); tq = np.array(spine.interpolate(Ls - 160).coords[0]); u = (tpa - tq) / max(1e-6, np.hypot(*(tpa - tq)))
    plat = LineString([tuple(tq), tuple(tpa + u * 80)]).buffer(400, cap_style=2).intersection(OUTLINE.buffer(-4))
    if plat.geom_type != "Polygon" and not plat.is_empty: plat = min(plat.geoms, key=lambda q_: q_.distance(Point(*tpa)))
    DOCKS["Docking Platform %s%d" % (side, idx)] = plat
    k = 0; rr = W1 + 60
    while rr + GATE_W < Ls - 170:               # airport gates down both sides of the lane
        a_ = np.array(spine.interpolate(rr).coords[0]); b_ = np.array(spine.interpolate(rr + GATE_W).coords[0])
        u2 = (b_ - a_) / max(1e-6, np.hypot(*(b_ - a_))); v2 = np.array([-u2[1], u2[0]]); c0 = (a_ + b_) / 2
        for sgn, nm in ((1, "L"), (-1, "R")):
            gate = LineString([tuple(c0 + v2 * sgn * LANE / 2), tuple(c0 + v2 * sgn * 400)]).buffer(GATE_W / 2, cap_style=2).intersection(OUTLINE.buffer(-4))
            gate = gate.difference(core.buffer(W1)).difference(plat.buffer(T))
            if gate.geom_type != "Polygon" and not gate.is_empty: gate = max(gate.geoms, key=lambda q_: q_.area)
            if not gate.is_empty and gate.area > 1200 and gate.distance(lane) < 2: DOCKS["Dock Gate %s%d-%d%s" % (side, idx, k + 1, nm)] = gate
        k += 1; rr += GATE_W + GATE_GAP
net = unary_union([walkway] + arm_lanes).intersection(OUTLINE)
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
for k_, g_ in DOCKS.items():
    g_ = g_.difference(net.buffer(T / 2))
    if g_.geom_type != "Polygon" and not g_.is_empty: g_ = max(g_.geoms, key=lambda q: q.area)
    if not g_.is_empty and g_.area > 1500: R[k_] = g_
docks = unary_union(list(R.values()))
cells = core.intersection(OUTLINE).difference(net.buffer(T / 2)).difference(docks.buffer(T / 2))
n_unnamed = 0; used = set()
for c in sorted(getattr(cells, "geoms", [cells]), key=lambda c: (round(c.centroid.y / 50), c.centroid.x)):
    if c.area < 900: continue
    name = next((k for k, p in LABELS.items() if k not in used and c.contains(p)), None)
    if name is None:
        n_unnamed += 1; name = "Service Block %s%d" % ("W" if c.centroid.x < AX else "E", n_unnamed)
    used.add(name); R[name] = c.simplify(0.8)
# sheet names not inside any block go to the nearest unnamed block of about the same place
for nm, p in LABELS.items():
    if nm in R: continue
    cand = [(R[k].distance(p), k) for k in R if k.startswith("Service Block")]
    if cand:
        d, k = min(cand)
        if d < 140: R[nm] = R.pop(k)
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
NO_INSET = ("Central Hub", "Cargo Terminal B", "Cargo Terminal D", "Commerce District (South")   # (the two pointed wedges: a band would close their door)
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
    if k.startswith(NO_INSET) or k.startswith("Dock") or g.area < 12000:   # small blocks: no room for a band
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

S = Ship("liberty_hub_main", HERE, SRC, AX, R, pieces, DOORS, start=(AX, CY + RA + 4), center_y=CY)
if __name__ == "__main__":
    cov = sum(g.area for g in R.values()) / OUTLINE.area
    print("rooms cover %.0f %% of the deck" % (100 * cov)); print("unnamed blocks:", n_unnamed, "| sheet names not placed:", [k for k in SHEET if k not in R])
    bad = run(S)
    if bad:                                     # a block no door can reach is structure / service space, not a room
        print("made service space:", bad)
        for k in bad: R.pop(k, None)
        S = Ship("liberty_hub_main", HERE, SRC, AX, R, pieces, DOORS, start=(AX, CY + RA + 4), center_y=CY)
        bad = run(S)
    sys.exit(1 if bad else 0)
