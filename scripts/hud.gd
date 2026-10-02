extends Control
## Freelancer-style mobile HUD (owner's layout, Sept 30): two mirrored button blocks in the top corners.
## Top left:  SHIELD · REPAIR · TRACTOR, and under them STOP · WARP.
## Top right: three weapon slots (default LIGHT MISSILE · HEAVY MISSILE · MINE), and under them THRUST · KILL.
## Top centre: colour bars for SHIELD / HULL / ENERGY (no numbers), then MAP · VIEW · LOG · CALL · TARGET · GO TO.
## Bottom: FLIGHT stick, dashboard (SPEED · radar · WAYPOINT/SCAN), AIM stick. Lasers fire on their own.
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
var btn := 94.0 # corner button size
var log_rect := Rect2()
var held := {}
var msg := ""
var msg_t := 0.0
var damage_flash := 0.0
var objective := ""
var comms_open := false
var comms_line := ""
var comms_from := ""
var comms_mode := "" # incoming | talk | roster (= comms console open) | picker
var comms_hostile := false
## Side comms screens: "l" = enemies, "r" = friendlies. Both can be on at once. Each slot: from, line, face, expr,
## voice, female, hostile, mode (incoming | talk), timer, generic, anim (slide-in 0..1). Empty = closed.
var slots := {"l": {}, "r": {}}
var _last := "r"
var console_open := false
signal typed(text: String)
var _typer: LineEdit
## Seconds left on the newest incoming line (kept as one value for older callers).
var comms_timer: float:
	get: return float(slots[_last].get("timer", 0.0)) if not slots[_last].is_empty() else 0.0
	set(v):
		if not slots[_last].is_empty(): slots[_last]["timer"] = v
var comms_face := ""        # portrait set id (assets/portraits/<face>_<expr>.png), "" = no face (waveform)
var comms_expr := "normal"
var comms_voice := 1.0
var comms_female := false
var comms_generic := false   # a generic enemy pilot (face "gp/<id>") is on the line
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
	# typing box for the comms console (phones get their on-screen keyboard)
	_typer = LineEdit.new()
	_typer.visible = false
	_typer.placeholder_text = "Type a message…"
	_typer.max_length = 120
	_typer.add_theme_font_size_override("font_size", 18)
	add_child(_typer)
	_typer.text_submitted.connect(func(txt: String):
		_typer.visible = false
		_typer.release_focus()
		txt = txt.strip_edges()
		_typer.text = ""
		if txt != "":
			_log("YOU: " + txt)
			typed.emit(txt))

func _log(line: String) -> void:
	history.push_front(line)
	if history.size() > 30: history.pop_back()

func flash_message(txt: String) -> void:
	msg = txt
	msg_t = 4.0
	_log(txt)

func hurt() -> void:
	damage_flash = 0.6

func pulse(id: String) -> void:
	flash[id] = 0.6

## A voice on the radio. Enemies appear on the LEFT side screen, friendlies on the RIGHT; one of each can be on
## at the same time. Placing a call closes the comms console.
func open_comms(from: String, line: String, mode := "talk", hostile := false, face := "", voice := 1.0, female := false) -> void:
	var expr := "angry" if hostile else "normal"
	if line.begins_with("[") and line.find("]") > 0:   # "[smile]Text" picks the face for this line
		expr = line.substr(1, line.find("]") - 1)
		line = line.substr(line.find("]") + 1).strip_edges()
	var side := "l" if hostile else "r"
	var old: Dictionary = slots[side]
	var v := voice if face != "" else (0.8 if hostile else 1.0)
	slots[side] = {"from": from, "line": line, "face": face, "expr": expr, "voice": v, "female": female, "hostile": hostile,
		"mode": mode, "timer": 7.0 if mode == "incoming" else 0.0, "generic": face.begins_with("gp/"),
		"anim": float(old.get("anim", 0.0)) if not old.is_empty() else 0.0}
	_last = side
	comms_from = from
	comms_expr = expr
	comms_face = face
	comms_generic = face.begins_with("gp/")
	comms_line = line
	comms_voice = v
	comms_female = female
	comms_hostile = hostile
	if mode == "talk": console_open = false
	Sfx.speak(line, v, female)
	_sync()
	_log("%s: %s" % [from, line])

## Is that side's screen busy with a call you placed (don't talk over it)?
func side_busy(hostile: bool) -> bool:
	return slots["l" if hostile else "r"].get("mode", "") == "talk"

func slot(side: String) -> Dictionary:
	return slots[side]

func close_side(side: String) -> void:
	slots[side] = {}
	if slots[_last].is_empty(): _last = "l" if side == "r" else "r"
	_sync()

## Keep the old single-panel view of the state (comms_open / comms_mode) in step with the side screens + console.
func _sync() -> void:
	var any: bool = not slots["l"].is_empty() or not slots["r"].is_empty()
	comms_open = any or console_open
	if console_open: comms_mode = "roster"
	elif not slots[_last].is_empty(): comms_mode = slots[_last]["mode"]
	elif any: comms_mode = (slots["l"] if not slots["l"].is_empty() else slots["r"])["mode"]
	else: comms_mode = ""

func open_picker(list: Array) -> void:
	contacts = list
	comms_open = true
	comms_mode = "picker"
	comms_hostile = false

## LOG = the comms console: drops down under the centre buttons with your contacts (call anyone who is in THIS
## star system, like a codec but with names instead of frequencies), the chat log, and a box to type in.
## Tap LOG again (or wait) and it rolls back up.
func open_log() -> void:
	console_open = true
	roster_t = 0.0
	roster_closing = false
	roster_idle = 0.0
	_sync()

func roster_rect() -> Rect2:
	var w := clampf(S.x - (8 + _block_w()) * 2 - 40, 420.0, 640.0)
	var full_h := 322.0
	return Rect2(S.x * 0.5 - w * 0.5, 130, w, maxf(8.0, full_h * ease(roster_t, 0.35)))

## Can you call this contact from here? Only people in the same star system answer.
static func in_range(id: String) -> bool:
	return Data.CHARACTERS[id].get("system", GS.system_id) == GS.system_id

func close_roster() -> void:
	roster_closing = true

func _face_tex(face: String, expr: String) -> Texture2D:
	var k := face + "_" + expr
	if face.begins_with("gp/"):   # generic enemy pilot: enemies pack, normal / damaged only; not cached until it exists
		var gp := "res://assets/enemy_pilots/%s_%s.jpg" % [face.substr(3), "damaged" if expr == "damaged" else "normal"]
		if _faces.get(k) == null: _faces[k] = load(gp) if ResourceLoader.exists(gp) else null
		return _faces[k]
	if not _faces.has(k):
		var path := "res://assets/portraits/%s.png" % k
		_faces[k] = load(path) if ResourceLoader.exists(path) else null
		if _faces[k] == null and expr != "normal": _faces[k] = _face_tex(face, "normal")
	return _faces[k]

func close_comms() -> void:
	if not slots["l"].is_empty() or not slots["r"].is_empty(): Sfx.hang_up()
	slots = {"l": {}, "r": {}}
	console_open = false
	if _typer: _typer.visible = false
	_sync()

## Where a side screen sits: under the corner buttons, clear of the sticks.
func side_rect(side: String) -> Rect2:
	var w := clampf(S.x * 0.14, 150.0, 190.0)
	var top := 8.0 + btn * 2.0 + 8.0 + 14.0
	var h := minf(w + 90.0, _home("move").y - stick_r - 10.0 - top)
	return Rect2(8.0 if side == "l" else S.x - 8.0 - w, top, w, h)

# ---------------------------------------------------------------- layout
func _home(which: String) -> Vector2:
	var x := 36 + stick_r if which == "move" else S.x - 36 - stick_r
	return Vector2(x, S.y - stick_r - 28)

## The radar screen (chase: centre dash panel; cockpit: the art's centre screen). It is a button: tap = radar map.
func radar_rect() -> Rect2:
	if GS.view == "cockpit" and cockpit_texture():
		var cr := cockpit_rect()
		return Rect2(cr.position + cr.size * Vector2(0.433, 0.66), cr.size * Vector2(0.136, 0.155))
	var c := _console()
	var mid := clampf(c.size.x * 0.34, 150.0, 220.0)
	return Rect2(c.get_center().x - mid * 0.5, c.position.y, mid, c.size.y)

## Where a stick can be grabbed: the bottom corners only (not the radar / middle of the dash).
func stick_zone(which: String) -> Rect2:
	var top := btn * 2.0 + 30.0
	var w := clampf(S.x * 0.36, 260.0, 520.0)
	return Rect2(0.0, top, w, S.y - top) if which == "move" else Rect2(S.x - w, top, w, S.y - top)

func _console() -> Rect2:
	var l := _home("move").x + stick_r + 14
	var r := _home("aim").x - stick_r - 14
	return Rect2(l, S.y - 150, r - l, 140)

func _comms_rect() -> Rect2:
	# over the dashboard, between the two sticks
	var l := _home("move").x + stick_r + 10
	var r := _home("aim").x - stick_r - 10
	var w := minf(720.0, r - l)
	return Rect2(S.x * 0.5 - w * 0.5, S.y - 272, w, 262)

## Width of one corner block (three buttons).
func _block_w() -> float:
	return btn * 3 + 16

func _layout() -> void:
	S = get_viewport_rect().size
	stick_r = clampf(S.y * 0.128, 80.0, 100.0)
	btn = clampf(S.y * 0.13, 84.0, 104.0)
	col_w = 24.0
	buttons.clear()
	var g := 8.0
	var y1 := 8.0
	var y2 := y1 + btn + g
	var bs := Vector2(btn, btn)
	# top left: SHIELD · REPAIR · TRACTOR / STOP · WARP
	var lids := ["shield", "repair", "tractor"]
	for k in 3: buttons[lids[k]] = Rect2(Vector2(8 + k * (btn + g), y1), bs)
	buttons["form"] = Rect2(Vector2(8, y2), bs)   # TRANSFORM sits where STOP used to be
	buttons["warp"] = Rect2(Vector2(8 + btn + g, y2), bs)
	# top right mirrors it: three weapon slots / THRUST · KILL (kill hard against the right edge)
	for k in 3: buttons["slot_%d" % k] = Rect2(Vector2(S.x - 8 - (3 - k) * btn - (2 - k) * g, y1), bs)
	buttons["kill"] = Rect2(Vector2(S.x - 8 - btn, y2), bs)
	buttons["thrust"] = Rect2(Vector2(S.x - 8 - btn * 2 - g, y2), bs)
	# centre strip: MAP · VIEW · LOG · CALL · TARGET · GO TO under the status bars
	var cl := 8 + _block_w() + 14
	var avail := S.x - cl * 2
	var pw := clampf((avail - 5 * 6) / 6.0, 66.0, 110.0)
	var row := pw * 6 + 30
	var ids := ["map", "view", "log", "call", "target", "goto"]
	for k in 6: buttons[ids[k]] = Rect2(Vector2(S.x * 0.5 - row * 0.5 + k * (pw + 6), 78), Vector2(pw, 44))
	log_rect = buttons["log"]
	if space and space.controls and not console_open: buttons["radar"] = radar_rect()
	if space and space.controls:
		var db := Rect2(S.x * 0.5 - 130, 176, 260, 60)
		if space.dock_candidate() != null: buttons["dock"] = db
		elif space.gate_in_range(): buttons["jump"] = db
	for side in ["l", "r"]:
		var sd: Dictionary = slots[side]
		if sd.is_empty(): continue
		var sr := side_rect(side)
		if sd["mode"] == "talk": buttons["hangup"] = Rect2(sr.end.x - 34, sr.position.y + 2, 32, 22)   # before the body, so it wins
		buttons["side_" + side] = sr
	if console_open:
		var rr := roster_rect()
		if roster_t > 0.95 and not roster_closing:
			var cw := rr.size.x * 0.46
			for k in mini(GS.met.size(), 5):
				buttons["met_%d" % k] = Rect2(rr.position.x + 8, rr.position.y + 34 + k * 46, cw, 42)
			buttons["type"] = Rect2(rr.position.x + 8, rr.end.y - 46, cw * 0.5 - 4, 38)
			buttons["voice"] = Rect2(rr.position.x + 8 + cw * 0.5 + 4, rr.end.y - 46, cw * 0.5 - 4, 38)

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
					Sfx.play("button", -14.0)
					if id != "thrust": pressed.emit(id)   # THRUST works while held
					get_viewport().set_input_as_handled()
					return
			if console_open:
				if roster_rect().has_point(e.position):
					owners[e.index] = "comms_body"
					roster_idle = 0.0
					return
				if not (_typer and _typer.visible): close_roster()
			if stick_zone("move").has_point(e.position) and not owners.values().has("move"):
				owners[e.index] = "move"
				origins["move"] = e.position
			elif stick_zone("aim").has_point(e.position) and not owners.values().has("aim"):
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
	space.fire_held = Input.is_action_pressed("fire")
	space.thrust_held = held.has("thrust") or Input.is_key_pressed(KEY_SHIFT)
	if console_open:
		if roster_closing:
			roster_t = maxf(0.0, roster_t - dt * 6.0)
			if roster_t <= 0.0:
				console_open = false
				_typer.visible = false
				_sync()
		else:
			roster_t = minf(1.0, roster_t + dt * 6.0)
			if not _typer.visible: roster_idle += dt
			if roster_idle > 10.0: close_roster() # rolls itself back up if you leave it
	for side in ["l", "r"]:
		var sd: Dictionary = slots[side]
		if sd.is_empty(): continue
		sd["anim"] = minf(1.0, float(sd["anim"]) + dt * 4.0)
		if sd["mode"] == "incoming":
			sd["timer"] = float(sd["timer"]) - dt
			if sd["timer"] <= 0.0: close_side(side)
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
		"repair":
			_icon("hull", c, s, col)
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
		"heavy":
			var hdir := Vector2(1, -1).normalized()
			var hperp := Vector2(-hdir.y, hdir.x)
			draw_line(c - hdir * s * 0.85, c + hdir * s * 0.5, col, s * 0.56)
			draw_colored_polygon(PackedVector2Array([c + hdir * s * 1.05, c + hdir * s * 0.45 + hperp * s * 0.3, c + hdir * s * 0.45 - hperp * s * 0.3]), col)
			draw_colored_polygon(PackedVector2Array([c - hdir * s * 0.5 + hperp * s * 0.6, c - hdir * s * 0.95, c - hdir * s * 0.5 - hperp * s * 0.6]), col)
			draw_line(c - hdir * s * 0.1 + hperp * s * 0.3, c - hdir * s * 0.1 - hperp * s * 0.3, RED, 3.0)
		"tractor":
			# a beam cone pulling a crate in
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.85), c + Vector2(s * 0.2, -s * 0.85), c + Vector2(s * 0.75, s * 0.35), c + Vector2(-s * 0.75, s * 0.35)]), Color(col, 0.35))
			draw_rect(Rect2(c + Vector2(-s * 0.35, -s * 1.0), Vector2(s * 0.7, s * 0.25)), col)
			draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.3), Vector2(s * 0.8, s * 0.6)), GOLD)
			draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.3), Vector2(s * 0.8, s * 0.6)), Color(0.3, 0.2, 0.05), false, 2.0)
			for k in 3: draw_arc(c + Vector2(0, -s * 0.8), s * (0.45 + k * 0.35), deg_to_rad(60), deg_to_rad(120), 10, Color(col, 0.8), 2.0)
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
		"form":   # two arrows chasing each other: ship <-> mech
			draw_arc(c, s * 0.8, deg_to_rad(200), deg_to_rad(340), 16, col, 3.0, true)
			draw_arc(c, s * 0.8, deg_to_rad(20), deg_to_rad(160), 16, col, 3.0, true)
			var a1 := c + Vector2(cos(deg_to_rad(340)), sin(deg_to_rad(340))) * s * 0.8
			var a2 := c + Vector2(cos(deg_to_rad(160)), sin(deg_to_rad(160))) * s * 0.8
			draw_colored_polygon(PackedVector2Array([a1 + Vector2(-s * 0.35, -s * 0.1), a1 + Vector2(s * 0.25, -s * 0.05), a1 + Vector2(0, s * 0.4)]), col)
			draw_colored_polygon(PackedVector2Array([a2 + Vector2(s * 0.35, s * 0.1), a2 + Vector2(-s * 0.25, s * 0.05), a2 + Vector2(0, -s * 0.4)]), col)
		"kill":
			draw_circle(c, s * 0.55, col, false, 3.0)
			for k in 4:
				var ang := k * PI / 2.0 + t * 0.0
				draw_line(c + Vector2(cos(ang), sin(ang)) * s * 0.55, c + Vector2(cos(ang), sin(ang)) * s * 0.9, col, 3.0)
			draw_line(c + Vector2(-s, -s * 0.9), c + Vector2(s, s * 0.9), RED, 3.0)
		"thrust":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.55, -s * 0.1), c + Vector2(s * 0.6, s * 0.45), c + Vector2(0, s * 0.95), c + Vector2(-s * 0.6, s * 0.45), c + Vector2(-s * 0.4, -s * 0.2)]), ORANGE)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.3), c + Vector2(s * 0.3, s * 0.3), c + Vector2(0, s * 0.8), c + Vector2(-s * 0.3, s * 0.3)]), YELLOW)

## One big corner button: raised face, icon, label, optional count badge and cooldown ring.
func _corner(id: String, label: String, icon: String, col: Color, active := false, badge := "", cd := 0.0, locked := false, sub := "") -> void:
	if not buttons.has(id): return
	var r: Rect2 = buttons[id]
	var down := held.has(id) or float(flash.get(id, 0.0)) > 0.3
	var on := down or active
	if not down: _box(Rect2(r.position + Vector2(0, 4), r.size), Color(0.0, 0.03, 0.07, 0.95), Color(0, 0, 0, 0), 14, 0)
	var f := Rect2(r.position + (Vector2(0, 4) if down else Vector2.ZERO), r.size)
	_box(f, Color(col.darkened(0.45), 0.92) if on else Color(0.04, 0.12, 0.22, 0.9), Color(col, 1.0) if on else Color(col, 0.75), 14, 3 if on else 2)
	draw_rect(Rect2(f.position + Vector2(8, 4), Vector2(f.size.x - 16, 2)), Color(1, 1, 1, 0.22))
	_icon(icon, f.position + Vector2(f.size.x * 0.5, f.size.y * 0.4), f.size.x * 0.19, col.lightened(0.25) if icon != "tractor" else col)
	_text(Vector2(f.position.x, f.end.y - (22 if sub != "" else 11)), label, 15, WHITE, HORIZONTAL_ALIGNMENT_CENTER, f.size.x)
	if sub != "": _text(Vector2(f.position.x, f.end.y - 7), sub, 11, Color(col.lightened(0.35), 0.95), HORIZONTAL_ALIGNMENT_CENTER, f.size.x)
	if badge != "":
		var bc := f.position + Vector2(f.size.x - 17, 17)
		var empty := badge == "0" or badge == "00"
		draw_circle(bc, 14, RED if empty else Color(0.02, 0.07, 0.14))
		draw_arc(bc, 14, 0, TAU, 24, Color(col, 0.9), 2.0, true)
		_text(bc + Vector2(-14, 6), badge, 15, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 28)
	if cd > 0.0:
		draw_arc(f.get_center(), f.size.x * 0.46, -PI / 2, -PI / 2 + TAU * (1.0 - cd), 40, Color(WHITE, 0.8), 3.0, true)
	if locked:
		draw_rect(f, Color(0, 0, 0, 0.62))
		_text(Vector2(f.position.x, f.get_center().y + 6), "LOCKED", 14, GOLD, HORIZONTAL_ALIGNMENT_CENTER, f.size.x)

## Freelancer-style status: segmented colour bars, no numbers. Shield blue, hull green→yellow→red, energy gold.
func _status_bars() -> void:
	var w := clampf(S.x - (8 + _block_w() + 14) * 2 - 60, 220.0, 420.0)
	var x := S.x * 0.5 - w * 0.5 + 16
	var rows := [["shield", GS.shield / GS.max_shield(), Color(0.35, 0.7, 1.0)],
		["hull", GS.hull / GS.max_hull(), _hull_col(GS.hull / GS.max_hull())],
		["energy", GS.energy / Data.ENERGY_MAX, YELLOW]]
	_box(Rect2(x - 38, 6, w + 44, 66), Color(0.01, 0.05, 0.1, 0.72), Color(CYAN, 0.45), 10, 1)
	_damage_icon(Vector2(x - 38 - 36, 39), 31.0, GS.wing_l / GS.wing_max(), GS.hull / GS.max_hull(), GS.wing_r / GS.wing_max(), space.is_mech_form() if space.has_method("is_mech_form") else false)
	for k in 3:
		var y := 12.0 + k * 20.0
		var v: float = clampf(rows[k][1], 0.0, 1.0)
		var col: Color = rows[k][2]
		var low := v < 0.25 and k < 2 and fmod(t, 0.6) < 0.3
		_icon(rows[k][0], Vector2(x - 18, y + 7), 7.0, RED if low else col)
		if k == 1:
			_three_part(Rect2(Vector2(x, y + 2), Vector2(w - 8, 11)), GS.wing_l / GS.wing_max(), v, GS.wing_r / GS.wing_max(), low)
			continue
		var segs := 20
		var sw := (w - 8) / segs
		for i in segs:
			var fill := clampf(v * segs - i, 0.0, 1.0)
			var sr := Rect2(Vector2(x + i * sw, y + 2), Vector2(sw - 2, 11))
			draw_rect(sr, Color(col, 0.14))
			if fill > 0.0: draw_rect(Rect2(sr.position, Vector2(sr.size.x * fill, sr.size.y)), RED if low else col)

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
var _cockpit_tex: Texture2D
const COCKPIT_PATH := "res://assets/cockpit/cockpit_b.png"
## The owner's cockpit art (cockpit pack): glass keyed out so space shows through. 1280 x 720, scaled to cover the
## screen and anchored to the bottom so the dashboard always shows.
## Scaled up 1.3x and pushed down so the dashboard sits low and you see more space; the spare margin lets the
## cockpit slide the opposite way when you look around (free-look), without showing its edges.
const COCKPIT_SCALE := 1.3
func cockpit_rect() -> Rect2:
	var sc := maxf(S.x / 1280.0, S.y / 720.0) * COCKPIT_SCALE
	var sz := Vector2(1280.0, 720.0) * sc
	var base := Vector2((S.x - sz.x) * 0.5, S.y - 4.0 - sz.y * 0.82)   # centre dash screen's bottom edge on the screen bottom
	var lk: Vector2 = space.look if space else Vector2.ZERO
	var mx := (sz.x - S.x) * 0.5 * 0.85
	base += Vector2(-lk.x * mx, clampf(-lk.y * 70.0, -40.0, maxf(0.0, -base.y)))
	return Rect2(base, sz)

func cockpit_texture() -> Texture2D:
	if _cockpit_tex == null and ResourceLoader.exists(COCKPIT_PATH): _cockpit_tex = load(COCKPIT_PATH)
	return _cockpit_tex

func _cockpit() -> void:
	var tex := cockpit_texture()
	if tex:
		var cr := cockpit_rect()
		draw_texture_rect(tex, cr, false)
		_cockpit_instruments(cr)
		return
	_cockpit_old()

## Cockpit-view instruments: the centre dash screen becomes the radar; heading tape, SPD and ALT/RNG bars and a
## ring reticle on the glass (like the owner's concept).
func _cockpit_instruments(cr: Rect2) -> void:
	var scr := Rect2(cr.position + cr.size * Vector2(0.433, 0.66), cr.size * Vector2(0.136, 0.155))
	_radar(scr.get_center(), minf(scr.size.x, scr.size.y) * 0.46, false)
	var c := S * 0.5
	var col := Color(0.55, 0.88, 1.0, 0.9)
	# heading tape
	var hdg := fposmod(rad_to_deg(-space.yaw), 360.0)
	var ty := c.y - 98.0   # between the DOCK / WARP GATE button and the reticle
	var span := 40.0
	var px := 260.0 / span
	draw_line(Vector2(c.x - 130, ty + 8), Vector2(c.x + 130, ty + 8), Color(col, 0.6), 1.5)
	var start := int(floor((hdg - span * 0.5) / 5.0)) * 5
	for k in range(start, int(hdg + span * 0.5) + 1, 5):
		var x := c.x + (k - hdg) * px
		if absf(x - c.x) > 130.0: continue
		var big := k % 10 == 0
		draw_line(Vector2(x, ty + 8), Vector2(x, ty + (0.0 if big else 4.0)), col, 1.5)
		if big and absf(x - c.x) > 18.0: _text(Vector2(x - 20, ty - 4), "%03d" % posmod(k, 360), 11, col, HORIZONTAL_ALIGNMENT_CENTER, 40)
	_box(Rect2(c.x - 24, ty - 18, 48, 20), Color(0.02, 0.08, 0.16, 0.8), col, 4, 1)
	_text(Vector2(c.x - 24, ty - 3), "%03d" % int(hdg), 13, WHITE, HORIZONTAL_ALIGNMENT_CENTER, 48)
	draw_colored_polygon(PackedVector2Array([Vector2(c.x - 5, ty + 10), Vector2(c.x + 5, ty + 10), Vector2(c.x, ty + 16)]), col)
	# speed (left) and altitude / range (right) bars
	var top_speed: float = float(GS.ship()["speed"]) * Data.THRUST_MULT
	_cockpit_bar(Vector2(c.x - 170, c.y), "SPD", "%d m/s" % int(space.speed_now), clampf(space.speed_now / top_speed, 0.0, 1.0), col, true)
	var right_lbl := "RNG"
	var right_val := "—"
	var right_k := 0.0
	if space.surface_mode:
		right_lbl = "ALT"
		right_val = "%d m" % int(space.altitude)
		right_k = clampf(space.altitude / Surface.CEILING, 0.0, 1.0)
	elif space.target and is_instance_valid(space.target):
		var dd: float = space.distance_to(space.target)
		right_val = _dist(dd)
		right_k = clampf(dd / 3000.0, 0.0, 1.0)
	_cockpit_bar(Vector2(c.x + 170, c.y), right_lbl, right_val, right_k, col, false)

func _cockpit_bar(p: Vector2, lbl: String, val: String, k: float, col: Color, left: bool) -> void:
	var h := 150.0
	var r := Rect2(p - Vector2(4, h * 0.5), Vector2(8, h))
	draw_rect(r, Color(col, 0.18))
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - h * k), Vector2(8, h * k)), col)
	for i in 6: draw_line(Vector2(r.position.x - 4, r.position.y + i * h / 5.0), Vector2(r.end.x + 4, r.position.y + i * h / 5.0), Color(col, 0.6), 1)
	var tx := r.position.x - 92 if left else r.end.x + 10
	_text(Vector2(tx, p.y - 8), lbl, 12, col, HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT, 82)
	_text(Vector2(tx, p.y + 14), val, 17, WHITE, HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT, 82)

func _cockpit_old() -> void:
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
	if space.sun_flare > 0.01:   # sun bloom: washes the view out the closer and more head-on you fly at it
		var sc: Color = (space.sys["star"] as Color).lerp(Color.WHITE, 0.55)
		draw_rect(Rect2(Vector2.ZERO, S), Color(sc, minf(0.92, space.sun_flare * 0.95)))
	for n in [space.station, space.planet, space.gate]:
		if not n.visible and n.get_meta("kind", "") != "station": continue
		if n.get_meta("kind", "") == "none": continue
		var pos: Vector3 = space.dock_point(n) if n != space.gate else n.global_position
		var sp = _screen(pos)
		var col := GOLD if n == space.gate else GREEN
		if sp != null and Rect2(Vector2(col_w, 0), Vector2(S.x - col_w * 2, S.y)).has_point(sp):
			draw_arc(sp, 14, 0, TAU, 4, Color(col, 0.85), 2.0)
			_text(sp + Vector2(20, 6), "%s  %s" % [n.name, _dist(space.distance_to(n))], 14, Color(col, 0.95))
	if is_instance_valid(space.waypoint):
		var wsp = _screen(space.waypoint.global_position)
		if wsp != null:
			draw_colored_polygon(PackedVector2Array([wsp + Vector2(0, -10), wsp + Vector2(10, 0), wsp + Vector2(0, 10), wsp + Vector2(-10, 0)]), Color(GOLD, 0.9))
			_text(wsp + Vector2(16, 6), "WAYPOINT  " + _dist(space.distance_to(space.waypoint)), 14, GOLD)
		elif space.autopilot == space.waypoint:
			_edge_arrow(space.waypoint.global_position, GOLD, Rect2(Vector2(col_w + 30, 40), Vector2(S.x - col_w * 2 - 60, S.y - 80)), true)
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
			_text(pp - Vector2(110, 0), pu["text"], 18, Color(pu["col"], a), HORIZONTAL_ALIGNMENT_CENTER, 220)
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
	# warp spool countdown and the planet warning
	if space.warp_state == "charging":
		var left := int(ceil(Data.WARP_CHARGE - space.warp_t))
		_text(Vector2(0, S.y * 0.5 - 62), str(maxi(1, left)), 60, Color(0.75, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER, S.x)
		_text(Vector2(0, S.y * 0.5 - 44), "WARP SPOOLING · WEAPONS LOCKED", 15, Color(0.75, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	elif space.warp_flash > 0.0:
		_text(Vector2(0, S.y * 0.5 - 62), "WARP", 64, Color(0.85, 0.92, 1.0, minf(1.0, space.warp_flash * 2.0)), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	if space.sun_hazard > 0 and fmod(t, 0.5) < 0.32:
		_text(Vector2(0, S.y * 0.5 - 132), "HEAT WARNING", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
		_text(Vector2(0, S.y * 0.5 - 100), "TURN AWAY FROM THE STAR", 24, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	if space.planet_hazard > 0 and fmod(t, 0.5) < 0.32:
		_text(Vector2(0, S.y * 0.5 - 132), "PLANETARY MASS DETECTED", 34, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
		_text(Vector2(0, S.y * 0.5 - 100), "DROP WARP NOW", 24, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	# reticle (cockpit view: a wider ring with ticks and a chevron, like the concept)
	var c := S * 0.5
	var locked: bool = space._in_fire_cone(space.target)
	var rc2 := RED if locked else WHITE
	if cockpit and cockpit_texture():
		var nose = _screen(space.player.global_position - space.player.global_basis.z * 400.0)
		if nose != null: c = nose   # the crosshair marks where the nose points, even while you look around
		var rcol := RED if locked else Color(0.6, 0.9, 1.0)
		draw_arc(c, 46, 0, TAU, 64, Color(rcol, 0.95), 2.0, true)
		draw_arc(c, 52, deg_to_rad(200), deg_to_rad(340), 32, Color(rcol, 0.5), 1.5, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * 46, c + d * 60, Color(rcol, 0.95), 2.0)
		draw_line(c + Vector2(-110, 0), c + Vector2(-64, 0), Color(rcol, 0.5), 1.5)
		draw_line(c + Vector2(64, 0), c + Vector2(110, 0), Color(rcol, 0.5), 1.5)
		draw_polyline(PackedVector2Array([c + Vector2(-9, 64), c + Vector2(0, 74), c + Vector2(9, 64)]), rcol, 2.0)
		draw_circle(c, 3, rcol)
	else:
		draw_arc(c, 32, 0, TAU, 48, Color(rc2, 0.95), 2.5, true)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * 20, c + d * 52, Color(rc2, 0.95), 2.5)
		draw_circle(c, 4, rc2)
	_status_bars()
	var line2 := objective
	if msg_t > 0.0: line2 = msg
	_text(Vector2(col_w, 144), line2, 15, GOLD if msg_t > 0.0 else WHITE, HORIZONTAL_ALIGNMENT_CENTER, S.x - col_w * 2)
	var zone := ""
	if space.surface_mode: zone = "%s  ·  ALT %d m" % [Surface.tile_name(space.planet_id, space.tile), int(space.altitude)]
	elif space.in_nebula > 0.0: zone = "%s NEBULA — SENSORS DEGRADED" % Data.SYSTEMS[GS.system_id]["nebula"]["name"].to_upper()
	elif space.in_belt: zone = "%s — WATCH FOR ROCKS" % Data.SYSTEMS[GS.system_id]["asteroids"]["name"].to_upper()
	if zone != "": _text(Vector2(col_w, 164), zone, 14, CYAN_HI, HORIZONTAL_ALIGNMENT_CENTER, S.x - col_w * 2)
	# top-left block
	var sh_cd: float = space.shield_cd / Data.SHIELD_BOOST_COOLDOWN
	_corner("shield", "SHIELD", "shield", Color(0.35, 0.7, 1.0), false, str(GS.shield_charges), sh_cd)
	_corner("repair", "REPAIR", "repair", GREEN, false, str(GS.repairs), space.repair_cd / 1.5)
	_corner("tractor", "TRACTOR", "tractor", Color(0.45, 0.9, 1.0), space.tractor_t > 0.0, str(space.loot.size()) if space.loot.size() > 0 else "")
	var tf: bool = space.transform_t > 0.0
	_corner("form", "…" if tf else ("SHIP" if GS.form == "mech" else "MECH"), "form", GOLD, tf, "", 0.0, space.warp_state != "off", "TRANSFORM")
	var wsub := ""
	if space.warp_state == "charging": wsub = "%d s" % int(ceil(Data.WARP_CHARGE - space.warp_t))
	elif space.warp_state == "on": wsub = "DROP OUT"
	_corner("warp", "WARP", "warp", Color(0.62, 0.55, 1.0), space.warp_state != "off", "", 0.0, GS.form == "mech", wsub)
	if space.warp_state == "charging":
		var wr: Rect2 = buttons["warp"]
		draw_rect(Rect2(wr.position + Vector2(8, wr.size.y - 5), Vector2((wr.size.x - 16) * space.warp_t / Data.WARP_CHARGE, 3)), Color(0.8, 0.75, 1.0))
	# top-right block: weapon slots, then THRUST · KILL
	for k in GS.slots.size():
		var item: String = GS.slots[k]
		var it: Dictionary = Data.SLOT_ITEMS[item]
		var ammo := GS.slot_ammo(item)
		var scol := ORANGE if item == "light_missile" else (RED if item == "heavy_missile" else GOLD)
		var cdk: float = (space.mine_cd / 2.5) if item == "mine" else (space.missile_cd / 1.2)
		_corner("slot_%d" % k, it["label"], it["icon"], scol, false, "%d" % ammo, cdk, space.warp_active(), it["sub"])
	var mech: bool = GS.form == "mech"
	_corner("thrust", "BOOST" if mech else "THRUST", "thrust", ORANGE, space.boosting, "", 0.0, false, "STICK = DASH" if mech else "")
	_corner("kill", "KILL", "kill", GOLD, space.engine_kill, "", 0.0, mech, "DRIFTING" if space.engine_kill else "ENGINE")
	_pill("map", "MAP")
	_pill("view", "CHASE" if cockpit else "COCKPIT", false, CYAN, "VIEW")
	_pill("target", "TARGET", false, CYAN, "NEXT")
	_pill("goto", "GO TO", space.autopilot != null, CYAN, "AUTO")
	_pill("log", "LOG", comms_mode == "roster", CYAN, "CONTACTS")
	_pill("call", "CALL", comms_mode == "talk", GREEN)
	if buttons.has("dock"): _pill("dock", "DOCK", true, GREEN, space.dock_candidate().name.to_upper())
	if buttons.has("jump"): _pill("jump", "WARP GATE", true, GOLD, "TO %s" % Data.SYSTEMS[space.sys["gate"]["to"]]["name"].to_upper())
	if not (cockpit and cockpit_texture()): _dashboard()   # the cockpit art has its own dash screens
	_stick("move", "FLIGHT")
	_stick("aim", "AIM")
	if comms_open: _comms()
	if damage_flash > 0.0:
		for i in 6: draw_rect(Rect2(Vector2.ZERO, S), Color(RED, damage_flash * 0.08), false, 60.0 - i * 9.0)

func _hull_col(k: float) -> Color:
	return GREEN.lerp(YELLOW, clampf((0.75 - k) / 0.35, 0, 1)).lerp(RED, clampf((0.4 - k) / 0.3, 0, 1))

## Structural status: a circle split like a "Y" into three wedges — HULL (top, between the arms of the Y), LEFT and
## RIGHT wing (or arm, for a mech) — each green > yellow > red, dark grey when destroyed, with the silhouette on top.
func _damage_icon(c: Vector2, r: float, lk: float, ck: float, rk: float, mech := false) -> void:
	var wedges := [[-150.0, -30.0, ck, false], [90.0, 210.0, lk, true], [-30.0, 90.0, rk, true]]   # degrees, screen y down
	draw_circle(c, r + 3, Color(0.01, 0.05, 0.1, 0.85))
	for wd in wedges:
		var k: float = clampf(wd[2], 0.0, 1.0)
		var col := Color(0.25, 0.27, 0.3) if (wd[3] and k <= 0.0) else _hull_col(k)
		if not wd[3] and k <= 0.0: col = Color(0.25, 0.27, 0.3)
		var pts := PackedVector2Array([c])
		for i in 13:
			var a := deg_to_rad(lerpf(wd[0], wd[1], i / 12.0))
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(col, 0.85))
	for a2 in [-150.0, -30.0, 90.0]:
		draw_line(c, c + Vector2(cos(deg_to_rad(a2)), sin(deg_to_rad(a2))) * r, Color(0.01, 0.05, 0.1), 2.5)
	draw_arc(c, r, 0, TAU, 40, Color(CYAN_HI, 0.9), 2.0, true)
	var s := r / 28.0
	var sil: PackedVector2Array
	if mech:
		sil = PackedVector2Array([Vector2(-5, -17), Vector2(5, -17), Vector2(6, -11), Vector2(16, -9), Vector2(18, 6), Vector2(12, 6), Vector2(10, -3), Vector2(7, -2),
			Vector2(8, 18), Vector2(2, 18), Vector2(0, 6), Vector2(-2, 18), Vector2(-8, 18), Vector2(-7, -2), Vector2(-10, -3), Vector2(-12, 6), Vector2(-18, 6), Vector2(-16, -9), Vector2(-6, -11)])
	else:
		sil = PackedVector2Array([Vector2(0, -19), Vector2(4, -7), Vector2(19, 6), Vector2(19, 10), Vector2(5, 7), Vector2(4, 15), Vector2(-4, 15), Vector2(-5, 7), Vector2(-19, 10), Vector2(-19, 6), Vector2(-4, -7)])
	for i in sil.size(): sil[i] = c + sil[i] * s
	sil.append(sil[0])
	draw_polyline(sil, WHITE, 2.0, true)

## [ LEFT ] [ CORE ] [ RIGHT ]: side sections are short bars at each end, the core is the long middle bar.
## A destroyed side shows as a dark red box with an X.
func _three_part(r: Rect2, lk: float, ck: float, rk: float, blink := false) -> void:
	var gap := maxf(2.0, r.size.x * 0.02)
	var sw := r.size.x * 0.2
	var parts := [[Rect2(r.position, Vector2(sw, r.size.y)), lk], [Rect2(r.position + Vector2(sw + gap, 0), Vector2(r.size.x - sw * 2 - gap * 2, r.size.y)), ck],
		[Rect2(r.position + Vector2(r.size.x - sw, 0), Vector2(sw, r.size.y)), rk]]
	for i in 3:
		var pr: Rect2 = parts[i][0]
		var k: float = clampf(parts[i][1], 0.0, 1.0)
		draw_rect(pr, Color(0, 0, 0, 0.55))
		if i != 1 and k <= 0.0:
			draw_rect(pr, Color(0.45, 0.05, 0.05, 0.9))
			draw_line(pr.position, pr.end, RED, 1.5)
			draw_line(Vector2(pr.position.x, pr.end.y), Vector2(pr.end.x, pr.position.y), RED, 1.5)
			continue
		var c := RED if (blink and i == 1) else _hull_col(k)
		draw_rect(Rect2(pr.position, Vector2(pr.size.x * k, pr.size.y)), c)

## Shield (cyan) over hull (green -> red) bars for one enemy.
func _enemy_bars(p: Vector2, w: float, h: float, e: Dictionary, labels := false) -> void:
	var shk: float = float(e["sh"]) / maxf(1.0, float(e["sh_max"]))
	var hk: float = clampf(float(e["hp"]) / float(e["max"]), 0.0, 1.0)
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, h * 2 + 5)), Color(0, 0, 0, 0.55))
	if float(e["sh_max"]) > 0.0:
		draw_rect(Rect2(p, Vector2(w * shk, h)), CYAN_HI)
	var sm: float = maxf(1.0, float(e.get("side_max", 1.0)))
	_three_part(Rect2(p + Vector2(0, h + 2), Vector2(w, h)), float(e.get("l", sm)) / sm, hk, float(e.get("r", sm)) / sm)
	if labels:
		_text(p + Vector2(w + 6, h + 1), "SH %d" % roundi(float(e["sh"])), 12, CYAN_HI)
		_text(p + Vector2(w + 6, h * 2 + 12), "CORE %d" % roundi(float(e["hp"])), 12, _hull_col(hk))
		var lab := "ARM" if e.get("mech", false) else "WING"
		_text(p + Vector2(0, h * 2 + 16), "L " + lab, 10, Color(1, 1, 1, 0.75))
		_text(p + Vector2(0, h * 2 + 16), "R " + lab, 10, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_RIGHT, w)

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
	if space.surface_mode and mode == "": mode = "ALT %d m" % int(space.altitude)
	if mode != "": _text(Vector2(speed_r.position.x, speed_r.end.y + 16), mode, 13, GOLD, HORIZONTAL_ALIGNMENT_CENTER, speed_r.size.x)
	# centre screen: radar with your ship silhouette
	_box(screen_r, Color(0.01, 0.06, 0.12, 0.95), Color(CYAN, 0.9), 12, 2)
	_radar(screen_r.get_center() + Vector2(0, 4), minf(screen_r.size.x, screen_r.size.y) * 0.44, true)
	_way_box(way_r)

## Radar: blips around your ship silhouette (also drawn on the cockpit's centre dash screen).
func _radar(rc: Vector2, rr: float, label: bool) -> void:
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
	if space.station.get_meta("kind", "") == "station": items.append([space.station.global_position, GREEN])
	if not space.surface_mode:
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
	_text(Vector2(rc.x - rr, rc.y + rr + (-2.0 if label else 2.0)), "RADAR %s" % _dist(rng), 10, Color(CYAN, 0.8), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0)

## Waypoint box: autopilot destination, else the current target.
func _way_box(way_r: Rect2) -> void:
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

# ---------------------------------------------------------------- comms: side screens + console
func _comms() -> void:
	for side in ["l", "r"]: _side(side)
	if console_open: _roster()

## One holo screen sliding in from its side: name strip, portrait, and the line on a white see-through panel under it.
func _side(side: String) -> void:
	var d: Dictionary = slots[side]
	if d.is_empty(): return
	var r := side_rect(side)
	var e := ease(float(d["anim"]), 0.4)
	r.position.x += (1.0 - e) * (r.size.x + 24.0) * (-1.0 if side == "l" else 1.0)
	var accent := RED if d["hostile"] else CYAN_HI
	var a := 0.55 + 0.45 * e
	_box(r, Color(0.02, 0.07, 0.14, 0.5 * a), Color(accent, 0.9 * a), 8, 2)
	# name strip
	var head := Rect2(r.position, Vector2(r.size.x, 26))
	draw_rect(head, Color(accent.darkened(0.35), 0.85 * a))
	var parts := (d["from"] as String).split(" — ", true, 1)
	var nm := parts[0].to_upper()
	var fs := 15
	var nw := r.size.x - (44 if d["mode"] == "talk" else 12)
	while fs > 10 and font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > nw: fs -= 1
	_text(head.position + Vector2(6, 18), nm, fs, WHITE)
	if d["mode"] == "talk" and buttons.has("hangup"):
		var hb: Rect2 = buttons["hangup"]
		hb.position.x += (1.0 - e) * (r.size.x + 24.0) * (-1.0 if side == "l" else 1.0)
		draw_rect(hb, Color(RED, 0.9))
		_text(hb.position + Vector2(0, 16), "END", 12, WHITE, HORIZONTAL_ALIGNMENT_CENTER, hb.size.x)
	# portrait
	var pr := Rect2(r.position + Vector2(6, 30), Vector2(r.size.x - 12, r.size.x - 12))
	pr.size.y = minf(pr.size.y, r.size.y - 30 - 70)
	var tex: Texture2D = _face_tex(d["face"], d["expr"]) if d["face"] != "" else null
	var talk: float = Sfx.talking if side == _last else 0.0
	if tex:
		var src := Rect2(Vector2.ZERO, tex.get_size())
		var asp := pr.size.x / pr.size.y
		if asp > 1.0: src = Rect2(0, src.size.y * (1.0 - 1.0 / asp) * 0.3, src.size.x, src.size.y / asp)
		draw_texture_rect_region(tex, Rect2(pr.position + Vector2(0, -2.0 * talk), pr.size), src, Color(1, 1, 1, a).lerp(Color(1.12, 1.12, 1.12, a), talk))
	else:
		draw_rect(pr, Color(0.02, 0.1, 0.2, 0.8 * a))
		var cc := pr.get_center()
		for i in 15:
			var hgt := 6.0 + 26.0 * absf(sin(t * 7.0 + i * 0.9)) * (0.35 + 0.65 * Sfx.talking)
			var x := cc.x - 42 + i * 6
			draw_line(Vector2(x, cc.y - hgt * 0.5), Vector2(x, cc.y + hgt * 0.5), accent, 3)
	for k in int(pr.size.y / 4.0):   # holo scanlines
		draw_line(Vector2(pr.position.x, pr.position.y + k * 4), Vector2(pr.end.x, pr.position.y + k * 4), Color(0, 0.1, 0.2, 0.12), 1)
	var sy := fmod(t * 60.0, pr.size.y)
	draw_line(Vector2(pr.position.x, pr.position.y + sy), Vector2(pr.end.x, pr.position.y + sy), Color(accent, 0.2), 3)
	draw_rect(pr, Color(accent, 0.7 * a), false, 1.5)
	if e < 1.0:   # digital materialise: bright bands sweep while it slides in
		for k in 6: draw_rect(Rect2(r.position.x, r.position.y + fmod(k * 53.0 + t * 900.0, r.size.y), r.size.x, 3), Color(accent, 0.5 * (1.0 - e)))
	# the line, on white see-through glass under the portrait
	var tr := Rect2(Vector2(r.position.x + 5, pr.end.y + 5), Vector2(r.size.x - 10, r.end.y - pr.end.y - 10))
	draw_rect(tr, Color(1, 1, 1, 0.7 * a))
	draw_rect(tr, Color(accent, 0.8 * a), false, 1.5)
	var tag := ("HOSTILE" if d["hostile"] else "FRIENDLY") + (" · LIVE" if d["mode"] == "talk" else "")
	draw_string(font, tr.position + Vector2(5, 12), tag, HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 10, 9, Color(accent.darkened(0.45), a))
	draw_multiline_string(font, tr.position + Vector2(5, 26), d["line"], HORIZONTAL_ALIGNMENT_LEFT, tr.size.x - 10, 13, maxi(1, int((tr.size.y - 16) / 15.0)), Color(0.03, 0.07, 0.13, a))

func _dist(d: float) -> String:
	return "%.1f km" % (d / 1000.0) if d >= 1000.0 else "%d m" % int(d)

## Comms console (LOG): contacts on the left (only people in this star system pick up), the chat log on the right,
## TYPE and VOICE along the bottom.
func _roster() -> void:
	var r := roster_rect()
	_box(r, Color(0.02, 0.07, 0.14, 0.94), CYAN_HI, 10, 2)
	if r.size.y < 36.0: return
	var cw := r.size.x * 0.46
	_text(r.position + Vector2(12, 24), "COMMS · CONTACTS", 15, WHITE)
	_text(r.position + Vector2(cw + 22, 24), "LOG", 15, WHITE)
	_text(r.position + Vector2(0, 24), "TAP LOG TO CLOSE", 10, CYAN_HI, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12)
	if r.size.y < 300.0: return
	if GS.met.is_empty():
		_text(r.position + Vector2(12, 60), "Nobody yet — people you meet appear here.", 12, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, cw)
	for k in mini(GS.met.size(), 5):
		var br := Rect2(r.position.x + 8, r.position.y + 34 + k * 46, cw, 42)
		var id: String = GS.met[k]
		var c: Dictionary = Data.CHARACTERS[id]
		var ok := in_range(id)
		var m: String = GS.mood.get(id, "neutral")
		var mc: Color = {"friendly": GREEN, "neutral": CYAN_HI, "enraged": RED}[m]
		if not ok: mc = Color(0.55, 0.6, 0.66)
		var down := held.has("met_%d" % k)
		_box(br, Color(mc, 0.25) if down else Color(0.05, 0.13, 0.23, 1.0 if ok else 0.6), Color(mc, 0.7 if ok else 0.35), 8, 1)
		var pc := br.position + Vector2(22, 21)
		var ftex: Texture2D = _face_tex(c.get("face", ""), "normal") if c.get("face", "") != "" else null
		if ftex: draw_texture_rect(ftex, Rect2(pc - Vector2(17, 17), Vector2(34, 34)), false, Color(1, 1, 1, 1.0 if ok else 0.4))
		else: draw_circle(pc, 16, Color(c["color"], 0.9))
		_text(Vector2(br.position.x + 46, br.position.y + 19), c["name"], 14, WHITE if ok else Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_LEFT, br.size.x - 52)
		var sub: String = c["role"] if ok else "OUT OF RANGE · %s" % Data.SYSTEMS[c["system"]]["name"].to_upper()
		_text(Vector2(br.position.x + 46, br.position.y + 35), sub, 10, Color(0.8, 0.88, 0.95) if ok else Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_LEFT, br.size.x - 52)
	# chat log, newest at the top
	var lr := Rect2(r.position.x + cw + 16, r.position.y + 34, r.size.x - cw - 24, r.size.y - 42)
	draw_rect(lr, Color(1, 1, 1, 0.08))
	var y := lr.position.y + 16
	for line in history:
		if y > lr.end.y - 6: break
		var mine := (line as String).begins_with("YOU:")
		var lines := maxi(1, int(ceil(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / (lr.size.x - 12))))
		draw_multiline_string(font, Vector2(lr.position.x + 6, y), line, HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 12, 12, 3, GOLD if mine else Color(0.85, 0.92, 1.0))
		y += 15.0 * mini(lines, 3) + 5.0
	_pill("type", "TYPE", _typer.visible, CYAN)
	_pill("voice", "VOICE", false, CYAN, "READ" if Sfx.voice_mode == "read" else "MUMBLE")
	if _typer.visible:
		_typer.position = Vector2(lr.position.x, r.end.y + 6)
		_typer.size = Vector2(lr.size.x, 40)

## TYPE: open the message box (the phone keyboard comes up).
func start_typing() -> void:
	roster_idle = 0.0
	_typer.visible = true
	_typer.grab_focus()
