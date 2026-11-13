#!/usr/bin/env python3
"""v13.102 (owner's quarters: the crossfade stitch ghosted a second chair, pillar and plant): ChatGPT redraws the
"copied" thirds of a join row a little shifted (often 100+ px), so blending them over the originals doubles things.
Here the originals stay whole and only the NEW middle of each join row goes in, cut hard (no blend):
for each row, SIFT finds where the row's left copy sits against the first view's right end and where its right copy
sits against the second view's left start; the strip of the row between those two points is the join.

    python3 tools/rooms/stitch_hard.py <split.png> <joins_filled.png> <out.jpg>"""
import sys
import cv2, numpy as np
src, fil, out = sys.argv[1:4]
im = cv2.imread(src); H, W = im.shape[:2]; m = H // 2
top = im[:m - 6]; bot = im[m + 6:]; h = min(len(top), len(bot)); top, bot = top[:h], bot[:h]
j = cv2.resize(cv2.imread(fil), (W, H)); r1 = j[:h]; r2 = j[H - h:]
sift = cv2.SIFT_create(4000)
def off(view, vx0, vx1, row, rx0, rx1):
    """median (dx, dy, n): row_x = view_x + dx for matches between view[:, vx0:vx1] and row[:, rx0:rx1]"""
    k1, d1 = sift.detectAndCompute(cv2.cvtColor(view[:, vx0:vx1], cv2.COLOR_BGR2GRAY), None)
    k2, d2 = sift.detectAndCompute(cv2.cvtColor(row[:, rx0:rx1], cv2.COLOR_BGR2GRAY), None)
    ms = [a for a, b in cv2.BFMatcher().knnMatch(d1, d2, k=2) if a.distance < 0.75 * b.distance]
    dx = np.array([(k2[q.trainIdx].pt[0] + rx0) - (k1[q.queryIdx].pt[0] + vx0) for q in ms])
    dy = np.array([k2[q.trainIdx].pt[1] - k1[q.queryIdx].pt[1] for q in ms])
    med = np.median(dx); keep = np.abs(dx - med) < 6
    return float(np.median(dx[keep])), float(np.median(dy[keep])), int(keep.sum())
segs = []
for a, b, row in ((top, bot, r1), (bot, top, r2)):
    dl = off(a, W * 2 // 3, W, row, 0, W // 2)        # a's right end in the row
    dr = off(b, 0, W // 3, row, W // 2, W)            # b's left start in the row
    x0 = int(round(W + dl[0])); x1 = int(round(0 + dr[0]))
    print("row: left copy dx %.0f dy %.1f (%d), right copy dx %.0f dy %.1f (%d) -> join %d..%d (%d px)" % (dl + dr + (x0, x1, x1 - x0)))
    if x1 - x0 < 8: sys.exit("the join is too narrow: the row's ends overlap; ask for a wider gap")
    seg = row[:, x0:x1].astype(np.float32)
    seg = np.roll(seg, -int(round((dl[1] + dr[1]) / 2)), 0)   # (vertical shift back)
    # colour: one gain per channel, from the row's copies against the originals they copy (whole areas, not edges)
    ca = row[:, max(0, x0 - 250):x0].astype(np.float32); oa = a[:, W - ca.shape[1]:].astype(np.float32)
    cb = row[:, x1:x1 + 250].astype(np.float32); ob = b[:, :cb.shape[1]].astype(np.float32)
    for c in range(3):
        g = (oa[..., c].mean() + ob[..., c].mean()) / max(ca[..., c].mean() + cb[..., c].mean(), 1)
        seg[..., c] *= g
    segs.append(np.clip(seg, 0, 255).astype(np.uint8))
loop = np.concatenate([top, segs[0], bot, segs[1]], 1)
cv2.imwrite(out, loop, [cv2.IMWRITE_JPEG_QUALITY, 90]); print(out, loop.shape[1], "x", h)
