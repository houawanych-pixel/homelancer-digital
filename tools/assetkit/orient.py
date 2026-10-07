"""orient.py IN.glb OUT.glb [ops] : NEW copy turned so the ship's mirror plane is x = 0 and its long axis lies along Z.
Finds the mirror plane by a full 3D search (handles pitched / rolled / tail-standing pieces).
ops (applied after, in order, comma separated): fz = turn 180 about Y (swap nose/tail), fy = turn 180 about Z (upside down),
  rx = quarter turn about X (long axis was really the up axis), rx- = the other way, cand=N = use the N-th best plane.
Prints the 3x3 matrix (row-major, applied as P @ R.T) so build.py can reuse it."""
import sys, os, json, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read, surf_points
from glbio import write_glb
from scipy.spatial import cKDTree

def find_planes(P, I, nS=3500, free=False):
    S = surf_points(P, I, nS); S = S - (S.min(0) + S.max(0)) / 2; tree = cKDTree(S); diag = np.linalg.norm(np.ptp(S, 0))
    def err(n):
        pr = S @ n; best = 1e9; mid = (pr.min() + pr.max()) / 2; w = np.ptp(pr)
        for c in mid + w * np.array([-0.04, -0.02, 0, 0.02, 0.04]):
            M = S - 2 * np.outer(pr - c, n); e = tree.query(M)[0].mean()
            if e < best: best = e; bc = c
        return best / w, bc
    # hemisphere fibonacci
    N = 500; k = np.arange(N) + 0.5; ph = np.arccos(1 - k / N); th = np.pi * (1 + 5 ** 0.5) * k
    D = np.stack([np.cos(th) * np.sin(ph), np.sin(th) * np.sin(ph), np.cos(ph)], 1)
    w_, v_ = np.linalg.eigh(np.cov(S.T)); a1 = v_[:, 2]; elong = (w_[2] / max(w_[1], 1e-12)) ** 0.5
    def ok(d): return abs(d[1]) < 0.57 and (free or elong < 1.5 or abs(d @ a1) < 0.5)   # near-horizontal normal, across the long axis
    D = np.array([d for d in D if ok(d)])
    E = np.array([err(d)[0] for d in D]); order = np.argsort(E); cands = []
    for i in order:
        if all(abs(D[i] @ c) < 0.94 for c in cands): cands.append(D[i])
        if len(cands) == 4: break
    out = []
    for n in cands:
        best = (err(n)[0], n)
        for step in (0.06, 0.02, 0.007):
            for _ in range(2):
                a = np.cross(best[1], [1, 0, 0]);
                if np.linalg.norm(a) < 0.1: a = np.cross(best[1], [0, 1, 0])
                a /= np.linalg.norm(a); b = np.cross(best[1], a)
                for da in (-step, 0, step):
                    for db in (-step, 0, step):
                        m = best[1] + da * a + db * b; m /= np.linalg.norm(m); e = err(m)[0]
                        if e < best[0] and ok(m): best = (e, m)
        out.append((best[0], best[1], err(best[1])[1]))
    out.sort(key=lambda t: t[0]); return out, S.mean(0) * 0

if __name__ == '__main__':
    P, N, U, I, js, imgs = read(sys.argv[1]); ops = sys.argv[3].split(',') if len(sys.argv) > 3 and sys.argv[3] else []
    ctr = (P.min(0) + P.max(0)) / 2; P = P - ctr
    planes, _ = find_planes(P, I, free='free' in ops); ci = 0
    for o in ops:
        if o.startswith('cand='): ci = int(o[5:])
    e, n, c = planes[ci]
    # long axis inside the plane
    Q = P[::3] - np.outer(P[::3] @ n, n); w, v = np.linalg.eigh(np.cov(Q.T)); z = v[:, 2]; z -= (z @ n) * n; z /= np.linalg.norm(z)
    y = np.cross(z, n); R = np.stack([n, y, z])      # rows = new axes
    if np.linalg.det(R) < 0: R[0] = -R[0]
    for o in ops:
        if o == 'fz': R = np.diag([-1.0, 1, -1]) @ R
        elif o == 'fy': R = np.diag([-1.0, -1, 1]) @ R
        elif o == 'rx': R = np.array([[1.0, 0, 0], [0, 0, -1], [0, 1, 0]]) @ R
        elif o == 'rx-': R = np.array([[1.0, 0, 0], [0, 0, 1], [0, -1, 0]]) @ R
    P2 = P @ R.T; N2 = N @ R.T; P2[:, 0] -= (P2[:, 0].min() + P2[:, 0].max()) / 2 * 0
    P2 -= (P2.min(0) + P2.max(0)) / 2
    write_glb(sys.argv[2], [{"pos": P2, "nrm": N2, "uv": U, "idx": I, "mat": 0}], js['materials'][:1], imgs, 'p')
    json.dump({"R": R.tolist(), "err": [round(float(p[0]) * 100, 2) for p in planes]}, open(sys.argv[2] + '.json', 'w'))
    print(os.path.basename(sys.argv[1]), 'plane errors %', [round(float(p[0]) * 100, 2) for p in planes], 'size', [round(float(x), 3) for x in np.ptp(P2, 0)])
