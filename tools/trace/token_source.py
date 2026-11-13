#!/usr/bin/env python3
"""Ships with no HoloDeck sheet (Solarion, Savagers): make the trace folder's source.jpg from the fleet token
(assets/fleet_tokens/<faction>_<class>.png), sized like the traced sheets (1024 x 1536, the ship about 132 m long at
10 px = 1 m, nose up, centred on x 512) on a dark blue map, plus source_mask.png (the token's own alpha) so
decklib.hull reads the silhouette exactly.   usage: python3 -I tools/trace/token_source.py solarion_capital [...]"""
import os, sys
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
W, H, LONG, MAXW = 1024, 1536, 1320, 940


def make(sid):
    tok = Image.open(os.path.join(ROOT, "assets", "fleet_tokens", sid + ".png")).convert("RGBA")
    a = np.array(tok)[:, :, 3]
    ys, xs = np.where(a > 40)
    tok = tok.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    k = min(LONG / tok.size[1], MAXW / tok.size[0])
    big = tok.resize((round(tok.size[0] * k), round(tok.size[1] * k)), Image.LANCZOS)
    x0, y0 = (W - big.size[0]) // 2, (H - big.size[1]) // 2
    bg = Image.new("RGBA", (W, H), (8, 16, 34, 255))
    grid = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    g = np.array(grid)
    g[::40, :, :] = (30, 60, 90, 120); g[:, ::40, :] = (30, 60, 90, 120)
    bg = Image.alpha_composite(bg, Image.fromarray(g))
    bg.alpha_composite(big, (x0, y0))
    mask = Image.new("L", (W, H), 0)
    mask.paste(big.getchannel("A").point(lambda v: 255 if v > 110 else 0).filter(ImageFilter.MedianFilter(5)), (x0, y0))
    out = os.path.join(ROOT, "tools", "trace", "fleet_" + sid)
    os.makedirs(os.path.join(out, "eng"), exist_ok=True)
    bg.convert("RGB").save(os.path.join(out, "source.jpg"), quality=88)
    mask.save(os.path.join(out, "source_mask.png"), optimize=True)
    print(sid, "ship %d x %d px (%.0f x %.0f m)" % (big.size[0], big.size[1], big.size[0] / 10, big.size[1] / 10))


if __name__ == "__main__":
    for s in sys.argv[1:]:
        make(s)
