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
    m = re.match(r"HL_(?:Weapon|WPN)_(?:\d+_)?([A-Za-z]+)", b) or re.match(r"HL_(?:SHIP_L3|PROP)_([A-Za-z]+)", b)
    name = m.group(1) if m else re.sub(r"[^A-Za-z]", "", b.split("_")[-1] or b)[:24] or "Item"
    return kind, name

def items_of(path):
    """the sheet's items: connected pieces, grouped when their boxes touch or nearly touch"""
    sc = trimesh.load(path, force="scene")
    mesh = sc.to_geometry() if hasattr(sc, "to_geometry") else sc.dump(concatenate=True)
    parts = mesh.split(only_watertight=False)
    if len(parts) == 0: return []
    diag = float(np.linalg.norm(mesh.bounds[1] - mesh.bounds[0]))
    gap = diag * 0.02
    n = len(parts)
    par = list(range(n))
    def f(i):
        while par[i] != i:
            par[i] = par[par[i]]; i = par[i]
        return i
    bx = [p.bounds for p in parts]
    for i in range(n):
        for j in range(i + 1, n):
            a, b = bx[i], bx[j]
            if np.all(a[0] - gap <= b[1]) and np.all(b[0] - gap <= a[1]):
                par[f(i)] = f(j)
    groups = {}
    for i in range(n): groups.setdefault(f(i), []).append(parts[i])
    meshes = [trimesh.util.concatenate(g) for g in groups.values()]
    total = sum(len(m.vertices) for m in meshes)
    big = [m for m in meshes if len(m.vertices) >= total * 0.01] or meshes
    big.sort(key=lambda m: (round(float(m.bounds[0][1]) / max(diag * 0.25, 1e-6)) * -1, float(m.bounds[0][0])))   # rows top-down, left-right
    return big

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
        for k, m in enumerate(items):
            nid = "%s_%s_%02d" % (prefix, name, k + 1)
            rec = {"id": nid, "kind": KIND[kind], "type": name, "path": "res://%s/%s.glb" % (OUT[kind], nid), "source": f}
            if kind == "wpn":
                sock = lay_weapon(m)
                L = float(max(m.extents))
                rec["socket"] = [round(x / L, 4) for x in sock]   # (as a share of the gun's length: the game sizes it per user)
                rec["len"] = 3.0
                t = WTYPES.get(name, WTYPES["Rifle"])
                data = {"id": nid, "name": "%s %s" % (re.sub(r"(?<!^)(?=[A-Z])", " ", name), k + 1), "short": name[:10], "class": t["class"],
                        "game_class": t["game_class"], "users": t["users"], "mounts": MOUNTS[t["class"]], "damage": t["damage"], "rate": t["rate"],
                        "ammo": t["ammo"], "heat": t["heat"], "weight": t["weight"], "energy": t["energy"], "icon": ICON[t["game_class"]]}
                rec["data"] = data
            else:
                m.apply_translation(-m.bounds.mean(axis=0))
                m.apply_translation([0, float(m.extents[1]) * 0.5, 0])   # (props stand on the floor)
                rec["size"] = [round(float(x), 3) for x in m.extents]
                rec["len"] = 16.0 if kind == "ship" else round(float(max(m.extents)), 3)
            if not dry:
                os.makedirs(os.path.join(ROOT, OUT[kind]), exist_ok=True)
                m.export(os.path.join(ROOT, OUT[kind], nid + ".glb"))
                if kind == "wpn":
                    os.makedirs(os.path.join(ROOT, WDATA), exist_ok=True)
                    json.dump(rec["data"], open(os.path.join(ROOT, WDATA, nid + ".json"), "w"), indent=1)
            reg["items"][nid] = rec
            made.append(nid)
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
