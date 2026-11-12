#!/usr/bin/env python3
"""UPP Tianjin graybox in Blender (bpy 5.x, run with python3): extrudes the approved clean plans.
Main deck (eng/main_plan.json) at z 0; the command tower (eng/tower_plan.json) one deck up (3.5 m) on the stern block.
Scale from the standard door: 1.2 m (Homelancer metrics) = the plan's DOOR width. Walls 3.0 m, floor slab 0.2 m.
Exterior hull (eng/exterior_silhouette.json) as a thin reference outline at floor level.
Output: tianjin_graybox_WIP_NOT_APPROVED.blend and .glb next to this script."""
import json, os, bpy, numpy as np
from shapely.geometry import shape, Polygon, MultiPolygon
from shapely import affinity
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__)); ENG = os.path.join(HERE, "..", "eng")
WALL_H, SLAB, DECK = 3.0, 0.2, 3.5
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1); m.diffuse_color = (*rgb, 1); return m
M_FLOOR, M_WALL, M_TOWER, M_HULL = mat("floor", (0.18, 0.2, 0.23)), mat("wall", (0.62, 0.64, 0.68)), mat("tower_wall", (0.55, 0.62, 0.72)), mat("hull_ref", (0.9, 0.45, 0.45))
def coll(name):
    c = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c); return c
def add(geom, height, z, name, material, collection):
    polys = list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]
    meshes = [trimesh.creation.extrude_polygon(p.buffer(0), height) for p in polys if p.area > 1e-4]
    if not meshes: return
    tm = trimesh.util.concatenate(meshes); tm.apply_translation((0, 0, z))
    me = bpy.data.meshes.new(name); me.from_pydata(tm.vertices.tolist(), [], tm.faces.tolist()); me.update()
    ob = bpy.data.objects.new(name, me); ob.data.materials.append(material); collection.objects.link(ob)

def to_m(g, s, ox=0.0, oy=0.0):   # image px -> metres, y flipped (image down = ship port side)
    return affinity.affine_transform(g, [s, 0, 0, -s, ox, oy])

main = json.load(open(os.path.join(ENG, "main_plan.json")))
sm = 1.2 / float(main["door"]); CYm = float(main["mirror_y"])
mfloor = to_m(shape(main["floor"]), sm, 0, CYm * sm); mwalls = to_m(shape(main["walls"]), sm, 0, CYm * sm)
c1 = coll("DECK_main")
add(mfloor, SLAB, -SLAB, "main_floor", M_FLOOR, c1); add(mwalls, WALL_H, 0, "main_walls", M_WALL, c1)

# command tower on the stern block: placed by the exterior (block x 262-400 of the exterior's 200-1240 stern->nose),
# along the ship's length measured on the main sheet's hull; centred on the centre line; its own door scale
hull = (np.array(json.load(open(os.path.join(ENG, "..", "ship_rooms.json")))["hull"], float) / 3.0 - [0, 60]) * 4
x_st, x_no = hull[:, 0].min(), hull[:, 0].max(); L = x_no - x_st
mid_px = x_st + L * (((262 + 400) / 2 - 200) / (1240 - 200))
tw = json.load(open(os.path.join(ENG, "tower_plan.json"))); st = 1.2 / float(tw["door"])
tf, twl = shape(tw["floor"]), shape(tw["walls"])
cx_px = (tf.bounds[0] + tf.bounds[2]) / 2
ox = mid_px * sm - cx_px * st; oy = float(tw["mirror_y"]) * st
c2 = coll("DECK_command_tower")
add(to_m(tf, st, ox, oy), SLAB, DECK - SLAB, "tower_floor", M_FLOOR, c2); add(to_m(twl, st, ox, oy), WALL_H, DECK, "tower_walls", M_TOWER, c2)

# exterior hull outline (reference): scaled so its stern->nose length matches the main sheet's hull
ex = np.array(json.load(open(os.path.join(ENG, "exterior_silhouette.json")))["outline"], float)
k = (L * sm) / (ex[:, 0].max() - ex[:, 0].min())
ey = (ex[:, 1].max() + ex[:, 1].min()) / 2
hull_m = Polygon([((x - ex[:, 0].min()) * k + x_st * sm, -(y - ey) * k) for x, y in ex])
c3 = coll("HULL_reference")
add(hull_m.exterior.buffer(0.15), 0.3, -SLAB, "hull_outline", M_HULL, c3)

# a 1.8 m human for scale, at the CIC
cic = bpy.data.objects.new("scale_human_1.8m", None); cic.empty_display_type = "SINGLE_ARROW"; cic.empty_display_size = 1.8
cic.location = (1640 * sm, 0, 0); bpy.context.scene.collection.objects.link(cic)
out = os.path.join(HERE, "tianjin_graybox_WIP_NOT_APPROVED")
bpy.ops.wm.save_as_mainfile(filepath=out + ".blend")
bpy.ops.export_scene.gltf(filepath=out + ".glb", export_format="GLB")
mins = np.min([o.bound_box[0] for o in []] or [[0, 0, 0]], axis=0)
print("main deck size m:", round((mfloor.bounds[2] - mfloor.bounds[0]), 1), "x", round(mfloor.bounds[3] - mfloor.bounds[1], 1),
      "| hull length m:", round(L * sm, 1), "| tower size m:", round((tf.bounds[2] - tf.bounds[0]) * st, 1), "x", round((tf.bounds[3] - tf.bounds[1]) * st, 1))
