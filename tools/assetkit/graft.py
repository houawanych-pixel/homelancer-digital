"""graft.py SHIP.glb PART.glb OUT.glb SCALE X Y Z [nose=K:Z0] : bolt a part (a barrel, a pod) onto a levelled, mirrored
ship at (X, Y, Z) and again mirrored at (-X, Y, Z), so the ship stays symmetric. The part keeps its own heading (its -Z
is the ship's forward). The two textures are packed side by side into one atlas: still one mesh, one material.
PART_DROP="x0,x1,y0,y1,z0,z1" (in the part's own units) removes triangles whose centre is in the box (a turret's stand).
nose=K:Z0 also pulls the nose back: everything ahead of z = Z0 is squeezed toward Z0 by the factor K (0.7 = 30 % shorter).
Always writes a NEW file."""
import io, os, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
from PIL import Image
a = sys.argv; sc, x, y, z = [float(v) for v in a[4:8]]
P, N, U, I, js, imgs = read(a[1]); Pp, Np, Up, Ip, jsp, imgsp = read(a[2])
for o in a[8:]:
    if o.startswith('nose='):
        k, z0 = [float(v) for v in o[5:].split(':')]; m = P[:, 2] < z0; P[m, 2] = z0 + (P[m, 2] - z0) * k
box = os.environ.get('PART_DROP')
if box:
    b = [float(v) for v in box.split(',')]; c = Pp[Ip].mean(1)
    Ip = Ip[~((c[:, 0] >= b[0]) & (c[:, 0] <= b[1]) & (c[:, 1] >= b[2]) & (c[:, 1] <= b[3]) & (c[:, 2] >= b[4]) & (c[:, 2] <= b[5]))]
used, inv = np.unique(Ip, return_inverse=True); Pp, Np, Up, Ip = Pp[used], Np[used], Up[used], inv.reshape(-1, 3)
Pp = (Pp - (Pp.min(0) + Pp.max(0)) / 2) * sc
R = Pp + [x, y, z]; L = Pp * [-1, 1, 1] + [-x, y, z]; NL = Np * [-1, 1, 1]
T = [Image.open(io.BytesIO(b)).convert('RGB') for b, _ in imgs]; D = [Image.open(io.BytesIO(b)).convert('RGB') for b, _ in imgsp]
W, H = T[0].size; w, h = D[0].size; k = min(1.0, 256.0 / max(w, h)); w2, h2 = max(4, round(w * k)), max(4, round(h * k))   # a small part: 256 px is plenty
AW, AH = W + w2, max(H, h2); out = []
for i in range(len(T)):
    A = Image.new('RGB', (AW, AH)); A.paste(T[i], (0, 0)); A.paste(D[min(i, len(D) - 1)].resize((w2, h2), Image.LANCZOS), (W, 0))
    o = io.BytesIO(); A.save(o, 'JPEG', quality=88); out.append((o.getvalue(), 'image/jpeg'))
U2 = U * [W / AW, H / AH]; Up2 = (Up * [w2, h2] + [W, 0]) / [AW, AH]
P2 = np.concatenate([P, R, L]); N2 = np.concatenate([N, Np, NL]); UU = np.concatenate([U2, Up2, Up2])
I2 = np.concatenate([I, Ip + len(P), Ip[:, ::-1] + len(P) + len(R)])
P2[:, 1] -= (P2[:, 1].min() + P2[:, 1].max()) / 2; P2[:, 2] -= (P2[:, 2].min() + P2[:, 2].max()) / 2
write_glb(a[3], [{"pos": P2, "nrm": N2, "uv": UU, "idx": I2, "mat": 0}], js['materials'][:1], out, js['nodes'][0].get('name', 'ship'))
print('%s: %d tris, size %s' % (os.path.basename(a[3]), len(I2), np.round(np.ptp(P2, 0), 4)))
