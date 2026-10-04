#!/usr/bin/env python3
"""Planet maps for the game, from NASA's public maps (art/planet_maps, taken from github.com/nasa/NASA-3D-Resources,
"Images and Textures"; NASA media usage guidelines apply) -> assets/worlds/<name>.jpg (the "worlds" pack).
  python3 tools/planets/make_worlds.py
A planet map is an EQUIRECTANGULAR picture: twice as wide as tall, left edge = right edge, top row = north pole.
To add your own world: drop a 2:1 picture in art/planet_maps, add a line to MAPS below, run this, and name the map
in PLANET_LOOKS (scripts/space.gd). The tool makes it 1024 x 512, closes the left/right seam, fills black gaps
(places the spacecraft never photographed) with the map's own colours, and softens the poles.
Also writes assets/worlds/clouds.jpg: one seamless cloud layer shared by every world with weather."""
import os
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

W, H = 1024, 512
# output name: (source file, gamma, saturation)   gamma < 1 brightens, > 1 darkens
MAPS = {
    "earth": ("earth_a.jpg", 1.0, 0.8), "mars": ("mars.jpg", 1.0, 1.0), "venus": ("venus.jpg", 1.0, 1.0),
    "jupiter": ("jupiter.jpg", 1.0, 1.0), "saturn": ("saturn.jpg", 1.0, 0.9), "neptune": ("neptune.jpg", 1.0, 1.0),
    "europa": ("jupiter_europa.jpg", 1.1, 1.0), "io": ("jupiter_io_a.jpg", 1.0, 1.0), "ganymede": ("jupiter_ganymede.jpg", 1.15, 1.0),
    "pluto": ("pluto.jpg", 1.0, 1.0), "charon": ("pluto_charon.jpg", 1.0, 1.0),
    "titan": ("saturn_titan.jpg", 1.0, 1.0),
}
root = os.path.join(os.path.dirname(__file__), "..", "..")

def fix(a):
    a = a.astype(np.float32)
    # gaps: pure-black areas get the blurred colour of what surrounds them
    gap = (a.max(2) < 10).astype(np.float32)
    if gap.mean() > 0.002:
        w = 1.0 - gap
        blur = gaussian_filter(a * w[..., None], (18, 18, 0), mode="wrap") / np.maximum(gaussian_filter(w, 18, mode="wrap")[..., None], 1e-3)
        soft = gaussian_filter(gap, 3, mode="wrap")[..., None]
        a = a * (1 - soft) + blur * soft
    # left/right seam: ramp the difference between the two edges away over a wide band
    d = (a[:, :4].mean(1) - a[:, -4:].mean(1))[:, None, :]
    band = W // 6
    ramp = (1 - np.arange(band) / band)[None, :, None] ** 2
    a[:, :band] -= d * 0.5 * ramp
    a[:, -band:] += d * 0.5 * ramp[:, ::-1]
    # poles: blend the top and bottom rows toward their own average so there is no pinch
    for y in range(24):
        k = (y / 24.0) ** 2
        for row in (y, H - 1 - y):
            a[row] = a[row] * k + a[row].mean(0) * (1 - k)
    return np.clip(a, 0, 255)

def clouds(seed=7):
    """Seamless cloud cover: noise made on the sphere itself, so it wraps and has no pole pinch."""
    rng = np.random.default_rng(seed)
    lat = (np.arange(H) + 0.5) / H * np.pi - np.pi / 2
    lon = (np.arange(W) + 0.5) / W * 2 * np.pi
    x = np.cos(lat)[:, None] * np.cos(lon)[None, :]; y = np.sin(lat)[:, None] * np.ones(W)[None, :]; z = np.cos(lat)[:, None] * np.sin(lon)[None, :]
    v = np.zeros((H, W), np.float32); amp = 1.0
    for octave in range(6):
        f = 1.6 * 2 ** octave
        for _ in range(10):
            d = rng.normal(size=3); d /= np.linalg.norm(d)
            v += amp * np.sin(f * (x * d[0] + y * d[1] + z * d[2]) * 2.2 + rng.uniform(0, 6.28))
        amp *= 0.62
    v += 2.0 * np.sin(lat * 6.0)[:, None] * 0.35           # weather bands
    v = (v - v.mean()) / v.std()
    c = np.clip((v + 0.35) / 1.7, 0, 1) ** 1.15
    return (c * 255).astype(np.uint8)

os.makedirs(os.path.join(root, "assets/worlds"), exist_ok=True)
for name, (src, gamma, sat) in MAPS.items():
    im = Image.open(os.path.join(root, "art/planet_maps", src)).convert("RGB").resize((W, H), Image.LANCZOS)
    a = fix(np.asarray(im))
    g = a.mean(2, keepdims=True)
    a = np.clip(g + (a - g) * sat, 0, 255)
    a = 255.0 * (a / 255.0) ** gamma
    Image.fromarray(a.astype(np.uint8)).save(os.path.join(root, "assets/worlds", name + ".jpg"), quality=88)
Image.fromarray(clouds()).save(os.path.join(root, "assets/worlds/clouds.jpg"), quality=85)
print(len(MAPS), "maps + clouds ->", "assets/worlds")
