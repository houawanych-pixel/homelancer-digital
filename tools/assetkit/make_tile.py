"""make_tile.py IN OUT AXIS_A min max AXIS_B min max [mirror]
Cut a rectangle out of a piece with exact planes (triangles crossing an edge are cut ON the edge, so the tile is
watertight there), along two axes (x / y / z). With "mirror" the tile is mirrored into a 2 x 2 block: every edge then
meets its own mirror image, so copies laid side by side join with no seam. Centred on the cut rectangle. NEW file."""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read, clip_half
from glbio import write_glb
P, N, U, I, js, imgs = read(sys.argv[1])
ax = {'x': 0, 'y': 1, 'z': 2}
cuts = [(ax[sys.argv[3]], float(sys.argv[4]), float(sys.argv[5])), (ax[sys.argv[6]], float(sys.argv[7]), float(sys.argv[8]))]
mirror = len(sys.argv) > 9 and sys.argv[9] == 'mirror'
def clip_axis(P, N, U, I, a, c, sign):
    perm = [a] + [k for k in range(3) if k != a]; inv = np.argsort(perm)
    P2, N2, U2, I2 = clip_half(P[:, perm], N[:, perm], U, I, c, sign)
    return P2[:, inv], N2[:, inv], U2, I2
for a, lo, hi in cuts:
    P, N, U, I = clip_axis(P, N, U, I, a, lo, 1)
    P, N, U, I = clip_axis(P, N, U, I, a, hi, -1)
for a, lo, hi in cuts: P[:, a] -= (lo + hi) / 2
if mirror:
    parts = [(P, N, I)]
    for a, lo, hi in cuts:
        w = hi - lo; new = []
        for (Pp, Np, Ip) in parts:
            Pm = Pp.copy(); Pm[:, a] = -Pm[:, a]; Nm = Np.copy(); Nm[:, a] = -Nm[:, a]
            Pa = Pp.copy(); Pa[:, a] -= w / 2; Pm[:, a] += w / 2
            new += [(Pa, Np, Ip), (Pm, Nm, Ip[:, ::-1])]
        parts = new
    PP, NN, UU, II = [], [], [], []; base = 0
    for (Pp, Np, Ip) in parts:
        PP.append(Pp); NN.append(Np); UU.append(U); II.append(Ip + base); base += len(Pp)
    P, N, U, I = np.concatenate(PP), np.concatenate(NN), np.concatenate(UU), np.concatenate(II)
write_glb(sys.argv[2], [{"pos": P, "nrm": N, "uv": U, "idx": I, "mat": 0}], js['materials'][:1], imgs, 'tile')
print(os.path.basename(sys.argv[2]), len(I), 'tris', np.round(P.min(0), 3), np.round(P.max(0), 3))
