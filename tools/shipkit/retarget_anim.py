#!/usr/bin/env python3
"""retarget_anim — copy an animation from a Mixamo-rigged GLB (Tripo auto-rig, "mixamorig:*" bones) onto a GLB made
by rig_humanoid.py (22 Godot-humanoid bones, identity rest rotations), so many characters share one character's moves.

  retarget_anim.py source.glb target.glb out.glb [--anim walk] [--as Walk] [--fps 30]

How: for every mapped bone, the source's rotation change from its rest pose is taken in WORLD space and given to the
target bone (whose rest is identity), then turned back into a local rotation under its parent. The hips also get the
source's up/down and sideways sway, scaled by the hip heights. The target keeps its other animations; one with the
same name is replaced.
"""
import argparse, json, struct, sys, os
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as sk

MAP = {"Hips": "Hips", "Spine": "Spine", "Spine1": "Chest", "Spine2": "UpperChest", "Neck": "Neck", "Head": "Head"}
for S in ("Left", "Right"):
    MAP.update({S + "Shoulder": S + "Shoulder", S + "Arm": S + "UpperArm", S + "ForeArm": S + "LowerArm", S + "Hand": S + "Hand",
                S + "UpLeg": S + "UpperLeg", S + "Leg": S + "LowerLeg", S + "Foot": S + "Foot", S + "ToeBase": S + "Toes"})


def q2m(q): return sk.quat_mat(q)


def m2q(m):
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2; w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s; y = (m[0, 2] - m[2, 0]) / s; z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2; w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s; y = (m[0, 1] + m[1, 0]) / s; z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2; w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s; y = 0.25 * s; z = (m[1, 2] + m[2, 1]) / s
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2; w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s; y = (m[1, 2] + m[2, 1]) / s; z = 0.25 * s
    q = np.array([x, y, z, w]); return q / np.linalg.norm(q)


def slerp(a, b, t):
    a = np.array(a, float); b = np.array(b, float)
    d = float(a @ b)
    if d < 0: b = -b; d = -d
    if d > 0.9995: r = a + t * (b - a); return r / np.linalg.norm(r)
    th = np.arccos(d); return (np.sin((1 - t) * th) * a + np.sin(t * th) * b) / np.sin(th)


def sample(ts, vals, t, rot):
    if t <= ts[0]: return vals[0]
    if t >= ts[-1]: return vals[-1]
    i = int(np.searchsorted(ts, t)) - 1
    k = (t - ts[i]) / max(1e-9, ts[i + 1] - ts[i])
    return slerp(vals[i], vals[i + 1], k) if rot else vals[i] * (1 - k) + vals[i + 1] * k


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst"); ap.add_argument("out")
    ap.add_argument("--anim", default=None); ap.add_argument("--as", dest="as_name", default="Walk"); ap.add_argument("--fps", type=float, default=30)
    a = ap.parse_args()
    sjs, sbin = sk.read_glb(a.src)
    anim = [x for x in sjs["animations"] if a.anim is None or x.get("name", "").lower() == a.anim.lower()][0]
    nodes = sjs["nodes"]
    parent = {}
    for i, nd in enumerate(nodes):
        for c in nd.get("children", []): parent[c] = i
    tracks = {}   # node -> {path: (ts, vals)}
    T = 0.0
    for ch in anim["channels"]:
        smp = anim["samplers"][ch["sampler"]]
        ts = sk.accessor(sjs, sbin, smp["input"])[:, 0]
        vs = sk.accessor(sjs, sbin, smp["output"])
        tracks.setdefault(ch["target"]["node"], {})[ch["target"]["path"]] = (ts, vs)
        T = max(T, float(ts[-1]))
    def local(i, t):
        nd = nodes[i]
        tr = tracks.get(i, {})
        tt = sample(*tr["translation"], t, False) if (t is not None and "translation" in tr) else np.array(nd.get("translation", [0, 0, 0]), float)
        rr = sample(*tr["rotation"], t, True) if (t is not None and "rotation" in tr) else np.array(nd.get("rotation", [0, 0, 0, 1]), float)
        ss = sample(*tr["scale"], t, False) if (t is not None and "scale" in tr) else np.array(nd.get("scale", [1, 1, 1]), float)
        if "matrix" in nd and t is None: return np.array(nd["matrix"], float).reshape(4, 4).T
        m = np.eye(4); m[:3, :3] = q2m(rr) * ss; m[:3, 3] = tt; return m
    def world(i, t, cache):
        if i in cache: return cache[i]
        m = local(i, t)
        if i in parent: m = world(parent[i], t, cache) @ m
        cache[i] = m; return m
    sname = {}
    for i, nd in enumerate(nodes):
        n = nd.get("name", "").split(":")[-1]
        if n in MAP: sname[MAP[n]] = i
    rest = {}
    rc = {}
    for b, i in sname.items(): rest[b] = world(i, None, rc)
    def rot_only(m):
        r = m[:3, :3]; return r / np.linalg.norm(r, axis=0)
    # target
    tjs, tbin = sk.read_glb(a.dst)
    tn = {nd["name"]: i for i, nd in enumerate(tjs["nodes"])}
    tparent = {}
    for i, nd in enumerate(tjs["nodes"]):
        for c in nd.get("children", []): tparent[c] = i
    order = [b for b in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"] + [S + p for S in ("Left", "Right") for p in ("Shoulder", "UpperArm", "LowerArm", "Hand", "UpperLeg", "LowerLeg", "Foot", "Toes")] if b in tn]
    tparent_name = {b: tjs["nodes"][tparent[tn[b]]]["name"] if tn[b] in tparent else None for b in order}
    hips_t = np.array(tjs["nodes"][tn["Hips"]].get("translation", [0, 0, 0]), float)
    # source hip height (world) for scaling the sway
    s_hip_h = abs(rest["Hips"][1, 3]) if abs(rest["Hips"][1, 3]) > 1e-6 else 1.0
    t_hip_h = hips_t[1] if abs(hips_t[1]) > 1e-6 else 1.0
    n = max(2, int(round(T * a.fps)) + 1)
    times = np.linspace(0, T, n)
    rots = {b: [] for b in order}
    hip_tr = []
    for t in times:
        cache = {}
        D = {}
        for b in order:
            if b in sname:
                Ga = rot_only(world(sname[b], t, cache)); Gr = rot_only(rest[b])
                D[b] = Ga @ Gr.T
            else:
                D[b] = D.get(tparent_name[b], np.eye(3)) if tparent_name[b] else np.eye(3)
        for b in order:
            p = tparent_name[b]
            L = (D[p].T @ D[b]) if p in D else D[b]
            rots[b].append(m2q(L))
        dp = (world(sname["Hips"], t, cache)[:3, 3] - rest["Hips"][:3, 3]) * (t_hip_h / s_hip_h)
        dp[2] = 0.0   # (walking on the spot: the game moves the character)
        hip_tr.append(hips_t + dp)
    # write: append data to the target's buffer, replace the animation of the same name
    buf = bytearray(tbin)
    def add(arr, typ):
        nonlocal buf
        while len(buf) % 4: buf += b"\0"
        arr = np.ascontiguousarray(arr, np.float32)
        tjs["bufferViews"].append({"buffer": 0, "byteOffset": len(buf), "byteLength": arr.nbytes})
        buf += arr.tobytes()
        acc = {"bufferView": len(tjs["bufferViews"]) - 1, "componentType": 5126, "count": int(arr.shape[0]), "type": typ}
        if typ == "SCALAR": acc["min"] = [float(arr.min())]; acc["max"] = [float(arr.max())]
        tjs["accessors"].append(acc); return len(tjs["accessors"]) - 1
    tacc = add(times.reshape(-1, 1), "SCALAR")
    samplers, channels = [], []
    for b in order:
        samplers.append({"input": tacc, "output": add(np.array(rots[b]), "VEC4"), "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": tn[b], "path": "rotation"}})
    samplers.append({"input": tacc, "output": add(np.array(hip_tr), "VEC3"), "interpolation": "LINEAR"})
    channels.append({"sampler": len(samplers) - 1, "target": {"node": tn["Hips"], "path": "translation"}})
    anims = [x for x in tjs.get("animations", []) if x.get("name") != a.as_name]
    anims.append({"name": a.as_name, "samplers": samplers, "channels": channels})
    tjs["animations"] = anims
    while len(buf) % 4: buf += b"\0"
    tjs["buffers"] = [{"byteLength": len(buf)}]
    j = json.dumps(tjs, separators=(",", ":")).encode(); j += b" " * ((-len(j)) % 4)
    with open(a.out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(buf)))
        f.write(struct.pack("<II", len(j), 0x4E4F534A)); f.write(j)
        f.write(struct.pack("<II", len(buf), 0x004E4942)); f.write(bytes(buf))
    print(json.dumps({"anim": anim.get("name"), "as": a.as_name, "seconds": round(T, 3), "frames": n, "bones": len(order), "mapped": len(sname)}))


if __name__ == "__main__":
    main()
