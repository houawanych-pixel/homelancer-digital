class_name HangarView
extends Control
## v1.5p: full-screen hangar (YOUR SHIP -> ENTER HANGAR). The 3D hangar room (HangarRoom) in its own world, your
## craft in it: the mech standing on the launch pad, or the ship parked in front of it. Drag to look around,
## pinch / wheel to zoom. SHIP / MECH switches which one you look at; WINGS swings folding wings out and back.
## (Mounting weapons and the three paint channels come next, on this same screen.)

signal closed

var vp: SubViewport
var room: HangarRoom
var cam: Camera3D
var craft: Node3D
var showing := ""          # "ship" | "mech"
var yaw := 0.0
var pitch := 0.18
var dist := 22.0
var target := Vector3.ZERO
var wings_k := 0.0
var wings_want := 0.0
var status: Label
var _touches := {}
var _pinch0 := 0.0

func _ready() -> void:
	name = "HangarView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.02, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var svc := SubViewportContainer.new()
	svc.name = "HangarViewport"
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	svc.add_child(vp)
	svc.gui_input.connect(_input_3d)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.02, 0.025, 0.035)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.55, 0.6, 0.7)
	we.environment.ambient_light_energy = 0.9
	we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 0.5
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 55
	cam.far = 400
	vp.add_child(cam)
	_ui()
	Packs.request("hangar")
	Packs.request("mechs")
	_load.call_deferred()

func _ui() -> void:
	var back := _btn("HangarBack", "BACK", Vector2(16, 16))
	back.pressed.connect(close)
	var sw := _btn("HangarSwitch", "MECH", Vector2(16, 84))
	sw.pressed.connect(func(): show_craft("mech" if showing == "ship" else "ship"))
	var wg := _btn("HangarWings", "WINGS", Vector2(16, 152))
	wg.pressed.connect(func(): wings_want = 0.0 if wings_want > 0.5 else 1.0)
	status = Label.new()
	status.name = "HangarStatus"
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -40
	status.offset_left = 20
	status.text = "HANGAR  ·  loading..."
	add_child(status)

func _btn(nm: String, txt: String, at: Vector2) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.position = at
	b.custom_minimum_size = Vector2(150, 56)
	b.add_theme_font_size_override("font_size", 20)
	add_child(b)
	return b

func _load() -> void:
	await Packs.wait("hangar", 60.0)
	if not is_inside_tree(): return
	room = HangarRoom.new()
	room.name = "HangarRoom"
	vp.add_child(room)
	if HangarRoom.available(): room.build()
	show_craft("mech" if GS.form == "mech" else "ship")

func pad_point() -> Vector3:
	return room.transform * room.pad_center if room else Vector3.ZERO

func ship_point() -> Vector3:
	return room.transform * room.ship_spot if room else Vector3.ZERO

func show_craft(which: String) -> void:
	if is_instance_valid(craft): craft.queue_free()
	showing = which
	var mech_ok := ShipFactory.has_real_model("mech_player")
	if which == "mech" and not mech_ok: showing = "ship"
	var key: String = "mech_player" if showing == "mech" else str(GS.ship()["model"])
	craft = ShipFactory.build(key, false)
	craft.name = "Craft"
	craft.rotation.y = PI   # facing out into the room (the mech off its pad, the ship towards the door)
	vp.add_child(craft)
	var box := ShipFactory._aabb(craft, Transform3D.IDENTITY)
	if showing == "mech":
		craft.position = pad_point() - Vector3(0, box.position.y, 0) + Vector3(0, 0.3, 0)
		target = craft.position + Vector3(0, box.size.y * 0.55, 0)
		dist = 20.0
	else:
		craft.position = ship_point()
		target = craft.position
		dist = 18.0
	yaw = 0.35
	wings_k = 0.0
	wings_want = 0.0
	var sw := get_node_or_null("HangarSwitch") as Button
	if sw: sw.text = "SHIP" if showing == "mech" else "MECH"
	var wg := get_node_or_null("HangarWings") as Button
	if wg: wg.visible = ShipFactory.wings_open(craft) >= 0.0
	var nm: String = "your mech" if showing == "mech" else str(GS.ship()["name"])
	status.text = "HANGAR  ·  %s  ·  drag to look around, pinch to zoom%s" % [nm, "" if room and room.missing.is_empty() else "  (parts still loading)"]
	_camera()

func close() -> void:
	closed.emit()
	queue_free()

func _process(dt: float) -> void:
	if is_instance_valid(craft) and ShipFactory.wings_open(craft) >= 0.0 and not is_equal_approx(wings_k, wings_want):
		wings_k = move_toward(wings_k, wings_want, dt * Data.WINGS_OPEN_RATE)
		ShipFactory.set_wings(craft, wings_k)

func turn(rel: Vector2) -> void:
	yaw -= rel.x * 0.008
	pitch = clampf(pitch + rel.y * 0.006, -0.25, 1.1)
	_camera()

func zoom(k: float) -> void:
	dist = clampf(dist * k, Data.HANGAR_CAM_DIST[0], Data.HANGAR_CAM_DIST[1])
	_camera()

## Orbit the craft, kept inside the room (never through a wall, the floor or the ceiling).
func _camera() -> void:
	if not is_instance_valid(cam): return
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var p := target + off
	if room:   # inside the room, clear of the walls, floor and ceiling
		var k: float = Data.HANGAR_SCALE
		var m: float = 3.0 + (float(room.surfaces["walls"][3]) if room.surfaces.has("walls") else 0.0)
		p.x = clampf(p.x, -(room.W * 0.5 - m) * k, (room.W * 0.5 - m) * k)
		p.z = clampf(p.z, -(room.D * 0.5 - m) * k, (room.D * 0.5 - m) * k)
		p.y = clampf(p.y, 1.5, (room.H - 3.0) * k)
	cam.position = p
	cam.look_at(target, Vector3.UP)

func _input_3d(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed: _touches[e.index] = e.position
		else: _touches.erase(e.index)
		if _touches.size() == 2: _pinch0 = (_touches.values()[0] as Vector2).distance_to(_touches.values()[1])
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var d := (_touches.values()[0] as Vector2).distance_to(_touches.values()[1])
			if _pinch0 > 1.0: zoom(_pinch0 / d)
			_pinch0 = d
		else: turn(e.relative)
	elif e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
		turn(e.relative)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP: zoom(0.9)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom(1.1)
	elif e is InputEventMagnifyGesture:
		zoom(1.0 / e.factor)
