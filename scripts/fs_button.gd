extends CanvasLayer
## v11.1 (owner: "a universal place for everything, easy to remember"): ONE full-screen button on every screen (flight,
## rooms, maps, docks). Four corner brackets; they point in when you are already full screen. Tap = the browser's full
## screen on / off. v11.53 (owner: it covered the system name, e.g. "DREADHOLM · F8"): BOTTOM MIDDLE now; in flight it
## sits just above the bottom row (the HUD says where: hud.fs_slot), clear of the joysticks.

const SIZE := 44.0   # (v11.2: a little lower, so the station title can sit higher)
const WIDTH := 176.0   # v11.2 (owner: "the full screen should say full screen"): icon + the words
const MARGIN := 8.0
const CYAN := Color(0.35, 0.85, 1.0)

var btn: Control
var on := false

func _ready() -> void:
	layer = 120   # over every page and the flight HUD
	btn = Control.new()
	btn.name = "FsButton"
	btn.position = Vector2(MARGIN, MARGIN)
	btn.size = Vector2(WIDTH, SIZE)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.tooltip_text = "Full screen"
	btn.draw.connect(_draw_btn)
	btn.gui_input.connect(_on_input)
	add_child(btn)

func _process(_d: float) -> void:
	_place()
	if Engine.get_process_frames() % 30 != 0: return
	var now := is_full()
	if now != on:
		on = now
		btn.queue_redraw()

## Bottom middle of the screen; in flight the HUD's slot just above the bottom row.
func slot() -> Rect2:
	var S: Vector2 = get_viewport().get_visible_rect().size
	var m = get_tree().current_scene
	if m != null and str(m.get("state")) == "flight" and m.get("hud") != null and (m.hud as CanvasItem).visible:
		var r: Rect2 = m.hud.get("fs_slot") if m.hud.get("fs_slot") != null else Rect2()
		if r.size.x > 0.0: return r
	return Rect2(S.x * 0.5 - WIDTH * 0.5, S.y - SIZE - MARGIN, WIDTH, SIZE)

func _place() -> void:
	var r := slot()
	if btn.position != r.position or btn.size != r.size:
		btn.position = r.position
		btn.size = r.size
		btn.queue_redraw()

func is_full() -> bool:
	if OS.has_feature("web"): return bool(JavaScriptBridge.eval("!!(window.__hlFsIsOn && window.__hlFsIsOn())", true))
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func toggle() -> void:
	if OS.has_feature("web"): JavaScriptBridge.eval("window.__hlFsToggle && window.__hlFsToggle()", true)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_full() else DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_tree().create_timer(0.4).timeout.connect(func(): on = is_full(); btn.queue_redraw())

func _on_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed) or (e is InputEventScreenTouch and e.pressed)
	if tap:
		btn.accept_event()
		toggle()

func _draw_btn() -> void:
	var r := Rect2(Vector2.ZERO, btn.size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.06, 0.12, 0.78)
	sb.border_color = Color(CYAN, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	btn.draw_style_box(sb, r)
	var hgt: float = btn.size.y
	var c := Vector2(hgt * 0.5, hgt * 0.5)   # the brackets sit on the left, the words on the right
	var h := hgt * 0.26   # bracket corner distance from the middle
	var l := hgt * 0.14   # bracket arm length
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx, sy) * h
			var dx := Vector2(-sx * l, 0.0)
			var dy := Vector2(0.0, -sy * l)
			if on:   # full screen: the brackets turn inward (= shrink back)
				p = c + Vector2(sx, sy) * (h - l)
				dx = -dx
				dy = -dy
			btn.draw_polyline(PackedVector2Array([p + dx, p, p + dy]), Color(0.85, 0.97, 1.0), 3.0, true)
	var f: Font = ThemeDB.fallback_font
	var txt := "EXIT FULL" if on else "FULL SCREEN"
	btn.draw_string(f, Vector2(hgt - 4.0, hgt * 0.5 + 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, btn.size.x - hgt - 4.0, 15 if hgt < 40.0 else 16, Color(0.85, 0.97, 1.0))
