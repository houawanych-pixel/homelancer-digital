#!/usr/bin/env python3
"""shipkit — split a multi-ship GLB into separate game-ready ships (numpy only).

  inspect  fleet.glb --out DIR            list every separate ship ("cluster") + overview.png with numbers
  export   fleet.glb --cluster 3[,7] --name cargo --out ship.glb
           [--taper 0.65] [--nose-frac 0.35] [--flip] [--tex 1024] [--preview p.png]

Export: keeps only the chosen cluster(s), centres it, turns it so the nose points -Z (Godot forward)
and +Y is up, narrows the front section (--taper = width at the tip, 1.0 = unchanged), downsizes
textures, and writes a clean GLB. Polygon reduction is done afterwards by decimate.gd (Godot/meshoptimizer).
"""
import argparse, json, struct, io, os, sys, math
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


# ------------------------------------------------------------------ reading
def read_glb(path):
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        sys.exit("not a GLB file: " + path)
    off, js, binc = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binc = chunk
    req = js.get("extensionsRequired", [])
    if any(e in req for e in ("KHR_draco_mesh_compression", "EXT_meshopt_compression")):
        sys.exit("GLB uses compressed geometry %s — re-export it uncompressed first." % req)
    return js, binc


def bv_bytes(js, binc, i):
    bv = js["bufferViews"][i]
    o = bv.get("byteOffset", 0)
    return binc[o:o + bv["byteLength"]], bv.get("byteStride")


def accessor(js, binc, i):
    a = js["accessors"][i]
    n, comps, dt = a["count"], NC[a["type"]], np.dtype(CT[a["componentType"]])
    if "bufferView" in a:
        raw, stride = bv_bytes(js, binc, a["bufferView"])
        off = a.get("byteOffset", 0)
        esz = dt.itemsize * comps
        if stride and stride != esz:
            buf = np.frombuffer(raw, np.uint8)
            rows = np.stack([buf[off + k * stride: off + k * stride + esz] for k in range(n)]) if n else np.zeros((0, esz), np.uint8)
            arr = rows.view(dt).reshape(n, comps)
        else:
            arr = np.frombuffer(raw, dt, count=n * comps, offset=off).reshape(n, comps)
    else:
        arr = np.zeros((n, comps), dt)
    arr = arr.astype(np.float64) if dt != np.uint32 else arr.astype(np.int64)
    if a.get("normalized"):
        arr = arr / float(np.iinfo(dt).max)
    return arr


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def node_mat(nd):
    if "matrix" in nd:
        return np.array(nd["matrix"], float).reshape(4, 4).T
    m = np.eye(4)
    s = np.array(nd.get("scale", [1, 1, 1]), float)
    m[:3, :3] = quat_mat(nd.get("rotation", [0, 0, 0, 1])) * s
    m[:3, 3] = nd.get("translation", [0, 0, 0])
    return m


def load_geometry(path):
    """Flatten every triangle in the default scene into world space.
    Returns dict(pos, nrm, uv, tri, tmat) + (js, binc)."""
    js, binc = read_glb(path)
    P, N, U, T, M = [], [], [], [], []
    base = 0
    scene = js.get("scenes", [{}])[js.get("scene", 0)] if js.get("scenes") else {"nodes": list(range(len(js.get("nodes", []))))}

    def walk(ni, parent):
        nonlocal base
        nd = js["nodes"][ni]
        W = parent @ node_mat(nd)
        if "mesh" in nd:
            for pr in js["meshes"][nd["mesh"]]["primitives"]:
                if pr.get("mode", 4) != 4:
                    continue
                at = pr["attributes"]
                p = accessor(js, binc, at["POSITION"])
                n = accessor(js, binc, at["NORMAL"]) if "NORMAL" in at else None
                uv = accessor(js, binc, at["TEXCOORD_0"]) if "TEXCOORD_0" in at else np.zeros((len(p), 2))
                idx = accessor(js, binc, pr["indices"]).reshape(-1) if "indices" in pr else np.arange(len(p))
                idx = idx.astype(np.int64).reshape(-1, 3)
                pw = p @ W[:3, :3].T + W[:3, 3]
                if n is None:
                    n = np.zeros_like(p)
                    fn = np.cross(p[idx[:, 1]] - p[idx[:, 0]], p[idx[:, 2]] - p[idx[:, 0]])
                    for k in range(3):
                        np.add.at(n, idx[:, k], fn)
                nw = n @ np.linalg.inv(W[:3, :3])
                nw /= np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-12)
                if np.linalg.det(W[:3, :3]) < 0:
                    idx = idx[:, [0, 2, 1]]
                P.append(pw); N.append(nw); U.append(uv[:, :2]); T.append(idx + base)
                M.append(np.full(len(idx), pr.get("material", -1)))
                base += len(p)
        for c in nd.get("children", []):
            walk(c, W)

    for r in scene.get("nodes", []):
        walk(r, np.eye(4))
    if not P:
        sys.exit("no triangle meshes found")
    g = dict(pos=np.vstack(P), nrm=np.vstack(N), uv=np.vstack(U), tri=np.vstack(T), tmat=np.concatenate(M))
    return g, js, binc


# ------------------------------------------------------------------ splitting
def components(g):
    """Connected pieces of the mesh (after welding identical positions across UV seams)."""
    pos, tri = g["pos"], g["tri"]
    diag = np.linalg.norm(pos.max(0) - pos.min(0))
    q = np.round(pos / (diag * 1e-6 + 1e-12)).astype(np.int64)
    _, weld = np.unique(q, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    t = weld[tri]
    nv = weld.max() + 1
    rows = np.concatenate([t[:, 0], t[:, 1]])
    cols = np.concatenate([t[:, 1], t[:, 2]])
    adj = coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(nv, nv))
    ncomp, lab = connected_components(adj, directed=False)
    return lab[t[:, 0]], ncomp  # component id per triangle


def clusters(g, margin_frac=0.01):
    """Group mesh pieces into ships: pieces whose bounding boxes touch (with a small margin) are one ship."""
    tcomp, nc = components(g)
    pos, tri = g["pos"], g["tri"]
    tp = pos[tri]  # (T,3,3)
    lo = np.full((nc, 3), np.inf); hi = np.full((nc, 3), -np.inf)
    np.minimum.at(lo, tcomp, tp.min(1)); np.maximum.at(hi, tcomp, tp.max(1))
    diag = np.linalg.norm(pos.max(0) - pos.min(0))
    m = diag * margin_frac
    parent = np.arange(nc)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    order = np.argsort(-(hi - lo).prod(1))
    for s in range(0, nc, 512):
        blk = order[s:s + 512]
        ov = np.all((lo[blk, None, :] - m <= hi[None, :, :]) & (hi[blk, None, :] + m >= lo[None, :, :]), axis=2)
        for bi, row in zip(blk, ov):
            for j in np.nonzero(row)[0]:
                ra, rb = find(bi), find(j)
                if ra != rb:
                    parent[rb] = ra
    roots = np.array([find(i) for i in range(nc)])
    # repeat merge on merged boxes until stable (a chain of touching parts)
    changed = True
    while changed:
        changed = False
        ur = np.unique(roots)
        blo = np.array([lo[roots == r].min(0) for r in ur]); bhi = np.array([hi[roots == r].max(0) for r in ur])
        ov = np.all((blo[:, None] - m <= bhi[None]) & (bhi[:, None] + m >= blo[None]), axis=2)
        for a in range(len(ur)):
            for b in range(a + 1, len(ur)):
                if ov[a, b]:
                    roots[roots == ur[b]] = ur[a]; changed = True
                    break
            if changed:
                break
    ur, cl = np.unique(roots, return_inverse=True)
    tcl = cl[tcomp]
    info = []
    for c in range(len(ur)):
        sel = tcl == c
        pts = tp[sel].reshape(-1, 3)
        info.append(dict(id=0, tris=int(sel.sum()), lo=pts.min(0), hi=pts.max(0)))
    # number clusters left→right, then front→back, for a readable overview
    order = sorted(range(len(info)), key=lambda i: (round(float(info[i]["lo"][0] + info[i]["hi"][0]) / 2, 3), float(info[i]["lo"][2])))
    remap = np.zeros(len(info), int)
    out = []
    for new, old in enumerate(order):
        remap[old] = new
        d = info[old]; d["id"] = new; out.append(d)
    return remap[tcl], out


# ------------------------------------------------------------------ preview renderer (painter's algorithm)
def render(pos, tri, view, size=900, label_pts=None, labels=None, title=None, bg=(14, 18, 30)):
    from PIL import Image, ImageDraw
    axes = {"top": (0, 2, 1, (1, 1)), "side": (2, 1, 0, (-1, -1)), "front": (0, 1, 2, (1, -1)),
            "persp": None}
    if view == "persp":
        a, b = math.radians(35), math.radians(-25)
        R = np.array([[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]])
        R = np.array([[1, 0, 0], [0, math.cos(b), -math.sin(b)], [0, math.sin(b), math.cos(b)]]) @ R
        v = pos @ R.T
        X, Y, D, sg = v[:, 0], -v[:, 1], v[:, 2], (1, 1)
    else:
        ix, iy, iz, sg = axes[view]
        X, Y, D = pos[:, ix] * sg[0], pos[:, iy] * sg[1], pos[:, iz]
        if view == "top":
            D = pos[:, 1]
        elif view == "side":
            D = pos[:, 0]
        else:
            D = -pos[:, 2]
    pts2 = np.stack([X, Y], 1)
    lo, hi = pts2.min(0), pts2.max(0)
    sc = (size * 0.9) / max(hi - lo)
    off = (size - (hi - lo) * sc) / 2
    s2 = (pts2 - lo) * sc + off
    img = Image.new("RGB", (size, size), bg)
    dr = ImageDraw.Draw(img)
    t = tri
    fn = np.cross(pos[t[:, 1]] - pos[t[:, 0]], pos[t[:, 2]] - pos[t[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    light = np.array([0.4, 0.8, 0.45]); light /= np.linalg.norm(light)
    shade = 0.35 + 0.65 * np.abs(fn @ light)
    depth = D[t].mean(1)
    for k in np.argsort(depth):
        c = int(60 + 170 * shade[k])
        dr.polygon([tuple(s2[i]) for i in t[k]], fill=(c, c, min(255, c + 18)))
    if label_pts is not None:
        lp = np.stack([label_pts[:, axes[view][0]] * axes[view][3][0], label_pts[:, axes[view][1]] * axes[view][3][1]], 1) if view != "persp" else None
        if lp is not None:
            lp = (lp - lo) * sc + off
            for (x, y), lab in zip(lp, labels):
                dr.ellipse([x - 16, y - 16, x + 16, y + 16], fill=(255, 190, 40))
                dr.text((x - 7 if len(lab) > 1 else x - 4, y - 7), lab, fill=(0, 0, 0))
    if title:
        dr.text((10, 8), title, fill=(200, 220, 255))
    return img


def sheet(images, path):
    from PIL import Image
    w = sum(i.width for i in images); h = max(i.height for i in images)
    out = Image.new("RGB", (w, h))
    x = 0
    for i in images:
        out.paste(i, (x, 0)); x += i.width
    out.save(path)


# ------------------------------------------------------------------ writing
def write_glb(path, surfaces, materials_json, images, name):
    """surfaces: list of (pos, nrm, uv, tri, material_index). images: list of (bytes, mime)."""
    bin_parts, views, accs = [], [], []

    def add_view(b, target=None):
        off = sum(len(x) for x in bin_parts)
        pad = (-off) % 4
        if pad:
            bin_parts.append(b"\0" * pad); off += pad
        bin_parts.append(b)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(b)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def add_acc(arr, ctype, typ, target, minmax=False):
        vi = add_view(arr.tobytes(), target)
        a = {"bufferView": vi, "componentType": ctype, "count": int(len(arr)), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
        accs.append(a)
        return len(accs) - 1

    prims = []
    for pos, nrm, uv, tri, mi in surfaces:
        at = {"POSITION": add_acc(pos.astype(np.float32), 5126, "VEC3", 34962, True),
              "NORMAL": add_acc(nrm.astype(np.float32), 5126, "VEC3", 34962),
              "TEXCOORD_0": add_acc(uv.astype(np.float32), 5126, "VEC2", 34962)}
        pr = {"attributes": at, "indices": add_acc(tri.reshape(-1).astype(np.uint32), 5125, "SCALAR", 34963), "mode": 4}
        if mi is not None and mi >= 0:
            pr["material"] = int(mi)
        prims.append(pr)
    imgs = []
    for data, mime in images:
        imgs.append({"bufferView": add_view(data), "mimeType": mime})
    js = {"asset": {"version": "2.0", "generator": "homelancer shipkit"}, "scene": 0,
          "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "mesh": 0}],
          "meshes": [{"name": name, "primitives": prims}], "accessors": accs, "bufferViews": views}
    if materials_json:
        js["materials"] = materials_json
    if imgs:
        js["images"] = imgs
        js["textures"] = [{"source": i, "sampler": 0} for i in range(len(imgs))]
        js["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    b = b"".join(bin_parts)
    b += b"\0" * ((-len(b)) % 4)
    js["buffers"] = [{"byteLength": len(b)}]
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * ((-len(j)) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(b)))
        f.write(struct.pack("<II", len(j), 0x4E4F534A)); f.write(j)
        f.write(struct.pack("<II", len(b), 0x004E4942)); f.write(b)


TEX_KEYS = [("pbrMetallicRoughness", "baseColorTexture"), ("pbrMetallicRoughness", "metallicRoughnessTexture"),
            (None, "normalTexture"), (None, "emissiveTexture"), (None, "occlusionTexture")]


def remap_materials(js, binc, used, tex_size):
    """Copy the used materials and their images (downsized to tex_size) into a fresh list."""
    from PIL import Image
    mats, images, img_map = [], [], {}
    mat_map = {}
    for old in used:
        if old < 0:
            continue
        m = json.loads(json.dumps(js["materials"][old]))
        for grp, key in TEX_KEYS:
            holder = m.get(grp, {}) if grp else m
            if key not in holder:
                continue
            tex = js["textures"][holder[key]["index"]]
            src = tex.get("source")
            if src is None:
                del holder[key]; continue
            if src not in img_map:
                im = js["images"][src]
                raw, _ = bv_bytes(js, binc, im["bufferView"]) if "bufferView" in im else (b"", None)
                mime = im.get("mimeType", "image/png")
                try:
                    pil = Image.open(io.BytesIO(raw))
                    if tex_size and max(pil.size) > tex_size:
                        pil = pil.resize((tex_size, tex_size) if pil.size[0] == pil.size[1] else
                                         (max(1, pil.size[0] * tex_size // max(pil.size)), max(1, pil.size[1] * tex_size // max(pil.size))),
                                         Image.LANCZOS)
                    buf = io.BytesIO()
                    if key == "baseColorTexture" and pil.mode in ("RGB", "L", "P") or (mime == "image/jpeg"):
                        pil.convert("RGB").save(buf, "JPEG", quality=88); mime = "image/jpeg"
                    else:
                        pil.save(buf, "PNG", optimize=True); mime = "image/png"
                    raw = buf.getvalue()
                except Exception:
                    pass
                img_map[src] = len(images)
                images.append((raw, mime))
            holder[key] = {k: v for k, v in holder[key].items() if k != "texCoord"}
            holder[key]["index"] = img_map[src]
        m.pop("extensions", None)
        mat_map[old] = len(mats)
        mats.append(m)
    return mats, images, mat_map


# ------------------------------------------------------------------ ship shaping
def orient(pos, nrm, flip=False, axis=None):
    """Centre the ship, make its long axis point -Z (nose) with +Y up. Returns pos, nrm, report."""
    c = (pos.min(0) + pos.max(0)) / 2
    p = pos - c
    ext = p.max(0) - p.min(0)
    la = int(np.argmax(ext)) if axis is None else "xyz".index(axis)
    L = ext[la]
    # nose = the end with the smaller cross-section (engines/cargo pods usually make the back wider)
    ends = []
    for sgn in (1, -1):
        sl = p[(p[:, la] * sgn) > (L / 2 - 0.15 * L)]
        other = [k for k in range(3) if k != la]
        ends.append(np.prod(sl[:, other].max(0) - sl[:, other].min(0)) if len(sl) else 0)
    sgn = 1 if ends[0] < ends[1] else -1
    if flip:
        sgn = -sgn
    f = np.zeros(3); f[la] = sgn
    up = np.array([0, 1, 0.]) if la != 1 else np.array([0, 0, 1.])
    r = np.cross(f, up)
    R = np.stack([r, up, -f])
    p2 = p @ R.T
    n2 = nrm @ R.T
    c2 = (p2.min(0) + p2.max(0)) / 2
    return p2 - c2, n2, {"long_axis": "xyz"[la], "nose_sign": sgn, "size": (p2.max(0) - p2.min(0)).round(3).tolist()}


def taper_nose(pos, nrm, tip=0.65, frac=0.35, vertical=0.4):
    """Narrow the front `frac` of the ship toward `tip` width (x), and a little in height (y)."""
    z = pos[:, 2]
    zmin, zmax = z.min(), z.max()
    start = zmin + frac * (zmax - zmin)
    t = np.clip((start - z) / max(start - zmin, 1e-9), 0, 1)
    t = t * t * (3 - 2 * t)
    sx = 1 - (1 - tip) * t
    sy = 1 - (1 - tip) * vertical * t
    out = pos.copy()
    out[:, 0] *= sx
    out[:, 1] = pos[:, 1] * sy
    n = nrm.copy()
    n[:, 0] /= sx; n[:, 1] /= sy
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    return out, n


def compact(pos, nrm, uv, tri):
    used, inv = np.unique(tri.reshape(-1), return_inverse=True)
    return pos[used], nrm[used], uv[used], inv.reshape(-1, 3)


# ------------------------------------------------------------------ commands
def cmd_inspect(a):
    g, js, binc = load_geometry(a.glb)
    tcl, info = clusters(g, a.margin)
    os.makedirs(a.out, exist_ok=True)
    print("file: %s  triangles: %d  vertices: %d  materials: %d  images: %d" % (
        a.glb, len(g["tri"]), len(g["pos"]), len(js.get("materials", [])), len(js.get("images", []))))
    print(" id   tris      size (x × y × z)            centre")
    rows = []
    for d in info:
        sz = d["hi"] - d["lo"]; ce = (d["hi"] + d["lo"]) / 2
        print("%3d %7d   %8.3f × %8.3f × %8.3f   (%.2f, %.2f, %.2f)" % (d["id"], d["tris"], *sz, *ce))
        rows.append({"id": d["id"], "tris": d["tris"], "size": sz.round(4).tolist(), "centre": ce.round(4).tolist()})
    json.dump(rows, open(os.path.join(a.out, "clusters.json"), "w"), indent=1)
    # overview (sub-sample very dense meshes for speed)
    tri = g["tri"]
    if len(tri) > a.preview_tris:
        tri = tri[np.random.default_rng(0).choice(len(tri), a.preview_tris, replace=False)]
    cent = np.array([(d["hi"] + d["lo"]) / 2 for d in info]); labs = [str(d["id"]) for d in info]
    imgs = [render(g["pos"], tri, v, 800, cent, labs, v.upper()) for v in ("top", "side", "front")]
    sheet(imgs, os.path.join(a.out, "overview.png"))
    # one thumbnail per big cluster
    big = [d for d in info if d["tris"] >= a.min_tris]
    thumbs = []
    for d in big[:24]:
        sel = tri_sel = g["tri"][tcl == d["id"]]
        if len(sel) > 40000:
            sel = sel[np.random.default_rng(1).choice(len(sel), 40000, replace=False)]
        thumbs.append(render(g["pos"], sel, "persp", 360, title="#%d  %d tris" % (d["id"], d["tris"])))
    if thumbs:
        from PIL import Image
        cols = 6; rws = (len(thumbs) + cols - 1) // cols
        S = Image.new("RGB", (cols * 360, rws * 360), (10, 12, 20))
        for k, im in enumerate(thumbs):
            S.paste(im, ((k % cols) * 360, (k // cols) * 360))
        S.save(os.path.join(a.out, "clusters.png"))
    print("wrote", os.path.join(a.out, "overview.png"), "and clusters.png")


def cmd_export(a):
    g, js, binc = load_geometry(a.glb)
    tcl, info = clusters(g, a.margin)
    want = [int(x) for x in a.cluster.split(",")]
    sel = np.isin(tcl, want)
    if not sel.any():
        sys.exit("cluster(s) %s not found" % a.cluster)
    tri = g["tri"][sel]; tmat = g["tmat"][sel]
    pos, nrm, uv, tri = compact(g["pos"], g["nrm"], g["uv"], tri)
    pos, nrm, rep = orient(pos, nrm, a.flip, a.axis)
    if a.taper < 1.0:
        pos, nrm = taper_nose(pos, nrm, a.taper, a.nose_frac)
    used = sorted(set(int(m) for m in tmat))
    mats, images, mat_map = remap_materials(js, binc, used, a.tex) if js.get("materials") else ([], [], {})
    surfaces = []
    for m in used:
        ts = tri[tmat == m]
        p, n, u, t = compact(pos, nrm, uv, ts)
        surfaces.append((p, n, u, t, mat_map.get(m, -1)))
    write_glb(a.out, surfaces, mats, images, a.name)
    rep.update(name=a.name, clusters=want, tris=int(len(tri)), size_after=(pos.max(0) - pos.min(0)).round(3).tolist(),
               bytes=os.path.getsize(a.out))
    print(json.dumps(rep))
    if a.preview:
        t = tri if len(tri) <= 60000 else tri[np.random.default_rng(0).choice(len(tri), 60000, replace=False)]
        sheet([render(pos, t, v, 520, title="%s %s" % (a.name, v)) for v in ("top", "side", "persp")], a.preview)


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    i = sp.add_parser("inspect"); i.add_argument("glb"); i.add_argument("--out", default="shipkit_out")
    i.add_argument("--margin", type=float, default=0.01); i.add_argument("--min-tris", type=int, default=200)
    i.add_argument("--preview-tris", type=int, default=150000)
    e = sp.add_parser("export"); e.add_argument("glb"); e.add_argument("--cluster", required=True)
    e.add_argument("--name", default="ship"); e.add_argument("--out", required=True)
    e.add_argument("--margin", type=float, default=0.01)
    e.add_argument("--taper", type=float, default=0.65); e.add_argument("--nose-frac", type=float, default=0.35)
    e.add_argument("--flip", action="store_true"); e.add_argument("--axis", choices=list("xyz"))
    e.add_argument("--tex", type=int, default=1024); e.add_argument("--preview")
    a = ap.parse_args()
    {"inspect": cmd_inspect, "export": cmd_export}[a.cmd](a)


if __name__ == "__main__":
    main()
