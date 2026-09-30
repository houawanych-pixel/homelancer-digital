#!/usr/bin/env python3
"""rigfix — re-weight rigid parts of an auto-rigged GLB so they stop bending.

  rigfix.py in.glb out.glb --rule "BONE : condition" [--rule ...] [--keep "condition"]

Each rule assigns every vertex matching its condition 100 % to BONE (later rules win).
Conditions are numpy expressions over x, y, z (bind-pose mesh coordinates), e.g.
    --rule "Spine02 : (y > 0.70)"  --keep "(x > -0.17) & (x < -0.05) & (y > 0.70) & (y < 0.86)"
Vertices matching any --keep condition are never changed. Everything else in the file is copied untouched.
"""
import argparse, json, struct, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as sk


def write_accessor(js, binc, idx, arr):
    a = js["accessors"][idx]
    bv = js["bufferViews"][a["bufferView"]]
    dt = np.dtype(sk.CT[a["componentType"]])
    comps = sk.NC[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride") or dt.itemsize * comps
    data = np.asarray(arr).astype(dt).reshape(-1, comps)
    if stride == dt.itemsize * comps:
        raw = data.tobytes(); binc[off:off + len(raw)] = raw
        return
    for i in range(len(data)):
        binc[off + i * stride: off + i * stride + dt.itemsize * comps] = data[i].tobytes()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("glb"); ap.add_argument("out")
    ap.add_argument("--rule", action="append", default=[])
    ap.add_argument("--keep", action="append", default=[])
    a = ap.parse_args()
    js, binc = sk.read_glb(a.glb)
    binc = bytearray(binc)
    names = [js["nodes"][j]["name"] for j in js["skins"][0]["joints"]]
    report = {}
    for mesh in js["meshes"]:
        for pr in mesh["primitives"]:
            at = pr["attributes"]
            if "JOINTS_0" not in at: continue
            P = sk.accessor(js, bytes(binc), at["POSITION"])
            J = sk.accessor(js, bytes(binc), at["JOINTS_0"]).astype(np.int64)
            W = sk.accessor(js, bytes(binc), at["WEIGHTS_0"])
            x, y, z = P[:, 0], P[:, 1], P[:, 2]
            env = {"x": x, "y": y, "z": z, "np": np}
            keep = np.zeros(len(P), bool)
            for k in a.keep:
                keep |= eval(k, env)
            for r in a.rule:
                bone, cond = [s.strip() for s in r.split(":", 1)]
                bi = names.index(bone)
                m = eval(cond, env) & ~keep
                J[m] = [bi, 0, 0, 0]
                W[m] = [1.0, 0.0, 0.0, 0.0]
                report[bone + " <- " + cond] = int(m.sum())
            wa = js["accessors"][at["WEIGHTS_0"]]
            if wa["componentType"] != 5126:
                W = np.round(W * np.iinfo(np.dtype(sk.CT[wa["componentType"]])).max)
            write_accessor(js, binc, at["JOINTS_0"], J)
            write_accessor(js, binc, at["WEIGHTS_0"], W)
    j = json.dumps(js, separators=(",", ":")).encode()
    j += b" " * ((-len(j)) % 4)
    b = bytes(binc) + b"\0" * ((-len(binc)) % 4)
    with open(a.out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(b)))
        f.write(struct.pack("<II", len(j), 0x4E4F534A)); f.write(j)
        f.write(struct.pack("<II", len(b), 0x004E4942)); f.write(b)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
