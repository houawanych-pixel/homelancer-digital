#!/usr/bin/env python3
"""Bake a Blender building export for the game: merge all parts into ONE mesh with one surface per material
(131 draw calls -> 8), apply node transforms, scale to game metres. Positions + normals only (the city shader
maps its panel detail in world space, so no UVs are needed).
usage: bake_glb.py in.glb out.glb [scale]"""
import json, struct, sys
import numpy as np

src, dst = sys.argv[1], sys.argv[2]
scale = float(sys.argv[3]) if len(sys.argv) > 3 else 1.0
b = open(src, "rb").read()
n = struct.unpack("<I", b[12:16])[0]
j = json.loads(b[20:20 + n])
binc = b[20 + n + 8:]
CT = {5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

def acc(i):
    a = j["accessors"][i]; v = j["bufferViews"][a["bufferView"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0); nc = NC[a["type"]]; dt = np.dtype(CT[a["componentType"]])
    st = v.get("byteStride", dt.itemsize * nc)
    raw = np.frombuffer(binc, dtype=np.uint8, count=st * (a["count"] - 1) + dt.itemsize * nc, offset=off)
    if st == dt.itemsize * nc: return raw.view(dt).reshape(a["count"], nc)
    return np.stack([raw[k * st:k * st + dt.itemsize * nc].view(dt) for k in range(a["count"])])

def mat(nd):
    if "matrix" in nd: return np.array(nd["matrix"], dtype=float).reshape(4, 4).T
    m = np.eye(4); x, y, z, w = nd.get("rotation", [0, 0, 0, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m[:3, :3] = R * np.array(nd.get("scale", [1, 1, 1])); m[:3, 3] = nd.get("translation", [0, 0, 0]); return m

groups = {}
def walk(i, M):
    nd = j["nodes"][i]; M = M @ mat(nd)
    if "mesh" in nd:
        for p in j["meshes"][nd["mesh"]]["primitives"]:
            P = acc(p["attributes"]["POSITION"]).astype(float); N = acc(p["attributes"]["NORMAL"]).astype(float)
            I = acc(p["indices"]).astype(np.int64).reshape(-1, 3)
            P = (P @ M[:3, :3].T + M[:3, 3]) * scale
            N = N @ np.linalg.inv(M[:3, :3]); N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
            if np.linalg.det(M[:3, :3]) < 0: I = I[:, ::-1]
            g = groups.setdefault(p.get("material", 0), [[], [], [], 0])
            g[0].append(P); g[1].append(N); g[2].append(I + g[3]); g[3] += len(P)
    for c in nd.get("children", []): walk(c, M)
for r in j["scenes"][j.get("scene", 0)]["nodes"]: walk(r, np.eye(4))

out = bytearray(); views = []; accs = []; prims = []
def push(arr, target, typ, ct, mm=False):
    while len(out) % 4: out.append(0)
    views.append({"buffer": 0, "byteOffset": len(out), "byteLength": arr.nbytes, "target": target}); out.extend(arr.tobytes())
    a = {"bufferView": len(views) - 1, "componentType": ct, "count": len(arr) if typ != "SCALAR" else arr.size, "type": typ}
    if mm: a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
    accs.append(a); return len(accs) - 1
tris = 0
for m in sorted(groups):
    P = np.concatenate(groups[m][0]).astype("<f4"); N = np.concatenate(groups[m][1]).astype("<f4"); I = np.concatenate(groups[m][2]).reshape(-1)
    tris += len(I) // 3
    big = len(P) > 65535
    prims.append({"attributes": {"POSITION": push(P, 34962, "VEC3", 5126, True), "NORMAL": push(N, 34962, "VEC3", 5126)},
        "indices": push(I.astype("<u4" if big else "<u2"), 34963, "SCALAR", 5125 if big else 5123), "material": m})
while len(out) % 4: out.append(0)
name = dst.split("/")[-1].split(".")[0]
g = {"asset": {"version": "2.0", "generator": "homelancer bake_glb"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "mesh": 0}],
    "meshes": [{"name": name, "primitives": prims}], "materials": [{k: v for k, v in mt.items() if k != "extensions"} for mt in j["materials"]],
    "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(out)}]}
js = json.dumps(g, separators=(",", ":")).encode(); js += b" " * (-len(js) % 4)
open(dst, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack("<II", len(js), 0x4E4F534A) + js
    + struct.pack("<II", len(out), 0x004E4942) + bytes(out))
print("%s: %d surfaces, %d triangles, %d bytes" % (dst, len(prims), tris, 28 + len(js) + len(out)))
