#!/usr/bin/env python3
"""auto_joints — finish a joints.json: you give each joint's x,y (read off the measured front view), this fills z
(the middle of the body at that height) so every bone sits inside the mesh.

  auto_joints.py body.glb guess.json joints.json
guess.json: {"Hips":[x,y], "Spine":[x,y], ..., "LeftToes":[x,y], "LeftToes_end":[x,y], ...}  (1 m-tall units,
character faces +Z, its left is +X). Toes use the foot's front; Toes_end goes to the tip of the foot.
"""
import sys, json, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as sk
g, js, b = sk.load_geometry(sys.argv[1]); P = g["pos"]
out = {}
for k, (x, y) in json.load(open(sys.argv[2])).items():
    m = (abs(P[:, 0] - x) < 0.035) & (abs(P[:, 1] - y) < 0.02)
    if "Toes" in k: m = (abs(P[:, 0] - x) < 0.05) & (P[:, 1] < 0.06)
    zs = P[m, 2]
    if len(zs) == 0: print("WARNING no mesh near", k); z = 0.0
    elif k.endswith("Toes_end"): z = float(np.percentile(zs, 97))
    elif k.endswith("Toes"): z = float(np.percentile(zs, 60))
    else: z = float((np.percentile(zs, 5) + np.percentile(zs, 95)) / 2)
    out[k] = [round(x, 3), round(y, 3), round(z, 3)]
json.dump(out, open(sys.argv[3], "w"), indent=1)
print(json.dumps(out))
