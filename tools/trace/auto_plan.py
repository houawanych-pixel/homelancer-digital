#!/usr/bin/env python3
"""First-pass engineering plan for a HoloDeck sheet (the owner's style: glowing cyan walls, green door squares,
labelled rooms). Measures the sheet's own walls; never invents a room. Output is the SAME plan.json that
fleet_<id>/eng/build_plan.py writes (rooms, halls, doors, floor, walls), so to_deck_json.py takes it as is.

  python3 -I tools/trace/auto_plan.py <ship id>            -> tools/trace/fleet_<id>/eng/{plan.json, plan.png, plan_on_map.jpg, auto_report.json}

How:
  walls     : top-hat of the sheet's own lines (+ the green door squares), so rooms close at their doors
  rooms     : the floor piece under each seed label (tools/holodeck/seeds/<id>.json), furniture holes filled, then
              a clean shape: a circle / ellipse if it is round, a rectangle if it is near one, else its outline with
              every edge snapped to 0 / 45 / 90 degrees and one wall thickness
  hallways  : the unlabelled floor pieces the doors join (kept if a door touches them), cleaned the same way
  doors     : one per green square, one standard width, oriented by which sides are floor
  symmetry  : the sheet's mirror axis is found; the left half is kept and mirrored (the owner's ships are symmetric)
  overrides : tools/trace/fleet_<id>/eng/overrides.json can drop pieces, add doors, rename, or replace a room's
              shape with measured points (that is how each ship is corrected after the owner marks X / O)."""
import json, os, sys, math
import cv2, numpy as np
from shapely import affinity
from shapely.geometry import Point, Polygon, box, mapping, LineString, MultiPolygon
from shapely.ops import unary_union

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
T, DOOR = 4.0, 16.0

def mirror_axis(g):
    H, W = g.shape
    best = None
    for ax in np.arange(W * 0.42, W * 0.58, 0.5):
        w = int(min(ax, W - ax)) - 5
        L = g[int(H * .08):int(H * .92), int(ax - w):int(ax)].astype(float)
        R = g[int(H * .08):int(H * .92), int(ax):int(ax + w)][:, ::-1].astype(float)
        n = min(L.shape[1], R.shape[1]); d = np.abs(L[:, -n:] - R[:, -n:]).mean()
        if best is None or d < best[0]: best = (d, float(ax))
    return best[1], best[0]

def masks(im):
    g = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
    B, G, R = [im[:, :, i].astype(int) for i in range(3)]
    green = ((G > 150) & (R < 150) & (G - B > 15)).astype(np.uint8)
    th = cv2.morphologyEx(g, cv2.MORPH_TOPHAT, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
    wall = ((th > 38) | (g > 205)).astype(np.uint8) | green
    wall = cv2.dilate(wall, np.ones((3, 3), np.uint8))
    return g, green, wall

def snap_poly(mask, eps=2.5, hull=True):
    cs, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cs: return None
    c = max(cs, key=cv2.contourArea)
    if hull: c = cv2.convexHull(c)
    area = cv2.contourArea(c)
    if area < 60: return None
    per = cv2.arcLength(c, True)
    x, y, w, h = cv2.boundingRect(c)
    circ = 4 * math.pi * area / max(per * per, 1)
    if circ > 0.84 and 0.85 < w / h < 1.18:       # round room: a true circle at its measured size
        (cx, cy), r = cv2.minEnclosingCircle(c)
        r2 = math.sqrt(area / math.pi)
        return Point(cx, cy).buffer((r + r2) / 2, 64)
    if area > 0.93 * w * h:                        # near a rectangle: the rectangle
        return box(x, y, x + w, y + h)
    ap = cv2.approxPolyDP(c, eps, True)[:, 0, :].astype(float)
    # snap each edge to 0 / 45 / 90 degrees: rebuild corners as the crossings of the snapped edge lines
    n = len(ap)
    lines = []
    for i in range(n):
        a, b = ap[i], ap[(i + 1) % n]
        ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])) % 180
        snapped = min([0, 45, 90, 135, 180], key=lambda s: abs(ang - s)) % 180
        if abs(((ang - snapped + 90) % 180) - 90) > 14: snapped = ang   # a real odd angle: keep it
        mid = (a + b) / 2
        d = np.array([math.cos(math.radians(snapped)), math.sin(math.radians(snapped))])
        lines.append((mid, d, np.linalg.norm(b - a)))
    pts = []
    for i in range(n):
        (p1, d1, _), (p2, d2, _) = lines[i - 1], lines[i]
        den = d1[0] * d2[1] - d1[1] * d2[0]
        if abs(den) < 1e-6: continue                 # parallel neighbours: drop the joint
        t = ((p2[0] - p1[0]) * d2[1] - (p2[1] - p1[1]) * d2[0]) / den
        pts.append(p1 + d1 * t)
    if len(pts) < 3: return box(x, y, x + w, y + h)
    p = Polygon(pts).buffer(0)
    if p.is_empty or abs(p.area - area) > 0.35 * area: return box(x, y, x + w, y + h)
    if p.geom_type != "Polygon": p = max(p.geoms, key=lambda q: q.area)
    return Polygon([(round(px * 2) / 2, round(py * 2) / 2) for px, py in p.exterior.coords]).buffer(0)

def main(sid):
    hd = [f for f in os.listdir(os.path.join(ROOT, "assets/holodeck")) if f.lower().startswith("hl_" + sid.replace("_", "").lower()) and f.endswith(".jpg")]
    src_path = os.path.join(ROOT, "assets/holodeck", hd[0])
    seed = json.load(open(os.path.join(ROOT, "tools/holodeck/seeds", sid + ".json")))
    folder = os.path.join(ROOT, "tools/trace", "fleet_" + sid)
    eng = os.path.join(folder, "eng"); os.makedirs(eng, exist_ok=True)
    im = cv2.imread(src_path); H, W = im.shape[:2]
    if not os.path.exists(os.path.join(folder, "source.jpg")): cv2.imwrite(os.path.join(folder, "source.jpg"), im, [cv2.IMWRITE_JPEG_QUALITY, 90])
    ov_path = os.path.join(eng, "overrides.json")
    OV = json.load(open(ov_path)) if os.path.exists(ov_path) else {}
    g, green, wall = masks(im)
    AX, asym = mirror_axis(g)
    AX = OV.get("mirror_x", round(AX * 2) / 2)
    free = (1 - wall).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(free, connectivity=4)
    outside = set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])
    # rooms: the piece under each label (labels are text = wall pixels: the biggest piece near the label point)
    claimed, rooms = {}, {}
    for r in seed["rooms"]:
        nm = OV.get("rename", {}).get(r["name"], r["name"])
        if nm in OV.get("drop", []): continue
        x, y = int(r["at"][0]), int(r["at"][1])
        best = None
        for rad in (6, 14, 24, 36, 50):
            ys, xs = slice(max(0, y - rad), y + rad), slice(max(0, x - rad), x + rad)
            ids, cnt = np.unique(lab[ys, xs], return_counts=True)
            cand = [(st[i, 4], i) for i in ids if i not in outside and i != 0 and st[i, 4] > 60]
            if cand: best = max(cand)[1]; break
        if best is None: continue
        m = (lab == best).astype(np.uint8)
        # a room cut up by its furniture: take in the pieces lying inside its closed outline
        k = max(9, int(math.sqrt(st[best, 4]) * 0.18) | 1)
        closed = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (k, k)))
        cs, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        fill = np.zeros_like(m); cv2.drawContours(fill, cs, -1, 1, -1)
        for i in np.unique(lab[fill > 0]):
            if i != 0 and i not in outside and (lab[fill > 0] == i).sum() > 0.85 * st[i, 4]: claimed[i] = nm
        rooms[nm] = (fill, best)
    # the clean shapes
    R = {}
    for nm, (fill, best) in rooms.items():
        if nm in OV.get("shapes", {}):
            spec = OV["shapes"][nm]
            R[nm] = Point(*spec["circle"][:2]).buffer(spec["circle"][2], 64) if "circle" in spec else Polygon(spec["poly"])
        else:
            p = snap_poly(fill)
            if p is not None: R[nm] = p
    # doors: one per green square
    gn, glab, gst, gcen = cv2.connectedComponentsWithStats(green, connectivity=8)
    doors = []
    for i in range(1, gn):
        if gst[i, 4] < 12: continue
        cx, cy = gcen[i]
        if cx > AX + 1: continue                                  # (the right half comes from the mirror)
        def free_at(px, py):
            px, py = int(px), int(py)
            return 0 <= px < W and 0 <= py < H and free[py, px] and lab[py, px] not in outside
        lr = sum(free_at(cx + s * d, cy) for s in (-1, 1) for d in (9, 12, 15))
        ud = sum(free_at(cx, cy + s * d) for s in (-1, 1) for d in (9, 12, 15))
        doors.append([round(cx, 1), round(cy, 1), "v" if lr >= ud else "h"])
    doors += [d for d in OV.get("add_doors", [])]
    # hallways: unlabelled pieces a door touches (left half + centre), cleaned
    halls = []
    touched = set()
    for x, y, o in doors:
        for dx, dy in ((-12, 0), (12, 0), (0, -12), (0, 12), (-16, 0), (16, 0), (0, -16), (0, 16)):
            px, py = int(x + dx), int(y + dy)
            if 0 <= px < W and 0 <= py < H: touched.add(lab[py, px])
    for i in touched:
        if i == 0 or i in outside or i in claimed or st[i, 4] < 120: continue
        if st[i, 0] > AX + 2: continue
        m = (lab == i).astype(np.uint8)
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        for kern in ((1, 21), (21, 1)):   # the straight runs of the piece: each run's box is a clean hallway piece
            run = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones(kern, np.uint8))
            k2, l2, s2, _ = cv2.connectedComponentsWithStats(run, connectivity=4)
            for j in range(1, k2):
                x, y, w, h, a = s2[j]
                if a < 0.6 * w * h or a < 100: continue
                if kern[1] == 21 and h > 34: continue          # (a wide blob, not a hall run)
                if kern[0] == 21 and w > 34: continue
                halls.append(box(x, y, x + w, y + h))
    for spec in OV.get("add_halls", []):
        halls.append(LineString(spec["line"]).buffer(spec.get("w", 20) / 2, cap_style=2, join_style=2))
    # mirror: keep the left half (and the centre), mirror it
    Mf = lambda gg: affinity.scale(gg, -1, 1, origin=(AX, 0))
    left = box(0, 0, AX, H)
    def sym(gg):
        lh = gg.intersection(left)
        if lh.is_empty: return Mf(gg)
        return unary_union([lh, Mf(lh)]).buffer(0)
    R2 = {}
    for nm, p in R.items():
        c = p.centroid
        if abs(c.x - AX) < 6: R2[nm] = sym(p)                        # centre-line room: made symmetric
        elif c.x < AX: R2[nm] = p
    for nm, p in list(R2.items()):                                     # each left room's twin on the right
        if p.centroid.x < AX - 6:
            twin = [k for k, q in R.items() if q.centroid.x > AX + 6 and Mf(p).centroid.distance(q.centroid) < 40]
            R2[twin[0] if twin else nm + " (starboard)"] = Mf(p)
    HL = [sym(h) if h.bounds[2] > AX - 4 else h for h in halls]
    HL += [Mf(h) for h in HL if h.bounds[2] < AX - 4]
    DO = [d for d in doors] + [[round(2 * AX - d[0], 1), d[1], d[2]] for d in doors if abs(d[0] - AX) > 2]
    for nm in OV.get("drop_after", []): R2.pop(nm, None)
    return dict(sid=sid, src=src_path, W=W, H=H, AX=AX, asym=asym, R=R2, HALLS=HL, DOORS=DO, folder=folder, eng=eng, start=seed.get("start"))

def door_box(x, y, o, depth):
    return box(x - DOOR / 2, y - depth, x + DOOR / 2, y + depth) if o == "h" else box(x - depth, y - DOOR / 2, x + depth, y + DOOR / 2)

def build(P):
    R, HALLS, DOORS = P["R"], P["HALLS"], P["DOORS"]
    floor = unary_union(list(R.values()) + HALLS + [door_box(x, y, o, T * 2.6) for x, y, o in DOORS]).buffer(0.5).buffer(-0.5)
    halls = unary_union(HALLS) if HALLS else Polygon()
    rings = [g.exterior.buffer(T / 2, join_style=2) for g in R.values()]
    for p in getattr(halls, "geoms", [halls]):
        if p.is_empty: continue
        rings.append(p.exterior.buffer(T / 2, join_style=2)); rings += [r.buffer(T / 2, join_style=2) for r in p.interiors]
    walls = unary_union(rings).difference(unary_union([door_box(x, y, o, T * 2.6) for x, y, o in DOORS]))
    walls = walls.intersection(floor.buffer(T / 2, join_style=2))
    walls = unary_union([p for p in getattr(walls, "geoms", [walls]) if p.area > 8])
    return floor, walls

def raster(gg, shape):
    out = np.zeros(shape, np.uint8)
    for p in getattr(gg, "geoms", [gg]):
        if p.is_empty: continue
        m1 = np.zeros(shape, np.uint8); cv2.fillPoly(m1, [np.array(p.exterior.coords, np.int32)], 1)
        for r in p.interiors: cv2.fillPoly(m1, [np.array(r.coords, np.int32)], 0)
        out |= m1
    return out

def reach(P, floor, walls, start):
    shape = (P["H"], P["W"])
    m = np.zeros(shape, np.uint8); m[raster(floor, shape) > 0] = 1; m[raster(walls, shape) > 0] = 0
    n, lab = cv2.connectedComponents(m, connectivity=4)
    s = lab[int(start[1]), int(start[0])]
    return {k: bool(s != 0 and lab[int(g.representative_point().y), int(g.representative_point().x)] == s) for k, g in P["R"].items()}

def draw(P, floor, walls, entry=None):
    src = cv2.imread(P["src"])
    plan = np.zeros_like(src); ov = (src * 0.4).astype(np.uint8)
    for im in (plan, ov):
        m = raster(walls, src.shape[:2]); im[m > 0] = (255, 255, 255)
    for k, g in P["R"].items():
        c = g.representative_point(); t = k.upper()[:22]
        (w, h), _ = cv2.getTextSize(t, cv2.FONT_HERSHEY_SIMPLEX, 0.32, 1)
        cv2.putText(plan, t, (int(c.x - w / 2), int(c.y + h / 2)), cv2.FONT_HERSHEY_SIMPLEX, 0.32, (255, 220, 120), 1, cv2.LINE_AA)
    cv2.imwrite(os.path.join(P["eng"], "plan.png"), plan)
    cv2.imwrite(os.path.join(P["eng"], "plan_on_map.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 85])

if __name__ == "__main__":
    sid = sys.argv[1]
    P = main(sid)
    floor, walls = build(P)
    OV = json.load(open(os.path.join(P["eng"], "overrides.json"))) if os.path.exists(os.path.join(P["eng"], "overrides.json")) else {}
    start = OV.get("start") or P["R"].get(OV.get("entry", ""), Polygon([(0, 0), (1, 0), (1, 1)])).representative_point().coords[0]
    rc = reach(P, floor, walls, start)
    draw(P, floor, walls)
    bad = [k for k, v in rc.items() if not v]
    json.dump({"ship": sid, "units": "source px", "px_per_m": 10.0, "thickness": T, "door": DOOR, "mirror_x": P["AX"], "center_y": P["H"] / 2.0,
               "start": list(start), "rooms": {k: mapping(g) for k, g in P["R"].items()}, "halls": [mapping(h) for h in P["HALLS"]],
               "doors": P["DOORS"], "proposed_doors": OV.get("add_doors", []), "floor": mapping(floor), "walls": mapping(walls)},
              open(os.path.join(P["eng"], "plan.json"), "w"))
    rep = {"rooms": len(P["R"]), "halls": len(P["HALLS"]), "doors": len(P["DOORS"]), "mirror_x": P["AX"], "mirror_err": round(P["asym"], 1), "unreachable": bad}
    json.dump(rep, open(os.path.join(P["eng"], "auto_report.json"), "w"), indent=1)
    print(sid, rep)
