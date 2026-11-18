#!/usr/bin/env python3
"""alien_zoom.py IMAGE OUTDIR [--close 13]
Zoom-in trace for Alien: Isolation style area maps (grid background, thin cyan / green floor outlines, yellow / green / red icon
boxes, white labels, a legend under the frame). Generalised from alien_maint_10/zoom_trace.py (owner-approved 17 Nov 2026).

Steps (all at 4x, so every notch, door jamb and angled corner is followed):
 1. find the map frame (the long grey rectangle) and work inside it
 2. outline = cyan / green pixels; letters of the cyan labels (small compact blobs) are dropped
 3. icon boxes count as wall only next to an outline (a lift / lock pad on a hall edge); white labels and the title don't
 4. close gaps up to --close map px (dashed 'underneath floor' outlines, doors under icons), flood the outside, the rest is floor
 5. thin slivers (leader lines) opened away; an icon box touching two floor pieces is a door and is opened
 6. long thin wall bars inside a floor become inner walls (holes) unless they would cut the floor in two
 7. outlines straightened (approxPolyDP 0.5 map px), edges within 5 deg of 0 / 90 snapped
Output in OUTDIR: source.png (copy), zoom_overlay.jpg (white trace on the dimmed map), zoom_trace.png (white on black),
zoom_sheet.jpg (every piece zoomed), zoom/piece_NN.png, zoom_pieces.json (polygons in map px of the crop, holes, icon doors)."""
import argparse, json, math, os, shutil
import cv2, numpy as np

ap = argparse.ArgumentParser(); ap.add_argument("image"); ap.add_argument("out"); ap.add_argument("--close", type=int, default=13); ap.add_argument("--grid", action="store_true")
A = ap.parse_args(); os.makedirs(os.path.join(A.out, "zoom"), exist_ok=True)
Z = 4
BLUE, BLUE2 = (255, 150, 30), (255, 190, 90)        # owner: trace lines in blue, not white (BGR)
full = cv2.imread(A.image)
if os.path.abspath(A.image) != os.path.abspath(os.path.join(A.out, "source.png")): cv2.imwrite(os.path.join(A.out, "source.png"), full)

# 1. map frame: rows / columns that are mostly light grey
grey = ((full.max(2) > 70) & (full.max(2).astype(int) - full.min(2) < 40)).astype(np.uint8)
H0, W0 = grey.shape
rows = np.where(grey.sum(1) > 0.5 * W0)[0]; cols = np.where(grey.sum(0) > 0.4 * H0)[0]
Y0, Y1 = (rows.min() + 4, rows.max() - 3) if len(rows) >= 2 else (0, H0)
X0, X1 = (cols.min() + 4, cols.max() - 3) if len(cols) >= 2 else (0, W0)
src = full[Y0:Y1, X0:X1]
# the zoom buttons (+ / -) sit inside the frame at the top right: blank that corner
zb = src.copy(); zb[:int(0.25 * src.shape[0]), int(0.94 * src.shape[1]):] = src[5:6, 5:6]
src = zb
big = cv2.resize(src, None, fx=Z, fy=Z, interpolation=cv2.INTER_CUBIC)
a = big.astype(np.int16); b, g, r = a[..., 0], a[..., 1], a[..., 2]; mx = a.max(2)

# 2. outline pixels, minus label letters
line = ((g > 60) & (g > r + 15) & (mx < 200)).astype(np.uint8) * 255
n, lab, st, _ = cv2.connectedComponentsWithStats(cv2.resize(line, None, fx=1 / Z, fy=1 / Z, interpolation=cv2.INTER_NEAREST))
small = np.zeros(n, bool)
for i in range(1, n):
    w, h, ar = st[i, 2], st[i, 3], st[i, 4]
    if max(w, h) <= 26 and min(w, h) >= 5 and ar < 0.6 * w * h: small[i] = True        # a letter, not a dash (dashes are thin)
letters = cv2.resize(small[lab].astype(np.uint8) * 255, (line.shape[1], line.shape[0]), interpolation=cv2.INTER_NEAREST)
line &= ~cv2.dilate(letters, np.ones((Z, Z), np.uint8))

# 3. icons next to an outline
icons = cv2.morphologyEx((mx > 95).astype(np.uint8) * 255, cv2.MORPH_OPEN, np.ones((3 * Z, 3 * Z), np.uint8))
near = cv2.dilate(line, np.ones((6 * Z, 6 * Z), np.uint8))
ni, il, ist, _ = cv2.connectedComponentsWithStats(icons); keep_i = np.zeros(ni, bool)
for i in range(1, ni):
    x, y, w, h = ist[i, :4]
    if w < 30 * Z and h < 30 * Z and near[y:y + h, x:x + w].any(): keep_i[i] = True
icons = (keep_i[il]).astype(np.uint8) * 255
k = lambda s: cv2.getStructuringElement(cv2.MORPH_RECT, (s, s))
bar = cv2.morphologyEx(cv2.bitwise_or(line, icons), cv2.MORPH_CLOSE, k(A.close * Z + 1))

# 4. flood the outside
ff = bar.copy(); mk = np.zeros((ff.shape[0] + 2, ff.shape[1] + 2), np.uint8); cv2.floodFill(ff, mk, (0, 0), 128)
floor = (ff != 128).astype(np.uint8) * 255
floor = cv2.morphologyEx(floor, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9 * Z, 9 * Z)))

# 5. icon boxes across a hall are doors
DOORS, HALLS = [], []
nf, flab = cv2.connectedComponents(floor)
box = (((r > 120) & (g > 110) & (b < 100)) | ((r > 150) & (g < 90)) | ((g > 140) & (r < 110) & (b < 110))).astype(np.uint8) * 255
nb_, bl, bst, _ = cv2.connectedComponentsWithStats(cv2.dilate(box, np.ones((2 * Z, 2 * Z), np.uint8)))
for i in range(1, nb_):
    x, y, w, h = bst[i, :4]
    if w > 30 * Z or h > 30 * Z or w < 12 * Z or h < 12 * Z: continue
    R = 14 * Z; ya, xa = max(0, y - R), max(0, x - R)
    ring = cv2.dilate((bl[ya:y + h + R, xa:x + w + R] == i).astype(np.uint8), np.ones((R, R), np.uint8))
    touch = set(np.unique(flab[ya:y + h + R, xa:x + w + R][ring > 0])) - {0}
    if len(touch) >= 2:
        floor[max(0, y - Z):y + h + Z, max(0, x - Z):x + w + Z] = 255; HALLS.append((x, y, w, h))
        DOORS.append([round((x + w / 2) / Z, 1), round((y + h / 2) / Z, 1)])
floor = cv2.morphologyEx(floor, cv2.MORPH_CLOSE, k(5 * Z + 1))
for x, y, w, h in HALLS:
    R = 16 * Z; ya, xa = max(0, y - R), max(0, x - R)
    floor[ya:y + h + R, xa:x + w + R] = cv2.morphologyEx(floor[ya:y + h + R, xa:x + w + R], cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13 * Z, 13 * Z)))

# 5b. the map grid shows through lighter floors in the outline colour: find the grid lines (dark in the background, every
# column / row that is darker than its neighbours over most of the empty map) and take them out of the inner-line mask
gs = src.mean(2).astype(np.float32)
bgm = cv2.resize(floor, (src.shape[1], src.shape[0]), interpolation=cv2.INTER_NEAREST) == 0
def grid_lines(img, m, axis):
    v = np.where(m, img, np.nan)
    if not m.any(): return np.array([], int)
    nb_ = np.nanmean(np.stack([np.roll(v, d, axis=1 - axis) for d in (-3, -2, 2, 3)]), 0)
    dark = (v < nb_ - 2.5) & m
    frac = dark.sum(axis) / np.maximum(m.sum(axis), 1)
    return np.where(frac > 0.45)[0]
GX, GY = grid_lines(gs, bgm, 0), grid_lines(gs, bgm, 1)
gridm = np.zeros(line.shape, np.uint8)
for x in GX: gridm[:, max(0, x * Z - Z):x * Z + 2 * Z] = 255
for y in GY: gridm[max(0, y * Z - Z):y * Z + 2 * Z, :] = 255
thick = cv2.dilate(cv2.morphologyEx(line, cv2.MORPH_OPEN, np.ones((7, 7), np.uint8)), np.ones((3, 3), np.uint8))   # walls are 2-3 map px wide, grid lines 1
inline = (line & ~gridm if A.grid else line) & thick   # grid removal is off by default: it broke real walls on the grid
# 6. inner walls
inner = inline & cv2.erode(floor, np.ones((4 * Z, 4 * Z), np.uint8))
inner = cv2.morphologyEx(inner, cv2.MORPH_CLOSE, k(2 * Z + 1))
nb, lab, st, _ = cv2.connectedComponentsWithStats(inner); keep = np.zeros_like(inner)
for i in range(1, nb):
    w, h = st[i, 2], st[i, 3]
    if not (max(w, h) > 25 * Z and max(w, h) > 4 * min(w, h)): continue
    x, y = st[i, 0], st[i, 1]; P = 30 * Z
    ya, yb, xa, xb = max(0, y - P), y + h + P, max(0, x - P), x + w + P
    loc = floor[ya:yb, xa:xb].copy(); bi = cv2.dilate((lab[ya:yb, xa:xb] == i).astype(np.uint8) * 255, np.ones((Z, Z), np.uint8))
    if cv2.connectedComponents(loc & ~bi)[0] <= cv2.connectedComponents(loc)[0]: keep[lab == i] = 255
floor &= ~cv2.dilate(keep, np.ones((Z, Z), np.uint8))

# 6b. rooms: every cell closed in by outline lines inside a floor piece (overlapping decks and inner room walls kept)
cells = floor & ~cv2.dilate(cv2.morphologyEx(inline | icons, cv2.MORPH_CLOSE, k(A.close * Z + 1)), np.ones((Z, Z), np.uint8))
cells = cv2.morphologyEx(cells, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5 * Z, 5 * Z)))
nc, clab, cst, _ = cv2.connectedComponentsWithStats(cells)
ROOMS = [i for i in range(1, nc) if cst[i, 4] > 120 * Z * Z]

# 7. straighten and draw
def snap(p):
    p = p.reshape(-1, 2).astype(float); m = len(p)
    for _ in range(2):
        for i in range(m):
            j = (i + 1) % m; d = p[j] - p[i]
            if np.hypot(*d) < 4 * Z: continue
            ang = math.degrees(math.atan2(d[1], d[0])) % 90
            if min(ang, 90 - ang) < 5:
                if abs(d[0]) > abs(d[1]): p[j, 1] = p[i, 1]
                else: p[j, 0] = p[i, 0]
    return p

nb, lab, st, _ = cv2.connectedComponentsWithStats(floor)
# a real floor is tinted teal / green; a box closed around label text is plain background: keep pieces whose inside is tinted
tint = (g.astype(np.int16) - r) > 6
bgtint = np.median(tint[floor == 0])
def is_floor(i):
    x, y, w, h = st[i, :4]; m_ = lab[y:y + h, x:x + w] == i
    inner_ = cv2.erode(m_.astype(np.uint8), np.ones((3 * Z, 3 * Z), np.uint8)) > 0
    if inner_.any() and (line[y:y + h, x:x + w][inner_] > 0).mean() > 0.2: return False   # mostly letters: a box around label text
    return tint[y:y + h, x:x + w][m_].mean() > bgtint + 0.25
order = sorted([i for i in range(1, nb) if st[i, 4] > 600 * Z * Z and min(st[i, 2], st[i, 3]) > 18 * Z and is_floor(i)], key=lambda i: (st[i, 1] // (200 * Z), st[i, 0]))
plan = np.zeros_like(big); ov = (big * 0.45).astype(np.uint8); out, tiles = [], []
for f in os.listdir(os.path.join(A.out, "zoom")): os.remove(os.path.join(A.out, "zoom", f))
for n, i in enumerate(order):
    m = (lab == i).astype(np.uint8) * 255
    cs, hier = cv2.findContours(m, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE); rings = []
    for j, c in enumerate(cs):
        hole = hier[0][j][3] >= 0
        if hole and cv2.contourArea(c) < 40 * Z * Z: continue
        s = snap(cv2.approxPolyDP(c, 2.0, True)).astype(np.int32)
        for im in (plan, ov): cv2.polylines(im, [s], True, BLUE, Z, cv2.LINE_AA)
        rings.append({"hole": bool(hole), "pts": (s / Z).round(2).tolist()})
    rooms = []
    for c_i in ROOMS:
        if lab[cst[c_i, 1] + cst[c_i, 3] // 2, cst[c_i, 0] + cst[c_i, 2] // 2] != i and not (m[clab == c_i] > 0).any(): continue
        if not (m[clab == c_i] > 0).mean() > 0.8: continue
        cc, _ = cv2.findContours((clab == c_i).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        s2 = snap(cv2.approxPolyDP(max(cc, key=cv2.contourArea), 2.0, True)).astype(np.int32)
        for im in (plan, ov): cv2.polylines(im, [s2], True, BLUE2, max(2, Z * 3 // 4), cv2.LINE_AA)
        rooms.append((s2 / Z).round(2).tolist())
    out.append({"piece": n + 1, "bbox": [int(v / Z) for v in st[i, :4]], "rings": rings, "rooms": rooms})
for n, i in enumerate(order):
    x, y, w, h = st[i, :4]; P = 20 * Z
    tile = ov[max(0, y - P):y + h + P, max(0, x - P):x + w + P].copy()
    cv2.putText(tile, "#%d" % (n + 1), (6 * Z, 12 * Z), cv2.FONT_HERSHEY_SIMPLEX, 0.9 * Z / 2, (60, 210, 255), Z, cv2.LINE_AA)
    cv2.imwrite(os.path.join(A.out, "zoom", "piece_%02d.png" % (n + 1)), tile); tiles.append(tile)
T = 700; rws = []
for i in range(0, len(tiles), 3):
    row = []
    for t in tiles[i:i + 3]:
        s = min(T / t.shape[1], T / t.shape[0]); t = cv2.resize(t, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
        c = np.zeros((T, T, 3), np.uint8); c[:t.shape[0], :t.shape[1]] = t; cv2.rectangle(c, (0, 0), (T - 1, T - 1), (70, 70, 70), 2); row.append(c)
    while len(row) < 3: row.append(np.zeros((T, T, 3), np.uint8))
    rws.append(np.hstack(row))
if rws: cv2.imwrite(os.path.join(A.out, "zoom_sheet.jpg"), np.vstack(rws), [cv2.IMWRITE_JPEG_QUALITY, 84])
cv2.imwrite(os.path.join(A.out, "zoom_trace.png"), cv2.resize(plan, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA))
cv2.imwrite(os.path.join(A.out, "zoom_overlay.jpg"), cv2.resize(ov, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 84])
json.dump({"source": os.path.basename(A.image), "crop": [int(Y0), int(Y1), int(X0), int(X1)], "units": "map px of the crop", "zoom": Z,
           "close": A.close, "pieces": out, "icon_doors": DOORS}, open(os.path.join(A.out, "zoom_pieces.json"), "w"))
print("grid", len(GX), len(GY)); print(os.path.basename(A.out), "frame", (Y0, Y1, X0, X1), "|", len(out), "pieces,", sum(1 for o in out for q in o["rings"] if q["hole"]), "inner walls,", len(DOORS), "icon doors,", sum(len(o["rooms"]) for o in out), "rooms")
