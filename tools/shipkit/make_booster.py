#!/usr/bin/env python3
"""make_booster — procedural mech back-booster pack (GLB, separate object).

  make_booster.py out.glb [--scale 1.0] [--hull r,g,b] [--trim r,g,b] [--glow r,g,b]

Built around the origin (the mount point on the back), pointing backwards (-Z) and slightly down.
Parts: armoured core pack, two main thruster nacelles with glowing nozzles, two swept wing-vanes
with small vernier thrusters, and a spine fin. Hull/trim/glow colours match the mech's paint.
Units: body-height 1.0 (a 1.0-tall mech). Mount on UpperChest.
"""
import argparse, math, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as sk


class Mesh:
    def __init__(self):
        self.p, self.n, self.t = [], [], []

    def add(self, P, T, smooth=False):
        base = sum(len(x) for x in self.p)
        P = np.asarray(P, float); T = np.asarray(T, int)
        if smooth:   # shared vertices, averaged normals (round parts)
            fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
            vn = np.zeros_like(P)
            for k in range(3): np.add.at(vn, T[:, k], fn)
            vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
            self.p.append(P); self.n.append(vn); self.t.append(T + base)
            return
        # flat normals: unshare vertices per face
        tp = P[T].reshape(-1, 3)
        fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
        fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
        self.p.append(tp); self.n.append(np.repeat(fn, 3, 0))
        self.t.append(np.arange(len(tp)).reshape(-1, 3) + base)

    def arrays(self):
        return np.vstack(self.p), np.vstack(self.n), np.vstack(self.t)


def xform(P, R=np.eye(3), t=(0, 0, 0)):
    return np.asarray(P) @ np.asarray(R).T + np.asarray(t)


def rot(axis, deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    if axis == "x": return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
    if axis == "y": return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def box(sx, sy, sz, bevel=0.0):
    """Chamfered box: corners pulled in by `bevel` on the back face (tapered armour look)."""
    x, y, z = sx / 2, sy / 2, sz / 2
    b = bevel
    P = [[-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z],
         [-x + b, -y + b, -z], [x - b, -y + b, -z], [x - b, y - b, -z], [-x + b, y - b, -z]]
    F = [[0, 1, 2], [0, 2, 3], [5, 4, 7], [5, 7, 6], [4, 0, 3], [4, 3, 7], [1, 5, 6], [1, 6, 2],
         [3, 2, 6], [3, 6, 7], [4, 5, 1], [4, 1, 0]]
    return P, F


def cyl(r0, r1, length, seg=20, cap0=True, cap1=True):
    """Cylinder/cone along -Z from z=0 (radius r0) to z=-length (radius r1)."""
    P, F = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        P += [[r0 * math.cos(a), r0 * math.sin(a), 0], [r1 * math.cos(a), r1 * math.sin(a), -length]]
    for i in range(seg):
        a0, b0 = 2 * i, 2 * i + 1; a1, b1 = 2 * ((i + 1) % seg), 2 * ((i + 1) % seg) + 1
        F += [[a0, b0, a1], [a1, b0, b1]]
    if cap0:
        c = len(P); P.append([0, 0, 0])
        F += [[c, 2 * ((i + 1) % seg), 2 * i] for i in range(seg)]
    if cap1:
        c = len(P); P.append([0, 0, -length])
        F += [[c, 2 * i + 1, 2 * ((i + 1) % seg) + 1] for i in range(seg)]
    return P, F


def vane(span, root, tip, thick, sweep):
    """Swept wing-vane in the XY plane going +X, thickness along Z."""
    t = thick / 2
    P = [[0, -root / 2, t], [0, root / 2, t], [span, sweep + tip / 2, t], [span, sweep - tip / 2, t],
         [0, -root / 2, -t], [0, root / 2, -t], [span, sweep + tip / 2, -t], [span, sweep - tip / 2, -t]]
    F = [[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5],
         [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7]]
    return P, F


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--hull", default="0.50,0.03,0.04"); ap.add_argument("--trim", default="0.07,0.07,0.09")
    ap.add_argument("--glow", default="1.0,0.45,0.15")
    a = ap.parse_args()
    hull, trim, glow, metal = Mesh(), Mesh(), Mesh(), Mesh()
    # core pack: tapered armoured block hugging the back
    P, F = box(0.19, 0.22, 0.07, bevel=0.018); hull.add(xform(P, t=(0, 0, -0.035)), F)
    P, F = box(0.12, 0.15, 0.04, bevel=0.012); trim.add(xform(P, t=(0, 0.005, -0.085)), F)
    for s in (-1, 1):
        # main nacelle: points down and back, splayed slightly outboard
        R = rot("y", s * 8) @ rot("x", -30)
        base = np.array([s * 0.075, 0.03, -0.075])
        P, F = cyl(0.036, 0.040, 0.17, 28); hull.add(xform(P, R, base), F, smooth=True)
        for d in (0.03, 0.11):
            P, F = cyl(0.041, 0.041, 0.018, 28); trim.add(xform(P, R, base + R @ np.array([0, 0, -d])), F, smooth=True)
        P, F = cyl(0.040, 0.052, 0.05, 28, cap0=False, cap1=False); metal.add(xform(P, R, base + R @ np.array([0, 0, -0.17])), F, smooth=True)
        P, F = cyl(0.036, 0.0, 0.012, 28, cap1=False); glow.add(xform(P, R, base + R @ np.array([0, 0, -0.185])), F, smooth=True)
        # swept wing-vane rising up and out behind the shoulder, vernier at the tip
        Rv = rot("z", s * 38) @ rot("y", s * -14)
        P, F = vane(0.24, 0.09, 0.035, 0.012, 0.06)
        Pv = np.array(P); Pv[:, 0] *= s
        if s < 0: F = [[f[0], f[2], f[1]] for f in F]
        root = np.array([s * 0.08, 0.07, -0.075])
        hull.add(xform(Pv, Rv, root), F)
        tip = Rv @ np.array([s * 0.24, 0.06, 0]) + root
        P, F = cyl(0.013, 0.016, 0.045, 16); trim.add(xform(P, rot("x", -20), tip), F, smooth=True)
        P, F = cyl(0.012, 0.0, 0.005, 16, cap1=False); glow.add(xform(P, rot("x", -20), tip + rot("x", -20) @ np.array([0, 0, -0.05])), F, smooth=True)
    # dorsal fin: rises from the top of the pack
    P, F = vane(0.10, 0.08, 0.025, 0.012, -0.02)
    hull.add(xform(P, rot("y", 90) @ rot("z", 90), (0, 0.10, -0.06)), F)
    mats = [
        {"name": "booster_hull", "pbrMetallicRoughness": {"baseColorFactor": [*map(float, a.hull.split(",")), 1], "metallicFactor": 0.55, "roughnessFactor": 0.38}},
        {"name": "booster_trim", "pbrMetallicRoughness": {"baseColorFactor": [*map(float, a.trim.split(",")), 1], "metallicFactor": 0.8, "roughnessFactor": 0.35}},
        {"name": "booster_metal", "pbrMetallicRoughness": {"baseColorFactor": [0.32, 0.30, 0.30, 1], "metallicFactor": 0.95, "roughnessFactor": 0.25}},
        {"name": "booster_glow", "pbrMetallicRoughness": {"baseColorFactor": [*map(float, a.glow.split(",")), 1], "metallicFactor": 0.0, "roughnessFactor": 0.6},
         "emissiveFactor": [*map(float, a.glow.split(","))]},
    ]
    for m_ in mats:
        m_["doubleSided"] = True
    surfaces = []
    for i, m in enumerate((hull, trim, metal, glow)):
        p, n, t = m.arrays()
        surfaces.append((p * a.scale, n, np.zeros((len(p), 2)), t, i))
    sk.write_glb(a.out, surfaces, mats, [], "BackBooster")
    print("booster tris", sum(len(s[3]) for s in surfaces))


if __name__ == "__main__":
    main()
