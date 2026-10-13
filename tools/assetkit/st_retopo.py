"""st_retopo.py ORIGINAL.glb OUT_DIR NAME [--straighten] [--yaw DEG]

Station3D-Retopo v1: one connected game station from a ~2M-triangle original.
  1. weld, drop specks (pieces under SPECK of the bounding size)
  2. optional: straighten (principal axes square to X / Y / Z, thinnest axis up), then a yaw; origin at the core
  3. every loose piece is joined to the main body with struts (a tube with a collar at each end, hull-coloured)
  4. LOD0 / LOD1 / LOD2 by quadric decimation of the welded shape
  5. each LOD unwrapped onto clean UVs (xatlas) and baked from the original: colour + tangent-space normal map
  6. GLB per LOD (JPEG textures), report.json
The original is only read.
"""
import sys, os, json, io, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageFile
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
import fast_simplification, xatlas
from st_load import load, texture
from glbio import write_glb
Image.MAX_IMAGE_PIXELS = None
ImageFile.MAXBLOCK = 1 << 26   # (optimized JPEGs need the whole image in one block)

SPECK = 0.005                        # pieces smaller than this share of the station's bounding size are junk
LODS = [("", 40000, 2048, 8, True), ("_LOD1", 10000, 1024, 6, True), ("_LOD2", 2500, 512, 4, False)]   # name, tris, texture, strut sides, collars
STRUT_SIDES = 8

def log(*a):
    print(time.strftime('%H:%M:%S'), *a, flush=True)

def comps(T, nv):
    a = np.concatenate([T[:, 0], T[:, 1], T[:, 2]]); b = np.concatenate([T[:, 1], T[:, 2], T[:, 0]])
    nc, lab = connected_components(coo_matrix((np.ones(len(a), np.int8), (a, b)), shape=(nv, nv)), directed=False)
    return nc, lab

def area_points(W, T, n, seed=3):
    rng = np.random.default_rng(seed); a = W[T[:, 0]]; b = W[T[:, 1]]; c = W[T[:, 2]]
    ar = np.linalg.norm(np.cross(b - a, c - a), axis=1); t = rng.choice(len(T), n, p=ar / ar.sum())
    u = rng.random(n); v = rng.random(n); f = u + v > 1; u[f] = 1 - u[f]; v[f] = 1 - v[f]
    return a[t] + (b[t] - a[t]) * u[:, None] + (c[t] - a[t]) * v[:, None]

def straighten(W, T):
    """principal axes square to the world axes: thinnest axis up (+Y), longest along Z"""
    S = area_points(W, T, 60000); S = S - S.mean(0)
    w, v = np.linalg.eigh(np.cov(S.T))           # ascending variance
    up, mid, lng = v[:, 0], v[:, 1], v[:, 2]
    if up[1] < 0: up = -up                         # keep it the way up it was closest to
    if lng[2] < 0: lng = -lng
    x = np.cross(up, lng)
    R = np.stack([x, up, lng])                     # rows: new X, Y, Z in old coordinates
    return R

def tube(p0, p1, r, sides=STRUT_SIDES):
    """closed tube from p0 to p1 (radius r): vertices, triangles"""
    ax = p1 - p0; L = np.linalg.norm(ax); ax = ax / max(L, 1e-9)
    t = np.cross(ax, [0, 1, 0] if abs(ax[1]) < 0.9 else [1, 0, 0]); t /= np.linalg.norm(t); bt = np.cross(ax, t)
    ang = np.arange(sides) * 2 * np.pi / sides
    ring = np.cos(ang)[:, None] * t + np.sin(ang)[:, None] * bt
    V = np.concatenate([p0 + ring * r, p1 + ring * r, [p0, p1]])
    F = []
    for i in range(sides):
        j = (i + 1) % sides
        F += [[i, j, sides + j], [i, sides + j, sides + i], [2 * sides, j, i], [2 * sides + 1, sides + i, sides + j]]
    return V, np.array(F)

def strut(pa, pb, r, sides=STRUT_SIDES, collars=True):
    """a strut from body point pa to piece point pb: a tube sunk a little into both, with a wider collar at each end"""
    d = pb - pa; L = np.linalg.norm(d); u = d / max(L, 1e-9)
    sink = max(r * 2.5, L * 0.1)
    parts = [tube(pa - u * sink, pb + u * sink, r, sides)]
    if collars:
        for p, s in ((pa, 1.0), (pb, -1.0)):           # collars: short, wider, at the hull
            parts.append(tube(p - u * s * r * 0.6, p + u * s * r * 0.9, r * 1.6, sides))
    V = []; F = []; base = 0
    for v, f in parts:
        V.append(v); F.append(f + base); base += len(v)
    return np.concatenate(V), np.concatenate(F)

def connect(W, T, CU, tl, nc, diag, log_out):
    """join every loose piece to the main body (or to the nearest piece already joined) with struts"""
    cnt = np.bincount(tl, minlength=nc); order = [int(c) for c in np.argsort(-cnt) if cnt[c] > 0]
    main = order[0]
    joined_v = np.unique(T[tl == main]); tree = cKDTree(W[joined_v])
    # body UVs at a vertex: any corner that uses it
    vuv = np.zeros((len(W), 2)); vuv[T.ravel()] = CU.reshape(-1, 2)
    specs = []
    for c in order[1:]:
        pv = np.unique(T[tl == c]); P = W[pv]
        lo, hi = P.min(0), P.max(0); size = np.linalg.norm(hi - lo); thin = max(np.min(hi - lo), size * 0.05)
        d, j = tree.query(P)
        k = int(np.argmin(d)); gap = float(d[k])
        pairs = [(P[k], W[joined_v[j[k]]])]
        if size > 0.08 * diag:                       # a big piece gets a second strut, well apart from the first
            far = np.linalg.norm(P - P[k], axis=1) > size * 0.45
            if far.any():
                k2 = int(np.argmin(np.where(far, d, np.inf))); pairs.append((P[k2], W[joined_v[j[k2]]]))
        r = float(np.clip(thin * 0.18, diag * 0.0035, diag * 0.012))
        for pp, bp in pairs:
            specs.append((bp, pp, r, vuv[joined_v[tree.query(bp)[1]]]))
        log_out.append({"piece_tris": int(cnt[c]), "piece_size_pct": round(100 * size / diag, 1), "gap_pct": round(100 * gap / diag, 2),
                        "struts": len(pairs), "strut_radius_pct": round(100 * r / diag, 2)})
        joined_v = np.concatenate([joined_v, pv]); tree = cKDTree(W[joined_v])
    return specs

def strut_mesh(specs, sides, collars):
    """all struts as one mesh: V, F, per-corner UV (each strut wears the hull colour where it meets the body)"""
    V = []; F = []; U = []; base = 0
    for bp, pp, r, uv in specs:
        v, f = strut(bp, pp, r, sides, collars)
        V.append(v); F.append(f + base); U.append(np.repeat(uv[None], len(f) * 3, 0).reshape(-1, 3, 2)); base += len(v)
    if not V: return np.zeros((0, 3)), np.zeros((0, 3), np.int64), np.zeros((0, 3, 2))
    return np.concatenate(V), np.concatenate(F), np.concatenate(U)

def vertex_normals(V, F):
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    n = np.zeros_like(V)
    for k in range(3): np.add.at(n, F[:, k], fn)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)

def tangents(V, N, UV, F):
    p0, p1, p2 = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]; t0, t1, t2 = UV[F[:, 0]], UV[F[:, 1]], UV[F[:, 2]]
    e1, e2 = p1 - p0, p2 - p0; d1, d2 = t1 - t0, t2 - t0
    det = d1[:, 0] * d2[:, 1] - d2[:, 0] * d1[:, 1]; det = np.where(np.abs(det) < 1e-14, 1e-14, det)
    tf = (e1 * d2[:, 1:2] - e2 * d1[:, 1:2]) / det[:, None]; bf = (e2 * d1[:, 0:1] - e1 * d2[:, 0:1]) / det[:, None]
    T = np.zeros_like(V); B = np.zeros_like(V)
    for k in range(3): np.add.at(T, F[:, k], tf); np.add.at(B, F[:, k], bf)
    T = T - N * (T * N).sum(1, keepdims=True)
    bad = np.linalg.norm(T, axis=1) < 1e-12
    T[bad] = np.cross(N[bad], [0.0, 1.0, 0.0]) + 1e-6
    T /= np.linalg.norm(T, axis=1, keepdims=True)
    w = np.where((np.cross(N, T) * B).sum(1) < 0, -1.0, 1.0)
    return T, w

def raster(UV, F, R):
    """every texel centre inside a UV triangle: (pixel x, pixel y, triangle, barycentrics)"""
    px = UV * R
    xs = []; ys = []; ts = []; bs = []
    tri = px[F]                                   # (m, 3, 2)
    mn = np.floor(tri.min(1)).astype(int).clip(0, R - 1); mx = np.ceil(tri.max(1)).astype(int).clip(0, R - 1)
    for i in range(len(F)):
        x0, y0 = mn[i]; x1, y1 = mx[i]
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        q = np.stack([gx.ravel() + 0.5, gy.ravel() + 0.5], 1)
        a, b, c = tri[i]
        v0 = b - a; v1 = c - a; v2 = q - a
        den = v0[0] * v1[1] - v1[0] * v0[1]
        if abs(den) < 1e-12: continue
        l1 = (v2[:, 0] * v1[1] - v1[0] * v2[:, 1]) / den; l2 = (v0[0] * v2[:, 1] - v2[:, 0] * v0[1]) / den; l0 = 1 - l1 - l2
        ok = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
        if not ok.any(): continue
        xs.append(gx.ravel()[ok]); ys.append(gy.ravel()[ok]); ts.append(np.full(ok.sum(), i)); bs.append(np.stack([l0[ok], l1[ok], l2[ok]], 1))
    return np.concatenate(xs), np.concatenate(ys), np.concatenate(ts), np.concatenate(bs)

def dilate(img, mask, it=12):
    img = img.copy(); m = mask.copy()
    for _ in range(it):
        acc = np.zeros_like(img, dtype=np.float64); n = np.zeros(m.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sm = np.roll(m, (dy, dx), (0, 1)); si = np.roll(img, (dy, dx), (0, 1))
            acc += si * sm[..., None]; n += sm
        grow = (~m) & (n > 0)
        img[grow] = (acc[grow] / n[grow][:, None]).astype(img.dtype); m = m | grow
    return img

class HighSampler:
    """closest original surface point for any query: dense samples of the original carrying its UV and normal"""
    def __init__(self, W, T, CU, n=6000000, seed=5):
        rng = np.random.default_rng(seed); a = W[T[:, 0]]; b = W[T[:, 1]]; c = W[T[:, 2]]
        cr = np.cross(b - a, c - a); ar = np.linalg.norm(cr, axis=1)
        self.fn = cr / np.maximum(ar, 1e-15)[:, None]
        k = rng.choice(len(T), n, p=ar / ar.sum())
        u = rng.random(n); v = rng.random(n); f = u + v > 1; u[f] = 1 - u[f]; v[f] = 1 - v[f]
        cent = np.arange(len(T))                      # plus every triangle's centre, so small triangles are never missed
        self.P = np.concatenate([a[k] + (b[k] - a[k]) * u[:, None] + (c[k] - a[k]) * v[:, None], (a + b + c) / 3])
        self.UV = np.concatenate([CU[k, 0] * (1 - u - v)[:, None] + CU[k, 1] * u[:, None] + CU[k, 2] * v[:, None], CU.mean(1)])
        self.tri = np.concatenate([k, cent])
        self.tree = cKDTree(self.P)
    def query(self, Q):
        d, j = self.tree.query(Q, workers=-1)
        return self.UV[j], self.fn[self.tri[j]], d

def sample(tex, uv):
    a = np.asarray(tex, dtype=np.float32); h, w = a.shape[:2]
    x = (uv[:, 0] % 1.0) * w - 0.5; y = (uv[:, 1] % 1.0) * h - 0.5
    x0 = np.floor(x).astype(int); y0 = np.floor(y).astype(int); fx = (x - x0)[:, None]; fy = (y - y0)[:, None]
    x0 %= w; y0 %= h; x1 = (x0 + 1) % w; y1 = (y0 + 1) % h
    return (a[y0, x0] * (1 - fx) * (1 - fy) + a[y0, x1] * fx * (1 - fy) + a[y1, x0] * (1 - fx) * fy + a[y1, x1] * fx * fy)

def bake(V, F, N, TG, TW, UV, R, hs, tex):
    xs, ys, ts, bs = raster(UV, F, R)
    f = F[ts]
    pos = (V[f] * bs[:, :, None]).sum(1)
    n = (N[f] * bs[:, :, None]).sum(1); n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    t = (TG[f] * bs[:, :, None]).sum(1); t -= n * (t * n).sum(1, keepdims=True); t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-12)
    w = TW[f[:, 0]]
    b = np.cross(n, t) * w[:, None]
    huv, hn, dist = hs.query(pos)
    hn = np.where(((hn * n).sum(1) < 0)[:, None], -hn, hn)     # (the original's faces can be wound either way)
    col = sample(tex, huv)
    ts_n = np.stack([(hn * t).sum(1), (hn * b).sum(1), (hn * n).sum(1)], 1)
    ts_n /= np.maximum(np.linalg.norm(ts_n, axis=1, keepdims=True), 1e-12)
    C = np.zeros((R, R, 3), np.float32); NM = np.zeros((R, R, 3), np.float32); M = np.zeros((R, R), bool)
    C[ys, xs] = col; NM[ys, xs] = ts_n * 0.5 + 0.5; M[ys, xs] = True
    NM[~M] = (0.5, 0.5, 1.0)
    C = dilate(C, M); NM = dilate(NM, M)
    return C, NM, float(M.mean()), float(np.percentile(dist, 95))

def jpeg(arr, q, sub=2):
    b = io.BytesIO(); Image.fromarray(np.clip(arr * (255.0 if arr.max() <= 1.0001 else 1.0), 0, 255).astype(np.uint8)).save(b, 'JPEG', quality=q, subsampling=sub, optimize=True); return b.getvalue()

def floating(V, F, diag, eps=0.002):
    """pieces that touch nothing: a piece is attached when some of its surface comes within eps (share of the bounding
    size) of another piece. Returns (pieces, floating groups after joining touching ones)."""
    k, lab = comps(F, len(V))
    if k == 1: return 1, 0
    fl = lab[F[:, 0]]
    # surface samples at an even density over everything (a sparse body would miss where a strut goes into it)
    a = V[F[:, 0]]; b = V[F[:, 1]]; c_ = V[F[:, 2]]
    ar = np.linalg.norm(np.cross(b - a, c_ - a), axis=1); spacing = eps * diag * 0.7
    n = int(min(3_000_000, max(50_000, ar.sum() / 2 / spacing ** 2)))
    rng = np.random.default_rng(11); t = rng.choice(len(F), n, p=ar / ar.sum())
    u = rng.random(n); v = rng.random(n); f_ = u + v > 1; u[f_] = 1 - u[f_]; v[f_] = 1 - v[f_]
    pts = a[t] + (b[t] - a[t]) * u[:, None] + (c_[t] - a[t]) * v[:, None]
    vl = np.zeros(len(V), np.int64); vl[F.ravel()] = np.repeat(fl, 3)
    S = np.concatenate([pts, V]); L = np.concatenate([fl[t], vl]); tree = cKDTree(S)
    pairs = tree.query_pairs(eps * diag, output_type='ndarray')
    a = L[pairs[:, 0]]; b = L[pairs[:, 1]]; m = a != b
    g, glab = connected_components(coo_matrix((np.ones(m.sum()), (a[m], b[m])), shape=(k, k)), directed=False)
    floating.last = (fl, glab)
    return k, g - 1

def repair(V, F, diag, uvs_of):
    """after decimation: touching groups other than the biggest either go (smaller than 2 % of the size: invisible at
    that distance) or get a strut to the nearest point of the biggest group. Returns V, F, struts added, bits dropped."""
    k, flo = floating(V, F, diag)
    if flo == 0: return V, F, 0, 0
    fl, glab = floating.last
    g = glab[fl]                                   # touching group of each face
    cnt = np.bincount(g); main = int(np.argmax(cnt))
    keep = np.ones(len(F), bool); add = []; dropped = 0
    mv = np.unique(F[g == main]); tree = cKDTree(V[mv])
    for c in range(len(cnt)):
        if c == main or cnt[c] == 0: continue
        vv = np.unique(F[g == c]); P = V[vv]; size = np.linalg.norm(P.max(0) - P.min(0))
        if size < 0.02 * diag:
            keep &= g != c; dropped += 1; continue
        d, j = tree.query(P); kk = int(np.argmin(d))
        r = float(np.clip(size * 0.04, diag * 0.0035, diag * 0.01))
        add.append((V[mv[j[kk]]], P[kk], r, None))
    F = F[keep]
    used, inv = np.unique(F, return_inverse=True); V = V[used]; F = inv.reshape(-1, 3)
    for bp, pp, r, _ in add:
        sv, sf = strut(bp, pp, r, 6, False)
        F = np.concatenate([F, sf + len(V)]); V = np.concatenate([V, sv])
    return V, F, len(add), dropped

def main():
    src, out, name = sys.argv[1], sys.argv[2], sys.argv[3]
    straight = '--straighten' in sys.argv
    yaw = float(sys.argv[sys.argv.index('--yaw') + 1]) if '--yaw' in sys.argv else 0.0
    os.makedirs(out, exist_ok=True)
    rep = {"name": name, "source": os.path.basename(src)}
    log('load', name)
    W, T, CU, CN, tl, nc = load(src)
    tex = texture(src)
    lo, hi = W.min(0), W.max(0); diag = float(np.linalg.norm(hi - lo))
    cnt = np.bincount(tl, minlength=nc)
    sizes = np.zeros(nc)
    for c in np.nonzero(cnt)[0]:
        v = np.unique(T[tl == c]); sizes[c] = np.linalg.norm(W[v].max(0) - W[v].min(0))
    junk = sizes < SPECK * diag
    rep["original_tris"] = int(len(T)); rep["pieces"] = int(nc); rep["specks_removed"] = int(junk.sum()); rep["speck_tris"] = int(cnt[junk].sum())
    keep = ~junk[tl]
    T = T[keep]; CU = CU[keep]; tl = tl[keep]
    used, inv = np.unique(T, return_inverse=True); W = W[used]; T = inv.reshape(-1, 3)
    _, tl = np.unique(tl, return_inverse=True); nc = int(tl.max()) + 1
    # orientation: square to the axes when asked, the yaw, origin at the core (the main body's middle)
    if straight:
        R = straighten(W, T); W = W @ R.T; rep["straightened"] = True
    if yaw:
        a = np.radians(yaw); Ry = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]]); W = W @ Ry.T; rep["yaw"] = yaw
    mainc = np.argmax(np.bincount(tl)); mv = np.unique(T[tl == mainc])
    W = W - (W[mv].min(0) + W[mv].max(0)) / 2
    # loose pieces joined with struts
    joins = []
    specs = connect(W, T, CU, tl, nc, diag, joins)
    rep["loose_parts"] = joins
    SV, SF, SU = strut_mesh(specs, STRUT_SIDES, True)
    HW = np.concatenate([W, SV]); HT = np.concatenate([T, SF + len(W)]); HU = np.concatenate([CU, SU])
    pcs, flo = floating(HW, HT, diag)
    rep["high_floating"] = int(flo)
    log('high mesh', len(T), 'tris,', len(joins), 'loose parts joined; mesh pieces', pcs, 'floating', flo)
    hs = HighSampler(HW, HT, HU)
    rep["lods"] = []
    for suffix, target, res, sides, collars in LODS:
        log('LOD', suffix or '0', target)
        LV, LF, _ = strut_mesh(specs, sides, collars)
        want = max(target // 2, target - len(LF))
        V, F = fast_simplification.simplify(W.astype(np.float32), T.astype(np.int64), target_count=want, agg=7, lossless=False) if len(T) > want else (W.astype(np.float32), T)
        F = np.asarray(F, np.int64); V = np.asarray(V, np.float64)
        # tiny bits the decimation broke off (not struts: those stay joined) go
        k, lab = comps(F, len(V))
        if k > 1:
            fl = lab[F[:, 0]]; big = np.argmax(np.bincount(fl)); szs = {}
            keepf = np.ones(len(F), bool)
            for c in set(fl.tolist()) - {big}:
                vv = np.unique(F[fl == c])
                if np.linalg.norm(V[vv].max(0) - V[vv].min(0)) < SPECK * diag: keepf &= fl != c
            F = F[keepf]
        used, inv = np.unique(F, return_inverse=True); V = V[used]; F = inv.reshape(-1, 3)
        if len(LF): F = np.concatenate([F, LF + len(V)]); V = np.concatenate([V, LV])
        V, F, fixed, dropped = repair(V, F, diag, None)
        k, _ = comps(F, len(V))
        vm, idx, uv = xatlas.parametrize(V.astype(np.float32), F.astype(np.uint32))
        V2 = V[vm]; F2 = idx.astype(np.int64); UV2 = uv.astype(np.float64)
        N2 = vertex_normals(V, F)[vm]
        TG, TW = tangents(V2, N2, UV2, F2)
        C, NM, cover, d95 = bake(V2, F2, N2, TG, TW, UV2, res, hs, tex)
        fn = '%s%s.glb' % (name, suffix) if suffix else '%s_game.glb' % name
        fn = '%s_game%s.glb' % (name, suffix) if suffix else fn
        mat = {"name": "hull", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.35, "roughnessFactor": 0.6},
               "normalTexture": {"index": 1}}
        write_glb_tan(os.path.join(out, fn), V2, N2, np.concatenate([TG, TW[:, None]], 1), UV2, F2, mat, [(jpeg(C, 84), 'image/jpeg'), (jpeg(NM, 86, 0), 'image/jpeg')], name)
        pieces, flo = floating(V, F, diag)
        rep["lods"].append({"file": fn, "tris": int(len(F2)), "texture": res, "lod_struts_added": fixed, "lod_bits_dropped": dropped, "mesh_pieces": int(pieces), "floating": int(flo), "uv_cover": round(cover, 3), "bake_dist95_pct": round(100 * d95 / diag, 2),
                            "kb": os.path.getsize(os.path.join(out, fn)) // 1024})
        log(rep["lods"][-1])
    vlo, vhi = HW.min(0), HW.max(0)
    rep["size"] = [round(float(x), 3) for x in (vhi - vlo)]
    json.dump(rep, open(os.path.join(out, name + '_report.json'), 'w'), indent=1)
    log('done', name)

def write_glb_tan(path, V, N, TAN, UV, F, mat, images, name):
    import struct
    bin_ = bytearray(); views = []; accs = []
    def view(b, target=None):
        while len(bin_) % 4: bin_.append(0)
        v = {"buffer": 0, "byteOffset": len(bin_), "byteLength": len(b)}
        if target: v["target"] = target
        bin_.extend(b); views.append(v); return len(views) - 1
    def acc(arr, ctype, typ, target, minmax=False):
        a = {"bufferView": view(arr.tobytes(), target), "componentType": ctype, "count": int(len(arr)), "type": typ}
        if minmax: a["min"] = [float(x) for x in arr.min(0)]; a["max"] = [float(x) for x in arr.max(0)]
        accs.append(a); return len(accs) - 1
    at = {"POSITION": acc(np.ascontiguousarray(V, np.float32), 5126, "VEC3", 34962, True),
          "NORMAL": acc(np.ascontiguousarray(N, np.float32), 5126, "VEC3", 34962),
          "TANGENT": acc(np.ascontiguousarray(TAN, np.float32), 5126, "VEC4", 34962),
          "TEXCOORD_0": acc(np.ascontiguousarray(UV, np.float32), 5126, "VEC2", 34962)}
    prim = {"attributes": at, "indices": acc(np.ascontiguousarray(F, np.uint32).reshape(-1), 5125, "SCALAR", 34963), "material": 0}
    imgs = [{"bufferView": view(b), "mimeType": m} for b, m in images]
    js = {"asset": {"version": "2.0", "generator": "homelancer station retopo v1"}, "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"name": name, "mesh": 0}], "meshes": [{"name": name, "primitives": [prim]}], "materials": [mat],
          "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}], "images": imgs,
          "textures": [{"source": k, "sampler": 0} for k in range(len(imgs))],
          "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}]}
    jb = json.dumps(js, separators=(",", ":")).encode()
    while len(jb) % 4: jb += b" "
    while len(bin_) % 4: bin_.append(0)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, 12 + 8 + len(jb) + 8 + len(bin_)))
        f.write(struct.pack("<I", len(jb)) + b"JSON" + jb)
        f.write(struct.pack("<I", len(bin_)) + b"BIN\x00" + bytes(bin_))

if __name__ == '__main__':
    main()
