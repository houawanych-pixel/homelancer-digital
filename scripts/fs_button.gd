extends CanvasLayer
## v11.1 (owner: "a universal place for everything, easy to remember"): ONE full-screen button, always in the
## top-left corner, on every screen (flight, rooms, maps, docks). Four corner brackets; they point in when you are
## already full screen. Tap = the browser's full screen on / off.

const SIZE := 52.0
const MARGIN := 8.0
const CYAN := Color(0.35, 0.85, 1.0)

var btn: Control
var on := false

func _ready() -> void:
	layer = 120   # over every page and the flight HUD
	btn = Control.new()
	btn.name = "FsButton"
	btn.position = Vector2(MARGIN, MARGIN)
	btn.size = Vector2(SIZE, SIZE)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.tooltip_text = "Full screen"
	btn.draw.connect(_draw_btn)
	btn.gui_input.connect(_on_input)
	add_child(btn)

func _process(_d: float) -> void:
	if Engine.get_process_frames() % 30 != 0: return
	var now := is_full()
	if now != on:
		on = now
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
	var c := r.get_center()
	var h := SIZE * 0.26   # bracket corner distance from the middle
	var l := SIZE * 0.14   # bracket arm length
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
