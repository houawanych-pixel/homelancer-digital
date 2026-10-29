"""Green-screen key for the owner's character art: transparent background, green spill unmixed at the edges,
green details inside the character kept (only green connected to the picture's border is keyed)."""
import sys, numpy as np
from PIL import Image
from scipy import ndimage
B = np.array([3.0, 250.0, 3.0])
def key(path):
    p = np.array(Image.open(path).convert('RGB')).astype(np.float32)
    s = p[..., 1] - np.maximum(p[..., 0], p[..., 2])          # how green
    S_BG = 240.0
    cand = s > 70.0
    lab, n = ndimage.label(cand)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    # also the holes the background shows through (between an arm and the body, gaps in hair): near-pure key green
    med = ndimage.median(s, lab, index=np.arange(1, n + 1)) if n else []
    keep = [i + 1 for i, m in enumerate(med) if m > 215.0]
    bg = np.isin(lab, list(edge | set(keep)))
    zone = ndimage.binary_dilation(bg, iterations=3)          # the background and a thin band round it
    # key green seen through dark hair / thin gaps: green with almost no red or blue in it, touching the background
    mixed = (s > 60.0) & (np.maximum(p[..., 0], p[..., 2]) < 40.0)
    mixed = mixed & ndimage.binary_dilation(bg, iterations=40)
    zone |= mixed
    # green showing through sheer fabric and loose hair anywhere: key-coloured (red and blue about equal, green well
    # above both); those pixels are unmixed too, so the cloth stays see-through instead of green
    rb = np.abs(p[..., 0] - p[..., 2])
    sheer = (s > 45.0) & (rb < 0.35 * s + 8.0)
    zone |= sheer
    a = np.ones(s.shape, np.float32)
    est = 1.0 - np.clip((s - 25.0) / (S_BG - 25.0), 0.0, 1.0)
    a[zone] = est[zone]
    a[bg & (s > S_BG - 12)] = 0.0
    # unmix the background out of the edge pixels: p = a F + (1 - a) B
    aa = np.maximum(a, 0.05)[..., None]
    F = np.clip((p - (1.0 - aa) * B) / aa, 0, 255)
    F = np.where(zone[..., None], F, p)
    # what is left of the spill on the edge: green no higher than the brighter of red / blue (edge band only)
    g_cap = np.maximum(F[..., 0], F[..., 2]) * 1.08 + 6
    F[..., 1] = np.where(zone & (a < 0.98), np.minimum(F[..., 1], g_cap), F[..., 1])
    a = ndimage.uniform_filter(a, 2)                          # (a touch softer, no jaggies)
    out = np.dstack([F, a * 255]).astype(np.uint8)
    return Image.fromarray(out, 'RGBA')
if __name__ == '__main__':
    key(sys.argv[1]).save(sys.argv[2])
