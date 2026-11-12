#!/usr/bin/env python3
"""v13.83 (owner: "I prefer 3 pieces ... less animation"; the generator takes 16:9 or narrower): after
`loc_cut3.py ... --fewest --pieces 4`, stack the pieces two to a picture, like the owner's own room pictures (one view
on top, the next below, a thin white line between). 2 pictures = 2 animations per room, each narrower than 16:9, no
white bands. Each row is a window of the strip centred on its piece; only the piece (+overlap) is kept on the join.

    python3 tools/rooms/loc_pack_rows.py <sys> <place> <room> <out_dir>"""
import json, os, sys
import cv2, numpy as np
sy, place, room, d = sys.argv[1:5]
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
jp = os.path.join(HERE, "loc_cuts", "%s_%s_%s.json" % (sy, place.lower(), room.lower()))
m = json.load(open(jp)); OV = m["overlap"]; LINE = 6
im = cv2.imread(os.path.join(ROOT, m["src"])); H, W = im.shape[:2]
wrap = np.concatenate([im, im, im], axis=1)
cuts = m["cuts"]; N = len(cuts)
spans = []
for i in range(N):
    a = cuts[i]; b = cuts[(i + 1) % N]
    if b <= a: b += W
    spans.append((a, b))
sr = cv2.dnn_superres.DnnSuperResImpl_create(); sr.readModel("/tmp/srm/FSRCNN_x4.pb"); sr.setModel("fsrcnn", 4)
os.makedirs(d, exist_ok=True); m["pictures"] = []
for k in range(0, N, 2):
    rows = spans[k:k + 2]
    wr = max(b - a for a, b in rows) + 2 * OV
    assert wr <= (2 * H + LINE) * 16 / 9.0, "too wide for 16:9"
    frame = np.full((H * len(rows) + LINE * (len(rows) - 1), wr, 3), 255, np.uint8); info = []
    for r, (a, b) in enumerate(rows):
        x0 = (a + b) // 2 - wr // 2; y0 = r * (H + LINE)
        frame[y0:y0 + H] = wrap[:, W + x0:W + x0 + wr]
        info.append({"row": r, "strip_x0": x0 % W, "strip_w": wr, "keep": [a % W, b - a], "y0": y0})
    s = 1080.0 / frame.shape[0]
    up = cv2.resize(sr.upsample(frame), (int(round(wr * s)), 1080), interpolation=cv2.INTER_AREA)
    name = "%s_%s_pic%d.png" % (place, room, k // 2 + 1)
    cv2.imwrite(os.path.join(d, name), up)
    m["pictures"].append({"file": name, "size": [up.shape[1], 1080], "scale": s, "rows": info})
    print(name, up.shape)
json.dump(m, open(jp, "w"), indent=1)
