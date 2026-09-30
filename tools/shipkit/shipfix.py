#!/usr/bin/env python3
"""shipfix — small geometry repairs on an exported ship GLB (after `shipkit.py export`).

  shipfix.py in.glb out.glb --delete "x0,x1,y0,y1,z0,z1" [--delete ...] [--mirror-x]
                            --glass  "x0,x1,y0,y1,z0,z1[,shrink]"

--delete  removes every triangle whose centre lies in the box (open doors, landing gear, loose parts).
--mirror-x also applies each delete box mirrored across x = 0 (both sides of a symmetric ship).
--glass   builds a tinted glass shell inside an open canopy cage: convex hull of the vertices in the box,
          shrunk toward its centre (default 0.9) so the frame bars stay in front of it.
"""
import argparse, json, os, sys
import numpy as np
from scipy.spatial import ConvexHull
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as sk


def box(s):
    v = [float(x) for x in s.split(",")]
    return v


def fill_holes(pos, uv, tri, tmat, boxes, report):
    """Find open boundary loops (edges used by one triangle, after welding UV seams) and fan-fill the
    ones centred inside a box. The patch reuses an existing vertex's UV (nearest hull colour)."""
    q = np.round(pos / 1e-6).astype(np.int64)
    _, weld = np.unique(q, axis=0, return_inverse=True); weld = weld.reshape(-1)
    rep = {}
    for i, w in enumerate(weld):
        rep.setdefault(w, i)
    wt = weld[tri]
    e = np.concatenate([wt[:, [0, 1]], wt[:, [1, 2]], wt[:, [2, 0]]])
    key = np.sort(e, 1)
    uk, inv, cnt = np.unique(key, axis=0, return_inverse=True, return_counts=True)
    bmask = cnt[inv.reshape(-1)] == 1
    be = e[bmask]                      # directed boundary edges
    nxt = {}
    for a_, b_ in be:
        nxt.setdefault(a_, []).append(b_)
    seen = set(); loops = []
    for start in list(nxt.keys()):
        if start in seen: continue
        loop = [start]; seen.add(start); cur = start
        for _ in range(100000):
            nb = [v for v in nxt.get(cur, []) if v not in seen or v == start]
            if not nb: break
            cur = nb[0]
            if cur == start: loops.append(loop); break
            loop.append(cur); seen.add(cur)
    new_t, new_m = [], []
    filled = 0
    for lp in loops:
        idx = np.array([rep[v] for v in lp])
        c = pos[idx].mean(0)
        if not any(b[0] <= c[0] <= b[1] and b[2] <= c[1] <= b[3] and b[4] <= c[2] <= b[5] for b in boxes):
            continue
        if len(idx) < 3 or len(idx) > 400: continue
        # fan around the loop's first vertex (reversed winding closes the hole outward)
        for k in range(1, len(idx) - 1):
            new_t.append([idx[0], idx[k + 1], idx[k]]); new_m.append(tmat[0])
        filled += 1
    report["holes_filled"] = filled
    report["open_loops_total"] = len(loops)
    return np.array(new_t, dtype=np.int64).reshape(-1, 3), np.array(new_m, dtype=np.int64)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("glb"); ap.add_argument("out")
    ap.add_argument("--delete", action="append", default=[])
    ap.add_argument("--mirror-x", action="store_true")
    ap.add_argument("--glass", action="append", default=[])
    ap.add_argument("--fill", action="append", default=[], help="close open holes whose centre is inside this box")
    ap.add_argument("--panel", action="append", default=[],
                    help="x,y0,y1,z0,z1,sx,sy,sz : flat side panel at plane x covering y/z range, coloured like the hull vertex nearest (sx,sy,sz)")
    ap.add_argument("--clone", action="append", default=[],
                    help="x0,x1,y0,y1,z0,z1,dz,count,cz0,cz1 : copy outward-facing hull triangles in the box, shifted by dz "
                         "count times, keeping copies whose centre z is in [cz0,cz1] (patches an opening with real plating)")
    ap.add_argument("--name", default="ship")
    a = ap.parse_args()
    g, js, binc = sk.load_geometry(a.glb)
    pos, nrm, uv, tri, tmat = g["pos"], g["nrm"], g["uv"], g["tri"], g["tmat"]
    cen = pos[tri].mean(1)
    keep = np.ones(len(tri), bool)
    boxes = [box(b) for b in a.delete]
    if a.mirror_x:
        boxes += [[-b[1], -b[0]] + b[2:] for b in boxes]
    report = {"deleted": []}
    for b in boxes:
        m = (cen[:, 0] >= b[0]) & (cen[:, 0] <= b[1]) & (cen[:, 1] >= b[2]) & (cen[:, 1] <= b[3]) & (cen[:, 2] >= b[4]) & (cen[:, 2] <= b[5])
        report["deleted"].append(int((m & keep).sum()))
        keep &= ~m
    fills = [box(b) for b in a.fill]
    if a.mirror_x:
        fills += [[-b[1], -b[0]] + b[2:] for b in fills]
    if fills:
        tri_k = tri[keep]; tm_k = tmat[keep]
        new_t, new_m = fill_holes(pos, uv, tri_k, tm_k, fills, report)
        if len(new_t):
            tri = np.vstack([tri[keep], new_t]); tmat = np.concatenate([tmat[keep], new_m])
            keep = np.ones(len(tri), bool)
    mats, images, mat_map = sk.remap_materials(js, binc, sorted(set(int(x) for x in tmat)), 0)
    surfaces = []
    for mi in sorted(set(int(x) for x in tmat[keep])):
        p, n, u, t = sk.compact(pos, nrm, uv, tri[keep & (tmat == mi)])
        surfaces.append((p, n, u, t, mat_map.get(mi, -1)))
    clones = [box(b) for b in a.clone]
    if a.mirror_x:
        clones += [[-b[1], -b[0]] + b[2:] for b in clones]
    base = tri[keep]; base_m = tmat[keep]
    bc = pos[base].mean(1)
    bn = np.cross(pos[base[:, 1]] - pos[base[:, 0]], pos[base[:, 2]] - pos[base[:, 0]])
    bn /= np.maximum(np.linalg.norm(bn, axis=1, keepdims=True), 1e-12)
    for b in clones:
        x0, x1, y0, y1, z0, z1, dz, count, cz0, cz1 = b
        side = -1.0 if x1 <= 0 else 1.0
        m = (bc[:, 0] >= x0) & (bc[:, 0] <= x1) & (bc[:, 1] >= y0) & (bc[:, 1] <= y1) & (bc[:, 2] >= z0) & (bc[:, 2] <= z1) & (bn[:, 0] * side > 0.3)
        src = base[m]
        for k in range(1, int(count) + 1):
            sh = np.array([0, 0, dz * k])
            cz = bc[m][:, 2] + dz * k
            sel = (cz >= cz0) & (cz <= cz1)
            if not sel.any(): continue
            t = src[sel]
            P = pos[t].reshape(-1, 3) + sh
            N = nrm[t].reshape(-1, 3); U = uv[t].reshape(-1, 2)
            T = np.arange(len(P)).reshape(-1, 3)
            surfaces.append((P, N, U, T, mat_map.get(int(base_m[0]), 0)))
            report.setdefault("cloned_tris", 0); report["cloned_tris"] += int(len(T))
    panels = [box(b) for b in a.panel]
    if a.mirror_x:
        panels += [[-b[0], b[1], b[2], b[3], b[4], -b[5], b[6], b[7]] for b in panels]
    if panels:
        # hull colour = average texture colour of outward-facing triangles near each panel
        from PIL import Image, ImageDraw, ImageFilter
        import io
        base = tri[keep]
        cols = sk.tri_colours({"uv": uv}, js, binc, base)
        bcen = pos[base].mean(1)
        plate_img = {}
    for b in panels:
        x, y0, y1, z0, z1 = b[:5]
        near = (np.abs(bcen[:, 0] - x) < 0.04) & (bcen[:, 1] > y0 - 0.03) & (bcen[:, 1] < y1 + 0.03) & (
            (np.abs(bcen[:, 2] - z0) < 0.03) | (np.abs(bcen[:, 2] - z1) < 0.03))
        c = np.median(cols[near], 0) if near.any() else np.array([200, 200, 205.0])
        key = tuple(int(v) for v in c)
        if key not in plate_img:
            W, H = 512, 256
            rng = np.random.default_rng(7)
            base_arr = np.ones((H, W, 3)) * c
            noise = rng.normal(0, 1, (H // 8, W // 8, 1))
            noise = np.asarray(Image.fromarray(((noise[..., 0] + 3) * 40).clip(0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), float)[..., None] / 255.0
            base_arr = base_arr * (0.8 + 0.12 * noise)
            streak = rng.normal(0, 1, (1, W // 6))                      # vertical grime streaks like the hull
            streak = np.asarray(Image.fromarray(((streak + 3) * 40).clip(0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), float)[..., None] / 255.0
            fade = np.linspace(0.6, 1.0, H)[:, None, None]
            base_arr = base_arr * (1.0 - 0.18 * streak * fade)
            im = Image.fromarray(base_arr.clip(0, 255).astype(np.uint8))
            d = ImageDraw.Draw(im)
            dark = tuple(int(v * 0.62) for v in c); lite = tuple(min(255, int(v * 0.95)) for v in c)
            for xx in (0, 170, 341, 511):                       # vertical plate seams
                d.line([(xx, 0), (xx, H)], fill=dark, width=3); d.line([(xx + 3, 0), (xx + 3, H)], fill=lite, width=1)
            for yy in (0, 128, 255):
                d.line([(0, yy), (W, yy)], fill=dark, width=3); d.line([(0, yy + 3), (W, yy + 3)], fill=lite, width=1)
            for xx in range(20, W, 40):                          # rivets along seams
                for yy in (10, 118, 138, 246):
                    d.ellipse([xx - 2, yy - 2, xx + 2, yy + 2], fill=dark)
            d.rectangle([200, 40, 310, 88], outline=dark, width=3)   # small access panel
            im = im.filter(ImageFilter.GaussianBlur(1.0))
            buf = io.BytesIO(); im.save(buf, "JPEG", quality=90)
            images.append((buf.getvalue(), "image/jpeg"))
            mats.append({"name": "hull_plate", "pbrMetallicRoughness": {"baseColorTexture": {"index": len(images) - 1},
                         "metallicFactor": 0.35, "roughnessFactor": 0.55}})
            plate_img[key] = len(mats) - 1
        mi = plate_img[key]
        ys = np.linspace(y0, y1, 4); zs = np.linspace(z0, z1, 5)
        P = np.array([[x, yy, zz] for yy in ys for zz in zs])
        U = np.array([[(zz - z0) / (z1 - z0), (yy - y0) / (y1 - y0)] for yy in ys for zz in zs])
        T = []
        for i in range(3):
            for j in range(4):
                a0 = i * 5 + j; a1 = a0 + 1; b0 = a0 + 5; b1 = b0 + 1
                T += [[a0, b0, a1], [a1, b0, b1]]
        T = np.array(T)
        outward = np.array([np.sign(x) or 1.0, 0, 0])
        fn = np.cross(P[T[0, 1]] - P[T[0, 0]], P[T[0, 2]] - P[T[0, 0]])
        if fn @ outward < 0:
            T = T[:, [0, 2, 1]]
        N = np.tile(outward, (len(P), 1))
        surfaces.append((P, N, U, T, mi))
        surfaces.append((P.copy(), -N, U.copy(), T[:, [0, 2, 1]], mi))
        report.setdefault("panels", 0); report["panels"] += 1
    for gs in a.glass:
        b = box(gs)
        shrink = b[6] if len(b) > 6 else 0.9
        m = (pos[:, 0] >= b[0]) & (pos[:, 0] <= b[1]) & (pos[:, 1] >= b[2]) & (pos[:, 1] <= b[3]) & (pos[:, 2] >= b[4]) & (pos[:, 2] <= b[5])
        pts = pos[m]
        c = pts.mean(0)
        pts = c + (pts - c) * shrink
        h = ConvexHull(pts)
        gp = pts[h.vertices]
        remap = {v: i for i, v in enumerate(h.vertices)}
        gt = np.array([[remap[v] for v in f] for f in h.simplices])
        # make every face point outward
        fc = gp[gt].mean(1)
        fn = np.cross(gp[gt[:, 1]] - gp[gt[:, 0]], gp[gt[:, 2]] - gp[gt[:, 0]])
        flip = ((fc - c) * fn).sum(1) < 0
        gt[flip] = gt[flip][:, [0, 2, 1]]
        vn = np.zeros_like(gp)
        fn = np.cross(gp[gt[:, 1]] - gp[gt[:, 0]], gp[gt[:, 2]] - gp[gt[:, 0]])
        for k in range(3):
            np.add.at(vn, gt[:, k], fn)
        vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
        mats.append({"name": "canopy_glass", "pbrMetallicRoughness": {
            "baseColorFactor": [0.05, 0.09, 0.15, 1.0], "metallicFactor": 0.6, "roughnessFactor": 0.08},
            "emissiveFactor": [0.01, 0.03, 0.06]})
        surfaces.append((gp, vn, np.zeros((len(gp), 2)), gt, len(mats) - 1))
        report.setdefault("glass_tris", []).append(int(len(gt)))
    sk.write_glb(a.out, surfaces, mats, images, a.name)
    report["tris"] = int(sum(len(s[3]) for s in surfaces))
    print(json.dumps(report))


if __name__ == "__main__":
    main()
