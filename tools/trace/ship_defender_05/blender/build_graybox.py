#!/usr/bin/env python3
"""Defender graybox in Blender (bpy 5.x, run with python3): extrudes the two clean deck plans.
Lower deck (eng/lower_plan.json) at z 0, flight deck (eng/flight_plan.json) one deck up (3.5 m).
Scale from the standard door: 1.2 m = the flight deck plan's DOOR (96 px). The lower-deck minimap is zoomed in, so its px are
scaled by K = 0.63 into flight-deck px, and its stairs (11) are lined up under the flight deck passage to the lower deck (11).
Walls 3.0 m, slab 0.2 m. Output: defender_graybox_WIP_NOT_APPROVED.blend and .glb next to this script."""
import json, os, bpy
from shapely.geometry import shape, MultiPolygon
from shapely import affinity
import trimesh

HERE = os.path.dirname(os.path.abspath(__file__)); ENG = os.path.join(HERE, "..", "eng")
WALL_H, SLAB, DECK = 3.0, 0.2, 3.5
CX, NOSE = 995.0, 30.0                 # flight deck centre line and nose (px)
K = 0.63                               # lower-deck px -> flight-deck px
LOW_STAIR, FLIGHT_STAIR = (1305.0, 60.0), (987.0, 1150.0)   # top of the lower stairs -> under passage 11
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1); m.diffuse_color = (*rgb, 1); return m
M_FLOOR, M_WALL_F, M_WALL_L = mat("floor", (0.18, 0.2, 0.23)), mat("wall_flight", (0.55, 0.62, 0.72)), mat("wall_lower", (0.62, 0.64, 0.68))
def coll(name):
    c = bpy.data.collections.new(name); bpy.context.scene.collection.children.link(c); return c
def add(geom, height, z, name, material, collection):
    polys = list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]
    meshes = [trimesh.creation.extrude_polygon(p.buffer(0), height) for p in polys if p.area > 1e-4]
    tm = trimesh.util.concatenate(meshes); tm.apply_translation((0, 0, z))
    me = bpy.data.meshes.new(name); me.from_pydata(tm.vertices.tolist(), [], tm.faces.tolist()); me.update()
    ob = bpy.data.objects.new(name, me); ob.data.materials.append(material); collection.objects.link(ob)

F = json.load(open(os.path.join(ENG, "flight_plan.json"))); L = json.load(open(os.path.join(ENG, "lower_plan.json")))
s = 1.2 / float(F["door"])
to_m = lambda g: affinity.affine_transform(g, [s, 0, 0, -s, -CX * s, NOSE * s])     # x across (centre 0), y forward (nose 0)
low_to_f = lambda g: affinity.affine_transform(g, [K, 0, 0, K, FLIGHT_STAIR[0] - K * LOW_STAIR[0], FLIGHT_STAIR[1] - K * LOW_STAIR[1]])
cL = coll("DECK_lower")
lf, lw = to_m(low_to_f(shape(L["floor"]))), to_m(low_to_f(shape(L["walls"])))
add(lf, SLAB, -SLAB, "lower_floor", M_FLOOR, cL); add(lw, WALL_H, 0, "lower_walls", M_WALL_L, cL)
cF = coll("DECK_flight")
ff, fw = to_m(shape(F["floor"])), to_m(shape(F["walls"]))
add(ff, SLAB, DECK - SLAB, "flight_floor", M_FLOOR, cF); add(fw, WALL_H, DECK, "flight_walls", M_WALL_F, cF)
# exterior hull outline from the world map, as a red guide line at the lower floor
from shapely.geometry import Polygon
H = json.load(open(os.path.join(ENG, "hull_outline.json"))); hk = H["to_flight_px"]
hull = Polygon(H["outline"])
hull = affinity.affine_transform(hull, [hk["scale"], 0, 0, hk["scale"], hk["flight_round_room"][0] - hk["scale"] * hk["world_hub"][0],
                                        hk["flight_round_room"][1] - hk["scale"] * hk["world_hub"][1]])
M_HULL = mat("hull_ref", (0.9, 0.45, 0.45))
add(to_m(hull).exterior.buffer(0.15), 0.3, -SLAB, "hull_outline", M_HULL, coll("HULL_reference"))
hm = bpy.data.objects.new("scale_human_1.8m", None); hm.empty_display_type = "SINGLE_ARROW"; hm.empty_display_size = 1.8
bpy.context.scene.collection.objects.link(hm)
out = os.path.join(HERE, "defender_graybox_WIP_NOT_APPROVED")
bpy.ops.wm.save_as_mainfile(filepath=out + ".blend")
bpy.ops.export_scene.gltf(filepath=out + ".glb", export_format="GLB")
sz = lambda g: f"{g.bounds[2]-g.bounds[0]:.1f} x {g.bounds[3]-g.bounds[1]:.1f}"
u = ff.union(lf)
print("flight deck m:", sz(ff), "| lower deck m:", sz(lf), "| whole:", sz(u), "| hull:", sz(to_m(hull)))
