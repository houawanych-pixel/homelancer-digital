#!/usr/bin/env python3
"""Zoom-in trace (x4) of the owner's "Overhead district maps" sheet (Nov 18 2026): five decks on the Liberty Hub GLB
slices. Per deck panel: the RED mech rooms, the BLUE pilot rooms and the YELLOW lifts are read by their fill colour,
each room becomes one clean polygon (walls snapped to 0 / 45 / 90 deg), the hull is the cyan glow outline.
Output per deck: <deck>_trace.jpg (blue lines on the dimmed panel) and <deck>_trace.json (polygons, panel x4 px);
and trace_sheet.jpg (all five)."""
import json, os
import cv2, numpy as np
from shapely.geometry import Polygon, mapping

HERE = os.path.dirname(os.path.abspath(__file__))
DECKS = ["hangar", "engineering", "main_hub", "habitat", "command"]
BLUE_LINE = (255, 150, 30)
k = lambda s: cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (s, s))


def snap(c, eps=6.0, tol=14):
    p = cv2.approxPolyDP(c, eps, True).reshape(-1, 2).astype(float); m = len(p)
    if m < 3: return p
    d = np.roll(p, -1, 0) - p; ang = np.degrees(np.arctan2(d[:, 1], d[:, 0]))
    sn = np.round(ang / 45.0) * 45.0
    straight = np.abs((ang - sn + 180) % 360 - 180) < tol
    mid = p + d / 2; u = np.stack([np.cos(np.radians(sn)), np.sin(np.radians(sn))], 1)
    out = []
    for i in range(m):
        e0, e1 = (i - 1) % m, i
        if straight[e0] and straight[e1]:
            A = np.array([u[e0], -u[e1]]).T
            if abs(np.linalg.det(A)) > 1e-6:
                t = np.linalg.solve(A, mid[e1] - mid[e0]); q = mid[e0] + t[0] * u[e0]
                if np.hypot(*(q - p[i])) < 30: out.append(q); continue
        out.append(p[i])
    return np.array(out)


def blobs(m, min_area):
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=4); out = []
    for i in range(1, n):
        if st[i, 4] < min_area: continue
        cs, _ = cv2.findContours((lab == i).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        c = max(cs, key=cv2.contourArea)
        pg = Polygon(snap(c)).buffer(0)
        if pg.geom_type != "Polygon": pg = max(pg.geoms, key=lambda q: q.area)
        if not pg.is_empty: out.append(pg)
    return out


def clean_shape(pg, lift=False):
    """Engineering-clean room: a rectangle, a circle, or a rectangle with cut corners, fitted to the traced blob (the
    label letters and floor art no longer bite into it)."""
    from shapely.geometry import box, Point
    x0, y0, x1, y1 = pg.bounds; w, h = x1 - x0, y1 - y0; bx = box(x0, y0, x1, y1)
    if lift: return box(x0, y0, x1, y1)
    hull = pg.convex_hull; fill = hull.area / bx.area
    circ = 4 * np.pi * hull.area / hull.length ** 2
    if circ > 0.93 and 0.85 < w / h < 1.18:
        c = hull.centroid; return Point(c.x, c.y).buffer((w + h) / 4, 32)
    if fill > 0.93: return bx
    # cut corners: measured from how much each corner is missing
    cut = []
    for cx, cy in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
        d = 0
        for t in range(2, int(min(w, h) / 2.5), 2):
            from shapely.geometry import Point as P_
            if hull.contains(P_(cx + (t if cx == x0 else -t) * 0.71, cy + (t if cy == y0 else -t) * 0.71)): break
            d = t
        cut.append(d * 1.41 if d > 8 else 0)
    a, b_, c_, d_ = cut
    return Polygon([(x0 + a, y0), (x1 - b_, y0), (x1, y0 + b_), (x1, y1 - c_), (x1 - c_, y1), (x0 + d_, y1), (x0, y1 - d_), (x0, y0 + a)]).buffer(0)


def trace(name):
    im = cv2.imread(os.path.join(HERE, name + ".png"))
    a = cv2.GaussianBlur(im, (7, 7), 0).astype(int); b, g, r = a[..., 0], a[..., 1], a[..., 2]
    red = ((r > b + 35) & (r > g + 35) & (r > 80)).astype(np.uint8)
    blue = ((b > r + 50) & (b > 90) & (g < b - 25) & (g < 120)).astype(np.uint8)
    yel = ((r > 170) & (g > 150) & (b < 90)).astype(np.uint8)
    # the white room walls (thin bright lines): kept open so two rooms side by side stay two rooms
    wr = im.astype(int); white = ((wr.min(2) > 185)).astype(np.uint8)
    wall = cv2.morphologyEx(white, cv2.MORPH_OPEN, k(3)) - cv2.morphologyEx(white, cv2.MORPH_OPEN, k(19)).clip(0, 1)
    wall = cv2.dilate(wall.clip(0, 1).astype(np.uint8), k(5))
    # fills: the white label text and floor art inside a room close up; the white walls between rooms stay open
    def fill(m, close, open_):
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, k(close)); m = cv2.morphologyEx(m, cv2.MORPH_OPEN, k(open_))
        inv = 1 - m; n_, l_, s_, _ = cv2.connectedComponentsWithStats(inv, connectivity=4)
        for i in range(1, n_):
            if s_[i, 4] < 9000: m[l_ == i] = 1   # letters are part of the room
        return m
    redm = fill(red, 13, 21); bluem = fill(blue & (1 - redm), 13, 21); yelm = fill(yel, 5, 9)
    near_wall = cv2.dilate(white, k(15))
    def framed(L, need):     # a real room is framed by its white wall; hull lights and specks are not
        out = []
        for pg in L:
            ring = pg.exterior; pts = [ring.interpolate(t, normalized=True) for t in np.linspace(0, 1, 80, endpoint=False)]
            hit = np.mean([near_wall[min(int(p.y), near_wall.shape[0] - 1), min(int(p.x), near_wall.shape[1] - 1)] for p in pts])
            if hit >= need: out.append(pg)
        return out
    # red rooms drawn wall to wall: cut on the white wall lines between them (only long straight ones, not letters)
    ln = np.zeros_like(white)
    hl = cv2.morphologyEx(white, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (61, 1)))
    vl = cv2.morphologyEx(white, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (1, 61)))
    ln = cv2.dilate(hl | vl, k(7))
    redm = cv2.morphologyEx(redm & (1 - ln), cv2.MORPH_OPEN, k(9))
    # rooms stacked on the centre line touch: cut each red blob at its necks (rows where it narrows between two wider parts)
    n_, l_, s_, _ = cv2.connectedComponentsWithStats(redm, connectivity=4)
    for i in range(1, n_):
        m_ = (l_ == i); ys = np.where(m_.any(1))[0]
        if len(ys) < 200: continue
        wdt = m_.sum(1).astype(float); sm = np.convolve(wdt, np.ones(9) / 9, "same")
        cuts = []
        for y in range(ys.min() + 60, ys.max() - 60):
            up, dn = sm[ys.min():y - 25].max(), sm[y + 25:ys.max()].max()
            if sm[y] < 0.8 * min(up, dn) and sm[y] == sm[y - 30:y + 31].min(): cuts.append(y)
        for y in cuts: redm[y - 6:y + 7][m_[y - 6:y + 7]] = 0
    R = framed(blobs(redm, 9000), 0.2); B = [q for q in blobs(bluem, 7000) if q.area > 40000 or q in framed([q], 0.2)]; B = [q for q in B if q.area > 22000 or q in framed([q], 0.5)]; Y = blobs(yelm, 1500)
    R, Y = [clean_shape(q) for q in R], [clean_shape(q, lift=True) for q in Y]
    B0 = [clean_shape(q) for q in B]
    from shapely.ops import unary_union
    from shapely.geometry import Point
    for i, q in enumerate(B):               # an open plaza (Commons) wraps round its neighbours: the biggest clean
        if q.area < 40000: continue        # octagon round its middle that stays clear of them
        others = [B0[j] for j in range(len(B)) if j != i and B0[j].intersects(B0[i])]
        if not others: continue
        block = unary_union(others + Y + R).buffer(16); c = q.centroid; best = None
        for rr in range(60, 600, 6):
            o = Point(c.x, c.y).buffer(rr, 1).envelope.intersection(Point(c.x, c.y).buffer(rr * 1.08).envelope.buffer(0))
            o = Polygon([(c.x + rr * np.cos(np.radians(a)) / np.cos(np.radians(22.5)), c.y + rr * np.sin(np.radians(a)) / np.cos(np.radians(22.5))) for a in range(int(22.5), 382, 45)])
            if o.intersects(block): break
            best = o
        if best is not None: B0[i] = best
    B = B0
    # the hull: the cyan glow and everything it closes in
    cy = ((g > 150) & (b > 170) & (r < 170)).astype(np.uint8) | redm | bluem | yelm
    cy = cv2.morphologyEx(cy, cv2.MORPH_CLOSE, k(25))
    n0, l0 = cv2.connectedComponents(1 - cy, connectivity=4)
    edge = set(np.unique(np.concatenate([l0[0], l0[-1], l0[:, 0], l0[:, -1]]))) - {0}
    hull = (~np.isin(l0, list(edge))).astype(np.uint8)
    n_, l_, s_, _ = cv2.connectedComponentsWithStats(hull); hull = (l_ == 1 + np.argmax(s_[1:, 4])).astype(np.uint8)
    cs, _ = cv2.findContours(hull, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    H = Polygon(cv2.approxPolyDP(max(cs, key=cv2.contourArea), 5, True).reshape(-1, 2)).buffer(0)
    # draw: dimmed panel, red / blue / yellow fills, blue lines
    out = (im * 0.35).astype(np.uint8); fl = out.copy()
    for pg, col in [(q, (40, 40, 200)) for q in R] + [(q, (200, 90, 30)) for q in B] + [(q, (0, 210, 240)) for q in Y]:
        cv2.fillPoly(fl, [np.array(pg.exterior.coords, np.int32)], col)
    out = cv2.addWeighted(fl, 0.6, out, 0.4, 0)
    for pg in [H] + R + B + Y:
        cv2.polylines(out, [np.array(pg.exterior.coords, np.int32)], True, BLUE_LINE, 4, cv2.LINE_AA)
    cv2.imwrite(os.path.join(HERE, name + "_trace.jpg"), out, [cv2.IMWRITE_JPEG_QUALITY, 88])
    json.dump({"units": "panel px x4", "hull": mapping(H), "mech": [mapping(q) for q in R], "pilot": [mapping(q) for q in B],
               "lifts": [mapping(q) for q in Y]}, open(os.path.join(HERE, name + "_trace.json"), "w"))
    print(name, "red", len(R), "blue", len(B), "lifts", len(Y))
    return out


if __name__ == "__main__":
    T = [trace(d) for d in DECKS]
    h = 900; T = [cv2.resize(t, (int(t.shape[1] * h / t.shape[0]), h)) for t in T]
    cv2.imwrite(os.path.join(HERE, "trace_sheet.jpg"), np.hstack(T), [cv2.IMWRITE_JPEG_QUALITY, 88])
