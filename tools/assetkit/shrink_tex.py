"""shrink_tex.py IN.glb OUT.glb MAXSIDE : NEW copy with every texture scaled so its longer side is at most MAXSIDE."""
import io, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from symmetrize import read
from glbio import write_glb
from PIL import Image
P, N, U, I, js, imgs = read(sys.argv[1]); M = int(sys.argv[3]); out = []
for b, mime in imgs:
    im = Image.open(io.BytesIO(b)).convert('RGB'); k = min(1.0, M / max(im.size))
    if k < 1.0: im = im.resize((max(4, round(im.size[0] * k)), max(4, round(im.size[1] * k))), Image.LANCZOS)
    o = io.BytesIO(); im.save(o, 'JPEG', quality=84); out.append((o.getvalue(), 'image/jpeg'))
write_glb(sys.argv[2], [{"pos": P, "nrm": N, "uv": U, "idx": I, "mat": 0}], js['materials'][:1], out, js['nodes'][0].get('name', 'ship'))
print(os.path.basename(sys.argv[2]), len(I), 'tris', os.path.getsize(sys.argv[2]) // 1024, 'KB')
