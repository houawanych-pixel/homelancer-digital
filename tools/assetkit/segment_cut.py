"""segment_cut.py IN.glb OUT.glb Z1 Z2 [overlap] : shorten a levelled ship (nose at -Z) by cutting out the slice Z1 < z < Z2
and sliding everything ahead of it back to close the gap (a second cockpit-looking bulge removed, the real cockpit moved
back). Both cuts are capped. NO_CENTER=1 keeps the rear part where it was (for a rear_swap afterwards). NEW file always."""
import os, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
from rear_swap import clip_z
a = sys.argv; z1, z2 = float(a[3]), float(a[4]); ov = float(a[5]) if len(a) > 5 else 0.0015
P, N, U, I, js, imgs = read(a[1])
Pf, Nf, Uf, If = clip_z(P, N, U, I, z1, True); Pr, Nr, Ur, Ir = clip_z(P, N, U, I, z2, False)
Pf = Pf.copy(); Pf[:, 2] += (z2 - z1) + ov
P2 = np.concatenate([Pf, Pr]); I2 = np.concatenate([If, Ir + len(Pf)])
if not os.environ.get('NO_CENTER'):
    P2[:, 1] -= (P2[:, 1].min() + P2[:, 1].max()) / 2; P2[:, 2] -= (P2[:, 2].min() + P2[:, 2].max()) / 2
write_glb(a[2], [{"pos": P2, "nrm": np.concatenate([Nf, Nr]), "uv": np.concatenate([Uf, Ur]), "idx": I2, "mat": 0}], js['materials'][:1], imgs, js['nodes'][0].get('name', 'ship'))
print('%s: %d tris, length %.4f -> %.4f' % (os.path.basename(a[2]), len(I2), np.ptp(P[:, 2]), np.ptp(P2[:, 2])))
