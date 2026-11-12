"""Check renders for the Kasparov graybox (Workbench): top view, 3/4 view, and the lower deck with the upper deck hidden."""
import bpy, sys, os, mathutils
HERE = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "defender_graybox_WIP_NOT_APPROVED.blend"))
sc = bpy.context.scene; sc.render.engine = 'BLENDER_WORKBENCH'; sc.display.shading.light = 'STUDIO'
sc.display.shading.color_type = 'MATERIAL'; sc.display.shading.show_shadows = True
cam = bpy.data.cameras.new('c'); co = bpy.data.objects.new('c', cam); sc.collection.objects.link(co); sc.camera = co
sc.world = bpy.data.worlds.new('w')
def shot(name, loc, target, ortho=None, res=(1000, 1600), hide=()):
    for o in sc.objects: o.hide_render = o.name in hide
    sc.render.resolution_x, sc.render.resolution_y = res
    co.location = loc
    if ortho: cam.type = 'ORTHO'; cam.ortho_scale = ortho; co.rotation_euler = (0, 0, 0)
    else:
        cam.type = 'PERSP'; cam.lens = 28
        co.rotation_euler = (mathutils.Vector(target) - co.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = os.path.join(HERE, "check_" + name + ".png"); bpy.ops.render.render(write_still=True)
shot("top", (0, -17, 80), None, ortho=40)
shot("persp", (20, -50, 24), (0, -17, 1), res=(1600, 1000))
shot("lower_deck", (20, -50, 24), (0, -17, 1), res=(1600, 1000), hide=("flight_walls", "flight_floor"))
