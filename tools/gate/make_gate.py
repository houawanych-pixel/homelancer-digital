#!/usr/bin/env python3
"""Cut the owner's Tripo jump gate GLB into its two separate pieces and make them game-ready.
  python3 tools/gate/make_gate.py SOURCE.glb            (needs GODOT=path to the Godot 4.3 binary)
Piece 0 = the ring  -> assets/structures/jump_gate_ring.glb   (the "structures" pack; hole along Z, inner radius 1.0, 512 px maps)
Piece 1 = the arch  -> art/models/jump_gate_extra_section.glb   (kept for later use, 1024 px maps)
Uses the shipkit reader/writer and Godot's meshoptimizer (tools/shipkit/decimate.gd) for the polygon reduction."""
import json, os, subprocess, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shipkit"))
import shipkit as sk

RING_TRIS = int(os.environ.get("RING_TRIS", 6000))
EXTRA_TRIS = int(os.environ.get("EXTRA_TRIS", 12000))

def piece(g, js, binc, tcl, i, tex, out, name, ring):
    tri = g["tri"][tcl == i]
    pos, nrm, uv, tri = sk.compact(g["pos"], g["nrm"], g["uv"], tri)
    pos = pos - (pos.min(0) + pos.max(0)) / 2
    rep = {}
    if ring:
        r = np.hypot(pos[:, 0], pos[:, 1])
        thin = np.abs(pos[:, 2]) < 0.25 * np.abs(pos[:, 2]).max()
        inner = float(r[thin].min())
        pos = pos / inner                        # the clear opening has radius 1.0
        rep = {"outer_radius": round(float(np.hypot(pos[:, 0], pos[:, 1]).max()), 3), "depth": round(float(np.ptp(pos[:, 2])), 3)}
    mats, images, mat_map = sk.remap_materials(js, binc, [0], tex)
    sk.write_glb(out, [(pos, nrm, uv, tri, mat_map.get(0, -1))], mats, images, name)
    rep.update(name=name, tris=len(tri))
    return rep

def main():
    src = sys.argv[1]
    godot = os.environ.get("GODOT", "godot")
    g, js, binc = sk.load_geometry(src)
    tcl, info = sk.piece_clusters(g, 0.02)
    # the ring is the piece that is flat and round: widest in two directions, thin in the third
    sizes = [np.sort(d["hi"] - d["lo"]) for d in info]
    ring = int(np.argmax([s[1] / s[2] for s in sizes]))
    extra = [d["id"] for d in info if d["id"] != ring]
    os.makedirs("build/gate", exist_ok=True)
    jobs = [(ring, 512, "build/gate/ring_full.glb", "assets/structures/jump_gate_ring.glb", "JumpGateRing", True, RING_TRIS)]
    for k, e in enumerate(extra):
        suffix = "" if k == 0 else "_%d" % (k + 1)
        jobs.append((e, 1024, "build/gate/extra%s_full.glb" % suffix, "art/models/jump_gate_extra_section%s.glb" % suffix, "JumpGateExtra", False, EXTRA_TRIS))
    for i, tex, tmp, out, name, is_ring, tris in jobs:
        rep = piece(g, js, binc, tcl, i, tex, tmp, name, is_ring)
        r = subprocess.run([godot, "--headless", "--path", ".", "--script", "tools/shipkit/decimate.gd", "--", tmp, out, str(tris)], capture_output=True, text=True)
        line = [l for l in r.stdout.splitlines() if l.startswith("DECIMATE")]
        if os.path.exists(out):      # Godot writes the maps back as big PNGs; put the small JPEGs back
            subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "..", "shipkit", "shipkit.py"), "repack", out, "--textures-from", tmp, "--out", out, "--name", name], capture_output=True, text=True)
        rep.update(out=out, decimate=line[0] if line else r.stderr[-300:], bytes=os.path.getsize(out) if os.path.exists(out) else 0)
        print(json.dumps(rep))

if __name__ == "__main__":
    main()
