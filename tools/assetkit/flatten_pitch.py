"""flatten_pitch.py IN OUT [extra_deg] : NEW copy turned about X so the model is as flat as it can be (smallest height),
for ships that came in pitched up or down. extra_deg adds a turn after (180 = upside down fix). Prints the angle."""
import sys, os, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
P, N, U, I, js, imgs = read(sys.argv[1]); extra = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
def rx(a):
    c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
best = min(((np.ptp((P @ rx(np.radians(a)).T)[:, 1]), a) for a in np.arange(-90, 90.1, 1.0)))
R = rx(np.radians(best[1] + extra)); P = P @ R.T; N = N @ R.T
P -= (P.min(0) + P.max(0)) / 2
write_glb(sys.argv[2], [{"pos": P, "nrm": N, "uv": U, "idx": I, "mat": 0}], js['materials'][:1], imgs, 'ship')
print(os.path.basename(sys.argv[2]), 'pitch %.0f' % best[1], np.round(np.ptp(P, 0), 3))
