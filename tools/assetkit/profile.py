import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
for f in sys.argv[1:]:
    P, N, U, I, js, imgs = read(f); c = P[I].mean(1); print(os.path.basename(f), 'size', np.round(np.ptp(P, 0), 4), 'min', np.round(P.min(0), 4))
    z0, z1 = P[:, 2].min(), P[:, 2].max(); n = 24
    for k in range(n):
        a, b = z0 + (z1 - z0) * k / n, z0 + (z1 - z0) * (k + 1) / n; m = (c[:, 2] >= a) & (c[:, 2] < b); q = P[I[m]].reshape(-1, 3)
        if len(q): print('  z %+.4f..%+.4f  halfwidth %.4f  y %+.4f..%+.4f  tris %d' % (a, b, np.abs(q[:, 0]).max(), q[:, 1].min(), q[:, 1].max(), m.sum()))
