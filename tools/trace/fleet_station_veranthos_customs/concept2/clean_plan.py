#!/usr/bin/env python3
"""Engineering-clean redraw of the traced Veranthos Customs mech / pilot ways (owner, Nov 18 2026: "lines need to be
parallel like real rooms, good real shapes, not little nippets"). Nothing is redrawn by hand: the traced masks
(trace_ways.py -> masks.npz, 4x) are measured and rebuilt as clean geometry:

 MECH WAYS  the centre line of every red way is traced as a graph; a run that keeps one distance from the hub is a true
            ARC (ring walkway), any other run is straightened into 0 / 45 / 90 deg legs; each run gets ONE width (its own
            measured width, rounded to the nearest of three standard widths), so both walls are always parallel
 ROOMS      every space the clean mech ways close in is a block; its room is the block pulled in by one service band,
            so each room wall runs parallel to the walkway wall beside it. A block that was mostly blue on the map is a
            PILOT room (blue); the others are service / mech space (dark)
 MIRROR     built on the left half and mirrored exactly about the hub
Output: clean_plan.png, clean_on_map.jpg, clean_plan.json (source px)."""
import json, math, os
from collections import deque
import cv2, numpy as np
from skimage.morphology import skeletonize
from shapely.geometry import Polygon, LineString, Point, box, mapping
from shapely.ops import unary_union
from shapely import affinity

HERE = os.path.dirname(os.path.abspath(__file__))
Z, AXS = 4, 553
M_ = np.load(os.path.join(HERE, "masks.npz")); floor, mech, pilot = M_["floor"], M_["mech"], M_["pilot"]
H, W = mech.shape; AX = AXS * Z
# the hub (middle of the round centre): the row where the mech ring's inner edge is widest on the axis
ys = np.where(mech[:, AX] > 0)[0]
CYH = 515 * Z
WIDTHS = np.array([7, 10, 14]) * Z           # three standard way widths (map px x Z): side way, ring / main way, arm lane
BAND = 4 * Z                                 # service band between a way and the room beside it

# ---- centre lines (left half only; the right is the mirror)
half = mech.copy(); half[:, AX + 2:] = 0
sk = skeletonize(half > 0).astype(np.uint8)
dist = cv2.distanceTransform(mech, cv2.DIST_L2, 5)
NB8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
def nbrs(p):
    y, x = p; return [(y + a, x + b) for a, b in NB8 if 0 <= y + a < H and 0 <= x + b < W and sk[y + a, x + b]]
for _ in range(12 * Z):                      # prune spurs (bumps from lights and props)
    deg = cv2.filter2D(sk, -1, np.ones((3, 3)), borderType=0) - 1
    e = (sk > 0) & (deg <= 1); e[:, AX - 2:] = False
    if not e.any(): break
    sk[e] = 0
deg = cv2.filter2D(sk, -1, np.ones((3, 3)), borderType=0) - 1
pix = set(map(tuple, np.argwhere(sk > 0)))
node = {p for p in pix if deg[p] != 2}
seen = set(); runs = []
def walk(a, b):
    path = [a, b]; prev, cur = a, b
    while cur not in node:
        nx = [q for q in nbrs(cur) if q != prev and (min(cur, q), max(cur, q)) not in seen]
        if not nx: break
        seen.add((min(cur, nx[0]), max(cur, nx[0]))); prev, cur = cur, nx[0]; path.append(cur)
    return path
for a in node:
    for b in nbrs(a):
        e = (min(a, b), max(a, b))
        if e not in seen: seen.add(e); runs.append(walk(a, b))
for p in pix:
    if p in node or any((min(p, q), max(p, q)) in seen for q in nbrs(p)): continue
    q = nbrs(p)
    if q: seen.add((min(p, q[0]), max(p, q[0]))); runs.append(walk(p, q[0]))

def snap_leg(p):
    """straight legs: 0 / 45 / 90 deg, corners rebuilt where two legs cross"""
    p = cv2.approxPolyDP(np.array(p, np.float32).reshape(-1, 1, 2), 9.0 * Z, False).reshape(-1, 2).astype(float)
    if len(p) < 2: return p
    # merge neighbouring legs that snap to the same angle (no staircase)
    keep = [p[0]]
    for k in range(1, len(p) - 1):
        a1 = round(math.degrees(math.atan2(*(p[k] - keep[-1])[::-1])) / 45); a2 = round(math.degrees(math.atan2(*(p[k + 1] - p[k])[::-1])) / 45)
        if a1 != a2 and np.hypot(*(p[k] - keep[-1])) > 6 * Z: keep.append(p[k])
    keep.append(p[-1]); p = np.array(keep)
    d = np.diff(p, axis=0); ang = np.degrees(np.arctan2(d[:, 1], d[:, 0])); sn = np.round(ang / 45) * 45
    u = np.stack([np.cos(np.radians(sn)), np.sin(np.radians(sn))], 1); mid = (p[:-1] + p[1:]) / 2
    out = [mid[0] + np.dot(p[0] - mid[0], u[0]) * u[0]]
    for k in range(1, len(p) - 1):
        A = np.array([u[k - 1], -u[k]]).T
        if abs(np.linalg.det(A)) > 1e-6:
            t = np.linalg.solve(A, mid[k] - mid[k - 1]); out.append(mid[k - 1] + t[0] * u[k - 1])
        else: out.append(mid[k] + np.dot(p[k] - mid[k], u[k]) * u[k])
    out.append(mid[-1] + np.dot(p[-1] - mid[-1], u[-1]) * u[-1])
    return np.array(out)
lines = []
for r in runs:
    if len(r) < 6 * Z: continue
    xy = np.array([(x, y) for y, x in r], float)
    wid = float(np.median([dist[y, x] for y, x in r])) * 2
    w = float(WIDTHS[np.argmin(np.abs(WIDTHS - wid))])
    rad = np.hypot(xy[:, 0] - AX, xy[:, 1] - CYH); ang = np.degrees(np.arctan2(xy[:, 1] - CYH, xy[:, 0] - AX))
    span = np.ptp(np.unwrap(np.radians(ang))) * 180 / math.pi
    if rad.std() < 2.5 * Z and span > 25:                      # a ring walkway: a true arc
        R = round(rad.mean() / Z) * Z
        a0, a1 = np.radians(ang[0]), np.radians(ang[-1]); aa = np.unwrap([a0, a1])
        ts = np.linspace(aa[0], aa[1], max(8, int(abs(aa[1] - aa[0]) * 180 / math.pi / 2)))
        g = LineString([(AX + R * math.cos(t), CYH + R * math.sin(t)) for t in ts])
    else:
        g = LineString(snap_leg(xy))
    if g.length > 4 * Z: lines.append((g, w))
# ---- the ARMS: one straight lane each, fitted to the red pixels of that arm (no staircase)
cs0, _ = cv2.findContours(floor, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
oc = cv2.approxPolyDP(max(cs0, key=cv2.contourArea), 7.0 * Z, True).reshape(-1, 2).astype(float)
rad0 = np.hypot(oc[:, 0] - AX, oc[:, 1] - CYH)
tips = []
for k in range(len(oc)):
    if oc[k][0] > AX - 20 * Z or rad0[k] < 330 * Z: continue
    if rad0[k] >= max(rad0[(k + d) % len(oc)] for d in (-2, -1, 1, 2)): tips.append(oc[k])
ARMZ, ARM_LANES = [], []
my, mx = np.nonzero(mech); mrad = np.hypot(mx - AX, my - CYH); mang = np.degrees(np.arctan2(my - CYH, mx - AX))
for tp in tips:
    ta = math.degrees(math.atan2(tp[1] - CYH, tp[0] - AX)); tr = math.hypot(tp[0] - AX, tp[1] - CYH)
    sel = (np.abs((mang - ta + 180) % 360 - 180) < 9) & (mrad > 0.55 * tr) & (mrad < tr)
    if sel.sum() < 200: continue
    pts = np.stack([mx[sel], my[sel]], 1).astype(np.float32)
    vx, vy, x0, y0 = cv2.fitLine(pts, cv2.DIST_HUBER, 0, 0.01, 0.01).ravel()
    if vx * (tp[0] - AX) + vy * (tp[1] - CYH) < 0: vx, vy = -vx, -vy
    tt = (pts[:, 0] - x0) * vx + (pts[:, 1] - y0) * vy
    a_, b_ = (x0 + vx * tt.min(), y0 + vy * tt.min()), (x0 + vx * tt.max(), y0 + vy * tt.max())
    lane = LineString([(a_[0] - vx * 20 * Z, a_[1] - vy * 20 * Z), b_])
    ARM_LANES.append(lane.buffer(WIDTHS[2] / 2, cap_style=2))
    ARMZ.append(Polygon([(AX, CYH), (AX + 2 * tr * math.cos(math.radians(ta - 13)), CYH + 2 * tr * math.sin(math.radians(ta - 13))),
                         (AX + 2 * tr * math.cos(math.radians(ta + 13)), CYH + 2 * tr * math.sin(math.radians(ta + 13)))]).difference(Point(AX, CYH).buffer(0.58 * tr)))
armz = unary_union(ARMZ) if ARMZ else Polygon()
lines = [(g, w) for g, w in lines if g.intersection(armz).length < 0.4 * g.length]
pads = [p for p in pads if not armz.contains(p.centroid)] if 'pads' in dir() else []
print("arms", len(ARM_LANES))
ways_half = unary_union([g.buffer(w / 2, cap_style=2, join_style=2) for g, w in lines] + ARM_LANES)
# nodes: square-cornered pads where ways meet, so junctions are clean
pads = []
for p in node:
    if deg[p] >= 3:
        wid = float(WIDTHS[np.argmin(np.abs(WIDTHS - dist[p] * 2))]); pads.append(Point(p[1], p[0]).buffer(wid / 2, cap_style=3))
pads = [p for p in pads if not armz.contains(p.centroid)]
ways_half = unary_union([ways_half] + pads)
mir = lambda g: affinity.scale(g, -1, 1, origin=(AX, 0))
FLOOR = None
cs, _ = cv2.findContours(floor, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
fl = Polygon(cv2.approxPolyDP(max(cs, key=cv2.contourArea), 7.0 * Z, True).reshape(-1, 2)).buffer(0)
flh = fl.intersection(box(0, 0, AX, H)); FLOOR = unary_union([flh, mir(flh)]).buffer(0.5).buffer(-0.5)
WAYS = unary_union([ways_half.intersection(box(0, 0, AX + 1, H)), mir(ways_half.intersection(box(0, 0, AX + 1, H)))]).intersection(FLOOR)
WAYS = max(getattr(WAYS, "geoms", [WAYS]), key=lambda q: q.area)            # the one connected network

# ---- rooms: every block the ways close in, pulled in by the service band (walls parallel to the ways)
blocks = FLOOR.difference(WAYS)
pil = pilot.astype(bool)
PILOT, SERVICE = [], []
for b in getattr(blocks, "geoms", [blocks]):
    if b.centroid.x > AX + 1 or b.area < (12 * Z) ** 2: continue            # left half; the right is mirrored
    rm = b.buffer(-BAND, join_style=2)
    if rm.is_empty: continue
    for r in getattr(rm, "geoms", [rm]):
        if r.area < (10 * Z) ** 2: continue
        r = r.simplify(3.5 * Z)
        q = snap_leg(np.array(r.exterior.coords))
        rq = (Polygon(q).buffer(0) if len(q) >= 4 else r).intersection(rm)   # never past the block's band
        if rq.geom_type != "Polygon" and not rq.is_empty: rq = max(rq.geoms, key=lambda g_: g_.area)
        if not rq.is_empty and rq.geom_type == "Polygon" and rq.area > 0.85 * r.area: r = rq
        m1 = np.zeros((H, W), np.uint8); cv2.fillPoly(m1, [np.array(r.exterior.coords, np.int32)], 1)
        frac = pil[m1 > 0].mean() if m1.any() else 0
        (PILOT if frac > 0.30 else SERVICE).append(r)
def both(gs):
    out = []
    for g in gs:
        out.append(g)
        if g.bounds[2] < AX - 1: out.append(mir(g))
    return out
PILOT, SERVICE = both(PILOT), both(SERVICE)

RED, BLUE, NAVY = (60, 50, 215), (235, 130, 40), (90, 50, 28)
def fill(img, g, col):
    for p in getattr(g, "geoms", [g]):
        m1 = np.zeros(img.shape[:2], np.uint8); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 1)
        for h in p.interiors: cv2.fillPoly(m1, [np.array(h.coords, np.int32)], 0)
        img[m1 > 0] = col
def outline(img, g, col, t):
    for p in getattr(g, "geoms", [g]):
        for ring in [p.exterior] + list(p.interiors): cv2.polylines(img, [np.array(ring.coords, np.int32)], True, col, t, cv2.LINE_AA)
def draw(base, alpha):
    img = base.copy(); f = img.copy()
    fill(f, FLOOR, (60, 36, 20)); fill(f, WAYS, RED)
    for g in PILOT: fill(f, g, BLUE)
    for g in SERVICE: fill(f, g, NAVY)
    img = cv2.addWeighted(f, alpha, img, 1 - alpha, 0)
    outline(img, FLOOR, (255, 255, 255), Z); outline(img, WAYS, (255, 255, 255), Z // 2 + 1)
    for g in PILOT + SERVICE: outline(img, g, (255, 255, 255), Z // 2 + 1)
    return cv2.resize(img, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
src = cv2.resize(cv2.imread(os.path.join(HERE, "source.png")), (W, H), interpolation=cv2.INTER_CUBIC)
cv2.imwrite(os.path.join(HERE, "clean_plan.png"), draw(np.full((H, W, 3), (40, 22, 8), np.uint8), 1.0))
cv2.imwrite(os.path.join(HERE, "clean_on_map.jpg"), draw((src * 0.5).astype(np.uint8), 0.6), [cv2.IMWRITE_JPEG_QUALITY, 88])
sc = lambda g: mapping(affinity.scale(g, 1 / Z, 1 / Z, origin=(0, 0)))
json.dump({"units": "source px", "axis_x": AXS, "hub_y": CYH / Z, "floor": sc(FLOOR), "mech_ways": sc(WAYS),
           "pilot_rooms": [sc(g) for g in PILOT], "service": [sc(g) for g in SERVICE]}, open(os.path.join(HERE, "clean_plan.json"), "w"))
print("runs", len(lines), "pilot rooms", len(PILOT), "service blocks", len(SERVICE))
