class_name ShipInterior
extends Control
## v12.97 / v12.98 (owner: "graybox, just like the regular dungeons, but now we actually have the floor plan ...
## do it like Metal Gear Solid style, we only need the inside"): a SHIP INTERIOR STAGE seen from above and behind
## (the Metal Gear Solid camera), graybox, laid out exactly from the official holographic deck plan
## (HL_<Faction><Class>_HoloDeck_*.png). Not rooms.gd (station 360 panoramas) and not Boarding (mech-scale). One deck:
##   - every cyan wall line the plan draws is a full-height grey wall with collision, on a grey grid floor
##     (tools/holodeck/extract.py turns the PNG into assets/holodeck/<id>.json); no ceiling (the camera is above)
##   - every labelled room is a Room_<name> node: a colour-coded floor patch and its name sign
##   - every green square is a Door_<n> doorway (the opening, green door lights, the green floor mark); AIRLOCK on the hull
##   - the plan itself is the minimap, with you on it
## Nothing invented: no extra decks, no props. Lifts drawn on the plan are marked but go nowhere (one deck).
## Runs in its own 3D world (a SubViewport); LEAVE SHIP puts you back where you were.
## Keys: WASD / arrows move (up = toward the bow), Shift run. Touch: drag anywhere to move.

signal left

const M_PER_CELL := 0.6      # 1 plan cell = 4 px = 0.6 m (1 px = 0.15 m: the Unity Capital deck is about 154 x 230 m)
const WALL_H := 3.4
const CAM_OFF := Vector3(0, 14.0, 7.0)   # above and behind (south of) you, looking down: the MGS view
const WALK_SPEED := 4.6      # (same as the on-foot escape, StationEscape)
const RUN_SPEED := 7.2
const GRAV := 18.0
const FOV := 50.0

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
var _grid_tex: Texture2D

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
func _rect_center(r: Array) -> Vector3:
	return cell_to_world(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
func _rect_size(r: Array, h: float) -> Vector3:
	return Vector3(float(r[2]) * M_PER_CELL, h, float(r[3]) * M_PER_CELL)

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
	e.background_color = Color(0.03, 0.035, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.65, 0.72)
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.12, 0.14, 0.18)
	e.fog_density = 0.006
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()   # a soft key light so walls and floor read apart (graybox shading)
	sun.rotation_degrees = Vector3(-62, 35, 0)
	sun.light_energy = 0.55
	world.add_child(sun)
	_grid_tex = _make_grid()
	_grid()
	_floor_ceiling()
	_walls()
	_rooms()
	_doors()
	_lifts()
	_player()
	_ui()

## The graybox grid: a 2 m tile with a darker line round it (one texture, laid in world space on every surface).
static func _make_grid() -> Texture2D:
	var img := Image.create(128, 128, true, Image.FORMAT_RGB8)
	img.fill(Color(0.62, 0.63, 0.66))
	for i in 128:
		for t in 3:
			img.set_pixel(i, t, Color(0.42, 0.43, 0.46)); img.set_pixel(t, i, Color(0.42, 0.43, 0.46))
		img.set_pixel(i, 64, Color(0.55, 0.56, 0.59)); img.set_pixel(64, i, Color(0.55, 0.56, 0.59))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _grey(col: Color, scale := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _grid_tex
	m.albedo_color = col
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale   # 1 / 2 m tiles
	m.roughness = 0.85
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _grid() -> void:
	var w := int(data["w"]); var h := int(data["h"])
	_room_grid.resize(w * h)
	var y := 0
	for row in data["room_rows"]:
		var parts: PackedStringArray = str(row).split(",")
		for x in mini(w, parts.size()): _room_grid[y * w + x] = int(parts[x])
		y += 1
	for r in data["rooms"]: rooms_by_id[int(r["id"])] = r

## A grey grid floor over the whole deck and one flat collision slab (no ceiling: the camera looks down from above).
func _floor_ceiling() -> void:
	var sz := Vector2(float(data["w"]), float(data["h"])) * M_PER_CELL
	var fl := MeshInstance3D.new()
	fl.name = "Floor"
	var pm := PlaneMesh.new()
	pm.size = sz
	fl.mesh = pm
	fl.material_override = _grey(Color(0.78, 0.8, 0.84))
	world.add_child(fl)
	var sb := StaticBody3D.new()
	sb.name = "FloorBody"
	for yy in [-0.2]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(sz.x, 0.4, sz.y)
		cs.shape = bs
		cs.position.y = yy
		sb.add_child(cs)
	world.add_child(sb)

## Every wall the plan draws: a full-height grey box (one MultiMesh for the looks, a box shape each for collision).
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
		var c := _rect_center(r) + Vector3(0, WALL_H * 0.5, 0)
		var s := _rect_size(r, WALL_H)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(s), c))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s
		cs.shape = bs
		cs.position = c
		sb.add_child(cs)
		i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "WallBoxes"
	mmi.multimesh = mm
	mmi.material_override = _grey(Color(0.68, 0.7, 0.75))
	world.add_child(mmi)
	# a thin cyan strip along the foot of every wall: the plan's line colour, so you can read the layout
	var mm2 := MultiMesh.new()
	mm2.transform_format = MultiMesh.TRANSFORM_3D
	mm2.mesh = bm
	mm2.instance_count = walls.size()
	i = 0
	for r in walls:
		var s2 := _rect_size(r, 0.08) + Vector3(0.04, 0, 0.04)
		mm2.set_instance_transform(i, Transform3D(Basis.from_scale(s2), _rect_center(r) + Vector3(0, 0.04, 0)))
		i += 1
	var trim := MultiMeshInstance3D.new()
	trim.name = "WallTrim"
	trim.multimesh = mm2
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(0.25, 0.8, 0.95)
	trim.material_override = tm
	world.add_child(trim)

## Each labelled room: a Room_<name> node with its floor patch (a colour-coded graybox tint) and its name sign.
const ROOM_TINTS := [Color(0.55, 0.75, 0.95), Color(0.95, 0.8, 0.5), Color(0.6, 0.9, 0.65), Color(0.9, 0.6, 0.6),
	Color(0.75, 0.65, 0.95), Color(0.6, 0.9, 0.9), Color(0.95, 0.7, 0.85)]
func _rooms() -> void:
	var k := 0
	for r in data["rooms"]:
		var rn := Node3D.new()
		rn.name = "Room_" + str(r["name"]).validate_node_name().replace(" ", "_")
		rn.set_meta("room", r["name"])
		world.add_child(rn)
		var tint := StandardMaterial3D.new()
		tint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var tc: Color = ROOM_TINTS[k % ROOM_TINTS.size()]
		tint.albedo_color = Color(tc.r, tc.g, tc.b, 0.22)
		k += 1
		for b in (data["room_floor"] as Dictionary).get(str(r["id"]), []):
			var mi := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = _rect_size(b, 0.02)
			mi.mesh = pm
			mi.material_override = tint
			mi.position = _rect_center(b) + Vector3(0, 0.012, 0)
			rn.add_child(mi)
		var lb := Label3D.new()
		lb.text = str(r["name"]).to_upper()
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 48
		lb.pixel_size = 0.008
		lb.outline_size = 10
		lb.modulate = Color(0.85, 1.0, 1.0)
		lb.pixel_size = 0.014
		lb.position = cell_to_world(float(r["at"][0]), float(r["at"][1])) + Vector3(0, 3.8, 0)
		rn.add_child(lb)

## The green squares: a doorway each (the opening, green door lights on top of the walls beside it, the green floor
## mark of the plan's square); AIRLOCK on the hull.
func _doors() -> void:
	var rows: Array = data["rows"]
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(0.25, 1.0, 0.4)
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
		var lt := MeshInstance3D.new()   # the green door light, just under the header
		var lm := BoxMesh.new()
		lm.size = Vector3(maxf(float(d[2]) * M_PER_CELL, 0.5), 0.12, maxf(float(d[3]) * M_PER_CELL, 0.5))
		lt.mesh = lm
		lt.material_override = gmat
		lt.position.y = WALL_H + 0.05
		dn.add_child(lt)
		var fl := MeshInstance3D.new()   # and a green mark on the floor of the doorway (the plan's square)
		var fm := BoxMesh.new()
		fm.size = Vector3(maxf(float(d[2]) * M_PER_CELL, 0.5), 0.02, maxf(float(d[3]) * M_PER_CELL, 0.5))
		fl.mesh = fm
		fl.material_override = gmat
		fl.position.y = 0.02
		dn.add_child(fl)
		if hull:
			var al := Label3D.new()
			al.text = "AIRLOCK"
			al.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			al.font_size = 32
			al.pixel_size = 0.008
			al.modulate = Color(0.5, 1.0, 0.6)
			al.position.y = WALL_H + 0.6
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
		lb.font_size = 28
		lb.pixel_size = 0.008
		lb.modulate = Color(1, 1, 1, 0.85)
		lb.position.y = 2.1
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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.72, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.2, 0.05)
	var mi := MeshInstance3D.new()   # a stand-in figure (graybox): body and a visor showing which way you face
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.75
	mi.mesh = cm
	mi.material_override = mat
	mi.position.y = 0.9
	body.add_child(mi)
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.42, 0.16, 0.3)
	visor.mesh = vb
	var vm := StandardMaterial3D.new()
	vm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vm.albedo_color = Color(0.3, 0.9, 1.0)
	visor.material_override = vm
	visor.position = Vector3(0, 1.5, -0.28)
	body.add_child(visor)
	world.add_child(body)
	var st: Array = data["start"]
	body.position = cell_to_world(float(st[0]), float(st[1])) + Vector3(0, 0.1, 0)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.current = true
	world.add_child(cam)

func _ready() -> void:
	_cam_follow(1.0)

func _cam_follow(k: float) -> void:
	cam.global_position = cam.global_position.lerp(body.global_position + CAM_OFF, k)
	cam.look_at(body.global_position + Vector3(0, 1.0, -1.0), Vector3.UP)

func _ui() -> void:
	var top := Label.new()
	top.name = "ShipName"
	top.text = "%s  ·  MAIN DECK  ·  graybox" % str(entry["name"]).to_upper()
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
	hint.text = "WASD / arrows walk (up = toward the bow) · Shift run  |  touch: drag to walk"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -40)
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 0.85))
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

func _gui_input(ev: InputEvent) -> void:
	# touch / mouse drag anywhere = a walking stick (up on the screen = toward the bow)
	if ev is InputEventScreenTouch or ev is InputEventMouseButton:
		var pressed: bool = ev.pressed
		var idx: int = ev.index if ev is InputEventScreenTouch else 0
		if pressed and _stick_id == -1: _stick_id = idx; _stick_from = ev.position
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
	var dir := Vector3(v.x, 0, -v.y)   # the camera looks bow-ward (-Z): up on the stick is toward the bow
	body.velocity.x = dir.x * sp
	body.velocity.z = dir.z * sp
	body.velocity.y = 0.0 if body.is_on_floor() else body.velocity.y - GRAV * dt
	if dir.length() > 0.1: body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), clampf(dt * 12.0, 0.0, 1.0))
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
