"""straighten.py IN.glb OUT.glb : NEW copy turned about Y so its long horizontal axis lies along Z, centred. Keeps texture."""
import sys, os, json, struct, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
P, N, U, I, js, imgs = read(sys.argv[1])
xz = P[:, [0, 2]] - P[:, [0, 2]].mean(0); w, v = np.linalg.eigh(np.cov(xz[::5].T)); m = v[:, 1]
a = -np.arctan2(m[0], m[1]); c, s = np.cos(a), np.sin(a); R = np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
P = P @ R.T; N = N @ R.T; P -= (P.min(0) + P.max(0)) / 2
write_glb(sys.argv[2], [{"pos": P, "nrm": N, "uv": U, "idx": I, "mat": 0}], js['materials'][:1], imgs, 'p')
print('%.1f' % np.degrees(a), [round(float(x), 3) for x in np.ptp(P, 0)])
