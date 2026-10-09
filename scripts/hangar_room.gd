class_name HangarRoom
extends Node3D
## v1.5q: the hangar as ONE unified room, all from one rich part of the owner's (hlhang03: the wall with the doors,
## its squared panels and its floor). The owner: same kind of piece everywhere; one wall becomes four walls; 3 x 3;
## the floor and ceiling cut from that same piece so copies meet seamlessly; keep the mech pad, on that same floor.
##   walls:   the wall section (four bays, three doors), three side by side on each of the four sides (square room)
##   floor:   its floor, cut to a tile and mirrored into a 2 x 2 block so every edge meets its mirror (no seams),
##            repeated across the room
##   ceiling: a block of its squared panels, cut and mirrored the same way, repeated overhead
##   pad:     the launch pad frame with its own deck taken out, so the mech stands on the room's floor
## Each floor / ceiling grid is a whole number of tiles stretched a little to fit exactly; drawn as MultiMeshes.
## Built in "plan" units and scaled by Data.HANGAR_SCALE so the player's mech fits. The same room is every hangar.

const DIR := "res://assets/hangar/"

var W := 0.0          # room size in plan units (square: three wall sections a side)
var D := 0.0
var H := 0.0
var parts := 0        # pieces placed (tests)
var tris := 0         # triangles drawn (tests / budget)
var missing: Array = []
var surfaces := {}    # surface -> [columns, rows, tile width, tile depth, filled width, filled depth] (tests: no gaps)
var walls_per_side := 0
var pad_center := Vector3.ZERO     # where the mech stands (plan units, before HANGAR_SCALE)
var ship_spot := Vector3.ZERO
var floor_top := 0.0

static func available() -> bool:
	return ResourceLoader.exists(DIR + Data.HANGAR_WALL + ".glb") and ResourceLoader.exists(DIR + Data.HANGAR_FLOOR + ".glb")

func _piece(key: String) -> Array:   # [mesh, aabb (in the file's space), the mesh node's own transform]
	var p := DIR + key + ".glb"
	if not ResourceLoader.exists(p):
		missing.append(key)
		return []
	var scene: Node3D = (load(p) as PackedScene).instantiate()
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var out := [mi.mesh, mi.transform * mi.mesh.get_aabb(), mi.transform]
	scene.free()
	return out

func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count(): n += m.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	return n

func _multi(nm: String, pc: Array, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pc[0]
	mm.instance_count = xforms.size()
	for k in xforms.size(): mm.set_instance_transform(k, xforms[k] * (pc[2] as Transform3D))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	parts += xforms.size()
	tris += _tris(pc[0]) * xforms.size()

func build() -> void:
	var wall := _piece(Data.HANGAR_WALL)
	var flo := _piece(Data.HANGAR_FLOOR)
	var cei := _piece(Data.HANGAR_CEILING)
	if wall.is_empty() or flo.is_empty() or cei.is_empty(): return
	var wb: AABB = wall[1]
	H = Data.HANGAR_HEIGHT
	var s := H / wb.size.y                       # one scale for the wall sections
	walls_per_side = Data.HANGAR_WALLS_PER_SIDE
	W = wb.size.x * s * walls_per_side
	D = W
	var wd := wb.size.z * s
	# ---- walls: three sections on each side, backs on the room's outline, facing in
	var wx: Array = []
	var back_c := Vector3(wb.get_center().x, wb.position.y, wb.position.z)
	var seg := wb.size.x * s
	for side in [[Basis(), func(u): return Vector3(-W / 2 + u, 0, -D / 2)],
			[Basis(Vector3.UP, PI), func(u): return Vector3(W / 2 - u, 0, D / 2)],
			[Basis(Vector3.UP, PI / 2), func(u): return Vector3(-W / 2, 0, D / 2 - u)],
			[Basis(Vector3.UP, -PI / 2), func(u): return Vector3(W / 2, 0, -D / 2 + u)]]:
		var b: Basis = (side[0] as Basis) * Basis.from_scale(Vector3.ONE * s)
		for i in walls_per_side:
			var at: Vector3 = (side[1] as Callable).call((i + 0.5) * seg)
			wx.append(Transform3D(b, at - b * back_c))
	_multi("Walls", wall, wx)
	# ---- floor: the seamless floor tile, a grid stretched to fill the room exactly
	var fb: AABB = flo[1]
	var cols := maxi(1, roundi(W / Data.HANGAR_FLOOR_TILE))
	var tw := W / cols
	var fs := Vector3(tw / fb.size.x, Data.HANGAR_FLOOR_TILE / fb.size.x, tw / fb.size.z)
	var fx: Array = []
	var fc := Vector3(fb.get_center().x, fb.position.y, fb.get_center().z)
	for i in cols:
		for j in cols:
			var b := Basis.from_scale(fs)
			var at := Vector3(-W / 2 + (i + 0.5) * tw, 0, -D / 2 + (j + 0.5) * tw)
			fx.append(Transform3D(b, at - b * fc))
	_multi("Floor", flo, fx)
	floor_top = fb.size.y * fs.y
	surfaces["floor"] = [cols, cols, tw, tw, cols * tw, cols * tw]
	# ---- ceiling: the squared-panel tile (it faces +Z in its file), turned to face down, a grid overhead
	var cb: AABB = cei[1]
	var ccols := maxi(1, roundi(W / Data.HANGAR_CEILING_TILE))
	var crows := maxi(1, roundi(D / (Data.HANGAR_CEILING_TILE * cb.size.y / cb.size.x)))
	var cw := W / ccols
	var cd := D / crows
	var cs := Vector3(cw / cb.size.x, cd / cb.size.y, Data.HANGAR_CEILING_DEPTH / cb.size.z)
	var crot := Basis(Vector3.RIGHT, PI / 2)    # front (+Z) turns to face down (-Y)
	var cc := Vector3(cb.get_center().x, cb.get_center().y, cb.position.z)
	var cx: Array = []
	for i in ccols:
		for j in crows:
			var b := crot * Basis.from_scale(cs)
			var at := Vector3(-W / 2 + (i + 0.5) * cw, H, -D / 2 + (j + 0.5) * cd)
			cx.append(Transform3D(b, at - b * cc))
	_multi("Ceiling", cei, cx)
	surfaces["ceiling"] = [ccols, crows, cw, cd, ccols * cw, crows * cd]
	surfaces["walls"] = [walls_per_side, 4, seg, wd, walls_per_side * seg, W]
	_backing()
	_corners(wd)
	# ---- the mech pad, on the room's floor, its back towards the back wall
	pad_center = Vector3(0, floor_top, -D / 2 + wd + Data.HANGAR_PAD_FROM_WALL)
	var pad := _piece(Data.HANGAR_PAD)
	if not pad.is_empty():
		var pb: AABB = pad[1]
		var ps: float = Data.HANGAR_PLAN_PAD_H / pb.size.y
		var b := Basis.from_scale(Vector3.ONE * ps)
		var back := Vector3(pb.get_center().x, pb.position.y, pb.position.z)
		var at := Vector3(0, floor_top - 0.3, pad_center.z)
		_multi("Pad", pad, [Transform3D(b, at - b * back)])
		pad_center.z = at.z + pb.size.z * ps * 0.5
	ship_spot = Vector3(0, floor_top + Data.HANGAR_SHIP_LIFT, pad_center.z + Data.HANGAR_SHIP_AHEAD)
	_lights()
	scale = Vector3.ONE * Data.HANGAR_SCALE

## The four corners, where two walls' depths meet: a dark steel column fills each, so no gap shows.
func _corners(wd: float) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Data.HANGAR_CORNER_COLOR
	m.metallic = 0.6
	m.roughness = 0.45
	var k := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(wd, H, wd)
			mi.mesh = bm
			mi.position = Vector3(sx * (W / 2 - wd / 2), H / 2, sz * (D / 2 - wd / 2))
			mi.material_override = m
			mi.name = "Backing_corner%d" % k
			k += 1
			add_child(mi)

## A solid shell behind everything in the room's grey, so no seam ever shows black.
func _backing() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Data.HANGAR_SEAM_COLOR
	m.roughness = 0.7
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var e := 0.05
	var n := 0
	for b in [[Vector3(W, H, e), Vector3(0, H / 2, -D / 2)], [Vector3(W, H, e), Vector3(0, H / 2, D / 2)],
			[Vector3(e, H, D), Vector3(-W / 2, H / 2, 0)], [Vector3(e, H, D), Vector3(W / 2, H / 2, 0)],
			[Vector3(W, e, D), Vector3(0, 0.0, 0)], [Vector3(W, e, D), Vector3(0, H + 1.0, 0)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[0]
		mi.mesh = bm
		mi.position = b[1]
		mi.material_override = m
		mi.name = "Backing%d" % n
		n += 1
		add_child(mi)

func _lights() -> void:
	for p in [Vector3(-W * 0.25, H * 0.8, -D * 0.2), Vector3(W * 0.25, H * 0.8, -D * 0.2), Vector3(-W * 0.25, H * 0.8, D * 0.25), Vector3(W * 0.25, H * 0.8, D * 0.25)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = W * 0.6
		o.light_energy = 1.5
		o.light_color = Color(0.92, 0.96, 1.0)
		add_child(o)
	var sp := SpotLight3D.new()   # a white key light on the pad
	sp.position = pad_center + Vector3(0, H * 0.9, D * 0.3)
	sp.look_at_from_position(sp.position, pad_center + Vector3(0, 8.0, 0), Vector3.UP)
	sp.spot_range = H * 2.5
	sp.spot_angle = 28.0
	sp.light_energy = 2.5
	add_child(sp)
