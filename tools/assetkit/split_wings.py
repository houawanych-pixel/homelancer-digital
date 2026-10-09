"""split_wings.py IN.glb OUT.glb CUT_X [TUCK] : NEW copy split into nodes Body / WingL / WingR (triangles whose centre is
past |x| = CUT_X go to the wing on that side). With TUCK the wings are moved that far inward (a closed-form preview);
without it they sit where they are (the open form; the game moves them)."""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb_nodes
P, N, U, I, js, imgs = read(sys.argv[1]); cut = float(sys.argv[3]); tuck = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
cx = P[I].mean(1)[:, 0]
def part(mask):
    f = I[mask]; u, inv = np.unique(f, return_inverse=True)
    return {"pos": P[u], "nrm": N[u], "uv": U[u], "idx": inv.reshape(-1, 3), "mat": 0}
parts = [("Body", [part(np.abs(cx) <= cut)], (0, 0, 0)), ("WingL", [part(cx < -cut)], (tuck, 0, 0)), ("WingR", [part(cx > cut)], (-tuck, 0, 0))]
write_glb_nodes(sys.argv[2], parts, js["materials"][:1], imgs, js["nodes"][0].get("name", "ship"))
print("body", int((np.abs(cx) <= cut).sum()), "wings", int((cx < -cut).sum()), int((cx > cut).sum()))
