extends Control
class_name StationViewer
## v11.27 (owner: "set it up just like the ships, so we can rotate the station and look at it ... a screen that helps
## isolate it: toggle a light blue screen and a magenta one ... no ring underneath"): the Station Viewer, opened from
## COMMAND. Any 3D station in the game on a flat key-colour backdrop: drag to turn, pinch / wheel to zoom, snap to
## FRONT (the docking face, -Z) / BACK / LEFT / RIGHT / TOP / BOTTOM / 3-4, flat (orthographic) or perspective, and HIDE to clear the buttons
## for a clean picture (tap anywhere to bring them back). Made for taking true turnaround images to rework a station.

const KEY_BLUE := Color(0.55, 0.82, 1.0)     # light blue screen (for green / red / gold stations)
const KEY_MAGENTA := Color(1.0, 0.0, 1.0)    # magenta screen (for blue / cyan stations)
const KEY_SPACE := Color(0.02, 0.04, 0.08)   # dark, for just looking
const VIEWS := {"FRONT": Vector2(PI, 0.0), "BACK": Vector2(0.0, 0.0), "LEFT": Vector2(-PI / 2, 0.0), "RIGHT": Vector2(PI / 2, 0.0),
	"TOP": Vector2(0.0, PI / 2 - 0.001), "BOTTOM": Vector2(0.0, -PI / 2 + 0.001), "3/4": Vector2(0.75, 0.35)}

var keys: Array = []        # station model keys (assets/stations3d/<key>.glb)
var idx := 0
var yaw := 0.75
var pitch := 0.35
var dist := 2.3              # in model radii
var ortho := false
var bg_mode := 0             # 0 light blue, 1 magenta, 2 space
var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var env: Environment
var ui: Control
var name_label: Label
var status: Label
var _touches := {}
var _pinch0 := 0.0
var _loading := false

static func station_keys() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://assets/stations3d")
	if d:
		for f in d.get_files():
			var n := f.trim_suffix(".import").trim_suffix(".remap")
			if n.ends_with(".glb") and not n.ends_with("_lod1.glb") and not n.ends_with("_lod2.glb"):
				var k := n.trim_suffix(".glb")
				if not k in out: out.append(k)
	for k in Packs.PACKS:   # web: packs that are not mounted yet are still listed
		if str(k).begins_with("HL_Station_") or str(k).begins_with("st3d_"):
			if not k in out: out.append(k)
	out.sort()
	return out

static func pretty(k: String) -> String:
	return k.trim_prefix("HL_Station_").trim_prefix("st3d_").trim_suffix("_retopo").replace("_", " ").to_upper()

func _ready() -> void:
	name = "StationViewer"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	keys = station_keys()
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.68)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	for r in [Vector3(-40, 35, 0), Vector3(-20, 215, 0), Vector3(60, 120, 0)]:   # key, rim, fill from below
		var l := DirectionalLight3D.new()
		l.rotation_degrees = r
		l.light_energy = 1.1 if r.y < 100 else (0.55 if r.x < 0 else 0.35)
		vp.add_child(l)
	cam = Camera3D.new()
	cam.fov = 35
	vp.add_child(cam)
	pivot = Node3D.new()
	vp.add_child(pivot)
	svc.gui_input.connect(_input_view)
	_build_ui()
	_apply_bg()
	var start := 0
	var here: Dictionary = Data.RETOPO_STATIONS.get(GS.system_id, Data.STATION3D.get(GS.system_id, {}))
	if here.has("*") and keys.has(here["*"]): start = keys.find(here["*"])   # opens on this system's own station
	show_station(start)

func _button(txt: String, cb: Callable, w := 0.0) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", Data.ts(15))
	b.custom_minimum_size = Vector2(w, 44)
	b.pressed.connect(cb)
	return b

func _build_ui() -> void:
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var top := HBoxContainer.new()   # station picker
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 10
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 10)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ui.add_child(top)
	top.add_child(_button("◀", func(): show_station(idx - 1), 56))
	name_label = Label.new()
	name_label.name = "StationName"
	name_label.custom_minimum_size = Vector2(420, 44)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", Data.ts(20))
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name_label.add_theme_constant_override("outline_size", 6)
	top.add_child(name_label)
	top.add_child(_button("▶", func(): show_station(idx + 1), 56))
	var side := VBoxContainer.new()   # views + display
	side.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	side.offset_left = -170
	side.offset_right = -12
	side.grow_vertical = Control.GROW_DIRECTION_BOTH
	side.add_theme_constant_override("separation", 6)
	ui.add_child(side)
	for v in VIEWS:
		side.add_child(_button(v, func(): snap(v), 150))
	var bot := HBoxContainer.new()   # backdrop, flat / perspective, hide, close
	bot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bot.offset_bottom = -12
	bot.offset_top = -56
	bot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bot.alignment = BoxContainer.ALIGNMENT_CENTER
	bot.add_theme_constant_override("separation", 10)
	ui.add_child(bot)
	var bgb := _button("SCREEN: LIGHT BLUE", Callable(), 230)
	bgb.name = "BgButton"
	bgb.pressed.connect(func():
		bg_mode = (bg_mode + 1) % 3
		bgb.text = "SCREEN: " + ["LIGHT BLUE", "MAGENTA", "SPACE"][bg_mode]
		_apply_bg())
	bot.add_child(bgb)
	var ob := _button("PERSPECTIVE", Callable(), 170)
	ob.name = "OrthoButton"
	ob.pressed.connect(func():
		ortho = not ortho
		ob.text = "FLAT" if ortho else "PERSPECTIVE"
		_camera())
	bot.add_child(ob)
	bot.add_child(_button("HIDE BUTTONS", func(): _hide_ui(true), 170))
	bot.add_child(_button("CLOSE", func(): queue_free(), 120))
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status.offset_left = 16
	status.offset_top = -90
	status.offset_bottom = -64
	status.add_theme_font_size_override("font_size", Data.ts(14))
	status.add_theme_color_override("font_color", Color(1, 1, 1))
	status.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	status.add_theme_constant_override("outline_size", 5)
	status.text = "Drag to turn · pinch or scroll to zoom"
	ui.add_child(status)

func _hide_ui(h: bool) -> void:
	ui.visible = not h
	Fs.visible = not h   # the corner FULL SCREEN button goes too, for a clean picture

func _exit_tree() -> void:
	Fs.visible = true

func _apply_bg() -> void:
	env.background_color = [KEY_BLUE, KEY_MAGENTA, KEY_SPACE][bg_mode]

## Load station i (wrapping), fit it to the view (centred on its bounds, scaled to a unit radius).
func show_station(i: int) -> void:
	if keys.is_empty() or _loading: return
	idx = wrapi(i, 0, keys.size())
	var key: String = keys[idx]
	name_label.text = "%s   (%d / %d)" % [pretty(key), idx + 1, keys.size()]
	for c in pivot.get_children(): c.queue_free()
	var path := "res://assets/stations3d/%s.glb" % key
	if not ResourceLoader.exists(path) and Packs.PACKS.has(key):
		_loading = true
		status.text = "Loading %s ..." % pretty(key)
		await Packs.wait(key, 90.0)
		_loading = false
		if not is_inside_tree(): return
	if not ResourceLoader.exists(path):
		status.text = "%s is not available here." % pretty(key)
		return
	var ps := load(path) as PackedScene
	if ps == null: return
	var inst: Node3D = ps.instantiate()
	pivot.add_child(inst)
	var box := AABB(); var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var xf: Transform3D = inst.global_transform.affine_inverse() * m.global_transform
		var b: AABB = xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var r := maxf(box.size.length() * 0.5, 0.001)
	inst.scale = Vector3.ONE / r
	inst.position = -box.get_center() / r
	status.text = "Drag to turn · pinch or scroll to zoom · %s" % key
	_camera()

func snap(v: String) -> void:
	var a: Vector2 = VIEWS[v]
	yaw = a.x
	pitch = a.y
	_camera()

func _input_view(e: InputEvent) -> void:
	if not ui.visible and (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
		_hide_ui(false)   # tap to bring the buttons back after HIDE
		return
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

func turn(rel: Vector2) -> void:
	yaw -= rel.x * 0.01
	pitch = clampf(pitch + rel.y * 0.008, -PI / 2 + 0.001, PI / 2 - 0.001)
	_camera()

func zoom(k: float) -> void:
	dist = clampf(dist * k, 1.3, 8.0)
	_camera()

func _camera() -> void:
	if not is_instance_valid(cam): return
	cam.position = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var up := Vector3.UP if absf(pitch) < 1.5 else Vector3(-sin(yaw), 0, -cos(yaw)) * signf(pitch)
	cam.look_at(Vector3.ZERO, up)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
	cam.size = dist * 0.75   # ortho: the same framing as the perspective view at this distance
	cam.near = 0.01
	cam.far = 100.0
