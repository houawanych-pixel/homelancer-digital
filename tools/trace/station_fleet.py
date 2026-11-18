#!/usr/bin/env python3
"""v13.190 (owner, Liberty Hub: "why does it not follow the same format as the ships? ... it should be the same build,
it's just a different map ... enemy stations are the same infiltration, rescue the hostage, destroy"): a station's
decks built with the FLEET SHIP pipeline, so it plays, looks and maps exactly like a fleet ship:

  station silhouette (station_plans.deck_outlines, the MAIN HUB slice) -> fleet_station_<model>/source.jpg + source_mask.png
  fleetmain.compose with the "station" recipe (a spine with bands: Docking Bay, Main Hub, Mission Center, shops ...)
  fleet_compose upper / lower decks round the same lift shaft (like the capital ships)
  to_deck_json.py --decks -> assets/holodeck/station_<model>.json (the same board format, same map pictures)

usage: python3 -I tools/trace/station_fleet.py st3d_veranthos_customs"""
import json, os, sys, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np, cv2
from PIL import Image
import station_plans as SP
import fleetmain
from shapely.affinity import scale, translate

W, H, LONG, MAXW = 1024, 1536, 1320, 940

fleetmain.RECIPES["station"] = [
    ("C", "Command Center", 8), ("S", ("Station Security", "Comms"), 7), ("O", "Main Hub", 12), ("S", ("Mission Center", "Shipyard"), 9),
    ("L", "Lift", 2.8), ("S", ("Supplies", "Medical Bay"), 8), ("S", ("Pilots' Lounge", "Mech Dealer"), 8),
    ("S", ("Detention*", "Armory"), 7), ("B", "Docking Bay", 16), ("S", ("Cargo Hold A", "Cargo Hold B"), 9),
    ("C", "Engineering", 8), ("O", "Reactor Core", 10), ("C", "Power Plant", 6)]
fleetmain.CARDS["station"] = 3
fleetmain.WIDE["station"] = 1.6


def source(model, out):
    S = json.load(open(os.path.join(SP.OUT, "stations.json")))
    st = next(s for s in S if s["model"] == model)
    O = SP.deck_outlines(st)
    poly = O["polys"][2]                       # the MAIN HUB deck's own outline
    x0, y0, x1, y1 = poly.bounds
    k = min(LONG / (y1 - y0), MAXW / (x1 - x0))
    p = translate(scale(poly, k, k, origin=(0, 0)), W / 2 - (x0 + x1) / 2 * k, H / 2 - (y0 + y1) / 2 * k)
    mask = np.zeros((H, W), np.uint8)
    cv2.fillPoly(mask, [np.round(np.array(p.exterior.coords)).astype(np.int32)], 255)
    img = np.zeros((H, W, 3), np.uint8); img[:] = (34, 16, 8)
    img[::40, :] = (90, 60, 30); img[:, ::40] = (90, 60, 30)
    img[mask > 0] = (120, 96, 70)
    cv2.polylines(img, [np.round(np.array(p.exterior.coords)).astype(np.int32)], True, (230, 200, 160), 2, cv2.LINE_AA)
    os.makedirs(os.path.join(out, "eng"), exist_ok=True)
    cv2.imwrite(os.path.join(out, "source.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 88])
    Image.fromarray(mask).save(os.path.join(out, "source_mask.png"), optimize=True)
    print(model, "silhouette %d x %d px" % (p.bounds[2] - p.bounds[0], p.bounds[3] - p.bounds[1]))
    return st


def main(model):
    sid = "station_" + model.replace("st3d_", "")
    out = os.path.join(HERE, "fleet_" + sid)
    st = source(model, out)
    eng = os.path.join(out, "eng")
    bad = fleetmain.main(sid, eng, "station")
    plan = json.load(open(os.path.join(eng, "plan.json")))
    print("main deck check failures:", bad)
    return sid, out


if __name__ == "__main__":
    for m in sys.argv[1:]: main(m)
