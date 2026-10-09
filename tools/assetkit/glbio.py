"""Tiny GLB writer: several surfaces, each {pos, nrm, uv (or None), idx, mat}. Materials are glTF material dicts;
images = list of (bytes, mime). Texture k uses image k."""
import json, struct
import numpy as np

def write_glb(path, surfaces, materials, images, name="Model"):
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
    prims = []
    for s in surfaces:
        at = {"POSITION": acc(np.ascontiguousarray(s["pos"], np.float32), 5126, "VEC3", 34962, True),
              "NORMAL": acc(np.ascontiguousarray(s["nrm"], np.float32), 5126, "VEC3", 34962)}
        if s.get("uv") is not None: at["TEXCOORD_0"] = acc(np.ascontiguousarray(s["uv"], np.float32), 5126, "VEC2", 34962)
        prims.append({"attributes": at, "indices": acc(np.ascontiguousarray(s["idx"], np.uint32).reshape(-1), 5125, "SCALAR", 34963), "material": s["mat"]})
    imgs = []
    for b, mime in images:
        imgs.append({"bufferView": view(b), "mimeType": mime})
    js = {"asset": {"version": "2.0", "generator": "homelancer asset kit"}, "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"name": name, "mesh": 0}], "meshes": [{"name": name, "primitives": prims}], "materials": materials,
          "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}]}
    if imgs:
        js["images"] = imgs; js["textures"] = [{"source": k, "sampler": 0} for k in range(len(imgs))]
        js["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    jb = json.dumps(js, separators=(",", ":")).encode()
    while len(jb) % 4: jb += b" "
    while len(bin_) % 4: bin_.append(0)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, 12 + 8 + len(jb) + 8 + len(bin_)))
        f.write(struct.pack("<I", len(jb)) + b"JSON" + jb)
        f.write(struct.pack("<I", len(bin_)) + b"BIN\x00" + bytes(bin_))

def load_raw(R):
    pos = np.fromfile(R + "pos.bin", np.float32).reshape(-1, 3)
    idx = np.fromfile(R + "idx.bin", np.uint32).reshape(-1, 3)
    uv = np.fromfile(R + "uv.bin", np.float32).reshape(-1, 2)
    nrm = np.fromfile(R + "nrm.bin", np.int8).reshape(-1, 4)[:, :3].astype(np.float32) / 127.0
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
    return pos, nrm, uv, idx

def write_glb_nodes(path, parts, materials, images, name="Model"):
    """Several named nodes under one root: parts = [(node_name, [surfaces], (tx, ty, tz))]. Same surface dicts as write_glb."""
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
    meshes = []; nodes = [{"name": name, "children": []}]
    for nm, surfaces, tr in parts:
        prims = []
        for s in surfaces:
            at = {"POSITION": acc(np.ascontiguousarray(s["pos"], np.float32), 5126, "VEC3", 34962, True),
                  "NORMAL": acc(np.ascontiguousarray(s["nrm"], np.float32), 5126, "VEC3", 34962)}
            if s.get("uv") is not None: at["TEXCOORD_0"] = acc(np.ascontiguousarray(s["uv"], np.float32), 5126, "VEC2", 34962)
            prims.append({"attributes": at, "indices": acc(np.ascontiguousarray(s["idx"], np.uint32).reshape(-1), 5125, "SCALAR", 34963), "material": s["mat"]})
        meshes.append({"name": nm, "primitives": prims})
        nd = {"name": nm, "mesh": len(meshes) - 1}
        if any(abs(float(x)) > 0 for x in tr): nd["translation"] = [float(x) for x in tr]
        nodes.append(nd); nodes[0]["children"].append(len(nodes) - 1)
    imgs = [{"bufferView": view(b), "mimeType": mime} for b, mime in images]
    js = {"asset": {"version": "2.0", "generator": "homelancer asset kit"}, "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": nodes, "meshes": meshes, "materials": materials, "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(bin_)}]}
    if imgs:
        js["images"] = imgs; js["textures"] = [{"source": k, "sampler": 0} for k in range(len(imgs))]
        js["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    jb = json.dumps(js, separators=(",", ":")).encode()
    while len(jb) % 4: jb += b" "
    while len(bin_) % 4: bin_.append(0)
    with open(path, "wb") as f:
        f.write(b"glTF" + struct.pack("<II", 2, 12 + 8 + len(jb) + 8 + len(bin_)))
        f.write(struct.pack("<I", len(jb)) + b"JSON" + jb)
        f.write(struct.pack("<I", len(bin_)) + b"BIN\x00" + bytes(bin_))
