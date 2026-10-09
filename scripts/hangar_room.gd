class_name HangarRoom
extends Node3D
## v1.5p: the hangar, built from the owner's 3D hangar parts (assets/hangar, the "hangar" pack).
## Four walls, a floor and a generated ceiling. Every wall is a continuous backing of panels (two rows, stretched a
## little so each row fills its wall exactly: no gaps), with the big parts standing in front of it:
##   back:  the launch pad in the middle (a solid plate behind its open frame), a mech bay each side, gantries between
##   sides: the wall bays (lockers and walkway), pipes, a valve
##   front: the tall door in a corridor arch, white wall panels either side, a window strip above
## Built in "plan" units (the pad is PLAN_PAD_H tall) and scaled by Data.HANGAR_SCALE so it fits the player's mech.
## Every part file is upright, front at +Z, bottom at y = 0, centred (tools/assetkit/orient_struct.py).

const DIR := "res://assets/hangar/"
const PANELS := ["hangar_panel_a", "hangar_panel_b", "hangar_panel_c", "hangar_panel_d", "hangar_panel_e", "hangar_panel_f"]
const WHITE_PANELS := ["hangar_wall_panel_a", "hangar_wall_panel_b", "hangar_wall_panel_c", "hangar_wall_panel_d", "hangar_wall_panel_e", "hangar_wall_panel_f", "hangar_wall_panel_g"]

var W := 0.0          # room size in plan units (set from Data in build)
var D := 0.0
var H := 0.0
var parts := 0        # part instances placed (tests)
var tris := 0         # triangles placed (tests / budget)
var missing: Array = []
var rows: Array = []  # every wall row: [wall length, length its panels fill, panels] (tests: rows must fill exactly)
var pad_center := Vector3.ZERO     # where the mech stands (plan units, before HANGAR_SCALE)
var ship_spot := Vector3.ZERO      # where the ship is parked
var _scenes := {}
var _boxes := {}

static func available() -> bool:
	return ResourceLoader.exists(DIR + "hangar_launch_pad.glb")

func build() -> void:
	W = Data.HANGAR_SIZE.x
	H = Data.HANGAR_SIZE.y
	D = Data.HANGAR_SIZE.z
	var wd: float = Data.HANGAR_WALL_DEPTH
	# walls: [name, yaw, origin of the wall's left end (seen from inside), along direction, length]
	var walls := {
		"back": [0.0, Vector3(-W / 2, 0, -D / 2), Vector3.RIGHT, W],
		"front": [180.0, Vector3(W / 2, 0, D / 2), Vector3.LEFT, W],
		"left": [90.0, Vector3(-W / 2, 0, D / 2), Vector3.FORWARD, D],
		"right": [-90.0, Vector3(W / 2, 0, -D / 2), Vector3.BACK, D],
	}
	var rh := H / 2.0
	for k in walls:
		var wl: Array = walls[k]
		var lower: Array = WHITE_PANELS if k == "front" else PANELS
		_tile_row(wl, lower, 0.0, rh, wd, k.length())
		_tile_row(wl, PANELS, rh, rh, wd, k.length() + 3)
	var face := -D / 2 + wd   # front face of the back wall
	# back wall: launch pad, mech bays, gantries
	var pad := _place("hangar_launch_pad", Vector3(0, 0, face), Data.HANGAR_PLAN_PAD_H, 0.0)
	if pad:
		var bx := _box("hangar_launch_pad")
		var s: float = Data.HANGAR_PLAN_PAD_H / bx.size.y
		pad_center = Vector3(0, 0, face + bx.size.z * s * 0.5)
		# the owner: the panel behind the pad must not be see-through. A solid plate fills the back of its frame.
		var plate := MeshInstance3D.new()
		plate.name = "PadBackPlate"
		var pm := BoxMesh.new()
		pm.size = Vector3(bx.size.x * s * 0.94, bx.size.y * s * 0.97, 0.6)
		plate.mesh = pm
		plate.material_override = _metal(Color(0.16, 0.17, 0.19), 0.7, 0.45)
		plate.position = Vector3(0, pm.size.y * 0.5, face + 0.35)
		add_child(plate)
	var bay_x: float = Data.HANGAR_BAY_X
	for sx in [-1.0, 1.0]:
		_place("hangar_mech_bay", Vector3(sx * bay_x, 0, face), Data.HANGAR_PLAN_PAD_H, 0.0)
		var g := _place("hangar_gantry", Vector3(sx * Data.HANGAR_GANTRY_X, 0, face + 1.0), Data.HANGAR_GANTRY_LEN, 0.0, "length")
		if g: g.scale.x *= 0.8
		# pipes along the top of the back wall, over each bay
		_place("hangar_pipe_long_b", Vector3(sx * bay_x, H * 0.78, face - 0.2), Data.HANGAR_PLAN_PAD_H, 0.0, "width")
	# side walls: two wall bays each (lockers and a walkway), a pipe run and a valve
	var side_d: float = Data.HANGAR_SIDE_DEPTH
	for side in [["left", -1.0, 90.0], ["right", 1.0, -90.0]]:
		var sx: float = side[1]
		var x := sx * (W / 2 - wd)
		for zc in Data.HANGAR_SIDE_BAYS:
			var n := _place("hangar_wall_bay", Vector3(x, 0, zc), Data.HANGAR_SIDE_H, side[2])
			if n: _limit_depth(n, "hangar_wall_bay", side_d)
		_place("hangar_pipe_riser", Vector3(x, H * 0.62, -D * 0.05), H * 0.16, side[2], "height")
	_place("hangar_valve_wheel", Vector3(W / 2 - wd, H * 0.12, D * 0.42), H * 0.07, -90.0, "height")
	# front wall: the tall door in a corridor arch, a window strip above it
	var ff := D / 2 - wd
	_place("hangar_corridor_arch_b", Vector3(0, 0, ff), H * 0.62, 180.0, "height")
	_place("hangar_door_tall", Vector3(0, 0, ff - 0.3), H * 0.55, 180.0, "height")
	_place("hangar_window_strip", Vector3(0, H * 0.7, ff - 0.2), W * 0.42, 180.0, "width")
	ship_spot = Vector3(0, Data.HANGAR_SHIP_LIFT, pad_center.z + Data.HANGAR_SHIP_AHEAD)
	_floor()
	_ceiling()
	_lights()
	scale = Vector3.ONE * Data.HANGAR_SCALE

## One part. at = where the middle of its BACK touches (plan units); size = its height (fit "height"), length along
## Z (fit "length") or width (fit "width").
func _place(key: String, at: Vector3, size: float, yaw: float, fit := "height") -> Node3D:
	var sc: PackedScene = _scene(key)
	if sc == null: return null
	var bx := _box(key)
	var span: float = bx.size.y if fit == "height" else (bx.size.z if fit == "length" else bx.size.x)
	var s := size / maxf(span, 0.0001)
	var n: Node3D = sc.instantiate()
	n.name = key
	n.scale = Vector3.ONE * s
	n.rotation_degrees.y = yaw
	var back := Vector3(0, 0, bx.position.z * s)
	n.position = at - back.rotated(Vector3.UP, deg_to_rad(yaw))
	add_child(n)
	_count(n)
	return n

## Squash a part front-to-back so it sticks out no more than `depth` (the walkway of a wall bay is deep).
func _limit_depth(n: Node3D, key: String, depth: float) -> void:
	var bx := _box(key)
	var s: float = n.scale.y
	if bx.size.z * s <= depth: return
	var back_local := bx.position.z
	var at := n.position + Vector3(0, 0, back_local * s).rotated(Vector3.UP, n.rotation.y)
	n.scale.z = depth / bx.size.z
	n.position = at - Vector3(0, 0, back_local * n.scale.z).rotated(Vector3.UP, n.rotation.y)

## One row of panels along a wall: each scaled to the row height, the row stretched (a few %) to fill it exactly.
func _tile_row(wl: Array, keys: Array, y0: float, h: float, depth: float, seed: int) -> void:
	var yaw: float = wl[0]
	var o: Vector3 = wl[1]
	var along: Vector3 = wl[2]
	var length: float = wl[3]
	var avail := keys.filter(func(k): return _scene(k) != null)
	if avail.is_empty(): return
	var pick: Array = []
	var widths: Array = []
	var sum := 0.0
	var i := seed
	while sum < length - 0.01:
		var k: String = avail[i % avail.size()]
		var bx := _box(k)
		var w := bx.size.x * h / bx.size.y
		if sum + w * 0.5 > length and not pick.is_empty(): break
		pick.append(k)
		widths.append(w)
		sum += w
		i += 1
	var f := length / sum
	var u := 0.0
	var filled := 0.0
	for j in pick.size():
		var k: String = pick[j]
		var bx := _box(k)
		var s := h / bx.size.y
		var w: float = widths[j] * f
		var n: Node3D = _scene(k).instantiate()
		n.name = "%s_%d" % [k, j]
		n.scale = Vector3(s * f, s, depth / bx.size.z)
		n.rotation_degrees.y = yaw
		var back := Vector3(0, 0, bx.position.z * n.scale.z).rotated(Vector3.UP, deg_to_rad(yaw))
		n.position = o + along * (u + w * 0.5) + Vector3(0, y0, 0) - back
		add_child(n)
		_count(n)
		u += w
		filled += w
	rows.append([length, filled, pick.size()])

func _scene(key: String) -> PackedScene:
	if not _scenes.has(key):
		var p := DIR + key + ".glb"
		_scenes[key] = load(p) if ResourceLoader.exists(p) else null
		if _scenes[key] == null: missing.append(key)
	return _scenes[key]

func _box(key: String) -> AABB:
	if not _boxes.has(key):
		var n: Node3D = _scene(key).instantiate()
		_boxes[key] = ShipFactory._aabb(n, Transform3D.IDENTITY)
		n.free()
	return _boxes[key]

func _count(n: Node) -> void:
	parts += 1
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh: for s in mi.mesh.get_surface_count(): tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3

func _metal(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m

const FLOOR_SHADER := """shader_type spatial;
uniform vec2 size;
uniform vec2 pad;          // launch pad centre (x, z) in plan units
uniform float pad_r;
void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 cell = abs(fract(p / 6.0) - 0.5);
	float seam = smoothstep(0.485, 0.5, max(cell.x, cell.y));
	vec2 id = floor(p / 6.0);
	float tone = 0.16 + 0.03 * fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 col = vec3(tone, tone * 1.02, tone * 1.08) * (1.0 - seam * 0.6);
	// bolts at plate corners
	vec2 q = abs(fract(p / 6.0 + 0.5) - 0.5) * 6.0;
	col *= 1.0 - 0.35 * (1.0 - smoothstep(0.08, 0.14, length(q)));
	// hazard frame in front of the pad
	vec2 d = abs(p - pad) - vec2(pad_r, pad_r * 0.8);
	float frame = step(max(d.x, d.y), 0.0) * step(-1.6, max(d.x, d.y));
	float stripe = step(0.5, fract((p.x + p.y) / 2.4));
	col = mix(col, mix(vec3(0.05), vec3(0.95, 0.72, 0.1), stripe), frame);
	// guide lines from the pad to the door
	float lane = step(abs(abs(p.x) - pad_r * 0.55), 0.25) * step(pad.y + pad_r * 0.8, p.y);
	col = mix(col, vec3(0.9, 0.7, 0.12), lane * 0.85);
	ALBEDO = col;
	METALLIC = 0.6;
	ROUGHNESS = 0.42 + seam * 0.3;
}"""

func _floor() -> void:
	var f := MeshInstance3D.new()
	f.name = "Floor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, D)
	f.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = FLOOR_SHADER
	m.set_shader_parameter("size", Vector2(W, D))
	m.set_shader_parameter("pad", Vector2(pad_center.x, pad_center.z + Data.HANGAR_PLAN_PAD_H * 0.35))
	m.set_shader_parameter("pad_r", Data.HANGAR_PLAN_PAD_H * 0.55)
	f.material_override = m
	add_child(f)

## The generated ceiling: a dark deck, a grid of deep beams, light strips between them and a cornice round the top.
func _ceiling() -> void:
	var root := Node3D.new()
	root.name = "Ceiling"
	add_child(root)
	var deck := _metal(Color(0.1, 0.11, 0.13), 0.6, 0.5)
	var beam := _metal(Color(0.3, 0.31, 0.33), 0.8, 0.35)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.85, 0.93, 1.0)
	lamp.emission_enabled = true
	lamp.emission = Color(0.8, 0.9, 1.0)
	lamp.emission_energy_multiplier = 2.5
	_cbox(root, Vector3(W, 0.8, D), Vector3(0, H + 0.4, 0), deck)
	var step_z := D / float(Data.HANGAR_BEAMS.y)
	var step_x := W / float(Data.HANGAR_BEAMS.x)
	for k in range(1, int(Data.HANGAR_BEAMS.y)):
		_cbox(root, Vector3(W, 2.2, 1.2), Vector3(0, H - 1.1, -D / 2 + k * step_z), beam)
	for k in range(1, int(Data.HANGAR_BEAMS.x)):
		_cbox(root, Vector3(1.0, 1.6, D), Vector3(-W / 2 + k * step_x, H - 0.8, 0), beam)
	for kz in int(Data.HANGAR_BEAMS.y):
		for kx in int(Data.HANGAR_BEAMS.x):
			var c := Vector3(-W / 2 + (kx + 0.5) * step_x, H - 0.15, -D / 2 + (kz + 0.5) * step_z)
			_cbox(root, Vector3(step_x * 0.55, 0.3, 1.2), c, lamp)
	for s in [-1.0, 1.0]:   # cornice: a deep beam round the top of every wall
		_cbox(root, Vector3(W, 2.6, 2.2), Vector3(0, H - 1.3, s * (D / 2 - 1.1)), beam)
		_cbox(root, Vector3(2.2, 2.6, D), Vector3(s * (W / 2 - 1.1), H - 1.3, 0), beam)

func _cbox(root: Node3D, size: Vector3, at: Vector3, m: Material) -> void:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = m
	b.position = at
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(b)

func _lights() -> void:
	for p in [Vector3(-W * 0.25, H * 0.85, -D * 0.15), Vector3(W * 0.25, H * 0.85, -D * 0.15), Vector3(-W * 0.25, H * 0.85, D * 0.25), Vector3(W * 0.25, H * 0.85, D * 0.25)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = W * 0.7
		o.light_energy = 1.4
		o.light_color = Color(0.9, 0.95, 1.0)
		add_child(o)
	var sp := SpotLight3D.new()   # a white key light on the pad
	sp.position = pad_center + Vector3(0, H * 0.9, D * 0.25)
	sp.look_at_from_position(sp.position, pad_center + Vector3(0, Data.HANGAR_PLAN_PAD_H * 0.4, 0), Vector3.UP)
	sp.spot_range = H * 2.0
	sp.spot_angle = 30.0
	sp.light_energy = 3.0
	add_child(sp)
