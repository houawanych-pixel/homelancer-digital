#!/usr/bin/env python3
"""v13.87 (owner: "no blend, no blur ... straight and crisp"; "if you blur it they'll see a line all the way down"):
cut a location room's 360 strip into 3 CONTINUOUS pieces at the given seams (pillars / walls / empty floor, chosen by eye
with loc_cut_pairs.py HL_NCUT=3 as a helper), each piece exactly seam-to-seam (no overlap, no padding, no stacking),
at most 16 x 4.5 so the owner's generator takes it, FSRCNN-upscaled to 1920 wide. The animated clips are later put
back edge to edge with a hard, crisp seam (no blend); the prompt keeps the edges still so they match.

    python3 tools/rooms/loc_cut_crisp.py <sys> <Place> <Room> <out_dir> <c1,c2,c3>"""
import json, os, sys
import cv2, numpy as np
sy, place, room, d, cs = sys.argv[1:6]
cuts = sorted(int(v) for v in cs.split(","))
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
src = "assets/rooms/loc/%s_%s_%s.jpg" % (sy, place.lower(), room.lower())
im = cv2.imread(os.path.join(ROOT, src)); H, W = im.shape[:2]
wrap = np.concatenate([im, im], axis=1)
sr = cv2.dnn_superres.DnnSuperResImpl_create(); sr.readModel("/tmp/srm/FSRCNN_x4.pb"); sr.setModel("fsrcnn", 4)
os.makedirs(d, exist_ok=True)
meta = {"src": src, "strip": [W, H], "cuts": cuts, "method": "crisp: 3 continuous pieces seam-to-seam, joined edge to edge, no blend", "parts": []}
pv = im.copy()
for i in range(3):
    a = cuts[i]; b = cuts[i + 1] if i < 2 else cuts[0] + W
    piece = wrap[:, a:b]; assert (b - a) / H <= 16 / 4.5 + 1e-6, "piece %d wider than 16 x 4.5" % (i + 1)
    h = int(round(H * 1920.0 / (b - a)))
    up = cv2.resize(sr.upsample(piece), (1920, h), interpolation=cv2.INTER_AREA)
    name = "%s_%s_clip%d.png" % (place, room, i + 1)
    cv2.imwrite(os.path.join(d, name), up)
    meta["parts"].append({"file": name, "strip_x0": a % W, "strip_w": b - a, "size": [1920, h]})
    cv2.line(pv, (a % W, 0), (a % W, H), (0, 0, 255), 4); cv2.putText(pv, str(i + 1), (a % W + 8, 40), 0, 1.2, (255, 255, 255), 3)
    print(name, up.shape, "strip", a % W, b - a, "ratio %.2f" % ((b - a) / H))
cv2.imwrite(os.path.join(d, "%s_%s_seams.jpg" % (place, room)), pv, [cv2.IMWRITE_JPEG_QUALITY, 85])
json.dump(meta, open(os.path.join(HERE, "loc_cuts", "%s_%s_%s.json" % (sy, place.lower(), room.lower())), "w"), indent=1)
