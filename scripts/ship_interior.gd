class_name ShipInterior
extends Control
## v12.97 (owner brief, job 2): a SHIP INTERIOR STAGE built from the official holographic deck plan
## (HL_<Faction><Class>_HoloDeck_*.png). A new stage type: not rooms.gd (the station 360 panoramas) and not
## Boarding (the mech-scale flight-game boarding). On foot, one main deck, blocked out from basic shapes:
##   - the plan itself is the floor (the official overlay) and the minimap
##   - every cyan wall line the plan draws is a box with collision (tools/holodeck/extract.py turns the PNG into
##     assets/holodeck/<id>.json: wall boxes, room floors, green-square doors, room names)
##   - every labelled room is a named Room_<name> node with its floor patch and its name over it
##   - every green square is a Door_<n> node (an opening through the wall with a green frame); one on the outer
##     hull is an AIRLOCK
## Nothing else is invented: no extra decks, no props. Lifts drawn on the plan are marked but go nowhere (one deck).
## Runs in its own 3D world (a SubViewport), so the flight scene underneath is untouched; LEAVE puts you back.

signal left

const M_PER_CELL := 0.6      # 1 plan cell = 4 px = 0.6 m (1 px = 0.15 m: the Unity Capital deck is about 154 x 230 m)
const WALL_H := 2.6
const WALK_SPEED := 6.0
const RUN_SPEED := 10.0
const CAM_OFF := Vector3(0, 22.0, 12.0)

var ship_id := ""
var entry := {}
var data := {}
var world: Node3D
var vp: SubViewport
var cam: Camera3D
var body: CharacterBody3D
var room_label: Label
var minimap: TextureRect
var dot: ColorRect
var room_now := ""
var move_override := Vector2.ZERO   # tests / touch stick: x = right, y = forward
var _stick_id := -1
var _stick_from := Vector2.ZERO
var _room_grid := PackedInt32Array()
var rooms_by_id := {}
var doors: Array = []

static func can_open(id: String) -> bool:
	return str(FleetCatalog.get_entry(id).get("stage", "")) != ""

## Builds the stage for a fleet ship. Returns null when that ship has no stage yet.
static func create(id: String) -> ShipInterior:
	if not can_open(id): return null
	var s := ShipInterior.new()
	s.ship_id = id
	s.entry = FleetCatalog.get_entry(id)
	var f := FileAccess.open(str(s.entry["stage"]), FileAccess.READ)
	if f == null: return null
	s.data = JSON.parse_string(f.get_as_text())
	s.name = "ShipInterior"
	s._build()
	return s

func cell_to_world(cx: float, cy: float) -> Vector3:
	return Vector3((cx - float(data["w"]) * 0.5) * M_PER_CELL, 0.0, (cy - float(data["h"]) * 0.5) * M_PER_CELL)
func world_to_cell(p: Vector3) -> Vector2:
	return Vector2(p.x / M_PER_CELL + float(data["w"]) * 0.5, p.z / M_PER_CELL + float(data["h"]) * 0.5)

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
	world.name = "Deck"
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.05, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.7, 0.85)
	e.ambient_light_energy = 0.8
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 0.7
	world.add_child(sun)
	_grid()
	_plan_floor()
	_walls()
	_rooms()
	_doors()
	_lifts()
	_player()
	_ui()

func _grid() -> void:
	var w := int(data["w"]); var h := int(data["h"])
	_room_grid.resize(w * h)
	var y := 0
	for row in data["room_rows"]:
		var parts: PackedStringArray = str(row).split(",")
		for x in mini(w, parts.size()): _room_grid[y * w + x] = int(parts[x])
		y += 1
	for r in data["rooms"]: rooms_by_id[int(r["id"])] = r

## The official plan as the deck floor, true to scale; one flat collision slab under the whole hull.
func _plan_floor() -> void:
	var tex: Texture2D = load(str(entry["holodeck_res"]))
	var sz := Vector2(float(data["w"]), float(data["h"])) * M_PER_CELL
	var mi := MeshInstance3D.new()
	mi.name = "PlanFloor"
	var pm := PlaneMesh.new()
	pm.size = sz
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.85, 0.9, 1.0)
	mi.material_override = mat
	world.add_child(mi)
	var sb := StaticBody3D.new()
	sb.name = "FloorBody"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(sz.x, 0.4, sz.y)
	cs.shape = bs
	cs.position.y = -0.2
	sb.add_child(cs)
	world.add_child(sb)

## Every wall the plan draws, as a box (one MultiMesh for the looks, one box shape each for collision).
func _walls() -> void:
	var walls: Array = data["walls"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	mm.mesh = bm
	mm.instance_count = walls.size()
	var sb := StaticBody3D.new()
	sb.name = "Walls"
	world.add_child(sb)
	var i := 0
	for r in walls:
		var c := cell_to_world(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
		var s := Vector3(float(r[2]) * M_PER_CELL, WALL_H, float(r[3]) * M_PER_CELL)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(s), c + Vector3(0, WALL_H * 0.5, 0)))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s
		cs.shape = bs
		cs.position = c + Vector3(0, WALL_H * 0.5, 0)
		sb.add_child(cs)
		i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "WallBoxes"
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.85, 1.0, 0.38)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.65, 0.9)
	mat.emission_energy_multiplier = 0.35
	mmi.material_override = mat
	world.add_child(mmi)

## Each labelled room: a Room_<name> node with its floor patch (a thin box) and its name over it.
func _rooms() -> void:
	var tint := StandardMaterial3D.new()
	tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint.albedo_color = Color(0.2, 0.7, 1.0, 0.12)
	for r in data["rooms"]:
		var rn := Node3D.new()
		rn.name = "Room_" + str(r["name"]).validate_node_name().replace(" ", "_")
		rn.set_meta("room", r["name"])
		world.add_child(rn)
		for b in (data["room_floor"] as Dictionary).get(str(r["id"]), []):
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(float(b[2]) * M_PER_CELL, 0.04, float(b[3]) * M_PER_CELL)
			mi.mesh = bm
			mi.material_override = tint
			mi.position = cell_to_world(float(b[0]) + float(b[2]) * 0.5, float(b[1]) + float(b[3]) * 0.5) + Vector3(0, 0.03, 0)
			rn.add_child(mi)
		var lb := Label3D.new()
		lb.text = str(r["name"]).to_upper()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 72
		lb.pixel_size = 0.02
		lb.outline_size = 14
		lb.modulate = Color(0.85, 1.0, 1.0)
		lb.no_depth_test = true
		lb.position = cell_to_world(float(r["at"][0]), float(r["at"][1])) + Vector3(0, 4.0, 0)
		rn.add_child(lb)

## The green squares: a Door_<n> node each, a green frame round the opening; AIRLOCK when it is on the hull.
func _doors() -> void:
	var rows: Array = data["rows"]
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.2, 1.0, 0.35)
	gmat.emission_enabled = true
	gmat.emission = Color(0.15, 1.0, 0.3)
	gmat.emission_energy_multiplier = 1.4
	var n := 0
	for d in data["doors"]:
		n += 1
		var cx := float(d[0]); var cy := float(d[1])
		var hull := false
		for oy in range(-4, 5):   # (outside the hull within 4 cells of the green square: an airlock)
			for ox in range(-4, 5):
				var yy := int(cy) + oy; var xx := int(cx) + ox
				if yy < 0 or yy >= rows.size() or xx < 0 or xx >= str(rows[yy]).length() or str(rows[yy])[xx] == " ": hull = true
		var dn := Node3D.new()
		dn.name = "Door_%d" % n
		dn.set_meta("airlock", hull)
		dn.position = cell_to_world(cx, cy)
		world.add_child(dn)
		var s := maxf(float(d[2]), float(d[3])) * M_PER_CELL + 1.2
		for k in 4:   # a square green frame lying round the opening, plus a lintel bar
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(s if k < 2 else 0.25, 0.12, 0.25 if k < 2 else s)
			mi.mesh = bm
			mi.material_override = gmat
			mi.position = [Vector3(0, 0.08, -s * 0.5), Vector3(0, 0.08, s * 0.5), Vector3(-s * 0.5, 0.08, 0), Vector3(s * 0.5, 0.08, 0)][k]
			dn.add_child(mi)
		var lt := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.6, 0.6, 0.6)
		lt.mesh = lm
		lt.material_override = gmat
		lt.position.y = WALL_H + 0.2
		dn.add_child(lt)
		if hull:
			var al := Label3D.new()
			al.text = "AIRLOCK"
			al.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			al.font_size = 40
			al.pixel_size = 0.02
			al.modulate = Color(0.5, 1.0, 0.6)
			al.position.y = WALL_H + 1.2
			dn.add_child(al)
		doors.append(dn)

func _lifts() -> void:
	var i := 0
	for l in data.get("lifts", []):
		i += 1
		var ln := Node3D.new()
		ln.name = "Lift_%d" % i
		ln.position = cell_to_world(float(l[0]), float(l[1]))
		world.add_child(ln)
		var lb := Label3D.new()
		lb.text = "LIFT (one deck only)"
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 32
		lb.pixel_size = 0.02
		lb.modulate = Color(1, 1, 1, 0.8)
		lb.position.y = 2.0
		ln.add_child(lb)

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
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.75
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.75, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.35, 0.1)
	mi.material_override = mat
	mi.position.y = 0.9
	body.add_child(mi)
	var nose := MeshInstance3D.new()   # which way you face
	var nb := BoxMesh.new()
	nb.size = Vector3(0.2, 0.2, 0.4)
	nose.mesh = nb
	nose.material_override = mat
	nose.position = Vector3(0, 1.4, -0.4)
	body.add_child(nose)
	world.add_child(body)
	var st: Array = data["start"]
	body.position = cell_to_world(float(st[0]), float(st[1])) + Vector3(0, 0.1, 0)
	cam = Camera3D.new()
	cam.fov = 55
	cam.current = true
	world.add_child(cam)

func _ready() -> void:
	_cam_follow(1.0)

func _ui() -> void:
	var top := Label.new()
	top.name = "ShipName"
	top.text = "%s  ·  MAIN DECK  ·  blockout (basic shapes)" % str(entry["name"]).to_upper()
	top.position = Vector2(20, 14)
	top.add_theme_font_size_override("font_size", 20)
	top.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	top.add_theme_constant_override("outline_size", 6)
	top.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_child(top)
	room_label = Label.new()
	room_label.name = "RoomName"
	room_label.position = Vector2(20, 44)
	room_label.add_theme_font_size_override("font_size", 30)
	room_label.add_theme_color_override("font_color", Color(1, 1, 1))
	room_label.add_theme_constant_override("outline_size", 8)
	room_label.add_theme_color_override("font_outline_color", Color(0, 0.1, 0.2))
	add_child(room_label)
	var hint := Label.new()
	hint.text = "WASD / arrows to walk · Shift to run · drag on the left to walk (touch)"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -40)
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95, 0.85))
	add_child(hint)
	# the official plan as the minimap, with you on it
	minimap = TextureRect.new()
	minimap.name = "Minimap"
	minimap.texture = load(str(entry["holodeck_res"]))
	minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	minimap.stretch_mode = TextureRect.STRETCH_SCALE
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.size = Vector2(190, 285)
	minimap.position = Vector2(-206, 14)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(minimap)
	dot = ColorRect.new()
	dot.color = Color(1.0, 0.25, 0.2)
	dot.size = Vector2(9, 9)
	minimap.add_child(dot)
	var leave := Button.new()
	leave.name = "Leave"
	leave.text = "LEAVE SHIP"
	leave.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	leave.custom_minimum_size = Vector2(170, 56)
	leave.position = Vector2(-190, -76)
	leave.add_theme_font_size_override("font_size", 20)
	leave.pressed.connect(close)
	add_child(leave)

func close() -> void:
	left.emit()
	queue_free()

func _cam_follow(k: float) -> void:
	var want := body.global_position + CAM_OFF
	cam.global_position = cam.global_position.lerp(want, k)
	cam.look_at(body.global_position + Vector3(0, 1.0, 0), Vector3.UP)

func _gui_input(ev: InputEvent) -> void:
	# touch / mouse drag on the left half = a walking stick
	if ev is InputEventScreenTouch or ev is InputEventMouseButton:
		var pressed: bool = ev.pressed
		var pos: Vector2 = ev.position
		var idx: int = ev.index if ev is InputEventScreenTouch else 0
		if pressed and pos.x < size.x * 0.5 and _stick_id == -1: _stick_id = idx; _stick_from = pos
		elif not pressed and idx == _stick_id: _stick_id = -1; move_override = Vector2.ZERO
	elif (ev is InputEventScreenDrag or ev is InputEventMouseMotion) and _stick_id != -1:
		var d: Vector2 = (ev.position - _stick_from) / 70.0
		move_override = Vector2(clampf(d.x, -1, 1), clampf(-d.y, -1, 1))

func _physics_process(dt: float) -> void:
	if not is_instance_valid(body): return
	var v := move_override
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y += 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y -= 1
	if v.length() > 1.0: v = v.normalized()
	var sp := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	var dir := Vector3(v.x, 0, -v.y)   # the camera looks nose-up (-Z), so up on the stick is toward the bow
	body.velocity.x = dir.x * sp
	body.velocity.z = dir.z * sp
	body.velocity.y = 0.0 if body.is_on_floor() else body.velocity.y - 20.0 * dt
	if dir.length() > 0.1: body.rotation.y = atan2(-dir.x, -dir.z)
	body.move_and_slide()
	_cam_follow(clampf(dt * 6.0, 0.0, 1.0))
	room_now = room_at(body.global_position)
	room_label.text = room_now if room_now != "" else "Corridor"
	var c := world_to_cell(body.global_position)
	dot.position = Vector2(c.x / float(data["w"]) * minimap.size.x, c.y / float(data["h"]) * minimap.size.y) - dot.size * 0.5

## The labelled room under a point ("" = corridor or open deck).
func room_at(p: Vector3) -> String:
	var c := world_to_cell(p)
	var x := int(c.x); var y := int(c.y); var w := int(data["w"])
	if x < 0 or y < 0 or x >= w or y >= int(data["h"]): return ""
	var rid := _room_grid[y * w + x]
	return str(rooms_by_id[rid]["name"]) if rooms_by_id.has(rid) else ""

## Where a room's label sits (tests and a later GO TO).
func room_point(nm: String) -> Vector3:
	for r in data["rooms"]:
		if str(r["name"]) == nm: return cell_to_world(float(r["at"][0]), float(r["at"][1]))
	return Vector3.INF
