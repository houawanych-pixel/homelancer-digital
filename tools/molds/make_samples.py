#!/usr/bin/env python3
"""Sample models for the mold tool, built from boxes (stand-ins for the owner's Blender shapes, pictures 08 and 09 in
docs/blocks_look/): a tree of tilted beams on a block trunk, and a big block with a beam leaning on it. Each box is
its own closed object (the tool fills each and joins them). Metres, Y up, base at y = 0, middle at x = z = 0."""
import math, os
HERE = os.path.dirname(os.path.abspath(__file__))


def box(c, size, yaw=0.0, tilt=0.0):
    """Corners of a box: centre c, size (w, h, d); tilted by `tilt` (radians from upright) toward the yaw direction."""
    w, h, d = [s / 2 for s in size]
    out = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                x, y, z = sx * w, sy * h, sz * d
                # tilt about the local z axis (lean toward +x), then turn by yaw
                x, y = x * math.cos(tilt) + y * math.sin(tilt), -x * math.sin(tilt) + y * math.cos(tilt)
                x, z = x * math.cos(yaw) - z * math.sin(yaw), x * math.sin(yaw) + z * math.cos(yaw)
                out.append((c[0] + x, c[1] + y, c[2] + z))
    return out


FACES = [(1, 2, 4, 3), (5, 7, 8, 6), (1, 5, 6, 2), (3, 4, 8, 7), (1, 3, 7, 5), (2, 6, 8, 4)]


def write(name, boxes):
    lines, base = [], 0
    for bi, corners in enumerate(boxes):
        lines.append('o part%d' % bi)
        for v in corners: lines.append('v %.3f %.3f %.3f' % v)
        for f in FACES: lines.append('f ' + ' '.join(str(base + i) for i in f))
        base += 8
    open(os.path.join(HERE, name), 'w').write('\n'.join(lines) + '\n')


def beam(start, yaw, tilt, length, thick):
    """A beam of the given length leaning from `start` (its foot)."""
    dx = math.sin(tilt) * math.cos(yaw)
    dz = math.sin(tilt) * math.sin(yaw)
    dy = math.cos(tilt)
    c = (start[0] + dx * length / 2, start[1] + dy * length / 2, start[2] + dz * length / 2)
    return box(c, (thick, length, thick), yaw, tilt)


# picture 09: a block trunk, side blocks, tilted beams fanning up out of its top
tree = [box((0, 22.5, 0), (15, 45, 15)), box((-12, 7.5, 6), (15, 15, 10)), box((10, 5, -8), (12, 10, 12)),
        box((-11, 30, -4), (10, 10, 10)), box((11, 34, 4), (10, 12, 10))]
for yaw, tilt, ln in [(0.3, 0.55, 40), (2.2, 0.6, 35), (3.9, 0.45, 45), (5.2, 0.7, 30), (1.2, 0.25, 50)]:
    tree.append(beam((0, 40, 0), yaw, tilt, ln, 6))
write('beam_tree.obj', tree)

# picture 08: a tall block with a long beam leaning on it from the ground, little blocks round the foot
lean = [box((0, 25, 0), (15, 50, 15)), box((8, 5, 10), (10, 10, 10)), box((-9, 4, -9), (8, 8, 8))]
lean.append(beam((-40, 0, 0), 0.0, 0.85, 62, 8))   # the beam's foot on the ground, its top against the block
write('beam_lean.obj', lean)
print('wrote beam_tree.obj, beam_lean.obj')
