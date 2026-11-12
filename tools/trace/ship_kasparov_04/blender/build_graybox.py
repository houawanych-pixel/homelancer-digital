#!/usr/bin/env python3
"""Kasparov graybox in Blender (bpy 5.x, run with python3): extrudes the two clean deck plans.
Lower deck (eng/deck_b_plan.json) at z 0, upper deck (eng/deck_a_plan.json) one deck up (3.5 m).
Both decks come from the same sheet at the same x4 scale; deck B is moved onto deck A's pixels by the hull offset (-88, -73).
Scale from the standard door: 1.2 m = the plan's DOOR width. Walls 3.0 m, slab 0.2 m. Hull outline shown as a guide only.
Output: kasparov_graybox_WIP_NOT_APPROVED.blend and .glb next to this script."""
import json, os, bpy, numpy as np
from shapely.geometry import shape, Polygon, MultiPolygon
from shapely import affinity
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__)); ENG = os.path.join(HERE, "..", "eng")
WALL_H, SLAB, DECK = 3.0, 0.2, 3.5
AXIS_A, NOSE_A = 593.0, 29.0
B_TO_A = (-88.0, -73.0)
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1); m.diffuse_color = (*rgb, 1); return m
M_FLOOR, M_WALL_A, M_WALL_B, M_HULL = mat("floor", (0.18, 0.2, 0.23)), mat("wall_upper", (0.55, 0.62, 0.72)), mat("wall_lower", (0.62, 0.64, 0.68)), mat("hull_ref", (0.9, 0.45, 0.45))
def coll(name):
    c = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c); return c
def add(geom, height, z, name, material, collection):
    polys = list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]
    meshes = [trimesh.creation.extrude_polygon(p.buffer(0), height) for p in polys if p.area > 1e-4]
    if not meshes: return
    tm = trimesh.util.concatenate(meshes); tm.apply_translation((0, 0, z))
    me = bpy.data.meshes.new(name); me.from_pydata(tm.vertices.tolist(), [], tm.faces.tolist()); me.update()
    ob = bpy.data.objects.new(name, me); ob.data.materials.append(material); collection.objects.link(ob)

A = json.load(open(os.path.join(ENG, "deck_a_plan.json"))); B = json.load(open(os.path.join(ENG, "deck_b_plan.json")))
s = 1.2 / float(A["door"])
# deck-A px -> metres: x = across the ship (centre line 0), y = forward (nose at y 0, stern negative)
def to_m(g, dx=0.0, dy=0.0):
    g = affinity.translate(g, dx, dy)
    return affinity.affine_transform(g, [s, 0, 0, -s, -AXIS_A * s, NOSE_A * s])
cB = coll("DECK_lower")
bf, bw = to_m(shape(B["floor"]), *B_TO_A), to_m(shape(B["walls"]), *B_TO_A)
add(bf, SLAB, -SLAB, "lower_floor", M_FLOOR, cB); add(bw, WALL_H, 0, "lower_walls", M_WALL_B, cB)
cA = coll("DECK_upper")
af, aw = to_m(shape(A["floor"])), to_m(shape(A["walls"]))
add(af, SLAB, DECK - SLAB, "upper_floor", M_FLOOR, cA); add(aw, WALL_H, DECK, "upper_walls", M_WALL_A, cA)

hull = Polygon(json.load(open(os.path.join(HERE, "..", "deck_a_rooms.json")))["hull"]).buffer(0)
cH = coll("HULL_reference")
add(to_m(hull).exterior.buffer(0.15), 0.3, -SLAB, "hull_outline", M_HULL, cH)

hm = bpy.data.objects.new("scale_human_1.8m", None); hm.empty_display_type = "SINGLE_ARROW"; hm.empty_display_size = 1.8
bpy.context.scene.collection.objects.link(hm)
out = os.path.join(HERE, "kasparov_graybox_WIP_NOT_APPROVED")
bpy.ops.wm.save_as_mainfile(filepath=out + ".blend")
bpy.ops.export_scene.gltf(filepath=out + ".glb", export_format="GLB")
sz = lambda g: f"{g.bounds[2]-g.bounds[0]:.1f} x {g.bounds[3]-g.bounds[1]:.1f}"
print("upper deck m:", sz(af), "| lower deck m:", sz(bf), "| hull m:", sz(to_m(hull)))
