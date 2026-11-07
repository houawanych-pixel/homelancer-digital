"""Tiny SVG kit for the Homelancer fauna concept sheets: cel-shaded anime-style shapes drawn by hand in code.

Every shape is a smooth closed outline (Catmull-Rom through the points). part() paints it in three cel tones
(light crescent upper-left, base, shade crescent lower-right, plus a narrow deep-shade rim) and an ink line,
the way an anime splash-art creature is coloured. No image generation: everything is vector.
"""
import math

INK = "#140c1c"
_uid = [0]


def uid(p="u"):
    _uid[0] += 1
    return f"{p}{_uid[0]}"


def f(v):
    return f"{v:.1f}"


def smooth(pts, closed=True, k=0.5):
    """Catmull-Rom spline through pts as an SVG path (cubic Beziers)."""
    n = len(pts)
    if n < 2:
        return ""
    d = [f"M{f(pts[0][0])},{f(pts[0][1])}"]
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if (closed or i > 0) else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if (closed or i + 2 < n) else p2
        c1 = (p1[0] + (p2[0] - p0[0]) * k / 3, p1[1] + (p2[1] - p0[1]) * k / 3)
        c2 = (p2[0] - (p3[0] - p1[0]) * k / 3, p2[1] - (p3[1] - p1[1]) * k / 3)
        d.append(f"C{f(c1[0])},{f(c1[1])} {f(c2[0])},{f(c2[1])} {f(p2[0])},{f(p2[1])}")
    if closed:
        d.append("Z")
    return " ".join(d)


def poly(pts):
    return "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts) + " Z"


def scallop(cx, cy, rx, ry, n, bulge=0.55, rot=0.0, a0=0.0, a1=math.tau, jitter=None):
    """A cloud / wool outline: arcs bulging out between points on an ellipse."""
    pts = []
    full = abs(a1 - a0 - math.tau) < 1e-6
    cnt = n if full else n + 1
    for i in range(cnt):
        a = a0 + (a1 - a0) * i / n
        j = 1.0 + (jitter[i % len(jitter)] if jitter else 0.0)
        x, y = math.cos(a) * rx * j, math.sin(a) * ry * j
        pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
    d = [f"M{f(pts[0][0])},{f(pts[0][1])}"]
    segs = n
    for i in range(segs):
        p = pts[i]
        q = pts[(i + 1) % len(pts)]
        ch = math.dist(p, q)
        r = ch * bulge
        d.append(f"A{f(r)},{f(r)} 0 0 1 {f(q[0])},{f(q[1])}")
    d.append("Z")
    return " ".join(d)


def tufts(cx, cy, rx, ry, n, out=0.18, rot=0.0, seed=1, a0=0.0, a1=math.tau):
    """A furry outline: pointed tufts round an ellipse (each tuft a curved spike)."""
    import random
    r = random.Random(seed)
    pts = []
    for i in range(n):
        a = a0 + (a1 - a0) * i / n
        b = a0 + (a1 - a0) * (i + 0.5) / n
        v = (math.cos(a) * rx, math.sin(a) * ry)
        o = 1.0 + out * r.uniform(0.6, 1.3)
        t = (math.cos(b + 0.12) * rx * o, math.sin(b + 0.12) * ry * o)
        pts.append(v)
        pts.append(t)

    def tr(p):
        x, y = p
        return (cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot))

    pts = [tr(p) for p in pts]
    d = [f"M{f(pts[0][0])},{f(pts[0][1])}"]
    for i in range(0, len(pts), 2):
        v = pts[i]
        t = pts[i + 1]
        w = pts[(i + 2) % len(pts)]
        c = ((v[0] + t[0]) / 2 + (t[1] - v[1]) * 0.18, (v[1] + t[1]) / 2 - (t[0] - v[0]) * 0.18)
        d.append(f"Q{f(c[0])},{f(c[1])} {f(t[0])},{f(t[1])}")
        c2 = ((t[0] + w[0]) / 2 - (w[1] - t[1]) * 0.1, (t[1] + w[1]) / 2 + (w[0] - t[0]) * 0.1)
        d.append(f"Q{f(c2[0])},{f(c2[1])} {f(w[0])},{f(w[1])}")
    d.append("Z")
    return " ".join(d)


def part(d, pal, sh=(9, 11), hl=(5, 6), ink=3.0, deep=True, ink_col=INK, extra=""):
    """A cel-shaded shape. pal = (light, base, shade, deep)."""
    light, base, shade, dark = pal
    c = uid("c")
    m = uid("m")
    m2 = uid("m")
    out = [f'<clipPath id="{c}"><path d="{d}"/></clipPath>',
           f'<mask id="{m}" maskUnits="userSpaceOnUse" x="-4000" y="-4000" width="8000" height="8000">'
           f'<rect x="-4000" y="-4000" width="8000" height="8000" fill="#fff"/>'
           f'<path d="{d}" transform="translate({-sh[0]},{-sh[1]})" fill="#000"/></mask>',
           f'<mask id="{m2}" maskUnits="userSpaceOnUse" x="-4000" y="-4000" width="8000" height="8000">'
           f'<rect x="-4000" y="-4000" width="8000" height="8000" fill="#fff"/>'
           f'<path d="{d}" transform="translate({-sh[0] * 0.35},{-sh[1] * 0.35})" fill="#000"/></mask>',
           f'<path d="{d}" fill="{light}"/>',
           f'<g clip-path="url(#{c})">',
           f'<path d="{d}" transform="translate({hl[0]},{hl[1]})" fill="{base}"/>',
           f'<path d="{d}" fill="{shade}" mask="url(#{m})"/>']
    if deep:
        out.append(f'<path d="{d}" fill="{dark}" mask="url(#{m2})"/>')
    out.append(extra)
    out.append('</g>')
    if ink > 0:
        out.append(f'<path d="{d}" fill="none" stroke="{ink_col}" stroke-width="{ink}" stroke-linejoin="round"/>')
    return "\n".join(out)


def line(pts, w=2.0, col=INK, closed=False, k=0.5, op=1.0, cap="round"):
    return (f'<path d="{smooth(pts, closed, k)}" fill="none" stroke="{col}" stroke-width="{w}" '
            f'stroke-linecap="{cap}" stroke-linejoin="round" opacity="{op}"/>')


def taper(pts, w0, w1):
    """A tapered stroke along pts as a closed outline (width w0 at the start, w1 at the end)."""
    left, right = [], []
    n = len(pts)
    for i, p in enumerate(pts):
        a = pts[max(0, i - 1)]
        b = pts[min(n - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / L, dx / L
        w = (w0 + (w1 - w0) * i / (n - 1)) / 2
        left.append((p[0] + nx * w, p[1] + ny * w))
        right.append((p[0] - nx * w, p[1] - ny * w))
    return left + right[::-1]


def glow(d, col, blur=8, op=0.9, core=None):
    g = uid("g")
    s = (f'<filter id="{g}" x="-1" y="-1" width="3" height="3"><feGaussianBlur stdDeviation="{blur}"/></filter>'
         f'<path d="{d}" fill="{col}" filter="url(#{g})" opacity="{op}"/>')
    if core:
        s += f'<path d="{d}" fill="{core}"/>'
    return s


def circle(cx, cy, r):
    return (f"M{f(cx - r)},{f(cy)} A{f(r)},{f(r)} 0 1 0 {f(cx + r)},{f(cy)} "
            f"A{f(r)},{f(r)} 0 1 0 {f(cx - r)},{f(cy)} Z")


def ellipse(cx, cy, rx, ry, rot=0.0, n=24):
    pts = []
    for i in range(n):
        a = math.tau * i / n
        x, y = math.cos(a) * rx, math.sin(a) * ry
        pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
    return smooth(pts)


def eye(cx, cy, r, iris, glowc, slit=False, look=(0.25, 0.0)):
    """An anime eye: dark lid shape, glowing iris, highlight dots."""
    s = glow(circle(cx, cy, r * 1.25), glowc, blur=r * 0.9, op=0.75)
    s += f'<path d="{ellipse(cx, cy, r * 1.05, r * 0.85)}" fill="{INK}"/>'
    s += f'<path d="{circle(cx + look[0] * r, cy + look[1] * r, r * 0.72)}" fill="{iris}"/>'
    if slit:
        s += f'<path d="{ellipse(cx + look[0] * r, cy, r * 0.14, r * 0.62)}" fill="{INK}"/>'
    else:
        s += f'<path d="{circle(cx + look[0] * r, cy + look[1] * r, r * 0.32)}" fill="{INK}"/>'
    s += f'<path d="{circle(cx + look[0] * r - r * 0.25, cy - r * 0.28, r * 0.2)}" fill="#fff"/>'
    s += f'<path d="{circle(cx + look[0] * r + r * 0.28, cy + r * 0.25, r * 0.09)}" fill="#fff" opacity="0.85"/>'
    return s


def mix(a, b, t):
    a = a.lstrip("#")
    b = b.lstrip("#")
    ca = [int(a[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b[i:i + 2], 16) for i in (0, 2, 4)]
    return "#" + "".join(f"{int(round(x + (y - x) * t)):02x}" for x, y in zip(ca, cb))


def tones(base, light_to="#ffffff", shade_to="#1a1030", lt=0.38, st=0.32, dt=0.55):
    """(light, base, shade, deep) cel tones from one base colour; shadows lean purple like anime paint."""
    return (mix(base, light_to, lt), base, mix(base, shade_to, st), mix(base, shade_to, dt))
