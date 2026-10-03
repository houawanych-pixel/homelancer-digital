#!/usr/bin/env python3
"""Make the owner's Tripo space station GLB game-ready (one piece, wheel flat in XZ, tower up +Y).
  python3 tools/gate/make_station.py SOURCE.glb [name]     (needs GODOT=path to the Godot 4.3 binary)
-> assets/structures/<name>.glb  (the "structures" pack; centred, widest side = 1.0, 1024 px maps, STATION_TRIS triangles)"""
import json, os, subprocess, sys
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "shipkit"))
import shipkit as sk
src = sys.argv[1]; name = sys.argv[2] if len(sys.argv) > 2 else "wheel_station"
tris = int(os.environ.get("STATION_TRIS", 10000)); godot = os.environ.get("GODOT", "godot")
g, js, binc = sk.load_geometry(src)
pos, nrm, uv, tri = sk.compact(g["pos"], g["nrm"], g["uv"], g["tri"])
pos = pos - (pos.min(0) + pos.max(0)) / 2
pos = pos / float(max(np.ptp(pos[:, 0]), np.ptp(pos[:, 2])))
mats, images, mat_map = sk.remap_materials(js, binc, [0], 1024)
os.makedirs("build/gate", exist_ok=True)
tmp, out = "build/gate/%s_full.glb" % name, "assets/structures/%s.glb" % name
sk.write_glb(tmp, [(pos, nrm, uv, tri, mat_map.get(0, -1))], mats, images, name)
r = subprocess.run([godot, "--headless", "--path", ".", "--script", "tools/shipkit/decimate.gd", "--", tmp, out, str(tris)], capture_output=True, text=True)
subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "..", "shipkit", "shipkit.py"), "repack", out, "--textures-from", tmp, "--out", out, "--name", name], capture_output=True, text=True)
print(json.dumps({"out": out, "decimate": [l for l in r.stdout.splitlines() if l.startswith("DECIMATE")], "bytes": os.path.getsize(out), "height": round(float(np.ptp(pos[:, 1])), 3)}))
