# Isometric "hologram blueprint" of a game model: blue-shaded body, clean outline and crease lines found from the
# rendered normals and depth (so a busy Tripo mesh still reads clean). Transparent background.
import sys, math, numpy as np, trimesh
from PIL import Image, ImageFilter
def render(path, out, size=700, yaw=45.0, pitch=30.0, roll_x=0.0, col=(95, 215, 255)):
    m = trimesh.load(path, force='mesh')
    v = np.array(m.vertices, float); v -= (v.max(0) + v.min(0)) / 2
    def R(ax, a):
        c, s = math.cos(math.radians(a)), math.sin(math.radians(a))
        return {"x": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]), "y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])}[ax]
    p = v @ R("x", roll_x).T @ R("y", yaw).T @ R("x", pitch).T
    S = size * 2
    k = S * 0.88 / max(np.ptp(p[:, 0]), np.ptp(p[:, 1]))
    X = p[:, 0] * k + S / 2; Y = -p[:, 1] * k + S / 2; Z = p[:, 2] * k
    F = np.array(m.faces)
    fn = np.cross(p[F[:, 1]] - p[F[:, 0]], p[F[:, 2]] - p[F[:, 0]]); fn /= np.linalg.norm(fn, axis=1, keepdims=True) + 1e-12
    zb = np.full((S, S), -1e9); nb = np.zeros((S, S, 3))
    for i, f in enumerate(F):
        xs, ys, zs = X[f], Y[f], Z[f]
        x0, x1 = int(max(0, xs.min())), int(min(S - 1, xs.max() + 1)); y0, y1 = int(max(0, ys.min())), int(min(S - 1, ys.max() + 1))
        if x1 < x0 or y1 < y0: continue
        d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(d) < 1e-9: continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
        b = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
        c = 1 - a - b
        ins = (a >= -0.02) & (b >= -0.02) & (c >= -0.02)
        z = a * zs[0] + b * zs[1] + c * zs[2]
        sub = zb[y0:y1 + 1, x0:x1 + 1]; upd = ins & (z > sub)
        sub[upd] = z[upd]
        n = fn[i] if fn[i][2] >= 0 else -fn[i]
        nb[y0:y1 + 1, x0:x1 + 1][upd] = n
    mask = zb > -1e8
    # shading: light from the upper left, a blue hologram ramp, brighter rims
    L = np.array([-0.5, 0.6, 0.65]); L /= np.linalg.norm(L)
    lam = np.clip((nb * L).sum(2), 0, 1)
    rim = np.clip(1 - nb[:, :, 2], 0, 1) ** 2
    base = np.array([6, 24, 44]); hi = np.array(col)
    shade = base[None, None, :] + (hi - base)[None, None, :] * (0.18 + 0.42 * lam[:, :, None] ** 1.5 + 0.35 * rim[:, :, None])
    # creases: where the (smoothed) normal turns sharply or the depth jumps
    nbs = np.stack([np.array(Image.fromarray(((nb[:, :, j] + 1) * 127.5).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)), float) / 127.5 - 1 for j in range(3)], 2)
    gxn = np.abs(np.diff(nbs, axis=1, prepend=nbs[:, :1])).sum(2); gyn = np.abs(np.diff(nbs, axis=0, prepend=nbs[:1])).sum(2)
    zz = np.where(mask, zb, zb[mask].min() if mask.any() else 0)
    gz = np.abs(np.diff(zz, axis=1, prepend=zz[:, :1])) + np.abs(np.diff(zz, axis=0, prepend=zz[:1]))
    crease = ((gxn + gyn) > 0.45) | (gz > S * 0.02)
    crease &= mask
    outline = np.array(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.FIND_EDGES)) > 40
    rgb = shade.copy()
    rgb[crease] = rgb[crease] * 0.35 + np.array([170, 235, 255]) * 0.65
    rgb[outline] = [225, 248, 255]
    a = np.where(mask, 235, 0); a[outline] = 255
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), a]).astype(np.uint8), "RGBA")
    ol = Image.fromarray((outline * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
    img.paste(Image.new("RGBA", (S, S), (225, 248, 255, 255)), (0, 0), ol)
    bb = img.getbbox(); img = img.crop(bb)
    img = img.resize((max(1, img.width // 2), max(1, img.height // 2)), Image.LANCZOS)
    img.save(out)
if __name__ == "__main__":
    a = sys.argv
    render(a[1], a[2], yaw=float(a[3]) if len(a) > 3 else 45.0, pitch=float(a[4]) if len(a) > 4 else 30.0, roll_x=float(a[5]) if len(a) > 5 else 0.0)
