"""mirror_x.py IN.glb OUT.glb : symmetry repair for a model that orient.py already levelled (mirror plane = x near 0).
Same cut-and-mirror as symmetrize.py fix, but the plane is NOT searched by yaw (needed for wide ships, whose long axis
runs wing tip to wing tip); only the small sideways offset is searched. Always writes a NEW file."""
import os, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read, surf_points, clip_half, _mirror_err
from glbio import write_glb
from scipy.spatial import cKDTree
P, N, U, I, js, imgs = read(sys.argv[1])
S = surf_points(P, I, 8000); tree = cKDTree(S); w = np.ptp(S[:, 0]); mid = (S[:, 0].min() + S[:, 0].max()) / 2
best = min(((_mirror_err(S, tree, (1.0, 0.0), c), c) for c in np.linspace(mid - 0.05 * w, mid + 0.05 * w, 41)), key=lambda t: t[0])
P[:, 0] -= best[1]; halves = []
for sign in (1, -1):
    h = clip_half(P, N, U, I, 0.0, sign); a = h[0][h[3]]
    halves.append((np.linalg.norm(np.cross(a[:, 1] - a[:, 0], a[:, 2] - a[:, 0]), axis=1).sum(), h))
Ph, Nh, Uh, Ih = max(halves, key=lambda x: x[0])[1]
Pm = Ph.copy(); Pm[:, 0] = -Pm[:, 0]; Nm = Nh.copy(); Nm[:, 0] = -Nm[:, 0]
P2 = np.concatenate([Ph, Pm]); I2 = np.concatenate([Ih, Ih[:, ::-1] + len(Ph)])
P2[:, 1] -= (P2[:, 1].min() + P2[:, 1].max()) / 2; P2[:, 2] -= (P2[:, 2].min() + P2[:, 2].max()) / 2
write_glb(sys.argv[2], [{"pos": P2, "nrm": np.concatenate([Nh, Nm]), "uv": np.concatenate([Uh, Uh]), "idx": I2, "mat": 0}], js['materials'][:1], imgs, js['nodes'][0].get('name', 'ship'))
print('%-28s error before %.2f%% of width, offset %.4f, tris %d -> %d' % (os.path.basename(sys.argv[1]), best[0] / w * 100, best[1], len(I), len(I2)))
