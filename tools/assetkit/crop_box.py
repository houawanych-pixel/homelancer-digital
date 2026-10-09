"""crop_box.py IN OUT xmin xmax ymin ymax zmin zmax : NEW copy keeping triangles whose centre lies in the box."""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
P, N, U, I, js, imgs = read(sys.argv[1]); b = [float(x) for x in sys.argv[3:9]]
c = P[I].mean(1)
m = (c[:, 0] >= b[0]) & (c[:, 0] <= b[1]) & (c[:, 1] >= b[2]) & (c[:, 1] <= b[3]) & (c[:, 2] >= b[4]) & (c[:, 2] <= b[5])
f = I[m]; u, inv = np.unique(f, return_inverse=True)
write_glb(sys.argv[2], [{"pos": P[u], "nrm": N[u], "uv": U[u], "idx": inv.reshape(-1, 3), "mat": 0}], js['materials'][:1], imgs, 'crop')
print(os.path.basename(sys.argv[2]), int(m.sum()), 'tris', np.round(P[u].min(0), 3), np.round(P[u].max(0), 3))
