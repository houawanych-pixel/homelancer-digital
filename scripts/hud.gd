extends Control
## Unified flight HUD (chase and cockpit views) with multi-touch controls.
## Layout follows the owner's mockup: six AUTO/MANUAL system panels (top), SHIELD/HULL/ENERGY readout (top centre),
## FLIGHT and AIM sticks (bottom corners), radar on the centre console with MAP · COMMS · VIEW beneath it.
## Each finger belongs to whatever it first touched, so dragging a stick never presses a button.

signal pressed(id: String)

const CYAN := Color(0.33, 0.8, 1.0)
const CYAN_HI := Color(0.55, 0.9, 1.0)
const BLUE := Color(0.13, 0.55, 1.0)
const PANEL := Color(0.03, 0.09, 0.17, 0.82)
const EDGE := Color(0.33, 0.75, 1.0, 0.65)
const WHITE := Color(0.93, 0.97, 1.0)
const RED := Color(1.0, 0.3, 0.25)
const GOLD := Color(1.0, 0.84, 0.3)
const GREEN := Color(0.45, 1.0, 0.55)
const YELLOW := Color(1.0, 0.92, 0.3)

var space: SpaceSystem
var font: Font = ThemeDB.fallback_font
var owners := {} # touch index -> "move" | "aim" | button id
var origins := {}
var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var buttons := {} # id -> Rect2
var held := {}
var msg := ""
var msg_t := 0.0
var damage_flash := 0.0
var objective := ""
var comms_open := false
var comms_line := ""
var comms_from := ""
var comms_mode := "" # incoming | picker | talk
var comms_hostile := false
var comms_timer := 0.0
var contacts: Array = [] # [[name, subtitle], ...] shown by the CALL picker
var S := Vector2(1280, 720)
var stick_r := 100.0
var flash := {} # system id -> seconds of highlight
var panels := {} # system id -> panel rect
var t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GS.changed.connect(queue_redraw)

func flash_message(txt: String) -> void:
	msg = txt
	msg_t = 4.0

func hurt() -> void:
	damage_flash = 0.6

func pulse(id: String) -> void:
	flash[id] = 0.6

func open_comms(from: String, line: String, mode := "talk", hostile := false) -> void:
	comms_open = true
	comms_from = from
	comms_line = line
	comms_mode = mode
	comms_hostile = hostile
	comms_timer = 7.0 if mode == "incoming" else 0.0

func open_picker(list: Array) -> void:
	contacts = list
	comms_open = true
	comms_mode = "picker"
	comms_from = "Intercom"
	comms_line = ""
	comms_hostile = false

func close_comms() -> void:
	comms_open = false
	comms_mode = ""

# ---------------------------------------------------------------- layout
func _home(which: String) -> Vector2:
	return Vector2(stick_r + 70, S.y - stick_r - 50) if which == "move" else Vector2(S.x - stick_r - 70, S.y - stick_r - 50)

func _radar_center() -> Vector2:
	return Vector2(S.x * 0.5, S.y - 168) if GS.view == "cockpit" else Vector2(S.x * 0.5, S.y - 136)

func _panel_w() -> float:
	return clampf(S.x * 0.27, 330.0, 430.0)

func _layout() -> void:
	S = get_viewport_rect().size
	stick_r = clampf(S.y * 0.14, 84.0, 110.0)
	buttons.clear()
	var pw := _panel_w()
	var i := 0
	for sysd in Data.SYSTEMS_UI:
		var left: bool = sysd["side"] == "left"
		var row := i % 3
		var r := Rect2(10 if left else S.x - pw - 10, 12 + row * 80, pw, 70)
		var id: String = sysd["id"]
		panels[id] = r
		buttons["mode_%s_manual" % id] = Rect2(r.end.x - 10 - 92, r.position.y + 14, 92, 42)
		buttons["mode_%s_auto" % id] = Rect2(r.end.x - 10 - 92 - 6 - 78, r.position.y + 14, 78, 42)
		# the icon itself is the manual action button (count printed on it)
		buttons["sys_" + id] = Rect2(r.position + Vector2(6, 5), Vector2(64, 60))
		i += 1
	var rc := _radar_center()
	buttons["map"] = Rect2(rc.x - 6 - 120, S.y - 58, 120, 48)
	buttons["view"] = Rect2(rc.x + 6, S.y - 58, 120, 48)
	buttons["target"] = Rect2(S.x - 10 - 150, 262, 150, 52)
	buttons["goto"] = Rect2(S.x - 10 - 150, 322, 150, 52)
	# action rows above the sticks: right hand = THRUST · STOP · ENGINE KILL, left hand = WARP · CALL · HANG UP
	var row_h := 64.0
	var row_y := _home("aim").y - stick_r - 14 - row_h
	var bw := 128.0
	buttons["thrust"] = Rect2(S.x - 14 - 150, row_y, 150, row_h)
	buttons["stop"] = Rect2(S.x - 14 - 150 - 10 - bw, row_y, bw, row_h)
	buttons["kill"] = Rect2(S.x - 14 - 150 - 20 - bw * 2, row_y, bw, row_h)
	buttons["warp"] = Rect2(14, row_y, 150, row_h)
	buttons["call"] = Rect2(14 + 150 + 10, row_y, bw, row_h)
	buttons["hangup"] = Rect2(14 + 150 + 20 + bw, row_y, bw, row_h)
	if space and space.controls:
		if space.dock_candidate() != null: buttons["dock"] = Rect2(10, 300, 250, 64)
		elif space.gate_in_range(): buttons["jump"] = Rect2(10, 300, 250, 64)
	if comms_open and comms_mode == "picker":
		var cp := _comms_rect()
		for k in contacts.size():
			buttons["contact_%d" % k] = Rect2(cp.position.x + 230, cp.position.y + 66 + k * 56, cp.size.x - 250, 48)

func _comms_rect() -> Rect2:
	var w := minf(700.0, S.x * 0.5)
	return Rect2(S.x * 0.5 - w * 0.5, 190, w, 240)

# ---------------------------------------------------------------- input
func _input(e: InputEvent) -> void:
	if not visible or space == null: return
	if e is InputEventScreenTouch:
		_layout()
		if e.pressed:
			var hit := ""
			for id in buttons:
				if (buttons[id] as Rect2).grow(4).has_point(e.position):
					hit = id
					break
			if hit != "":
				owners[e.index] = hit
				held[hit] = true
				if hit != "sys_guns" and hit != "thrust": pressed.emit(hit)
				get_viewport().set_input_as_handled()
				return
			if comms_open and _comms_rect().has_point(e.position):
				owners[e.index] = "comms_body"
				return
			if e.position.x < S.x * 0.45 and e.position.y > 250 and not owners.values().has("move"):
				owners[e.index] = "move"
				origins["move"] = e.position
			elif e.position.x >= S.x * 0.45 and e.position.y > 250 and not owners.values().has("aim"):
				owners[e.index] = "aim"
				origins["aim"] = e.position
		else:
			var o: String = owners.get(e.index, "")
			owners.erase(e.index)
			if o == "move":
				move_vec = Vector2.ZERO
				origins.erase("move")
			elif o == "aim":
				aim_vec = Vector2.ZERO
				origins.erase("aim")
			elif o != "":
				held.erase(o)
	elif e is InputEventScreenDrag:
		var o2: String = owners.get(e.index, "")
		if o2 == "move": move_vec = ((e.position - origins["move"]) / stick_r).limit_length(1.0)
		elif o2 == "aim": aim_vec = ((e.position - origins["aim"]) / stick_r).limit_length(1.0)

func _process(dt: float) -> void:
	if space == null: return
	t += dt
	msg_t = maxf(0.0, msg_t - dt)
	damage_flash = maxf(0.0, damage_flash - dt)
	for k in flash.keys():
		flash[k] = maxf(0.0, float(flash[k]) - dt)
	var kb := Vector2(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("back", "forward"))
	var ka := Vector2(Input.get_axis("yaw_left", "yaw_right"), Input.get_axis("pitch_up", "pitch_down"))
	space.move = Vector2(move_vec.x, -move_vec.y) if kb == Vector2.ZERO else kb
	var a := aim_vec if ka == Vector2.ZERO else ka
	space.aim = a * a.length()
	space.fire_held = held.has("sys_guns") or Input.is_action_pressed("fire")
	space.thrust_held = held.has("thrust") or Input.is_key_pressed(KEY_SHIFT)
	if comms_mode == "incoming":
		comms_timer -= dt
		if comms_timer <= 0.0: close_comms()
	queue_redraw()

# ---------------------------------------------------------------- drawing helpers
func _box(r: Rect2, bg := PANEL, edge := EDGE, radius := 12, bw := 2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(CYAN, 0.12)
	sb.shadow_size = 6
	draw_style_box(sb, r)

func _text(p: Vector2, txt: String, size := 18, col := WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(font, p, txt, align, width, size, 5, Color(0, 0.03, 0.08, 0.75))
	draw_string(font, p, txt, align, width, size, col)

func _chip(id: String, label: String, on: bool) -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	if on: _box(r, Color(BLUE, 0.95), Color(CYAN_HI, 0.95), 9, 2)
	else: _box(r, Color(0.06, 0.12, 0.2, 0.9), Color(1, 1, 1, 0.16), 9, 2)
	_text(r.position + Vector2(0, r.size.y * 0.5 + 6), label, 16, WHITE if on else Color(0.75, 0.83, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _pill(id: String, label: String, active := false, col := CYAN, sub := "") -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var on := held.has(id) or active
	_box(r, Color(col, 0.35) if on else Color(0.03, 0.09, 0.17, 0.78), Color(col, 0.95 if on else 0.6), 12, 2)
	var y := r.size.y * 0.5 + (6.0 if sub == "" else 1.0)
	_text(r.position + Vector2(0, y), label, 18 if r.size.y >= 48 else 16, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sub != "": _text(r.position + Vector2(0, y + 17), sub, 12, Color(col.lightened(0.2), 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	match id:
		"shield":
			var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.85, -s * 0.62), c + Vector2(s * 0.72, s * 0.25), c + Vector2(0, s), c + Vector2(-s * 0.72, s * 0.25), c + Vector2(-s * 0.85, -s * 0.62), c + Vector2(0, -s)])
			draw_polyline(pts, col, 3.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(0, -s * 0.62), c + Vector2(s * 0.5, -s * 0.38), c + Vector2(s * 0.42, s * 0.14), c + Vector2(0, s * 0.62)]), Color(col, 0.6), 2.0, true)
		"hull":
			draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.25, -s * 0.25), col, s * 0.28)
			draw_arc(c + Vector2(s * 0.45, -s * 0.45), s * 0.42, deg_to_rad(-20), deg_to_rad(250), 16, col, s * 0.2)
		"energy":
			draw_rect(Rect2(c + Vector2(-s * 0.45, -s * 0.8), Vector2(s * 0.9, s * 1.7)), col, false, 3.0)
			draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.98), Vector2(s * 0.4, s * 0.18)), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.12, -s * 0.6), c + Vector2(-s * 0.25, s * 0.08), c + Vector2(0, s * 0.08), c + Vector2(-s * 0.12, s * 0.62), c + Vector2(s * 0.25, -s * 0.08), c + Vector2(0, -s * 0.08)]), col)
		"guns":
			for dx in [-s * 0.3, s * 0.3]:
				draw_rect(Rect2(c + Vector2(dx - s * 0.13, -s * 0.9), Vector2(s * 0.26, s * 1.35)), col)
				draw_circle(c + Vector2(dx, s * 0.62), s * 0.22, col)
		"missile":
			var dir := Vector2(1, -1).normalized()
			var perp := Vector2(-dir.y, dir.x)
			draw_line(c - dir * s * 0.8, c + dir * s * 0.55, col, s * 0.36)
			draw_colored_polygon(PackedVector2Array([c + dir * s * 0.95, c + dir * s * 0.5 + perp * s * 0.19, c + dir * s * 0.5 - perp * s * 0.19]), col)
			draw_colored_polygon(PackedVector2Array([c - dir * s * 0.55 + perp * s * 0.45, c - dir * s * 0.9, c - dir * s * 0.55 - perp * s * 0.45]), col)
		"mine":
			draw_circle(c, s * 0.55, col)
			draw_rect(Rect2(c + Vector2(-s * 0.95, -s * 0.12), Vector2(s * 1.9, s * 0.24)), col)
			draw_circle(c + Vector2(0, -s * 0.2), s * 0.18, Color(0.05, 0.1, 0.18))

func _system_panel(sysd: Dictionary) -> void:
	var id: String = sysd["id"]
	var r: Rect2 = panels[id]
	var lit := float(flash.get(id, 0.0)) > 0.0
	var locked: bool = space.warp_active() and id in ["guns", "missile", "mine"]
	_box(r, Color(0.08, 0.24, 0.4, 0.9) if lit else PANEL, CYAN_HI if lit else EDGE, 12, 2)
	# icon button — tap (or hold, for weapons) to use it now
	var b: Rect2 = buttons["sys_" + id]
	var down := held.has("sys_" + id)
	_box(b, Color(BLUE, 0.85) if down else Color(0.07, 0.2, 0.34, 0.95), Color(CYAN_HI, 0.95), 10, 2)
	_icon(id, b.get_center() + Vector2(0, -4), 17.0, WHITE if down else CYAN_HI)
	var badge := ""
	var cd := 0.0
	match id:
		"shield": cd = space.shield_cd / Data.SHIELD_BOOST_COOLDOWN
		"energy": cd = space.energy_cd / Data.ENERGY_BOOST_COOLDOWN
		"hull": badge = str(GS.repairs)
		"missile": badge = "%02d" % GS.missiles
		"mine": badge = "%02d" % GS.mines
		"guns": badge = "%d%%" % int(GS.energy)
	if cd > 0.0:
		draw_rect(b, Color(0, 0, 0, 0.45))
		draw_arc(b.get_center(), 24, -PI / 2, -PI / 2 + TAU * (1.0 - cd), 32, CYAN_HI, 4.0)
		badge = "%ds" % ceili(cd * (Data.SHIELD_BOOST_COOLDOWN if id == "shield" else Data.ENERGY_BOOST_COOLDOWN))
	if badge != "":
		var empty := (id == "missile" and GS.missiles == 0) or (id == "mine" and GS.mines == 0) or (id == "hull" and GS.repairs == 0)
		_text(Vector2(b.position.x, b.end.y - 5), badge, 15, RED if empty else WHITE, HORIZONTAL_ALIGNMENT_CENTER, b.size.x)
	var lines: PackedStringArray = (sysd["label"] as String).split("\n")
	_text(r.position + Vector2(82, 30), lines[0], 17, WHITE)
	_text(r.position + Vector2(82, 52), lines[1], 17, WHITE)
	_chip("mode_%s_auto" % id, "AUTO", GS.is_auto(id))
	_chip("mode_%s_manual" % id, "MANUAL", not GS.is_auto(id))
	if locked:
		var chips: Rect2 = (buttons["mode_%s_auto" % id] as Rect2).merge(buttons["mode_%s_manual" % id])
		draw_rect(b, Color(0, 0, 0, 0.55))
		_box(chips, Color(0.1, 0.07, 0.02, 0.95), Color(GOLD, 0.9), 9, 2)
		_text(Vector2(chips.position.x, chips.position.y + 28), "LOCKED · WARP", 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER, chips.size.x)

func _stick(which: String, label: String) -> void:
	var active := owners.values().has(which)
	var c: Vector2 = origins.get(which, _home(which))
	var v := move_vec if which == "move" else aim_vec
	draw_circle(c, stick_r, Color(0.02, 0.1, 0.2, 0.55 if active else 0.42))
	draw_arc(c, stick_r, 0, TAU, 64, Color(CYAN, 0.95), 3.0, true)
	draw_arc(c, stick_r - 7, 0, TAU, 64, Color(CYAN, 0.25), 2.0, true)
	var a := stick_r * 0.78
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tip: Vector2 = c + d * a
		var perp := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([tip + d * 9, tip - d * 5 + perp * 9, tip - d * 5 - perp * 9]), Color(CYAN_HI, 0.9))
	var knob := c + v * stick_r * 0.62
	draw_circle(knob, stick_r * 0.36, Color(0.62, 0.8, 0.97, 0.95 if active else 0.8))
	draw_arc(knob, stick_r * 0.36, 0, TAU, 40, WHITE, 3.0, true)
	_text(c + Vector2(-60, stick_r * 0.72), label, 17, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120)

func _screen(p3: Vector3) -> Variant:
	var cam: Camera3D = space.cam
	if cam.is_position_behind(p3): return null
	return cam.unproject_position(p3)

# ---------------------------------------------------------------- cockpit frame (first-person view)
func _cockpit() -> void:
	var w := S.x
	var h := S.y
	var shell := Color(0.86, 0.88, 0.9)
	var shell_dk := Color(0.55, 0.6, 0.66)
	var metal := Color(0.16, 0.19, 0.24)
	var orange := Color(1.0, 0.55, 0.15)
	for side in [-1.0, 1.0]:
		var x0: float = w * 0.5 + side * w * 0.5
		var strut := PackedVector2Array([Vector2(x0, 0), Vector2(x0 - side * w * 0.035, 0), Vector2(x0 - side * w * 0.2, h * 0.64), Vector2(x0 - side * w * 0.15, h * 0.66), Vector2(x0, h * 0.2)])
		draw_colored_polygon(strut, shell)
		draw_line(Vector2(x0 - side * w * 0.03, h * 0.05), Vector2(x0 - side * w * 0.18, h * 0.62), Color(orange, 0.95), 6)
		draw_line(Vector2(x0 - side * w * 0.012, h * 0.1), Vector2(x0 - side * w * 0.155, h * 0.64), shell_dk, 3)
	var dash := PackedVector2Array([Vector2(0, h * 0.7), Vector2(w * 0.2, h * 0.62), Vector2(w * 0.38, h * 0.585), Vector2(w * 0.62, h * 0.585), Vector2(w * 0.8, h * 0.62), Vector2(w, h * 0.7), Vector2(w, h), Vector2(0, h)])
	draw_colored_polygon(dash, shell)
	var inner := PackedVector2Array([Vector2(w * 0.05, h * 0.76), Vector2(w * 0.22, h * 0.69), Vector2(w * 0.36, h * 0.66), Vector2(w * 0.64, h * 0.66), Vector2(w * 0.78, h * 0.69), Vector2(w * 0.95, h * 0.76), Vector2(w * 0.95, h), Vector2(w * 0.05, h)])
	draw_colored_polygon(inner, metal)
	for side in [-1.0, 1.0]:
		var cx: float = w * 0.5 + side * w * 0.2
		draw_colored_polygon(PackedVector2Array([Vector2(cx - w * 0.05, h * 0.69), Vector2(cx + w * 0.05, h * 0.67), Vector2(cx + w * 0.06, h * 0.74), Vector2(cx - w * 0.04, h * 0.76)]), Color(0.2, 0.62, 1.0, 0.85))
		draw_line(Vector2(w * 0.5 + side * w * 0.3, h * 0.72), Vector2(w * 0.5 + side * w * 0.42, h * 0.8), orange, 8)
		draw_line(Vector2(w * 0.5 + side * w * 0.13, h * 0.8), Vector2(w * 0.5 + side * w * 0.1, h), shell_dk, 5)
	var rc := _radar_center()
	draw_circle(rc, 138, shell_dk)
	draw_circle(rc, 128, metal)

# ---------------------------------------------------------------- main draw
func _draw() -> void:
	if space == null or not is_instance_valid(space.player): return
	_layout()
	var cam: Camera3D = space.cam
	var cockpit := GS.view == "cockpit"
	if space.in_nebula > 0.0:
		draw_rect(Rect2(Vector2.ZERO, S), Color(space.nebula_color, 0.36 * space.in_nebula))
	for n in [space.station, space.planet, space.gate]:
		var pos: Vector3 = space.dock_point(n) if n != space.gate else n.global_position
		var sp = _screen(pos)
		var col := GOLD if n == space.gate else GREEN
		if sp != null and Rect2(Vector2.ZERO, S).has_point(sp):
			draw_arc(sp, 14, 0, TAU, 4, Color(col, 0.85), 2.0)
			_text(sp + Vector2(20, 6), "%s  %s" % [n.name, _dist(space.distance_to(n))], 14, Color(col, 0.95))
	for tr in space.traffic:
		var tp0 = _screen(tr["node"].global_position)
		if tp0 != null and space.player.global_position.distance_to(tr["node"].global_position) < 900.0:
			_brackets(tp0, 18.0, Color(GREEN, 0.8))
	var tgt: Node3D = space.target
	if tgt and is_instance_valid(tgt):
		var tp = _screen(tgt.global_position)
		var tcol := RED if tgt.get_meta("kind", "") == "enemy" else GOLD
		if tp != null and Rect2(Vector2(40, 40), S - Vector2(80, 80)).has_point(tp):
			_brackets(tp, 30.0, tcol)
			if tgt.get_meta("kind", "") == "enemy":
				var hv: float = space.target_health()
				draw_rect(Rect2(tp + Vector2(-30, 38), Vector2(60, 6)), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(tp + Vector2(-30, 38), Vector2(60 * hv, 6)), RED)
				var e: Dictionary = space._enemy_entry(tgt)
				if not e.is_empty():
					var d: float = space.player.global_position.distance_to(tgt.global_position)
					var lp = _screen(tgt.global_position + (e["vel"] as Vector3) * (d / float(GS.weapon()["speed"])))
					if lp != null:
						draw_arc(lp, 11, 0, TAU, 24, Color(RED, 0.95), 2.0)
						draw_line(lp + Vector2(-5, 0), lp + Vector2(5, 0), RED, 2)
						draw_line(lp + Vector2(0, -5), lp + Vector2(0, 5), RED, 2)
		else:
			var v: Vector3 = cam.global_basis.inverse() * (tgt.global_position - cam.global_position)
			var dir := Vector2(v.x, -v.y).normalized()
			if dir == Vector2.ZERO: dir = Vector2.DOWN
			var edge := S * 0.5 + dir * Vector2(S.x * 0.47, S.y * 0.4)
			var perp := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([edge + dir * 22, edge - dir * 10 + perp * 16, edge - dir * 10 - perp * 16]), tcol)
	if space.warp_state == "on":
		var cc0 := S * 0.5
		for i in 48:
			var a := i * 2.399 + t * 0.4
			var ph := fmod(i * 0.137 + t * 1.8, 1.0)
			var d0 := Vector2(cos(a), sin(a))
			var r0 := 60.0 + ph * ph * S.x * 0.6
			draw_line(cc0 + d0 * r0, cc0 + d0 * (r0 + 30 + 160 * ph), Color(0.75, 0.85, 1.0, 0.55 * ph), 1.5 + 2.0 * ph)
	if cockpit: _cockpit()
	var c := S * 0.5
	var locked: bool = space._in_fire_cone(space.target)
	var rc2 := RED if locked else WHITE
	draw_arc(c, 34, 0, TAU, 48, Color(rc2, 0.95), 2.0, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * 22, c + d * 52, Color(rc2, 0.95), 2.0)
	draw_circle(c, 3, rc2)
	# top centre: title + SHIELD / HULL / ENERGY
	_text(Vector2(0, 32), "HOMELANCER", 24, WHITE, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	for side in [-1.0, 1.0]:
		for k in 3:
			var y := 22.0 + k * 5
			var x0: float = S.x * 0.5 + side * (96 + k * 4)
			draw_line(Vector2(x0, y), Vector2(x0 + side * (44 - k * 10), y), Color(CYAN_HI, 0.9), 3)
	var vals := [["SHIELD", GS.shield / GS.max_shield(), CYAN], ["HULL", GS.hull / GS.max_hull(), GREEN], ["ENERGY", GS.energy / Data.ENERGY_MAX, YELLOW]]
	for k in 3:
		var x: float = S.x * 0.5 + (k - 1) * 150.0 - 75.0
		_text(Vector2(x, 60), vals[k][0], 17, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 150)
		var pct := int(round(clampf(vals[k][1], 0.0, 1.0) * 100.0))
		var col: Color = vals[k][2] if pct > 25 else RED
		_text(Vector2(x, 98), "%d%%" % pct, 36, col, HORIZONTAL_ALIGNMENT_CENTER, 150)
	var sysname: String = Data.SYSTEMS[GS.system_id]["name"].to_upper()
	var zone := ""
	if space.in_nebula > 0.0: zone = "  ·  %s NEBULA — SENSORS DEGRADED" % Data.SYSTEMS[GS.system_id]["nebula"]["name"].to_upper()
	elif space.in_belt: zone = "  ·  %s — WATCH FOR ROCKS" % Data.SYSTEMS[GS.system_id]["asteroids"]["name"].to_upper()
	_text(Vector2(0, 124), "%s SYSTEM%s   ·   %s   ·   %s" % [sysname, zone, GS.ship()["name"].to_upper(), _money(GS.credits)], 14, CYAN_HI, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	if objective != "": _text(Vector2(0, 148), objective, 15, WHITE, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	if msg_t > 0.0: _text(Vector2(0, 172), msg, 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	for sysd in Data.SYSTEMS_UI: _system_panel(sysd)
	if tgt and is_instance_valid(tgt):
		var tr := Rect2(S.x * 0.5 - 125, 184, 250, 72)
		_box(tr)
		_text(tr.position + Vector2(14, 24), "TARGET", 12, CYAN_HI)
		_text(tr.position + Vector2(14, 47), tgt.name, 18, RED if tgt.get_meta("kind", "") == "enemy" else GOLD)
		_text(tr.position + Vector2(14, 66), _dist(space.distance_to(tgt)), 13, WHITE)
		var th: float = space.target_health()
		if th >= 0.0:
			draw_rect(Rect2(tr.position + Vector2(110, 58), Vector2(126, 7)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(tr.position + Vector2(110, 58), Vector2(126 * th, 7)), RED)
	var spd := "SPEED %d" % int(space.speed_now)
	if space.warp_state == "on": spd += "   ·   WARP"
	elif space.warp_state == "charging": spd += "   ·   WARP CHARGING %d%%" % int(space.warp_t / Data.WARP_CHARGE * 100)
	elif space.engine_kill: spd += "   ·   ENGINES OFF — DRIFTING"
	elif space.braking: spd += "   ·   STOPPING"
	elif space.boosting: spd += "   ·   THRUST"
	if space.autopilot != null: spd += "   ·   AUTOPILOT > %s" % space.autopilot.name
	_text(Vector2(0, c.y + 84), spd, 15, Color(CYAN_HI, 0.95), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	_radar(_radar_center(), 104.0 if cockpit else 70.0)
	_pill("map", "MAP")
	_pill("view", "COCKPIT" if not cockpit else "CHASE", false, CYAN, "VIEW")
	_pill("target", "TARGET", false, CYAN, "NEXT")
	_pill("goto", "GO TO", space.autopilot != null, CYAN, "AUTOPILOT")
	if buttons.has("dock"): _pill("dock", "DOCK", true, GREEN, space.dock_candidate().name.to_upper())
	if buttons.has("jump"): _pill("jump", "JUMP", true, GOLD, "TO %s" % Data.SYSTEMS[space.sys["gate"]["to"]]["name"].to_upper())
	_stick("move", "FLIGHT")
	_stick("aim", "AIM")
	if comms_open: _comms()
	_rows()
	if damage_flash > 0.0:
		for i in 6:
			draw_rect(Rect2(Vector2.ZERO, S), Color(RED, damage_flash * 0.08), false, 60.0 - i * 9.0)

func _brackets(p: Vector2, s: float, col: Color) -> void:
	for cr in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner: Vector2 = p + cr * s
		draw_line(corner, corner - Vector2(cr.x * s * 0.45, 0), col, 3)
		draw_line(corner, corner - Vector2(0, cr.y * s * 0.45), col, 3)

func _comms() -> void:
	var r := _comms_rect()
	var accent := RED if comms_hostile else CYAN_HI
	_box(r, Color(0.02, 0.08, 0.16, 0.93), accent, 16, 3)
	if comms_mode == "picker":
		_text(r.position + Vector2(24, 44), "INTERCOM — WHO DO YOU WANT TO CALL?", 22, WHITE)
		for k in contacts.size():
			var br: Rect2 = buttons["contact_%d" % k]
			var hostile: bool = contacts[k][2]
			_box(br, Color(0.05, 0.15, 0.26, 1.0), Color(RED if hostile else GREEN, 0.8), 10, 2)
			_text(br.position + Vector2(16, 32), contacts[k][0], 19, WHITE)
			_text(br.position + Vector2(0, 32), contacts[k][1], 13, Color(RED if hostile else GREEN, 0.9), HORIZONTAL_ALIGNMENT_RIGHT, br.size.x - 14)
		var hc := Vector2(r.position.x + 110, r.position.y + 150)
		draw_arc(hc, 60, 0, TAU, 40, Color(GREEN, 0.5), 3.0)
		_text(hc + Vector2(-80, 8), "TAP A NAME", 16, GREEN, HORIZONTAL_ALIGNMENT_CENTER, 160)
		return
	var card := Rect2(r.position + Vector2(16, 16), Vector2(r.size.y - 32, r.size.y - 32))
	_box(card, Color(0.18, 0.04, 0.05, 1.0) if comms_hostile else Color(0.05, 0.14, 0.24, 1.0), Color(accent, 0.5), 12, 2)
	var cc := card.get_center()
	draw_arc(cc, card.size.x * 0.34, 0, TAU, 48, Color(CYAN, 0.5), 2.0, true)
	for i in 21:
		var hgt := 8.0 + 30.0 * absf(sin(t * 7.0 + i * 0.9)) * (0.4 + 0.6 * absf(sin(i * 0.45)))
		var x := cc.x - 60 + i * 6
		draw_line(Vector2(x, cc.y - hgt * 0.5), Vector2(x, cc.y + hgt * 0.5), accent, 3)
	var tx := card.end.x + 22
	_text(Vector2(tx, r.position.y + 50), comms_from.to_upper(), 30, WHITE)
	draw_circle(Vector2(tx + 8, r.position.y + 78), 6, RED if comms_hostile else GREEN)
	var status := "INCOMING CALL" if comms_mode == "incoming" else "COMMS · LIVE"
	if comms_hostile: status += " · HOSTILE"
	_text(Vector2(tx + 22, r.position.y + 85), status, 17, accent)
	var line_r := Rect2(Vector2(tx - 4, r.position.y + 104), Vector2(r.end.x - tx - 14, 70))
	_box(line_r, Color(0.03, 0.1, 0.2, 1.0), Color(CYAN, 0.5), 10, 2)
	draw_multiline_string_outline(font, line_r.position + Vector2(16, 28), comms_line, HORIZONTAL_ALIGNMENT_LEFT, line_r.size.x - 28, 17, 2, 4, Color(0, 0.03, 0.08, 0.75))
	draw_multiline_string(font, line_r.position + Vector2(16, 28), comms_line, HORIZONTAL_ALIGNMENT_LEFT, line_r.size.x - 28, 17, 2, WHITE)
	if comms_mode == "incoming":
		_text(Vector2(line_r.position.x, r.end.y - 22), "Closes by itself · HANG UP to end now", 13, Color(1, 1, 1, 0.6))

func _radar(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(0.02, 0.1, 0.18, 0.9))
	draw_arc(c, r, 0, TAU, 64, Color(CYAN, 0.9), 3.0, true)
	for k in [0.33, 0.66]:
		draw_arc(c, r * k, 0, TAU, 48, Color(CYAN, 0.22), 1.0, true)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(CYAN, 0.2))
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(CYAN, 0.2))
	var sweep := fmod(t * 1.4, TAU)
	draw_line(c, c + Vector2(cos(sweep), sin(sweep)) * r, Color(CYAN, 0.35), 2.0)
	var rng := 1600.0 * (1.0 - 0.6 * space.in_nebula)
	var inv := Basis(Vector3.UP, -space.yaw)
	var pp: Vector3 = space.player.global_position
	var items: Array = []
	for e in space.enemies: items.append([e["node"].global_position, RED, "tri"])
	for tr in space.traffic: items.append([tr["node"].global_position, GREEN, "tri"])
	items.append([space.station.global_position, GREEN, "dot"])
	items.append([space.planet.global_position, Color(0.5, 0.8, 1.0), "big"])
	items.append([space.gate.global_position, GOLD, "dot"])
	for it in items:
		var rel: Vector3 = inv * (it[0] - pp)
		var v := Vector2(rel.x, rel.z) / rng * r
		var at_edge := v.length() > r - 6
		if at_edge: v = v.normalized() * (r - 6)
		var p := c + v
		var col: Color = Color(it[1], 0.55 if at_edge else 1.0)
		if it[2] == "tri": draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 5), p + Vector2(-6, 5)]), col)
		else: draw_circle(p, 7.0 if it[2] == "big" else 4.5, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -13), c + Vector2(9, 9), c + Vector2(0, 4), c + Vector2(-9, 9)]), WHITE)

func _dist(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)

func _money(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out + " cr"

func _rows() -> void:
	var ORANGE := Color(1.0, 0.6, 0.2)
	_pill("thrust", "THRUST", space.boosting, ORANGE, "HOLD")
	_pill("stop", "STOP", space.braking, CYAN, "FULL STOP")
	_pill("kill", "ENGINE", space.engine_kill, GOLD, "KILL" if not space.engine_kill else "RESTART")
	var wsub := "FROM STOP"
	if space.warp_state == "charging": wsub = "CHARGING %d%%" % int(space.warp_t / Data.WARP_CHARGE * 100)
	elif space.warp_state == "on": wsub = "DROP OUT"
	_pill("warp", "WARP", space.warp_state != "off", Color(0.6, 0.55, 1.0), wsub)
	if space.warp_state == "charging":
		var wr: Rect2 = buttons["warp"]
		draw_rect(Rect2(wr.position + Vector2(8, wr.size.y - 7), Vector2((wr.size.x - 16) * space.warp_t / Data.WARP_CHARGE, 4)), Color(0.75, 0.7, 1.0))
	_pill("call", "CALL", comms_mode == "picker", GREEN, "INTERCOM")
	_pill("hangup", "HANG UP", false, RED, "END CALL")
