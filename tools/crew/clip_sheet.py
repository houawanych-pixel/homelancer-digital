#!/usr/bin/env python3
"""Turn a magenta-screen character clip into a game sprite sheet (v11.17, the lockdown fighters).

    python3 tools/crew/clip_sheet.py <clip.mp4> <out_base> --from S --to S [--fps 8] [--stand 260]

Keys out the magenta (#FF00FF), samples the clip at --fps between --from and --to seconds, scales it so the person
standing in the FIRST frame is --stand px tall, and packs the frames into one sheet (<= 4096 px wide, phones) as
<out_base>.webp + <out_base>.json: {frames, cols, fw, fh, fps, foot: [x, y] (the first frame's feet in a frame),
stand (px)}. The game draws a frame so its feet land on the floor point and the standing height matches the guard.
"""
import json, os, subprocess, sys, tempfile
import numpy as np
from PIL import Image


def key(im):
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    k = np.minimum(r, b) - g                      # how magenta
    al = np.clip(1.0 - (k - 50.0) / 70.0, 0.0, 1.0)
    sp = np.clip(k / 255.0, 0.0, 1.0) * al        # take the pink off the edges
    a[..., 0] -= sp * 110.0
    a[..., 2] -= sp * 110.0
    return np.dstack([np.clip(a, 0, 255), al * 255.0]).astype(np.uint8)


def main():
    args = sys.argv[1:]
    opt = {"--from": 0.0, "--to": 99.0, "--fps": 8.0, "--stand": 260.0}
    for k in list(opt):
        if k in args:
            i = args.index(k); opt[k] = float(args[i + 1]); del args[i:i + 2]
    src, out = args[0], args[1]
    with tempfile.TemporaryDirectory() as td:
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(opt["--from"]), "-to", str(opt["--to"]), "-i", src,
                        "-vf", "fps=%g" % opt["--fps"], os.path.join(td, "f%04d.png")], check=True)
        frames = [key(Image.open(os.path.join(td, f))) for f in sorted(os.listdir(td))]
    if not frames: sys.exit("no frames")
    al0 = frames[0][..., 3] > 128
    ys, xs = np.where(al0)
    stand_px = ys.max() - ys.min()
    body = xs[ys < ys.min() + stand_px * 0.45]   # (the upper body: a gun or a blade held out does not pull the middle off)
    foot = (float((np.percentile(body, 5) + np.percentile(body, 95)) * 0.5), float(ys.max()))
    union = np.zeros_like(al0)
    for f in frames: union |= f[..., 3] > 20
    uy, ux = np.where(union)
    x0, x1, y0, y1 = ux.min(), ux.max() + 1, uy.min(), uy.max() + 1
    s = opt["--stand"] / float(stand_px)
    fw, fh = int(round((x1 - x0) * s)), int(round((y1 - y0) * s))
    cols = max(1, min(len(frames), 4096 // fw))
    rows = (len(frames) + cols - 1) // cols
    if rows * fh > 4096: sys.exit("sheet too tall: lower --fps or --stand")
    sheet = Image.new("RGBA", (cols * fw, rows * fh), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        im = Image.fromarray(f[y0:y1, x0:x1], "RGBA").resize((fw, fh), Image.LANCZOS)
        sheet.paste(im, ((i % cols) * fw, (i // cols) * fh))
    sheet.save(out + ".webp", quality=88, method=6)
    meta = {"frames": len(frames), "cols": cols, "fw": fw, "fh": fh, "fps": opt["--fps"],
            "foot": [round(float((foot[0] - x0) * s), 1), round(float((foot[1] - y0) * s), 1)], "stand": opt["--stand"]}
    with open(out + ".json", "w") as o: json.dump(meta, o)
    print(out, meta, "%.0f KB" % (os.path.getsize(out + ".webp") / 1024))


if __name__ == "__main__":
    main()
