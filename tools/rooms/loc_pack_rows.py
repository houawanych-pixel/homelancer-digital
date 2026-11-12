#!/usr/bin/env python3
"""v13.85 (owner: 3 clips a room, each 16:9 or narrower, every edge a real seam, no padding): stack the room's 6
pieces two to a picture, like the owner's own room pictures (one view on top, a thin white line, the next below).
The two pieces in a picture are paired by width (all 15 pairings tried, closest widths win); the narrower one is
scaled up to the same width, so the picture edges are exactly the cuts and there is nothing added. The cut file gets
each row's strip range, y and scale, to put the animated clips back on the strip.

    python3 tools/rooms/loc_pack_rows.py <sys> <place> <room> <out_dir>"""
import json, os, sys
import cv2, numpy as np
sy, place, room, d = sys.argv[1:5]
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
jp = os.path.join(HERE, "loc_cuts", "%s_%s_%s.json" % (sy, place.lower(), room.lower()))
m = json.load(open(jp)); LINE = 6
im = cv2.imread(os.path.join(ROOT, m["src"])); H, W = im.shape[:2]
wrap = np.concatenate([im, im, im], axis=1)
cuts = m["cuts"]; N = len(cuts)
spans = []
for i in range(N):
    a = cuts[i]; b = cuts[(i + 1) % N]
    if b <= a: b += W
    spans.append((a, b))
def pairings(items):
    if not items: yield []; return
    f = items[0]
    for j in range(1, len(items)):
        rest = items[1:j] + items[j + 1:]
        for p in pairings(rest): yield [(f, items[j])] + p
wid = lambda i: spans[i][1] - spans[i][0]
best = min(pairings(list(range(N))), key=lambda P: max(max(wid(a), wid(b)) / min(wid(a), wid(b)) for a, b in P))
best = sorted([tuple(sorted(p)) for p in best])
sr = cv2.dnn_superres.DnnSuperResImpl_create(); sr.readModel("/tmp/srm/FSRCNN_x4.pb"); sr.setModel("fsrcnn", 4)
os.makedirs(d, exist_ok=True); m["pictures"] = []
for k, (i, j) in enumerate(best):
    wr = max(wid(i), wid(j)); rows = []; y = 0
    for n in (i, j):
        a, b = spans[n]; piece = wrap[:, W + a:W + b]; k_s = wr / float(b - a); h = int(round(H * k_s))
        rows.append(cv2.resize(piece, (wr, h), interpolation=cv2.INTER_CUBIC) if k_s != 1 else piece)
    frame = np.full((rows[0].shape[0] + LINE + rows[1].shape[0], wr, 3), 255, np.uint8)
    frame[:rows[0].shape[0]] = rows[0]; frame[rows[0].shape[0] + LINE:] = rows[1]
    assert wr / frame.shape[0] <= 16 / 9.0 + 1e-6, "wider than 16:9"
    s = 1080.0 / frame.shape[0]
    up = cv2.resize(sr.upsample(frame), (int(round(wr * s)), 1080), interpolation=cv2.INTER_AREA)
    name = "%s_%s_clip%d.png" % (place, room, k + 1)
    cv2.imwrite(os.path.join(d, name), up)
    info = []; y = 0
    for n, r in zip((i, j), rows):
        a, b = spans[n]
        info.append({"piece": n + 1, "strip": [a % W, b - a], "y": round(y * s, 2), "h": round(r.shape[0] * s, 2), "px_per_strip_px": round(s * wr / (b - a), 4)})
        y += r.shape[0] + LINE
    m["pictures"].append({"file": name, "size": [up.shape[1], 1080], "rows": info})
    print(name, up.shape, "pieces", i + 1, j + 1, "widths", wid(i), wid(j))
json.dump(m, open(jp, "w"), indent=1)
