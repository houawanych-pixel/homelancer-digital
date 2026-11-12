#!/usr/bin/env python3
"""v13.81 (owner: "just crop the white off"): after loc_cut3.py, write each piece on its own (no bands, no white),
FSRCNN-upscaled to 1920 wide, and point the cut file's frame_rect at the whole picture.

    python3 tools/rooms/loc_crop.py <sys> <place> <room> <out_dir>"""
import json, os, sys
import cv2
sy, place, room, d = sys.argv[1:5]
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
jp = os.path.join(HERE, "loc_cuts", "%s_%s_%s.json" % (sy, place.lower(), room.lower()))
m = json.load(open(jp))
sr = cv2.dnn_superres.DnnSuperResImpl_create(); sr.readModel("/tmp/srm/FSRCNN_x4.pb"); sr.setModel("fsrcnn", 4)
im = cv2.imread(os.path.join(ROOT, m["src"])); H, W = im.shape[:2]
wrap = cv2.hconcat([im, im, im]); os.makedirs(d, exist_ok=True)
for p in m["parts"]:
    a, pw = p["strip_x0"], p["strip_w"]
    up = sr.upsample(wrap[:, W + a:W + a + pw]); h = int(round(H * 1920.0 / pw))
    up = cv2.resize(up, (1920, h), interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(d, p["file"]), up); p["frame_rect"] = [0, 0, 1920, h]; p["frame"] = [1920, h]
m["frame"] = "piece only, 1920 wide (no bands)"
json.dump(m, open(jp, "w"), indent=1)
