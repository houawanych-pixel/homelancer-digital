import json, struct, numpy as np
def read_simple_glb(path):
    d = open(path, "rb").read(); n = struct.unpack("<I", d[12:16])[0]; js = json.loads(d[20:20 + n]); b = d[20 + n + 8:]
    def acc(i):
        a = js["accessors"][i]; bv = js["bufferViews"][a["bufferView"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        comp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
        st = bv.get("byteStride", 0)
        if st and st != comp * np.dtype(dt).itemsize:
            raw = np.frombuffer(b, np.uint8, a["count"] * st, off).reshape(-1, st)[:, :comp * np.dtype(dt).itemsize].copy()
            return raw.view(dt).reshape(-1, comp)
        return np.frombuffer(b, dt, a["count"] * comp, off).reshape(-1, comp)
    P, N, U, I = [], [], [], []; base = 0
    def walk(ni, M):
        nonlocal base
        nd = js["nodes"][ni]; L = np.eye(4)
        if "matrix" in nd: L = np.array(nd["matrix"], float).reshape(4, 4).T
        else:
            if "scale" in nd: L = np.diag(list(nd["scale"]) + [1.0]) @ L
            if "rotation" in nd:
                x, y, z, w = nd["rotation"]
                Rm = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0], [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0], [0, 0, 0, 1]])
                L = Rm @ L
            if "translation" in nd: T = np.eye(4); T[:3, 3] = nd["translation"]; L = T @ L
        G = M @ L
        if "mesh" in nd:
            for pr in js["meshes"][nd["mesh"]]["primitives"]:
                p = acc(pr["attributes"]["POSITION"]).astype(np.float64)
                p = (G[:3, :3] @ p.T).T + G[:3, 3]
                nn = acc(pr["attributes"]["NORMAL"]).astype(np.float64); nn = (G[:3, :3] @ nn.T).T; nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
                P.append(p.astype(np.float32)); N.append(nn.astype(np.float32)); U.append(acc(pr["attributes"]["TEXCOORD_0"]).astype(np.float32))
                I.append(acc(pr["indices"]).reshape(-1, 3).astype(np.uint32) + base); base += len(p)
        for c in nd.get("children", []): walk(c, G)
    for r in js["scenes"][js.get("scene", 0)]["nodes"]: walk(r, np.eye(4))
    return np.concatenate(P), np.concatenate(N), np.concatenate(U), np.concatenate(I)
