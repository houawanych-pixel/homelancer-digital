"""orient_struct.py IN.glb OUT.glb [yaw|auto] [front: auto|+x|-x|+z|-z|none] [dropback 0|1]
Structure piece (wall, panel, pillar) -> NEW copy standing upright, square to the axes, its detailed FRONT facing +Z,
centred in X/Z with its bottom at y = 0. dropback=1 removes the flat back face (the side against the outer wall that
nobody sees) to save triangles; the edges stay where they were, so pieces still meet with no gaps."""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
P, N, U, I, js, imgs = read(sys.argv[1])
yaw = sys.argv[3] if len(sys.argv) > 3 else 'auto'; front = sys.argv[4] if len(sys.argv) > 4 else 'auto'
drop = len(sys.argv) > 5 and sys.argv[5] == '1'
def roty(a):
    c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
tri = P[I]; area = np.linalg.norm(np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]), axis=1) / 2
fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
if yaw == 'auto':
    # the turn that squares the big flat faces to the axes: area-weighted horizontal normals, angle folded to 90 deg
    h = fn[:, [0, 2]]; hl = np.linalg.norm(h, axis=1); m = hl > 0.7
    ang = np.arctan2(h[m, 1], h[m, 0]); w = area[m] * hl[m]
    z = (w * np.exp(4j * ang)).sum(); a = -np.angle(z) / 4.0
elif yaw == 'pca':
    # the piece's overall line (both halves of a bent unit) along X
    S = c0 = P[I].mean(1)[:, [0, 2]]; w_ = area / area.sum(); mu = (S * w_[:, None]).sum(0)
    C = ((S - mu) * w_[:, None]).T @ (S - mu); ev, vv = np.linalg.eigh(C); mj = vv[:, 1]
    a = np.arctan2(mj[1], mj[0])   # turning by +a about Y brings the major axis onto +X
else:
    a = np.radians(float(yaw))
R = roty(a); P = P @ R.T; N = N @ R.T; fn = fn @ R.T
c = P[I].mean(1); lo = P.min(0); hi = P.max(0); size = hi - lo
dirs = {'+x': (0, 1), '-x': (0, -1), '+z': (2, 1), '-z': (2, -1)}
def flat_at(d):
    ax, sg = dirs[d]; edge = hi[ax] if sg > 0 else lo[ax]
    m = (fn[:, ax] * sg > 0.9) & (np.abs(c[:, ax] - edge) < 0.06 * size[ax] + 1e-6)
    return area[m].sum() / max(area.sum(), 1e-12), int(((fn[:, ax] * sg) > 0.3).sum())
stats = {d: flat_at(d) for d in dirs}
if front == 'detail':   # the side more triangles face is the front (only +z / -z after a pca turn)
    front = '+z' if stats['+z'][1] >= stats['-z'][1] else '-z'
if front == 'auto':
    back = max(dirs, key=lambda d: stats[d][0] / (1 + stats[d][1] / len(I) * 4))   # big flat area, few triangles = the back
    front = {'+x': '-x', '-x': '+x', '+z': '-z', '-z': '+z'}[back]
if front != 'none':
    turn = {'+z': 0, '-z': np.pi, '+x': np.pi / 2, '-x': -np.pi / 2}[front]   # bring that side round to +Z
    R2 = roty(-turn) if front in ('+x', '-x') else roty(turn)
    # check: R2 @ front_vector must be +Z
    fv = {'+x': [1, 0, 0], '-x': [-1, 0, 0], '+z': [0, 0, 1], '-z': [0, 0, -1]}[front]
    if (R2 @ np.array(fv, float))[2] < 0.5: R2 = roty(turn) if front in ('+x', '-x') else roty(-turn)
    P = P @ R2.T; N = N @ R2.T; fn = fn @ R2.T
lo = P.min(0); hi = P.max(0)
P[:, 0] -= (lo[0] + hi[0]) / 2; P[:, 2] -= (lo[2] + hi[2]) / 2; P[:, 1] -= lo[1]
keep = np.ones(len(I), bool)
if drop and front != 'none':
    c = P[I].mean(1); zmin = P[:, 2].min(); depth = np.ptp(P[:, 2])
    keep = ~((fn[:, 2] < -0.5) & (c[:, 2] < zmin + 0.45 * depth))   # faces looking backwards, in the back half
I2 = I[keep]; u, inv = np.unique(I2, return_inverse=True)
write_glb(sys.argv[2], [{"pos": P[u], "nrm": N[u], "uv": U[u], "idx": inv.reshape(-1, 3), "mat": 0}], js['materials'][:1], imgs, js['nodes'][0].get('name', 'piece'))
print('%s yaw %.1f front %s tris %d -> %d size %s' % (os.path.basename(sys.argv[2]), np.degrees(a), front, len(I), len(I2), np.round(np.ptp(P[u], 0), 3)))
