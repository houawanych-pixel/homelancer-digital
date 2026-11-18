#!/usr/bin/env python3
"""Zoom-in trace of the Station Maintenance map (Alien: Isolation, owner's screenshot 17 Nov 2026).
The whole map is scaled up x4 and traced at that size, so every notch, door jamb and angled corner of the outline is followed
at 4x the detail. Floor = everything closed in by the cyan / green outline (dashes and icons sitting on the outline are closed
over). Thin long wall bars inside a floor (the slots in the big block) are kept as inner walls (holes). Outlines are straightened
(approxPolyDP 2 px at 4x = 0.5 map px), edges within 5 deg of 0 / 90 snapped, repeated tiny steps kept.
Output: zoom/piece_NN.png (each piece, white trace on the dimmed map), zoom_sheet.jpg, zoom_trace.png (white on black, full map),
zoom_overlay.jpg, zoom_pieces.json (polygons in crop px of the map, holes included)."""
import json, math, os
import cv2, numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
Z = 4
CLOSE = int(os.environ.get("CLOSE", 13))       # map px: gaps in the outline (dashes, doors under icons) closed up to this
Y0, Y1, X0, X1 = 142, 1660, 100, 1815                      # inside the map frame
BLANK = [(770, 395, 945, 432), (550, 1045, 730, 1080), (705, 750, 980, 790), (1290, 1440, 1715, 1518)]   # deck names, terminal name, logo
src = cv2.imread(os.path.join(HERE, "source.png"))[Y0:Y1, X0:X1]
big = cv2.resize(src, None, fx=Z, fy=Z, interpolation=cv2.INTER_CUBIC)
a = big.astype(int); g, r = a[..., 1], a[..., 2]
line = ((g > 60) & (g > r + 15) & (a.max(2) < 200)).astype(np.uint8) * 255
icons = cv2.morphologyEx((a.max(2) > 95).astype(np.uint8) * 255, cv2.MORPH_OPEN, np.ones((3 * Z, 3 * Z), np.uint8))
bar = cv2.bitwise_or(line, icons)
for x0, y0, x1, y1 in BLANK: bar[y0 * Z:y1 * Z, x0 * Z:x1 * Z] = 0
k = lambda n: cv2.getStructuringElement(cv2.MORPH_RECT, (n, n))
bar = cv2.morphologyEx(bar, cv2.MORPH_CLOSE, k(CLOSE * Z + 1))
ox0, oy0, ox1, oy1 = 1250, 305, 1345, 400                  # Maintenance Office: dashed and faint, close harder
sub = line[oy0 * Z:oy1 * Z, ox0 * Z:ox1 * Z]
bar[oy0 * Z:oy1 * Z, ox0 * Z:ox1 * Z] |= cv2.morphologyEx(sub, cv2.MORPH_CLOSE, k(31 * Z + 1))
ff = bar.copy(); mk = np.zeros((ff.shape[0] + 2, ff.shape[1] + 2), np.uint8); cv2.floodFill(ff, mk, (0, 0), 128)
floor = (ff != 128).astype(np.uint8) * 255
floor = cv2.morphologyEx(floor, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9 * Z, 9 * Z)))   # leader lines go
# icons sitting ACROSS a hall (lock pads, lifts) are doors, not walls: an icon box touching two separate floor pieces becomes floor
DOORS, HALLS = [], []
nf, flab = cv2.connectedComponents(floor)
ybox = ((a[..., 2] > 120) & (a[..., 1] > 110) & (a[..., 0] < 100)).astype(np.uint8) * 255      # yellow icon frames
ni, ilab, ist, _ = cv2.connectedComponentsWithStats(cv2.dilate(ybox, np.ones((2 * Z, 2 * Z), np.uint8)))
for i in range(1, ni):
    x, y, w, h = ist[i, :4]
    if w > 30 * Z or h > 30 * Z or w < 12 * Z or h < 12 * Z: continue   # not an icon box
    R = 14 * Z; ya, xa = max(0, y - R), max(0, x - R)
    ring = cv2.dilate((ilab[ya:y + h + R, xa:x + w + R] == i).astype(np.uint8), np.ones((R, R), np.uint8))
    touch = set(np.unique(flab[ya:y + h + R, xa:x + w + R][ring > 0])) - {0}
    if len(touch) >= 2:
        floor[y - Z:y + h + Z, x - Z:x + w + Z] = 255; HALLS.append((x, y, w, h)); DOORS.append([round((x + w / 2) / Z, 1), round((y + h / 2) / Z, 1)])
floor = cv2.morphologyEx(floor, cv2.MORPH_CLOSE, k(5 * Z + 1))
for x, y, w, h in HALLS:
    R = 16 * Z; ya, xa = max(0, y - R), max(0, x - R)
    floor[ya:y + h + R, xa:x + w + R] = cv2.morphologyEx(floor[ya:y + h + R, xa:x + w + R], cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13 * Z, 13 * Z)))                  # pieces split by a hairline (a door line) join up
# inner walls: long thin line bars well inside a floor
inner = line & cv2.erode(floor, np.ones((4 * Z, 4 * Z), np.uint8))
inner = cv2.morphologyEx(inner, cv2.MORPH_CLOSE, k(2 * Z + 1))
nb, lab, st, _ = cv2.connectedComponentsWithStats(inner); keep = np.zeros_like(inner)
for i in range(1, nb):
    w, h = st[i, cv2.CC_STAT_WIDTH], st[i, cv2.CC_STAT_HEIGHT]
    if not (max(w, h) > 25 * Z and max(w, h) > 4 * min(w, h)): continue
    # keep it as an inner wall only if it doesn't cut the floor in two (a wall across a hall is the hall's own edge)
    x, y = st[i, 0], st[i, 1]; P = 30 * Z
    ya, yb, xa, xb = max(0, y - P), y + h + P, max(0, x - P), x + w + P
    loc = floor[ya:yb, xa:xb].copy(); bar_i = cv2.dilate((lab[ya:yb, xa:xb] == i).astype(np.uint8) * 255, np.ones((Z, Z), np.uint8))
    before = cv2.connectedComponents(loc)[0]; after = cv2.connectedComponents(loc & ~bar_i)[0]
    if after <= before: keep[lab == i] = 255
floor &= ~cv2.dilate(keep, np.ones((Z, Z), np.uint8))

def snap(p):
    p = p.reshape(-1, 2).astype(float); n = len(p)
    for _ in range(2):
        for i in range(n):
            j = (i + 1) % n; d = p[j] - p[i]
            if np.hypot(*d) < 4 * Z: continue
            ang = math.degrees(math.atan2(d[1], d[0])) % 90
            if min(ang, 90 - ang) < 5:
                if abs(d[0]) > abs(d[1]): p[j, 1] = p[i, 1]
                else: p[j, 0] = p[i, 0]
    return p

nb, lab, st, _ = cv2.connectedComponentsWithStats(floor)
order = sorted([i for i in range(1, nb) if st[i, cv2.CC_STAT_AREA] > 900 * Z * Z], key=lambda i: (st[i, 1] // (200 * Z), st[i, 0]))
plan = np.zeros_like(big); ov = (big * 0.45).astype(np.uint8); out, tiles = [], []
os.makedirs(os.path.join(HERE, "zoom"), exist_ok=True)
for n, i in enumerate(order):
    m = (lab == i).astype(np.uint8) * 255
    cs, hier = cv2.findContours(m, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE); rings = []
    for j, c in enumerate(cs):
        hole = hier[0][j][3] >= 0
        if hole and cv2.contourArea(c) < 40 * Z * Z: continue
        s = snap(cv2.approxPolyDP(c, 2.0, True)).astype(np.int32)
        for im in (plan, ov): cv2.polylines(im, [s], True, (255, 255, 255), Z, cv2.LINE_AA)
        rings.append({"hole": bool(hole), "pts": (s / Z).round(2).tolist()})
    x, y, w, h = st[i, 0], st[i, 1], st[i, 2], st[i, 3]; P = 20 * Z
    tile = ov[max(0, y - P):y + h + P, max(0, x - P):x + w + P].copy()
    cv2.putText(tile, "#%d" % (n + 1), (10 * Z, 14 * Z), cv2.FONT_HERSHEY_SIMPLEX, 0.9 * Z / 2, (60, 210, 255), Z, cv2.LINE_AA)
    cv2.imwrite(os.path.join(HERE, "zoom", "piece_%02d.png" % (n + 1)), tile)
    out.append({"piece": n + 1, "rings": rings}); tiles.append(tile)

T = 700; rows = []
for i in range(0, len(tiles), 3):
    row = []
    for t in tiles[i:i + 3]:
        s = min(T / t.shape[1], T / t.shape[0]); t = cv2.resize(t, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
        c = np.zeros((T, T, 3), np.uint8); c[:t.shape[0], :t.shape[1]] = t; cv2.rectangle(c, (0, 0), (T - 1, T - 1), (70, 70, 70), 2); row.append(c)
    while len(row) < 3: row.append(np.zeros((T, T, 3), np.uint8))
    rows.append(np.hstack(row))
cv2.imwrite(os.path.join(HERE, "zoom_sheet.jpg"), np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 86])
cv2.imwrite(os.path.join(HERE, "zoom_trace.png"), cv2.resize(plan, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA))
cv2.imwrite(os.path.join(HERE, "zoom_overlay.jpg"), cv2.resize(ov, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 86])
json.dump({"crop": [Y0, Y1, X0, X1], "units": "crop px of the map", "zoom": Z, "pieces": out, "icon_doors": DOORS}, open(os.path.join(HERE, "zoom_pieces.json"), "w"))
print(len(DOORS), "icon doors opened;", len(out), "pieces;", sum(1 for o in out for q in o["rings"] if q["hole"]), "inner walls / holes")
