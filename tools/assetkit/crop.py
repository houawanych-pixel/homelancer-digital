"""crop.py IN.glb OUT.glb x0,x1,y0,y1,z0,z1 : NEW file with only the triangles whose centre lies in the box (texture kept)."""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
P, N, U, I, js, imgs = read(sys.argv[1]); b = [float(x) for x in sys.argv[3].split(',')]; c = P[I].mean(1)
m = (c[:, 0] >= b[0]) & (c[:, 0] <= b[1]) & (c[:, 1] >= b[2]) & (c[:, 1] <= b[3]) & (c[:, 2] >= b[4]) & (c[:, 2] <= b[5])
u, inv = np.unique(I[m], return_inverse=True)
write_glb(sys.argv[2], [{"pos": P[u], "nrm": N[u], "uv": U[u], "idx": inv.reshape(-1, 3), "mat": 0}], js['materials'][:1], imgs, 'part')
print(m.sum(), 'tris', np.round(P[u].min(0), 4), np.round(P[u].max(0), 4))
