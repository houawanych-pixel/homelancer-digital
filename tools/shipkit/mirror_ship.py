#!/usr/bin/env python3
"""Make a lopsided ship symmetrical: cut it in half along its length and mirror one half onto the other side.
  python3 tools/shipkit/mirror_ship.py SHIP.glb OUTDIR [--axis x]
Writes two ships, one from each half: <OUTDIR>/mirror_tall_full.glb (the half with the taller fin, so it gets two
fins) and mirror_low_full.glb, each with a preview. Nose -> -Z, up +Y, centred. Then decimate + repack as usual."""
import argparse, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import shipkit as sk

ap = argparse.ArgumentParser(); ap.add_argument("src"); ap.add_argument("out"); ap.add_argument("--axis", default="x"); ap.add_argument("--flip", action="store_true")
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)
g, js, binc = sk.load_geometry(a.src)
pos, nrm, uv, tri = sk.compact(g["pos"], g["nrm"], g["uv"], g["tri"])
pos, nrm, rep = sk.orient(pos, nrm, a.flip, a.axis)          # long axis -> Z, nose -Z; the cut plane is x = c
front = pos[pos[:, 2] < np.percentile(pos[:, 2], 25)]
c = float(np.median(front[:, 0]))                              # the hull's centre line, measured at the nose
mats, images, mat_map = sk.remap_materials(js, binc, [0], 512)
side_top = {s: float(pos[(pos[:, 0] - c) * s > 0.02][:, 1].max()) for s in (1, -1)}
tall = 1 if side_top[1] >= side_top[-1] else -1
for name, s in (("tall", tall), ("low", -tall)):
    keep = ((pos[tri][:, :, 0] - c) * s >= 0).any(1)           # triangles on this side (ones crossing are clamped)
    p, n, u, t = sk.compact(pos, nrm, uv, tri[keep])
    p = p.copy(); p[:, 0] = c + s * np.maximum((p[:, 0] - c) * s, 0.0)
    pm = p.copy(); pm[:, 0] = 2 * c - pm[:, 0]
    nm = n.copy(); nm[:, 0] = -nm[:, 0]
    P = np.concatenate([p, pm]); N = np.concatenate([n, nm]); U = np.concatenate([u, u])
    T = np.concatenate([t, t[:, ::-1] + len(p)])
    P = P - (P.min(0) + P.max(0)) / 2
    sk.write_glb(os.path.join(a.out, "mirror_%s_full.glb" % name), [(P, N, U, T, mat_map.get(0, -1))], mats, images, "mirror_" + name)
    tt = T if len(T) <= 70000 else T[np.random.default_rng(0).choice(len(T), 70000, replace=False)]
    sk.sheet([sk.render(P, tt, v, 520, title="%s %s" % (name, v)) for v in ("top", "front", "persp")], os.path.join(a.out, "mirror_%s_preview.png" % name))
    print(name, len(T), np.ptp(P, axis=0).round(3).tolist())
print(rep, "tall side", tall, side_top)
