#!/usr/bin/env python3
"""v3 station decks in the style of the owner's SWTOR examples (Nov 16 2026: "look at examples ... yours don't look
like them"). What the examples do and the old plans didn't:
  - SEPARATE BLOCKS with empty space between them, joined by bridge corridors (not a silhouette filled solid)
  - a layered round HUB in the middle: atrium, a ring hall, a band of rooms, an outer wall
  - a straight CROSS of bridges from the hub out to the edge, ending in small round pods
  - WINGS: arc-shaped blocks round the hub (between the bridges), each with an arc hall, big rooms on the inner side
    split by straight radial walls, and a row of equal small rooms round the outer rim
  - drawn as a glowing blueprint (cyan lines on a dark grid)
Everything mirror-true, sized to each deck's own outline (ellipses), clipped to the hull.
usage: python3 -I tools/trace/station_swtor.py [model ...]  -> stations/<model>/swtor.json, swtor.jpg"""
import json, math, os, sys
import numpy as np, cv2, shapely
from shapely import affinity
from shapely.geometry import Point, LineString, Polygon, box
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import station_plans as SP
import station_walkways as SW
import station_decks as SD

PX = 10.0
WM, WP = 3.2 * PX, 2.2 * PX
WALL = 0.5 * PX


def parts(g): return SW.parts(g)


def ell_ring(ax_, ay_, n=96):
    return [(ax_ * math.cos(2 * math.pi * i / n), ay_ * math.sin(2 * math.pi * i / n)) for i in range(n + 1)]


def ell(ax_, ay_, n=96):
    return Polygon(ell_ring(ax_, ay_, n)[:-1])


YK = [1.0, 1.0]   # (the egg: the +y half's / -y half's height scale of the current deck's ellipses)
def _y(ay, a): return ay * math.sin(a) * (YK[0] if math.sin(a) >= 0 else YK[1])
def sector(a0, a1, ax0, ay0, ax1, ay1, n=24, egg=True):
    """the band between two ellipses from angle a0 to a1 (degrees); egg: front and back halves scaled apart (the lift
    axis need not be the deck's middle)"""
    A = [math.radians(a0 + (a1 - a0) * i / n) for i in range(n + 1)]
    fy = _y if egg else (lambda ay, a: ay * math.sin(a))
    outer = [(ax1 * math.cos(a), fy(ay1, a)) for a in A]
    inner = [(ax0 * math.cos(a), fy(ay0, a)) for a in reversed(A)]
    return Polygon(outer + inner).buffer(0)


FILL_CELL = 7.5 * PX     # owner Nov 16: "still some spaces that we can utilize" - empty deck gets rooms (and a spur hall to reach deep ones)


def _grid(g, s):
    x0, y0, x1, y1 = g.bounds
    ls = [LineString([(k * s, y0 - s), (k * s, y1 + s)]) for k in range(int(x0 // s) - 1, int(x1 // s) + 2)]
    ls += [LineString([(x0 - s, k * s), (x1 + s, k * s)]) for k in range(int(y0 // s) - 1, int(y1 // s) + 2)]
    return shapely.set_precision(unary_union(ls).buffer(WALL / 2, cap_style=2), 0.05)


def _mx(g): return affinity.scale(g, -1, 1, origin=(0, 0))


def _sp(g): return shapely.set_precision(shapely.make_valid(g), 0.05)


def fill_empty(inner, halls, pods, rooms, lifts):
    """worked on the right half and mirrored, so the deck stays mirror-true"""
    from shapely.ops import polylabel, nearest_points
    inner_w = _sp(inner.buffer(-WALL, join_style=2))
    right = box(0, -1e5, 1e5, 1e5)
    def free_now():
        ways = unary_union([g for _, g in halls] + pods)
        taken = _sp(unary_union([_sp(g) for g in [ways] + [r["poly"] for r in rooms] + [q for _, q in lifts]]).buffer(WALL, join_style=2))
        free = _sp(inner_w.difference(taken))
        return ways, _sp(free.buffer(-1.2 * PX, join_style=2).buffer(1.2 * PX, join_style=2))   # (no slivers)
    for it in range(10):
        # 1. deep empty space no hall reaches: a spur hall in from the nearest way, right across it
        ways, free = free_now(); spurs = 0
        for part in parts(free.intersection(right)):
            if part.area < 60 * PX * PX: continue
            core = part.buffer(-WM / 2 - WALL)
            if core.is_empty: continue
            core = _sp(max(parts(core), key=lambda q: q.area))
            if core.is_empty or core.geom_type != 'Polygon': continue
            c = polylabel(core, 1.0)
            a = nearest_points(ways, c)[0]
            dx, dy = c.x - a.x, c.y - a.y; dl = math.hypot(dx, dy)
            if dl < 3 * PX: continue
            far = c
            seg = LineString([c, (c.x + dx / dl * 300 * PX, c.y + dy / dl * 300 * PX)]).intersection(core)
            for q in getattr(seg, "geoms", [seg]):
                if q.is_empty or q.distance(c) > 0.5 * PX: continue
                cs = list(q.coords); far = Point(max(cs, key=lambda t: math.hypot(t[0] - a.x, t[1] - a.y)))
            sp = SW.way((a.x, a.y), (far.x, far.y), WM)
            if sp.intersects(unary_union([q2 for _, q2 in lifts]).buffer(WALL)): continue
            sp = _sp(unary_union([sp, _mx(sp)]).intersection(inner_w))
            for r in rooms: r["poly"] = _sp(r["poly"].difference(sp.buffer(WALL, join_style=2)))
            halls.append(("spur", sp)); spurs += 1
        if spurs:
            keep = []
            for r in rooms:
                for q in parts(r["poly"]):
                    if q.area > 12 * PX * PX and not q.buffer(-1.4 * PX).is_empty: keep.append(dict(r, poly=q))
            rooms[:] = keep
        # 2. the empty space next to a way: a grid of rooms
        ways, free = free_now(); got = 0
        if free.is_empty: break
        cand = []
        for fp in parts(free):   # a small pocket is one room as it is; a big one is cut into a grid
            cand += [fp] if fp.area <= 70 * PX * PX else parts(_sp(fp.difference(_grid(fp, FILL_CELL))))
        for c in cand:
            if c.centroid.x < 0: continue
            if c.area < 12 * PX * PX or c.buffer(-1.5 * PX).is_empty: continue
            if c.area < 0.45 * c.minimum_rotated_rectangle.area: continue
            if c.distance(ways) > WALL * 2.5: continue
            for q in ([c] if c.centroid.x < 0.5 * PX else [c, _mx(c).intersection(free)]):
                for q2 in parts(q):
                    if q2.area > 12 * PX * PX: rooms.append({"poly": q2, "kind": "mech" if q2.area >= 50 * PX * PX else "pilot", "zone": "fill"}); got += 1
        if not got and not spurs: break


def path_way(region, a, b, w=WM):
    """a hall of width w from point a to point b that bends to stay inside region (through a hull neck, round a notch);
    None if there is no such way"""
    from skimage.graph import route_through_array
    core = region.buffer(-w / 2 + 0.2 * PX, join_style=2)
    if core.is_empty: return None
    RES = 0.5 * PX
    x0, y0, x1, y1 = region.bounds
    W, H = int((x1 - x0) / RES) + 3, int((y1 - y0) / RES) + 3
    m = np.zeros((H, W), np.uint8)
    for g in parts(core):
        cv2.fillPoly(m, [np.round((np.array(g.exterior.coords) - (x0, y0)) / RES).astype(np.int32)], 1)
        for h in g.interiors: cv2.fillPoly(m, [np.round((np.array(h.coords) - (x0, y0)) / RES).astype(np.int32)], 0)
    ys, xs = np.nonzero(m)
    if not len(xs): return None
    def snap(p):
        px_, py_ = (p.x - x0) / RES, (p.y - y0) / RES
        i = int(np.argmin((xs - px_) ** 2 + (ys - py_) ** 2)); return (int(ys[i]), int(xs[i]))
    sa, sb = snap(a), snap(b)
    cost = np.where(m > 0, 1.0, 1e6)
    path, c = route_through_array(cost, sa, sb, fully_connected=True, geometric=True)
    if c >= 1e5 or len(path) < 2: return None
    ln = LineString([(x0 + xx * RES, y0 + yy * RES) for yy, xx in path]).simplify(0.8 * PX)
    return unary_union([ln.buffer(w / 2, join_style=2), a.buffer(w / 2), b.buffer(w / 2)])


def connect_ways(inner, halls, pods, rooms, lifts):
    """owner Nov 16: every red way must join the rest - a mech can't reach a walkway that joins nothing.
    Each loose piece gets a straight link hall to the main network (mirrored); a piece no link can reach is removed."""
    from shapely.ops import nearest_points
    inner_w = _sp(inner.buffer(-WALL, join_style=2))
    for it in range(12):
        net = _sp(unary_union([_sp(g) for _, g in halls] + [_sp(q) for q in pods]).buffer(0.3 * PX))
        ps = parts(net)
        if len(ps) <= 1: return 0
        main = min(ps, key=lambda q: q.distance(Point(0, 0)))
        loose = sorted([q for q in ps if q is not main], key=lambda q: q.distance(main))
        q = loose[0]
        a, b = nearest_points(main, q)
        dx, dy = b.x - a.x, b.y - a.y; dl = math.hypot(dx, dy) or 1.0
        lk = SW.way((a.x - dx / dl * PX, a.y - dy / dl * PX), (b.x + dx / dl * PX, b.y + dy / dl * PX), WM)
        lk2 = _sp(unary_union([lk, _mx(lk)]).intersection(inner_w))
        ok = lk2.buffer(0.3 * PX).intersects(main) and \
            len(parts(_sp(unary_union([main, q, lk2.buffer(0.3 * PX)])))) == 1
        if not ok:   # no straight way: one that bends round the hull (through the neck)
            pw = path_way(inner_w, a, b)
            if pw is not None:
                lk2 = _sp(unary_union([pw, _mx(pw)]).intersection(inner_w))
                ok = lk2.buffer(0.3 * PX).intersects(main) and len(parts(_sp(unary_union([main, q, lk2.buffer(0.3 * PX)])))) == 1
        if ok:
            for r in rooms: r["poly"] = _sp(r["poly"].difference(lk2.buffer(WALL, join_style=2)))
            halls.append(("link", lk2))
        else:   # can't be reached: take it (and its mirror) out
            mq = _mx(q)   # (its mirror goes too only when that is loose as well - never cut the main network)
            cut = _sp(unary_union([q] + ([mq] if not mq.buffer(0.3 * PX).intersects(main) else [])).buffer(0.2 * PX))
            halls[:] = [(n, _sp(g.difference(cut))) for n, g in halls]
            pods[:] = [_sp(g.difference(cut)) for g in pods]
            halls[:] = [(n, g) for n, g in halls if not g.is_empty]; pods[:] = [g for g in pods if not g.is_empty]
    keep = []
    for r in rooms:
        for q in parts(r["poly"]):
            if q.area > 12 * PX * PX and not q.buffer(-1.4 * PX).is_empty: keep.append(dict(r, poly=q))
    rooms[:] = keep
    return len(parts(_sp(unary_union([_sp(g) for _, g in halls] + pods).buffer(0.3 * PX))))


BIG_ROOM = 130 * PX * PX    # owner Nov 16 (Velanthos hangar): huge wedge rooms and thin red strips read wrong


def tidy_rooms(rooms, halls, pods):
    """split huge rooms into a grid (keeping the pieces on a way), and a mech room must be a real bay (5 m wide);
    a thinner one is a pilot room, a strip under 3 m goes"""
    ways = _sp(unary_union([_sp(g) for _, g in halls] + [_sp(q) for q in pods]))
    out = []
    for r in rooms:
        ps = [r["poly"]]
        if r["poly"].area > BIG_ROOM:
            g = _sp(r["poly"]); ps = parts(_sp(g.difference(_grid(g, 10 * PX))))
        for q in ps:
            if q.area < 12 * PX * PX or q.buffer(-1.5 * PX).is_empty: continue
            if q.distance(ways) > WALL * 2.5: continue
            kind = r["kind"]
            if kind == "mech" and (q.buffer(-2.0 * PX).is_empty or q.area < 40 * PX * PX): kind = "pilot"
            out.append(dict(r, poly=q, kind=kind))
    rooms[:] = out


def prune_spurs(halls, pods, rooms):
    """a spur hall with fewer than 2 rooms on it is a dead walkway (owner Nov 16): take it out if nothing needs it"""
    def net(hs): return parts(_sp(unary_union([_sp(g) for _, g in hs] + [_sp(q) for q in pods]).buffer(0.3 * PX)))
    changed = True
    while changed:
        changed = False
        for i, (n, g) in enumerate(halls):
            if n not in ("spur", "link"): continue
            near = [r for r in rooms if r["poly"].distance(g) <= WALL * 2.5]
            if len(near) >= 2: continue
            rest = halls[:i] + halls[i + 1:]
            ways = _sp(unary_union([_sp(h) for _, h in rest] + [_sp(q) for q in pods]))
            if len(net(rest)) > 1: continue
            if any(r["poly"].distance(ways) > WALL * 2.5 for r in near): continue
            halls[:] = rest; changed = True; break


def layout(ol, role):
    inner = ol.buffer(-0.8 * PX, join_style=2)
    inner = max(parts(inner), key=lambda g: g.area)
    R = {d: SW.ray(inner, (0, 0), d, 200 * PX) for d in (0, 90, 180, 270)}
    rx, ry = min(R[0], R[180]), max(R[90], R[270], 1.0)
    YK[0], YK[1] = R[90] / ry, R[270] / ry
    ry_min = min(R[90], R[270])
    big = role in ("MAIN HUB",)
    # the hub: atrium, ring hall, a band of rooms, the outer wall
    h0 = (11 if big else 7) * PX
    h1 = h0 + WM                              # the hub's ring hall
    h2 = h1 + (7 if big else 6) * PX          # its band of rooms
    k = min(1.0, 0.4 * min(rx, ry_min) / h2)     # (a flat / small deck: a smaller hub, so the wings still fit round it)
    if k < 1.0:
        band = max(4.5 * PX, (h2 - h1) * k)
        h0 = max(4 * PX, h0 * k); h1 = h0 + WM; h2 = h1 + band
    rooms, halls, pods, lifts = [], [], [], []
    halls.append(("hub", Point(0, 0).buffer(h0, 64)))
    halls.append(("ring", Point(0, 0).buffer(h1, 64).difference(Point(0, 0).buffer(h0, 64))))
    gap = WM / 2 + WALL
    nb = 8 if big else 4
    for i in range(nb):
        a0, a1 = 360 * i / nb, 360 * (i + 1) / nb
        sc = sector(a0, a1, h1 + WALL, h1 + WALL, h2, h2, egg=False)
        for d in (0, 90, 180, 270):   # the cross runs through
            sc = sc.difference(SW.way((0, 0), (h2 * 2 * math.cos(math.radians(d)), h2 * 2 * math.sin(math.radians(d))), WM + 2 * WALL))
        for p in parts(sc):
            if p.area > 12 * PX * PX: rooms.append({"poly": p, "kind": "mech" if role in ("HANGAR", "ENGINEERING") and p.area > 40 * PX * PX else "pilot", "zone": "hub band"})
    # the wings: a hall that runs round the deck parallel to its hull, a row of equal rim rooms between it and the hull,
    # and big rooms on its inner side; empty space between them and the hub (the example's look, any deck shape)
    wing = None
    ewing = None
    for f in (0.74, 0.68, 0.62, 0.56):   # 1st choice: an elliptic wing ring (round stations: the example exactly)
        ax_m, ay_m = rx * f, min(R[90], R[270]) * f
        wb = min(12 * PX, min(ax_m, ay_m) - WM / 2 - h2 - 3 * PX)
        if wb < 4.5 * PX: continue
        ewing = (ax_m, ay_m, wb); break
    if ewing is not None:
        YK[0] = YK[1] = 1.0
        ax_m, ay_m, wb = ewing
        hw = WM / 2
        ai0, aj0 = ax_m - hw - wb, ay_m - hw - wb
        ai1, aj1 = ax_m - hw, ay_m - hw
        ao0, ap0 = ax_m + hw, ay_m + hw
        ao1, ap1 = ax_m + hw + 9 * PX, ay_m + hw + 9 * PX
        cross = unary_union([SW.way((0, 0), (300 * PX * math.cos(math.radians(d)), 300 * PX * math.sin(math.radians(d))), WM + 8 * PX) for d in (0, 90, 180, 270)])
        band = sector(0, 360, ai1, aj1, ao0, ap0, n=96, egg=False)
        halls.append(("wing hall", band.difference(cross).intersection(inner)))
        for q in range(4):
            a0, a1 = 90 * q, 90 * (q + 1)
            for j in range(2):
                b0, b1 = a0 + (a1 - a0) * j / 2, a0 + (a1 - a0) * (j + 1) / 2
                pp0 = sector(b0, b1, ai0, aj0, ai1 - WALL, aj1 - WALL, egg=False).difference(cross).buffer(-WALL / 2, join_style=2).intersection(inner)
                for pp in parts(pp0):
                    if pp.area > 25 * PX * PX: rooms.append({"poly": pp, "kind": "mech" if pp.area >= 45 * PX * PX else "pilot", "zone": "wing"})
            n = max(3, int(math.hypot(ao1, ap1) * math.radians(90) * 0.85 / (7.5 * PX)))
            for j in range(n):
                b0, b1 = a0 + (a1 - a0) * j / n, a0 + (a1 - a0) * (j + 1) / n
                pp0 = sector(b0, b1, ao0 + WALL, ap0 + WALL, ao1, ap1, egg=False).difference(cross).buffer(-WALL / 2, join_style=2)
                full = pp0.area
                for pp in parts(pp0.intersection(inner)):
                    if pp.area > 0.6 * full and pp.area > 12 * PX * PX: rooms.append({"poly": pp, "kind": "pilot", "zone": "rim"})
        wing = ("ellipse", ewing)
        for sx in (1, -1): lifts.append(("Freight lift", Point(sx * ax_m, 0).buffer(2.3 * PX, 8)))
    cross_cut = unary_union([SW.way((0, 0), (300 * PX * math.cos(math.radians(d)), 300 * PX * math.sin(math.radians(d))), WM + 8 * PX) for d in (0, 90, 180, 270)])
    smooth = inner.buffer(-6 * PX, join_style=2).buffer(6 * PX, join_style=2).simplify(2.5 * PX)
    smooth = max(parts(smooth), key=lambda g: g.area) if parts(smooth) else inner
    for rim in ((9 * PX, 7 * PX, 5.5 * PX) if wing is None else ()):
        core = smooth.buffer(-rim, join_style=2).simplify(2.0 * PX)
        core = max(parts(core), key=lambda g: g.area) if parts(core) else Polygon()
        if core.is_empty: continue
        hall_in = core.buffer(-WM, join_style=2)
        hall_in = max(parts(hall_in), key=lambda g: g.area) if parts(hall_in) else Polygon()
        void = Point(0, 0).buffer(h2 + 4 * PX, 64)
        if hall_in.is_empty: continue
        wing = (rim, core, hall_in, void); break
    if wing is not None and wing[0] != "ellipse":
        rim, core, hall_in, void = wing
        hall_band = core.difference(hall_in).difference(cross_cut.difference(SW.way((0, 0), (1, 0), 1)))
        halls.append(("wing hall", core.difference(hall_in).difference(void.buffer(WALL))))
        rim_band = smooth.difference(core.buffer(WALL, join_style=2)).difference(cross_cut).difference(void.buffer(WALL))
        wb = 11 * PX
        big_band = hall_in.buffer(-WALL, join_style=2).difference(hall_in.buffer(-wb, join_style=2)).difference(void).difference(cross_cut)
        ring = core.exterior                       # cut lines across the bands, square to the hall
        def cuts(step, reach):
            out = []
            Lr = ring.length; n = max(8, int(Lr / step))
            for i in range(n):
                p0 = ring.interpolate(Lr * i / n); p1 = ring.interpolate(Lr * i / n + 0.5 * PX)
                tx, ty = p1.x - p0.x, p1.y - p0.y; tl = math.hypot(tx, ty) or 1
                nx, ny = -ty / tl, tx / tl
                out.append(LineString([(p0.x - nx * reach, p0.y - ny * reach), (p0.x + nx * reach, p0.y + ny * reach)]).buffer(WALL / 2))
            return unary_union(out)
        cr = cuts(7.5 * PX, 30 * PX)
        for p in parts(rim_band.difference(cr)):
            if p.area > 14 * PX * PX and p.area > 0.62 * p.minimum_rotated_rectangle.area: rooms.append({"poly": p.buffer(-WALL / 2, join_style=2), "kind": "pilot", "zone": "rim"})
        cb = cuts(20 * PX, 40 * PX)
        for p in parts(big_band.difference(cb)):
            if p.area > 30 * PX * PX and p.area > 0.55 * p.minimum_rotated_rectangle.area: rooms.append({"poly": p.buffer(-WALL / 2, join_style=2), "kind": "mech" if p.area >= 45 * PX * PX else "pilot", "zone": "wing"})
        rooms = [r for r in rooms if not r["poly"].is_empty]
    # the cross: bridges from the hub ring to the edge, a round pod at each end
    for d in (0, 90, 180, 270):
        L = R[d] - 3 * PX
        if L < h2 + 4 * PX: continue
        a = math.radians(d)
        e = (L * math.cos(a), L * math.sin(a))
        halls.append(("bridge", SW.way((h0 * math.cos(a), h0 * math.sin(a)), e, WM).intersection(inner)))
        pod = Point(e).buffer(4.2 * PX, 8).intersection(inner)
        if pod.area > 20 * PX * PX: pods.append(pod)
    lifts.append(("Main lift", Point(0, 0).buffer(3.0 * PX, 8)))
    if wing is not None and wing[0] != "ellipse":
        for d in (0, 180):   # freight lifts where the cross meets the wing hall
            ln = LineString([(0, 0), (300 * PX * math.cos(math.radians(d)), 0)]).intersection(wing[1].difference(wing[2]))
            if not ln.is_empty: lifts.append(("Freight lift", ln.centroid.buffer(2.3 * PX, 8)))
    connect_ways(inner, halls, pods, rooms, lifts)
    tidy_rooms(rooms, halls, pods)
    fill_empty(inner, halls, pods, rooms, lifts)
    left = connect_ways(inner, halls, pods, rooms, lifts)
    tidy_rooms(rooms, halls, pods)
    prune_spurs(halls, pods, rooms)
    if left > 1: print('  loose ways left:', left, role, flush=True)
    # mirror-true at the end: the right half, mirrored (fill and links can come out a little lopsided)
    right = box(0, -1e5, 1e5, 1e5)
    wh = _sp(unary_union([_sp(g) for _, g in halls] + [_sp(q) for q in pods]).intersection(right))
    halls = [("ways", _sp(unary_union([wh, _mx(wh)]).buffer(0.2 * PX, join_style=2).buffer(-0.2 * PX, join_style=2)))]; pods = []
    sym = []
    for r in rooms:
        cx = r["poly"].centroid.x
        if r["poly"].bounds[0] >= -0.2 * PX: sym += [r, dict(r, poly=_mx(r["poly"]))] if r["poly"].bounds[0] > 0.2 * PX else [dict(r, poly=_sp(unary_union([r["poly"], _mx(r["poly"])])))]
        elif cx >= -0.3 * PX:
            hr = r["poly"].intersection(right); sym.append(dict(r, poly=_sp(unary_union([hr, _mx(hr)]))))
    rooms = [r for r in sym if not r["poly"].is_empty and r["poly"].geom_type == "Polygon"]
    # keep only what is joined up
    ways = unary_union([g for _, g in halls] + pods)
    rooms = [r for r in rooms if r["poly"].buffer(WALL * 2).intersects(ways)]
    return {"outline": ol, "inner": inner, "halls": halls, "rooms": rooms, "pods": pods, "lifts": lifts, "ways": ways,
            "wing": wing is not None}


GRID = (40, 26, 8)
LINE = (255, 230, 120)       # BGR cyan glow
DIM = (150, 120, 40)


DOOR_BGR = {0: (90, 255, 90), 1: (40, 230, 255), 2: (30, 140, 255), 3: (60, 60, 255), 4: (230, 80, 200)}   # the ships' map colours + purple


def draw(L, title, sub, rooms_named, size=640, header=True):
    """the deck in the SAME look as the fleet ships' in-game deck maps (tools/holodeck: dark blue, the hull a shade
    lighter, the floor in blue with bright cyan walls, key-coloured door squares, white LIFT boxes, names in capitals)"""
    g = L["outline"]; x0, y0, x1, y1 = g.bounds
    S = size * 0.9 / max(x1 - x0, y1 - y0)
    ox, oy = size / 2 - (x0 + x1) / 2 * S, size * 0.53 - (y0 + y1) / 2 * S
    T = lambda q: affinity.affine_transform(q, [S, 0, 0, S, ox, oy])
    img = np.zeros((size, size, 3), np.uint8); img[:] = (40, 16, 8)
    def mask(q):
        m = np.zeros((size, size), np.uint8)
        for p in parts(T(q)):
            m1 = np.zeros_like(m)
            cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 1)
            for h in p.interiors: cv2.fillPoly(m1, [np.array(h.coords, np.int32)], 0)
            m |= m1
        return m
    hull = mask(g)
    img[hull > 0] = (70, 34, 14)
    cs, _ = cv2.findContours(hull, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    cv2.drawContours(img, cs, -1, (160, 110, 40), 2, cv2.LINE_AA)
    # v13.170 (owner: "in game there are red walkways for mechs"): the ships' MECH / PILOT WAYS colours - every hall,
    # bridge and pod is a mech way (red), mech rooms red, pilot rooms blue, white walls, as the in-game ways map
    floor = unary_union([q for _, q in L["halls"]] + L["pods"]).buffer(0.6 * PX, join_style=2).buffer(-0.6 * PX, join_style=2)
    fm = mask(floor)
    over = img.copy()
    over[fm > 0] = (55, 45, 170)
    for r in rooms_named:
        rm = mask(r["poly"])
        over[rm > 0] = (45, 30, 120) if r["kind"] == "mech" else (175, 95, 30)
    img = cv2.addWeighted(over, 0.85, img, 0.15, 0)
    for r in rooms_named:
        cs, _ = cv2.findContours(mask(r["poly"]), cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
        cv2.drawContours(img, cs, -1, (245, 245, 245), 2, cv2.LINE_AA)
    cs, _ = cv2.findContours(fm, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    cv2.drawContours(img, cs, -1, (245, 245, 245), 2, cv2.LINE_AA)
    k = size / 640.0
    for r in rooms_named:
        d = T(Point(r["door"]))
        h = int((5 if r["kind"] == "mech" else 3.5) * k)
        cv2.rectangle(img, (int(d.x) - h, int(d.y) - h), (int(d.x) + h, int(d.y) + h), DOOR_BGR[r["key"]], -1)
    for nm, q in L["lifts"]:
        c = T(q.centroid); h = int(8 * k)
        cv2.rectangle(img, (int(c.x) - h, int(c.y) - h), (int(c.x) + h, int(c.y) + h), (0, 215, 255), -1)   # (elevators yellow)
        cv2.rectangle(img, (int(c.x) - h, int(c.y) - h), (int(c.x) + h, int(c.y) + h), (0, 0, 0), 1)
        cv2.putText(img, "LIFT", (int(c.x) - int(9 * k), int(c.y) + int(3 * k)), 0, 0.26 * k, (0, 0, 0), 1, cv2.LINE_AA)
    for r in rooms_named:
        q = T(r["poly"])
        t = r["name"].upper() + (" * %s CARD" % SP.KEY_NAME[r["card"]] if r.get("card") else "") + (" [OBJECTIVE]" if r.get("objective") else "")
        sc = 0.3 * k
        (tw, th), _ = cv2.getTextSize(t, 0, sc, 1)
        c = q.representative_point()
        if not q.buffer(1).contains(box(c.x - tw / 2, c.y - th / 2 - 1, c.x + tw / 2, c.y + th / 2 + 1)): continue   # (only a name that fits its room)
        col = (60, 230, 255) if r.get("card") or r.get("objective") else (255, 255, 255)
        cv2.putText(img, t, (int(c.x - tw / 2), int(c.y + th / 2)), 0, sc, col, 1, cv2.LINE_AA)
    if header:
        cv2.putText(img, title, (int(14 * k), int(28 * k)), 0, 0.62 * k, (255, 240, 170), max(1, int(1.5 * k)), cv2.LINE_AA)
        cv2.putText(img, sub, (int(14 * k), int(46 * k)), 0, 0.36 * k, (120, 200, 255), 1, cv2.LINE_AA)
    return img


def own_outline(O, k):
    """owner Nov 16: each floor has its own silhouette at its own height. The deck's slice and the slices just above
    and below it, closed up into a floor (not the top-down silhouette the old code fell back to)"""
    M, i = O["masks"], O["idx"][k]
    m = np.zeros_like(M[0])
    for j in range(max(0, i - 1), min(len(M), i + 2)): m = np.maximum(m, M[j])
    m = (m > 0).astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (31, 31)))
    m = SP.clean(m)
    return SP.outline(m)


def build(st):
    model = st["model"]
    O = SP.deck_outlines(st)
    style = next((k for k in SW.STYLE_M if "_%s_" % k in model), None)
    width_m = SW.STYLE_M.get(style, SW.ST3D_M.get(model, 120.0))
    f = width_m * PX / (SP.N - 40)
    c0 = O["c"]
    to_plan = lambda g: affinity.affine_transform(g, [f, 0, 0, f, -c0[0] * f, -c0[1] * f])
    hub0 = O["polys"][2]
    for k in range(5):
        if O["src"][k] != "silhouette": continue
        g = own_outline(O, k)
        if g is not None and g.area >= 0.2 * hub0.area: O["polys"][k] = shapely.make_valid(g.buffer(0)); O["src"][k] = "own slice"
    OLS = [SD.mirror_true(to_plan(O["polys"][k])) for k in range(5)]
    def room_at(y):   # (as station_decks: the lift axis goes where the decks are solid - a ring station's hole is not)
        pt = Point(0, y); sc = 0.0
        for k2, g in enumerate(OLS):
            w = 3.0 if k2 == 2 else 1.0
            sc += w * (g.exterior.distance(pt) if g.contains(pt) and not any(Polygon(h).contains(pt) for h in g.interiors) else -50 * PX)
        return sc
    ys = [y * PX for y in range(-70, 71, 2)]
    y0 = max(ys, key=lambda y: (room_at(y), -abs(y)))
    if room_at(0.0) >= 0.85 * room_at(y0): y0 = 0.0
    OLS = [affinity.translate(g, 0, -y0) for g in OLS]
    hub_ol = OLS[2]
    decks, panels = [], []
    for k, role in enumerate(SP.DECKS):
        ol = OLS[k]
        if ol.area < 0.2 * hub_ol.area:
            t = 0.05 * math.sqrt(hub_ol.area) * abs(k - 2)
            g2 = hub_ol.buffer(-t, join_style=2); ol = max(parts(g2), key=lambda q: q.area) if parts(g2) else hub_ol
        L = layout(ol, role)
        # names: services in the hub band on the hub deck, then the deck's role list, then fillers
        roles = SP.ROLES[role]
        order = sorted(range(len(L["rooms"])), key=lambda i: L["rooms"][i]["poly"].centroid.distance(Point(0, 0)))
        used, named = set(), []
        import random; rng = random.Random(sum(map(ord, model)) + k)
        for i in order:
            r = L["rooms"][i]
            pool = [x for x in roles if x[1] == r["kind"] and x[0] not in used]
            if pool: nm = pool[0]
            else:
                base = rng.choice(SP.FILL[r["kind"]]); j = 1
                while "%s %d" % (base, j) in used: j += 1
                nm = ("%s %d" % (base, j), r["kind"], rng.choice(SD.FILL_KEY[role]), "")
            used.add(nm[0])
            from shapely.ops import nearest_points
            dp = nearest_points(L["ways"], r["poly"])[1]
            named.append({"name": nm[0], "kind": r["kind"], "key": int(nm[2]), "sign": nm[3], "zone": r["zone"], "poly": r["poly"],
                          "door": (dp.x, dp.y), "area_m2": round(r["poly"].area / PX / PX, 1),
                          "centre": [round(r["poly"].centroid.x / PX, 2), round(r["poly"].centroid.y / PX, 2)]})
        decks.append({"deck": k + 1, "role": role, "rooms": named, "_L": L})
    chain, ok = SD.keys_chain(decks, sum(map(ord, model)))
    for D in decks:
        L = D["_L"]
        n = len(D["rooms"]); nm = sum(r["kind"] == "mech" for r in D["rooms"])
        panels.append(draw(L, "%s  -  %s DECK" % (st["name"].upper(), D["role"]), "%d rooms (%d mech, %d pilot) · hub, cross, %s" % (n, nm, n - nm, "wings" if L["wing"] else "no wings"), D["rooms"]))
    leg = SW.legend(O["top"], st, ["%s  (%s)" % (st["name"], st["faction"] or "-"), "system %s" % st["system"], "model %s" % model,
                                    "v3: the SWTOR example style", "PROPOSED: X = close, O = fix"])
    cv2.rectangle(leg, (325, 60), (640, 360), (0, 0, 0), -1)
    y = 90
    for txt, col in (("MECH WAY (red)", (55, 45, 170)), ("MECH BAY (dark red)", (45, 30, 120)), ("PILOT ROOM (blue)", (175, 95, 30)), ("ELEVATOR (yellow)", (0, 215, 255)), ("door OPEN", DOOR_BGR[0]), ("door YELLOW card", DOOR_BGR[1]), ("door ORANGE card", DOOR_BGR[2]),
                     ("door RED card", DOOR_BGR[3]), ("door PURPLE card", DOOR_BGR[4]), ("big square = mech door", (200, 200, 200))):
        cv2.rectangle(leg, (330, y - 13), (346, y + 3), col, -1)
        cv2.putText(leg, txt, (356, y), 0, 0.46, (230, 230, 230), 1, cv2.LINE_AA); y += 26
    y = 520
    for ln in chain[:6]:
        cv2.putText(leg, ln[:70], (14, y), 0, 0.38, (60, 220, 255), 1, cv2.LINE_AA); y += 18
    panels.append(leg)
    sheet = np.vstack([np.hstack([panels[4], panels[3], panels[5]]), np.hstack([panels[2], panels[1], panels[0]])])
    od = os.path.join(SP.OUT, model)
    cv2.imwrite(os.path.join(od, "swtor.jpg"), cv2.resize(sheet, (1920, 1280), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 84])
    return [len(D["rooms"]) for D in decks]


if __name__ == "__main__":
    S = json.load(open(os.path.join(SP.OUT, "stations.json")))
    for st in S:
        if sys.argv[1:] and st["model"] not in sys.argv[1:]: continue
        print(st["model"], build(st), flush=True)
