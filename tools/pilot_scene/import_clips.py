#!/usr/bin/env python3
"""v12.91 import_clips.py - the owner's pilot-scene pictures and MP4 clips into the game, with the frame check.

  python3 tools/pilot_scene/import_clips.py IN_DIR male|female [--check-only] [--max 0.92]

IN_DIR holds the pictures (A, B, C_<jacket>, D_<jacket> as .png / .jpg / .webp) and the clips (.mp4), named as in
scripts/pilot_scene.gd (zoom_in, zoom_out, alive_<name>[_<jacket>], tryon_<jacket>).

For every clip it checks the first and last frames against the pictures they must start and end on (SSIM, 1.0 = the
same): zoom_in A->B, zoom_out B->A, alive_* A->A (or D_<jacket>->D_<jacket>), tryon_<jacket> B->C_<jacket>.
A clip under --min (default 0.90) at either end is REJECTED (listed, not copied): regenerate it, don't hide the jump.
The ones that pass are made into Theora .ogv (Godot plays only that), 1280 px wide at most, silent, into
assets/pilot_scene/<male|female>/; the pictures are copied as JPEG (1920 px wide at most). Originals are never changed.
"""
import os, re, subprocess, sys, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PICS = (".png", ".jpg", ".jpeg", ".webp")

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def frame(clip, last, out):
    if last:
        run(["ffmpeg", "-loglevel", "error", "-y", "-sseof", "-0.1", "-i", clip, "-frames:v", "1", "-update", "1", out])
    else:
        run(["ffmpeg", "-loglevel", "error", "-y", "-i", clip, "-frames:v", "1", out])
    return os.path.exists(out)

def ssim(a, b):
    """SSIM of two pictures at 640x360 (ffmpeg's ssim filter)"""
    r = run(["ffmpeg", "-loglevel", "info", "-i", a, "-i", b, "-lavfi",
             "[0:v]scale=640:360,format=gray[x];[1:v]scale=640:360,format=gray[y];[x][y]ssim", "-f", "null", "-"])
    m = re.search(r"All:([0-9.]+)", r.stderr)
    return float(m.group(1)) if m else 0.0

def ends_for(name):
    """the pictures a clip must start and end on"""
    if name == "zoom_in": return "A", "B"
    if name == "zoom_out": return "B", "A"
    m = re.match(r"(zoom_in|zoom_out)_(.+)", name)
    if m:   # (in a jacket: full body D to waist-up C, or back)
        j = m.group(2)
        return ("D_" + j, "C_" + j) if m.group(1) == "zoom_in" else ("C_" + j, "D_" + j)
    m = re.match(r"tryon_(.+)", name)
    if m: return "B", "C_" + m.group(1)
    m = re.match(r"alive_[a-z]+_(.+)", name)
    if m: return "D_" + m.group(1), "D_" + m.group(1)
    if name.startswith("alive_"): return "A", "A"
    return None, None

def main():
    if len(sys.argv) < 3:
        print(__doc__); return 1
    src, sex = sys.argv[1], sys.argv[2]
    check_only = "--check-only" in sys.argv
    lim = float(sys.argv[sys.argv.index("--min") + 1]) if "--min" in sys.argv else 0.90
    out = os.path.join(ROOT, "assets/pilot_scene", sex)
    pics = {os.path.splitext(f)[0]: os.path.join(src, f) for f in os.listdir(src) if f.lower().endswith(PICS)}
    clips = sorted(f for f in os.listdir(src) if f.lower().endswith(".mp4"))
    tmp = tempfile.mkdtemp()
    ok, bad, missing = [], [], []
    for f in clips:
        nm = os.path.splitext(f)[0]
        a, b = ends_for(nm)
        if a is None:
            bad.append((nm, "unknown clip name")); continue
        if a not in pics or b not in pics:
            missing.append((nm, [x for x in (a, b) if x not in pics])); continue
        cp = os.path.join(src, f)
        f0, f1 = os.path.join(tmp, nm + "_first.png"), os.path.join(tmp, nm + "_last.png")
        if not (frame(cp, False, f0) and frame(cp, True, f1)):
            bad.append((nm, "can't read its frames")); continue
        s0, s1 = ssim(f0, pics[a]), ssim(f1, pics[b])
        dur = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", cp]).stdout.strip()
        line = "%s: start vs %s %.3f, end vs %s %.3f, %ss" % (nm, a, s0, b, s1, dur)
        if s0 < lim or s1 < lim:
            bad.append((nm, line)); continue
        ok.append(line)
        if not check_only:
            os.makedirs(out, exist_ok=True)
            run(["ffmpeg", "-loglevel", "error", "-y", "-i", cp, "-an", "-vf", "scale='min(1280,iw)':-2", "-c:v", "libtheora", "-q:v", "7",
                 os.path.join(out, nm + ".ogv")])
    if not check_only:
        os.makedirs(out, exist_ok=True)
        for nm, p in pics.items():
            run(["ffmpeg", "-loglevel", "error", "-y", "-i", p, "-vf", "scale='min(1920,iw)':-2", "-q:v", "3", os.path.join(out, nm + ".jpg")])
    shutil.rmtree(tmp, ignore_errors=True)
    print("PASSED (%d):" % len(ok)); [print("  " + x) for x in ok]
    print("REJECTED (%d): regenerate these" % len(bad)); [print("  %s  %s" % x) for x in bad]
    print("WAITING ON PICTURES (%d):" % len(missing)); [print("  %s needs %s" % (n, ", ".join(m))) for n, m in missing]
    return 0 if not bad else 2

if __name__ == "__main__":
    sys.exit(main())
