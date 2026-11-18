#!/usr/bin/env python3
"""Liberty Hub (Veranthos Customs) main deck v2, the source: the owner's "Veranthos Customs inner map - mech & pilot
ways (concept)" (fleet_station_veranthos_customs/concept2/source.png), x3, turned 45 deg about the hub so the four big
docking arms run straight (the ship engine builds straight walkways only). Writes source.jpg (the art, turned) and
hull.json (the station floor outline from the concept's traced floor mask, same frame)."""
import json, os
import cv2, numpy as np
from shapely.geometry import Polygon, mapping
HERE = os.path.dirname(os.path.abspath(__file__))
C2 = os.path.join(HERE, "..", "fleet_station_veranthos_customs", "concept2")
HUB = (553.0, 523.0); K = 3.0; N = 3300; ROT = 0.0
src = cv2.imread(os.path.join(C2, "source.png"))
A = cv2.getRotationMatrix2D(HUB, ROT, K); A[0, 2] += N / 2 - HUB[0]; A[1, 2] += N / 2 - HUB[1]
art = cv2.warpAffine(src, A, (N, N), flags=cv2.INTER_CUBIC, borderValue=(25, 12, 6))
cv2.imwrite(os.path.join(HERE, "source.jpg"), art, [cv2.IMWRITE_JPEG_QUALITY, 90])
fl = np.load(os.path.join(C2, "masks.npz"))["floor"]          # x4 of the source
A4 = cv2.getRotationMatrix2D((HUB[0] * 4, HUB[1] * 4), ROT, K / 4); A4[0, 2] += N / 2 - HUB[0] * 4; A4[1, 2] += N / 2 - HUB[1] * 4
m = cv2.warpAffine(fl.astype(np.uint8) * 255, A4, (N, N), flags=cv2.INTER_NEAREST)
cs, _ = cv2.findContours((m > 127).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
c = max(cs, key=cv2.contourArea)
P = Polygon(cv2.approxPolyDP(c, 3, True).reshape(-1, 2)).buffer(0)
json.dump({"hull": mapping(P), "centre": [N / 2, N / 2], "k": K, "rot": ROT}, open(os.path.join(HERE, "hull.json"), "w"))
print("hull bounds", [round(v) for v in P.bounds])
