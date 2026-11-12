#!/usr/bin/env python3
"""Fury-class Interceptor graybox in Blender (bpy 5.x, run with python3): extrudes the clean plan (eng/plan.json).
Real scale from the sheet: 40 px/m (47.8 m long, 41 m wide). Walls 3.0 m, slab 0.2 m.
Output: fury_graybox_WIP_NOT_APPROVED.blend and .glb."""
import json, os, bpy
from shapely.geometry import shape, MultiPolygon
from shapely import affinity
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__)); ENG = os.path.join(HERE, "..", "eng")
WALL_H, SLAB = 3.0, 0.2
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1); m.diffuse_color = (*rgb, 1); return m
M_FLOOR, M_WALL = mat("floor", (0.18, 0.2, 0.23)), mat("wall", (0.62, 0.6, 0.66))
col = bpy.data.collections.new("FURY_DECK"); bpy.context.scene.collection.children.link(col)
def add(geom, height, z, name, material):
    polys = list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]
    tm = trimesh.util.concatenate([trimesh.creation.extrude_polygon(p.buffer(0), height) for p in polys if p.area > 1e-4]); tm.apply_translation((0, 0, z))
    me = bpy.data.meshes.new(name); me.from_pydata(tm.vertices.tolist(), [], tm.faces.tolist()); me.update()
    ob = bpy.data.objects.new(name, me); ob.data.materials.append(material); col.objects.link(ob)
P = json.load(open(os.path.join(ENG, "plan.json"))); s = 1.0 / float(P["px_per_m"]); ax = P["mirror_x"]
to_m = lambda g: affinity.affine_transform(g, [s, 0, 0, -s, -ax * s, 870 * s])   # centre line x 0, nose y 0
add(to_m(shape(P["floor"])), SLAB, -SLAB, "floor", M_FLOOR); add(to_m(shape(P["walls"])), WALL_H, 0, "walls", M_WALL)
from shapely.geometry import Polygon
hull = to_m(Polygon(json.load(open(os.path.join(ENG, "hull_outline.json")))["outline"]))   # exterior outline, red guide
add(hull.exterior.buffer(0.15), 0.3, -SLAB, "hull_outline", mat("hull_ref", (0.9, 0.45, 0.45)))
hm = bpy.data.objects.new("scale_human_1.8m", None); hm.empty_display_type = "SINGLE_ARROW"; hm.empty_display_size = 1.8
bpy.context.scene.collection.objects.link(hm)
out = os.path.join(HERE, "fury_graybox_WIP_NOT_APPROVED")
bpy.ops.wm.save_as_mainfile(filepath=out + ".blend"); bpy.ops.export_scene.gltf(filepath=out + ".glb", export_format="GLB")
b = to_m(shape(P["floor"])).bounds; print("deck m:", round(b[2] - b[0], 1), "x", round(b[3] - b[1], 1), "| hull m:", [round(v, 1) for v in (hull.bounds[2] - hull.bounds[0], hull.bounds[3] - hull.bounds[1])])
