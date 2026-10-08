"""tame_metal.py IN.glb OUT.glb [max_metal=0.25] [min_rough=0.55] : NEW copy whose metallic/roughness texture is clamped, so a
chrome-like set (smooth + very metallic) does not render as a black silhouette in the game, which has no reflections."""
import io, os, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
from PIL import Image
P, N, U, I, js, imgs = read(sys.argv[1]); mm = float(sys.argv[3]) if len(sys.argv) > 3 else 0.25; mr = float(sys.argv[4]) if len(sys.argv) > 4 else 0.55
out = [imgs[0]]
if len(imgs) > 1:
    a = np.array(Image.open(io.BytesIO(imgs[1][0])).convert('RGB')).astype(np.float32) / 255
    a[..., 1] = np.maximum(a[..., 1], mr); a[..., 2] = np.minimum(a[..., 2], mm)
    b = io.BytesIO(); Image.fromarray((a * 255).astype(np.uint8)).save(b, 'JPEG', quality=80); out.append((b.getvalue(), 'image/jpeg'))
write_glb(sys.argv[2], [{"pos": P, "nrm": N, "uv": U, "idx": I, "mat": 0}], js['materials'][:1], out, js['nodes'][0].get('name', 'ship'))
print(os.path.basename(sys.argv[2]), 'metal <=', mm, 'rough >=', mr)
