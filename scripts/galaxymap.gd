extends Control
## Galaxy map: a panoramic view THROUGH the travel network, in Homelancer's white + blues blueprint style.
## You stand at the heart of the network and look around: drag left/right (a little up/down) to pan, tap a system to
## see it, EXPAND to open its blueprint (planets, stations, gates, spaceways). Pure data: nothing loads.

signal closed

const BG := Color(0.965, 0.978, 0.992)
const PALE := Color(0.81, 0.89, 0.96)
const SKY := Color(0.56, 0.76, 0.92)
const MID := Color(0.24, 0.56, 0.82)
const DEEP := Color(0.12, 0.37, 0.66)
const NAVY := Color(0.05, 0.18, 0.35)
const SHADES := [PALE, SKY, MID, DEEP, NAVY]
const FOV_H := 1.9   # radians across the screen
const FOV_V := 1.05

var font: Font = ThemeDB.fallback_font
var yaw := 0.0
var pitch := 0.0
var current := "solara"
var selected := ""
var expanded := ""
var viewer := Vector3(-10, 0, -20)
var t := 0.0
var _drag_from := Vector2.INF
var _drag_moved := 0.0
var _hits := {}
var _btns := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(system_id: String) -> void:
	current = system_id
	selected = system_id
	expanded = ""
	var net := Galaxy.network()
	var d: Vector3 = (net["systems"][current]["pos"] as Vector3) - viewer
	yaw = atan2(d.x, -d.z)   # face your own system
	pitch = 0.0
	visible = true

func _process(dt: float) -> void:
	if not visible: return
	t += dt
	if _drag_from == Vector2.INF and expanded == "": yaw += dt * 0.015   # slow drift, like a sensor sweep
	queue_redraw()

func _gui_input(e: InputEvent) -> void:
	var pos := Vector2.INF
	var pressed := false
	var released := false
	if e is InputEventScreenTouch:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
		pressed = e.pressed
		released = not e.pressed
	elif e is InputEventScreenDrag or e is InputEventMouseMotion:
		if _drag_from != Vector2.INF and expanded == "":
			var rel: Vector2 = e.relative
			_drag_moved += rel.length()
			yaw -= rel.x / get_viewport_rect().size.x * FOV_H
			pitch = clampf(pitch + rel.y / get_viewport_rect().size.y * FOV_V, -0.35, 0.35)
		accept_event()
		return
	else:
		return
	accept_event()
	if pressed:
		_drag_from = pos
		_drag_moved = 0.0
		return
	if released:
		_drag_from = Vector2.INF
		if _drag_moved > 12.0: return
		tap(pos)

## Handle a tap (also used by tests).
func tap(pos: Vector2) -> void:
	for b in _btns:
		if (_btns[b] as Rect2).has_point(pos):
			press(b)
			return
	if expanded != "": return
	var best := ""
	var bd := 38.0
	for id in _hits:
		var d: float = (_hits[id] as Vector2).distance_to(pos)
		if d < bd:
			bd = d
			best = id
	if best != "": selected = best

func press(b: String) -> void:
	match b:
		"close":
			if expanded != "": expanded = ""
			else:
				visible = false
				closed.emit()
		"expand": if selected != "": expanded = selected

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	var S := get_viewport_rect().size
	_hits.clear()
	_btns.clear()
	draw_network(self, S, yaw, pitch, t, viewer, current, selected, _hits)
	_title(S)
	if selected != "" and expanded == "": _info(S)
	if expanded != "": _system_view(S, expanded)
	var cb := Rect2(Vector2(S.x - 150, 16), Vector2(130, 48))
	_btns["close"] = cb
	_button(cb, "BACK" if expanded != "" else "CLOSE")

## The network drawing, shared with the title screen. hits (optional) receives screen positions of systems.
static func draw_network(ci: CanvasItem, S: Vector2, yaw: float, pitch: float, t: float, viewer: Vector3, current := "", selected := "", hits = null, labels := true) -> void:
	var f: Font = ThemeDB.fallback_font
	ci.draw_rect(Rect2(Vector2.ZERO, S), BG)
	# faint blueprint grid: horizon and meridians
	var hy := S.y * 0.5 + pitch / FOV_V * S.y
	ci.draw_line(Vector2(0, hy), Vector2(S.x, hy), Color(PALE, 0.9), 1.0)
	for k in 24:
		var az := k * TAU / 24.0
		var x := S.x * 0.5 + wrapf(az - yaw, -PI, PI) / FOV_H * S.x
		if x > -10 and x < S.x + 10: ci.draw_line(Vector2(x, 0), Vector2(x, S.y), Color(PALE, 0.5), 1.0)
	var net := Galaxy.network()
	var sys: Dictionary = net["systems"]
	var proj := {}
	for id in sys:
		var d: Vector3 = (sys[id]["pos"] as Vector3) - viewer
		var dist := d.length()
		var az := atan2(d.x, -d.z)
		var el := asin(clampf(d.y / maxf(dist, 0.001), -1, 1))
		var dx := wrapf(az - yaw, -PI, PI)
		var p := Vector2(S.x * 0.5 + dx / FOV_H * S.x, S.y * 0.5 - (el - pitch) / FOV_V * S.y)
		proj[id] = [p, dist, dx]
	# connections
	for l in net["links"]:
		var a: Array = proj[l[0]]
		var b: Array = proj[l[1]]
		if absf(float(a[2]) - float(b[2])) > PI * 0.9: continue   # would wrap round the back
		var pa: Vector2 = a[0]
		var pb: Vector2 = b[0]
		if (pa.x < -200 and pb.x < -200) or (pa.x > S.x + 200 and pb.x > S.x + 200): continue
		match l[2]:
			"warp_gate": ci.draw_line(pa, pb, Color(MID, 0.75), 1.6, true)
			"jump_gate": _dashed(ci, pa, pb, Color(SKY, 0.95), 2.0, 9.0)
			"rift_gate": _dashed(ci, pa, pb, Color(NAVY, 0.8), 3.0, 4.0)
	# systems
	for id in proj:
		var p: Vector2 = proj[id][0]
		if p.x < -20 or p.x > S.x + 20 or p.y < -20 or p.y > S.y + 20: continue
		var s: Dictionary = sys[id]
		var r := clampf(260.0 / maxf(float(proj[id][1]), 1.0), 3.0, 11.0)
		var col: Color = SHADES[int(s["shade"])]
		if s["discovered"]: ci.draw_circle(p, r, col)
		else: ci.draw_arc(p, r, 0, TAU, 20, col, 1.6, true)
		if s["playable"]: ci.draw_arc(p, r + 4, 0, TAU, 24, DEEP, 2.0, true)
		if id == current:
			ci.draw_arc(p, r + 10 + 2.0 * sin(t * 3.0), 0, TAU, 32, NAVY, 2.0, true)
			if labels: ci.draw_string(f, p + Vector2(-60, r + 28), "YOU ARE HERE", HORIZONTAL_ALIGNMENT_CENTER, 120, 12, NAVY)
		if id == selected:
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var q: Vector2 = p + c * (r + 8)
				ci.draw_line(q, q - Vector2(c.x * 7, 0), NAVY, 2.0)
				ci.draw_line(q, q - Vector2(0, c.y * 7), NAVY, 2.0)
		if labels and (s["discovered"] or id == selected or r > 7.0):
			ci.draw_string(f, p + Vector2(r + 6, 5), s["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13 if s["playable"] else 11, NAVY if s["discovered"] else MID)
		if hits != null: hits[id] = p
	if labels:
		for c in Galaxy.CLUSTERS:
			var d2: Vector3 = (c[2] as Vector3) - viewer
			var dx2 := wrapf(atan2(d2.x, -d2.z) - yaw, -PI, PI)
			var el2 := asin(clampf(d2.y / maxf(d2.length(), 0.001), -1, 1))
			var cp := Vector2(S.x * 0.5 + dx2 / FOV_H * S.x, S.y * 0.5 - (el2 - pitch) / FOV_V * S.y - 70)
			if cp.x > 0 and cp.x < S.x: ci.draw_string(f, cp - Vector2(100, 0), (c[0] as String).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 200, 13, Color(DEEP, 0.55))

static func _dashed(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float, dash: float) -> void:
	var l := a.distance_to(b)
	if l < 1.0: return
	var dir := (b - a) / l
	var s := 0.0
	while s < l:
		ci.draw_line(a + dir * s, a + dir * minf(s + dash, l), col, w, true)
		s += dash * 2.0

func _text(p: Vector2, s: String, size := 15, col := NAVY, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, p, s, align, w, size, col)

func _button(r: Rect2, label: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = DEEP
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, r)
	_text(r.position + Vector2(0, r.size.y * 0.5 + 6), label, 16, DEEP, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _title(S: Vector2) -> void:
	_text(Vector2(24, 40), "GALAXY NAVIGATION", 24, NAVY)
	_text(Vector2(24, 62), "Drag to look around · tap a system · EXPAND for its chart", 13, MID)
	var ly := S.y - 22.0
	draw_line(Vector2(24, ly), Vector2(60, ly), Color(MID, 0.75), 1.6)
	_text(Vector2(66, ly + 5), "Warp gate", 12, NAVY)
	_dashed(self, Vector2(150, ly), Vector2(186, ly), SKY, 2.0, 9.0)
	_text(Vector2(192, ly + 5), "Jump gate (natural)", 12, NAVY)
	_dashed(self, Vector2(330, ly), Vector2(366, ly), NAVY, 3.0, 4.0)
	_text(Vector2(372, ly + 5), "Rift gate", 12, NAVY)
	draw_arc(Vector2(462, ly), 6, 0, TAU, 16, DEEP, 2.0)
	_text(Vector2(474, ly + 5), "Flyable now", 12, NAVY)
	var n: int = Galaxy.network()["systems"].size()
	_text(Vector2(S.x - 340, ly + 5), "%d systems · %d links · map data only" % [n, Galaxy.network()["links"].size()], 12, MID, HORIZONTAL_ALIGNMENT_RIGHT, 320)

func _info(S: Vector2) -> void:
	var s: Dictionary = Galaxy.network()["systems"][selected]
	var r := Rect2(Vector2(24, 86), Vector2(330, 196))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.94)
	sb.border_color = DEEP
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	draw_style_box(sb, r)
	_text(r.position + Vector2(16, 32), (s["name"] as String).to_upper(), 22, NAVY)
	_text(r.position + Vector2(16, 54), "%s · %s" % [s["cluster"], s["faction"]], 13, MID)
	_text(r.position + Vector2(16, 78), "%s star · %d planets · %d stations · %d spaceways" % [s["star"], s["planets"], s["stations"], s["spaceways"]], 13, NAVY)
	var kinds := {"warp_gate": 0, "jump_gate": 0, "rift_gate": 0}
	for l in Galaxy.links_of(selected): kinds[l[2]] += 1
	_text(r.position + Vector2(16, 100), "Gates: %d warp · %d jump · %d rift" % [kinds["warp_gate"], kinds["jump_gate"], kinds["rift_gate"]], 13, NAVY)
	var status := "FLYABLE" if s["playable"] else ("SURVEYED — no route yet" if s["discovered"] else "UNCHARTED")
	_text(r.position + Vector2(16, 124), status, 14, DEEP if s["playable"] else MID)
	var eb := Rect2(r.position + Vector2(16, 140), Vector2(140, 44))
	_btns["expand"] = eb
	_button(eb, "EXPAND")

## Blueprint of one system: star, orbits, bodies, warp gate, spaceways as dashed highways between bodies.
func _system_view(S: Vector2, id: String) -> void:
	var r := Rect2(Vector2(S.x * 0.12, 80), Vector2(S.x * 0.76, S.y - 120))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.97)
	sb.border_color = DEEP
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	draw_style_box(sb, r)
	var s: Dictionary = Galaxy.network()["systems"][id]
	_text(r.position + Vector2(20, 34), "%s SYSTEM" % (s["name"] as String).to_upper(), 22, NAVY)
	_text(r.position + Vector2(20, 56), "Blueprint · %s" % ("charted" if s["playable"] else "long-range survey"), 13, MID)
	var bodies := Galaxy.bodies(id)
	var c := r.get_center() + Vector2(0, 20)
	var far := 1.0
	for b in bodies: far = maxf(far, Vector2(b["pos"].x, b["pos"].z).length())
	var k := minf(r.size.x, r.size.y - 90) * 0.42 / far
	draw_circle(c, 9, Color(1.0, 0.82, 0.4))
	draw_arc(c, 13, 0, TAU, 24, DEEP, 1.5)
	var at := {}
	for b in bodies:
		var p: Vector2 = c + Vector2(b["pos"].x, b["pos"].z) * k
		at[b["key"]] = p
		draw_arc(c, c.distance_to(p), 0, TAU, 64, Color(PALE, 0.9), 1.0)
	for sw in Galaxy.SPACEWAYS.get(id, []):
		if at.has(sw[1]) and at.has(sw[2]):
			_dashed(self, at[sw[1]], at[sw[2]], DEEP, 3.0, 7.0)
			var mid: Vector2 = (at[sw[1]] + at[sw[2]]) * 0.5
			_text(mid + Vector2(-80, -8), sw[0], 12, DEEP, HORIZONTAL_ALIGNMENT_CENTER, 160)
	for b in bodies:
		var p: Vector2 = at[b["key"]]
		match b["kind"]:
			"planet": draw_circle(p, 10, MID)
			"station": draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), DEEP)
			"warp gate":
				draw_arc(p, 11, 0, TAU, 24, NAVY, 3.0)
		_text(p + Vector2(14, 5), "%s (%s)" % [b["name"], b["kind"]], 12, NAVY)
	var links := Galaxy.links_of(id)
	var y := r.end.y - 18.0 - 16.0 * mini(links.size(), 4)
	_text(Vector2(r.position.x + 20, y - 4), "ROUTES OUT", 12, MID)
	for i in mini(links.size(), 4):
		var l: Array = links[i]
		var other: String = l[1] if l[0] == id else l[0]
		_text(Vector2(r.position.x + 20, y + 14 + i * 16), "%s → %s" % [(l[2] as String).replace("_", " "), Galaxy.network()["systems"][other]["name"]], 12, NAVY)
