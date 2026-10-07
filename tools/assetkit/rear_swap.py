"""rear_swap.py SHIP.glb DONOR.glb OUT.glb SHIP_CUT_Z DONOR_CUT_Z [scale] [dy] [overlap]
Thruster repair: cut everything behind z = SHIP_CUT_Z off a levelled, mirrored ship (nose at -Z), close the cut, and graft
on the rear end of another ship of the same set (everything behind z = DONOR_CUT_Z of DONOR), so the ship ends in real
thrusters instead of an upright cannon. Both cuts are closed with a cap. The two textures are packed side by side into one
atlas so the result is still one mesh with one material. Always writes a NEW file."""
import io, os, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
from PIL import Image


def clip_z(P, N, U, I, zc, keep_front):
    """keep z <= zc (keep_front) or z >= zc; crossing triangles are cut; the open cut is closed with a fan cap."""
    s = (zc - P[:, 2]) if keep_front else (P[:, 2] - zc)
    inside = s >= 0; cnt = inside[I].sum(1)
    P2 = [P]; N2 = [N]; U2 = [U]; out = [I[cnt == 3]]; nxt = len(P); newp = []; newn = []; newu = []; newt = []; segs = []
    for tri in I[(cnt > 0) & (cnt < 3)]:
        poly = []; cutpts = []
        for k in range(3):
            a = tri[k]; b = tri[(k + 1) % 3]
            if inside[a]: poly.append(a)
            if inside[a] != inside[b]:
                t = s[a] / (s[a] - s[b]); p = P[a] + (P[b] - P[a]) * t; p[2] = zc
                nn = N[a] + (N[b] - N[a]) * t; nn /= max(np.linalg.norm(nn), 1e-9)
                newp.append(p); newn.append(nn); newu.append(U[a] + (U[b] - U[a]) * t); poly.append(nxt); cutpts.append(nxt); nxt += 1
        for k in range(1, len(poly) - 1): newt.append([poly[0], poly[k], poly[k + 1]])
        if len(cutpts) == 2: segs.append(cutpts)
    if newp:
        P2.append(np.array(newp)); N2.append(np.array(newn)); U2.append(np.array(newu)); out.append(np.array(newt, dtype=np.int64))
    P3 = np.concatenate(P2); N3 = np.concatenate(N2); U3 = np.concatenate(U2); tris = [np.concatenate(out)]
    if segs:   # cap: weld the cut points, split into loops, fan each loop from its centre
        segs = np.array(segs); key = np.round(P3[segs.reshape(-1)][:, :2] / (1e-5 * max(1.0, np.ptp(P[:, 0]))) ).astype(np.int64)
        _, wid = np.unique(key, axis=0, return_inverse=True); wid = wid.reshape(-1, 2); n = wid.max() + 1
        parent = np.arange(n)
        def find(x):
            while parent[x] != x: parent[x] = parent[parent[x]]; x = parent[x]
            return x
        for a, b in wid: parent[find(a)] = find(b)
        root = np.array([find(a) for a in wid[:, 0]]); nz = -1.0 if not keep_front else 1.0   # cap faces the removed side
        capP = []; capN = []; capU = []; capT = []; base = len(P3)
        for r in np.unique(root):
            sg = segs[root == r]; pts = P3[sg.reshape(-1)]; c = pts.mean(0); uv = U3[sg[0, 0]]
            ci = base + len(capP); capP.append(c); capN.append([0, 0, nz]); capU.append(uv)
            for a, b in sg:
                ia = base + len(capP); capP += [P3[a], P3[b]]; capN += [[0, 0, nz]] * 2; capU += [uv, uv]
                w = np.cross(P3[a] - c, P3[b] - c)[2]
                capT.append([ci, ia, ia + 1] if w * nz > 0 else [ci, ia + 1, ia])
        P3 = np.concatenate([P3, np.array(capP)]); N3 = np.concatenate([N3, np.array(capN, float)]); U3 = np.concatenate([U3, np.array(capU)])
        tris.append(np.array(capT, dtype=np.int64))
    I3 = np.concatenate(tris); used, inv = np.unique(I3, return_inverse=True)
    return P3[used], N3[used], U3[used], inv.reshape(-1, 3)


def main():
    a = sys.argv
    zs, zd = float(a[4]), float(a[5]); scale = float(a[6]) if len(a) > 6 else 1.0; dy = float(a[7]) if len(a) > 7 else 0.0
    overlap = float(a[8]) if len(a) > 8 else 0.002
    P, N, U, I, js, imgs = read(a[1]); Pd, Nd, Ud, Id, jsd, imgsd = read(a[2])
    box = os.environ.get('DONOR_BOX')   # "x0,x1,y0,y1": only donor triangles fully inside (drops fin tips that would float)
    if box:
        b = [float(v) for v in box.split(',')]; q = Pd[Id]
        m = ((q[:, :, 0] >= b[0]) & (q[:, :, 0] <= b[1]) & (q[:, :, 1] >= b[2]) & (q[:, :, 1] <= b[3])).all(1); Id = Id[m]
    P, N, U, I = clip_z(P, N, U, I, zs, True)
    Pd, Nd, Ud, Id = clip_z(Pd, Nd, Ud, Id, zd, False)
    Pd = Pd * scale; Pd[:, 2] += zs - zd * scale - overlap; Pd[:, 1] += dy
    # one atlas: ship texture on the left, the donor's used region on the right
    out_imgs = []; T = [Image.open(io.BytesIO(b)).convert('RGB') for b, _ in imgs]; D = [Image.open(io.BytesIO(b)).convert('RGB') for b, _ in imgsd]
    W, H = T[0].size; w, h = D[0].size
    usedd = np.unique(Id); Ub = Ud[usedd]
    u0, v0 = np.floor(Ub.min(0) * [w, h]).astype(int) - 2; u1, v1 = np.ceil(Ub.max(0) * [w, h]).astype(int) + 2
    u0, v0 = max(u0, 0), max(v0, 0); u1, v1 = min(u1, w), min(v1, h); cw, chh = u1 - u0, v1 - v0
    AW, AH = W + cw, max(H, chh)
    for k in range(len(T)):
        A = Image.new('RGB', (AW, AH)); A.paste(T[k], (0, 0)); A.paste(D[min(k, len(D) - 1)].crop((u0, v0, u1, v1)), (W, 0))
        b = io.BytesIO(); A.save(b, 'JPEG', quality=88); out_imgs.append((b.getvalue(), 'image/jpeg'))
    U2 = U * [W / AW, H / AH]; Ud2 = (Ud * [w, h] - [u0, v0] + [W, 0]) / [AW, AH]
    P2 = np.concatenate([P, Pd]); N2 = np.concatenate([N, Nd]); UU = np.concatenate([U2, Ud2]); I2 = np.concatenate([I, Id + len(P)])
    P2[:, 1] -= (P2[:, 1].min() + P2[:, 1].max()) / 2; P2[:, 2] -= (P2[:, 2].min() + P2[:, 2].max()) / 2
    write_glb(a[3], [{"pos": P2, "nrm": N2, "uv": UU, "idx": I2, "mat": 0}], js['materials'][:1], out_imgs, js['nodes'][0].get('name', 'ship'))
    print('%s: ship %d tris + donor rear %d tris, atlas %dx%d, size %s' % (os.path.basename(a[3]), len(I), len(Id), AW, AH, np.round(np.ptp(P2, 0), 4)))


main()
