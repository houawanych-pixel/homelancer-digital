#!/usr/bin/env python3
"""v12.84 install_mechs.py — the rigged mechs from build_mechs.sh into the game.

  python3 tools/mechkit/install_mechs.py WORK_DIR

For each WORK/HL_MECH_<...>_rigged.glb in NAMES: copies it to assets/mech_frames/mf_<fid>.glb, lets Godot import it
(textures come out as mf_<fid>_N.jpg), bakes the pre-cut .scn with tools/shipkit/mech_bake.gd (Part_arms / core / legs),
then removes the .glb (the game loads the .scn, like the other frames). Points tools/asset_registry.json and
scripts/asset_registry.gd at the .scn and marks the Tripo pieces that are not humanoid mechs as held back.
"""
import json, os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.environ.get("GODOT", "/home/claude/godot/Godot_v4.3-stable_linux.x86_64")
NAMES = {"HL_MECH_ChromeBlueGoldRobot": "chromebg"}
NAMES.update({"HL_MECH_FactionMechaLineup_%02d" % i: "fml%02d" % i for i in range(1, 25)})
HELD = {"HL_MECH_ArticulatedLegs": "a box body on legs, not a humanoid mech (can't take the walking rig)",
        "HL_MECH_HeavyRectangularMech": "a long block, not a humanoid mech (can't take the walking rig)",
        "HL_MECH_WarframeBlockMech": "a block, not a humanoid mech (can't take the walking rig)"}

def main():
    work = sys.argv[1]
    dst = os.path.join(ROOT, "assets/mech_frames")
    todo = []
    for n, fid in NAMES.items():
        src = os.path.join(work, n + "_rigged.glb")
        if not os.path.exists(src):
            print("missing", src); continue
        out = os.path.join(dst, "mf_%s.glb" % fid)
        shutil.copy2(src, out)
        todo.append("res://assets/mech_frames/mf_%s.glb" % fid)
    subprocess.run([GODOT, "--headless", "--path", ROOT, "--editor", "--import", "--quit"], capture_output=True, timeout=1800)
    r = subprocess.run([GODOT, "--headless", "--path", ROOT, "--script", "res://tools/shipkit/mech_bake.gd", "--"] + todo,
                       capture_output=True, text=True, timeout=1800)
    print("\n".join(l for l in r.stdout.splitlines() if l.startswith("BAKE")))
    for t in todo:
        p = os.path.join(ROOT, t[len("res://"):])
        if os.path.exists(p[:-4] + ".scn"):
            for x in (p, p + ".import"):
                if os.path.exists(x): os.remove(x)
    regp = os.path.join(ROOT, "tools/asset_registry.json")
    reg = json.load(open(regp))
    for n, rec in reg["items"].items():
        if rec.get("kind") != "mech": continue
        if n in NAMES:
            rec["path"] = "res://assets/mech_frames/mf_%s.scn" % NAMES[n]
            rec["frame"] = NAMES[n]
            rec.pop("held", None)
        elif n in HELD:
            rec["path"] = ""
            rec["held"] = HELD[n]
    json.dump(reg, open(regp, "w"), indent=1)
    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import tripo_import
    tripo_import.write_gd(reg)
    print("registry updated")

if __name__ == "__main__":
    main()
