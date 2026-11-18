#!/usr/bin/env python3
"""STEP 2a of the station formula: each floor's clean silhouette (station_silhouette.py) placed on a fleet-ship sheet
(1600 x 1600, 10 px = 1 m, the station's middle on x 800, y 800, the MAIN HUB floor W_M metres across), so the deck is
built with the fleet ship tools (decklib: library rooms, halls, the owner's checks). Writes
tools/trace/fleet_station_<id>/source.jpg + source_mask.png (MAIN HUB) and eng/src_<floor>.jpg + _mask.png (the others).
usage: python3 -I station_source.py <model> [width_m]"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np, cv2
from shapely.geometry import shape
from shapely import affinity
import station_plans as SP

W, H = 1600, 1600
KEY = {"MAIN HUB": None, "HANGAR": "lower2", "ENGINEERING": "lower", "HABITAT": "upper", "COMMAND": "upper2"}


def make(model, width_m=140.0):
    S = json.load(open(os.path.join(SP.OUT, model, "silhouettes.json")))
    ax = S["axis_x"]; N = S["N"]
    hub = shape(next(f for f in S["floors"] if f["name"] == "MAIN HUB")["outline"])
    k = width_m * 10.0 / (hub.bounds[2] - hub.bounds[0])
    sid = "station_" + model.replace("st3d_", "")
    out = os.path.join(HERE, "fleet_" + sid)
    os.makedirs(os.path.join(out, "eng"), exist_ok=True)
    info = {}
    for f in S["floors"]:
        g = affinity.translate(affinity.scale(shape(f["outline"]), k, k, origin=(ax, N / 2.0)), W / 2 - ax, H / 2 - N / 2.0)
        mask = np.zeros((H, W), np.uint8)
        cv2.fillPoly(mask, [np.round(np.array(g.exterior.coords)).astype(np.int32)], 255)
        img = np.zeros((H, W, 3), np.uint8); img[:] = (34, 16, 8)
        img[::50, :] = (70, 46, 24); img[:, ::50] = (70, 46, 24)
        img[mask > 0] = (110, 72, 34)
        cv2.polylines(img, [np.round(np.array(g.exterior.coords)).astype(np.int32)], True, (240, 215, 170), 2, cv2.LINE_AA)
        if KEY[f["name"]] is None:
            cv2.imwrite(os.path.join(out, "source.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 90]); cv2.imwrite(os.path.join(out, "source_mask.png"), mask)
        else:
            p = os.path.join(out, "eng", "src_%s" % KEY[f["name"]])
            cv2.imwrite(p + ".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 90]); cv2.imwrite(p + "_mask.png", mask)
        info[f["name"]] = [round(v) for v in g.bounds]
    print(sid, "scale %.3f" % k, info)


if __name__ == "__main__":
    make(sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 140.0)
