#!/usr/bin/env python3
"""v13.79: bring loc_cut3.py's native 16:9 windows up to full 1920x1080 frames (FSRCNN x4, then area-scaled down),
so the video generator gets a whole picture with no white bands.  Needs OpenCV with dnn_superres (system python3).

    python3 tools/rooms/loc_upscale.py <out_dir> [model.pb]"""
import glob, os, sys
import cv2
d = sys.argv[1]
model = sys.argv[2] if len(sys.argv) > 2 else "/tmp/srm/FSRCNN_x4.pb"
sr = cv2.dnn_superres.DnnSuperResImpl_create(); sr.readModel(model); sr.setModel("fsrcnn", 4)
for p in sorted(glob.glob(os.path.join(d, "*_part*.png"))):
    im = cv2.imread(p)
    if im.shape[1] == 1920: continue
    up = cv2.resize(sr.upsample(im), (1920, 1080), interpolation=cv2.INTER_AREA)
    cv2.imwrite(p, up); print(p, up.shape)
