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
const SHELL_H := 8.8          # v13.00 shell decks: wall height under the ceiling (owner: "higher, like two stories")
const STOREY := 4.4
const CHAMFER_LO := 0.55      # v13.00 (owner: "I don't want square hallways ... hexagons or octagons, the top, bottom and side walls longer than the diagonal walls"): the slanted panel where wall meets floor
const CHAMFER_HI := 1.3       # and where wall meets ceiling: an eight-sided passage, not a box
const DECK_GAP := 11.0       # v13.00: metres between deck floors (upper deck +1, lower deck -1)
const SHOULDER := Vector3(0.7, 0.2, 2.9)   # v13.00: the over-the-shoulder camera (right, up, back), as on the station escape
const PILOT_GLB := "res://assets/pilot/hl_hova.glb"
const CAM_OFF := Vector3(0, 14.0, 7.0)   # above and behind (south of) you, looking down: the MGS view
const WALK_SPEED := 4.6      # (same as the on-foot escape, StationEscape)
const RUN_SPEED := 7.2
const GRAV := 18.0
const FOV := 50.0

var ship_id := ""
var mpc := M_PER_CELL        # v13.78: metres per plan cell for this ship (traced plans carry their own "m_per_cell")
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
var shell := false            # v13.00: this deck has traced wall outlines (tools/holodeck/shell.py): 3D walk-through view
var yaw := 0.0
var pitch := -0.12
var _look_id := -1
var _look_last := Vector2.ZERO
var wall_h := WALL_H
var decks: Array = []         # v13.00: every deck of this ship, the main one (level 0) first
var lift_pads: Array = []    # {pos, level, cell}
var level := 0
var at_lift := {}
var _lift_box: HBoxContainer
var _fade: ColorRect
var _top: Label
var _maps := {}
var gates: Array = []        # v13.00 sliding doors: {node, pos, level, open, a, b, body, slide, k}
var keys := [true, false, false, false]   # green is always open; 1 yellow, 2 orange, 3 red
var key_guards: Array = []   # {node, pos, key}
var _msg: Label
var _msg_t := 0.0
var _chips: Array = []
# v13.00 missions (owner: three kinds on every ship, each then a run back to the hangar)
var mission := ""            # "" (walking round) | sabotage | capture | rescue
var m_stage := 0             # 0 get to the target · 1 back to the hangar · 2 done · -1 failed
var m_timer := 0.0           # sabotage: seconds until the ship goes up
var waypoint := Vector3.INF
var waypoint_text := ""
var _obj_label: Label
var _wp_dot: ColorRect
var _beacon: MeshInstance3D
var _pick: Control
var _target_node: Node3D
var _timer_label: Label

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
	s.mpc = float(s.data.get("m_per_cell", M_PER_CELL))
	s.name = "ShipInterior"
	s._build()
	return s

func cell_to_world(cx: float, cy: float) -> Vector3:
	return Vector3((cx - float(data["w"]) * 0.5) * mpc, 0.0, (cy - float(data["h"]) * 0.5) * mpc)
func world_to_cell(p: Vector3) -> Vector2:
	return Vector2(p.x / mpc + float(data["w"]) * 0.5, p.z / mpc + float(data["h"]) * 0.5)
func _rect_center(r: Array) -> Vector3:
	return cell_to_world(float(r[0]) + float(r[2]) * 0.5, float(r[1]) + float(r[3]) * 0.5)
func _rect_size(r: Array, h: float) -> Vector3:
	return Vector3(float(r[2]) * mpc, h, float(r[3]) * mpc)

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
	shell = data.has("shell")
	wall_h = SHELL_H if shell else WALL_H
	_grid_tex = _make_grid()
	_grid()
	_floor_ceiling()
	if shell:
		_shell_deck(data["shell"], 0.0, "")
		_more_decks()
		_gates(data["shell"], 0.0)
		for dk in data.get("decks", []): _gates(dk["shell"], float(int(dk["level"])) * DECK_GAP)
		_key_guards()
	else: _walls()
	_rooms()
	_doors()
	_lifts()
	_player()
	_ui()
	_web_safe()

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
		var x := 0
		for run in str(row).split(","):   # runs of "room id*count" (tools/holodeck/extract.py rle)
			var vn: PackedStringArray = run.split("*")
			var n := int(vn[1]) if vn.size() > 1 else 1
			for k in n:
				if x < w: _room_grid[y * w + x] = int(vn[0])
				x += 1
		y += 1
	for r in data["rooms"]: rooms_by_id[int(r["id"])] = r

## A grey grid floor over the whole deck and one flat collision slab (no ceiling: the camera looks down from above).
func _floor_ceiling() -> void:
	var sz := Vector2(float(data["w"]), float(data["h"])) * mpc
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
		lb.pixel_size = 0.005 if shell else 0.014   # (a door-sign size when you are inside; big when seen from above)
		lb.position = cell_to_world(float(r["at"][0]), float(r["at"][1])) + Vector3(0, 3.1 if shell else 3.8, 0)
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
		lm.size = Vector3(clampf(float(d[2]) * mpc, 0.5, 1.4), 0.12, clampf(float(d[3]) * mpc, 0.5, 1.4))
		lt.mesh = lm
		lt.material_override = gmat
		lt.position.y = 3.4 if shell else WALL_H + 0.05
		dn.add_child(lt)
		var fl := MeshInstance3D.new()   # and a green mark on the floor of the doorway (the plan's square)
		var fm := BoxMesh.new()
		fm.size = Vector3(clampf(float(d[2]) * mpc, 0.5, 1.4), 0.02, clampf(float(d[3]) * mpc, 0.5, 1.4))   # (the plan's small square)
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
			al.position.y = 2.8 if shell else WALL_H + 0.6
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
		lb.text = "LIFT" if data.has("decks") else "LIFT (one deck only)"
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
	if shell:
		_cam_shoulder()
		return
	cam.global_position = cam.global_position.lerp(body.global_position + CAM_OFF, k)
	cam.look_at(body.global_position + Vector3(0, 1.0, -1.0), Vector3.UP)

func _ui() -> void:
	var top := Label.new()
	top.name = "ShipName"
	top.text = "%s  ·  MAIN DECK  ·  graybox%s" % [str(entry["name"]).to_upper(), "  ·  PROTOTYPE" if shell else ""]
	_top = top
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
	hint.text = "WASD walk · Shift run · drag right side to look  |  touch: left side walks, right side looks" if shell else "WASD / arrows walk (up = toward the bow) · Shift run  |  touch: drag to walk"
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
	if not decks.is_empty(): _lift_ui()
	if shell: _key_ui()
	if shell and not (data.get("objectives", {}) as Dictionary).is_empty(): _mission_ui()

func close() -> void:
	left.emit()
	queue_free()

func _gui_input(ev: InputEvent) -> void:
	if shell:
		_shell_input(ev)
		return
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
	if shell: dir = Basis(Vector3.UP, yaw) * dir   # (walk where the camera looks)
	body.velocity.x = dir.x * sp
	body.velocity.z = dir.z * sp
	body.velocity.y = 0.0 if body.is_on_floor() else body.velocity.y - GRAV * dt
	if dir.length() > 0.1: body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), clampf(dt * 12.0, 0.0, 1.0))
	body.move_and_slide()
	_cam_follow(clampf(dt * 6.0, 0.0, 1.0))
	if not decks.is_empty(): _deck_tick()
	if shell: _gate_tick(dt)
	if mission != "": _mission_tick(dt)
	room_now = room_at(body.global_position)
	room_label.text = room_now if room_now != "" else "Corridor"
	var c := world_to_cell(body.global_position)
	if shell and dir.length() < 0.1: body.rotation.y = lerp_angle(body.rotation.y, yaw, clampf(dt * 10.0, 0.0, 1.0))
	dot.position = Vector2(c.x / float(data["w"]) * minimap.size.x, c.y / float(data["h"]) * minimap.size.y) - dot.size * 0.5

## The labelled room under a point ("" = corridor or open deck).
func room_at(p: Vector3) -> String:
	var c := world_to_cell(p)
	if level != 0:   # the other decks: the room whose centre you are near (its rough size comes with the layout)
		var best := ""
		var best_k := 1.0
		for r in deck_of(level).get("rooms", []):   # the room you are deepest inside (rooms nest, so their rough circles overlap)
			var kk := c.distance_to(Vector2(float(r["at"][0]), float(r["at"][1]))) / maxf(1.0, float(r.get("rad", 8.0)))
			if kk <= best_k:
				best_k = kk
				best = str(r["name"])
		return best
	var x := int(c.x); var y := int(c.y); var w := int(data["w"])
	if x < 0 or y < 0 or x >= w or y >= int(data["h"]): return ""
	var rid := _room_grid[y * w + x]
	return str(rooms_by_id[rid]["name"]) if rooms_by_id.has(rid) else ""

## Where a room's label sits (tests and a later GO TO).
func room_point(nm: String) -> Vector3:
	for r in data["rooms"]:
		if str(r["name"]) == nm: return cell_to_world(float(r["at"][0]), float(r["at"][1]))
	return Vector3.INF

# ---------------------------------------------------------------------------------------------------------------------
## v13.00 (owner: "the gameplay should never really be a top-down Zelda, that's more for the map ... when you start
## grayboxing it needs to match those shapes"): a deck with traced outlines ("shell" in its json, tools/holodeck/shell.py)
## is walked in 3D from over the shoulder, like the station escape. The walls follow the plan's own lines (slants and
## curves, not 0.6 m steps), under a ceiling; the plan stays as the GPS map. Drawn equipment inside a room is low cover.
func _wall_mat(col: Color) -> StandardMaterial3D:
	var m := _grey(col)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
func _glow(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _band(st: SurfaceTool, a: Vector3, b: Vector3, n: Vector3, y0: float, y1: float, off: float) -> void:
	var o := n * off
	var p0 := a + o + Vector3(0, y0, 0); var p1 := b + o + Vector3(0, y0, 0)
	var p2 := b + o + Vector3(0, y1, 0); var p3 := a + o + Vector3(0, y1, 0)
	for v in [p0, p1, p2, p0, p2, p3]:
		st.set_normal(n)
		st.add_vertex(v)

func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	for v in [p0, p1, p2, p0, p2, p3]:
		st.set_normal(n)
		st.add_vertex(v)

func _outline(poly: Array) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in range(0, poly.size(), 2): pts.append(cell_to_world(float(poly[i]), float(poly[i + 1])))
	return pts

func _shell_deck(sh: Dictionary, y0: float, tag: String) -> void:
	var lift := Vector3(0, y0, 0)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)       # walls
	var lo := SurfaceTool.new(); lo.begin(Mesh.PRIMITIVE_TRIANGLES)       # cyan line at the foot (the plan's line colour)
	var hi := SurfaceTool.new(); hi.begin(Mesh.PRIMITIVE_TRIANGLES)       # light strip under the ceiling
	var cv := SurfaceTool.new(); cv.begin(Mesh.PRIMITIVE_TRIANGLES)       # cover
	var chm := SurfaceTool.new(); chm.begin(Mesh.PRIMITIVE_TRIANGLES)     # the slanted corner panels (looks only: the wall behind is what stops you)
	var faces := PackedVector3Array()
	for kind in ["walls", "cover"]:
		var top: float = wall_h if kind == "walls" else 1.15
		for poly in sh[kind]:
			var pts := _outline(poly)
			for pi in pts.size(): pts[pi] += lift
			var n := pts.size()
			for i in n:
				var a := pts[i]; var b := pts[(i + 1) % n]
				var e := b - a
				if e.length() < 0.01: continue
				var nrm := Vector3(e.z, 0, -e.x).normalized()   # the walkable side (shell.py keeps it on the left)
				_band(st if kind == "walls" else cv, a, b, nrm, 0.0, top, 0.0)
				var slant: bool = kind == "walls" and e.length() >= 2.2   # (short pieces are door jambs and nibs: left square so doorways stay full width)
				_band(lo, a, b, nrm, 0.0, 0.1, (CHAMFER_LO + 0.02) if slant else 0.02)
				if slant:
					var upv := Vector3.UP
					_quad(chm, a + nrm * CHAMFER_LO, b + nrm * CHAMFER_LO, b + upv * CHAMFER_LO, a + upv * CHAMFER_LO, (nrm + upv).normalized())
					_quad(chm, a + upv * (top - CHAMFER_HI), b + upv * (top - CHAMFER_HI), b + nrm * CHAMFER_HI + upv * top, a + nrm * CHAMFER_HI + upv * top, (nrm - upv).normalized())
				if kind == "walls":
					var hy: float = top - (CHAMFER_HI + 0.2 if slant else 0.55)
					_band(hi, a, b, nrm, hy, hy + 0.08, 0.02)
					_band(lo, a, b, nrm, STOREY - 0.06, STOREY + 0.06, 0.02)   # the line between the two storeys
				var up := Vector3(0, top, 0)
				faces.append_array([a, b, b + up, a, b + up, a + up])
			if kind == "cover":   # a lid on each piece of cover
				var p2 := PackedVector2Array()
				for p in pts: p2.append(Vector2(p.x, p.z))
				var tri := Geometry2D.triangulate_polygon(p2)
				for t in tri:
					cv.set_normal(Vector3.UP)
					cv.add_vertex(Vector3(p2[t].x, y0 + top, p2[t].y))
				for t in range(0, tri.size(), 3):
					faces.append_array([Vector3(p2[tri[t]].x, y0 + top, p2[tri[t]].y), Vector3(p2[tri[t + 1]].x, y0 + top, p2[tri[t + 1]].y), Vector3(p2[tri[t + 2]].x, y0 + top, p2[tri[t + 2]].y)])
	for pair in [[st, "ShellWalls", _wall_mat(Color(0.6, 0.68, 0.8))], [cv, "Cover", _wall_mat(Color(0.42, 0.47, 0.56))], [chm, "Chamfers", _wall_mat(Color(0.47, 0.54, 0.66))],
			[lo, "WallTrim", _glow(Color(0.25, 0.8, 0.95))], [hi, "LightStrip", _glow(Color(0.75, 0.95, 1.0))]]:
		var made: ArrayMesh = (pair[0] as SurfaceTool).commit()
		if made == null or made.get_surface_count() == 0: continue   # (a deck with no cover)
		var mi := MeshInstance3D.new()
		mi.name = str(pair[1]) + tag
		mi.mesh = made
		mi.material_override = pair[2]
		world.add_child(mi)
	var sb := StaticBody3D.new()
	sb.name = "Walls" + tag
	var cs := CollisionShape3D.new()
	var shp := ConcavePolygonShape3D.new()
	shp.backface_collision = true
	shp.set_faces(faces)
	cs.shape = shp
	sb.add_child(cs)
	world.add_child(sb)
	# the ceiling (you are inside now)
	var sz := Vector2(float(data["w"]), float(data["h"])) * mpc
	var ce := MeshInstance3D.new()
	ce.name = "Ceiling" + tag
	var bm := BoxMesh.new()
	bm.size = Vector3(sz.x, 0.2, sz.y)
	ce.mesh = bm
	ce.position.y = y0 + wall_h + 0.1
	ce.material_override = _grey(Color(0.3, 0.34, 0.42))
	world.add_child(ce)
	if tag == "":
		(world.get_node("Floor") as MeshInstance3D).material_override = _grey(Color(0.42, 0.47, 0.56))
		# the pilot: the owner's own model in place of the stand-in
		if ResourceLoader.exists(PILOT_GLB): call_deferred("_shell_pilot")
	else:   # another deck: its own floor (the main deck's floor is made in _floor_ceiling)
		var fl := MeshInstance3D.new()
		fl.name = "Floor" + tag
		var fm := BoxMesh.new()
		fm.size = Vector3(sz.x, 0.4, sz.y)
		fl.mesh = fm
		fl.position.y = y0 - 0.2
		fl.material_override = _grey(Color(0.42, 0.47, 0.56))
		world.add_child(fl)
		var fb := StaticBody3D.new()
		fb.name = "FloorBody" + tag
		var fcs := CollisionShape3D.new()
		var fbs := BoxShape3D.new()
		fbs.size = fm.size
		fcs.shape = fbs
		fcs.position.y = y0 - 0.2
		fb.add_child(fcs)
		world.add_child(fb)

func _shell_pilot() -> void:
	if not is_instance_valid(body): return
	var inst: Node3D = (load(PILOT_GLB) as PackedScene).instantiate()
	var bb := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a := mi.get_aabb()
		var x := mi.transform
		var par := mi.get_parent()
		while par != null and par != inst and par is Node3D:
			x = (par as Node3D).transform * x
			par = par.get_parent()
		a = x * a
		bb = a if first else bb.merge(a)
		first = false
	if first: return
	var k := 1.8 / maxf(0.01, bb.size.y)
	inst.scale = Vector3.ONE * k
	inst.rotation.y = PI / 2 if bb.size.z > bb.size.x * 1.3 else PI   # (faces away from the camera, as on the station escape)
	inst.position = Vector3(0, -bb.position.y * k, 0)
	body.add_child(inst)
	for c in body.get_children():
		if c is MeshInstance3D: (c as MeshInstance3D).visible = false

func _cam_shoulder() -> void:
	var pivot := body.global_position + Vector3(0, 1.55, 0)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var want := pivot + b * SHOULDER
	var q := PhysicsRayQueryParameters3D.create(pivot, want)   # never through a wall: pull the camera in
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty(): want = pivot + (hit["position"] - pivot) * 0.86
	cam.global_position = want
	cam.global_transform.basis = b

func look(d: Vector2) -> void:
	yaw -= d.x * 0.006
	pitch = clampf(pitch - d.y * 0.005, -0.9, 0.7)

func _shell_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch or ev is InputEventMouseButton:
		var pressed: bool = ev.pressed
		var idx: int = ev.index if ev is InputEventScreenTouch else 0
		var left: bool = ev.position.x < size.x * 0.5
		if pressed:
			if left and _stick_id == -1: _stick_id = idx; _stick_from = ev.position
			elif not left and _look_id == -1: _look_id = idx; _look_last = ev.position
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

# ---------------------------------------------------------------------------------------------------------------------
## v13.00 (owner: "two more ship levels, top level and lower level, different rooms and smaller ... put in the elevator
## system ... only two or four for the ships"): a deck json may carry "decks" (tools/holodeck/decks_<ship>.py): more
## decks stacked above (level +1) and below (level -1) the plan's main deck, each with its own outlines, rooms and map.
## The plan's lift squares are the shafts: a lift stops at every deck that has a lift at that same spot. Stand on a
## lift pad and the UP / DOWN buttons appear. Decks with no blueprint are marked PROPOSED on screen and on their map.
func deck_of(lv: int) -> Dictionary:
	for dk in decks:
		if int(dk["level"]) == lv: return dk
	return {}

func _more_decks() -> void:
	if not data.has("decks"): return
	decks = [{"id": "main", "level": 0, "name": "MAIN DECK", "proposed": false, "rooms": data["rooms"], "lifts": data.get("lifts", []),
		"map": str(entry["holodeck_res"])}]
	for dk in data["decks"]:
		var e: Dictionary = (dk as Dictionary).duplicate()
		e["map"] = FleetCatalog.HOLODECK_DIR + str(dk["map"])
		decks.append(e)
		var y0 := float(int(dk["level"])) * DECK_GAP
		_shell_deck(dk["shell"], y0, "_" + str(dk["id"]))
		for r in dk["rooms"]:
			var rn := Node3D.new()
			rn.name = "Room_%s_%s" % [str(dk["id"]), str(r["name"]).validate_node_name().replace(" ", "_")]
			rn.set_meta("room", r["name"])
			rn.position = cell_to_world(float(r["at"][0]), float(r["at"][1])) + Vector3(0, y0, 0)
			world.add_child(rn)
			var lb := Label3D.new()
			lb.text = str(r["name"]).to_upper()
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.font_size = 48
			lb.outline_size = 10
			lb.pixel_size = 0.005
			lb.modulate = Color(0.85, 1.0, 1.0)
			lb.position.y = 3.1
			rn.add_child(lb)
	var pad_mat := _glow(Color(0.3, 0.95, 1.0))
	for dk in decks:
		var i := 0
		for l in dk["lifts"]:
			i += 1
			var pos := cell_to_world(float(l[0]), float(l[1])) + Vector3(0, float(int(dk["level"])) * DECK_GAP, 0)
			lift_pads.append({"pos": pos, "level": int(dk["level"]), "cell": Vector2(float(l[0]), float(l[1]))})
			var pad := MeshInstance3D.new()   # the pad you stand on (a flat ring of light, graybox)
			pad.name = "LiftPad_%s_%d" % [str(dk["id"]), i]
			var tm := TorusMesh.new()
			tm.inner_radius = 0.95
			tm.outer_radius = 1.15
			tm.rings = 24
			tm.ring_segments = 6
			pad.mesh = tm
			pad.scale.y = 0.15
			pad.material_override = pad_mat
			pad.position = pos + Vector3(0, 0.03, 0)
			world.add_child(pad)
			if int(dk["level"]) != 0:
				var lb2 := Label3D.new()
				lb2.text = "LIFT"
				lb2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lb2.font_size = 28
				lb2.pixel_size = 0.008
				lb2.position = pos + Vector3(0, 2.1, 0)
				world.add_child(lb2)

## The decks a lift at this spot can take you to from this level: {+1: pad, -1: pad}.
func lift_stops(pad: Dictionary) -> Dictionary:
	var out := {}
	for p in lift_pads:
		if absi(int(p["level"]) - int(pad["level"])) == 1 and (p["cell"] as Vector2).distance_to(pad["cell"]) < 1.5:
			out[int(p["level"]) - int(pad["level"])] = p
	return out

func _lift_ui() -> void:
	_lift_box = HBoxContainer.new()
	_lift_box.name = "LiftButtons"
	_lift_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_lift_box.position = Vector2(-230, -150)
	_lift_box.custom_minimum_size = Vector2(460, 64)
	_lift_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lift_box.add_theme_constant_override("separation", 18)
	_lift_box.visible = false
	add_child(_lift_box)
	for dir in [1, -1]:
		var b := Button.new()
		b.name = "Up" if dir == 1 else "Down"
		b.custom_minimum_size = Vector2(220, 64)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(ride.bind(dir))
		_lift_box.add_child(b)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

## Take the lift you are standing on one deck up (+1) or down (-1). False when it does not go that way.
func ride(dir: int) -> bool:
	if at_lift.is_empty(): return false
	var stops := lift_stops(at_lift)
	if not stops.has(dir): return false
	var to: Dictionary = stops[dir]
	body.global_position = (to["pos"] as Vector3) + Vector3(0, 0.1, 0)
	body.velocity = Vector3.ZERO
	if is_instance_valid(_fade):
		_fade.color = Color(0, 0, 0, 1)
		create_tween().tween_property(_fade, "color", Color(0, 0, 0, 0), 0.45)
	_deck_tick()
	return true

func _deck_tick() -> void:
	var lv := int(round(body.global_position.y / DECK_GAP))
	if lv != level or _top.get_meta("lv", 99) != lv:
		level = lv
		_top.set_meta("lv", lv)
		_show_level(lv)
		var dk := deck_of(lv)
		_top.text = "%s  ·  %s  ·  graybox%s" % [str(entry["name"]).to_upper(), str(dk.get("name", "DECK")), "  ·  PROPOSED LAYOUT (no blueprint yet)" if bool(dk.get("proposed", false)) else "  ·  PROTOTYPE"]
		var mp := str(dk.get("map", ""))
		if mp != "" and ResourceLoader.exists(mp):
			if not _maps.has(mp): _maps[mp] = load(mp)
			minimap.texture = _maps[mp]
	at_lift = {}
	for p in lift_pads:
		if int(p["level"]) == level and (p["pos"] as Vector3).distance_to(body.global_position) < 1.7: at_lift = p
	if at_lift.is_empty():
		_lift_box.visible = false
		return
	var stops := lift_stops(at_lift)
	_lift_box.visible = not stops.is_empty()
	for dir in [1, -1]:
		var b: Button = _lift_box.get_node("Up" if dir == 1 else "Down")
		b.visible = stops.has(dir)
		if stops.has(dir): b.text = ("▲  " if dir == 1 else "▼  ") + str(deck_of(level + dir).get("name", "DECK"))

# ---------------------------------------------------------------------------------------------------------------------
## v13.00 (owner: "the doorway should be a little bit bigger ... certain doors should be coloured yellow, orange and
## red, three different access levels, green is always open ... find those guards with those keys"; "make it work like
## how it opens up"): every doorway of a shell deck is a sliding door. Two leaves part into the walls as you walk up.
## Green opens for anyone; yellow / orange / red stay shut until you carry that key. Each key is on a guard somewhere
## your current access can reach. Which doors are locked and where the guards stand is PROPOSED gameplay
## (tools/holodeck/decks_<ship>.py), not something the blueprint shows.
## The leaves are graybox stand-ins shaped to take the owner's door models later (one closed model per leaf pair).
const KEY_COL := [Color(0.25, 1.0, 0.4), Color(1.0, 0.9, 0.15), Color(1.0, 0.55, 0.1), Color(1.0, 0.2, 0.2)]
const KEY_NAME := ["GREEN", "YELLOW", "ORANGE", "RED"]
const DOOR_H := 3.6
const DOOR_PAD := 0.45    # the leaves reach this far into the wall each side (no gap round a shut door)

func _gates(sh: Dictionary, y0: float) -> void:
	var leaf_mat := _grey(Color(0.26, 0.3, 0.38))   # (darker than the walls, so a shut door reads as a door)
	var head_mat := _grey(Color(0.36, 0.4, 0.48))
	for dr in sh.get("doors", []):
		var r: Array = dr["rect"]
		var lv := int(dr["level"])
		var along_y: bool = str(dr.get("ax", "y")) == "y"    # you walk bow-stern through it: the leaves slide port-starboard
		var turned: bool = dr.has("rot")                      # a door on a slanted wall (the wedge rooms): built square, then turned
		if turned: along_y = true
		var c := cell_to_world((float(r[0]) + float(r[2])) * 0.5, (float(r[1]) + float(r[3])) * 0.5) + Vector3(0, y0, 0)
		var wide := (float(r[2]) - float(r[0]) if along_y else float(r[3]) - float(r[1])) * mpc + DOOR_PAD * 2.0
		if turned: wide = float(dr["w"]) * mpc + DOOR_PAD * 2.0
		var slide := Vector3(1, 0, 0) if along_y else Vector3(0, 0, 1)
		var g := Node3D.new()
		g.name = "Gate_%d" % gates.size()
		g.position = c
		g.set_meta("level", lv)
		if turned: g.rotation.y = deg_to_rad(float(dr["rot"]))
		world.add_child(g)
		var leaves := []
		for sgn in [-1.0, 1.0]:
			var leaf := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = (Vector3(wide * 0.5, DOOR_H, 0.35) if along_y else Vector3(0.35, DOOR_H, wide * 0.5))
			leaf.mesh = bm
			leaf.material_override = leaf_mat
			leaf.position = slide * (sgn * wide * 0.25) + Vector3(0, DOOR_H * 0.5, 0)
			g.add_child(leaf)
			var stripe := MeshInstance3D.new()   # the access colour, across each leaf on both faces
			var sm := BoxMesh.new()
			sm.size = (Vector3(wide * 0.5 - 0.3, 1.0, 0.39) if along_y else Vector3(0.39, 1.0, wide * 0.5 - 0.3))
			stripe.mesh = sm
			stripe.material_override = _glow(KEY_COL[lv])
			stripe.position.y = -0.35
			leaf.add_child(stripe)
			leaves.append(leaf)
		var head := MeshInstance3D.new()        # the wall above the door, up to the ceiling
		var hm := BoxMesh.new()
		hm.size = (Vector3(wide, wall_h - DOOR_H, 0.6) if along_y else Vector3(0.6, wall_h - DOOR_H, wide))
		head.mesh = hm
		head.material_override = head_mat
		head.position.y = DOOR_H + (wall_h - DOOR_H) * 0.5
		g.add_child(head)
		var lamp := MeshInstance3D.new()        # and the access light over it
		var lm := BoxMesh.new()
		lm.size = (Vector3(wide * 0.6, 0.18, 0.66) if along_y else Vector3(0.66, 0.18, wide * 0.6))
		lamp.mesh = lm
		lamp.material_override = _glow(KEY_COL[lv])
		lamp.position.y = DOOR_H + 0.25
		g.add_child(lamp)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		# shut, the whole doorway is blocked (its full footprint plus the pad), whichever way the leaves face
		bs.size = Vector3((float(r[2]) - float(r[0])) * mpc + DOOR_PAD * 2.0, DOOR_H, (float(r[3]) - float(r[1])) * mpc + DOOR_PAD * 2.0)
		if turned: bs.size = Vector3(wide, DOOR_H, float(dr["l"]) * mpc + DOOR_PAD * 2.0)
		cs.shape = bs
		cs.position.y = DOOR_H * 0.5
		sb.add_child(cs)
		g.add_child(sb)
		gates.append({"node": g, "pos": c, "level": lv, "open": false, "a": leaves[0], "b": leaves[1], "shape": cs,
			"slide": slide, "wide": wide, "k": 0.0})

func _key_guards() -> void:
	for kg in data.get("key_guards", []):
		var lv := int(kg["key"])
		var dlevel := 0
		for dk in data.get("decks", []):
			if str(dk["id"]) == str(kg["deck"]): dlevel = int(dk["level"])
		var n := Node3D.new()
		n.name = "KeyGuard_%s" % KEY_NAME[lv].to_lower()
		n.position = cell_to_world(float(kg["at"][0]), float(kg["at"][1])) + Vector3(0, float(dlevel) * DECK_GAP, 0)
		world.add_child(n)
		var fig := MeshInstance3D.new()   # a stand-in guard (graybox) until the owner's guard models are plugged in
		var cm := CapsuleMesh.new()
		cm.radius = 0.38
		cm.height = 1.85
		fig.mesh = cm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.25, 0.27, 0.32)
		fig.material_override = fm
		fig.position.y = 0.93
		n.add_child(fig)
		var card := MeshInstance3D.new()  # the key card he carries, in its colour
		var cb := BoxMesh.new()
		cb.size = Vector3(0.34, 0.22, 0.04)
		card.mesh = cb
		card.material_override = _glow(KEY_COL[lv])
		card.position = Vector3(0, 2.25, 0)
		n.add_child(card)
		var lb := Label3D.new()
		lb.text = "GUARD  ·  %s KEY" % KEY_NAME[lv]
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font_size = 40
		lb.pixel_size = 0.005
		lb.outline_size = 8
		lb.modulate = KEY_COL[lv]
		lb.position.y = 2.6
		n.add_child(lb)
		fig.name = "StandIn"
		key_guards.append({"node": n, "pos": n.position, "key": lv, "room": str(kg["room"]), "dressed": false, "asked": false})

func _key_ui() -> void:
	var row := HBoxContainer.new()
	row.name = "Keys"
	row.position = Vector2(20, 88)
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for lv in [1, 2, 3]:
		var chip := Label.new()
		chip.text = " %s KEY " % KEY_NAME[lv]
		chip.add_theme_font_size_override("font_size", 15)
		var sbx := StyleBoxFlat.new()
		sbx.bg_color = Color(0.1, 0.12, 0.16, 0.8)
		sbx.border_color = KEY_COL[lv]
		sbx.set_border_width_all(2)
		sbx.set_corner_radius_all(5)
		chip.add_theme_stylebox_override("normal", sbx)
		row.add_child(chip)
		_chips.append(chip)
	_msg = Label.new()
	_msg.name = "DoorMsg"
	_msg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_msg.position = Vector2(-300, 150)
	_msg.custom_minimum_size = Vector2(600, 0)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.add_theme_font_size_override("font_size", 24)
	_msg.add_theme_constant_override("outline_size", 8)
	_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_child(_msg)
	_chip_show()

func _chip_show() -> void:
	for i in _chips.size():
		var lv := i + 1
		var chip: Label = _chips[i]
		chip.add_theme_color_override("font_color", KEY_COL[lv] if keys[lv] else Color(0.45, 0.47, 0.52))
		(chip.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = Color(KEY_COL[lv].r, KEY_COL[lv].g, KEY_COL[lv].b, 0.28) if keys[lv] else Color(0.1, 0.12, 0.16, 0.8)

func say(t: String, col: Color) -> void:
	if not is_instance_valid(_msg): return
	_msg.text = t
	_msg.add_theme_color_override("font_color", col)
	_msg_t = 2.2

## Hand yourself a key (a guard's, or a test).
func give_key(lv: int) -> void:
	keys[lv] = true
	_chip_show()
	say("%s KEY TAKEN  ·  %s doors now open for you" % [KEY_NAME[lv], KEY_NAME[lv].to_lower()], KEY_COL[lv])

func _gate_tick(dt: float) -> void:
	var me := body.global_position
	if _msg_t > 0.0:
		_msg_t -= dt
		if _msg_t <= 0.0: _msg.text = ""
	for g in gates:
		var d := Vector2(me.x - (g["pos"] as Vector3).x, me.z - (g["pos"] as Vector3).z).length()
		var same := absf(me.y - (g["pos"] as Vector3).y) < 3.0
		var reach: float = float(g["wide"]) * 0.5 + 3.2
		var want: bool = same and d < reach and keys[int(g["level"])]
		if same and d < reach - 0.3 and not keys[int(g["level"])] and _msg_t <= 0.0:
			say("%s KEY NEEDED  ·  a guard on this ship carries it" % KEY_NAME[int(g["level"])], KEY_COL[int(g["level"])])
		if want != bool(g["open"]):
			g["open"] = want
			(g["shape"] as CollisionShape3D).disabled = want
		var k: float = move_toward(float(g["k"]), 1.0 if want else 0.0, dt * 3.2)
		if k != float(g["k"]):
			g["k"] = k
			var w: float = float(g["wide"])
			var off: Vector3 = (g["slide"] as Vector3) * (w * 0.25 + k * w * 0.5)
			(g["a"] as Node3D).position = -off + Vector3(0, DOOR_H * 0.5, 0)
			(g["b"] as Node3D).position = off + Vector3(0, DOOR_H * 0.5, 0)
	for kg in key_guards:
		if not is_instance_valid(kg["node"]): continue
		if not bool(kg["dressed"]): _dress_guard(kg)
		if (kg["pos"] as Vector3).distance_to(me) < 1.5:
			give_key(int(kg["key"]))
			(kg["node"] as Node3D).queue_free()

## v13.00 (owner: "I had given you a lot of GLB characters to use, we can use that versus your shape character"):
## the key guards wear the game's own rigged guard model (the station escape's, assets/crowd3d) in place of the grey
## stand-in. It loads with its pack; until then (or if the pack is missing) the stand-in shows.
const GUARD_GLB := "res://assets/crowd3d/future_soldier.glb"
const GUARD_PACK := "crowd3d"
func _dress_guard(kg: Dictionary) -> void:
	if not Packs.is_ready(GUARD_PACK):
		if not bool(kg["asked"]):
			kg["asked"] = true
			Packs.request(GUARD_PACK)
		return
	kg["dressed"] = true
	if not ResourceLoader.exists(GUARD_GLB): return
	var inst: Node3D = (load(GUARD_GLB) as PackedScene).instantiate()
	var bb := _model_box(inst)
	if bb.size.y < 0.01: return
	var k := 1.85 / bb.size.y
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
	var holder := Node3D.new()
	holder.name = "Model"
	(kg["node"] as Node3D).add_child(holder)
	holder.add_child(inst)
	var gray := (kg["node"] as Node3D).get_node_or_null("StandIn")
	if gray: (gray as Node3D).visible = false
	for ap in inst.find_children("*", "AnimationPlayer", true, false):   # his own idle clip, if the model has one
		var pl := ap as AnimationPlayer
		for a in pl.get_animation_list():
			if str(a).to_lower().ends_with("idle"):
				pl.get_animation(a).loop_mode = Animation.LOOP_LINEAR
				pl.play(a)
				break
		break

## The box round every mesh of a model, in the model's own space.
func _model_box(inst: Node3D) -> AABB:
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
	return bb

# ---------------------------------------------------------------------------------------------------------------------
## v13.00 (owner: "these are like the mini spaceship dungeons ... you gotta go and get the key ... you might pass one
## door in the beginning just to realize that you gotta come back to that door ... there's 3 types of missions"):
##   SABOTAGE  blow the generator: a countdown starts, get back to your ship in the hangar before it hits zero
##   CAPTURE   take the captain (high in the ship, behind red), then get him back to the hangar
##   RESCUE    free the hostage from the brig (behind red), then get them back to the hangar
## The targets and the key each needs come with the deck data ("objectives", tools/holodeck/decks.py: PROPOSED).
## The waypoint always points at the next thing to do: the guard carrying the next key you are missing, then the
## target, then the hangar. Fights are not in yet (the owner: "plug in the gameplay at the end"): reaching a guard
## takes his key, reaching the target does the deed.
const MISSION_TITLE := {"sabotage": "SABOTAGE  ·  blow the generator", "capture": "CAPTURE  ·  take the captain", "rescue": "RESCUE  ·  free the hostage"}
const MISSION_DONE := {"sabotage": "CHARGE SET", "capture": "CAPTAIN CAPTURED", "rescue": "HOSTAGE FREED"}
const MISSION_THING := {"sabotage": "GENERATOR", "capture": "CAPTAIN", "rescue": "HOSTAGE"}
const SABOTAGE_SECONDS := 150.0

func deck_y(deck_id: String) -> float:
	for dk in data.get("decks", []):
		if str(dk["id"]) == deck_id: return float(int(dk["level"])) * DECK_GAP
	return 0.0
func deck_title(y: float) -> String:
	return str(deck_of(int(round(y / DECK_GAP))).get("name", "MAIN DECK"))
func objective_pos(kind: String) -> Vector3:
	var o: Dictionary = data["objectives"][kind]
	return cell_to_world(float(o["at"][0]), float(o["at"][1])) + Vector3(0, deck_y(str(o["deck"])), 0)
func hangar_pos() -> Vector3:
	return cell_to_world(float(data["start"][0]), float(data["start"][1]))

func _mission_ui() -> void:
	_obj_label = Label.new()
	_obj_label.name = "Objective"
	_obj_label.position = Vector2(20, 122)
	_obj_label.add_theme_font_size_override("font_size", 18)
	_obj_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_obj_label.add_theme_constant_override("outline_size", 6)
	_obj_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_child(_obj_label)
	_timer_label = Label.new()
	_timer_label.name = "Countdown"
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.position = Vector2(-80, 96)
	_timer_label.custom_minimum_size = Vector2(160, 0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 40)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	_timer_label.add_theme_constant_override("outline_size", 10)
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_child(_timer_label)
	_wp_dot = ColorRect.new()
	_wp_dot.color = Color(1.0, 0.9, 0.2)
	_wp_dot.size = Vector2(11, 11)
	_wp_dot.rotation = PI / 4
	_wp_dot.visible = false
	minimap.add_child(_wp_dot)
	_beacon = MeshInstance3D.new()          # a column of light at the waypoint, seen down a corridor
	_beacon.name = "Waypoint"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.35, 7.0, 0.35)
	_beacon.mesh = bm
	var mat := _glow(Color(1.0, 0.9, 0.2, 0.55))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beacon.material_override = mat
	_beacon.visible = false
	world.add_child(_beacon)
	# the mission picker
	_pick = PanelContainer.new()
	_pick.name = "MissionPick"
	_pick.set_anchors_preset(Control.PRESET_CENTER)
	_pick.position = Vector2(-250, -150)
	_pick.custom_minimum_size = Vector2(500, 0)
	add_child(_pick)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_pick.add_child(vb)
	var t := Label.new()
	t.text = "BOARDING  ·  choose the mission"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 22)
	vb.add_child(t)
	for kind in ["sabotage", "capture", "rescue"]:
		if not (data["objectives"] as Dictionary).has(kind): continue
		var o: Dictionary = data["objectives"][kind]
		var b := Button.new()
		b.name = "Pick_" + kind
		b.text = "%s\n%s  ·  %s  ·  %s key" % [MISSION_TITLE[kind], str(o["room"]), deck_title(deck_y(str(o["deck"]))), KEY_NAME[int(o["need"])]]
		b.custom_minimum_size = Vector2(0, 66)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(start_mission.bind(kind))
		vb.add_child(b)
	var ex := Button.new()
	ex.name = "Pick_none"
	ex.text = "JUST LOOK ROUND"
	ex.custom_minimum_size = Vector2(0, 46)
	ex.pressed.connect(func(): _pick.visible = false)
	vb.add_child(ex)

func start_mission(kind: String) -> bool:
	if not (data.get("objectives", {}) as Dictionary).has(kind): return false
	mission = kind
	m_stage = 0
	m_timer = 0.0
	if is_instance_valid(_pick): _pick.visible = false
	if is_instance_valid(_target_node): _target_node.queue_free()
	_target_node = Node3D.new()             # the thing itself, a graybox stand-in with its name over it
	_target_node.name = "MissionTarget"
	_target_node.position = objective_pos(kind)
	world.add_child(_target_node)
	var fig := MeshInstance3D.new()
	if kind == "sabotage":
		var gm := CylinderMesh.new()
		gm.top_radius = 0.7
		gm.bottom_radius = 0.9
		gm.height = 2.2
		gm.radial_segments = 8
		fig.mesh = gm
		fig.position.y = 1.1
		fig.material_override = _glow(Color(0.4, 0.9, 1.0))
	else:
		var cm := CapsuleMesh.new()
		cm.radius = 0.36
		cm.height = 1.8
		fig.mesh = cm
		fig.position.y = 0.9
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.85, 0.75, 0.3) if kind == "capture" else Color(0.5, 0.8, 0.55)
		fig.material_override = fm
	_target_node.add_child(fig)
	var lb := Label3D.new()
	lb.text = MISSION_THING[kind]
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font_size = 44
	lb.pixel_size = 0.005
	lb.outline_size = 8
	lb.modulate = Color(1.0, 0.9, 0.3)
	lb.position.y = 2.7
	_target_node.add_child(lb)
	_mission_tick(0.0)
	return true

## The next thing to do, as a place and a line of text.
func _next_step() -> void:
	var o: Dictionary = data["objectives"][mission]
	if m_stage == 1:
		waypoint = hangar_pos()
		waypoint_text = "Get back to YOUR SHIP in the hangar  ·  MAIN DECK"
		return
	if m_stage != 0:
		waypoint = Vector3.INF
		return
	for lv in range(1, int(o["need"]) + 1):     # the lowest key you still need that a guard carries
		if keys[lv]: continue
		for kg in key_guards:
			if int(kg["key"]) == lv and is_instance_valid(kg["node"]):
				waypoint = kg["pos"]
				waypoint_text = "Take the %s KEY from the guard  ·  %s  ·  %s" % [KEY_NAME[lv], str(kg["room"]), deck_title((kg["pos"] as Vector3).y)]
				return
	waypoint = objective_pos(mission)
	waypoint_text = "%s  ·  %s  ·  %s" % [MISSION_THING[mission], str(o["room"]), deck_title(waypoint.y)]

func _mission_tick(dt: float) -> void:
	var me := body.global_position
	if m_stage == 0 and me.distance_to(objective_pos(mission)) < 2.2:
		m_stage = 1
		if mission == "sabotage": m_timer = SABOTAGE_SECONDS
		if is_instance_valid(_target_node) and mission != "sabotage": _target_node.visible = false   # (they come with you)
		say("%s  ·  now get back to the hangar" % MISSION_DONE[mission], Color(1.0, 0.9, 0.3))
	elif m_stage == 1 and absf(me.y) < 2.0 and Vector2(me.x - hangar_pos().x, me.z - hangar_pos().z).length() < 3.5:
		m_stage = 2
		m_timer = 0.0
		say("MISSION COMPLETE  ·  LEAVE SHIP to launch", Color(0.4, 1.0, 0.5))
	if m_stage == 1 and mission == "sabotage":
		m_timer -= dt
		if m_timer <= 0.0:
			m_stage = -1
			say("THE SHIP WENT UP WITH YOU ABOARD  ·  mission failed, starting again", Color(1.0, 0.3, 0.25))
			restart_mission()
			return
	_next_step()
	_timer_label.text = ("%d:%02d" % [int(m_timer) / 60, int(m_timer) % 60]) if (m_stage == 1 and mission == "sabotage") else ""
	var line: String = str(MISSION_TITLE[mission]) + "\n"
	if m_stage == 2: line += "DONE  ·  LEAVE SHIP"
	else:
		line += "NEXT: " + waypoint_text
		if waypoint != Vector3.INF and absf(waypoint.y - me.y) > 3.0: line += "   (take a lift %s)" % ("▲" if waypoint.y > me.y else "▼")
	_obj_label.text = line
	var here: bool = waypoint != Vector3.INF and absf(waypoint.y - me.y) <= 3.0
	_wp_dot.visible = here
	_beacon.visible = here
	if here:
		var c := world_to_cell(waypoint)
		_wp_dot.position = Vector2(c.x / float(data["w"]) * minimap.size.x, c.y / float(data["h"]) * minimap.size.y) - Vector2(0, 7)
		_beacon.position = waypoint + Vector3(0, 3.5, 0)

## The mission from the top (you failed it): back in the hangar, no keys, the guards back at their posts.
func restart_mission() -> void:
	var kind := mission
	body.global_position = hangar_pos() + Vector3(0, 0.1, 0)
	body.velocity = Vector3.ZERO
	keys = [true, false, false, false]
	_chip_show()
	for kg in key_guards:
		if is_instance_valid(kg["node"]): (kg["node"] as Node3D).queue_free()
	key_guards.clear()
	_key_guards()
	start_mission(kind)

# ---------------------------------------------------------------------------------------------------------------------
## v13.78 (owner: boarding is black on the phone): a deck held ~2,000 separate pieces (room patches, door frames,
## lights, door leaves) and WebGL draws NOTHING past about 1,000 (the breakout's v12.44 bug). Every piece that never
## moves is merged into one mesh per material per deck; each door leaf carries its key stripe in the same mesh; and
## only the deck you stand on is drawn.
var merged_pieces := 0
var _by_level := {}     # level -> [nodes drawn only on that deck]
func _xf_to_world(n: Node3D) -> Transform3D:
	var x := n.transform
	var p := n.get_parent()
	while p != null and p != world and p is Node3D:
		x = (p as Node3D).transform * x
		p = p.get_parent()
	return x

func _mat_key(m: Material) -> String:
	if not (m is StandardMaterial3D): return str(m.get_instance_id())
	var sm := m as StandardMaterial3D
	return "%s|%d|%d|%d|%s|%s" % [sm.albedo_color.to_html(), sm.shading_mode, sm.transparency, sm.cull_mode, str(sm.albedo_texture != null), str(sm.uv1_scale)]

func _web_safe() -> void:
	var keep := {}
	var skip_roots: Array = [body]
	for kg in key_guards: skip_roots.append(kg["node"])
	if is_instance_valid(_beacon): skip_roots.append(_beacon)
	if is_instance_valid(_target_node): skip_roots.append(_target_node)
	for r in skip_roots:
		if not is_instance_valid(r): continue
		keep[r] = true
		for c in (r as Node).find_children("*", "", true, false): keep[c] = true
	for g in gates:   # the leaves slide: each leaf and its stripe become one mesh (two surfaces), kept apart
		for side in ["a", "b"]:
			var leaf: MeshInstance3D = g[side]
			keep[leaf] = true
			var am := ArrayMesh.new()
			var lm: Mesh = leaf.mesh
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, lm.surface_get_arrays(0))
			am.surface_set_material(0, leaf.material_override)
			for st in leaf.get_children():
				if st is MeshInstance3D:
					var sti := st as MeshInstance3D
					var tool := SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					tool.append_from(sti.mesh, 0, sti.transform)
					tool.commit(am)
					am.surface_set_material(am.get_surface_count() - 1, sti.material_override)
					leaf.remove_child(sti)
					sti.free()
			leaf.mesh = am
			leaf.material_override = null
	var groups := {}   # "level|material" -> [[MeshInstance3D, Transform3D]]
	var mats := {}
	for c in world.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if keep.has(mi) or mi.mesh == null or mi.material_override == null or mi.get_child_count() > 0: continue
		var xf := _xf_to_world(mi)
		var lv := int(round(xf.origin.y / DECK_GAP))
		var k := "%d|%s" % [lv, _mat_key(mi.material_override)]
		if not groups.has(k): groups[k] = []; mats[k] = mi.material_override
		groups[k].append([mi, xf])
	for k in groups:
		var list: Array = groups[k]
		var lv := int(str(k).split("|")[0])
		if list.size() < 2:
			_level_node(lv, list[0][0])
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for pair in list:
			var m: Mesh = (pair[0] as MeshInstance3D).mesh
			for si in m.get_surface_count(): st.append_from(m, si, pair[1])
		var one := MeshInstance3D.new()
		one.name = "Merged_%d_%d" % [lv + 1, groups.keys().find(k)]
		one.mesh = st.commit()
		one.material_override = mats[k]
		one.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(one)
		_level_node(lv, one)
		for pair in list:
			var mi: MeshInstance3D = pair[0]
			mi.get_parent().remove_child(mi)
			mi.free()
			merged_pieces += 1
	for g in gates: _level_node(int(round((g["pos"] as Vector3).y / DECK_GAP)), g["node"])
	for lb in world.find_children("*", "Label3D", true, false):
		if keep.has(lb): continue
		_level_node(int(round(_xf_to_world(lb as Node3D).origin.y / DECK_GAP)), lb)
	_show_level(0)

func _level_node(lv: int, n: Node3D) -> void:
	if not _by_level.has(lv): _by_level[lv] = []
	_by_level[lv].append(n)

## Only the deck you stand on is drawn (the others are behind the floor and ceiling anyway).
func _show_level(lv: int) -> void:
	for k in _by_level:
		for n in _by_level[k]:
			if is_instance_valid(n): (n as Node3D).visible = int(k) == lv

func pieces_drawn() -> int:
	var n := 0
	for g in world.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).is_visible_in_tree(): n += 1
	return n
