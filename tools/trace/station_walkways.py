#!/usr/bin/env python3
"""v13.167 (owner, Nov 15 2026, after the first station plans: "what you have there looks bad ... we had a room
template, taking those different room templates to fit them in together ... we need to design the walkways first").

STEP 1 of the station decks, the WALKWAYS ONLY, for the owner to approve before any room goes in. The same engineering
rules as the fleet ships (planlib): a hallway is a centre line plus one fixed width, straight runs, octagon junctions,
mirrored left / right about the station's axis; red = mech ways, blue = pilot ways, yellow = lifts (fleet_ways colours).
Step 2 (after his OK) fits the traced library rooms (shape_library.json, decklib.lib) along these walkways.

Per deck (the five deck outlines of station_plans.deck_outlines: the model's own slices / silhouette):
  - the MAIN HUB (a round hall) at the lift axis; on the other decks a smaller round lift lobby
  - SPINES (mech, 3.2 m): front (to the docking concourse) and back, the sides, and the diagonals where the station
    reaches that way; all at 45-degree steps, mirrored
  - an OCTAGON RING (mech) round the hub where the deck is big enough
  - BRANCHES (pilot, 2.2 m): cross halls off the long spines, out into the wings
  - LIFTS: the main lift in the hub (every deck), freight lifts on the ring (the same spot on every deck that has it)
Writes tools/trace/stations/<model>/walkways.json (metres, origin = the lift axis, +y = front) and walkways.jpg.
usage: python3 -I tools/trace/station_walkways.py [model ...]"""
import json, math, os, sys
import numpy as np, cv2
from shapely import affinity
from shapely.geometry import Point, LineString, Polygon, box, mapping
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import station_plans as SP
from decklib import lib

PX = 10.0                       # plan px per metre (the fleet ships' scale)
WM, WP = 3.2 * PX, 2.2 * PX     # mech way, pilot way widths
MARGIN = 2.0 * PX               # walkways keep this far inside the outline
STYLE_M = {"Capital": 140.0, "Trade": 120.0, "Military": 105.0, "Outpost": 85.0}   # m across (the interior's own scale)
ST3D_M = {"st3d_aurelion_citadel": 140.0, "st3d_veranthos_senate": 140.0, "st3d_veranthos_summit": 140.0}
RED, BLUE, YEL = (40, 40, 235), (235, 120, 30), (0, 215, 255)   # BGR, as fleet_ways
DIRS_RIGHT = [90, 270, 0, 45, 315]                                # (screen angles: +y = front, the docking side)


def parts(g):
    """the polygons in a geometry (lines and points left by a clip are dropped)"""
    if g.is_empty: return []
    if hasattr(g, "geoms"): return [q for p in g.geoms for q in parts(p)]
    return [g] if isinstance(g, Polygon) else []


def octagon(cx, cy, d):
    r = d / 2 / math.cos(math.radians(22.5))
    return Polygon([(cx + r * math.cos(math.radians(22.5 + 45 * k)), cy + r * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)])


def ray(inner, c, ang, rmax):
    a = math.radians(ang)
    r, step = 0.0, 0.5 * PX
    while r < rmax:
        if not inner.contains(Point(c[0] + (r + step) * math.cos(a), c[1] + (r + step) * math.sin(a))): break
        r += step
    return r


def way(p0, p1, w):
    return LineString([p0, p1]).buffer(w / 2, cap_style=2, join_style=2)


def mirror(g, ax):
    return affinity.scale(g, -1, 1, origin=(ax, 0))


def walkways(outline, c, role, rmax):
    """outline: the deck (plan px), c: the lift axis. -> halls (mech, pilot), lifts, lines, notes"""
    ax = c[0]
    sym = outline.intersection(mirror(outline, ax))
    sym = max(parts(sym), key=lambda g: g.area) if parts(sym) else outline
    mirrored = sym.area > 0.6 * outline.area
    base = sym if mirrored else outline
    inner = base.buffer(-MARGIN, join_style=2)
    inner = max(parts(inner), key=lambda g: g.area) if parts(inner) else inner
    hub_r = (10.0 if role == "MAIN HUB" else 6.0) * PX
    if not inner.buffer(-hub_r * 0.8).contains(Point(c)): hub_r *= 0.6
    hub = Point(c).buffer(hub_r, 64)
    R = {d: ray(inner, c, d, rmax) for d in range(0, 360, 45)}
    lines, mech, pilot, juncs = [], [hub], [], []
    pick = []
    for d in DIRS_RIGHT:
        need = hub_r + (8 if d in (90, 270, 0) else 12) * PX
        if d in (45, 315) and R[d] < 0.75 * max(R[90], R[270], R[0], 1): continue
        if R[d] >= need: pick.append(d)
    full = sorted(set(pick + [(180 - d) % 360 for d in pick]))   # (mirrored: 0 <-> 180, 45 <-> 135, 315 <-> 225)
    ends = {}
    for d in full:
        L = R[d] - 1.0 * PX
        a = math.radians(d)
        e = (c[0] + L * math.cos(a), c[1] + L * math.sin(a))
        ends[d] = (e, L)
        mech.append(way(c, e, WM))
        lines.append(("mech", c, e))
    # the octagon ring round the hub
    ring_a = None
    if full:
        rmin = min(ends[d][1] for d in full)
        a_ = hub_r + max(10 * PX, 0.42 * (rmin - hub_r))
        if a_ + WM < rmin - 6 * PX:
            rc = a_ / math.cos(math.radians(22.5))
            pts = [(c[0] + rc * math.cos(math.radians(22.5 + 45 * k)), c[1] + rc * math.sin(math.radians(22.5 + 45 * k))) for k in range(9)]
            rg = LineString(pts).buffer(WM / 2, cap_style=2, join_style=2)
            if rg.intersection(inner).area > 0.92 * rg.area:
                ring_a = a_
                mech.append(rg)
                for k in range(8): lines.append(("mech", pts[k], pts[k + 1]))
                for d in full:
                    a = math.radians(d)
                    juncs.append(octagon(c[0] + a_ * math.cos(a) / 1.0, c[1] + a_ * math.sin(a), WM * 1.5))
    # branches: cross halls off the long spines, out into the wings
    for d in full:
        (e, L) = ends[d]
        if L < 30 * PX: continue
        a = math.radians(d)
        for t in (0.62, 0.9):
            dist = L * t
            if ring_a is not None and dist < ring_a + 8 * PX: continue
            p = (c[0] + dist * math.cos(a), c[1] + dist * math.sin(a))
            for side in (-1, 1):
                pa = d + 90 * side
                rr = ray(inner, p, pa, 40 * PX)
                ln = min(rr - 1.0 * PX, 22 * PX)
                if ln < 8 * PX: continue
                b = math.radians(pa)
                q = (p[0] + ln * math.cos(b), p[1] + ln * math.sin(b))
                pilot.append(way(p, q, WP))
                lines.append(("pilot", p, q))
                juncs.append(octagon(p[0], p[1], WM * 1.35))
    mech_u = unary_union(mech + juncs).intersection(inner.buffer(0.5 * PX))
    pilot_u = unary_union(pilot).intersection(inner).difference(mech_u)
    allw = unary_union([mech_u, pilot_u])
    keep = [g for g in parts(allw) if g.distance(Point(c)) < 1.0]   # (only what joins the hub)
    allw = unary_union(keep) if keep else hub
    if mirrored: allw = allw.intersection(mirror(allw, ax).buffer(0.2)).buffer(0)
    mech_u = mech_u.intersection(allw)
    pilot_u = pilot_u.intersection(allw)
    lifts = [("Main lift", lib("tianjin_10", c[0], c[1], w=5.7))]
    if ring_a is not None:
        for d in (0, 180):
            if d in full:
                a = math.radians(d)
                lifts.append(("Freight lift", lib("tianjin_10", c[0] + ring_a * math.cos(a), c[1] + ring_a * math.sin(a), w=4.6)))
    return {"outline": base, "inner": inner, "mech": mech_u, "pilot": pilot_u, "ways": allw, "lifts": lifts, "lines": lines,
            "ring": ring_a is not None, "spines": len(full), "mirrored": mirrored, "hub_r": hub_r, "c": c,
            "front": ends.get(90, (None, 0))[0], "branches": len(pilot)}


def draw(W, title, sub, role):
    g = W["outline"]
    x0, y0, x1, y1 = g.bounds
    S = 600.0 / max(x1 - x0, y1 - y0)
    ox, oy = 320 - (x0 + x1) / 2 * S, 340 - (y0 + y1) / 2 * S
    T = lambda q: affinity.affine_transform(q, [S, 0, 0, S, ox, oy])
    img = np.zeros((640, 640, 3), np.uint8)
    def fill(q, col, im=img):
        m = np.zeros(im.shape[:2], np.uint8)
        for p in parts(T(q)):   # (each piece with its own holes, OR-ed: a piece inside another's hole stays)
            m1 = np.zeros_like(m)
            cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 1)
            for h in p.interiors: cv2.fillPoly(m1, [np.array(h.coords, np.int32)], 0)
            m |= m1
        im[m > 0] = col
    def edge(q, col, t):
        for p in parts(T(q)):
            cv2.polylines(img, [np.array(p.exterior.coords, np.int32)], True, col, t, cv2.LINE_AA)
            for h in p.interiors: cv2.polylines(img, [np.array(h.coords, np.int32)], True, col, t, cv2.LINE_AA)
    fill(g, (30, 30, 30))
    room = W["inner"].difference(W["ways"].buffer(1.0 * PX))
    fill(room, (44, 44, 44))
    over = img.copy()
    fill(W["mech"], RED, over)
    fill(W["pilot"], BLUE, over)
    img[:] = cv2.addWeighted(over, 0.55, img, 0.45, 0)
    edge(W["ways"], (235, 235, 235), 2)
    for nm, q in W["lifts"]:
        fill(q, YEL)
        edge(q, (0, 0, 0), 1)
    edge(g, (255, 255, 255), 3)
    c = T(Point(W["c"]))
    cx, cy = int(c.x), int(c.y)
    if role == "MAIN HUB":
        star = [(cx + (12 if i % 2 == 0 else 5) * math.cos(-math.pi / 2 + i * math.pi / 5), cy - 22 + (12 if i % 2 == 0 else 5) * math.sin(-math.pi / 2 + i * math.pi / 5)) for i in range(10)]
        cv2.fillPoly(img, [np.array(star, np.int32)], YEL)
        for t2, dy, col in (("MAIN HUB", 26, (255, 255, 255)), ("START / FAST TRAVEL", 40, YEL)):
            (tw, _), _ = cv2.getTextSize(t2, 0, 0.4, 1)
            cv2.putText(img, t2, (cx - tw // 2, cy + dy), 0, 0.4, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(img, t2, (cx - tw // 2, cy + dy), 0, 0.4, col, 1, cv2.LINE_AA)
    fe = W["front"]
    if fe is not None and role in ("MAIN HUB", "HANGAR"):
        p = T(Point(fe))
        t2 = "DOCKING CONCOURSE" if role == "MAIN HUB" else "HANGAR DOORS"
        (tw, _), _ = cv2.getTextSize(t2, 0, 0.4, 1)
        cv2.putText(img, t2, (int(p.x) - tw // 2, int(p.y) + 16), 0, 0.4, (0, 0, 0), 3, cv2.LINE_AA)
        cv2.putText(img, t2, (int(p.x) - tw // 2, int(p.y) + 16), 0, 0.4, (120, 255, 120), 1, cv2.LINE_AA)
    # scale bar: 10 m
    L10 = int(10 * PX * S)
    cv2.line(img, (16, 626), (16 + L10, 626), (220, 220, 220), 2)
    cv2.putText(img, "10 m", (20 + L10, 630), 0, 0.38, (220, 220, 220), 1, cv2.LINE_AA)
    cv2.putText(img, "FRONT (docking) v", (520 - 60, 630), 0, 0.38, (120, 255, 120), 1, cv2.LINE_AA)
    cv2.rectangle(img, (0, 0), (640, 44), (0, 0, 0), -1)
    cv2.putText(img, title, (10, 20), 0, 0.6, (255, 255, 255), 1, cv2.LINE_AA)
    cv2.putText(img, sub, (10, 38), 0, 0.4, (180, 180, 180), 1, cv2.LINE_AA)
    return img


def legend(top, st, lines):
    img = np.zeros((640, 640, 3), np.uint8)
    t = cv2.resize(top, (300, 300))
    img[60:360, 10:310] = cv2.cvtColor(t, cv2.COLOR_GRAY2BGR) // 2
    cv2.putText(img, "THE MODEL FROM ABOVE", (10, 52), 0, 0.45, (200, 200, 200), 1, cv2.LINE_AA)
    y = 90
    for txt, col in (("mech way (3.2 m)", RED), ("pilot way (2.2 m)", BLUE), ("lift", YEL), ("room space (step 2)", (44, 44, 44))):
        cv2.rectangle(img, (330, y - 13), (352, y + 3), col, -1)
        cv2.rectangle(img, (330, y - 13), (352, y + 3), (200, 200, 200), 1)
        cv2.putText(img, txt, (360, y), 0, 0.48, (230, 230, 230), 1, cv2.LINE_AA)
        y += 28
    y = 250
    for ln in ["STEP 1: WALKWAYS ONLY.", "Rooms go in after you", "approve these: traced", "library rooms fitted", "along the halls."]:
        cv2.putText(img, ln, (330, y), 0, 0.48, (60, 220, 255), 1, cv2.LINE_AA)
        y += 22
    y = 400
    for ln in lines:
        cv2.putText(img, ln, (14, y), 0, 0.45, (230, 230, 230), 1, cv2.LINE_AA)
        y += 22
    return img


def build(st):
    model = st["model"]
    O = SP.deck_outlines(st)
    style = next((k for k in STYLE_M if "_%s_" % k in model), None)
    width_m = STYLE_M.get(style, ST3D_M.get(model, 120.0))
    f = width_m * PX / (SP.N - 40)            # outline px -> plan px
    c0 = O["c"]
    to_plan = lambda g: affinity.affine_transform(g, [f, 0, 0, f, -c0[0] * f, -c0[1] * f])
    c = (0.0, 0.0)
    panels, decks = [], []
    for k, role in enumerate(SP.DECKS):
        ol = to_plan(O["polys"][k])
        W = walkways(ol, c, role, width_m * PX)
        ln_m = sum(LineString([a, b]).length for _, a, b in W["lines"]) / PX
        sub = "%s · %d spines%s · %d branches · %d m of halls · %d m2 room space · %d x %d m" % (
            "mirrored" if W["mirrored"] else "not mirrored", W["spines"], " + ring" if W["ring"] else "", W["branches"], ln_m,
            W["inner"].difference(W["ways"].buffer(PX)).area / PX / PX, (W["outline"].bounds[2] - W["outline"].bounds[0]) / PX, (W["outline"].bounds[3] - W["outline"].bounds[1]) / PX)
        panels.append(draw(W, "%d  %s DECK" % (k + 1, role), sub, role))
        M = lambda g: [[round(x / PX, 2), round(y / PX, 2)] for x, y in g.exterior.coords]
        decks.append({"deck": k + 1, "role": role, "outline_from": O["src"][k], "mirrored": W["mirrored"], "outline": M(W["outline"]),
                      "halls": [{"kind": kd, "from": [round(a[0] / PX, 2), round(a[1] / PX, 2)], "to": [round(b[0] / PX, 2), round(b[1] / PX, 2)],
                                 "width_m": WM / PX if kd == "mech" else WP / PX} for kd, a, b in W["lines"]],
                      "hub_radius_m": round(W["hub_r"] / PX, 2), "ring": W["ring"],
                      "lifts": [{"name": nm, "at": [round(q.centroid.x / PX, 2), round(q.centroid.y / PX, 2)]} for nm, q in W["lifts"]],
                      "walkway_m2": round(W["ways"].area / PX / PX), "room_space_m2": round(W["inner"].difference(W["ways"].buffer(PX)).area / PX / PX)})
    lines = ["%s  (%s)" % (st["name"], st["faction"] or "-"), "system %s" % st["system"], "model %s" % model,
             "interior about %d m across, 5 decks" % width_m, "PROPOSED: waiting for your OK."]
    panels.append(legend(O["top"], st, lines))
    sheet = np.vstack([np.hstack([panels[4], panels[3], panels[5]]), np.hstack([panels[2], panels[1], panels[0]])])
    od = os.path.join(SP.OUT, model)
    os.makedirs(od, exist_ok=True)
    cv2.imwrite(os.path.join(od, "walkways.jpg"), cv2.resize(sheet, (1440, 960), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 78])
    json.dump({"station": st["name"], "model": model, "status": "PROPOSED (walkways, step 1)", "metres_across": width_m,
               "units": "metres, origin = the lift axis, +y = front (docking)", "decks": decks}, open(os.path.join(od, "walkways.json"), "w"), indent=1)
    return {"model": model, "name": st["name"], "decks": [(d["role"], len(d["halls"]), d["ring"], d["mirrored"]) for d in decks]}


if __name__ == "__main__":
    S = json.load(open(os.path.join(SP.OUT, "stations.json")))
    want = sys.argv[1:]
    for st in S:
        if want and st["model"] not in want: continue
        r = build(st)
        print("%-40s %-28s %s" % (r["model"], r["name"][:28], " ".join("%d%s%s" % (n, "R" if rg else "", "" if mi else "!") for _, n, rg, mi in r["decks"])), flush=True)
