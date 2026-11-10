class_name StationInterior
extends Control
## v13.01 station rebuild, first station: VERANTHOS (owner: "Replace the old Zelda-style station layouts ... built to
## the matching exterior silhouettes and new blueprint concepts ... Start with Veranthos ... plain working doors and
## lifts first. No new combat, quests or yellow-to-purple lock system in this pass").
## A station's inside, on foot, at the exterior model's own game scale. The deck outlines are MEASURED from the model
## (tools/stations/build_<id>.py -> assets/stations_int/<id>.json, in metres from the station's axis); the room names
## follow the owner's blueprint concept; decks the concept does not show are marked as designed additions on screen.
##   - walls: the traced outlines, tall, with the slanted corner panels (eight-sided passages, the owner's rule)
##   - doors: every doorway is a plain sliding door that opens as you walk up
##   - lifts: the same four shafts on every deck; stand on a pad for the UP / DOWN buttons
##   - the deck's map (top right) is your GPS; the red dot is you
## Separate from ShipInterior (fleet ships), Boarding (battleships), StationEscape (alarm) and the hub rooms: none of
## those are touched. Not wired into docking yet: opened from the Station Viewer (WALK INSIDE) while it is reviewed.
## Keys: WASD move, Shift run, drag the right side to look. Touch: left side walks, right side looks.

signal left

const DIR := "res://assets/stations_int/"
const WALL_H := 18.0
const CHAMFER_LO := 1.2
const CHAMFER_HI := 3.0
const DOOR_H := 8.0
const WALK_SPEED := 4.6      # (the same as every on-foot stage)
const RUN_SPEED := 7.2
const GRAV := 18.0
const FOV := 68.0
const SHOULDER := Vector3(0.7, 0.2, 2.9)
const PILOT_GLB := "res://assets/pilot/hl_hova.glb"

var station_id := ""
var data := {}
var world: Node3D
var vp: SubViewport
var cam: Camera3D
var body: CharacterBody3D
var level_i := 0             # index into data["levels"] (0 = the top deck)
var gates: Array = []        # {pos, level, a, b, shape, slide, wide, k, open}
var lift_pads: Array = []    # {pos, level, xz}
var at_lift := {}
var room_now := ""
var move_override := Vector2.ZERO
var yaw := 0.0
var pitch := -0.1
var _stick_id := -1
var _stick_from := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _top: Label
var _room: Label
var _lift_box: HBoxContainer
var _fade: ColorRect
var minimap: TextureRect
var dot: ColorRect
var _maps := {}
var _grid_tex: Texture2D

static func path_of(id: String) -> String: return DIR + id + ".json"
static func can_open(id: String) -> bool: return FileAccess.file_exists(path_of(id))
## The rebuilt station that stands for a 3D station model key ("" = none yet).
static func for_model(key: String) -> String:
	return str({"st3d_veranthos_senate": "veranthos", "st3d_aurelion_citadel": "aurelion", "HL_Station_Solarion_Capital_retopo": "synthari_capital"}.get(key, ""))

static func create(id: String) -> StationInterior:
	if not can_open(id): return null
	var f := FileAccess.open(path_of(id), FileAccess.READ)
	if f == null: return null
	var s := StationInterior.new()
	s.station_id = id
	s.data = JSON.parse_string(f.get_as_text())
	s.name = "StationInterior"
	s._build()
	return s

func level() -> Dictionary: return data["levels"][level_i]
func level_y(i: int) -> float: return float(data["levels"][i]["y"])
func find_level(lid: String) -> int:
	for i in (data["levels"] as Array).size():
		if str(data["levels"][i]["id"]) == lid: return i
	return 0

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	world = Node3D.new()
	world.name = "Station"
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.035, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.65, 0.72)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.1, 0.12, 0.16)
	e.fog_density = 0.0016          # (rooms hundreds of metres across: the far wall fades, it does not vanish)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 35, 0)
	sun.light_energy = 0.55
	world.add_child(sun)
	_grid_tex = ShipInterior._make_grid()
	for i in (data["levels"] as Array).size(): _deck(i)
	_player()
	_ui()

func _mat(col: Color, scale := 0.1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _grid_tex
	m.albedo_color = col
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale      # 10 m tiles: the grid a person reads the size of the place by
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
func _glow(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	for v in [p0, p1, p2, p0, p2, p3]:
		st.set_normal(n)
		st.add_vertex(v)

func _deck(i: int) -> void:
	var lv: Dictionary = data["levels"][i]
	var y0 := float(lv["y"])
	var ext := float(data["extent_m"])
	var tag := "_" + str(lv["id"])
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)     # walls
	var ch := SurfaceTool.new(); ch.begin(Mesh.PRIMITIVE_TRIANGLES)     # slanted corner panels
	var lo := SurfaceTool.new(); lo.begin(Mesh.PRIMITIVE_TRIANGLES)     # cyan line at the foot
	var hi := SurfaceTool.new(); hi.begin(Mesh.PRIMITIVE_TRIANGLES)     # light strip under the ceiling
	var faces := PackedVector3Array()
	var up := Vector3.UP
	for poly in lv["walls"]:
		var n := int((poly as Array).size() / 2)
		for k in n:
			var a := Vector3(float(poly[k * 2]), y0, float(poly[k * 2 + 1]))
			var k2 := (k + 1) % n
			var b := Vector3(float(poly[k2 * 2]), y0, float(poly[k2 * 2 + 1]))
			var e := b - a
			if e.length() < 0.05: continue
			var nrm := Vector3(e.z, 0, -e.x).normalized()   # the walkable side (the builder keeps it on the left)
			_quad(st, a, b, b + up * WALL_H, a + up * WALL_H, nrm)
			faces.append_array([a, b, b + up * WALL_H, a, b + up * WALL_H, a + up * WALL_H])
			var slant := e.length() >= 6.0
			var off: float = CHAMFER_LO + 0.03 if slant else 0.03
			_quad(lo, a + nrm * off, b + nrm * off, b + nrm * off + up * 0.18, a + nrm * off + up * 0.18, nrm)
			if slant:
				_quad(ch, a + nrm * CHAMFER_LO, b + nrm * CHAMFER_LO, b + up * CHAMFER_LO, a + up * CHAMFER_LO, (nrm + up).normalized())
				_quad(ch, a + up * (WALL_H - CHAMFER_HI), b + up * (WALL_H - CHAMFER_HI), b + nrm * CHAMFER_HI + up * WALL_H, a + nrm * CHAMFER_HI + up * WALL_H, (nrm - up).normalized())
			var hy: float = WALL_H - (CHAMFER_HI + 0.4 if slant else 1.0)
			_quad(hi, a + nrm * 0.03 + up * hy, b + nrm * 0.03 + up * hy, b + nrm * 0.03 + up * (hy + 0.16), a + nrm * 0.03 + up * (hy + 0.16), nrm)
	for pair in [[st, "Walls", _mat(Color(0.6, 0.68, 0.8))], [ch, "Chamfers", _mat(Color(0.47, 0.54, 0.66))],
			[lo, "Trim", _glow(Color(0.25, 0.8, 0.95))], [hi, "LightStrip", _glow(Color(0.75, 0.95, 1.0))]]:
		var made: ArrayMesh = (pair[0] as SurfaceTool).commit()
		if made == null or made.get_surface_count() == 0: continue
		var mi := MeshInstance3D.new()
		mi.name = str(pair[1]) + tag
		mi.mesh = made
		mi.material_override = pair[2]
		world.add_child(mi)
	var sb := StaticBody3D.new()
	sb.name = "WallBody" + tag
	var cs := CollisionShape3D.new()
	var shp := ConcavePolygonShape3D.new()
	shp.backface_collision = true
	shp.set_faces(faces)
	cs.shape = shp
	sb.add_child(cs)
	world.add_child(sb)
	for part in [["Floor", y0 - 0.25, 0.5, Color(0.42, 0.47, 0.56)], ["Ceiling", y0 + WALL_H + 0.25, 0.5, Color(0.3, 0.34, 0.42)]]:
		var mi2 := MeshInstance3D.new()
		mi2.name = str(part[0]) + tag
		var bm := BoxMesh.new()
		bm.size = Vector3(ext, float(part[2]), ext)
		mi2.mesh = bm
		mi2.position.y = float(part[1])
		mi2.material_override = _mat(part[3])
		world.add_child(mi2)
		if str(part[0]) == "Floor":
			var fb := StaticBody3D.new()
			fb.name = "FloorBody" + tag
			var fcs := CollisionShape3D.new()
			var fbs := BoxShape3D.new()
			fbs.size = bm.size
			fcs.shape = fbs
			fcs.position.y = float(part[1])
			fb.add_child(fcs)
			world.add_child(fb)
	# rooms: a name sign each
	for r in lv["rooms"]:
		var rn := Node3D.new()
		rn.name = "Room%s_%s" % [tag, str(r["name"]).validate_node_name().replace(" ", "_")]
		rn.position = Vector3(float(r["x"]), y0, float(r["z"]))
		world.add_child(rn)
		var lb := Label3D.new()
		lb.text = str(r["name"]).to_upper()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 64
		lb.outline_size = 12
		lb.pixel_size = 0.03
		lb.modulate = Color(0.85, 1.0, 1.0)
		lb.position.y = 9.0
		rn.add_child(lb)
	# doors: two leaves that part along the wall
	var leaf_mat := _mat(Color(0.26, 0.3, 0.38), 0.25)
	var head_mat := _mat(Color(0.36, 0.4, 0.48), 0.25)
	for d in lv["doors"]:
		var wide := float(d["w"]) + 1.2
		var g := Node3D.new()
		g.name = "Gate%s_%d" % [tag, gates.size()]
		g.position = Vector3(float(d["x"]), y0, float(d["z"]))
		g.rotation.y = -deg_to_rad(float(d["yaw"]))     # yaw: the way you walk through, clockwise from the front (-Z)
		world.add_child(g)
		var leaves := []
		for sgn in [-1.0, 1.0]:
			var leaf := MeshInstance3D.new()
			var bm2 := BoxMesh.new()
			bm2.size = Vector3(wide * 0.5, DOOR_H, 0.8)
			leaf.mesh = bm2
			leaf.material_override = leaf_mat
			leaf.position = Vector3(sgn * wide * 0.25, DOOR_H * 0.5, 0)
			g.add_child(leaf)
			var stripe := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(wide * 0.5 - 0.6, 1.4, 0.86)
			stripe.mesh = sm
			stripe.material_override = _glow(Color(0.25, 1.0, 0.4))
			stripe.position.y = -1.0
			leaf.add_child(stripe)
			leaves.append(leaf)
		var head := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(wide, WALL_H - DOOR_H, 1.4)
		head.mesh = hm
		head.material_override = head_mat
		head.position.y = DOOR_H + (WALL_H - DOOR_H) * 0.5
		g.add_child(head)
		var gb := StaticBody3D.new()
		var gcs := CollisionShape3D.new()
		var gbs := BoxShape3D.new()
		gbs.size = Vector3(wide, DOOR_H, 1.0)
		gcs.shape = gbs
		gcs.position.y = DOOR_H * 0.5
		gb.add_child(gcs)
		g.add_child(gb)
		gates.append({"node": g, "pos": g.position, "level": i, "a": leaves[0], "b": leaves[1], "shape": gcs, "wide": wide, "k": 0.0, "open": false})
	# lift pads
	var n_l := 0
	for l in lv["lifts"]:
		n_l += 1
		var pos := Vector3(float(l[0]), y0, float(l[1]))
		lift_pads.append({"pos": pos, "level": i, "xz": Vector2(float(l[0]), float(l[1]))})
		var pad := MeshInstance3D.new()
		pad.name = "LiftPad%s_%d" % [tag, n_l]
		var tm := TorusMesh.new()
		tm.inner_radius = 3.4
		tm.outer_radius = 4.0
		tm.rings = 32
		tm.ring_segments = 6
		pad.mesh = tm
		pad.scale.y = 0.12
		pad.material_override = _glow(Color(0.3, 0.95, 1.0))
		pad.position = pos + Vector3(0, 0.06, 0)
		world.add_child(pad)
		var lb2 := Label3D.new()
		lb2.text = "LIFT"
		lb2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb2.font_size = 64
		lb2.pixel_size = 0.02
		lb2.outline_size = 10
		lb2.position = pos + Vector3(0, 6.0, 0)
		world.add_child(lb2)

func _player() -> void:
	body = CharacterBody3D.new()
	body.name = "Player"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.9
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "StandIn"
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.75
	mi.mesh = cm
	mi.position.y = 0.9
	body.add_child(mi)
	world.add_child(body)
	var stt: Dictionary = data["start"]
	level_i = find_level(str(stt["level"]))
	body.position = Vector3(float(stt["x"]), level_y(level_i) + 0.1, float(stt["z"]))
	yaw = atan2(-body.position.x, -body.position.z) + PI    # (look in toward the hub)
	yaw = atan2(body.position.x, body.position.z)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.far = 3000.0
	cam.current = true
	world.add_child(cam)
	if ResourceLoader.exists(PILOT_GLB): call_deferred("_pilot")

func _pilot() -> void:
	if not is_instance_valid(body): return
	var inst: Node3D = (load(PILOT_GLB) as PackedScene).instantiate()
	var bb := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var x := mi.transform
		var par := mi.get_parent()
		while par != null and par != inst and par is Node3D:
			x = (par as Node3D).transform * x
			par = par.get_parent()
		var a := x * mi.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	if first: return
	var k := 1.8 / maxf(0.01, bb.size.y)
	inst.scale = Vector3.ONE * k
	inst.rotation.y = PI / 2 if bb.size.z > bb.size.x * 1.3 else PI
	inst.position = Vector3(0, -bb.position.y * k, 0)
	body.add_child(inst)
	(body.get_node("StandIn") as Node3D).visible = false

func _ready() -> void:
	_cam()

func _cam() -> void:
	var pivot := body.global_position + Vector3(0, 1.55, 0)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var want := pivot + b * SHOULDER
	var q := PhysicsRayQueryParameters3D.create(pivot, want)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty(): want = pivot + (hit["position"] - pivot) * 0.86
	cam.global_position = want
	cam.global_transform.basis = b

func look(d: Vector2) -> void:
	yaw -= d.x * 0.006
	pitch = clampf(pitch - d.y * 0.005, -0.9, 0.7)

func _ui() -> void:
	_top = Label.new()
	_top.name = "Title"
	_top.position = Vector2(20, 14)
	_top.add_theme_font_size_override("font_size", 20)
	_top.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	_top.add_theme_constant_override("outline_size", 6)
	_top.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_child(_top)
	_room = Label.new()
	_room.name = "RoomName"
	_room.position = Vector2(20, 44)
	_room.add_theme_font_size_override("font_size", 30)
	_room.add_theme_constant_override("outline_size", 8)
	_room.add_theme_color_override("font_outline_color", Color(0, 0.1, 0.2))
	add_child(_room)
	var hint := Label.new()
	hint.text = "WASD walk · Shift run · drag right side to look  |  touch: left side walks, right side looks"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -40)
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 0.85))
	add_child(hint)
	minimap = TextureRect.new()
	minimap.name = "Minimap"
	minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap.stretch_mode = TextureRect.STRETCH_SCALE
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.size = Vector2(270, 270)
	minimap.position = Vector2(-286, 14)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	dot = ColorRect.new()
	dot.color = Color(1.0, 0.25, 0.2)
	dot.size = Vector2(9, 9)
	minimap.add_child(dot)
	_lift_box = HBoxContainer.new()
	_lift_box.name = "LiftButtons"
	_lift_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_lift_box.position = Vector2(-240, -150)
	_lift_box.custom_minimum_size = Vector2(480, 64)
	_lift_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lift_box.add_theme_constant_override("separation", 18)
	_lift_box.visible = false
	add_child(_lift_box)
	for dir in [-1, 1]:      # (-1 = one deck up: the list runs top deck first)
		var b := Button.new()
		b.name = "Up" if dir == -1 else "Down"
		b.custom_minimum_size = Vector2(230, 64)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(ride.bind(dir))
		_lift_box.add_child(b)
	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "LEAVE STATION"
	leave.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	leave.custom_minimum_size = Vector2(190, 56)
	leave.position = Vector2(-210, -76)
	leave.add_theme_font_size_override("font_size", 20)
	leave.pressed.connect(close)
	add_child(leave)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_show_level()

func _show_level() -> void:
	var lv := level()
	_top.text = "%s  ·  %s %s  ·  graybox  ·  %s" % [str(data["name"]).to_upper(), str(lv["id"]), str(lv["name"]),
		"DESIGNED ADDITION (not on the blueprint)" if bool(lv["proposed"]) else "rooms from the blueprint concept"]
	var mp := DIR + str(lv["map"])
	if ResourceLoader.exists(mp):
		if not _maps.has(mp): _maps[mp] = load(mp)
		minimap.texture = _maps[mp]

func close() -> void:
	left.emit()
	queue_free()

## The pad on the deck above (dir -1) or below (dir +1) in the same shaft, or {}.
func lift_stop(pad: Dictionary, dir: int) -> Dictionary:
	for p in lift_pads:
		if int(p["level"]) == int(pad["level"]) + dir and (p["xz"] as Vector2).distance_to(pad["xz"]) < 0.5: return p
	return {}

func ride(dir: int) -> bool:
	if at_lift.is_empty(): return false
	var to := lift_stop(at_lift, dir)
	if to.is_empty(): return false
	body.global_position = (to["pos"] as Vector3) + Vector3(0, 0.1, 0)
	body.velocity = Vector3.ZERO
	level_i = int(to["level"])
	_show_level()
	if is_instance_valid(_fade):
		_fade.color = Color(0, 0, 0, 1)
		create_tween().tween_property(_fade, "color", Color(0, 0, 0, 0), 0.45)
	return true

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventMouseButton:
		var pressed: bool = ev.pressed
		var idx: int = ev.index if ev is InputEventScreenTouch else 0
		var left_side: bool = ev.position.x < size.x * 0.5
		if pressed:
			if left_side and _stick_id == -1: _stick_id = idx; _stick_from = ev.position
			elif not left_side and _look_id == -1: _look_id = idx; _look_last = ev.position
		else:
			if idx == _stick_id: _stick_id = -1; move_override = Vector2.ZERO
			if idx == _look_id: _look_id = -1
	elif ev is InputEventScreenDrag or ev is InputEventMouseMotion:
		var idx2: int = ev.index if ev is InputEventScreenDrag else (_stick_id if _stick_id != -1 else _look_id)
		if idx2 == _stick_id and _stick_id != -1:
			var d: Vector2 = (ev.position - _stick_from) / 70.0
			move_override = Vector2(clampf(d.x, -1, 1), clampf(-d.y, -1, 1))
		elif idx2 == _look_id and _look_id != -1:
			look(ev.position - _look_last)
			_look_last = ev.position

func _physics_process(dt: float) -> void:
	if not is_instance_valid(body): return
	var v := move_override
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y -= 1
	if v.length() > 1.0: v = v.normalized()
	var sp := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	var dir := Basis(Vector3.UP, yaw) * Vector3(v.x, 0, -v.y)
	body.velocity.x = dir.x * sp
	body.velocity.z = dir.z * sp
	body.velocity.y = 0.0 if body.is_on_floor() else body.velocity.y - GRAV * dt
	if dir.length() > 0.1: body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), clampf(dt * 12.0, 0.0, 1.0))
	else: body.rotation.y = lerp_angle(body.rotation.y, yaw, clampf(dt * 10.0, 0.0, 1.0))
	body.move_and_slide()
	_cam()
	var me := body.global_position
	# doors of this deck open as you come up to them
	for g in gates:
		if int(g["level"]) != level_i: continue
		var d := Vector2(me.x - (g["pos"] as Vector3).x, me.z - (g["pos"] as Vector3).z).length()
		var want: bool = d < float(g["wide"]) * 0.5 + 5.0
		if want != bool(g["open"]):
			g["open"] = want
			(g["shape"] as CollisionShape3D).disabled = want
		var k: float = move_toward(float(g["k"]), 1.0 if want else 0.0, dt * 2.4)
		if k != float(g["k"]):
			g["k"] = k
			var w: float = float(g["wide"])
			(g["a"] as Node3D).position.x = -(w * 0.25 + k * w * 0.5)
			(g["b"] as Node3D).position.x = w * 0.25 + k * w * 0.5
	at_lift = {}
	for p in lift_pads:
		if int(p["level"]) == level_i and Vector2(me.x, me.z).distance_to(p["xz"]) < 4.5: at_lift = p
	_lift_box.visible = not at_lift.is_empty()
	if not at_lift.is_empty():
		for dir2 in [-1, 1]:
			var b: Button = _lift_box.get_node("Up" if dir2 == -1 else "Down")
			var to := lift_stop(at_lift, dir2)
			b.visible = not to.is_empty()
			if not to.is_empty():
				var tl: Dictionary = data["levels"][int(to["level"])]
				b.text = "%s  %s %s" % ["▲" if dir2 == -1 else "▼", str(tl["id"]), str(tl["name"])]
	room_now = room_at(me)
	_room.text = room_now if room_now != "" else "Concourse"
	var ext := float(level().get("map_extent_m", data["extent_m"]))   # (a deck's map may be cropped to the station)
	dot.position = Vector2((me.x / ext + 0.5) * minimap.size.x, (me.z / ext + 0.5) * minimap.size.y) - dot.size * 0.5

## The room you are deepest inside on this deck ("" = a passage).
func room_at(p: Vector3) -> String:
	var best := ""
	var best_k := 1.0
	for r in level()["rooms"]:
		var kk := Vector2(p.x - float(r["x"]), p.z - float(r["z"])).length() / maxf(1.0, float(r["rad"]))
		if kk <= best_k:
			best_k = kk
			best = str(r["name"])
	return best

## Where a room's sign stands on a deck (tests).
func room_point(lid: String, nm: String) -> Vector3:
	var i := find_level(lid)
	for r in data["levels"][i]["rooms"]:
		if str(r["name"]) == nm: return Vector3(float(r["x"]), level_y(i), float(r["z"]))
	return Vector3.INF

## Put yourself on a deck at a point (tests and the lift).
func place(lid: String, at: Vector3) -> void:
	level_i = find_level(lid)
	body.global_position = Vector3(at.x, level_y(level_i) + 0.1, at.z)
	body.velocity = Vector3.ZERO
	_show_level()
