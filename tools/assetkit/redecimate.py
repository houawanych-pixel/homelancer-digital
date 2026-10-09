"""redecimate.py IN_game.glb OUT.glb TARGET : one more decimation pass on a light copy (keeps its textures)."""
import sys, os, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from rsg import read_simple_glb
from glbio import write_glb
P, N, U, I, js, imgs = read(sys.argv[1]); tmp = sys.argv[2] + '.lo.glb'
r = subprocess.run([os.environ.get('GODOT', 'godot'), '--headless', '--path', os.environ.get('HL_REPO', '.'), '--script', 'tools/shipkit/decimate.gd', '--', os.path.abspath(sys.argv[1]), os.path.abspath(tmp), sys.argv[3]], capture_output=True, text=True)
print([l for l in r.stdout.splitlines() if 'DECIMATE' in l])
P2, N2, U2, I2 = read_simple_glb(tmp); os.remove(tmp)
write_glb(sys.argv[2], [{"pos": P2, "nrm": N2, "uv": U2, "idx": I2, "mat": 0}], js['materials'][:1], imgs, js['nodes'][0].get('name', 'piece'))
