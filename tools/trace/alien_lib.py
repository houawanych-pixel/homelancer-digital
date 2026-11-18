#!/usr/bin/env python3
"""alien_lib.py MAPDIR [MAPDIR ...] [--hall 0 = auto] [--min-room 1400]
Room library pieces from an Alien: Isolation zoom trace (alien_zoom.py output, zoom_pieces.json). Owner, Nov 18 2026:
"build out the room library ... store the silhouette of the rooms, the shapes where the doors go".

For each map:
 1. the traced floor (outline rings minus holes = courts and inner wall bars) is drawn at 4x
 2. ROOMS = the wide parts: what survives an erosion by half the widest hall (--hall map px), grown back inside the
    floor; HALLS = the narrow rest. Small wide bits (< --min-room map px^2) stay hall.
 3. DOORS = where a hall meets a room (and where two rooms meet with no wall between): each contact becomes ONE flat
    face on the room's outline (a straight connector across the hall), stored as a door with its width and the
    direction out of the room
 4. every outline is straightened: approxPolyDP 2 map px, edges within 8 deg of a multiple of 45 deg snapped and their
    corners re-intersected (cut corners stay cut, curves stay curves)
Output in MAPDIR/lib/: pieces.json (every room / hall: polygon in map px of the crop, area, bbox, doors),
lib_sheet.jpg (each room alone, zoomed: blue line, yellow door faces), lib_overlay.jpg (rooms blue, halls cyan,
doors yellow, on the dimmed map), lib_rooms.png (white on black). Sizes stay in map px until the owner gives a scale."""
import argparse, json, math, os
import cv2, numpy as np
from shapely.geometry import Polygon

Z = 4
ap = argparse.ArgumentParser(); ap.add_argument("maps", nargs="+"); ap.add_argument("--hall", type=float, default=0.0)
ap.add_argument("--min-room", type=float, default=1400.0)
A = ap.parse_args()
BLUE, CYAN, YEL = (255, 150, 30), (230, 220, 90), (40, 220, 255)

def floor_mask(d, H, W):
    m = np.zeros((H * Z, W * Z), np.uint8)
    for p in d["pieces"]:
        for r in p["rings"]:
            pts = (np.array(r["pts"]) * Z).astype(np.int32)
            if not r["hole"]: cv2.fillPoly(m, [pts], 255)
        for r in p["rings"]:
            pts = (np.array(r["pts"]) * Z).astype(np.int32)
            if r["hole"]: cv2.fillPoly(m, [pts], 0)
    return m

def snap_poly(pts, keep_flat=None):
    """Straighten one ring (map px): edges near a multiple of 45 deg are snapped and their corners re-intersected."""
    n = len(pts)
    if n < 4: return pts
    ang, ok = [], []
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        dx, dy = b[0] - a[0], b[1] - a[1]; L = math.hypot(dx, dy)
        t = math.degrees(math.atan2(dy, dx)); s = round(t / 45.0) * 45.0
        good = L >= 5.0 and abs(t - s) < 8.0
        ang.append(math.radians(s) if good else math.radians(t)); ok.append(good)
    out = []
    for i in range(n):
        j = (i - 1) % n   # edge j ends at vertex i, edge i starts there
        if ok[i] and ok[j]:
            if abs(math.sin(ang[i] - ang[j])) < 1e-6: continue   # two edges on one line: drop the vertex between
            # line j through its midpoint, line i through its midpoint
            pa, pb = pts[j], pts[i]; qa, qb = pts[i], pts[(i + 1) % n]
            m1 = ((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2); m2 = ((qa[0] + qb[0]) / 2, (qa[1] + qb[1]) / 2)
            d1 = (math.cos(ang[j]), math.sin(ang[j])); d2 = (math.cos(ang[i]), math.sin(ang[i]))
            den = d1[0] * d2[1] - d1[1] * d2[0]
            t1 = ((m2[0] - m1[0]) * d2[1] - (m2[1] - m1[1]) * d2[0]) / den
            x, y = m1[0] + d1[0] * t1, m1[1] + d1[1] * t1
            if math.hypot(x - pts[i][0], y - pts[i][1]) < 6.0: out.append((x, y)); continue
        out.append(tuple(pts[i]))
    # drop edges shorter than 1 px
    clean = [out[0]]
    for p in out[1:]:
        if math.hypot(p[0] - clean[-1][0], p[1] - clean[-1][1]) >= 1.0: clean.append(p)
    return clean

def region_rings(mask, flat=None):
    """Outer ring + hole rings of a region mask (at Z), straightened, in map px. `flat` = pixels on a door face:
    runs of outline points on it collapse to their two ends, so the face is one straight edge."""
    cs, hier = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    rings = []
    if hier is None: return rings
    for k, c in enumerate(cs):
        if cv2.contourArea(c) < 40 * Z * Z: continue
        hole = hier[0][k][3] >= 0
        c2 = c.reshape(-1, 2)
        if flat is not None:
            on = flat[np.clip(c2[:, 1], 0, flat.shape[0] - 1), np.clip(c2[:, 0], 0, flat.shape[1] - 1)] > 0
            keep = [i for i in range(len(c2)) if not on[i] or not on[i - 1] or not on[(i + 1) % len(c2)]]
            c2 = c2[keep]
        ap_ = cv2.approxPolyDP(c2.reshape(-1, 1, 2).astype(np.float32), 2.0 * Z, True).reshape(-1, 2) / Z
        pts = snap_poly([tuple(map(float, p)) for p in ap_])
        if len(pts) >= 3: rings.append({"hole": bool(hole), "pts": [[round(x, 2), round(y, 2)] for x, y in pts]})
    return rings

BARRIER = None; DOOR_MAX = 1e9
def contact_doors(lab, rid, other, H, W):
    """Door faces of room `rid`: its pixels touching `other` (hall or room label set), one per touching blob.
    Where the touch runs along an inner wall line of the map it is a WALL, not a door - unless it is only as long as a
    doorway (a short line drawn across a gap between two jambs: the map's own door mark)."""
    me = (lab == rid).astype(np.uint8)
    edge = me & (1 - cv2.erode(me, np.ones((3, 3), np.uint8)))      # my own outline pixels
    doors = []
    for oid in other:
        touch = (edge > 0) & (cv2.dilate((lab == oid).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0)
        if touch.sum() < 3 * Z: continue
        if BARRIER is not None:
            wl = touch & (BARRIER > 0)
            if wl.any():   # wall-line contacts: keep only doorway-length ones
                nw, cw = cv2.connectedComponents(cv2.dilate(wl.astype(np.uint8), np.ones((5, 5), np.uint8)))
                for kk in range(1, nw):
                    seg = (cw == kk) & wl; yy, xx = np.nonzero(seg)
                    if len(xx) and max(xx.max() - xx.min(), yy.max() - yy.min()) / Z > DOOR_MAX: touch[seg] = False
        n, cl = cv2.connectedComponents(cv2.dilate(touch.astype(np.uint8), np.ones((5, 5), np.uint8)))
        for k in range(1, n):
            ys, xs = np.nonzero((cl == k) & touch)
            if len(xs) < 3 * Z: continue
            P0 = np.stack([xs, ys], 1).astype(float); c0 = P0.mean(0); _, _, vt0 = np.linalg.svd(P0 - c0)
            tt = (P0 - c0) @ vt0[0]
            if (tt.max() - tt.min()) / Z < 6.0: continue   # (a touch narrower than a doorway is not a door)
            P = np.stack([xs, ys], 1).astype(float)
            c = P.mean(0); u, s, vt = np.linalg.svd(P - c); d = vt[0]
            t = (P - c) @ d
            p0, p1 = c + d * t.min(), c + d * t.max()
            # direction out of the room: from my pixels' centre side across the face
            nrm = np.array([-d[1], d[0]])
            my = np.stack(np.nonzero(me)[::-1], 1).astype(float)
            near = my[np.hypot(*(my - c).T) < 12 * Z]
            if len(near) and (near.mean(0) - c) @ nrm > 0: nrm = -nrm
            doors.append({"to": int(oid), "a": [round(p0[0] / Z, 2), round(p0[1] / Z, 2)], "b": [round(p1[0] / Z, 2), round(p1[1] / Z, 2)],
                          "width": round(float(t.max() - t.min()) / Z, 2), "out": [round(float(nrm[0]), 3), round(float(nrm[1]), 3)],
                          "px": np.stack([xs, ys], 1)})
    return doors

for mdir in A.maps:
    d = json.load(open(os.path.join(mdir, "zoom_pieces.json")))
    y0, y1, x0, x1 = d["crop"]; H, W = y1 - y0, x1 - x0
    src = cv2.imread(os.path.join(mdir, "source.png"))[y0:y1, x0:x1]
    fl = floor_mask(d, H, W)
    hall_px = A.hall
    if hall_px <= 0:   # auto: the map's most common corridor width (peak of the floor's centre-line widths); maps differ in zoom
        dt0 = cv2.distanceTransform(fl, cv2.DIST_L2, 5); mx0 = cv2.dilate(dt0, np.ones((5, 5), np.uint8))
        w0 = 2 * dt0[(dt0 >= mx0 - 0.01) & (dt0 > 2 * Z)] / Z
        hh, ee = np.histogram(w0, bins=np.arange(4, 80, 2)); hall_px = float(ee[hh.argmax()])
    r = int(hall_px * Z / 2) + Z
    # INNER WALLS: the map's own thin teal lines inside the floor (room-to-room walls) are barriers
    bigsrc = cv2.resize(src, (fl.shape[1], fl.shape[0]), interpolation=cv2.INTER_CUBIC).astype(np.int16)
    bb, gg, rr = bigsrc[..., 0], bigsrc[..., 1], bigsrc[..., 2]
    line = ((gg > 70) & (bb > 65) & (gg > rr + 25) & (bb > rr + 20) & (np.abs(gg - bb) < 70) & (bigsrc.max(2) < 215)).astype(np.uint8)
    inner = cv2.erode(fl, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * 3 * Z + 1, 2 * 3 * Z + 1)))   # not the outline itself
    line &= (inner > 0).astype(np.uint8)
    nl, ll, st, _ = cv2.connectedComponentsWithStats(line)
    keep = np.zeros(nl, np.uint8); keep[1:] = (np.maximum(st[1:, 2], st[1:, 3]) >= 8 * Z)   # real wall runs, not dots or letters
    wallines = keep[ll]
    barrier = cv2.dilate(wallines, np.ones((3, 3), np.uint8))
    BARRIER, DOOR_MAX = barrier, hall_px * 1.25
    fl2 = (fl > 0) & (barrier == 0)
    ncc, cc = cv2.connectedComponents(fl2.astype(np.uint8))
    core = cv2.erode(fl2.astype(np.uint8) * 255, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1)))
    n, cl = cv2.connectedComponents(core)
    lab = np.zeros(fl.shape, np.int32)   # 1..: rooms, 1000+: halls
    # grow each core back inside the floor (by the same radius, nearest core wins)
    if n > 1:
        dist, idx = cv2.distanceTransformWithLabels((core == 0).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
        ys, xs = np.nonzero(core); seedlab = np.zeros(idx.max() + 1, np.int32)
        seedlab[idx[ys, xs]] = cl[ys, xs]
        grown = seedlab[idx]; grown[(dist > r + 2) | (~fl2)] = 0
        # a core only grows inside its own walled space
        cc_of = np.zeros(n, np.int32); cc_of[cl[ys, xs]] = cc[ys, xs]
        grown[(grown > 0) & (cc_of[grown] != cc)] = 0
        rid = 0
        for k in range(1, n):
            m = grown == k
            if m.sum() / (Z * Z) < A.min_room: continue
            rid += 1; lab[m] = rid
    nroom = lab.max()
    hall = fl2 & (lab == 0)
    nh, hl = cv2.connectedComponents(hall.astype(np.uint8))
    hdt = cv2.distanceTransform(hall.astype(np.uint8), cv2.DIST_L2, 5)
    for k in range(1, nh):
        m = hl == k
        # a real hall: big enough and at least HALL_MIN map px wide somewhere (thin slivers along a room's edge are not)
        if m.sum() / (Z * Z) >= 150 and hdt[m].max() * 2 / Z >= 6.0: lab[m] = 1000 + k
        else:   # a crumb between rooms: give it to the room next to it
            ring = cv2.dilate(m.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
            nb = lab[ring & (lab > 0) & (lab < 1000)]
            if len(nb): lab[m] = np.bincount(nb).argmax()
    # wall-line pixels (and crumbs) go to the nearest piece, so neighbours share one boundary
    if (fl > 0).any():
        free = ((lab == 0) & (fl > 0))
        if free.any():
            d2, i2 = cv2.distanceTransformWithLabels((lab == 0).astype(np.uint8), cv2.DIST_L2, 5, labelType=cv2.DIST_LABEL_PIXEL)
            yl, xl = np.nonzero(lab > 0); lut = np.zeros(i2.max() + 1, np.int32); lut[i2[yl, xl]] = lab[yl, xl]
            lab[free] = lut[i2[free]]
    halls = sorted(set(np.unique(lab)) - {0} - set(range(1, nroom + 1)))
    if os.environ.get("LIBDBG"): np.save(os.environ["LIBDBG"], lab)
    pieces = []
    allid = list(range(1, nroom + 1)) + halls
    # DOOR FACES: every room-hall / room-room contact is redrawn as one straight face, its direction snapped to the
    # nearest 45 deg: floor in a small window round the contact goes to the room on its side, to the other on the far side
    for i in range(1, nroom + 1):
        for dd in contact_doors(lab, i, [o for o in allid if o != i], H, W):
            a = np.array(dd["a"]) * Z; b = np.array(dd["b"]) * Z; c = (a + b) / 2
            t = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0])); sn = round(t / 45.0) * 45.0
            if abs(t - sn) < 25.0: t = sn
            u = np.array([math.cos(math.radians(t)), math.sin(math.radians(t))]); nrm = np.array([-u[1], u[0]])
            if nrm @ np.array(dd["out"]) < 0: nrm = -nrm
            half = np.hypot(*(b - a)) / 2 + 3 * Z; depth = 7 * Z
            xa, xb = int(max(0, c[0] - half - depth)), int(min(fl.shape[1], c[0] + half + depth + 1))
            ya, yb = int(max(0, c[1] - half - depth)), int(min(fl.shape[0], c[1] + half + depth + 1))
            yy, xx = np.mgrid[ya:yb, xa:xb]
            tt = (xx - c[0]) * u[0] + (yy - c[1]) * u[1]; ss = (xx - c[0]) * nrm[0] + (yy - c[1]) * nrm[1]
            win = (np.abs(tt) <= half) & (np.abs(ss) <= depth)
            sub = lab[ya:yb, xa:xb]
            other = 1000 + int(dd["to"]) - 1000 if dd["to"] >= 1000 else int(dd["to"])
            pair = win & ((sub == i) | (sub == other))
            sub[pair & (ss < 0)] = i; sub[pair & (ss >= 0)] = other
    doors_of = {i: contact_doors(lab, i, [o for o in allid if o != i], H, W) for i in allid}
    for i in allid:
        m = (lab == i).astype(np.uint8) * 255
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))   # no 1 px spurs (double lines)
        rings = region_rings(m)
        if not rings: continue
        outer = [rg for rg in rings if not rg["hole"]]
        P = Polygon(outer[0]["pts"], [rg["pts"] for rg in rings if rg["hole"]]) if outer else None
        kind = "room" if i <= nroom else "hall"
        doors = [{k: v for k, v in dd.items() if k != "px"} for dd in doors_of[i]]
        if P is not None:   # a door must sit on the outline (not on a spur the clean-up removed)
            from shapely.geometry import Point
            doors = [dd for dd in doors if P.exterior.distance(Point((dd["a"][0] + dd["b"][0]) / 2, (dd["a"][1] + dd["b"][1]) / 2)) < 2.5
                     or any(Polygon(h).exterior.distance(Point((dd["a"][0] + dd["b"][0]) / 2, (dd["a"][1] + dd["b"][1]) / 2)) < 2.5 for h in [rg["pts"] for rg in rings if rg["hole"]])]
        for dd in doors: dd["to"] = ("room_%02d" % dd["to"]) if dd["to"] <= nroom else ("hall_%02d" % (dd["to"] - 1000))
        pid = ("room_%02d" % i) if kind == "room" else ("hall_%02d" % (i - 1000))
        pieces.append({"id": pid, "kind": kind, "area": round(P.area, 1) if P else 0, "bbox": [round(v, 1) for v in P.bounds] if P else [],
                       "rings": rings, "doors": doors})
    name = os.path.basename(os.path.normpath(mdir))
    out = os.path.join(mdir, "lib"); os.makedirs(out, exist_ok=True)
    json.dump({"map": name, "source": "source.png", "crop": d["crop"], "units": "map px of the crop", "hall_max_px": hall_px,
               "rooms": sum(p["kind"] == "room" for p in pieces), "halls": sum(p["kind"] == "hall" for p in pieces), "pieces": pieces},
              open(os.path.join(out, "pieces.json"), "w"), indent=0)
    # overlay on the dimmed map, at 2x
    S = 2
    ov = cv2.resize((src * 0.35).astype(np.uint8), None, fx=S, fy=S, interpolation=cv2.INTER_CUBIC)
    wb = np.zeros((H * S, W * S, 3), np.uint8)
    for p in pieces:
        col = BLUE if p["kind"] == "room" else CYAN
        for rg in p["rings"]:
            pts = (np.array(rg["pts"]) * S).astype(np.int32)
            cv2.polylines(ov, [pts], True, col, 2, cv2.LINE_AA)
            if p["kind"] == "room": cv2.polylines(wb, [pts], True, (255, 255, 255), 2, cv2.LINE_AA)
        for dd in p["doors"]:
            a = (np.array(dd["a"]) * S).astype(int); b = (np.array(dd["b"]) * S).astype(int)
            cv2.line(ov, tuple(a), tuple(b), YEL, 3, cv2.LINE_AA)
            if p["kind"] == "room": cv2.line(wb, tuple(a), tuple(b), YEL, 3, cv2.LINE_AA)
        if p["kind"] == "room" and p["bbox"]:
            cx, cy = (p["bbox"][0] + p["bbox"][2]) / 2 * S, (p["bbox"][1] + p["bbox"][3]) / 2 * S
            for img in (ov, wb): cv2.putText(img, p["id"][5:], (int(cx) - 12, int(cy) + 8), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
    cv2.imwrite(os.path.join(out, "lib_overlay.jpg"), ov, [cv2.IMWRITE_JPEG_QUALITY, 88])
    cv2.imwrite(os.path.join(out, "lib_rooms.png"), wb)
    # sheet: each room alone, scaled to a 300 px tile
    rooms = [p for p in pieces if p["kind"] == "room"]
    T, cols = 300, 6
    rows_ = max(1, math.ceil(len(rooms) / cols))
    sheet = np.zeros((rows_ * T, cols * T, 3), np.uint8)
    for k, p in enumerate(rooms):
        bx0, by0, bx1, by1 = p["bbox"]; sc = (T - 50) / max(bx1 - bx0, by1 - by0, 1)
        ox, oy = (k % cols) * T + (T - (bx1 - bx0) * sc) / 2, (k // cols) * T + 30 + (T - 40 - (by1 - by0) * sc) / 2
        def tf(q): return (int(ox + (q[0] - bx0) * sc), int(oy + (q[1] - by0) * sc))
        for rg in p["rings"]:
            cv2.polylines(sheet, [np.array([tf(q) for q in rg["pts"]], np.int32)], True, BLUE, 2, cv2.LINE_AA)
        for dd in p["doors"]: cv2.line(sheet, tf(dd["a"]), tf(dd["b"]), YEL, 4, cv2.LINE_AA)
        cv2.putText(sheet, "%s  %dx%d px  %d door%s" % (p["id"], bx1 - bx0, by1 - by0, len(p["doors"]), "" if len(p["doors"]) == 1 else "s"),
                    ((k % cols) * T + 8, (k // cols) * T + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1, cv2.LINE_AA)
    cv2.imwrite(os.path.join(out, "lib_sheet.jpg"), sheet, [cv2.IMWRITE_JPEG_QUALITY, 90])
    print(name, "hall", hall_px, "rooms", len(rooms), "halls", len(pieces) - len(rooms), "doors", sum(len(p["doors"]) for p in rooms))
