#!/usr/bin/env python3
"""Malgus Command Deck graybox in Blender (bpy 5.x, run with python3): extrudes the clean plan (eng/plan.json).
Scale guess until the owner gives one: door 1.2 m = DOOR (60 px) -> 50 px/m. Walls 4.0 m (station), slab 0.2 m.
From the in-game shots: the wing stages are raised 0.6 m, the hub centre has a 1.0 m railing ring.
Output: malgus_command_deck_graybox_WIP_NOT_APPROVED.blend and .glb."""
import json, os, bpy
from shapely.geometry import shape, MultiPolygon, Point
from shapely import affinity
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__)); ENG = os.path.join(HERE, "..", "eng")
WALL_H, SLAB, STAGE_H, RAIL_H = 4.0, 0.2, 0.6, 1.0
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1); m.diffuse_color = (*rgb, 1); return m
M_FLOOR, M_WALL, M_STAGE, M_RAIL = mat("floor", (0.18, 0.2, 0.23)), mat("wall", (0.6, 0.63, 0.68)), mat("stage", (0.35, 0.42, 0.5)), mat("railing", (0.85, 0.7, 0.3))
col = bpy.data.collections.new("COMMAND_DECK"); bpy.context.scene.collection.children.link(col)
def add(geom, height, z, name, material):
    polys = list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]
    tm = trimesh.util.concatenate([trimesh.creation.extrude_polygon(p.buffer(0), height) for p in polys if p.area > 1e-4]); tm.apply_translation((0, 0, z))
    me = bpy.data.meshes.new(name); me.from_pydata(tm.vertices.tolist(), [], tm.faces.tolist()); me.update()
    ob = bpy.data.objects.new(name, me); ob.data.materials.append(material); col.objects.link(ob)

P = json.load(open(os.path.join(ENG, "plan.json"))); s = 1.2 / float(P["door"]); cx, cy = P["centre"]
to_m = lambda g: affinity.affine_transform(g, [s, 0, 0, -s, -cx * s, cy * s])   # hub centre at the origin, north = +y
add(to_m(shape(P["floor"])), SLAB, -SLAB, "floor", M_FLOOR)
add(to_m(shape(P["walls"])), WALL_H, 0, "walls", M_WALL)
for i, f in enumerate(P["features"]):
    g = to_m(shape(f["shape"]))
    if f["name"].startswith("raised stage"): add(g, STAGE_H, 0, f"stage_{i}", M_STAGE)
    elif f["name"].startswith("centre ring"): add(g.exterior.buffer(0.06), RAIL_H, 0, "centre_railing", M_RAIL)
hm = bpy.data.objects.new("scale_human_1.8m", None); hm.empty_display_type = "SINGLE_ARROW"; hm.empty_display_size = 1.8
bpy.context.scene.collection.objects.link(hm)
out = os.path.join(HERE, "malgus_command_deck_graybox_WIP_NOT_APPROVED")
bpy.ops.wm.save_as_mainfile(filepath=out + ".blend"); bpy.ops.export_scene.gltf(filepath=out + ".glb", export_format="GLB")
b = to_m(shape(P["floor"])).bounds; print("deck m:", round(b[2] - b[0], 1), "x", round(b[3] - b[1], 1))
