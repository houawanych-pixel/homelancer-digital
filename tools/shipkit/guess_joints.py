#!/usr/bin/env python3
"""guess_joints — first guess of a standing humanoid's joints (x, y in 1 m units) straight from the mesh, for
rig_mech.sh rig (instead of reading them off the grid by eye). Works for Tripo characters in an A- or T-pose:
facing +Z, its left at +X, feet on y=0, about 1 m tall.

  guess_joints.py body.glb guess.json [--debug]

Torso joints go at the usual shares of the height, centred on the head; legs follow the middle of each leg at the
hip, knee and ankle; each arm runs from the shoulder ball to the farthest point of that arm (the finger tips).
Always check the bones / walk pictures after rigging.
"""
import sys, json, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as sk

g, js, b = sk.load_geometry(sys.argv[1])
P = g["pos"]
top = float(P[:, 1].max())
H = top                                   # (feet at 0)
y = P[:, 1] / H
x = P[:, 0] / H
head = (y > 0.9)
cx = float(np.median(x[head])) if head.any() else 0.0

def band(lo, hi, side=0, near=None):
    m = (y >= lo) & (y <= hi)
    if side: m &= (x - cx) * side > 0.005
    if near is not None: m &= np.abs(x - cx) < near
    return m

out = {}
T = {"Hips": 0.535, "Spine": 0.60, "Chest": 0.665, "UpperChest": 0.735, "Neck": 0.835, "Head": 0.865, "Head_end": 0.985}
for k, v in T.items(): out[k] = [cx, v]
# shoulder width: the body's half-width just under the armpit line (arms hang away from it in an A-pose)
torso = band(0.70, 0.74, near=0.16)
half = float(np.percentile(np.abs(x[torso] - cx), 90)) if torso.any() else 0.1
def segs_at(lo, hi):   # clusters across x (centred) in a height band of the front view
    xs = x[(y > lo) & (y < hi)] - cx
    occ = np.histogram(xs, bins=200, range=(-0.5, 0.5))[0] > 2
    out, i = [], 0
    while i < 200:
        if occ[i]:
            j = i
            while j + 1 < 200 and (occ[j + 1] or (j + 2 < 200 and occ[j + 2])): j += 1
            out.append((-0.5 + i * 0.005, -0.5 + (j + 1) * 0.005)); i = j + 1
        else: i += 1
    return out
arm_seg = {}
if "--arms-down" in sys.argv:   # the front view at mid height: arm | leg | leg | arm (clusters across x)
    xs = x[(y > 0.40) & (y < 0.50)] - cx
    occ = np.histogram(xs, bins=200, range=(-0.5, 0.5))[0] > 2
    segs, i = [], 0
    while i < 200:
        if occ[i]:
            j = i
            while j + 1 < 200 and (occ[j + 1] or (j + 2 < 200 and occ[j + 2])): j += 1
            segs.append((-0.5 + i * 0.005, -0.5 + (j + 1) * 0.005)); i = j + 1
        else: i += 1
    if len(segs) >= 4:
        arm_seg[-1] = segs[0]; arm_seg[1] = segs[-1]
    print("segments", [(round(a, 3), round(b, 3)) for a, b in segs])
for S, s in (("Left", 1), ("Right", -1)):
    def leg_x(lo, hi):
        if "--arms-down" in sys.argv:   # v12.84: wide-legged heavy mechs: the leg is the widest cluster on that side, not an arm
            arm = arm_seg.get(s)
            cand = [g for g in segs_at(lo, hi) if (g[0] + g[1]) / 2 * s > 0.02 and not (arm and g[1] > arm[0] and g[0] < arm[1])]
            if cand:
                g = max(cand, key=lambda g: g[1] - g[0])
                return cx + (g[0] + g[1]) / 2
        m = band(lo, hi, s, near=0.16)
        return float(np.median(x[m])) if m.any() else cx + s * 0.06
    hx = leg_x(0.50, 0.53)
    kx = leg_x(0.26, 0.30)
    ax = leg_x(0.05, 0.08)
    out[S + "UpperLeg"] = [hx, 0.52]
    out[S + "LowerLeg"] = [kx, 0.28]
    out[S + "Foot"] = [ax, 0.06]
    out[S + "Toes"] = [ax, 0.025]
    out[S + "Toes_end"] = [ax, 0.008]
    sh = [cx + s * max(0.03, half * 0.45), 0.80]
    ua = [cx + s * max(0.08, half * 0.95), 0.81]
    # the hand: the farthest-out point on this side between hip and shoulder height
    m = band(0.35, 0.86, s)
    if m.any():
        far = np.argmax((x[m] - cx) * s)
        tip = [float(x[m][far]), float(y[m][far])]
    else:
        tip = [cx + s * 0.3, 0.55]
    if "--arms-down" in sys.argv and arm_seg.get(s):   # v12.84 mechs whose arms hang outside the legs (guns down):
        lo_x, hi_x = arm_seg[s]                         # follow that arm down from mid height until it ends
        yy = 0.46
        while yy > 0.04:
            sl = (y > yy - 0.012) & (y <= yy) & (x - cx >= lo_x - 0.01) & (x - cx <= hi_x + 0.01)
            if sl.sum() < 3: break
            yy -= 0.01
        tip = [cx + (lo_x + hi_x) / 2, yy + 0.02]
    if abs(tip[0] - cx) < half + 0.04:      # arms down by the sides: hands at the hips
        tip = [cx + s * (half + 0.04), 0.47]
    v = np.array(tip) - np.array(ua)
    out[S + "Shoulder"] = sh
    out[S + "UpperArm"] = ua
    out[S + "LowerArm"] = list(np.array(ua) + v * 0.44)
    out[S + "Hand"] = list(np.array(ua) + v * 0.84)
    out[S + "Hand_end"] = list(np.array(ua) + v * 0.98)
out = {k: [round(float(a), 3), round(float(b2), 3)] for k, (a, b2) in out.items()}
json.dump(out, open(sys.argv[2], "w"), indent=1)
if "--debug" in sys.argv: print(json.dumps({"H": H, "cx": cx, "half": half}))
print("guess:", sys.argv[2])
