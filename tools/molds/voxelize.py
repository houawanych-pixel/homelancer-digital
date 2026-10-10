#!/usr/bin/env python3
"""Turn closed 3D models (Blender exports: .glb or .obj) into Homelancer block MOLDS.

A mold is a filled volume of 5 m cells, stored as runs [dx, dz, klo, khi] (cells from the model's middle, layers
up from its base, khi not included). The game stamps molds into the block ground: "add" makes those cells solid in
a material (rock trees, cliffs, arches), "cut" makes them air (caves, entrances).

How it works: for every 5 m column it shoots a line straight up through the model and counts where it crosses the
surface (in, out, in, out...): a layer is inside when its middle is between an "in" and an "out". So each separate
object must be CLOSED (watertight). Overlapping parts are fine as long as they are separate objects (each is filled
on its own and the results are joined).

Usage:  python3 tools/molds/voxelize.py            (reads tools/molds/molds.json, writes scripts/mold_library.gd)

molds.json lists each model: {"name": "beam_tree", "file": "beam_tree.obj", "op": "add", "mat": "obsidian",
"anchor": "ground", "chance": 0.25, "scale": 1.0}. Models are in metres, Y up (Blender's glTF export does that),
the base at y = 0 and the middle at x = z = 0.
"""
import json, os, struct, sys
import numpy as np

CELL = 5.0
OVERLAP = 1.5   # m of a 5 m layer that must be inside the model for it to count
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def load_obj(path):
    """-> list of (V (n,3), F (m,3)) per object ('o' / 'g' starts a new one)."""
    objs, V, F, cur = [], [], [], []
    for line in open(path):
        p = line.split()
        if not p: continue
        if p[0] == 'v': V.append([float(x) for x in p[1:4]])
        elif p[0] == 'f':
            idx = [int(t.split('/')[0]) for t in p[1:]]
            idx = [i - 1 if i > 0 else len(V) + i for i in idx]
            for k in range(1, len(idx) - 1): cur.append([idx[0], idx[k], idx[k + 1]])
        elif p[0] in ('o', 'g'):
            if cur: objs.append(cur)
            cur = []
    if cur: objs.append(cur)
    Va = np.array(V, dtype=float)
    return [(Va, np.array(f, dtype=int)) for f in objs]


def _quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def load_glb(path):
    """Minimal glTF binary reader: every mesh primitive (triangles) with its node's transform, as its own object."""
    data = open(path, 'rb').read()
    magic, ver, length = struct.unpack_from('<4sII', data, 0)
    assert magic == b'glTF', 'not a .glb'
    off, js, binc = 12, None, b''
    while off < length:
        clen, ctype = struct.unpack_from('<II', data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A: js = json.loads(chunk)
        elif ctype == 0x004E4942: binc = chunk
        off += 8 + clen
    comp = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
    ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}

    def acc(i):
        a = js['accessors'][i]
        bv = js['bufferViews'][a['bufferView']]
        fmt, size = comp[a['componentType']]
        nc = ncomp[a['type']]
        start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride', size * nc)
        out = np.zeros((a['count'], nc))
        for k in range(a['count']):
            out[k] = struct.unpack_from('<' + fmt * nc, binc, start + k * stride)
        return out

    def node_mat(n):
        if 'matrix' in n: return np.array(n['matrix']).reshape(4, 4).T
        M = np.eye(4)
        S = np.diag(n.get('scale', [1, 1, 1]) + [1])
        R = np.eye(4)
        R[:3, :3] = _quat_mat(n.get('rotation', [0, 0, 0, 1]))
        T = np.eye(4)
        T[:3, 3] = n.get('translation', [0, 0, 0])
        return T @ R @ S @ M

    objs = []

    def walk(ni, parent):
        n = js['nodes'][ni]
        M = parent @ node_mat(n)
        if 'mesh' in n:
            for prim in js['meshes'][n['mesh']]['primitives']:
                if prim.get('mode', 4) != 4: continue
                V = acc(prim['attributes']['POSITION'])
                V = (np.c_[V, np.ones(len(V))] @ M.T)[:, :3]
                I = acc(prim['indices']).astype(int).reshape(-1) if 'indices' in prim else np.arange(len(V))
                objs.append((V, I.reshape(-1, 3)))
        for c in n.get('children', []): walk(c, M)

    scene = js['scenes'][js.get('scene', 0)]
    for ni in scene['nodes']: walk(ni, np.eye(4))
    return objs


def fill(V, F):
    """Cells inside one closed object: {(i, j): set(k)} with i, j, k the 5 m cell / layer indices (cell centres)."""
    out = {}
    tri = V[F]   # (m, 3, 3)
    lo = np.floor(tri.min(axis=(0, 1)) / CELL).astype(int)
    hi = np.ceil(tri.max(axis=(0, 1)) / CELL).astype(int)
    for i in range(lo[0], hi[0] + 1):
        for j in range(lo[2], hi[2] + 1):
            x, z = (i + 0.5) * CELL, (j + 0.5) * CELL
            ys = []
            # vertical line at (x, z): where it crosses each triangle (2D point-in-triangle on x/z, then height)
            a, b, c = tri[:, 0], tri[:, 1], tri[:, 2]
            d = (b[:, 0] - a[:, 0]) * (c[:, 2] - a[:, 2]) - (c[:, 0] - a[:, 0]) * (b[:, 2] - a[:, 2])
            ok = np.abs(d) > 1e-9
            u = ((b[:, 0] - x) * (c[:, 2] - z) - (c[:, 0] - x) * (b[:, 2] - z))
            v = ((c[:, 0] - x) * (a[:, 2] - z) - (a[:, 0] - x) * (c[:, 2] - z))
            with np.errstate(divide='ignore', invalid='ignore'):
                l0 = np.where(ok, u / d, -1)
                l1 = np.where(ok, v / d, -1)
            l2 = 1 - l0 - l1
            hit = ok & (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
            if not hit.any(): continue
            y = l0[hit] * a[hit, 1] + l1[hit] * b[hit, 1] + l2[hit] * c[hit, 1]
            ys = np.unique(np.round(np.sort(y), 4))
            if len(ys) < 2: continue
            ks = set()
            for t in range(0, len(ys) - 1, 2):
                y0, y1 = ys[t], ys[t + 1]
                for k in range(int(np.floor(y0 / CELL)), int(np.ceil(y1 / CELL)) + 1):
                    # a layer counts when at least OVERLAP of it is inside (so thin tilted beams stay one joined piece)
                    if min(y1, (k + 1) * CELL) - max(y0, k * CELL) >= OVERLAP: ks.add(k)
            if ks: out.setdefault((i, j), set()).update(ks)
    return out


def join_up(cells):
    """Blocks only hold each other up through a shared face, so where two filled cells touch only at an edge or a
    corner (a tilted beam crossing the grid at a slant) fill the cells between them, making one joined piece."""
    import itertools
    def has(p): return p[2] in cells.get((p[0], p[1]), ())
    def put(p): cells.setdefault((p[0], p[1]), set()).add(p[2])
    def add(p, ax, dv): return tuple(p[t] + (dv if t == ax else 0) for t in range(3))
    added = True
    while added:
        added = False
        for (i, j), ks in list(cells.items()):
            for k in list(ks):
                v = (i, j, k)
                for d in itertools.product((-1, 0, 1), repeat=3):
                    axes = [(t, d[t]) for t in range(3) if d[t] != 0]
                    if len(axes) < 2 or not has((i + d[0], j + d[1], k + d[2])): continue
                    joined = False
                    for perm in itertools.permutations(axes):
                        p, ok = v, True
                        for ax, dv in perm[:-1]:
                            p = add(p, ax, dv)
                            if not has(p):
                                ok = False
                                break
                        if ok:
                            joined = True
                            break
                    if joined: continue
                    p = v
                    for ax, dv in axes[:-1]:   # fill a face-to-face path: across one axis at a time
                        p = add(p, ax, dv)
                        put(p)
                    added = True
    return cells


def runs_of(cells):
    out = []
    for (i, j), ks in sorted(cells.items()):
        ks = sorted(ks)
        s = 0
        while s < len(ks):
            e = s
            while e + 1 < len(ks) and ks[e + 1] == ks[e] + 1: e += 1
            out.append([i, j, ks[s], ks[e] + 1])
            s = e + 1
    return out


def build(entry):
    path = os.path.join(HERE, entry['file'])
    objs = load_glb(path) if path.lower().endswith('.glb') else load_obj(path)
    sc = float(entry.get('scale', 1.0))
    cells = {}
    for V, F in objs:
        for key, ks in fill(V * sc, F).items(): cells.setdefault(key, set()).update(ks)
    if not cells: raise SystemExit('%s: nothing inside (is it closed?)' % entry['file'])
    cells = join_up(cells)
    kmin = min(min(ks) for ks in cells.values())
    cells = {key: {k - kmin for k in ks} for key, ks in cells.items()}   # the base sits on layer 0
    # cells not joined to the base through faces would just fall when stamped in: say so (fix the model)
    seen, todo = set(), [(i, j, k) for (i, j), ks in cells.items() for k in ks if k == 0]
    seen.update(todo)
    while todo:
        i, j, k = todo.pop()
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            q = (i + d[0], j + d[1], k + d[2])
            if q not in seen and q[2] in cells.get((q[0], q[1]), ()):
                seen.add(q)
                todo.append(q)
    loose = sum(len(ks) for ks in cells.values()) - len(seen)
    if loose: print('  warning: %s has %d cells not joined to its base (they would fall): make the parts touch' % (entry['name'], loose))
    r = runs_of(cells)
    xs = [c[0] for c in r]
    zs = [c[1] for c in r]
    size = [max(xs) - min(xs) + 1, max(c[3] for c in r), max(zs) - min(zs) + 1]
    return {"op": entry.get('op', 'add'), "mat": entry.get('mat', 'stone'), "anchor": entry.get('anchor', 'ground'),
            "chance": float(entry.get('chance', 0.2)), "size": size, "cells": sum(c[3] - c[2] for c in r), "runs": r}


def main():
    manifest = json.load(open(os.path.join(HERE, 'molds.json')))
    lib = {}
    for e in manifest:
        lib[e['name']] = build(e)
        m = lib[e['name']]
        print('%-14s %s %-8s %3d x %3d x %3d cells, %5d filled, %d runs' % (e['name'], m['op'], m['mat'], m['size'][0], m['size'][1], m['size'][2], m['cells'], len(m['runs'])))
    lines = ['## GENERATED by tools/molds/voxelize.py from the models in tools/molds/ (do not edit by hand: change the model',
             '## or tools/molds/molds.json and run the tool again). Each mold: runs [dx, dz, klo, khi] of 5 m cells.',
             '## (loaded with preload, no class_name, so no editor import is needed)', '', 'const MOLDS := {']
    for name, m in lib.items():
        runs = ', '.join('[%d, %d, %d, %d]' % tuple(r) for r in m['runs'])
        lines.append('\t"%s": {"op": "%s", "mat": "%s", "anchor": "%s", "chance": %s, "size": %s, "cells": %d, "runs": [%s]},'
                     % (name, m['op'], m['mat'], m['anchor'], m['chance'], m['size'], m['cells'], runs))
    lines.append('}')
    out = os.path.join(ROOT, 'scripts', 'mold_library.gd')
    open(out, 'w').write('\n'.join(lines) + '\n')
    print('wrote', os.path.relpath(out, ROOT))


if __name__ == '__main__':
    main()
