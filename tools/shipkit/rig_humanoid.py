#!/usr/bin/env python3
"""rig_humanoid — rig an unrigged humanoid GLB with a Godot-humanoid skeleton and attach a separate weapon.

  rig_humanoid.py body.glb joints.json out.glb [--weapon rifle.glb --weapon-bone RightHand --grip x,y,z]
                  [--height 1.8]

joints.json: joint positions in the body's own coordinates (character faces +Z, up +Y, its left is +X):
  {"Hips":[x,y,z], "Spine":[...], ..., "LeftHand_end":[...], ...}
Bone names follow Godot's SkeletonProfileHumanoid so any humanoid animation retargets onto it.
Skin weights: capsule distance to each bone, normalised by bone radius, blended smoothly at joints.
The weapon stays a separate object (own mesh node) parented to the hand bone: swap or drop it freely.
Adds two animations to prove the rig: Idle and Walk.
"""
import argparse, json, math, os, struct, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shipkit as sk

# name, parent, end-joint key (segment end), capsule radius (in body-height units)
BONES = [
    ("Hips", None, "Spine", 0.14), ("Spine", "Hips", "Chest", 0.14), ("Chest", "Spine", "UpperChest", 0.15),
    ("UpperChest", "Chest", "Neck", 0.15), ("Neck", "UpperChest", "Head", 0.05), ("Head", "Neck", "Head_end", 0.08),
]
for S, s in (("Left", 1), ("Right", -1)):
    BONES += [
        (S + "Shoulder", "UpperChest", S + "UpperArm", 0.06), (S + "UpperArm", S + "Shoulder", S + "LowerArm", 0.052),
        (S + "LowerArm", S + "UpperArm", S + "Hand", 0.046), (S + "Hand", S + "LowerArm", S + "Hand_end", 0.04),
        (S + "UpperLeg", "Hips", S + "LowerLeg", 0.075), (S + "LowerLeg", S + "UpperLeg", S + "Foot", 0.06),
        (S + "Foot", S + "LowerLeg", S + "Toes", 0.055), (S + "Toes", S + "Foot", S + "Toes_end", 0.045),
    ]
NAMES = [b[0] for b in BONES]


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-12), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def skin_weights(P, J):
    dn = np.stack([seg_dist(P, np.array(J[n]), np.array(J[e])) / r for n, _, e, r in BONES], 1)
    order = np.argsort(dn, 1)[:, :4]
    best = np.take_along_axis(dn, order, 1)
    w = np.maximum(best, 1e-4) ** -6.0
    w[best > best[:, :1] * 1.6] = 0.0          # only blend bones that are nearly as close (joint zones)
    w /= w.sum(1, keepdims=True)
    return order.astype(np.uint16), w.astype(np.float32)


def quat_axis(axis, deg):
    a = np.array(axis, float); a /= np.linalg.norm(a)
    h = math.radians(deg) / 2
    return [*(a * math.sin(h)), math.cos(h)]


def qmul(q1, q2):
    x1, y1, z1, w1 = q1; x2, y2, z2, w2 = q2
    return [w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
            w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2]


def make_anims(J, H):
    """Idle (breathing sway) and Walk (1 s loop). Rest pose rotations are identity, so keys are absolute."""
    anims = []
    # ---- Walk
    n = 25; ts = np.linspace(0, 1.0, n)
    rot = {}; trans = {}
    ph = 2 * math.pi * ts
    for S, sg in (("Left", 1), ("Right", -1)):
        leg = 28 * np.sin(ph + (0 if S == "Left" else math.pi))           # + = forward swing
        knee = 35 * np.clip(np.sin(ph + (0 if S == "Left" else math.pi) - 1.2), 0, 1) + 6
        arm = -18 * np.sin(ph + (0 if S == "Left" else math.pi))
        rot[S + "UpperLeg"] = [quat_axis([1, 0, 0], -a) for a in leg]
        rot[S + "LowerLeg"] = [quat_axis([1, 0, 0], k) for k in knee]
        rot[S + "Foot"] = [quat_axis([1, 0, 0], -0.4 * a) for a in leg]
        rot[S + "UpperArm"] = [quat_axis([1, 0, 0], -a) for a in arm]
        rot[S + "LowerArm"] = [quat_axis([1, 0, 0], -12 - 8 * max(0, math.sin(p))) for p in ph]
    rot["Spine"] = [quat_axis([0, 1, 0], 5 * math.sin(p)) for p in ph]
    rot["Chest"] = [quat_axis([0, 1, 0], -7 * math.sin(p)) for p in ph]
    hips0 = np.array(J["Hips"]) * H
    trans["Hips"] = [(hips0 + np.array([0, -0.012 * H * abs(math.cos(p)), 0])).tolist() for p in ph]
    anims.append(("Walk", ts, rot, trans))
    # ---- Idle
    n = 41; ts = np.linspace(0, 4.0, n); ph = 2 * math.pi * ts / 4.0
    rot = {"Chest": [quat_axis([1, 0, 0], 1.5 * math.sin(p)) for p in ph],
           "Neck": [quat_axis([0, 1, 0], 4 * math.sin(p * 0.5)) for p in ph],
           "LeftUpperArm": [quat_axis([0, 0, 1], 2 * math.sin(p)) for p in ph],
           "RightUpperArm": [quat_axis([0, 0, 1], -2 * math.sin(p)) for p in ph]}
    anims.append(("Idle", ts, rot, {}))
    return anims


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("body"); ap.add_argument("joints"); ap.add_argument("out")
    ap.add_argument("--weapon"); ap.add_argument("--weapon-bone", default="RightHand")
    ap.add_argument("--weapon-at", help="x,y,z where the weapon grip sits, in body coordinates")
    ap.add_argument("--height", type=float, default=1.8)
    ap.add_argument("--shift-x", type=float, default=0.0)
    a = ap.parse_args()
    H = a.height
    J = {k: (np.array(v) + [a.shift_x, 0, 0]).tolist() for k, v in json.load(open(a.joints)).items()}
    g, js, binc = sk.load_geometry(a.body)
    P = g["pos"] + [a.shift_x, 0, 0]
    joints_idx, weights = skin_weights(P, J)
    # ---------------- build glTF
    buf = bytearray(); views = []; accs = []

    def add(arr, ctype, typ, target=None, minmax=False):
        nonlocal buf
        while len(buf) % 4: buf += b"\0"
        raw = np.ascontiguousarray(arr).tobytes()
        v = {"buffer": 0, "byteOffset": len(buf), "byteLength": len(raw)}
        if target: v["target"] = target
        buf += raw; views.append(v)
        acc = {"bufferView": len(views) - 1, "componentType": ctype, "count": int(len(arr)), "type": typ}
        if minmax: acc["min"] = np.asarray(arr).min(0).tolist(); acc["max"] = np.asarray(arr).max(0).tolist()
        accs.append(acc); return len(accs) - 1

    def add_image(data, mime):
        nonlocal buf
        while len(buf) % 4: buf += b"\0"
        views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data)}); buf += data
        return {"bufferView": len(views) - 1, "mimeType": mime}

    materials, images_all, textures = [], [], []

    def import_mats(srcjs, srcbin):
        base_img = len(images_all)
        mats, imgs, mm = sk.remap_materials(srcjs, srcbin, list(range(len(srcjs.get("materials", [])))), 0)
        for data, mime in imgs:
            images_all.append(add_image(data, mime)); textures.append({"source": len(images_all) - 1, "sampler": 0})
        base_mat = len(materials)
        for m in mats:
            m = json.loads(json.dumps(m))
            for grp, key in sk.TEX_KEYS:
                h = m.get(grp, {}) if grp else m
                if key in h: h[key]["index"] += base_img
            materials.append(m)
        return {k: v + base_mat for k, v in mm.items()}

    mm_body = import_mats(js, binc)
    pos = (P * H).astype(np.float32)
    prim = {"attributes": {"POSITION": add(pos, 5126, "VEC3", 34962, True),
                           "NORMAL": add(g["nrm"].astype(np.float32), 5126, "VEC3", 34962),
                           "TEXCOORD_0": add(g["uv"].astype(np.float32), 5126, "VEC2", 34962),
                           "JOINTS_0": add(joints_idx, 5123, "VEC4", 34962),
                           "WEIGHTS_0": add(weights, 5126, "VEC4", 34962)},
            "indices": add(g["tri"].reshape(-1).astype(np.uint32), 5125, "SCALAR", 34963),
            "material": mm_body.get(0, 0)}
    meshes = [{"name": "Body", "primitives": [prim]}]
    # joints: rest rotations identity -> local translation = child - parent
    nodes = []
    jnode = {}
    for n, parent, _, _ in BONES:
        jnode[n] = len(nodes)
        t = np.array(J[n]) * H - (np.array(J[parent]) * H if parent else 0)
        nodes.append({"name": n, "translation": t.tolist(), "children": []})
    for n, parent, _, _ in BONES:
        if parent: nodes[jnode[parent]]["children"].append(jnode[n])
    ibm = np.stack([np.eye(4) for _ in BONES]).astype(np.float32)
    for i, (n, *_r) in enumerate(BONES):
        ibm[i][:3, 3] = -np.array(J[n]) * H
    ibm_acc = add(np.ascontiguousarray(ibm.transpose(0, 2, 1)).reshape(-1, 16), 5126, "MAT4")
    body_node = len(nodes)
    nodes.append({"name": "Body", "mesh": 0, "skin": 0})
    root = len(nodes)
    nodes.append({"name": "Soldier", "children": [jnode["Hips"], body_node]})
    for nd in nodes:
        if "children" in nd and not nd["children"]: del nd["children"]
    # weapon: separate rigid object on the hand bone
    if a.weapon:
        wg, wjs, wb = sk.load_geometry(a.weapon)
        mm_w = import_mats(wjs, wb)
        wprim = {"attributes": {"POSITION": add((wg["pos"] * H).astype(np.float32), 5126, "VEC3", 34962, True),
                                "NORMAL": add(wg["nrm"].astype(np.float32), 5126, "VEC3", 34962),
                                "TEXCOORD_0": add(wg["uv"].astype(np.float32), 5126, "VEC2", 34962)},
                 "indices": add(wg["tri"].reshape(-1).astype(np.uint32), 5125, "SCALAR", 34963),
                 "material": mm_w.get(0, 0)}
        meshes.append({"name": "Weapon", "primitives": [wprim]})
        at = np.array([float(v) for v in a.weapon_at.split(",")]) + [a.shift_x, 0, 0]
        hb = jnode[a.weapon_bone]
        wn = len(nodes)
        nodes.append({"name": "Weapon", "mesh": 1, "translation": ((at - np.array(J[a.weapon_bone])) * H).tolist()})
        nodes[hb].setdefault("children", []).append(wn)
    # animations
    anims = []
    for name, ts, rot, trans in make_anims(J, H):
        tacc = add(np.asarray(ts, np.float32), 5126, "SCALAR"); accs[tacc]["min"] = [float(ts[0])]; accs[tacc]["max"] = [float(ts[-1])]
        samplers, channels = [], []
        for bn, qs in rot.items():
            samplers.append({"input": tacc, "output": add(np.asarray(qs, np.float32), 5126, "VEC4"), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": jnode[bn], "path": "rotation"}})
        for bn, vs in trans.items():
            samplers.append({"input": tacc, "output": add(np.asarray(vs, np.float32), 5126, "VEC3"), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": jnode[bn], "path": "translation"}})
        anims.append({"name": name, "samplers": samplers, "channels": channels})
    out = {"asset": {"version": "2.0", "generator": "homelancer rig_humanoid"}, "scene": 0, "scenes": [{"nodes": [root]}],
           "nodes": nodes, "meshes": meshes, "skins": [{"name": "Humanoid", "joints": [jnode[n] for n in NAMES],
           "inverseBindMatrices": ibm_acc, "skeleton": jnode["Hips"]}], "animations": anims,
           "materials": materials, "images": images_all, "textures": textures,
           "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
           "accessors": accs, "bufferViews": views}
    while len(buf) % 4: buf += b"\0"
    out["buffers"] = [{"byteLength": len(buf)}]
    j = json.dumps(out, separators=(",", ":")).encode(); j += b" " * ((-len(j)) % 4)
    with open(a.out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(j) + 8 + len(buf)))
        f.write(struct.pack("<II", len(j), 0x4E4F534A)); f.write(j)
        f.write(struct.pack("<II", len(buf), 0x004E4942)); f.write(bytes(buf))
    dom = joints_idx[np.arange(len(P)), 0]
    print(json.dumps({"bones": len(BONES), "verts": int(len(P)), "tris": int(len(g["tri"])),
                      "verts_per_bone": {NAMES[i]: int((dom == i).sum()) for i in range(len(NAMES))}}))


if __name__ == "__main__":
    main()
