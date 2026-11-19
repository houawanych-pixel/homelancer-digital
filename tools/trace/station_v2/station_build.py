#!/usr/bin/env python3
"""Station v2 builder: any station model -> five decks in the SHIP construction (the method the owner approved on
Liberty Hub, v13.220-227, Nov 2026). One script for every faction station; Liberty Hub's per-deck scripts
(fleet_station_liberty_v2/decks/*.py) were the template.

  outlines   the model's own slices (station_plans.deck_outlines), turned so the mirror axis is vertical, scaled so
             the main deck has Liberty Hub's floor area (ship scale: 10 px = 1 m), mirror-true about x = C
  lifts      the lift centre is the point on the axis deepest inside every deck; the four lift shafts sit at the same
             place on every deck (same boxes as Liberty Hub), so one elevator runs through all five decks
  walkways   octagon rings with 45 deg corners (ring A by the lifts, ring B, the outer ring P fitted to the deck), the
             cross (N/S/E/W) out to pads at the hull ends, side lanes A->B and B->P, the arms: a straight lane or an
             angled lane (planlib.dhall) off the outer ring's corner out to a pad at every arm tip
  rooms      the deck's hub in the middle, district rooms in the band between ring B and P, then small rooms from the
             owner's room library (room_library/kit.json) along every straight walkway, right half first, mirrored
  names      per deck (HANGAR / ENGINEERING / MAIN HUB / HABITAT / COMMAND); the main deck carries the eight 360
             service rooms (Mission Center, Shipyard, ...)

usage: python3 -I tools/trace/station_v2/station_build.py <sid> <model> "<Station name>" [deck ...]
       decks: lower2 lower main upper upper2 (default all). Writes tools/trace/fleet_<sid>/ (source.jpg, hull.json,
       decks/outlines.json, decks/<deck>_plan.jpg, eng/plan.json, eng/deck_<deck>.json, eng/overrides.json,
       eng/gameplay.json first pass). Then run station_v2/finish.sh <sid>."""
import json, math, os, sys, hashlib
import cv2, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); TR = os.path.join(HERE, "..")
sys.path.insert(0, TR)
import planlib
from planlib import hall, dhall, Ship, run, DOOR
import station_plans as SP
from shapely.geometry import Polygon, box, Point, shape, mapping, LineString
from shapely import affinity
from shapely.ops import unary_union
from shapely.strtree import STRtree

C, NPX = 1650.0, 3300
MW, PW = 34.0, 20.0
A_HUB, A_A = 128.0, 232.0
LIB_AREA = 3817526.0                     # Liberty Hub main deck floor (px^2): every station is built at that size
LIFTS = {"Lift (north)": ((1667, 1332, 1729, 1402), (1667.0, 1367.0, "v")), "Lift (south)": ((1667, 1898, 1729, 1968), (1667.0, 1933.0, "v")),
         "Lift (East)": ((1898, 1571, 1968, 1633), (1933.0, 1633.0, "h")), "Lift (West)": ((1332, 1571, 1402, 1633), (1367.0, 1633.0, "h"))}
LIFT_AT = [[1698, 1367], [1698, 1933], [1933, 1602], [1367, 1602]]   # (v13.229: south = the north mirrored, so a ring of 342+ clears all four)
DECKS = [("lower2", "HANGAR", -2), ("lower", "ENGINEERING", -1), ("main", "MAIN HUB", 0), ("upper", "HABITAT", 1), ("upper2", "COMMAND", 2)]
ROLE = {
    "HANGAR": dict(dist=["Freight Hall", "Drone Bay", "Fighter Deck"], hub="Flight Control", pad="Launch Pad", word="Hangar",
                   big=["Launch Bay A", "Launch Bay B", "Mech Bay A", "Mech Bay B", "Cargo Staging East", "Vehicle Bay East", "Cargo Staging West", "Vehicle Bay West"]),
    "ENGINEERING": dict(dist=["Fusion Plant", "Coolant Plant", "Fabrication Hall"], hub="Reactor Core", pad="Repair Bay", word="Engine",
                        big=["Engine Control A", "Engine Control B", "Power Routing A", "Power Routing B", "Turbine Hall NE", "Turbine Hall SE", "Turbine Hall NW", "Turbine Hall SW"]),
    "MAIN HUB": dict(dist=["Trade Plaza", "Transit Hall", "Arrivals Hall"], hub="Main Hub", pad="Dock Pad", word="Concourse",
                     big=["Docking Hall A", "Docking Hall B", "Customs A", "Customs B", "Market East", "Cargo Exchange East", "Market West", "Cargo Exchange West"]),
    "HABITAT": dict(dist=["Garden Dome", "Housing Block", "Recreation Hall"], hub="Commons", pad="Observation Pod", word="Residential",
                    big=["Crew Quarters A", "Crew Quarters B", "Mess Hall A", "Mess Hall B", "Hydroponics East", "Gym East", "Hydroponics West", "Gym West"]),
    "COMMAND": dict(dist=["Fleet Ops", "Intelligence Hall", "Flag Office"], hub="Bridge", pad="Command Pod", word="Command",
                    big=["Tactical A", "Tactical B", "Comms A", "Comms B", "War Room East", "Security Center East", "War Room West", "Security Center West"]),
}
MECH_BIG = ("Freight Hall", "Drone Bay", "Fighter Deck", "Fusion Plant", "Coolant Plant", "Fabrication Hall", "Trade Plaza", "Transit Hall", "Arrivals Hall", "Garden Dome", "Recreation Hall", "Fleet Ops", "Launch Bay", "Mech Bay", "Cargo Staging", "Vehicle Bay", "Engine Control", "Power Routing", "Turbine Hall", "Docking Hall",
            "Cargo Exchange", "Hydroponics", "Gym", "Tactical", "War Room")
PILOT_WORDS = ["Cabin", "Office", "Quarters", "Store", "Lobby", "Canteen", "Lounge", "Clinic", "Control"]
MECH_WORDS = ["Cargo Bay", "Plant", "Machine Shop", "Armoury", "Loading Bay", "Bay"]
SERVICES_MECH = ["Shipyard", "Mech Dealer", "Supplies", "Weapons"]
SERVICES_PILOT = ["Mission Center", "Pilots' Lounge", "Medical Bay", "Command"]

# ------------------------------------------------------------------ the room library (owner's kit, metres)
KIT = []
for p in json.load(open(os.path.join(TR, "room_library", "kit.json")))["pieces"]:
    g = Polygon(p["poly"]).buffer(0)
    if g.geom_type != "Polygon": g = max(g.geoms, key=lambda q: q.area)
    g = Polygon(g.exterior).simplify(0.12)
    x0, y0, x1, y1 = g.bounds
    if min(x1 - x0, y1 - y0) < 1.5: continue
    fill = g.area / ((x1 - x0) * (y1 - y0))
    if fill < 0.62: continue                      # (spindly shapes make slivers when stretched to a slot)
    KIT.append({"id": p["id"], "g": affinity.translate(g, -(x0 + x1) / 2, -(y0 + y1) / 2), "ar": (x1 - x0) / (y1 - y0), "m2": p["area_m2"]})

def pick(w, h, seed, mech):
    ar = w / h; ok = []
    for r in KIT:
        if mech and r["m2"] < 30: continue
        if not mech and r["m2"] > 80: continue
        for rot in (0, 90):
            a = r["ar"] if rot == 0 else 1 / r["ar"]
            if 1 / 1.35 <= a / ar <= 1.35: ok.append((r, rot))
    if not ok: return box(-w / 2, -h / 2, w / 2, h / 2), None
    r, rot = ok[seed % len(ok)]
    g = affinity.rotate(r["g"], 90, origin=(0, 0)) if rot else r["g"]
    x0, y0, x1, y1 = g.bounds
    return affinity.scale(g, w / (x1 - x0), h / (y1 - y0), origin=(0, 0)).simplify(0.6), r["id"]

def octo(cx, cy, hw, hh, c):
    return Polygon([(cx - hw + c, cy - hh), (cx + hw - c, cy - hh), (cx + hw, cy - hh + c), (cx + hw, cy + hh - c),
                    (cx + hw - c, cy + hh), (cx - hw + c, cy + hh), (cx - hw, cy + hh - c), (cx - hw, cy - hh + c)])
CUT = 1 - math.tan(math.radians(22.5))
def cut_of(hw, hh): return CUT * min(hw, hh)

# ------------------------------------------------------------------ outlines
def outlines(model):
    O = SP.deck_outlines({"model": model})
    polys = [p.buffer(0) for p in O["polys"]]
    # a deck the slices were too broken for came back as the top silhouette (the same for the top and bottom deck):
    # use the model's own slice nearest that height, between it and the hub, that is a usable floor (owner: every
    # floor its own silhouette)
    for k in (0, 1, 3, 4):
        if O["src"][k] != "silhouette": continue
        i0, hub = O["idx"][k], O["idx"][2]
        step = 1 if hub > i0 else -1
        for i in range(i0, hub, step):
            q = SP.outline(SP.clean(O["masks"][i]))
            if q is None or q.area < 0.35 * polys[2].area or q.length / math.sqrt(q.area) > 14.0: continue
            if any(q.symmetric_difference(polys[j]).area < 0.05 * q.area for j in range(5) if j != k): continue
            polys[k] = q.buffer(0); O["src"][k] = "slice %d" % i; break
    main = polys[2]
    # the mirror axis: vertical or horizontal, wherever the main slice matches its own mirror best
    def sym(g, vertical):
        best = (0, 0)
        x0, y0, x1, y1 = g.bounds
        lo, hi = (x0, x1) if vertical else (y0, y1)
        for t in np.linspace(lo + (hi - lo) * 0.3, lo + (hi - lo) * 0.7, 41):
            m = affinity.scale(g, -1, 1, origin=(t, 0)) if vertical else affinity.scale(g, 1, -1, origin=(0, t))
            iou = g.intersection(m).area / g.union(m).area
            if iou > best[0]: best = (iou, t)
        return best
    v, h = sym(main, True), sym(main, False)
    turn = h[0] > v[0] + 0.03
    if turn:   # (turn 90 deg so the axis is vertical)
        polys = [affinity.rotate(p, 90, origin=(SP.N / 2, SP.N / 2)) for p in polys]; v = sym(polys[2], True)
    ax = v[1]
    # the lift centre: on the axis, the point deepest inside every deck
    dts = []
    for p in polys:
        m = np.zeros((SP.N, SP.N), np.uint8); cv2.fillPoly(m, [np.array(p.exterior.coords, np.int32)], 255)
        dts.append(cv2.distanceTransform(m, cv2.DIST_L2, 5))
    col = int(round(ax)); prof = np.min([d[:, col] for d in dts], 0)
    prof2 = dts[2][:, col] * 0.25 + prof              # (prefer the main deck's middle a little)
    ly = float(np.argmax(prof2))
    k = 5.35 * math.sqrt(LIB_AREA / 5.35 ** 2 / main.area)
    x0, y0, x1, y1 = main.bounds
    k = min(k, 3100 / max(2 * max(ax - x0, x1 - ax), 1), 3100 / max(2 * max(ly - y0, y1 - ly), 1))
    out = []
    for p in polys:
        g = affinity.translate(p, C - ax, C - ly); g = affinity.scale(g, k, k, origin=(C, C))
        L = g.intersection(box(0, 0, C, NPX)); R_ = g.intersection(box(C, 0, NPX, NPX))
        half = L if L.area >= R_.area else affinity.scale(R_, -1, 1, origin=(C, 0))
        g = half.union(affinity.scale(half, -1, 1, origin=(C, 0))).buffer(1).buffer(-1)
        # every deck holds the lift core (the shafts run through all five)
        g = g.union(octo(C, C, 380, 380, 380 * CUT)).buffer(0)
        if g.geom_type != "Polygon": g = max(g.geoms, key=lambda q: q.area)
        out.append(Polygon(g.exterior).intersection(box(20, 20, NPX - 20, NPX - 20)))
    return out, {"turn": turn, "axis": ax, "lift_y": ly, "k": k, "depth_m": float(prof[int(ly)]) * k / 10}

# ------------------------------------------------------------------ one deck
def build_deck(HULL0, role, sid, name, here, src):
    planlib.DIAG.clear()
    HULL = HULL0.buffer(-12)
    INNER = HULL.buffer(-MW / 2 - 64, join_style=2)
    R, HALLS, DOORS, SEGS, NAMES = {}, [], [], [], ROLE[role]
    def node(x, y, w):
        g = box(x - w / 2, y - w / 2, x + w / 2, y + w / 2); HALLS.append(g); return g
    # ---- ring P: the biggest octagon (45 deg corners) that fits the deck with a row of rooms outside it
    best = None
    for r_ in np.linspace(0.45, 2.6, 30):
        lo_, hi_ = 150.0, 1450.0
        for _ in range(22):
            mid = (lo_ + hi_) / 2; hw, hh = min(mid * r_, 1450), mid
            if INNER.contains(octo(C, C, hw + MW / 2, hh + MW / 2, cut_of(hw, hh))): lo_ = mid
            else: hi_ = mid
        hw, hh = min(lo_ * r_, 1450), lo_
        if INNER.contains(octo(C, C, hw + MW / 2, hh + MW / 2, cut_of(hw, hh))) and (best is None or hw * hh > best[0] * best[1]): best = (hw, hh)
    DY = 0.0
    if not best or min(best) < 342:
        # a deck too tight round the lifts for a ring with rooms outside it: the ring may hug the hull, and sit off
        # the lift centre up or down, as long as it still clears the four shafts (its sides 342+ from the centre)
        IN2 = HULL.buffer(-MW / 2 - 10, join_style=2); best2 = None
        for dy_ in np.arange(-320.0, 321.0, 20.0):
            for r_ in np.linspace(0.45, 2.6, 18):
                lo_, hi_ = 150.0, 1450.0
                for _ in range(18):
                    mid = (lo_ + hi_) / 2; hw, hh = min(mid * r_, 1450), mid
                    if IN2.contains(octo(C, C + dy_, hw + MW / 2, hh + MW / 2, cut_of(hw, hh))): lo_ = mid
                    else: hi_ = mid
                hw, hh = min(lo_ * r_, 1450), lo_
                if hh - abs(dy_) >= 342 and hw >= 342 and IN2.contains(octo(C, C + dy_, hw + MW / 2, hh + MW / 2, cut_of(hw, hh))) and (best2 is None or hw * hh > best2[0] * best2[1]):
                    best2 = (hw, hh, dy_)
        if best2: best, DY = best2[:2], float(best2[2])
    RINGS = [(A_A, A_A)]
    if best and min(best) >= 342:   # (an outer ring nearer than that would run through the lift shafts)
        P_ = best; RINGS.append(((A_A + P_[0]) / 2, (A_A + P_[1]) / 2) if min(P_) >= 560 and DY == 0 else None); RINGS.append(P_)
        RINGS = [q for q in RINGS if q]
    hwP, hhP = RINGS[-1]; cP = cut_of(hwP, hhP)
    def verts(cx, cy, hw, hh):
        c = cut_of(hw, hh)
        return [(cx + hw - c, cy - hh), (cx + hw, cy - hh + c), (cx + hw, cy + hh - c), (cx + hw - c, cy + hh),
                (cx - hw + c, cy + hh), (cx - hw, cy + hh - c), (cx - hw, cy - hh + c), (cx - hw + c, cy - hh)]
    def ring(rg, w=MW):
        cx, cy, hw, hh, breaks = rg["cx"], rg["cy"], rg["hw"], rg["hh"], rg["breaks"]
        V = verts(cx, cy, hw, hh)
        for v in V: node(v[0], v[1], w)
        for i in range(0, 8, 2):
            HALLS.append(hall(V[(i - 1) % 8], V[i], w=w))
        for i in range(0, 8, 2):
            p, q = V[i], V[i + 1]
            pts = [p] + sorted(breaks.get(i, []), key=lambda t: math.hypot(t[0] - p[0], t[1] - p[1])) + [q]
            for t in pts[1:-1]: node(t[0], t[1], w)
            for u, v in zip(pts, pts[1:]):
                sx = 1 if v[0] > u[0] else -1; sy = 1 if v[1] > u[1] else -1
                HALLS.append(dhall((u[0] + sx * w / 2, u[1] + sy * w / 2), (v[0] - sx * w / 2, v[1] - sy * w / 2), w=w, axis="x"))
        c = cut_of(hw, hh)
        SEGS.extend([(cx - hw + c, cy - hh, cx + hw - c, cy - hh, w), (cx - hw + c, cy + hh, cx + hw - c, cy + hh, w),
                     (cx - hw, cy - hh + c, cx - hw, cy + hh - c, w), (cx + hw, cy - hh + c, cx + hw, cy + hh - c, w)])
        return V
    RG = [{"cx": C, "cy": C, "hw": hw, "hh": hh, "breaks": {}} for hw, hh in RINGS]
    if len(RG) > 1: RG[-1]["cy"] = C + DY
    MAINP = RG[-1]
    CORNER = lambda rg, x, y: (0 if y < rg["cy"] else 2) if x > rg["cx"] else (6 if y < rg["cy"] else 4)
    PADS, LINKS, DIST = [], [], []
    def pad_at(p, u, room):
        # the biggest pad (up to 60 px half) on the line p + t u, as far out as fits
        L = 0
        while HULL.contains(Point(p[0] + u[0] * (L + 10), p[1] + u[1] * (L + 10))) and L < 2000: L += 10
        for kk in range(80):
            d = L - 40 - 10 * kk
            if d < 3 * MW: return None
            cx, cy = p[0] + u[0] * d, p[1] + u[1] * d
            for hw in (60, 52, 45, 38):
                if HULL.contains(box(cx - hw, cy - hw, cx + hw, cy + hw)): return (cx, cy, hw)
        return None
    # ---- districts: every big piece of floor the rings don't reach gets its own octagon ring (a square one) with a
    # district hall in the middle, linked to the nearest ring by a straight lane or a 45 deg lane corner to corner
    def dry_dhall(a, b, axis):
        n0 = len(planlib.DIAG); dhall(a, b, w=MW, axis=axis); out = [g.bounds for g in planlib.DIAG[n0:]]; del planlib.DIAG[n0:]
        return out
    def corner_boxes(rg, extra_pt):
        """the bounding boxes of a ring corner's angled pieces with one more break in it (what the converter will make)"""
        V = verts(rg["cx"], rg["cy"], rg["hw"], rg["hh"]); i = CORNER(rg, *extra_pt); p, q = V[i], V[i + 1]
        pts = [p] + sorted(rg["breaks"].get(i, []) + [extra_pt], key=lambda t: math.hypot(t[0] - p[0], t[1] - p[1])) + [q]
        out = []
        for u, v in zip(pts, pts[1:]):
            sx = 1 if v[0] > u[0] else -1; sy = 1 if v[1] > u[1] else -1
            out += dry_dhall((u[0] + sx * MW / 2, u[1] + sy * MW / 2), (v[0] - sx * MW / 2, v[1] - sy * MW / 2), "x")
        return out
    def boxes_hit(A, B):
        return any(a[0] < b[2] - 1 and b[0] < a[2] - 1 and a[1] < b[3] - 1 and b[1] < a[3] - 1 for a in A for b in B)
    def all_cb():
        CB = []   # (every ring corner's angled pieces: a pad's box must not sit over one)
        for rg in RG:
            V = verts(rg["cx"], rg["cy"], rg["hw"], rg["hh"])
            for i in range(0, 8, 2):
                p_, q_ = V[i], V[i + 1]; pts_ = [p_] + sorted(rg["breaks"].get(i, []), key=lambda t: math.hypot(t[0] - p_[0], t[1] - p_[1])) + [q_]
                for u_, v_ in zip(pts_, pts_[1:]):
                    sx_ = 1 if v_[0] > u_[0] else -1; sy_ = 1 if v_[1] > u_[1] else -1
                    CB += dry_dhall((u_[0] + sx_ * MW / 2, u_[1] + sy_ * MW / 2), (v_[0] - sx_ * MW / 2, v_[1] - sy_ * MW / 2), "x")
        return CB
    def ring_shape(rg, extra):
        return octo(rg["cx"], rg["cy"], rg["hw"] + extra, rg["hh"] + extra, cut_of(rg["hw"], rg["hh"]))
    def link(rg, Q, a, pad=False):
        """a lane from ring rg to a new square ring (centre Q, apothem a): straight when Q is in line with one of rg's
        straight sides, else 45 deg from rg's corner face to the new ring's facing corner (stubs at both ends)."""
        cx, cy, hw, hh = rg["cx"], rg["cy"], rg["hw"], rg["hh"]; c = cut_of(hw, hh); cq = cut_of(a, a)
        dx, dy = Q[0] - cx, Q[1] - cy
        out = []
        if abs(dx) <= hw - c - MW and abs(dy) > hh + a + 2 * MW:
            sy = math.copysign(1, dy); out.append(("s", [(Q[0], cy + sy * hh), (Q[0], Q[1] - sy * a)], "h"))
        if abs(dy) <= hh - c - MW and abs(dx) > hw + a + 2 * MW:
            sx = math.copysign(1, dx); out.append(("s", [(cx + sx * hw, Q[1]), (Q[0] - sx * a, Q[1])], "v"))
        sgx, sgy = (1 if dx > 0 else -1), (1 if dy > 0 else -1)
        s = (sgx * dx + sgy * dy - (hw + hh - c)) / 2
        r1 = (Q[0] - s * sgx, Q[1] - s * sgy)
        r2 = (Q[0] - (2 * a - cq) / 2 * sgx, Q[1] - (2 * a - cq) / 2 * sgy)
        # the far end meets the middle of the new ring's (or pad's) near side: a T, no break in a short corner
        r2 = (Q[0] - sgx * a, Q[1]) if abs(dx) - hw >= abs(dy) - hh else (Q[0], Q[1] - sgy * a)
        xo = min(max(sgx * (r1[0] - cx), hw - c + 1.2 * MW), hw - 1.2 * MW)   # (off the face: the nearest point on it)
        r1 = (cx + sgx * xo, cy + sgy * (hw + hh - c - xo))
        far_ok = all(abs(b_[0] - r1[0]) >= 1.8 * MW for b_ in rg["breaks"].get(CORNER(rg, *r1), []))
        if c > 3.6 * MW and far_ok:
            flat = abs(Q[0] - r1[0]) >= abs(Q[1] - r1[1])
            ends = []
            if not pad and cq > 3.6 * MW:   # (corner to corner: the new ring's facing 45 deg corner, a stub out of it)
                ends.append(((Q[0] - (2 * a - cq) / 2 * sgx, Q[1] - (2 * a - cq) / 2 * sgy), True))
            ends.append(((Q[0] - sgx * a, Q[1]) if flat else (Q[0], Q[1] - sgy * a), False))
            nr_ = {"cx": Q[0], "cy": Q[1], "hw": a, "hh": a, "breaks": {}}
            for r2, corner in ends:
                good = False
                for Ls in (1.5 * MW, 2.4 * MW, 3.4 * MW, 4.6 * MW, 6 * MW):   # the shortest stubs whose angled pieces clear the corners'
                    for Ls2 in ((1.5 * MW, 2.4 * MW, 3.4 * MW) if corner else (1.5 * MW,)):
                        if flat:   # (horizontal stubs, the angled lane cut by vertical lines: its ends meet the stubs' end faces)
                            st1 = (r1[0] + sgx * Ls, r1[1]); st2 = (r2[0] - sgx * Ls2, r2[1])
                            a0 = (st1[0] + sgx * MW / 2, st1[1]); b0 = (st2[0] - sgx * MW / 2, st2[1])
                            if (b0[0] - a0[0]) * sgx <= 2 * MW: continue
                        else:
                            st1 = (r1[0], r1[1] + sgy * Ls); st2 = (r2[0], r2[1] - sgy * Ls2)
                            a0 = (st1[0], st1[1] + sgy * MW / 2); b0 = (st2[0], st2[1] - sgy * MW / 2)
                            if (b0[1] - a0[1]) * sgy <= 2 * MW: continue
                        pcs = dry_dhall(a0, b0, "x" if flat else "y")
                        if boxes_hit(pcs, corner_boxes(rg, r1)) or (corner and boxes_hit(pcs, corner_boxes(nr_, r2))): continue
                        good = True; break
                    if good: break
                if good: out.append(("d", [r1, st1, a0, b0, st2, r2], "x" if flat else "y"))
        for kind, pts, o in out:
            g = (hall(*pts, w=MW) if kind == "s" else unary_union([hall(pts[0], pts[1], w=MW), LineString([pts[2], pts[3]]).buffer(MW / 2, cap_style=2), hall(pts[4], pts[5], w=MW)]))
            mid_ = g.difference(ring_shape(rg, MW / 2 + 74)).buffer(-2)
            if pad:
                if boxes_hit([box(Q[0] - a, Q[1] - a, Q[0] + a, Q[1] + a).buffer(4).bounds], all_cb()): continue
                g = g.union(box(Q[0] - a, Q[1] - a, Q[0] + a, Q[1] + a))
            ok_h, ok_t = HULL.contains(g.buffer(-2)), not mid_.intersects(TAKEN[0])
            if os.environ.get("SB_DEBUG"): print("  link", kind, ok_h, ok_t)
            if ok_h and ok_t: return (kind, pts, o, rg)
        return None
    TAKEN = [unary_union([ring_shape(r_, MW / 2 + 70) for r_ in RG])]
    CROSS = []
    # ---- the hub and the cross (out of the outer ring on to a pad wherever the hull runs on)
    hubname = NAMES["hub"] + (" (%s)" % name if role == "MAIN HUB" else "")
    R[hubname] = octo(C, C, A_HUB, A_HUB, A_HUB * 0.414)
    for dx, dy, lab in ((0, -1, "N"), (0, 1, "S"), (1, 0, "E"), (-1, 0, "W")):
        a1 = (MAINP["hh"] + dy * (MAINP["cy"] - C)) if dx == 0 else MAINP["hw"]
        if a1 < 360:   # (no outer ring: the cross runs on past the lift doors to a junction)
            a1 = 360.0; node(C + dx * a1, C + dy * a1, MW)
        HALLS.append(hall((C + dx * A_HUB, C + dy * A_HUB), (C + dx * a1, C + dy * a1), w=MW)); CROSS.append([(C + dx * A_HUB, C + dy * A_HUB), (C + dx * a1, C + dy * a1)])
        DOORS.append((C + dx * A_HUB, C + dy * A_HUB, "h" if dx == 0 else "v"))
        SEGS.append((C, C + dy * A_HUB, C, C + dy * a1, MW) if dx == 0 else (C + dx * A_HUB, C, C + dx * a1, C, MW))
        p = (C + dx * a1, C + dy * a1)
        pad = pad_at(p, (dx, dy), None)
        if pad and math.hypot(pad[0] - p[0], pad[1] - p[1]) > pad[2] + 220:
            cx, cy, hw = pad
            if dx == 0: cx = C
            else: cy = C
            if not HULL.contains(box(cx - hw, cy - hw, cx + hw, cy + hw)): continue
            e = (cx - dx * hw, cy - dy * hw)
            CROSS.append([p, e]); HALLS.append(hall(p, e, w=MW)); SEGS.append((p[0], min(p[1], e[1]), e[0], max(p[1], e[1]), MW) if dx == 0 else (min(p[0], e[0]), p[1], max(p[0], e[0]), e[1], MW))
            nm = "%s %s" % (NAMES["pad"], lab); R[nm] = octo(cx, cy, hw, hw, hw * 0.3)
            DOORS.append((round(e[0], 1), round(e[1], 1), "h" if dx == 0 else "v")); PADS.append(nm)
            TAKEN[0] = TAKEN[0].union(hall(p, e, w=MW + 2 * 100)).union(box(cx - hw, cy - hw, cx + hw, cy + hw).buffer(100))
    for _ in range(6):
        free = HULL.buffer(-(MW / 2 + 70), join_style=2).difference(TAKEN[0].buffer(MW / 2 + 70 - 4)).intersection(box(C + MW / 2 + 70, 0, NPX, NPX))
        pcs = sorted([q for q in getattr(free, "geoms", [free]) if q.geom_type == "Polygon" and q.area > 60000], key=lambda q: -q.area)
        made = False
        for q in pcs:
            m = np.zeros((NPX, NPX), np.uint8); cv2.fillPoly(m, [np.array(q.exterior.coords, np.int32)], 255)
            for h_ in q.interiors: cv2.fillPoly(m, [np.array(h_.coords, np.int32)], 0)
            dt = cv2.distanceTransform(m, cv2.DIST_L2, 5)
            a = float(dt.max()) * 0.92 - MW / 2
            if os.environ.get("SB_DEBUG"): print("piece", round(q.area), "a", round(a))
            if a < 100: continue
            Qy, Qx = np.unravel_index(int(np.argmax(dt)), dt.shape); Q = (float(Qx), float(Qy))
            a = min(a, 420.0)
            while a >= 100 and not q.buffer(MW / 2 + 70).contains(octo(Q[0], Q[1], a + MW / 2, a + MW / 2, cut_of(a, a))): a -= 8
            if a < 100: continue
            if os.environ.get("SB_DEBUG"): print("district try", [round(v) for v in Q], round(a), round(q.area))
            for rg in sorted([r_ for r_ in RG if r_ is MAINP or r_.get("district")], key=lambda r_: math.hypot(r_["cx"] - Q[0], r_["cy"] - Q[1])):
                L1 = link(rg, Q, a)
                Qm = (2 * C - Q[0], Q[1]); rgm = rg if rg["cx"] == C else next((r_ for r_ in RG if abs(r_["cx"] - (2 * C - rg["cx"])) < 1 and abs(r_["cy"] - rg["cy"]) < 1), None)
                L2 = link(rgm, Qm, a) if rgm else None
                if os.environ.get("SB_DEBUG"): print("  district links", bool(L1), bool(L2))
                if L1 and L2:
                    for (kind, pts, o, rg_), QQ in ((L1, Q), (L2, Qm)):
                        nr = {"cx": QQ[0], "cy": QQ[1], "hw": a, "hh": a, "breaks": {}, "district": True}
                        RG.append(nr); LINKS.append((kind, pts, o, rg_, nr))
                        if kind == "d":
                            rg_["breaks"].setdefault(CORNER(rg_, *pts[0]), []).append(pts[0])
                            if abs(abs(pts[5][0] - QQ[0]) - a) > 1 and abs(abs(pts[5][1] - QQ[1]) - a) > 1:   # (on its corner)
                                nr["breaks"].setdefault(CORNER(nr, *pts[5]), []).append(pts[5])
                        TAKEN[0] = TAKEN[0].union(ring_shape(nr, MW / 2 + 70)).union(hall(pts[0], pts[-1], w=MW + 40))
                    made = True; break
            if made: break
        if not made: break
    # ---- spurs: the narrower floor left over (wings, spikes) gets a lane from the nearest ring out to a pad at its tip
    SPURS = []
    from shapely.prepared import prep
    STRAIGHT = [[a_, b_] for kind, pts, o, rg_, nr in LINKS if kind == "s" for a_, b_ in [pts]] + CROSS
    def tspur(q):
        """a straight lane at right angles off any straight walkway side, as far into the piece q as it goes, a pad at
        its end (the longest such lane wins)"""
        segs = list(STRAIGHT)
        for rg in RG:
            V = verts(rg["cx"], rg["cy"], rg["hw"], rg["hh"])
            segs += [[V[7], V[0]], [V[1], V[2]], [V[3], V[4]], [V[5], V[6]]]
        HI, TK, QP = prep(HULL.buffer(-36)), prep(TAKEN[0]), prep(q)
        HIp = prep(HULL.buffer(-MW / 2 - 6))   # (angled lanes and lanes out of a pad may squeeze through a neck to a pod beyond)
        FREE = HULL.buffer(-12)
        CB = all_cb()
        padok = lambda bb: HULL.contains(bb) and not TK.intersects(bb) and not boxes_hit([bb.buffer(4).bounds], CB)
        best = None
        for (ax_, ay_), (bx_, by_) in segs:
            hz = abs(ay_ - by_) < 1
            lo, hi = (min(ax_, bx_), max(ax_, bx_)) if hz else (min(ay_, by_), max(ay_, by_))
            for u in np.arange(lo + MW / 2 + 6, hi - MW / 2 - 5, 12.0):
                for sd in (-1, 1):
                    x_, y_ = (u, ay_) if hz else (ax_, u)
                    if x_ < C + MW / 2 + 60: continue
                    dx_, dy_ = (0, sd) if hz else (sd, 0)
                    t = MW / 2
                    while t < 1600:
                        pt = Point(x_ + dx_ * (t + 10), y_ + dy_ * (t + 10))
                        if not HIp.contains(pt) or (t > 110 and TK.contains(pt)): break
                        t += 10
                    if os.environ.get("SB_DEBUG3") and x_ > 2100: print("   s-ray", round(x_), round(y_), dx_, dy_, t, QP.contains(Point(x_ + dx_ * (t - 60), y_ + dy_ * (t - 60))))
                    if t < 200 or not QP.contains(Point(x_ + dx_ * (t - 60), y_ + dy_ * (t - 60))): continue
                    if best and t <= best[0]: continue
                    for a, bk in [(a_, b_) for b_ in range(0, int(t) - 150, 20) for a_ in (60, 52, 45)]:   # (as far out as a pad fits)
                        Q = (x_ + dx_ * (t + 40 - a - bk), y_ + dy_ * (t + 40 - a - bk))
                        if padok(box(Q[0] - a, Q[1] - a, Q[0] + a, Q[1] + a)):
                            best = (t - bk, "s", [(x_, y_), (Q[0] - dx_ * a, Q[1] - dy_ * a)], Q, a, None); break
        # angled: off a ring's 45 deg corner face (a short straight stub, then the lane out at 45 deg to a pad)
        for rg in RG:
            cx, cy, hw, hh = rg["cx"], rg["cy"], rg["hw"], rg["hh"]; c = cut_of(hw, hh)
            if c <= 3.6 * MW: continue
            TKr = prep(TAKEN[0].difference(ring_shape(rg, MW / 2 + 72)))
            for sgx in (1, -1):
                for sgy in (1, -1):
                    for xo in np.arange(hw - c + 1.2 * MW, hw - 1.2 * MW, 20.0):
                        r1 = (cx + sgx * xo, cy + sgy * (hw + hh - c - xo))
                        if any(abs(b_[0] - r1[0]) < 1.8 * MW for b_ in rg["breaks"].get(CORNER(rg, *r1), [])): continue
                        if r1[0] < C + MW / 2 + 60: continue
                        st1 = (r1[0] + sgx * 1.5 * MW, r1[1]); a0 = (st1[0] + sgx * MW / 2, st1[1])
                        if boxes_hit(dry_dhall(a0, (a0[0] + sgx * 300, a0[1] + sgy * 300), "x"), corner_boxes(rg, r1)): continue
                        u = (sgx / math.sqrt(2), sgy / math.sqrt(2)); t = 0
                        while t < 1600:
                            ok_ = True
                            for off in (-MW / 2, 0, MW / 2):
                                pt = Point(a0[0] + u[0] * (t + 10) - u[1] * off, a0[1] + u[1] * (t + 10) + u[0] * off)
                                if not HIp.contains(pt) or TKr.contains(pt): ok_ = False; break
                            if not ok_: break
                            t += 10
                        if os.environ.get("SB_DEBUG2"): print("  d-ray", [round(v) for v in r1], sgx, sgy, t, QP.contains(Point(a0[0] + u[0] * (t - 40), a0[1] + u[1] * (t - 40))))
                        if t < 150 or not QP.contains(Point(a0[0] + u[0] * (t - 40), a0[1] + u[1] * (t - 40))): continue
                        # a pod ring where the angled lane comes out into open floor (a district of its own); the lane
                        # ends square on the middle part of its near side
                        for a in (190.0, 160.0, 130.0, 110.0):
                            got = None
                            for d in np.arange(150.0, t + 1, 10.0):
                                b0 = (a0[0] + u[0] * d, a0[1] + u[1] * d)
                                for off in (0.0, -0.35 * a, 0.35 * a):
                                    cen = (b0[0] + sgx * a, b0[1] + off)
                                    og = octo(cen[0], cen[1], a + MW / 2 + 4, a + MW / 2 + 4, cut_of(a, a))
                                    if FREE.contains(og) and not TKr.intersects(og) and QP.intersects(og) and abs(off) <= a - cut_of(a, a) - MW:
                                        got = (b0, cen); break
                                if got: break
                            if got:
                                if not best or a + t > best[0]: best = (a + t, "dr", [r1, st1, a0, got[0]], got[1], a, rg)
                                break
                        if best and t <= best[0]: continue
                        for a in (60, 52, 45):
                            b0 = (a0[0] + u[0] * (t + 30 - 2 * a), a0[1] + u[1] * (t + 30 - 2 * a))
                            Q = (b0[0] + sgx * a, b0[1])
                            bb = box(Q[0] - a, Q[1] - a, Q[0] + a, Q[1] + a)
                            if padok(bb):
                                best = (t, "d", [r1, st1, a0, b0], Q, a, rg); break
        # on from a pad: a lane out of a pad's side (the pad is a junction room, doors at both ends)
        for kind0, pts0, o0, rg0_, Qp, ap in SPURS:
            if kind0 in ("pr", "dr") or Qp[0] < C + MW / 2 + 60: continue
            TKr = prep(TAKEN[0].difference(box(Qp[0] - ap, Qp[1] - ap, Qp[0] + ap, Qp[1] + ap).buffer(MW + 46)))
            for u, sh in [(u_, sh_) for u_ in ((1, 0), (-1, 0), (0, 1), (0, -1)) for sh_ in (0, -1, 1)]:
                if (u[0] * (pts0[-1][0] - Qp[0]) + u[1] * (pts0[-1][1] - Qp[1])) > ap - 2: continue   # (the side it is reached from)
                sv = sh * (ap - MW / 2 - 6)
                st = (Qp[0] + u[0] * ap - u[1] * sv, Qp[1] + u[1] * ap + u[0] * sv)
                t = 4
                while t < 1600:
                    ok_ = True
                    for off in (-MW / 2, 0, MW / 2):
                        pt = Point(st[0] + u[0] * (t + 10) - u[1] * off, st[1] + u[1] * (t + 10) + u[0] * off)
                        if not HIp.contains(pt) or TKr.contains(pt): ok_ = False; break
                    if not ok_: break
                    t += 10
                # a pod ring at the end when the floor opens out there (a district of its own)
                for a in (190.0, 160.0, 130.0, 110.0):
                    got = None
                    for d in np.arange(t, a + 2 * MW, -10.0):
                        cen = (st[0] + u[0] * d, st[1] + u[1] * d)
                        if cen[0] - a - MW < C + MW / 2 + 40: continue
                        og = octo(cen[0], cen[1], a + MW / 2 + 4, a + MW / 2 + 4, cut_of(a, a))
                        if FREE.contains(og) and not TK.intersects(og) and QP.intersects(og):
                            got = cen; break
                    if got and (not best or a + t > best[0]):
                        best = (a + t, "pr", [st, (got[0] - u[0] * a, got[1] - u[1] * a)], got, a, None)
                    if got: break
                if os.environ.get("SB_DEBUG"): print("   pad-ray", [round(v) for v in Qp], ap, u, t, QP.contains(Point(st[0] + u[0] * (t - 60), st[1] + u[1] * (t - 60))))
                if t < 200 or not QP.contains(Point(st[0] + u[0] * (t - 60), st[1] + u[1] * (t - 60))): continue
                if best and t <= best[0]: continue
                for a, bk in [(a_, b_) for b_ in range(0, int(t) - 150, 20) for a_ in (60, 52, 45)]:
                    Q = (st[0] + u[0] * (t + 40 - a - bk), st[1] + u[1] * (t + 40 - a - bk))
                    bb = box(Q[0] - a, Q[1] - a, Q[0] + a, Q[1] + a)
                    if padok(bb):
                        best = (t - bk, "p", [st, (Q[0] - u[0] * a, Q[1] - u[1] * a)], Q, a, None); break
        # straight out of a ring's corner face (a T on the angled corner), across or down
        for rg in RG:
            cx, cy, hw, hh = rg["cx"], rg["cy"], rg["hw"], rg["hh"]; c = cut_of(hw, hh)
            if c <= 3.6 * MW: continue
            TKr = prep(TAKEN[0].difference(ring_shape(rg, MW / 2 + 72)))
            for sgx in (1, -1):
                for sgy in (1, -1):
                    for xo in np.arange(hw - c + 1.2 * MW, hw - 1.2 * MW, 16.0):
                        r1 = (cx + sgx * xo, cy + sgy * (hw + hh - c - xo))
                        if any(abs(b_[0] - r1[0]) < 1.8 * MW for b_ in rg["breaks"].get(CORNER(rg, *r1), [])): continue
                        if r1[0] < C + MW / 2 + 60: continue
                        for u in ((sgx, 0), (0, sgy)):
                            t = MW / 2
                            while t < 1600:
                                ok_ = True
                                for off in (-MW / 2, 0, MW / 2):
                                    pt = Point(r1[0] + u[0] * (t + 10) - u[1] * off, r1[1] + u[1] * (t + 10) + u[0] * off)
                                    if not HIp.contains(pt) or TKr.contains(pt): ok_ = False; break
                                if not ok_: break
                                t += 10
                            if os.environ.get("SB_DEBUG2"): print("  b-ray", [round(v) for v in r1], u, t, QP.contains(Point(r1[0] + u[0] * (t - 60), r1[1] + u[1] * (t - 60))))
                            if t < 200 or not QP.contains(Point(r1[0] + u[0] * (t - 60), r1[1] + u[1] * (t - 60))): continue
                            if best and t <= best[0]: continue
                            for a, bk in [(a_, b_) for b_ in range(0, int(t) - 150, 20) for a_ in (60, 52, 45)]:
                                Q = (r1[0] + u[0] * (t + 40 - a - bk), r1[1] + u[1] * (t + 40 - a - bk))
                                bb = box(Q[0] - a, Q[1] - a, Q[0] + a, Q[1] + a)
                                if padok(bb):
                                    best = (t - bk, "b", [r1, (Q[0] - u[0] * a, Q[1] - u[1] * a)], Q, a, rg); break
        if not best: return None
        if best[1] in ("s", "d", "b", "p", "pr", "dr"): return best[1:]
        return ("s", best[1], best[2], best[3], None)
    for _ in range(16):
        free = HULL.buffer(-(MW / 2 + 16), join_style=2).difference(TAKEN[0].buffer(MW / 2 + 40)).intersection(box(C + MW / 2 + 70, 0, NPX, NPX))
        pcs = sorted([q for q in getattr(free, "geoms", [free]) if q.geom_type == "Polygon" and q.area > 25000], key=lambda q: -q.area)
        made = False
        for q in pcs:
            m = np.zeros((NPX, NPX), np.uint8); cv2.fillPoly(m, [np.array(q.exterior.coords, np.int32)], 255)
            dt = cv2.distanceTransform(m, cv2.DIST_L2, 5)
            ys, xs = np.nonzero(dt >= 46)
            if len(xs) == 0: continue
            # the tip: the deep-enough point farthest from the rings
            near = min(RG, key=lambda r_: math.hypot(r_["cx"] - xs.mean(), r_["cy"] - ys.mean()))
            dd = np.hypot(xs - near["cx"], ys - near["cy"]); i_ = int(np.argmax(dd))
            Q = (float(xs[i_]), float(ys[i_])); a = float(min(60, dt[ys[i_], xs[i_]] - 6))
            t_ = tspur(q)   # (a pod ring, when one fits, beats a bare lane to a pad)
            pod = bool(t_) and t_[0] in ("pr", "dr")
            for rg in ([] if pod else sorted(RG, key=lambda r_: math.hypot(r_["cx"] - Q[0], r_["cy"] - Q[1]))):
                if rg["hw"] < 300 and not rg.get("district"): continue
                L1 = link(rg, Q, a, pad=True)
                Qm = (2 * C - Q[0], Q[1]); rgm = rg if rg["cx"] == C else next((r_ for r_ in RG if abs(r_["cx"] - (2 * C - rg["cx"])) < 1 and abs(r_["cy"] - rg["cy"]) < 1), None)
                L2 = link(rgm, Qm, a, pad=True) if rgm else None
                if os.environ.get("SB_DEBUG"): print("  district links", bool(L1), bool(L2))
                if L1 and L2:
                    for (kind, pts, o, rg_), QQ in ((L1, Q), (L2, Qm)):
                        SPURS.append((kind, pts, o, rg_, QQ, a))
                        if kind == "d": rg_["breaks"].setdefault(CORNER(rg_, *pts[0]), []).append(pts[0])
                        TAKEN[0] = TAKEN[0].union(box(QQ[0] - a, QQ[1] - a, QQ[0] + a, QQ[1] + a).buffer(MW + 40)).union(hall(pts[0], pts[-1], w=MW + 60))
                    made = True; break
            if not made:
                if os.environ.get("SB_DEBUG"): print("spur piece", round(q.area), [round(v) for v in q.bounds], "tspur", t_ and t_[0])
                if t_:
                    kind_, pts, Q, a, rg0 = t_
                    for k_ in (1, -1):
                        P2 = pts if k_ == 1 else [(2 * C - x_, y_) for x_, y_ in pts]; QQ = Q if k_ == 1 else (2 * C - Q[0], Q[1])
                        SPURS.append((kind_, P2, "x", None, QQ, a))
                        if kind_ in ("pr", "dr"):
                            nr = {"cx": QQ[0], "cy": QQ[1], "hw": a, "hh": a, "breaks": {}, "district": True}
                            RG.append(nr); TAKEN[0] = TAKEN[0].union(ring_shape(nr, MW / 2 + 70)).union(hall(P2[0], P2[-1], w=MW + 60))
                            if kind_ == "pr": STRAIGHT.append(P2); continue
                            rgx = rg0 if (k_ == 1 or abs(rg0["cx"] - C) < 1) else next((r_ for r_ in RG if abs(r_["cx"] - (2 * C - rg0["cx"])) < 1 and abs(r_["cy"] - rg0["cy"]) < 1), rg0)
                            rgx["breaks"].setdefault(CORNER(rgx, *P2[0]), []).append(P2[0]); continue
                        if kind_ in ("d", "b"):
                            rgx = rg0 if (k_ == 1 or abs(rg0["cx"] - C) < 1) else next((r_ for r_ in RG if abs(r_["cx"] - (2 * C - rg0["cx"])) < 1 and abs(r_["cy"] - rg0["cy"]) < 1), rg0)
                            rgx["breaks"].setdefault(CORNER(rgx, *P2[0]), []).append(P2[0])
                        TAKEN[0] = TAKEN[0].union(box(QQ[0] - a, QQ[1] - a, QQ[0] + a, QQ[1] + a).buffer(MW + 40)).union(hall(P2[0], P2[-1], w=MW + 60))
                        if kind_ != "d": STRAIGHT.append(P2)
                    made = True
            if made: break
        if not made: break
    for rg in RG: ring(rg)
    pname = lambda cx, cy: "%s %d" % (NAMES["pad"], int(round(math.degrees(math.atan2(-(cy - C), cx - C)) % 360)))
    for kind, pts, o, rg_, Q, a in SPURS:
        if kind == "dr":   # (an angled lane out of a ring corner to a pod ring's side)
            r1, st1, a0, b0 = pts
            HALLS.append(hall(r1, st1, w=MW)); node(st1[0], st1[1], MW)
            HALLS.append(dhall(a0, b0, w=MW, axis="x"))
            continue
        if kind == "pr":   # (a lane from a pad to a pod ring: a door on the pad, a T into the ring's side)
            DOORS.append((round(pts[0][0], 1), round(pts[0][1], 1), "h" if abs(pts[0][0] - pts[1][0]) < 1 else "v"))
            HALLS.append(hall(*pts, w=MW)); SEGS.append((min(pts[0][0], pts[1][0]), min(pts[0][1], pts[1][1]), max(pts[0][0], pts[1][0]), max(pts[0][1], pts[1][1]), MW))
            continue
        nm = pname(*Q)
        while nm in R: nm += "b"
        e = pts[-1]
        # (later breaks move a ring corner's pieces: a pad now over one is drawn in toward its door, if nothing starts from it)
        fed = any(k2 in ("p", "pr") and box(Q[0] - a - 2, Q[1] - a - 2, Q[0] + a + 2, Q[1] + a + 2).contains(Point(*p2[0])) for k2, p2, *_ in SPURS)
        DB = [g.bounds for g in planlib.DIAG]
        u_ = ((Q[0] - e[0]) / max(abs(Q[0] - e[0]), 1e-9), 0) if abs(Q[0] - e[0]) > 1 else (0, (Q[1] - e[1]) / max(abs(Q[1] - e[1]), 1e-9))
        while not fed and a > 32 and boxes_hit([box(Q[0] - a, Q[1] - a, Q[0] + a, Q[1] + a).buffer(3).bounds], DB):
            a -= 6; Q = (e[0] + u_[0] * a, e[1] + u_[1] * a)
        R[nm] = octo(Q[0], Q[1], a, a, a * 0.3); PADS.append(nm)
        if kind == "p":
            DOORS.append((round(pts[0][0], 1), round(pts[0][1], 1), "h" if abs(pts[0][0] - pts[1][0]) < 1 else "v"))
        if kind in ("s", "b", "p"):
            HALLS.append(hall(*pts, w=MW)); SEGS.append((min(pts[0][0], pts[1][0]), min(pts[0][1], pts[1][1]), max(pts[0][0], pts[1][0]), max(pts[0][1], pts[1][1]), MW))
        elif len(pts) == 4:
            r1, st1, a0, b0 = pts
            HALLS.append(hall(r1, st1, w=MW)); node(st1[0], st1[1], MW)
            HALLS.append(dhall(a0, b0, w=MW, axis="x"))
        else:
            r1, st1, a0, b0, st2, r2 = pts
            HALLS.append(hall(r1, st1, w=MW)); node(st1[0], st1[1], MW)
            HALLS.append(dhall(a0, b0, w=MW, axis=o))
            HALLS.append(hall(st2, r2, w=MW)); node(st2[0], st2[1], MW)
        DOORS.append((round(e[0], 1), round(e[1], 1), "h" if abs(e[0] - Q[0]) < 1 else "v"))
    for kind, pts, o, rg_, nr in LINKS:
        if kind == "s":
            HALLS.append(hall(*pts, w=MW)); SEGS.append((min(pts[0][0], pts[1][0]), min(pts[0][1], pts[1][1]), max(pts[0][0], pts[1][0]), max(pts[0][1], pts[1][1]), MW))
        else:
            r1, st1, a0, b0, st2, r2 = pts
            HALLS.append(hall(r1, st1, w=MW)); node(st1[0], st1[1], MW)
            HALLS.append(dhall(a0, b0, w=MW, axis=o))
            HALLS.append(hall(st2, r2, w=MW)); node(st2[0], st2[1], MW)
    # each district: a hall in the middle (when there is room) on a small cross to its ring
    DNAMES = NAMES["dist"]
    if os.environ.get("SB_DEBUG"): print("districts", [(round(r_["cx"]), round(r_["cy"]), r_["hw"]) for r_ in RG if r_.get("district")])
    for i, rg in enumerate([r_ for r_ in RG if r_.get("district")]):
        a = rg["hw"]; ha = min(110.0, a - MW / 2 - 100)
        dname = "%s %s" % (DNAMES[(i // 2) % len(DNAMES)], "East" if rg["cx"] > C else "West")
        if ha >= 55:
            R[dname] = octo(rg["cx"], rg["cy"], ha, ha, ha * 0.414); DIST.append(dname)
            for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
                p0 = (rg["cx"] + dx * ha, rg["cy"] + dy * ha); p1 = (rg["cx"] + dx * a, rg["cy"] + dy * a)
                HALLS.append(hall(p0, p1, w=MW)); DOORS.append((round(p0[0], 1), round(p0[1], 1), "h" if dx == 0 else "v"))
                SEGS.append((min(p0[0], p1[0]), min(p0[1], p1[1]), max(p0[0], p1[0]), max(p0[1], p1[1]), MW))
    hwP, hhP = MAINP["hw"], MAINP["hh"]
    # ---- side lanes: from each ring's corners straight out to the next ring
    for k_, ((hw0, hh0), (hw1, hh1)) in enumerate(zip(RINGS, RINGS[1:])):
        c0, c1 = cut_of(hw0, hh0), cut_of(hw1, hh1)
        dy1 = DY if k_ + 2 == len(RINGS) else 0.0
        for sx in (-1, 1):
            for sy in (-1, 1):
                if hw0 - c0 < hw1 - c1 - MW:
                    a, b = (C + sx * (hw0 - c0), C + sy * hh0), (C + sx * (hw0 - c0), C + dy1 + sy * hh1)
                    HALLS.append(hall(a, b, w=MW)); SEGS.append((a[0], min(a[1], b[1]), b[0], max(a[1], b[1]), MW))
                if hh0 - c0 < hh1 - c1 - MW and abs(sy * (hh0 - c0) - dy1) <= hh1 - c1 - MW:
                    a, b = (C + sx * hw0, C + sy * (hh0 - c0)), (C + sx * hw1, C + sy * (hh0 - c0))
                    HALLS.append(hall(a, b, w=MW)); SEGS.append((min(a[0], b[0]), a[1], max(a[0], b[0]), b[1], MW))
    # ---- the district rooms: in the band between the last two rings, either side of the cross
    if len(RINGS) >= 2 and DY == 0:
        (hwB, hhB), (hwP_, hhP_) = RINGS[-2], RINGS[-1]
        cB = cut_of(hwB, hhB)
        bi = iter(NAMES["big"])
        for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
            for k in (-1, 1):
                nm = next(bi)
                d0 = (hhB if dx == 0 else hwB) + MW / 2 + 8; d1 = (hhP_ if dx == 0 else hwP_) - MW / 2 - 4
                sp = (hwB - cB if dx == 0 else hhB - cB)               # (stop short of the B -> P lanes)
                lo, hi = MW / 2 + 8, min(sp - MW / 2 - 8, MW / 2 + 8 + 300)
                if d1 - d0 < 90 or hi - lo < 90: continue
                if dx == 0:
                    xs = sorted([C + k * lo, C + k * hi]); ys = sorted([C + dy * d0, C + dy * d1]); door = ((xs[0] + xs[1]) / 2, C + dy * (d1 + 4), "h")
                else:
                    ys = sorted([C + k * lo, C + k * hi]); xs = sorted([C + dx * d0, C + dx * d1]); door = (C + dx * (d1 + 4), (ys[0] + ys[1]) / 2, "v")
                g = octo((xs[0] + xs[1]) / 2, (ys[0] + ys[1]) / 2, (xs[1] - xs[0]) / 2, (ys[1] - ys[0]) / 2, 14)
                if not HULL.contains(g): continue
                R[nm] = g; DOORS.append((round(door[0], 1), round(door[1], 1), door[2]))
    for nm, (bx_, d_) in LIFTS.items(): R[nm] = box(*bx_); DOORS.append(d_)
    # ---- the small rooms: library shapes along every straight walkway, right half first, mirrored
    occ = list(HALLS) + [b.buffer(4) for b in R.values()] + [box(*d.bounds).buffer(3) for d in planlib.DIAG]
    def blocked(g):
        if not HULL.contains(g): return True
        gg = g.buffer(-2)
        return any(gg.intersects(o) for o in occ if o.bounds[0] <= gg.bounds[2] and o.bounds[2] >= gg.bounds[0] and o.bounds[1] <= gg.bounds[3] and o.bounds[3] >= gg.bounds[1])
    def sector(x, y):
        a = math.degrees(math.atan2(-(y - C), x - C)) % 360
        return NAMES["word"] + (" North" if 45 <= a < 135 else " South" if 225 <= a < 315 else " East" if x > C else " West")
    n_room, KIND, used = {}, {}, {}
    def place(bx, door, mech, seed, shape_=None):
        x0, y0, x1, y1 = bx.bounds; cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        dw = DOOR + 12
        def shaped(g0):
            g = g0
            for dd in range(10, 200, 8):   # a doorway strip from the door in, as deep as it takes to reach the room's shape
                strip = (box(door[0] - dw / 2, door[1] - dd, door[0] + dw / 2, door[1] + dd) if door[2] == "h" else box(door[0] - dd, door[1] - dw / 2, door[0] + dd, door[1] + dw / 2)).intersection(bx)
                g = unary_union([g0, strip]).intersection(bx).buffer(0)
                if g.geom_type == "Polygon" and strip.intersection(g0).area > dw * 12: break
            g = g.buffer(-5, join_style=2).buffer(5, join_style=2).intersection(bx).buffer(0)   # (no slivers)
            if g.geom_type != "Polygon": g = max(g.geoms, key=lambda q: q.area)
            return Polygon(g.exterior)
        if shape_ is None:
            for i_ in range(12):   # a library shape whose middle is clear of its own walls (the game finds rooms by it)
                g0, kid = pick(x1 - x0, y1 - y0, seed + i_ * 7919, mech) if i_ < 11 else (box(-(x1 - x0) / 2, -(y1 - y0) / 2, (x1 - x0) / 2, (y1 - y0) / 2), None)
                g = shaped(affinity.translate(g0, cx, cy))
                if g.centroid.within(g.buffer(-16)) and g.representative_point().within(g.buffer(-12)) and g.area > 0.5 * bx.area: break
        else: g, kid = shape_, None
        sec = sector(cx, cy); words = MECH_WORDS if mech else PILOT_WORDS; wd = words[seed % len(words)]
        n_room[(sec, wd)] = n_room.get((sec, wd), 0) + 1
        nm = "%s %s %d" % (sec, wd, n_room[(sec, wd)])
        R[nm] = g; KIND[nm] = "mech" if mech else "pilot"; occ.append(bx.buffer(4)); DOORS.append((round(door[0], 1), round(door[1], 1), door[2]))
        if kid: used[kid] = used.get(kid, 0) + 1
        return nm
    mbox = lambda b: box(2 * C - b.bounds[2], b.bounds[1], 2 * C - b.bounds[0], b.bounds[3])
    ringB = max(RINGS[-2]) if len(RINGS) >= 2 else 9999
    for si, (x0, y0, x1, y1, w) in enumerate(SEGS):
        horiz = abs(y1 - y0) < 1
        if not horiz and abs(x1 - x0) > 1: continue
        for side in (-1, 1):
            u0, u1 = (min(x0, x1), max(x0, x1)) if horiz else (min(y0, y1), max(y0, y1))
            u = u0 + 8; k = 0
            while u < u1:
                mid = ((u + 30) - C, (y0 if horiz else x0) - C)
                mech_zone = max(abs(mid[0]), abs(mid[1])) > min(ringB, 420) + 20
                done = False
                for depth, length in ([(88, 96), (62, 70), (50, 58)] if mech_zone else [(62, 70), (50, 58)]):
                    if u + length > u1 - 4: continue
                    if horiz:
                        e = y0 + side * w / 2; bx = box(u, min(e, e + side * depth), u + length, max(e, e + side * depth)); door = (u + length / 2, e, "h")
                    else:
                        e = x0 + side * w / 2; bx = box(min(e, e + side * depth), u, max(e, e + side * depth), u + length); door = (e, u + length / 2, "v")
                    cx = (bx.bounds[0] + bx.bounds[2]) / 2
                    if cx < C + 2 or blocked(bx): continue
                    mb = mbox(bx)
                    if abs(cx - C) >= 2 and blocked(mb): continue
                    seed = int(hashlib.md5(("%s%d%d%d" % (sid, si, side, k)).encode()).hexdigest(), 16) % 9973
                    nm = place(bx, door, depth >= 88, seed)
                    if not bx.equals(mb) and not blocked(mb):
                        place(mb, (2 * C - door[0], door[1], door[2]), depth >= 88, seed, affinity.scale(R[nm], -1, 1, origin=(C, C)))
                    u += length + 8; k += 1; done = True; break
                if not done: u += 10
    # ---- the main deck's 360 service rooms: the rooms nearest the hub, by kind
    if role == "MAIN HUB":
        near = lambda k: R[k].centroid.distance(Point(C, C))
        for svcs, kd in ((SERVICES_MECH, "mech"), (SERVICES_PILOT, "pilot")):
            cands = sorted([k for k in KIND if KIND[k] == kd], key=near)
            if len(cands) < len(svcs): cands += sorted([k for k in KIND if KIND[k] != kd and k not in cands], key=near)
            for svc, k in zip(svcs, cands):
                R[svc] = R.pop(k); KIND[svc] = kd; KIND.pop(k)
    kinds = {}
    for k in R:
        if k.startswith("Lift"): kinds[k] = "lift"
        elif k in KIND: kinds[k] = KIND[k]
        elif k == hubname or k in PADS or k.startswith(MECH_BIG): kinds[k] = "mech"
        else: kinds[k] = "pilot"
    START = (C, C + A_A)
    S = Ship(sid, here, src, C, R, HALLS, DOORS, start=START, center_y=C)
    info = {"rings": [[round(a), round(b)] for a, b in RINGS], "pads": PADS, "rooms": len(R), "kit_shapes": len(used),
            "diag": len(planlib.DIAG)}
    return S, kinds, hubname, info

# ------------------------------------------------------------------ the check picture (the in-game map colours)
def draw(path, HULL, plan, kinds, title):
    im = np.zeros((NPX, NPX, 3), np.uint8); im[:] = (40, 18, 6)
    cv2.fillPoly(im, [np.array(HULL.exterior.coords, np.int32)], (70, 40, 15))
    for h in plan["halls"] + plan.get("diag", []):
        for q in getattr(shape(h), "geoms", [shape(h)]): cv2.fillPoly(im, [np.array(q.exterior.coords, np.int32)], (60, 50, 215))
    for k, gj in plan["rooms"].items():
        g = shape(gj); col = {"mech": (40, 30, 150), "pilot": (200, 110, 30), "lift": (0, 210, 240)}[kinds[k]]
        cv2.fillPoly(im, [np.array(g.exterior.coords, np.int32)], col)
    im[planlib.raster(shape(plan["walls"]), (NPX, NPX)) > 0] = (255, 255, 255)
    cv2.polylines(im, [np.array(HULL.exterior.coords, np.int32)], True, (255, 220, 0), 4, cv2.LINE_AA)
    for k, gj in plan["rooms"].items():
        if kinds[k] == "mech" and not k.split()[-1].isdigit() or kinds[k] == "lift" or "Pad" in k or k in SERVICES_MECH + SERVICES_PILOT:
            c = shape(gj).representative_point(); t = k.upper()
            (tw, th), _ = cv2.getTextSize(t, 0, 0.7, 2)
            cv2.putText(im, t, (int(c.x - tw / 2), int(c.y + th / 2)), 0, 0.7, (255, 255, 255), 2, cv2.LINE_AA)
    cv2.putText(im, title, (40, 90), 0, 2.6, (255, 255, 255), 5, cv2.LINE_AA)
    x0, y0, x1, y1 = [int(v) for v in HULL.bounds]
    im = im[max(0, y0 - 120):y1 + 60, max(0, x0 - 60):x1 + 60]
    cv2.imwrite(path, im, [cv2.IMWRITE_JPEG_QUALITY, 85])

def main():
    sid, model, name = sys.argv[1:4]
    want = sys.argv[4:] or [d[0] for d in DECKS]
    root = os.path.join(TR, "fleet_" + sid); eng = os.path.join(root, "eng"); dk = os.path.join(root, "decks")
    for d in (root, eng, dk): os.makedirs(d, exist_ok=True)
    O, meta = outlines(model)
    json.dump({n: mapping(p) for (_, n, _), p in zip(DECKS, O)} | {"meta": meta}, open(os.path.join(dk, "outlines.json"), "w"))
    # source.jpg: the main deck's silhouette on the canvas (the map picture behind the main deck)
    src = np.zeros((NPX, NPX, 3), np.uint8); src[:] = (40, 18, 6)
    cv2.fillPoly(src, [np.array(O[2].exterior.coords, np.int32)], (90, 50, 18))
    cv2.polylines(src, [np.array(O[2].exterior.coords, np.int32)], True, (150, 110, 40), 6, cv2.LINE_AA)
    cv2.imwrite(os.path.join(root, "source.jpg"), src, [cv2.IMWRITE_JPEG_QUALITY, 90])
    json.dump({"hull": mapping(O[2]), "centre": [C, C], "model": model, "meta": meta}, open(os.path.join(root, "hull.json"), "w"))
    print("outlines", meta)
    bad_all = {}
    import tempfile, shutil
    for (dname, role, lvl), HULL in zip(DECKS, O):
        if dname not in want: continue
        tmp = tempfile.mkdtemp()
        S, kinds, hub, info = build_deck(HULL, role, sid, name, tmp if dname != "main" else eng, os.path.join(root, "source.jpg"))
        bad = run(S); bad_all[dname] = bad
        P = json.load(open(os.path.join(S.here, "plan.json")))
        draw(os.path.join(dk, "%s_plan.jpg" % dname), HULL, P, kinds, "%s  -  %s DECK" % (name.upper(), role))
        if dname == "main":
            pads = [k for k in info["pads"]]
            entry = max(pads, key=lambda k: shape(P["rooms"][k]).centroid.y) if pads else hub
            json.dump({"entry": entry, "C": hub, "kinds": kinds}, open(os.path.join(eng, "overrides.json"), "w"), indent=1)
            pt = lambda k: [int(shape(P["rooms"][k]).representative_point().x), int(shape(P["rooms"][k]).representative_point().y)]
            G = {"entry": {"room": entry, "at": pt(entry)}, "locks": [], "guards": [], "wreck": [], "patrols": [], "targets": {},
                 "lifts": [{"room": k, "at": pt(k)} for k in LIFTS], "room_guards": {k: (2 if kinds[k] == "mech" else 0) for k in kinds if kinds[k] != "lift"},
                 "note": "%s MAIN HUB deck (station_v2/station_build.py)" % name}
            json.dump(G, open(os.path.join(eng, "gameplay.json"), "w"), indent=1)
            g1 = os.path.join(eng, "gameplay_v1.json")
            json.dump(G, open(g1, "w"), indent=1)
        else:
            P["deck"] = dname; P["level"] = lvl; P["hull"] = mapping(HULL)
            P["lifts"] = [[(b[0] + b[2]) / 2, (b[1] + b[3]) / 2] for b, _ in LIFTS.values()]
            P["kinds"] = kinds
            json.dump(P, open(os.path.join(eng, "deck_%s.json" % dname), "w"))
        shutil.rmtree(tmp, ignore_errors=True)
        print("%-7s %-12s rings %s pads %d rooms %d (kit shapes %d) angled pieces %d unreachable %s" % (
            dname, role, info["rings"], len(info["pads"]), info["rooms"], info["kit_shapes"], info["diag"], bad))
    sys.exit(1 if any(bad_all.values()) else 0)

if __name__ == "__main__":
    main()
