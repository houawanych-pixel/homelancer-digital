"""tint.py IN OUT r g b [amount] : NEW copy with the colour texture tinted toward a colour (keeps the light/dark detail):
the faction colour on a placeholder ship. amount 0..1 (default 0.6)."""
import io, os, sys, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
from PIL import Image
P, N, U, I, js, imgs = read(sys.argv[1]); col = np.array([float(x) for x in sys.argv[3:6]]); k = float(sys.argv[6]) if len(sys.argv) > 6 else 0.6
out = []
for n, (b, mime) in enumerate(imgs):
    im = Image.open(io.BytesIO(b)).convert('RGB')
    if n == 0:
        a = np.asarray(im).astype(np.float32) / 255.0
        lum = (a @ np.array([0.3, 0.59, 0.11]))[..., None]
        t = np.clip(lum * col * 1.6, 0, 1)
        im = Image.fromarray((np.clip(a * (1 - k) + t * k, 0, 1) * 255).astype(np.uint8))
    o = io.BytesIO(); im.save(o, 'JPEG', quality=88); out.append((o.getvalue(), 'image/jpeg'))
write_glb(sys.argv[2], [{"pos": P, "nrm": N, "uv": U, "idx": I, "mat": 0}], js['materials'][:1], out, js['nodes'][0].get('name', 'ship'))
