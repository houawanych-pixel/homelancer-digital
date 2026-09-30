extends Control
## Unified cockpit HUD (owner mockup 3): two side columns.
## Left:  SHIELD · REPAIR · ENERGY cards (icon, count, AUTO | MAN), then WARP · CALL · LOG · HANG UP.
## Right: WEAPONS · MISSILE · MINE cards, then STOP · KILL · THRUST.
## Bottom: FLIGHT stick, dashboard (SPEED · status/radar screen · WAYPOINT/SCAN), AIM stick.
## Top: title + SHIELD/HULL/ENERGY, MAP · VIEW (left of title), TARGET · GO TO (right of title).
## Each finger belongs to whatever it first touched, so dragging a stick never presses a button.

signal pressed(id: String)

const CYAN := Color(0.33, 0.8, 1.0)
const CYAN_HI := Color(0.6, 0.92, 1.0)
const BLUE := Color(0.13, 0.55, 1.0)
const PANEL := Color(0.02, 0.07, 0.14, 0.86)
const EDGE := Color(0.3, 0.72, 1.0, 0.85)
const WHITE := Color(0.94, 0.97, 1.0)
const RED := Color(1.0, 0.28, 0.25)
const GOLD := Color(1.0, 0.84, 0.3)
const GREEN := Color(0.45, 1.0, 0.55)
const YELLOW := Color(1.0, 0.92, 0.3)
const ORANGE := Color(1.0, 0.6, 0.2)

var space: SpaceSystem
var font: Font = ThemeDB.fallback_font
var owners := {} # touch index -> "move" | "aim" | button id
var origins := {}
var move_vec := Vector2.ZERO
var aim_vec := Vector2.ZERO
var buttons := {} # id -> Rect2 (touch areas)
var cards := {} # system id -> card Rect2
var held := {}
var msg := ""
var msg_t := 0.0
var damage_flash := 0.0
var objective := ""
var comms_open := false
var comms_line := ""
var comms_from := ""
var comms_mode := "" # incoming | picker | talk | log
var comms_hostile := false
var comms_timer := 0.0
var comms_face := ""        # portrait set id (assets/portraits/<face>_<expr>.png), "" = no face (waveform)
var comms_expr := "normal"
var comms_voice := 1.0
var comms_female := false
var _faces := {}
var contacts: Array = []
var history: Array = [] # recent messages and calls for LOG
var roster_t := 1.0 # drop-down animation 0..1
var roster_closing := false
var roster_idle := 0.0
var S := Vector2(1280, 720)
var stick_r := 92.0
var col_w := 140.0
var flash := {}
var t := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GS.changed.connect(queue_redraw)

func _log(line: String) -> void:
	history.push_front(line)
	if history.size() > 8: history.pop_back()

func flash_message(txt: String) -> void:
	msg = txt
	msg_t = 4.0
	_log(txt)

func hurt() -> void:
	damage_flash = 0.6

func pulse(id: String) -> void:
	flash[id] = 0.6

func open_comms(from: String, line: String, mode := "talk", hostile := false, face := "", voice := 1.0, female := false) -> void:
	comms_open = true
	comms_from = from
	comms_expr = "angry" if hostile else "normal"
	if line.begins_with("[") and line.find("]") > 0:   # "[smile]Text" picks the face for this line
		comms_expr = line.substr(1, line.find("]") - 1)
		line = line.substr(line.find("]") + 1).strip_edges()
	comms_face = face
	comms_line = line
	comms_voice = voice if face != "" else (0.8 if hostile else 1.0)
	comms_female = female
	Sfx.speak(line, comms_voice, female)
	comms_mode = mode
	comms_hostile = hostile
	comms_timer = 7.0 if mode == "incoming" else 0.0
	_log("%s: %s" % [from, line])

func open_picker(list: Array) -> void:
	contacts = list
	comms_open = true
	comms_mode = "picker"
	comms_hostile = false

func open_log() -> void:
	# LOG = pull-out tab of the people you've met; tap one to call them
	comms_open = true
	comms_mode = "roster"
	comms_hostile = false
	roster_t = 0.0
	roster_closing = false
	roster_idle = 0.0

## Compact drop-down: only as tall as the contact list, pulls down from under MAP and rolls back up.
func roster_rect() -> Rect2:
	var n := clampi(GS.met.size(), 1, 6)
	var full_h := 40.0 + n * 48.0 + 6.0
	return Rect2(col_w + 14, 62, 290, maxf(8.0, full_h * ease(roster_t, 0.35)))

func close_roster() -> void:
	roster_closing = true

func _face_tex(face: String, expr: String) -> Texture2D:
	var k := face + "_" + expr
	if not _faces.has(k):
		var path := "res://assets/portraits/%s.png" % k
		_faces[k] = load(path) if ResourceLoader.exists(path) else null
		if _faces[k] == null and expr != "normal": _faces[k] = _face_tex(face, "normal")
	return _faces[k]

func close_comms() -> void:
	if comms_open and comms_mode != "roster" and comms_mode != "picker": Sfx.hang_up()
	comms_open = false
	comms_mode = ""

# ---------------------------------------------------------------- layout
func _home(which: String) -> Vector2:
	var x := col_w + 24 + stick_r if which == "move" else S.x - col_w - 24 - stick_r
	return Vector2(x, S.y - stick_r - 28)

func _console() -> Rect2:
	var l := _home("move").x + stick_r + 14
	var r := _home("aim").x - stick_r - 14
	return Rect2(l, S.y - 150, r - l, 140)

func _comms_rect() -> Rect2:
	# like the mockup: over the dashboard, between the two sticks
	var l := _home("move").x + stick_r + 10
	var r := _home("aim").x - stick_r - 10
	var w := minf(720.0, r - l)
	return Rect2(S.x * 0.5 - w * 0.5, S.y - 272, w, 262)

func _layout() -> void:
	S = get_viewport_rect().size
	stick_r = clampf(S.y * 0.128, 80.0, 100.0)
	col_w = clampf(S.y * 0.19, 120.0, 150.0)
	buttons.clear()
	cards.clear()
	var card_h := 104.0
	var gap := 6.0
	for i in 6:
		var sysd: Dictionary = Data.SYSTEMS_UI[i]
		var left: bool = sysd["side"] == "left"
		var r := Rect2(8 if left else S.x - col_w - 8, 8 + (i % 3) * (card_h + gap), col_w, card_h)
		var id: String = sysd["id"]
		cards[id] = r
		buttons["sys_" + id] = Rect2(r.position + Vector2(6, 6), Vector2(60, 58)) # the icon push-button
		buttons["mode_%s_auto" % id] = Rect2(r.position.x + 6, r.end.y - 36, r.size.x * 0.5 - 8, 30)
		buttons["mode_%s_manual" % id] = Rect2(r.position.x + r.size.x * 0.5 + 2, r.end.y - 36, r.size.x * 0.5 - 8, 30)
	var sq := Vector2(col_w * 0.72, 74)
	var y0 := 8 + 3 * (card_h + gap) + 4
	var lids := ["log", "call", "hangup", "warp"] # phone buttons together, WARP at the bottom
	for k in lids.size(): buttons[lids[k]] = Rect2(Vector2(8, y0 + k * (sq.y + 6)), sq)
	var rids := ["stop", "kill", "thrust"]
	for k in rids.size(): buttons[rids[k]] = Rect2(Vector2(S.x - 8 - sq.x, y0 + k * (sq.y + 6)), sq)
	# top bar either side of the title
	var tb := Vector2(104, 46)
	buttons["map"] = Rect2(Vector2(col_w + 18, 10), tb)
	buttons["view"] = Rect2(Vector2(col_w + 18 + tb.x + 8, 10), tb)
	buttons["goto"] = Rect2(Vector2(S.x - col_w - 18 - tb.x, 10), tb)
	buttons["target"] = Rect2(Vector2(S.x - col_w - 18 - tb.x * 2 - 8, 10), tb)
	if space and space.controls:
		var db := Rect2(S.x * 0.5 - 130, 150, 260, 60)
		if space.dock_candidate() != null: buttons["dock"] = db
		elif space.gate_in_range(): buttons["jump"] = db
	if comms_open and comms_mode != "roster" and comms_mode != "picker":
		var cr := _comms_rect()
		buttons["voice"] = Rect2(cr.end.x - 128, cr.position.y + 10, 116, 34)
	if comms_open and comms_mode == "roster":
		var rr := roster_rect()
		if roster_t > 0.95 and not roster_closing:
			for k in mini(GS.met.size(), 6):
				buttons["met_%d" % k] = Rect2(rr.position.x + 8, rr.position.y + 40 + k * 48, rr.size.x - 16, 44)

# ---------------------------------------------------------------- input
func _input(e: InputEvent) -> void:
	if not visible or space == null: return
	if e is InputEventScreenTouch:
		_layout()
		if e.pressed:
			for id in buttons:
				if (buttons[id] as Rect2).grow(3).has_point(e.position):
					owners[e.index] = id
					held[id] = true
					if id != "sys_guns" and id != "thrust": pressed.emit(id)
					get_viewport().set_input_as_handled()
					return
			if comms_open and comms_mode == "roster":
				if roster_rect().has_point(e.position):
					owners[e.index] = "comms_body"
					return
				close_roster()
			if comms_open and comms_mode != "roster" and _comms_rect().has_point(e.position):
				owners[e.index] = "comms_body"
				return
			if e.position.y > S.y * 0.35 and e.position.x > col_w + 10 and e.position.x < S.x - col_w - 10:
				if e.position.x < S.x * 0.5 and not owners.values().has("move"):
					owners[e.index] = "move"
					origins["move"] = e.position
				elif e.position.x >= S.x * 0.5 and not owners.values().has("aim"):
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
	for k in flash.keys(): flash[k] = maxf(0.0, float(flash[k]) - dt)
	var kb := Vector2(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("back", "forward"))
	var ka := Vector2(Input.get_axis("yaw_left", "yaw_right"), Input.get_axis("pitch_up", "pitch_down"))
	space.move = Vector2(move_vec.x, -move_vec.y) if kb == Vector2.ZERO else kb
	var a := aim_vec if ka == Vector2.ZERO else ka
	space.aim = a * a.length()
	space.fire_held = held.has("sys_guns") or Input.is_action_pressed("fire")
	space.thrust_held = held.has("thrust") or Input.is_key_pressed(KEY_SHIFT)
	if comms_mode == "roster":
		if roster_closing:
			roster_t = maxf(0.0, roster_t - dt * 6.0)
			if roster_t <= 0.0: close_comms()
		else:
			roster_t = minf(1.0, roster_t + dt * 6.0)
			roster_idle += dt
			if roster_idle > 8.0: close_roster() # rolls itself back up if you don't pick anyone
	if comms_mode == "incoming":
		comms_timer -= dt
		if comms_timer <= 0.0: close_comms()
	queue_redraw()

# ---------------------------------------------------------------- drawing helpers
func _box(r: Rect2, bg := PANEL, edge := EDGE, radius := 10, bw := 2) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(CYAN, 0.18)
	sb.shadow_size = 5
	draw_style_box(sb, r)

func _text(p: Vector2, txt: String, size := 18, col := WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(font, p, txt, align, width, size, 5, Color(0, 0.03, 0.08, 0.8))
	draw_string(font, p, txt, align, width, size, col)

func _icon(id: String, c: Vector2, s: float, col: Color) -> void:
	match id:
		"shield":
			var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.85, -s * 0.62), c + Vector2(s * 0.72, s * 0.25), c + Vector2(0, s), c + Vector2(-s * 0.72, s * 0.25), c + Vector2(-s * 0.85, -s * 0.62), c + Vector2(0, -s)])
			draw_polyline(pts, col, 3.0, true)
			draw_polyline(PackedVector2Array([c + Vector2(0, -s * 0.6), c + Vector2(s * 0.5, -s * 0.36), c + Vector2(s * 0.42, s * 0.14), c + Vector2(0, s * 0.6)]), Color(col, 0.6), 2.0, true)
		"hull":
			draw_line(c + Vector2(-s * 0.7, s * 0.7), c + Vector2(s * 0.25, -s * 0.25), col, s * 0.28)
			draw_arc(c + Vector2(s * 0.45, -s * 0.45), s * 0.42, deg_to_rad(-20), deg_to_rad(250), 16, col, s * 0.2)
		"energy":
			draw_rect(Rect2(c + Vector2(-s * 0.45, -s * 0.8), Vector2(s * 0.9, s * 1.7)), col, false, 3.0)
			draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.98), Vector2(s * 0.4, s * 0.18)), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.12, -s * 0.6), c + Vector2(-s * 0.25, s * 0.08), c + Vector2(0, s * 0.08), c + Vector2(-s * 0.12, s * 0.62), c + Vector2(s * 0.25, -s * 0.08), c + Vector2(0, -s * 0.08)]), col)
		"guns":
			for dx in [-s * 0.55, 0.0, s * 0.55]:
				draw_rect(Rect2(c + Vector2(dx - s * 0.16, -s * 0.5), Vector2(s * 0.32, s * 1.3)), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(dx - s * 0.16, -s * 0.5), c + Vector2(dx, -s * 1.0), c + Vector2(dx + s * 0.16, -s * 0.5)]), col)
		"missile":
			var dir := Vector2(1, -1).normalized()
			var perp := Vector2(-dir.y, dir.x)
			draw_line(c - dir * s * 0.8, c + dir * s * 0.55, col, s * 0.36)
			draw_colored_polygon(PackedVector2Array([c + dir * s * 0.95, c + dir * s * 0.5 + perp * s * 0.19, c + dir * s * 0.5 - perp * s * 0.19]), col)
			draw_colored_polygon(PackedVector2Array([c - dir * s * 0.55 + perp * s * 0.45, c - dir * s * 0.9, c - dir * s * 0.55 - perp * s * 0.45]), col)
		"mine":
			draw_circle(c, s * 0.62, col)
			draw_rect(Rect2(c + Vector2(-s * 1.0, -s * 0.1), Vector2(s * 2.0, s * 0.2)), Color(0.02, 0.07, 0.14))
			for k in 5: draw_circle(c + Vector2(-s * 0.5 + k * s * 0.25, s * 0.3), s * 0.08, Color(0.02, 0.07, 0.14))
			draw_rect(Rect2(c + Vector2(-s * 0.12, -s * 0.95), Vector2(s * 0.24, s * 0.35)), col)
		"warp":
			for k in 3: draw_arc(c + Vector2(k * 1.5, 0), s * (0.35 + k * 0.28), deg_to_rad(40 + k * 60), deg_to_rad(330 + k * 60), 20, col, 3.0, true)
		"call":
			draw_arc(c + Vector2(s * 0.3, -s * 0.3), s * 0.85, deg_to_rad(92), deg_to_rad(178), 16, col, s * 0.42)
			draw_circle(c + Vector2(s * 0.28, s * 0.55), s * 0.3, col)
			draw_circle(c + Vector2(-s * 0.55, -s * 0.28), s * 0.3, col)
		"log":
			for k in 3:
				var hc := c + Vector2((k - 1) * s * 0.62, -s * 0.2 + (0 if k == 1 else s * 0.1))
				draw_circle(hc, s * 0.26, col)
				draw_arc(hc + Vector2(0, s * 0.62), s * 0.36, PI, TAU, 12, col, s * 0.28)
		"hangup":
			draw_arc(c + Vector2(0, s * 0.7), s * 0.95, deg_to_rad(215), deg_to_rad(325), 18, RED, s * 0.42)
			draw_circle(c + Vector2(-s * 0.8, s * 0.2), s * 0.3, RED)
			draw_circle(c + Vector2(s * 0.8, s * 0.2), s * 0.3, RED)
		"stop":
			draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.6), Vector2(s * 1.2, s * 1.2)), col)
		"kill":
			draw_circle(c, s * 0.55, col, false, 3.0)
			for k in 4:
				var ang := k * PI / 2.0 + t * 0.0
				draw_line(c + Vector2(cos(ang), sin(ang)) * s * 0.55, c + Vector2(cos(ang), sin(ang)) * s * 0.9, col, 3.0)
			draw_line(c + Vector2(-s, -s * 0.9), c + Vector2(s, s * 0.9), RED, 3.0)
		"thrust":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.55, -s * 0.1), c + Vector2(s * 0.6, s * 0.45), c + Vector2(0, s * 0.95), c + Vector2(-s * 0.6, s * 0.45), c + Vector2(-s * 0.4, -s * 0.2)]), ORANGE)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.3), c + Vector2(s * 0.3, s * 0.3), c + Vector2(0, s * 0.8), c + Vector2(-s * 0.3, s * 0.3)]), YELLOW)

func _card(id: String) -> void:
	var r: Rect2 = cards[id]
	var lit := float(flash.get(id, 0.0)) > 0.0 or held.has("sys_" + id)
	var locked: bool = space.warp_active() and id in ["guns", "missile", "mine"]
	_box(r, Color(0.07, 0.22, 0.38, 0.95) if lit else PANEL, CYAN_HI if lit else EDGE, 12, 2)
	# icon push-button: raised face, darker when pressed — tap to use now (hold for weapons)
	var ib: Rect2 = buttons["sys_" + id]
	var down := held.has("sys_" + id)
	if not down: _box(Rect2(ib.position + Vector2(0, 3), ib.size), Color(0.0, 0.03, 0.07, 1.0), Color(0, 0, 0, 0), 9, 0)
	var face := Rect2(ib.position + (Vector2(0, 3) if down else Vector2.ZERO), ib.size)
	_box(face, Color(BLUE, 0.9) if down else Color(0.1, 0.3, 0.5, 1.0), CYAN_HI, 9, 2)
	draw_rect(Rect2(face.position + Vector2(4, 3), Vector2(face.size.x - 8, 2)), Color(1, 1, 1, 0.25))
	_icon(id, face.get_center() + Vector2(0, -3), 17.0, WHITE)
	_text(Vector2(face.position.x, face.end.y - 4), "HOLD" if id == "guns" else "PUSH", 9, Color(CYAN_HI, 0.9), HORIZONTAL_ALIGNMENT_CENTER, face.size.x)
	var count := ""
	var label: String = {"shield": "SHIELD", "hull": "REPAIR", "energy": "ENERGY", "guns": "WEAPONS", "missile": "MISSILE", "mine": "MINE"}[id]
	var n := 0
	match id:
		"shield": n = GS.shield_charges; count = str(n)
		"hull": n = GS.repairs; count = str(n)
		"energy": n = GS.energy_cells; count = str(n)
		"guns": n = 1; count = "∞"
		"missile": n = GS.missiles; count = "%02d" % n
		"mine": n = GS.mines; count = "%02d" % n
	var cx := r.position.x + 68.0 + (r.size.x - 68.0) * 0.5
	if id == "guns":
		# infinity sign drawn (the default font lacks the glyph)
		var ic := Vector2(cx, r.position.y + 26)
		draw_arc(ic + Vector2(-9, 0), 9, 0, TAU, 20, WHITE, 3.0, true)
		draw_arc(ic + Vector2(9, 0), 9, 0, TAU, 20, WHITE, 3.0, true)
	else:
		_text(Vector2(cx - 40, r.position.y + 38), count, 32, WHITE if n > 0 else RED, HORIZONTAL_ALIGNMENT_CENTER, 80)
	_text(Vector2(cx - 40, r.position.y + 60), label, 12 if label.length() > 6 else 14, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 80)
	# AUTO | MAN split toggle
	var ra: Rect2 = buttons["mode_%s_auto" % id]
	var rm: Rect2 = buttons["mode_%s_manual" % id]
	var auto := GS.is_auto(id)
	var bar := ra.merge(rm)
	_box(bar, Color(0.02, 0.06, 0.12, 1.0), Color(CYAN, 0.55), 7, 1)
	if auto: _box(ra, Color(BLUE, 0.95), Color(CYAN_HI, 0.9), 7, 1)
	else: _box(rm, Color(BLUE, 0.95), Color(CYAN_HI, 0.9), 7, 1)
	_text(Vector2(ra.position.x, ra.position.y + 21), "AUTO", 14, WHITE if auto else Color(0.7, 0.78, 0.86), HORIZONTAL_ALIGNMENT_CENTER, ra.size.x)
	_text(Vector2(rm.position.x, rm.position.y + 21), "MAN", 14, WHITE if not auto else Color(0.7, 0.78, 0.86), HORIZONTAL_ALIGNMENT_CENTER, rm.size.x)
	draw_line(Vector2(bar.get_center().x, bar.position.y + 6), Vector2(bar.get_center().x, bar.end.y - 6), Color(1, 1, 1, 0.3), 1.0)
	var cd := 0.0
	if id == "shield": cd = space.shield_cd / Data.SHIELD_BOOST_COOLDOWN
	if id == "energy": cd = space.energy_cd / Data.ENERGY_BOOST_COOLDOWN
	if cd > 0.0: draw_arc((buttons["sys_" + id] as Rect2).get_center(), 27, -PI / 2, -PI / 2 + TAU * (1.0 - cd), 28, CYAN_HI, 3.0)
	if locked:
		draw_rect(r, Color(0, 0, 0, 0.6))
		_text(Vector2(r.position.x, r.position.y + 58), "LOCKED", 18, GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _square(id: String, label: String, active := false, col := CYAN, sub := "") -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var on := held.has(id) or active
	_box(r, Color(col, 0.32) if on else PANEL, Color(col, 0.95) if on else EDGE, 10, 2)
	_icon(id, r.position + Vector2(r.size.x * 0.5, 28), 15.0, col if id != "hangup" else RED)
	_text(Vector2(r.position.x, r.end.y - (20 if sub != "" else 10)), label, 15, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sub != "": _text(Vector2(r.position.x, r.end.y - 5), sub, 10, Color(col.lightened(0.3), 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _pill(id: String, label: String, active := false, col := CYAN, sub := "") -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var on := held.has(id) or active
	_box(r, Color(col, 0.35) if on else PANEL, Color(col, 0.95 if on else 0.65), 10, 2)
	var y := r.size.y * 0.5 + (6.0 if sub == "" else 0.0)
	_text(r.position + Vector2(0, y), label, 16, WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	if sub != "": _text(r.position + Vector2(0, y + 15), sub, 11, Color(col.lightened(0.2), 0.95), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

func _stick(which: String, label: String) -> void:
	var active := owners.values().has(which)
	var c: Vector2 = origins.get(which, _home(which))
	var v := move_vec if which == "move" else aim_vec
	draw_circle(c, stick_r + 8, Color(0.0, 0.05, 0.1, 0.35))
	draw_circle(c, stick_r, Color(0.02, 0.1, 0.2, 0.62 if active else 0.5))
	draw_arc(c, stick_r, 0, TAU, 64, CYAN, 4.0, true)
	draw_arc(c, stick_r - 9, 0, TAU, 64, Color(CYAN, 0.3), 2.0, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tip: Vector2 = c + d * stick_r * 0.78
		var perp := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([tip + d * 9, tip - d * 5 + perp * 9, tip - d * 5 - perp * 9]), CYAN_HI)
	var knob := c + v * stick_r * 0.6
	draw_circle(knob, stick_r * 0.34, Color(0.62, 0.8, 0.97, 0.95 if active else 0.85))
	draw_arc(knob, stick_r * 0.34, 0, TAU, 40, WHITE, 3.0, true)
	_text(c + Vector2(-60, stick_r * 0.72), label, 16, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 120)

func _screen(p3: Vector3) -> Variant:
	var cam: Camera3D = space.cam
	if cam.is_position_behind(p3): return null
	return cam.unproject_position(p3)

# ---------------------------------------------------------------- cockpit frame
func _cockpit() -> void:
	var w := S.x
	var h := S.y
	var shell := Color(0.5, 0.54, 0.6)
	var shell_lt := Color(0.72, 0.75, 0.8)
	var metal := Color(0.13, 0.15, 0.2)
	var orange := Color(1.0, 0.62, 0.2)
	for side in [-1.0, 1.0]:
		var x0: float = w * 0.5 + side * (w * 0.5 - col_w - 8)
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x0 - side * 26, 0), Vector2(x0 - side * w * 0.1, h * 0.62), Vector2(x0 - side * w * 0.06, h * 0.64), Vector2(x0, h * 0.3)]), shell)
		draw_line(Vector2(x0 - side * 16, h * 0.02), Vector2(x0 - side * w * 0.085, h * 0.6), Color(orange, 0.95), 4)
	var top := h * 0.66
	draw_colored_polygon(PackedVector2Array([Vector2(col_w, h * 0.72), Vector2(w * 0.3, top), Vector2(w * 0.7, top), Vector2(w - col_w, h * 0.72), Vector2(w - col_w, h), Vector2(col_w, h)]), shell_lt)
	draw_colored_polygon(PackedVector2Array([Vector2(col_w + 20, h * 0.76), Vector2(w * 0.32, top + 18), Vector2(w * 0.68, top + 18), Vector2(w - col_w - 20, h * 0.76), Vector2(w - col_w - 20, h), Vector2(col_w + 20, h)]), metal)
	for side in [-1.0, 1.0]:
		for k in 3:
			var cx: float = w * 0.5 + side * (w * 0.12 + k * w * 0.07)
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 26, top + 30 + k * 6), Vector2(cx + 26, top + 26 + k * 6), Vector2(cx + 22, top + 42 + k * 6), Vector2(cx - 30, top + 46 + k * 6)]), Color(0.2, 0.6, 1.0, 0.85) if k != 1 else Color(orange, 0.9))

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
		if sp != null and Rect2(Vector2(col_w, 0), Vector2(S.x - col_w * 2, S.y)).has_point(sp):
			draw_arc(sp, 14, 0, TAU, 4, Color(col, 0.85), 2.0)
			_text(sp + Vector2(20, 6), "%s  %s" % [n.name, _dist(space.distance_to(n))], 14, Color(col, 0.95))
	for tr in space.traffic:
		var tp0 = _screen(tr["node"].global_position)
		if tp0 != null and space.player.global_position.distance_to(tr["node"].global_position) < 900.0:
			_brackets(tp0, 18.0, Color(GREEN, 0.85))
	# off-screen hostiles: red arrows at the view edge; friendlies green
	var view := Rect2(Vector2(col_w + 30, 40), Vector2(S.x - col_w * 2 - 60, S.y - 80))
	for e in space.enemies:
		_edge_arrow(e["node"].global_position, RED, view, e["node"] == space.target)
		if e["node"] == space.target: continue
		var ep = _screen(e["node"].global_position)
		var edist: float = space.player.global_position.distance_to(e["node"].global_position)
		if ep != null and view.has_point(ep) and edist < 900.0:
			_enemy_bars(ep + Vector2(-22, -30), 44.0, 4.0, e)
	for pu in space.popups:
		var pp = _screen(pu["pos"])
		if pp != null:
			var a: float = clampf(pu["life"] / 0.9, 0.0, 1.0)
			_text(pp - Vector2(30, 0), pu["text"], 18, Color(pu["col"], a), HORIZONTAL_ALIGNMENT_CENTER, 60)
	var tgt: Node3D = space.target
	if tgt and is_instance_valid(tgt):
		var tp = _screen(tgt.global_position)
		var tcol := RED if tgt.get_meta("kind", "") == "enemy" else GOLD
		if tp != null and view.has_point(tp):
			_brackets(tp, 30.0, tcol)
			if tgt.get_meta("kind", "") == "enemy":
				var e2: Dictionary = space._enemy_entry(tgt)
				if not e2.is_empty(): _enemy_bars(tp + Vector2(-40, 38), 80.0, 7.0, e2, true)
				if not e2.is_empty():
					var d: float = space.player.global_position.distance_to(tgt.global_position)
					var lp = _screen(tgt.global_position + (e2["vel"] as Vector3) * (d / float(GS.weapon()["speed"])))
					if lp != null:
						draw_arc(lp, 11, 0, TAU, 24, Color(RED, 0.95), 2.0)
						draw_line(lp + Vector2(-5, 0), lp + Vector2(5, 0), RED, 2)
						draw_line(lp + Vector2(0, -5), lp + Vector2(0, 5), RED, 2)
		elif tgt.get_meta("kind", "") != "enemy":
			_edge_arrow(tgt.global_position, GOLD, view, true)
	if space.warp_state == "on":
		var cc0 := S * 0.5
		for i in 48:
			var a := i * 2.399 + t * 0.4
			var ph := fmod(i * 0.137 + t * 1.8, 1.0)
			var d0 := Vector2(cos(a), sin(a))
			var r0 := 60.0 + ph * ph * S.x * 0.6
			draw_line(cc0 + d0 * r0, cc0 + d0 * (r0 + 30 + 160 * ph), Color(0.75, 0.85, 1.0, 0.55 * ph), 1.5 + 2.0 * ph)
	if cockpit: _cockpit()
	# reticle
	var c := S * 0.5
	var locked: bool = space._in_fire_cone(space.target)
	var rc2 := RED if locked else WHITE
	draw_arc(c, 32, 0, TAU, 48, Color(rc2, 0.95), 2.5, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * 20, c + d * 52, Color(rc2, 0.95), 2.5)
	draw_circle(c, 4, rc2)
	# top centre readout
	_text(Vector2(0, 32), "HOMELANCER", 24, WHITE, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	for side in [-1.0, 1.0]:
		for k in 3:
			var y := 20.0 + k * 5
			var x0: float = S.x * 0.5 + side * (96 + k * 4)
			draw_line(Vector2(x0, y), Vector2(x0 + side * (40 - k * 9), y), Color(CYAN_HI, 0.95), 3)
	var vals := [["SHIELD", GS.shield / GS.max_shield(), CYAN], ["HULL", GS.hull / GS.max_hull(), GREEN], ["ENERGY", GS.energy / Data.ENERGY_MAX, YELLOW]]
	for k in 3:
		var x: float = S.x * 0.5 + (k - 1) * 140.0 - 70.0
		_text(Vector2(x, 58), vals[k][0], 17, vals[k][2], HORIZONTAL_ALIGNMENT_CENTER, 140)
		var pct := int(round(clampf(vals[k][1], 0.0, 1.0) * 100.0))
		_text(Vector2(x, 94), "%d%%" % pct, 34, vals[k][2] if pct > 25 else RED, HORIZONTAL_ALIGNMENT_CENTER, 140)
	var line2 := objective
	if msg_t > 0.0: line2 = msg
	_text(Vector2(col_w, 124), line2, 15, GOLD if msg_t > 0.0 else WHITE, HORIZONTAL_ALIGNMENT_CENTER, S.x - col_w * 2)
	var zone := ""
	if space.in_nebula > 0.0: zone = "%s NEBULA — SENSORS DEGRADED" % Data.SYSTEMS[GS.system_id]["nebula"]["name"].to_upper()
	elif space.in_belt: zone = "%s — WATCH FOR ROCKS" % Data.SYSTEMS[GS.system_id]["asteroids"]["name"].to_upper()
	if zone != "": _text(Vector2(col_w, 144), zone, 14, CYAN_HI, HORIZONTAL_ALIGNMENT_CENTER, S.x - col_w * 2)
	# columns
	for id in ["shield", "hull", "energy", "guns", "missile", "mine"]: _card(id)
	var wsub := ""
	if space.warp_state == "charging": wsub = "%d%%" % int(space.warp_t / Data.WARP_CHARGE * 100)
	elif space.warp_state == "on": wsub = "DROP OUT"
	_square("warp", "WARP", space.warp_state != "off", Color(0.62, 0.55, 1.0), wsub)
	if space.warp_state == "charging":
		var wr: Rect2 = buttons["warp"]
		draw_rect(Rect2(wr.position + Vector2(6, wr.size.y - 4), Vector2((wr.size.x - 12) * space.warp_t / Data.WARP_CHARGE, 3)), Color(0.8, 0.75, 1.0))
	_square("call", "CALL", comms_mode == "talk", GREEN)
	_square("log", "LOG", comms_mode == "roster", CYAN, "CONTACTS")
	_square("hangup", "HANG UP", false, RED)
	_square("stop", "STOP", space.braking, CYAN)
	_square("kill", "KILL", space.engine_kill, GOLD, "DRIFTING" if space.engine_kill else "")
	_square("thrust", "THRUST", space.boosting, ORANGE)
	_pill("map", "MAP")
	_pill("view", "CHASE" if cockpit else "COCKPIT", false, CYAN, "VIEW")
	_pill("target", "TARGET", false, CYAN, "NEXT")
	_pill("goto", "GO TO", space.autopilot != null, CYAN, "AUTO")
	if buttons.has("dock"): _pill("dock", "DOCK", true, GREEN, space.dock_candidate().name.to_upper())
	if buttons.has("jump"): _pill("jump", "JUMP", true, GOLD, "TO %s" % Data.SYSTEMS[space.sys["gate"]["to"]]["name"].to_upper())
	_dashboard()
	_stick("move", "FLIGHT")
	_stick("aim", "AIM")
	if comms_open: _comms()
	if damage_flash > 0.0:
		for i in 6: draw_rect(Rect2(Vector2.ZERO, S), Color(RED, damage_flash * 0.08), false, 60.0 - i * 9.0)

func _hull_col(k: float) -> Color:
	return GREEN.lerp(YELLOW, clampf((0.75 - k) / 0.35, 0, 1)).lerp(RED, clampf((0.4 - k) / 0.3, 0, 1))

## Shield (cyan) over hull (green -> red) bars for one enemy.
func _enemy_bars(p: Vector2, w: float, h: float, e: Dictionary, labels := false) -> void:
	var shk: float = float(e["sh"]) / maxf(1.0, float(e["sh_max"]))
	var hk: float = clampf(float(e["hp"]) / float(e["max"]), 0.0, 1.0)
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, h * 2 + 5)), Color(0, 0, 0, 0.55))
	if float(e["sh_max"]) > 0.0:
		draw_rect(Rect2(p, Vector2(w * shk, h)), CYAN_HI)
	draw_rect(Rect2(p + Vector2(0, h + 2), Vector2(w * hk, h)), _hull_col(hk))
	if labels:
		_text(p + Vector2(w + 6, h + 1), "SH %d" % roundi(float(e["sh"])), 12, CYAN_HI)
		_text(p + Vector2(w + 6, h * 2 + 12), "HULL %d" % roundi(float(e["hp"])), 12, _hull_col(hk))

func _edge_arrow(p3: Vector3, col: Color, view: Rect2, big: bool) -> void:
	var sp = _screen(p3)
	if sp != null and view.has_point(sp): return
	var cam: Camera3D = space.cam
	var v: Vector3 = cam.global_basis.inverse() * (p3 - cam.global_position)
	var dir := Vector2(v.x, -v.y).normalized()
	if dir == Vector2.ZERO: dir = Vector2.DOWN
	var half := view.size * 0.5
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var at := view.get_center() + dir * k
	var perp := Vector2(-dir.y, dir.x)
	var s := 16.0 if big else 11.0
	draw_colored_polygon(PackedVector2Array([at + dir * s * 1.2, at - dir * s * 0.6 + perp * s, at - dir * s * 0.6 - perp * s]), col)

func _brackets(p: Vector2, s: float, col: Color) -> void:
	for cr in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner: Vector2 = p + cr * s
		draw_line(corner, corner - Vector2(cr.x * s * 0.45, 0), col, 3)
		draw_line(corner, corner - Vector2(0, cr.y * s * 0.45), col, 3)

# ---------------------------------------------------------------- dashboard: SPEED · status/radar · WAYPOINT
func _dashboard() -> void:
	var cr := _console()
	var sw := clampf(cr.size.x * 0.3, 120.0, 190.0)
	var mid := clampf(cr.size.x * 0.34, 150.0, 220.0)
	var speed_r := Rect2(cr.get_center().x - mid * 0.5 - 10 - sw, cr.position.y + 26, sw, 76)
	var screen_r := Rect2(cr.get_center().x - mid * 0.5, cr.position.y, mid, cr.size.y)
	var way_r := Rect2(cr.get_center().x + mid * 0.5 + 10, cr.position.y + 26, sw, 86)
	_box(speed_r, PANEL, EDGE, 10, 2)
	_text(Vector2(speed_r.position.x, speed_r.position.y + 26), "SPEED", 16, CYAN_HI, HORIZONTAL_ALIGNMENT_CENTER, speed_r.size.x)
	_text(Vector2(speed_r.position.x, speed_r.position.y + 60), "%d m/s" % int(space.speed_now), 26, WHITE, HORIZONTAL_ALIGNMENT_CENTER, speed_r.size.x)
	var mode := ""
	if space.warp_state == "on": mode = "WARP"
	elif space.warp_state == "charging": mode = "WARP CHARGING"
	elif space.engine_kill: mode = "DRIFT"
	elif space.braking: mode = "STOPPING"
	elif space.boosting: mode = "THRUST"
	if mode != "": _text(Vector2(speed_r.position.x, speed_r.end.y + 16), mode, 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER, speed_r.size.x)
	# centre screen: radar with your ship silhouette
	_box(screen_r, Color(0.01, 0.06, 0.12, 0.95), Color(CYAN, 0.9), 12, 2)
	var rc := screen_r.get_center() + Vector2(0, 4)
	var rr := minf(screen_r.size.x, screen_r.size.y) * 0.44
	draw_arc(rc, rr, 0, TAU, 48, Color(CYAN, 0.35), 1.5, true)
	draw_arc(rc, rr * 0.5, 0, TAU, 36, Color(CYAN, 0.2), 1.0, true)
	draw_line(rc + Vector2(0, -rr), rc + Vector2(0, rr), Color(CYAN, 0.15))
	draw_line(rc + Vector2(-rr, 0), rc + Vector2(rr, 0), Color(CYAN, 0.15))
	var sweep := fmod(t * 1.4, TAU)
	draw_line(rc, rc + Vector2(cos(sweep), sin(sweep)) * rr, Color(CYAN, 0.3), 2.0)
	var rng := 1600.0 * (1.0 - 0.6 * space.in_nebula)
	var inv := Basis(Vector3.UP, -space.yaw)
	var pp: Vector3 = space.player.global_position
	var items: Array = []
	for e in space.enemies: items.append([e["node"].global_position, RED])
	for tr in space.traffic: items.append([tr["node"].global_position, GREEN])
	items.append([space.station.global_position, GREEN])
	items.append([space.planet.global_position, Color(0.5, 0.8, 1.0)])
	items.append([space.gate.global_position, GOLD])
	for it in items:
		var rel: Vector3 = inv * (it[0] - pp)
		var v := Vector2(rel.x, rel.z) / rng * rr
		if v.length() > rr: v = v.normalized() * rr
		draw_colored_polygon(PackedVector2Array([rc + v + Vector2(0, -5), rc + v + Vector2(4, 4), rc + v + Vector2(-4, 4)]), it[1])
	var hullc := GREEN.lerp(RED, 1.0 - GS.hull / GS.max_hull())
	var sil := PackedVector2Array([rc + Vector2(0, -16), rc + Vector2(4, -6), rc + Vector2(15, 6), rc + Vector2(4, 5), rc + Vector2(3, 12), rc + Vector2(-3, 12), rc + Vector2(-4, 5), rc + Vector2(-15, 6), rc + Vector2(-4, -6)])
	draw_colored_polygon(sil, Color(hullc, 0.9))
	draw_polyline(sil + PackedVector2Array([sil[0]]), WHITE, 1.5, true)
	_text(Vector2(screen_r.position.x, screen_r.end.y - 6), "RADAR %s" % _dist(rng), 10, Color(CYAN, 0.8), HORIZONTAL_ALIGNMENT_CENTER, screen_r.size.x)
	# waypoint: autopilot destination, else the current target
	_box(way_r, PANEL, EDGE, 10, 2)
	var wp: Node3D = space.autopilot if space.autopilot != null else space.target
	var dcol := GOLD
	if wp and is_instance_valid(wp):
		if wp.get_meta("kind", "") == "enemy": dcol = RED
		var dia := way_r.position + Vector2(20, 24)
		draw_colored_polygon(PackedVector2Array([dia + Vector2(0, -9), dia + Vector2(9, 0), dia + Vector2(0, 9), dia + Vector2(-9, 0)]), dcol)
		_text(way_r.position + Vector2(36, 22), "WAYPOINT" if space.autopilot != null else "TARGET", 12, CYAN_HI)
		_text(way_r.position + Vector2(36, 44), _dist(space.distance_to(wp)), 20, WHITE)
		_text(way_r.position + Vector2(12, 62), wp.name, 11, dcol, HORIZONTAL_ALIGNMENT_LEFT, way_r.size.x - 20)
		var th: float = space.target_health()
		if wp == space.target and th >= 0.0:
			var ts: float = space.target_shield()
			var bw := way_r.size.x - 24
			if ts >= 0.0:
				draw_rect(Rect2(way_r.position + Vector2(12, 64), Vector2(bw, 3)), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(way_r.position + Vector2(12, 64), Vector2(bw * ts, 3)), CYAN_HI)
			draw_rect(Rect2(way_r.position + Vector2(12, 68), Vector2(bw, 4)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(way_r.position + Vector2(12, 68), Vector2(bw * th, 4)), _hull_col(th))
	else:
		_text(way_r.position + Vector2(12, 34), "NO WAYPOINT", 13, Color(1, 1, 1, 0.6))
	var scan := "NORMAL"
	var scol := GREEN
	if space.in_nebula > 0.0:
		scan = "DEGRADED"
		scol = GOLD
	elif space.hostiles_near(900.0) > 0:
		scan = "%d HOSTILE" % space.hostiles_near(900.0)
		scol = RED
	_text(way_r.position + Vector2(12, 82), "SCAN  " + scan, 12, scol)

# ---------------------------------------------------------------- intercom panel
func _comms() -> void:
	if comms_mode == "roster":
		_roster()
		return
	var r := _comms_rect()
	var accent := RED if comms_hostile else CYAN_HI
	_box(r, Color(0.02, 0.08, 0.16, 0.94), accent, 14, 3)
	if comms_mode == "roster":
		_roster()
		return
	var card := Rect2(r.position + Vector2(14, 14), Vector2(r.size.y - 28, r.size.y - 28))
	_box(card, Color(0.18, 0.04, 0.05, 1.0) if comms_hostile else Color(0.05, 0.14, 0.24, 1.0), Color(accent, 0.5), 12, 2)
	var cc := card.get_center()
	var tex: Texture2D = _face_tex(comms_face, comms_expr) if comms_face != "" else null
	if tex:
		# portrait: bobs and brightens with each spoken syllable, with a faint radio scanline
		var talk: float = Sfx.talking
		var inner := card.grow(-5)
		var bob := Vector2(0, -2.0 * talk)
		draw_texture_rect(tex, Rect2(inner.position + bob, inner.size), false, Color(1, 1, 1).lerp(Color(1.12, 1.12, 1.12), talk))
		for k in int(inner.size.y / 4.0):
			draw_line(Vector2(inner.position.x, inner.position.y + k * 4), Vector2(inner.end.x, inner.position.y + k * 4), Color(0, 0.1, 0.2, 0.12), 1)
		var sy := fmod(t * 60.0, inner.size.y)
		draw_line(Vector2(inner.position.x, inner.position.y + sy), Vector2(inner.end.x, inner.position.y + sy), Color(accent, 0.18), 3)
		_box(Rect2(inner.position, inner.size), Color(0, 0, 0, 0), Color(accent, 0.7), 8, 2)
		# little voice meter along the bottom of the portrait
		for i in 14:
			var hh := 3.0 + 12.0 * talk * absf(sin(t * 23.0 + i * 1.3))
			var xx := inner.position.x + 10 + i * (inner.size.x - 20) / 13.0
			draw_line(Vector2(xx, inner.end.y - 6 - hh), Vector2(xx, inner.end.y - 6), Color(accent, 0.9), 3)
	else:
		draw_arc(cc, card.size.x * 0.34, 0, TAU, 48, Color(accent, 0.5), 2.0, true)
		for i in 21:
			var hgt := 8.0 + 30.0 * absf(sin(t * 7.0 + i * 0.9)) * (0.4 + 0.6 * absf(sin(i * 0.45))) * (0.35 + 0.65 * Sfx.talking)
			var x := cc.x - 60 + i * 6
			draw_line(Vector2(x, cc.y - hgt * 0.5), Vector2(x, cc.y + hgt * 0.5), accent, 3)
	var tx := card.end.x + 20
	var parts := comms_from.split(" — ", true, 1)
	var nm := parts[0].to_upper()
	var name_w := r.end.x - tx - 140
	var fs := 26
	while fs > 15 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > name_w: fs -= 1
	_text(Vector2(tx, r.position.y + 42), nm, fs, WHITE)
	if parts.size() > 1: _text(Vector2(tx, r.position.y + 61), parts[1], 13, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 16)
	draw_circle(Vector2(tx + 8, r.position.y + 78), 6, RED if comms_hostile else GREEN)
	var status := "INCOMING CALL" if comms_mode == "incoming" else "COMMS · LIVE"
	if comms_hostile: status += " · HOSTILE"
	_text(Vector2(tx + 22, r.position.y + 85), status, 15, accent)
	var line_r := Rect2(Vector2(tx - 4, r.position.y + 96), Vector2(r.end.x - tx - 12, 96))
	_box(line_r, Color(0.03, 0.1, 0.2, 1.0), Color(accent, 0.5), 10, 2)
	draw_multiline_string_outline(font, line_r.position + Vector2(14, 28), comms_line, HORIZONTAL_ALIGNMENT_LEFT, line_r.size.x - 24, 17, 3, 4, Color(0, 0.03, 0.08, 0.75))
	draw_multiline_string(font, line_r.position + Vector2(14, 28), comms_line, HORIZONTAL_ALIGNMENT_LEFT, line_r.size.x - 24, 17, 3, WHITE)
	if comms_mode == "incoming":
		_text(Vector2(line_r.position.x, r.end.y - 18), "Closes by itself · HANG UP to end now", 13, Color(1, 1, 1, 0.6))
	if buttons.has("voice"):
		_pill("voice", "VOICE", false, accent, "READ ALOUD" if Sfx.voice_mode == "read" else "RADIO MUMBLE")

func _dist(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)

## LOG drop-down: everyone you've met, with their mood; tap to call.
func _roster() -> void:
	var r := roster_rect()
	_box(r, Color(0.02, 0.07, 0.14, 0.94), CYAN_HI, 10, 2)
	if r.size.y < 36.0: return
	_text(r.position + Vector2(12, 26), "CONTACTS", 16, WHITE)
	_text(r.position + Vector2(0, 26), "TAP TO CALL", 11, CYAN_HI, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12)
	if GS.met.is_empty():
		if r.size.y > 70: _text(r.position + Vector2(12, 64), "Nobody yet — people you meet appear here.", 12, Color(1, 1, 1, 0.7))
		return
	for k in mini(GS.met.size(), 6):
		var br := Rect2(r.position.x + 8, r.position.y + 40 + k * 48, r.size.x - 16, 44)
		if br.end.y > r.end.y: break
		var id: String = GS.met[k]
		var c: Dictionary = Data.CHARACTERS[id]
		var m: String = GS.mood.get(id, "neutral")
		var mc: Color = {"friendly": GREEN, "neutral": CYAN_HI, "enraged": RED}[m]
		var down := held.has("met_%d" % k)
		_box(br, Color(mc, 0.25) if down else Color(0.05, 0.13, 0.23, 1.0), Color(mc, 0.7), 8, 1)
		var pc := br.position + Vector2(24, 22)
		draw_circle(pc, 16, Color(c["color"], 0.9))
		var parts: PackedStringArray = (c["name"] as String).replace(".", "").split(" ")
		var ini := (parts[0].substr(0, 1) + parts[parts.size() - 1].substr(0, 1)).to_upper()
		_text(pc + Vector2(-20, 5), ini, 13, Color(0.02, 0.05, 0.1), HORIZONTAL_ALIGNMENT_CENTER, 40)
		_text(Vector2(br.position.x + 48, br.position.y + 20), c["name"], 15, WHITE)
		_text(Vector2(br.position.x + 48, br.position.y + 37), c["role"], 11, Color(0.8, 0.88, 0.95))
		_text(Vector2(br.position.x, br.position.y + 20), m.to_upper(), 10, mc, HORIZONTAL_ALIGNMENT_RIGHT, br.size.x - 8)
