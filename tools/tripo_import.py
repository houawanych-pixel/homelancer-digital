#!/usr/bin/env python3
"""HOMELANCER - Tripo asset import (v12.68).

Takes the Tripo GLBs (as exported, often several items on one sheet) and makes game assets:
  * splits a multi-object sheet into one mesh per item (connected pieces grouped by how close they sit)
  * bakes the transforms (scale applied), centres the pivot, lays a weapon along -Z (its longest axis)
  * names them HL_WPN_<Type>_<NN>.glb / HL_SHIP_L3_<Name>_<NN>.glb / HL_PROP_<Name>_<NN>.glb
  * files them: assets/weapons/, assets/ships/level3/, assets/props/  (originals kept in art/tripo_originals/)
  * finds a weapon's grip (the handle under the rear half) and records it as its MountSocket
  * writes a data file per weapon (data/weapons/<id>.json) and rewrites scripts/asset_registry.gd (AssetRegistry:
    MODELS = placeholder key -> new item, ITEMS = every item), which the game reads to swap in the real files
    (tools/asset_registry.json keeps the same list for the next run)

Usage:  python3 tools/tripo_import.py <folder of GLBs> [--kind auto|wpn|ship|prop] [--dry]
The kind and type come from the file name when it says (HL_Weapon_01_Gatling..., HL_SHIP_..., HL_PROP_...);
--kind forces one. Re-running is safe (same names, same numbers, files replaced).
"""
import json, os, re, shutil, sys
import numpy as np
import trimesh

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = {"wpn": "assets/weapons", "ship": "assets/ships/level3", "prop": "assets/props"}
ORIG = "art/tripo_originals"
REG = "tools/asset_registry.json"
REG_GD = "scripts/asset_registry.gd"
ICON = {"blaster": "bolt", "rifle": "rifle", "cannon": "cannon", "rail": "rail", "heavy": "heavy", "missile": "missile"}
KIND = {"wpn": "weapon", "ship": "ship_l3", "prop": "prop"}
WDATA = "data/weapons"
# the code-made placeholders the real models replace: placeholder model key -> weapon type of the real one
PLACEHOLDERS = {"gatling": "Gatling", "rocket_pod": "RocketPod", "missile": "Missile", "mine": "Mine",
                "fleet3_weapon_long": "LongGun", "fleet3_weapon_short": "ShortGun", "fleet3_weapon_pod": "Pod"}
# a weapon type's defaults (class Light / Medium / Heavy, who can use it, which mounts, its numbers)
WTYPES = {
    "Gatling":     {"class": "Medium", "game_class": "rifle",   "users": ["Mech", "Ship"],          "damage": 7,  "rate": 9.0, "ammo": 600, "heat": 3,  "weight": 9,  "energy": 6},
    "Minigun":     {"class": "Medium", "game_class": "rifle",   "users": ["Mech", "Ship"],          "damage": 6,  "rate": 10.0, "ammo": 700, "heat": 3, "weight": 9,  "energy": 6},
    "RotaryGun":   {"class": "Medium", "game_class": "rifle",   "users": ["Mech", "Ship"],          "damage": 8,  "rate": 8.0, "ammo": 500, "heat": 4,  "weight": 10, "energy": 6},
    "RocketPod":   {"class": "Medium", "game_class": "missile", "users": ["Mech", "Ship"],          "damage": 30, "rate": 1.4, "ammo": 36,  "heat": 6,  "weight": 11, "energy": 4},
    "MissilePod":  {"class": "Medium", "game_class": "missile", "users": ["Mech", "Ship"],          "damage": 34, "rate": 1.2, "ammo": 30,  "heat": 6,  "weight": 12, "energy": 4},
    "Pod":         {"class": "Medium", "game_class": "missile", "users": ["Mech", "Ship"],          "damage": 30, "rate": 1.3, "ammo": 32,  "heat": 6,  "weight": 11, "energy": 4},
    "Missile":     {"class": "Heavy",  "game_class": "heavy",   "users": ["Mech", "Ship"],          "damage": 80, "rate": 0.6, "ammo": 12,  "heat": 14, "weight": 20, "energy": 8},
    "Mine":        {"class": "Light",  "game_class": "missile", "users": ["Ship"],                  "damage": 60, "rate": 0.5, "ammo": 10,  "heat": 2,  "weight": 6,  "energy": 2},
    "LongGun":     {"class": "Heavy",  "game_class": "rail",    "users": ["Mech", "Ship"],          "damage": 42, "rate": 1.4, "ammo": 80,  "heat": 14, "weight": 12, "energy": 24},
    "Sniper":      {"class": "Heavy",  "game_class": "rail",    "users": ["Mech", "Ship", "Pilot"], "damage": 48, "rate": 1.0, "ammo": 60,  "heat": 16, "weight": 11, "energy": 22},
    "ShortGun":    {"class": "Light",  "game_class": "blaster", "users": ["Mech", "Ship", "Pilot"], "damage": 11, "rate": 4.5, "ammo": -1,  "heat": 5,  "weight": 6,  "energy": 12},
    "AlienRifle":  {"class": "Medium", "game_class": "rifle",   "users": ["Mech", "Pilot"],         "damage": 16, "rate": 3.5, "ammo": 300, "heat": 5,  "weight": 8,  "energy": 8},
    "Rifle":       {"class": "Medium", "game_class": "rifle",   "users": ["Mech", "Ship", "Pilot"], "damage": 14, "rate": 3.6, "ammo": 360, "heat": 4,  "weight": 8,  "energy": 6},
    "Cannon":      {"class": "Heavy",  "game_class": "cannon",  "users": ["Mech", "Ship"],          "damage": 34, "rate": 1.8, "ammo": 120, "heat": 10, "weight": 13, "energy": 10},
    "Launcher":    {"class": "Heavy",  "game_class": "heavy",   "users": ["Mech", "Ship"],          "damage": 70, "rate": 0.8, "ammo": 20,  "heat": 12, "weight": 19, "energy": 10},
    "Grenade":     {"class": "Light",  "game_class": "missile", "users": ["Pilot"],                 "damage": 50, "rate": 0.6, "ammo": 6,   "heat": 0,  "weight": 1,  "energy": 0},
}
MOUNTS = {"Light": ["L_Arm", "R_Arm", "Nose", "Wing_L", "Wing_R", "Ventral"],
          "Medium": ["L_Arm", "R_Arm", "L_Shoulder", "R_Shoulder", "Wing_L", "Wing_R", "Ventral", "Dorsal"],
          "Heavy": ["L_Shoulder", "R_Shoulder", "Dorsal", "Ventral"]}

def guess(fname, forced):
    b = os.path.splitext(os.path.basename(fname))[0]
    kind = forced if forced != "auto" else ("ship" if re.search(r"ship|_L3_", b, re.I) else "prop" if re.search(r"prop|crate|wall|door|ammo.?case", b, re.I) else "wpn")
    b = re.sub(r"_?Sheet_?", "_", b).strip("_")   # (HL_WPN_Sheet_GrayModules -> GrayModules; WhiteFighter_Sheet -> WhiteFighter)
    m = re.match(r"HL_(?:Weapon|WPN)_(?:\d+_)?([A-Za-z]+)", b) or re.match(r"HL_(?:SHIP_L3|PROP)_([A-Za-z]+)", b)
    name = m.group(1) if m else re.sub(r"[^A-Za-z]", "", b.split("_")[-1] or b)[:24] or "Item"
    return kind, name

def items_of(path):
    """the sheet's items: connected pieces (by shared faces), joined when their surfaces touch. Works on face index
    lists (no copy of the texture per piece), then cuts one mesh per item."""
    sc = trimesh.load(path, force="scene")
    mesh = sc.to_geometry() if hasattr(sc, "to_geometry") else sc.dump(concatenate=True)
    mesh.merge_vertices(merge_tex=True, merge_norm=True)
    comps = trimesh.graph.connected_components(mesh.face_adjacency, nodes=np.arange(len(mesh.faces)), min_len=1)
    n = len(comps)
    if n == 0: return []
    diag = float(np.linalg.norm(mesh.bounds[1] - mesh.bounds[0]))
    par = list(range(n))
    def f(i):
        while par[i] != i:
            par[i] = par[par[i]]; i = par[i]
        return i
    # pieces of one item touch (their surfaces within `gap`); pieces of two items only sit near each other. Box overlap
    # is not enough on a crowded sheet, so: points sampled on every piece, pairs closer than `gap` join their pieces.
    gap = diag * float(os.environ.get("HL_SPLIT_GAP", "0.004"))
    from scipy.spatial import cKDTree
    pts, lab = [], []
    for i, fc in enumerate(comps):
        v = np.unique(mesh.faces[fc].ravel())
        if len(v) > 600: v = v[np.random.default_rng(i).choice(len(v), 600, replace=False)]
        pts.append(mesh.vertices[v]); lab.append(np.full(len(v), i))
    pts = np.concatenate(pts); lab = np.concatenate(lab)
    for a, b in cKDTree(pts).query_pairs(gap, output_type="ndarray"):
        if lab[a] != lab[b]: par[f(int(lab[a]))] = f(int(lab[b]))
    groups = {}
    for i in range(n): groups.setdefault(f(i), []).append(comps[i])
    faces = [np.concatenate(g) for g in groups.values()]
    total = sum(len(x) for x in faces)
    faces = [x for x in faces if len(x) >= total * 0.01] or faces
    meshes = [mesh.submesh([x], append=True) for x in faces]
    top = max(float(max(m.extents)) for m in meshes)
    keep = [m for m in meshes if float(max(m.extents)) >= top * float(os.environ.get("HL_MIN_SIZE", "0.3"))]   # (bits and magazines left out)
    if os.environ.get("HL_ELONGATED"):   # ships: only the long ones (a ship drawn nose-on comes out a flat disc)
        keep = [m for m in keep if sorted(m.extents)[-1] >= sorted(m.extents)[-2] * float(os.environ["HL_ELONGATED"])]
    meshes = keep or meshes
    meshes.sort(key=lambda m: (round(float(m.bounds[0][2]) / max(diag * 0.2, 1e-6)), float(m.bounds[0][0])))   # rows back to front, then left to right (the sheet lies flat)
    return meshes

def light_tex(m, size=1024):
    """the game copy: only the colour map, at most `size` px, as JPEG (phones)"""
    import io
    from PIL import Image
    mat = getattr(m.visual, "material", None)
    if mat is None: return
    img = getattr(mat, "baseColorTexture", None)
    if img is not None:
        im = img.convert("RGB")
        if max(im.size) > size: im = im.resize((size, size), Image.LANCZOS)
        b = io.BytesIO(); im.save(b, "JPEG", quality=85); b.seek(0)
        mat.baseColorTexture = Image.open(b)
    for k in ("normalTexture", "metallicRoughnessTexture", "occlusionTexture", "emissiveTexture"):
        if hasattr(mat, k): setattr(mat, k, None)

def classify(m, top):
    """a weapon type from its shape (after lay_weapon: length on Z) and its size next to the sheet's biggest item `top`:
    long and slim = LongGun (rail), slim = Rifle, small = ShortGun, fat = RocketPod, else Cannon. All of these fit a
    ship's wing / belly, a mech and (with --all-users) the pilot's hands."""
    L = float(m.extents[2]); w = float(max(m.extents[0], m.extents[1])); r = L / max(w, 1e-6); k = L / max(top, 1e-6)
    if r >= 2.8: return "LongGun" if k >= 0.75 else "Rifle"
    if k < 0.45: return "ShortGun"
    if r < 1.6: return "RocketPod"
    return "Cannon"

def lay_ship(m):
    """a ship's longest flat side along Z, nose (the thinner end) to -Z, sitting centred; returns its yaw note"""
    ext = m.extents
    ax = int(np.argmax(ext))
    if ax == 0: m.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [0, 1, 0]))      # a side view: length on X
    elif ax == 1: m.apply_transform(trimesh.transformations.rotation_matrix(-np.pi / 2, [1, 0, 0]))  # a top view stood up on the sheet: lay it flat, its top up
    m.apply_translation(-m.bounds.mean(axis=0))
    v = m.vertices; zs = v[:, 2]; lo, hi = zs.min(), zs.max()
    def width(sel): return float(np.ptp(v[sel][:, 0])) if np.any(sel) else 0.0
    if width(zs < lo + (hi - lo) * 0.25) > width(zs > hi - (hi - lo) * 0.25): m.apply_transform(trimesh.transformations.rotation_matrix(np.pi, [0, 1, 0]))

def lay_weapon(m):
    """the weapon's longest side along -Z, its pivot at the middle of its box; returns the grip (MountSocket)"""
    ext = m.extents
    ax = int(np.argmax(ext))
    if ax == 0: m.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [0, 1, 0]))
    elif ax == 1: m.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [1, 0, 0]))
    m.apply_translation(-m.bounds.mean(axis=0))
    v = m.vertices
    # the muzzle end is the thinner one: point it at -Z
    zs = v[:, 2]
    lo, hi = zs.min(), zs.max()
    thick_front = np.ptp(v[zs < lo + (hi - lo) * 0.2][:, 1]) if np.any(zs < lo + (hi - lo) * 0.2) else 0
    thick_back = np.ptp(v[zs > hi - (hi - lo) * 0.2][:, 1]) if np.any(zs > hi - (hi - lo) * 0.2) else 0
    if thick_front > thick_back: m.apply_transform(trimesh.transformations.rotation_matrix(np.pi, [0, 1, 0]))
    v = m.vertices
    # the grip: the lowest stuff in the rear half (a handle hangs down behind the middle)
    rear = v[v[:, 2] > 0]
    if len(rear) == 0: rear = v
    ylo = rear[:, 1].min()
    hand = rear[rear[:, 1] < ylo + np.ptp(v[:, 1]) * 0.25]
    sock = [float(hand[:, 0].mean()), float(hand[:, 1].max()), float(hand[:, 2].mean())]
    return sock

def gd(v):
    """a Python value as GDScript constant text"""
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str): return json.dumps(v)
    if isinstance(v, (list, tuple)): return "[" + ", ".join(gd(x) for x in v) + "]"
    if isinstance(v, dict): return "{" + ", ".join("%s: %s" % (json.dumps(str(k)), gd(x)) for k, x in v.items()) + "}"
    return "null"

def write_gd(reg):
    lines = ["class_name AssetRegistry", "extends RefCounted",
             "## v12.68 (owner's spec: \"Tripo Asset Import\"): written by tools/tripo_import.py, never by hand.",
             "## MODELS: an old model key -> the new split Tripo item that replaces it (ShipFactory loads the new one).",
             "## ITEMS: every split item: id -> {kind, path, len, socket (the grip, as a share of its length), data (weapon stats)}.",
             "", "const MODELS := " + gd(reg["models"]),
             "const ITEMS := {"]
    for k, v in reg["items"].items(): lines.append("\t%s: %s," % (json.dumps(k), gd(v)))
    lines.append("}")
    lines.append("const PLACEHOLDERS := " + gd(list(PLACEHOLDERS.keys())))
    open(os.path.join(ROOT, REG_GD), "w").write("\n".join(lines) + "\n")

def main():
    if len(sys.argv) < 2:
        print(__doc__); return 1
    src = sys.argv[1]
    forced = sys.argv[sys.argv.index("--kind") + 1] if "--kind" in sys.argv else "auto"
    dry = "--dry" in sys.argv
    regp = os.path.join(ROOT, REG)
    reg = json.load(open(regp)) if os.path.exists(regp) else {"models": {}, "items": {}}
    files = sorted(f for f in os.listdir(src) if f.lower().endswith(".glb"))
    made = []
    for f in files:
        path = os.path.join(src, f)
        kind, name = guess(f, forced)
        items = items_of(path)
        if not dry:
            os.makedirs(os.path.join(ROOT, ORIG), exist_ok=True)
            shutil.copy2(path, os.path.join(ROOT, ORIG, f))
        prefix = {"wpn": "HL_WPN", "ship": "HL_SHIP_L3", "prop": "HL_PROP"}[kind]
        top_len = max(float(max(x.extents)) for x in items) if items else 1.0
        for k, m in enumerate(items):
            nid = "%s_%s_%02d" % (prefix, name, k + 1)
            rec = {"id": nid, "kind": KIND[kind], "type": name, "path": "res://%s/%s.glb" % (OUT[kind], nid), "source": f}
            if kind == "wpn":
                sock = lay_weapon(m)
                L = float(max(m.extents))
                rec["socket"] = [round(x / L, 4) for x in sock]   # (as a share of the gun's length: the game sizes it per user)
                rec["len"] = 3.0
                wt = name if name in WTYPES else classify(m, top_len)
                t = dict(WTYPES[wt])
                if "--all-users" in sys.argv: t["users"] = ["Mech", "Ship", "Pilot"]   # (the owner: every one on mechs, ships and in the pilot's hands)
                data = {"id": nid, "name": "%s %s %d" % (re.sub(r"(?<!^)(?=[A-Z])", " ", name), re.sub(r"(?<!^)(?=[A-Z])", " ", wt), k + 1), "short": ("%s %d" % (wt, k + 1))[:12], "type": wt, "class": t["class"],
                        "game_class": t["game_class"], "users": t["users"], "mounts": MOUNTS[t["class"]], "damage": t["damage"], "rate": t["rate"],
                        "ammo": t["ammo"], "heat": t["heat"], "weight": t["weight"], "energy": t["energy"], "icon": ICON[t["game_class"]]}
                rec["data"] = data
            elif kind == "ship":
                lay_ship(m)
                rec["size"] = [round(float(x), 3) for x in m.extents]
                rec["len"] = float(max(m.extents))
            else:
                m.apply_translation(-m.bounds.mean(axis=0))
                m.apply_translation([0, float(m.extents[1]) * 0.5, 0])   # (props stand on the floor)
                rec["size"] = [round(float(x), 3) for x in m.extents]
                rec["len"] = round(float(max(m.extents)), 3)
            if not dry:
                os.makedirs(os.path.join(ROOT, OUT[kind]), exist_ok=True)
                light_tex(m)
                m.export(os.path.join(ROOT, OUT[kind], nid + ".glb"))
                if kind == "wpn":
                    os.makedirs(os.path.join(ROOT, WDATA), exist_ok=True)
                    json.dump(rec["data"], open(os.path.join(ROOT, WDATA, nid + ".json"), "w"), indent=1)
            reg["items"][nid] = rec
            made.append(nid)
        if kind == "ship" and items:   # the sheet's ships keep their sizes to each other: the biggest 46 m, none under 16 m
            ids = made[-len(items):]
            big = max(float(reg["items"][i]["len"]) for i in ids)
            for i in ids: reg["items"][i]["len"] = round(16.0 + 30.0 * float(reg["items"][i]["len"]) / max(big, 1e-6), 1)
            for ph, typ in PLACEHOLDERS.items():   # the first of a type replaces its placeholder
                if kind == "wpn" and typ == name and k == 0: reg["models"][ph] = nid
    if not dry:
        os.makedirs(os.path.dirname(regp), exist_ok=True)
        json.dump(reg, open(regp, "w"), indent=1)
        write_gd(reg)
    print("made %d: %s" % (len(made), ", ".join(made)))
    missing = [p for p in PLACEHOLDERS if p not in reg["models"]]
    print("placeholders still code-made: %s" % (", ".join(missing) if missing else "none"))
    return 0

if __name__ == "__main__":
    sys.exit(main())
