extends Control
## Flight HUD and multi-touch controls. Each finger is owned by whatever it first touched (a stick or a
## button), so dragging the aim stick can never press a button and several buttons work at once.

signal pressed(id: String)

const CYAN := Color(0.4, 0.86, 1.0)
const INK := Color(0.02, 0.06, 0.11, 0.72)
const WHITE := Color(0.92, 0.96, 1.0)
const RED := Color(1.0, 0.36, 0.3)
const GOLD := Color(1.0, 0.82, 0.4)
const GREEN := Color(0.45, 1.0, 0.6)

var space: SpaceSystem
var font: Font = ThemeDB.fallback_font
var owners := {} # touch index -> "move" | "aim" | button id
var origins := {}
var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var move_origin := Vector2.ZERO
var aim_origin := Vector2.ZERO
var buttons := {} # id -> Rect2
var held := {}
var msg := ""
var msg_t := 0.0
var damage_flash := 0.0
var objective := ""
var S := Vector2(1280, 720)
const STICK_R := 92.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GS.changed.connect(queue_redraw)

func flash_message(t: String) -> void:
	msg = t
	msg_t = 4.0

func hurt() -> void:
	damage_flash = 0.6

func _layout() -> void:
	S = get_viewport_rect().size
	buttons.clear()
	var r := S.x
	var b := S.y
	buttons["fire"] = Rect2(r - 176, b - 196, 150, 150)
	buttons["missile"] = Rect2(r - 330, b - 112, 138, 76)
	buttons["repair"] = Rect2(r - 176, b - 292, 150, 76)
	buttons["target"] = Rect2(r - 330, b - 204, 138, 76)
	buttons["auto"] = Rect2(r - 330, b - 292, 138, 76)
	buttons["nav"] = Rect2(r - 300, 112, 92, 58)
	buttons["cruise"] = Rect2(S.x * 0.5 - 250, b - 84, 150, 62)
	buttons["goto"] = Rect2(S.x * 0.5 + 100, b - 84, 150, 62)
	if space and space.controls:
		if space.dock_candidate() != null: buttons["dock"] = Rect2(S.x * 0.5 - 90, b - 170, 180, 70)
		elif space.gate_in_range(): buttons["jump"] = Rect2(S.x * 0.5 - 90, b - 170, 180, 70)
	move_origin = origins.get("move", Vector2(170, b - 170))
	aim_origin = origins.get("aim", Vector2(r - 470, b - 170))

func _input(e: InputEvent) -> void:
	if not visible or space == null: return
	if e is InputEventScreenTouch:
		_layout()
		if e.pressed:
			for id in buttons:
				if (buttons[id] as Rect2).grow(6).has_point(e.position):
					owners[e.index] = id
					held[id] = true
					if id != "fire": pressed.emit(id)
					get_viewport().set_input_as_handled()
					return
			if e.position.x < S.x * 0.42 and not owners.values().has("move"):
				owners[e.index] = "move"
				origins["move"] = e.position
			elif not owners.values().has("aim"):
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
		if o2 == "move": move_vec = ((e.position - origins["move"]) / STICK_R).limit_length(1.0)
		elif o2 == "aim": aim_vec = ((e.position - origins["aim"]) / STICK_R).limit_length(1.0)

func _process(dt: float) -> void:
	if space == null: return
	msg_t = maxf(0.0, msg_t - dt)
	damage_flash = maxf(0.0, damage_flash - dt)
	# keyboard fallback for desktop testing
	var k := Vector2(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("back", "forward"))
	var ka := Vector2(Input.get_axis("yaw_left", "yaw_right"), Input.get_axis("pitch_up", "pitch_down"))
	space.move = Vector2(move_vec.x, -move_vec.y) if k == Vector2.ZERO else k
	var a := aim_vec if ka == Vector2.ZERO else ka
	# soft response curve for precise aiming
	space.aim = a * a.length()
	space.fire_held = held.has("fire") or Input.is_action_pressed("fire")
	queue_redraw()

# ---------------------------------------------------------------- drawing helpers
func _panel(r: Rect2, bg := INK, edge := Color(CYAN, 0.55), radius := 10) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	draw_style_box(sb, r)

func _text(p: Vector2, t: String, size := 18, col := WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(font, p, t, align, width, size, 4, Color(0, 0, 0, 0.7))
	draw_string(font, p, t, align, width, size, col)

func _bar(p: Vector2, w: float, v: float, col: Color, label: String) -> void:
	_text(p + Vector2(0, -4), label, 13, Color(col, 0.9))
	draw_rect(Rect2(p + Vector2(0, 2), Vector2(w, 12)), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(p + Vector2(0, 2), Vector2(w * clampf(v, 0.0, 1.0), 12)), col)

func _button(id: String, label: String, active := false, accent := CYAN, sub := "") -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var on := held.has(id) or active
	_panel(r, Color(accent, 0.38) if on else INK, Color(accent, 0.9), 14)
	var fs := 20 if r.size.x > 140 else 17
	_text(r.position + Vector2(0, r.size.y * 0.5 + (0 if sub == "" else -4) + 7), label, fs, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sub != "": _text(r.position + Vector2(0, r.size.y * 0.5 + 24), sub, 12, Color(accent, 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _stick(center: Vector2, v: Vector2, label: String, active: bool) -> void:
	draw_circle(center, STICK_R, Color(0.02, 0.08, 0.14, 0.45 if active else 0.28))
	draw_arc(center, STICK_R, 0, TAU, 48, Color(CYAN, 0.7 if active else 0.35), 2.0, true)
	draw_circle(center + v * STICK_R, 34, Color(0.55, 0.8, 0.95, 0.8 if active else 0.4))
	_text(center + Vector2(-60, STICK_R + 22), label, 14, Color(CYAN, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 120)

func _screen(p3: Vector3) -> Variant:
	var cam: Camera3D = space.cam
	if cam.is_position_behind(p3): return null
	return cam.unproject_position(p3)

func _draw() -> void:
	if space == null or not is_instance_valid(space.player): return
	_layout()
	var cam: Camera3D = space.cam
	# nebula haze + damage vignette
	if space.in_nebula > 0.0:
		draw_rect(Rect2(Vector2.ZERO, S), Color(space.nebula_color, 0.38 * space.in_nebula))
	if damage_flash > 0.0:
		for i in 6:
			var w := 60.0 - i * 9.0
			draw_rect(Rect2(Vector2.ZERO, S), Color(RED, damage_flash * 0.08), false, w)
	# world markers: station, planet, gate
	for n in [space.station, space.planet, space.gate]:
		var pos: Vector3 = space.dock_point(n) if n != space.gate else n.global_position
		var sp = _screen(pos)
		var col := GOLD if n == space.gate else GREEN
		if sp != null and Rect2(Vector2.ZERO, S).has_point(sp):
			draw_arc(sp, 16, 0, TAU, 4, Color(col, 0.8), 2.0)
			_text(sp + Vector2(22, 6), "%s  %s" % [n.name, _dist(space.distance_to(n))], 14, Color(col, 0.95))
	# target brackets + off-screen arrow
	var t: Node3D = space.target
	if t and is_instance_valid(t):
		var tp = _screen(t.global_position)
		var tcol := RED if t.get_meta("kind", "") == "enemy" else GOLD
		if tp != null and Rect2(Vector2(40, 40), S - Vector2(80, 80)).has_point(tp):
			var s := 26.0
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var corner: Vector2 = tp + c * s
				draw_line(corner, corner - Vector2(c.x * 11, 0), tcol, 3)
				draw_line(corner, corner - Vector2(0, c.y * 11), tcol, 3)
			if t.get_meta("kind", "") == "enemy":
				var hv: float = space.target_health()
				draw_rect(Rect2(tp + Vector2(-26, 32), Vector2(52, 6)), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(tp + Vector2(-26, 32), Vector2(52 * hv, 6)), RED)
				# lead indicator
				var e: Dictionary = space._enemy_entry(t)
				if not e.is_empty():
					var d: float = space.player.global_position.distance_to(t.global_position)
					var lead: Vector3 = t.global_position + (e["vel"] as Vector3) * (d / float(GS.weapon()["speed"]))
					var lp = _screen(lead)
					if lp != null:
						draw_circle(lp, 6, Color(RED, 0.9))
						draw_line(tp, lp, Color(RED, 0.4), 1.0)
		else:
			var v: Vector3 = cam.global_basis.inverse() * (t.global_position - cam.global_position)
			var dir := Vector2(v.x, -v.y).normalized()
			if dir == Vector2.ZERO: dir = Vector2.DOWN
			var c2 := S * 0.5
			var edge := c2 + dir * minf(S.x, S.y) * 0.4
			var perp := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([edge + dir * 20, edge - dir * 8 + perp * 13, edge - dir * 8 - perp * 13]), tcol)
	# crosshair
	var c := S * 0.5
	var locked: bool = space._in_fire_cone(space.target)
	var cc := GOLD if locked else Color(WHITE, 0.85)
	draw_arc(c, 22, 0, TAU, 40, cc, 2.0, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * 14, c + d * 30, cc, 2.0)
	if locked: _text(c + Vector2(-40, -36), "IN RANGE", 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER, 80)
	# status panel (top-left)
	_panel(Rect2(14, 12, 318, 150))
	_bar(Vector2(28, 36), 180, GS.hull / GS.max_hull(), Color(0.55, 1.0, 0.55), "HULL %d" % int(GS.hull))
	_bar(Vector2(28, 70), 180, GS.shield / GS.max_shield(), CYAN, "SHIELD %d" % int(GS.shield))
	_text(Vector2(222, 38), "REPAIR", 13, Color(GREEN, 0.9))
	for i in Data.MAX_REPAIRS:
		draw_rect(Rect2(Vector2(222 + i * 19, 46), Vector2(14, 14)), GREEN if i < GS.repairs else Color(1, 1, 1, 0.15))
	_text(Vector2(222, 86), "MISSILES %d/%d" % [GS.missiles, GS.max_missiles()], 13, GOLD)
	_text(Vector2(28, 112), "%s  ·  %s" % [GS.ship()["name"].to_upper(), GS.weapon()["name"]], 15, WHITE)
	_text(Vector2(28, 140), "CREDITS  %s" % _money(GS.credits), 17, GOLD)
	# location / objective / messages (top-centre)
	var sysname: String = Data.SYSTEMS[GS.system_id]["name"].to_upper()
	var zone := ""
	if space.in_nebula > 0.0: zone = "  ·  %s NEBULA — SENSORS DEGRADED" % Data.SYSTEMS[GS.system_id]["nebula"]["name"].to_upper()
	elif space.in_belt: zone = "  ·  %s — WATCH FOR ROCKS" % Data.SYSTEMS[GS.system_id]["asteroids"]["name"].to_upper()
	_text(Vector2(0, 34), "%s SYSTEM%s" % [sysname, zone], 18, CYAN, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	if objective != "": _text(Vector2(0, 60), objective, 16, WHITE, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	if msg_t > 0.0: _text(Vector2(0, 88), msg, 17, GOLD, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	var spd := "SPEED %d" % int(space.speed_now)
	if space.cruise: spd += "  CRUISE %s" % ("ENGAGED" if space.cruise_charge >= 1.0 else "CHARGING %d%%" % int(space.cruise_charge * 100))
	if space.autopilot != null: spd += "  ·  AUTOPILOT > %s" % space.autopilot.name
	_text(Vector2(0, S.y * 0.5 + 64), spd, 15, Color(CYAN, 0.95), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	# radar (top-right)
	_radar(Vector2(S.x - 100, 100), 80.0)
	# target panel under radar
	if t and is_instance_valid(t):
		var tr := Rect2(S.x - 252, 212, 236, 74)
		_panel(tr)
		_text(tr.position + Vector2(12, 26), "TARGET", 12, Color(CYAN, 0.9))
		_text(tr.position + Vector2(12, 48), t.name, 17, RED if t.get_meta("kind", "") == "enemy" else GOLD)
		_text(tr.position + Vector2(12, 67), _dist(space.distance_to(t)), 13, WHITE)
		var th: float = space.target_health()
		if th >= 0.0:
			draw_rect(Rect2(tr.position + Vector2(96, 58), Vector2(116, 8)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(tr.position + Vector2(96, 58), Vector2(116 * th, 8)), RED)
	# controls
	_stick(move_origin, move_vec, "THRUST / STRAFE", owners.values().has("move"))
	_stick(aim_origin, aim_vec, "AIM", owners.values().has("aim"))
	_button("fire", "FIRE", false, RED, "HOLD")
	_button("missile", "MISSILE", false, GOLD, "%d LEFT" % GS.missiles)
	_button("repair", "REPAIR", false, GREEN, "%d/5" % GS.repairs)
	_button("target", "TARGET", false, CYAN, "NEXT")
	_button("auto", "AUTO" if space.auto_fire else "MANUAL", space.auto_fire, CYAN, "FIRE MODE")
	_button("nav", "MAP", false, CYAN)
	_button("cruise", "CRUISE", space.cruise, CYAN, "ON" if space.cruise else "OFF")
	_button("goto", "GO TO", space.autopilot != null, CYAN, "TARGET")
	if buttons.has("dock"):
		var dn: Node3D = space.dock_candidate()
		_button("dock", "DOCK", true, GREEN, dn.name.to_upper())
	if buttons.has("jump"): _button("jump", "JUMP", true, GOLD, "TO %s" % Data.SYSTEMS[space.sys["gate"]["to"]]["name"].to_upper())

func _radar(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(0.02, 0.07, 0.12, 0.78))
	draw_arc(c, r, 0, TAU, 48, Color(CYAN, 0.7), 2.0, true)
	draw_arc(c, r * 0.5, 0, TAU, 36, Color(CYAN, 0.2), 1.0, true)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(CYAN, 0.15))
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(CYAN, 0.15))
	var rng := 1600.0 * (1.0 - 0.6 * space.in_nebula)
	var inv: Basis = Basis(Vector3.UP, -space.yaw)
	var pp: Vector3 = space.player.global_position
	var items: Array = []
	for e in space.enemies: items.append([e["node"].global_position, RED, 3.5])
	for tr in space.traffic: items.append([tr["node"].global_position, Color(0.7, 0.8, 1.0), 3.0])
	items.append([space.station.global_position, GREEN, 5.0])
	items.append([space.planet.global_position, Color(0.5, 0.8, 1.0), 7.0])
	items.append([space.gate.global_position, GOLD, 5.0])
	for it in items:
		var rel: Vector3 = inv * (it[0] - pp)
		var v := Vector2(rel.x, rel.z) / rng * r
		var edge := v.length() > r
		if edge: v = v.normalized() * r
		draw_circle(c + v, it[2] * (0.7 if edge else 1.0), Color(it[1], 0.5 if edge else 1.0))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(-6, 6)]), WHITE)
	_text(c + Vector2(-r, r + 18), "RADAR %s" % _dist(rng), 11, Color(CYAN, 0.8), HORIZONTAL_ALIGNMENT_CENTER, r * 2)

func _dist(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)

func _money(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out + " cr"
