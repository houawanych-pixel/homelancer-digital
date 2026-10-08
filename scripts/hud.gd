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
var controls: Controls   # Job J: desktop keyboard + mouse (null-safe: touch never needs it)
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
var radar_range: float = Data.RADAR_RANGE   # what the radar shows right now (v1.4m: it zooms out when you are far from everything)
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
var comms_voice_id := ""   # v1.4t: whose recorded voice the line on screen looks for
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
func open_comms(from: String, line: String, mode := "talk", hostile := false, face := "", voice := 1.0, female := false, voice_id := "") -> void:
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
	comms_voice_id = voice_id
	Sfx.speak(line, v, female, voice_id)
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

## v1.4n: the console is two panels at the screen edges, so the middle (your ship, the view) stays clear.
## Contacts sit flush against the RIGHT edge, the message log against the LEFT edge. Both slide in from their side.
func _panel_w() -> float:
	return clampf(S.x * Data.COMMS_PANEL_FRAC, Data.COMMS_PANEL_W[0], Data.COMMS_PANEL_W[1])

func _panel_span() -> Vector2:   # top and bottom of both panels: under the corner buttons, above the sticks
	var top := 8.0 + btn * 2.0 + 8.0 + 14.0
	var bottom := _home("move").y - stick_r - 10.0
	return Vector2(top, maxf(top + 150.0, bottom))

func contacts_rect() -> Rect2:
	var w := _panel_w()
	var sp := _panel_span()
	var e := ease(roster_t, 0.35)
	return Rect2(S.x - w * e, sp.x, w, sp.y - sp.x)

func msglog_rect() -> Rect2:
	var w := _panel_w()
	var sp := _panel_span()
	var e := ease(roster_t, 0.35)
	return Rect2(-w * (1.0 - e), sp.x, w, sp.y - sp.x)

## How many contact rows fit (up to 5).
func contact_rows() -> int:
	return clampi(int((contacts_rect().size.y - 38.0) / Data.COMMS_ROW_H), 1, 5)

## Kept for older callers: the area the console covers = the contacts panel.
func roster_rect() -> Rect2:
	return contacts_rect()

## Can you call this contact from here? Only people in the same star system answer.
static func in_range(id: String) -> bool:
	return Data.CHARACTERS[id].get("system", GS.system_id) == GS.system_id

func close_roster() -> void:
	roster_closing = true

func _face_tex(face: String, expr: String) -> Texture2D:
	var k := face + "_" + expr
	if face.begins_with("gp/"):   # generic enemy pilot: enemies pack, normal / damaged only; not cached until it exists
		var gp := "res://assets/enemy_pilots/%s_%s.jpg" % [face.substr(3), "damaged" if expr == "damaged" else "normal"]
		if expr != "damaged" and not ResourceLoader.exists(gp): gp = "res://assets/enemy_pilots/%s_clean.jpg" % face.substr(3)   # roster characters: clean / damaged
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
	var inset := 8.0 + ((_panel_w() + 6.0) * ease(roster_t, 0.35) if console_open else 0.0)   # v1.4n: a caller floats in NEXT to the console panel
	return Rect2(inset if side == "l" else S.x - inset - w, top, w, h)

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
	buttons["fire"] = Rect2(Vector2(S.x - 8 - btn * 3 - g * 2, y2), bs)   # v1.4l: FIRE on/off, in the empty corner of the block
	# centre strip: MAP · VIEW · LOG · CALL · TARGET · GO TO under the status bars
	var cl := 8 + _block_w() + 14
	var avail := S.x - cl * 2
	var pw := clampf((avail - 5 * 6) / 6.0, 66.0, 110.0)
	var row := pw * 6 + 30
	var ids := ["map", "view", "log", "call", "target", "goto"]
	for k in 6: buttons[ids[k]] = Rect2(Vector2(S.x * 0.5 - row * 0.5 + k * (pw + 6), 78), Vector2(pw, 44))
	log_rect = buttons["log"]
	if space and space.controls and not console_open: buttons["radar"] = radar_rect()
	if space and space.controls and way_rect != Rect2() and space.target != null and is_instance_valid(space.target): buttons["scan"] = way_rect   # v1.5g: tap the target box = SCAN
	if not scan.is_empty(): buttons["scan_close"] = scan_rect()
	if space and space.controls:
		var db := Rect2(S.x * 0.5 - 130, 176, 260, 60)
		var pr: String = space.prompt()   # v1.4u: one prompt, the nearest thing wins
		if pr != "": buttons[pr] = db
	for side in ["l", "r"]:
		var sd: Dictionary = slots[side]
		if sd.is_empty(): continue
		var sr := side_rect(side)
		if sd["mode"] == "talk": buttons["hangup"] = Rect2(sr.end.x - 34, sr.position.y + 2, 32, 22)   # before the body, so it wins
		buttons["side_" + side] = sr
	if console_open:
		var rr := contacts_rect()
		var lg := msglog_rect()
		if roster_t > 0.95 and not roster_closing:
			for k in mini(GS.met.size(), contact_rows()):
				buttons["met_%d" % k] = Rect2(rr.position.x + 6, rr.position.y + 32 + k * Data.COMMS_ROW_H, rr.size.x - 6, Data.COMMS_ROW_H - 4)
			var hw := (lg.size.x - 24.0) / 3.0
			buttons["type"] = Rect2(lg.position.x + 6, lg.end.y - 44, hw, 38)
			buttons["talk"] = Rect2(lg.position.x + 12 + hw, lg.end.y - 44, hw, 38)   # v1.5j hold-to-talk
			buttons["voice"] = Rect2(lg.position.x + 18 + hw * 2.0, lg.end.y - 44, hw, 38)

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
					if id == "radar": radar_pick = radar_pick_at(e.position)   # v1.4p: which blip the tap landed on, if any
					if id == "talk":   # v1.5j: held, not tapped
						talk_press()
						get_viewport().set_input_as_handled()
						return
					if id != "thrust": pressed.emit(id)   # THRUST works while held
					get_viewport().set_input_as_handled()
					return
			if console_open:
				if contacts_rect().has_point(e.position) or msglog_rect().has_point(e.position):
					owners[e.index] = "comms_body"
					roster_idle = 0.0
					return   # v1.4n: a touch anywhere else flies the ship; LOG (or leaving it alone) closes the console
			if _mouse_in_kbm(e): return   # Job J: in keyboard + mouse mode the MOUSE flies (left-drag); real touches are unchanged
			if space.controls and not stick_zone("move").has_point(e.position) and not stick_zone("aim").has_point(e.position):   # v1.5g: tap a ship = target it
				var tapped: Node3D = space.ship_at_screen(e.position)
				if tapped != null:
					space.target = tapped
					Sfx.play("button", -14.0)
					get_viewport().set_input_as_handled()
					return
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
				if o == "talk": talk_release()
	elif e is InputEventScreenDrag:
		var o2: String = owners.get(e.index, "")
		if o2 == "move": move_vec = ((e.position - origins["move"]) / stick_r).limit_length(1.0)
		elif o2 == "aim": aim_vec = ((e.position - origins["aim"]) / stick_r).limit_length(1.0)

func _process(dt: float) -> void:
	if space == null: return
	t += dt
	_tick_scan(dt)
	_tick_talk(dt)
	msg_t = maxf(0.0, msg_t - dt)
	damage_flash = maxf(0.0, damage_flash - dt)
	for k in flash.keys(): flash[k] = maxf(0.0, float(flash[k]) - dt)
	var kb := Vector2(_axis("strafe_left", "strafe_right"), _axis("back", "forward"))
	var ka := Vector2(_axis("yaw_left", "yaw_right"), _axis("pitch_up", "pitch_down"))
	if kb.y == 0.0 and controls and controls.is_kbm() and not controls.blocked: kb.y = controls.wheel_throttle   # Job J: wheel throttle
	space.move = Vector2(move_vec.x, -move_vec.y) if kb == Vector2.ZERO else kb
	var a := aim_vec if ka == Vector2.ZERO else ka
	if a == Vector2.ZERO and controls: a = controls.mouse_steer(S)   # Job J: left-drag steer / mouse flight (keyboard + mouse only)
	space.aim = a * a.length()
	space.fire_held = controls.held("fire") if controls else Input.is_action_pressed("fire")   # Job J: right-click by default
	space.thrust_held = held.has("thrust") or (controls != null and controls.held("afterburner"))   # Job J: afterburner key (Tab)
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
			if roster_idle > Data.COMMS_IDLE_CLOSE: close_roster() # rolls itself back up if you leave it
	for side in ["l", "r"]:
		var sd: Dictionary = slots[side]
		if sd.is_empty(): continue
		sd["anim"] = minf(1.0, float(sd["anim"]) + dt * 4.0)
		if sd["mode"] == "incoming":
			sd["timer"] = float(sd["timer"]) - dt
			if sd["timer"] <= 0.0: close_side(side)
	queue_redraw()

## Job J: a held keyboard axis (paused while the Settings screen is open).
func _axis(neg: String, pos: String) -> float:
	if controls and controls.blocked: return 0.0
	return Input.get_axis(neg, pos)

## Job J: an emulated touch made by the MOUSE (not a finger) while in keyboard + mouse mode.
func _mouse_in_kbm(e: InputEvent) -> bool:
	return controls != null and controls.is_kbm() and e.device == InputEvent.DEVICE_ID_EMULATION

## Job J: which HUD button (if any) is under a screen point.
func button_at(p: Vector2) -> String:
	if not visible: return ""
	_layout()
	for id in buttons:
		if (buttons[id] as Rect2).grow(3).has_point(p): return id
	return ""

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
	if size < Data.TEXT_BUMP_BELOW: size = maxi(Data.TEXT_MIN, size + Data.TEXT_BUMP)   # v1.4m: small print is a little bigger
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
		var lit: float = space.beacon_lit   # v1.4r: a light beacon lights the cloud: the haze thins and warms near the lamp
		draw_rect(Rect2(Vector2.ZERO, S), Color(space.nebula_color.lerp(Data.BEACON_LIGHT_COLOR, lit * 0.6), 0.36 * space.in_nebula * (1.0 - Data.BEACON_HAZE_CLEAR * lit)))
	if space.sun_surface:   # on a star: everything is seen through a hot yellow haze (your heat shield, if you have one)
		draw_rect(Rect2(Vector2.ZERO, S), Color(1.0, 0.82, 0.25, 0.16 + 0.04 * sin(t * 3.1)))
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
	# v1.5a: the mission waypoint: a gold marker with what it is and how far, and an arrow at the screen edge when it is out of view
	var mw: Dictionary = space.mission_waypoint()
	if not mw.is_empty():
		var mnode: Node3D = mw["node"]
		var view := Rect2(Vector2(col_w + 30, 40), Vector2(S.x - col_w * 2 - 60, S.y - 80))
		var msp = _screen(mnode.global_position)
		if msp != null and view.has_point(msp):
			draw_colored_polygon(PackedVector2Array([msp + Vector2(0, -14), msp + Vector2(12, 0), msp + Vector2(0, 14), msp + Vector2(-12, 0)]), Color(GOLD, 0.25))
			draw_polyline(PackedVector2Array([msp + Vector2(0, -14), msp + Vector2(12, 0), msp + Vector2(0, 14), msp + Vector2(-12, 0), msp + Vector2(0, -14)]), GOLD, 2.5)
			_text(msp + Vector2(18, -8), "MISSION  " + _dist(space.distance_to(mnode)), 14, GOLD)
		else:
			_edge_arrow(mnode.global_position, GOLD, view, true)
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
					# The aim box (Freelancer style, v1.4l): a RED box ahead of the enemy, where your shots will meet it.
					# Put the crosshair on the box and fire. It shows for any targeted enemy on screen.
					var lp = _screen(space.lead_point(tgt))
					if lp != null and space.distance_to(tgt) < float(GS.weapon()["range"]) * Data.LEAD_BOX_RANGE:
						var on: bool = lp.distance_to(S * 0.5) < Data.LEAD_BOX_ON
						var lc := Color(1.0, 0.95, 0.3) if on else RED
						var hs: float = Data.LEAD_BOX_SIZE
						draw_line(tp, lp, Color(RED, 0.45), 1.5)
						draw_rect(Rect2(lp - Vector2(hs, hs), Vector2(hs, hs) * 2.0), Color(lc, 1.0), false, 3.0)
						draw_line(lp + Vector2(-hs * 0.45, 0), lp + Vector2(hs * 0.45, 0), lc, 2.0)
						draw_line(lp + Vector2(0, -hs * 0.45), lp + Vector2(0, hs * 0.45), lc, 2.0)
					# Job M: missile locks: one pip per lock the fitted rack can hold, filled as they come
					var item := "light_missile" if "light_missile" in GS.slots else "heavy_missile"
					var cap: int = mini(GS.max_locks(item), GS.slot_ammo(item))
					var got: int = space.lock_count(item)
					for k in cap:
						var pc: Vector2 = tp + Vector2((k - (cap - 1) * 0.5) * 16.0, -46.0)
						var dia := PackedVector2Array([pc + Vector2(0, -6), pc + Vector2(6, 0), pc + Vector2(0, 6), pc + Vector2(-6, 0)])
						if k < got: draw_colored_polygon(dia, RED)
						dia.append(dia[0])
						draw_polyline(dia, Color(RED, 0.95), 1.5)
					if got > 0: _text(tp + Vector2(-60, -74), "LOCK %d" % got, 14, RED, HORIZONTAL_ALIGNMENT_CENTER, 120)
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
		_text(Vector2(0, S.y * 0.5 - 100), "NO HEAT SHIELD — CLIMB OUT NOW" if space.sun_surface else "TURN AWAY FROM THE STAR", 24, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
	elif space.sun_surface and space.heat_shielded:
		_text(Vector2(0, 182), "HEAT SHIELD HOLDING", 15, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER, S.x)
	if space.missile_warn >= 0.0 and fmod(t, 0.4) < 0.28:   # Job M
		_text(Vector2(0, S.y * 0.5 - 98), "MISSILE  %d m" % int(space.missile_warn), 26, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
		_text(Vector2(0, S.y * 0.5 - 76), "BOOST SIDEWAYS NOW" if space.missile_warn < Data.DODGE_RANGE else "TURN SIDEWAYS · BOOST WHEN IT IS CLOSE", 16, RED, HORIZONTAL_ALIGNMENT_CENTER, S.x)
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
		var ssub: String = it["sub"]
		if item != "mine":   # Job M: how many this button fires, and the locks held right now
			var lk: int = space.lock_count(item)
			ssub = "LOCK %d/%d" % [lk, GS.max_locks(item)] if lk > 0 else "MISSILE ×%d" % GS.max_locks(item)
		_corner("slot_%d" % k, it["label"], it["icon"], scol, false, "%d" % ammo, cdk, space.warp_active(), ssub)
	var mech: bool = GS.form == "mech"
	_corner("thrust", "BOOST" if mech else "THRUST", "thrust", ORANGE, space.boosting, "", 0.0, false, "STICK = DASH" if mech else "")
	_corner("fire", "FIRE", "guns", RED, space.fire_lock, "", 0.0, space.warp_active() or not space.lane.is_empty(), "ON · TAP OFF" if space.fire_lock else "TAP = ON")
	_corner("kill", "KILL", "kill", GOLD, space.engine_kill, "", 0.0, mech, "DRIFTING" if space.engine_kill else "ENGINE")
	_pill("map", "MAP")
	_pill("view", "CHASE" if cockpit else "COCKPIT", false, CYAN, "VIEW")
	_pill("target", "TARGET", false, CYAN, "NEXT")
	_pill("goto", "GO TO", space.autopilot != null, CYAN, "AUTO")
	_pill("log", "LOG", comms_mode == "roster", CYAN, "CONTACTS")
	_pill("call", "CALL", comms_mode == "talk", GREEN)
	if buttons.has("dock"): _pill("dock", "DOCK", true, GREEN, space.dock_candidate().name.to_upper())
	if buttons.has("lane"):
		if space.lane.is_empty(): _pill("lane", "TRADE LANE", true, CYAN, "TO %s" % str(space.lane_candidate().get("to", "")).to_upper())
		else: _pill("lane", "IN LANE · %d m/s" % int(space.speed_now), true, CYAN, "TAP TO LEAVE · TO %s" % str(space.lane.get("to", "")).to_upper())
	if buttons.has("jump"): _pill("jump", "%s GATE" % str(space.near_gate().get_meta("info").get("gkind", "warp")).to_upper() if space.sys.get("generated", false) else "WARP GATE", true, GOLD, "DOCK · TO %s" % Data.SYSTEMS[space.near_gate().get_meta("info")["to"]]["name"].to_upper())
	if not (cockpit and cockpit_texture()): _dashboard()   # the cockpit art has its own dash screens
	_stick("move", "FLIGHT")
	_stick("aim", "AIM")
	if comms_open: _comms()
	_draw_scan()   # v1.5g
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
	way_rect = way_r
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
	_gps_strip(Rect2(cr.get_center().x - 230, cr.position.y - 44, 460, 34))   # v1.5i

## Radar (Job S, v1.4p): the same GPS-style view as the navigation map, small. A grid, faceted blips, a north
## marker, and the course line when one is set. North-up or heading-up, angled or overhead (NavGrid's setting).
## A tap on a blip opens the map with that object's info card.
var radar_blips: Array = []        # [world position, screen position, kind] of what was drawn (hit-testing, tests)
var radar_pick := Vector3.INF      # the world position of the blip the last radar tap landed on (INF = none)
var radar_view := NavGrid.new()
var radar_stats := {}
var radar_north := Vector2.ZERO    # where the N marker was drawn
var radar_route := {}              # {"from", "to"} when a course is drawn on the radar

func radar_pick_at(p: Vector2) -> Vector3:
	var best := Vector3.INF
	var best_d: float = Data.RADAR_HIT_RADIUS
	for bl in radar_blips:
		var d := (bl[1] as Vector2).distance_to(p)
		if d < best_d:
			best_d = d
			best = bl[0]
	return best

func _radar(rc: Vector2, rr: float, label: bool) -> void:
	var pp: Vector3 = space.player.global_position
	# v1.4m: normal range near things; far from everything (out by the sun, say) the radar zooms out until the
	# station, the planets and the gates all fit, so you can see where you are
	var want_rng: float = Data.RADAR_RANGE
	if not space.surface_mode:
		var near := INF
		var far := 0.0
		for n: Node3D in [space.station, space.planet] + space.gates + space.extras:
			if not is_instance_valid(n): continue
			var dn := pp.distance_to(n.global_position)
			near = minf(near, dn)
			far = maxf(far, dn)
		if near > Data.RADAR_RANGE: want_rng = far * Data.RADAR_FIT
	radar_range = lerpf(radar_range, want_rng, clampf(get_process_delta_time() * Data.RADAR_ZOOM_SPEED, 0.0, 1.0))
	var rng := radar_range * (1.0 - 0.6 * space.in_nebula * (1.0 - Data.BEACON_SENSOR_HELP * space.beacon_lit))
	var heading := NavGrid.orient == "heading"
	var fwd3: Vector3 = -space.player.global_basis.z
	var anchor := rc + Vector2(0, rr * Data.RADAR_HEADING_ANCHOR) if heading else rc
	radar_view.major_px = 44.0
	radar_view.setup(anchor, Vector3(pp.x, 0, pp.z), rr / rng, fwd3 if heading else Vector3.ZERO, NavGrid.tilt == "angled", rr * Data.NAV_DEPTH)
	# the scope: a polygon disc, the grid cut to it, polygon range rings
	NavGrid.fill(self, NavGrid.poly(rc, rr, 16), Color(0.01, 0.05, 0.09, 0.55))
	radar_stats = radar_view.draw_grid(self, Rect2(rc - Vector2(rr, rr), Vector2(rr, rr) * 2.0), rr)
	var rim := NavGrid.poly(rc, rr, 16)
	draw_polyline(rim + PackedVector2Array([rim[0]]), Color(CYAN, 0.75), 2.0, true)
	var half := NavGrid.poly(anchor, rr * 0.5, 16)
	for i in 16:
		var seg := NavGrid.clip_circle(half[i], half[(i + 1) % 16], rc, rr)
		if not seg.is_empty(): draw_line(seg[0], seg[1], Color(CYAN, 0.3), 1.0)
	# the course line
	radar_route = {}
	if space.autopilot != null and is_instance_valid(space.autopilot):
		var dest := radar_view.to_screen(space.autopilot.global_position)
		var rseg := NavGrid.clip_circle(anchor, dest, rc, rr)
		if not rseg.is_empty():
			NavGrid.route(self, rseg[0], rseg[1], GREEN, t, dest.distance_to(rc) <= rr, 0.5)
			radar_route = {"from": rseg[0], "to": rseg[1]}
	var items: Array = []   # [position, colour, kind, node]
	for e in space.enemies: items.append([e["node"].global_position, RED if e["node"].get_meta("kind", "enemy") == "enemy" else GOLD, "ship", e["node"]])
	for tr in space.traffic: items.append([tr["node"].global_position, GREEN, "ship", tr["node"]])
	if space.station.get_meta("kind", "") == "station": items.append([space.station.global_position, GREEN, "station", null])
	if not space.surface_mode:
		items.append([space.planet.global_position, Color(0.5, 0.8, 1.0), "planet", null])
		for g in space.gates: items.append([g.global_position, GOLD, "gate", null])
		if radar_range > Data.RADAR_RANGE * 1.2:   # zoomed out: the rest of the system shows too
			for x in space.extras:
				var big: bool = float(x.get_meta("radius", 0.0)) > 100.0
				items.append([x.global_position, Color(0.5, 0.8, 1.0) if big else GREEN, "planet" if big else "station", null])
			if space.sun_pos != Vector3.INF: items.append([space.sun_pos, Color(1.0, 0.9, 0.4), "star", null])
	radar_blips.clear()
	for it in items:
		var v: Vector2 = radar_view.to_screen(it[0])
		var off := v - rc
		if off.length() > rr - 5.0: v = rc + off.normalized() * (rr - 5.0)
		match it[2]:
			"planet": NavGrid.sphere(self, v, 6.0, it[1], 12, false)
			"station": NavGrid.ring(self, v, 6.0, it[1], 8, 0.4, 0.2)
			"gate": NavGrid.ring(self, v, 6.0, it[1], 12, 0.3, 0.15, 0.85)
			"star": NavGrid.star(self, v, 3.5, it[1])
			_:
				var nf: Vector3 = -(it[3] as Node3D).global_basis.z if is_instance_valid(it[3]) else Vector3.FORWARD
				NavGrid.dart(self, v, 5.5, Vector2(nf.x, nf.z).rotated(radar_view.rot), it[1])
		radar_blips.append([it[0], v, it[2]])
	# you: the arrow. Heading-up: fixed, pointing up. North-up: it turns with the ship.
	var hullc := GREEN.lerp(RED, 1.0 - GS.hull / GS.max_hull())
	NavGrid.dart(self, anchor, 11.0, Vector2(fwd3.x, fwd3.z).rotated(radar_view.rot), hullc.lightened(0.2), true)
	# north marker on the rim: straight up in north-up, wherever true north is in heading-up
	var nd := Vector2(0, -1).rotated(radar_view.north_angle())
	radar_north = rc + nd * rr
	var np := Vector2(-nd.y, nd.x)
	NavGrid.fill(self, PackedVector2Array([radar_north + nd * 7.0, radar_north - nd * 3.0 + np * 5.0, radar_north - nd * 3.0 - np * 5.0]), Color(1.0, 0.45, 0.4))
	draw_string(font, radar_north + nd * 15.0 + Vector2(-4, 5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WHITE)
	_text(Vector2(rc.x - rr, rc.y + rr + (-2.0 if label else 2.0)), "RADAR %s" % _dist(rng), 10, Color(CYAN, 0.8), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0)

# ---------------------------------------------------------------- v1.5i GPS strip
var gps_drawn := {}   # what the strip showed last frame (tests): {name, dist, eta, k}

## Point A (you) and point B (the destination) on a blue line; your marker slides toward B as the distance closes
## (and back if you fly away), with the name, the distance and the ETA at your current effective speed.
func _gps_strip(rc: Rect2) -> void:
	gps_drawn = {}
	var n: Node3D = space.nav_dest
	if n == null or not is_instance_valid(n): return
	var d: float = space.distance_to(n)
	var full: float = maxf(space.nav_start, d)
	var k := clampf(1.0 - d / maxf(full, 1.0), 0.0, 1.0)
	var eta: float = space.nav_eta()
	_box(rc, Color(0.01, 0.05, 0.1, 0.82), Color(Data.GPS_ROUTE_COLOR, 0.9), 8, 2)
	var x0 := rc.position.x + 34.0
	var x1 := rc.end.x - 34.0
	var y := rc.position.y + 24.0
	var col: Color = Data.GPS_ROUTE_COLOR
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(col, 0.35), 4.0)
	var xa := lerpf(x0, x1, k)
	draw_line(Vector2(xa, y), Vector2(x1, y), col, 4.0)   # the part still to fly
	draw_circle(Vector2(x1, y), 7.0, col)
	_text(Vector2(x1 + 10, y + 5), "B", 13, WHITE)
	var tri := PackedVector2Array([Vector2(xa + 9, y), Vector2(xa - 6, y - 7), Vector2(xa - 6, y + 7)])
	draw_colored_polygon(tri, WHITE)
	_text(Vector2(x0 - 24, y + 5), "A", 13, Color(1, 1, 1, 0.7))
	var eta_s := "--" if eta < 0.0 else ("%dm %02ds" % [int(eta) / 60, int(eta) % 60] if eta >= 60.0 else "%ds" % int(eta))
	var nst: int = space.nav_route.size()
	var lead := "GPS  %s" % n.name if nst <= 1 else "STOP 1/%d  %s" % [nst, n.name]
	_text(Vector2(rc.position.x + 10, rc.position.y + 12), lead, 11, WHITE, HORIZONTAL_ALIGNMENT_LEFT, rc.size.x * 0.5)
	var right := "%s  ·  ETA %s" % [_dist(d), eta_s]
	var total := d
	if nst > 1:   # the whole route too
		total = float(space.route_lengths()[1])
		var te: float = total / maxf(space.eff_speed(), 1.0)
		right += "   ROUTE %s · %s" % [_dist(total), "%dm %02ds" % [int(te) / 60, int(te) % 60] if te >= 60.0 else "%ds" % int(te)]
	_text(Vector2(rc.position.x, rc.position.y + 12), right, 11, col, HORIZONTAL_ALIGNMENT_RIGHT, rc.size.x - 10)
	gps_drawn = {"name": str(n.name), "dist": d, "eta": eta, "k": k, "stops": nst, "total": total}

# ---------------------------------------------------------------- v1.5g ship scan
var way_rect := Rect2()     # where the waypoint / target box was drawn (tap = scan)
var scan := {}              # the scan on screen ({} = none): space.scan_info() of scan_node
var scan_node: Node3D = null
var scan_t := 0.0           # > 0 while a scan is running

## Start a scan of the current target: in range, a ship, takes SCAN_TIME. Returns what to say.
func start_scan() -> String:
	var n: Node3D = space.target
	if n == null or not is_instance_valid(n): return "No target to scan."
	if space.scan_info(n).is_empty(): return "%s is not a ship." % n.name
	if space.distance_to(n) > Data.SCAN_RANGE: return "Too far to scan: get within %s." % _dist(Data.SCAN_RANGE)
	scan_node = n
	scan = {}
	scan_t = Data.SCAN_TIME
	Sfx.play("tractor", -10.0)
	return "Scanning %s..." % n.name

func close_scan() -> void:
	scan = {}
	scan_node = null
	scan_t = 0.0

func scan_rect() -> Rect2:
	return Rect2(S.x * 0.5 - 250, 132, 500, 64 + 30 * maxi(1, (scan.get("lines", []) as Array).size()))

func _tick_scan(dt: float) -> void:
	if scan_node == null: return
	if not is_instance_valid(scan_node) or space.target != scan_node:
		close_scan()
		return
	if scan_t > 0.0:
		scan_t -= dt
		if scan_t <= 0.0:
			scan = space.scan_info(scan_node)
			Sfx.play("pickup", -10.0)
	elif not scan.is_empty() and int(t * 2.0) != int((t - dt) * 2.0):
		scan = space.scan_info(scan_node)   # live hull / weapons while it is open

func _draw_scan() -> void:
	if scan_node == null or not is_instance_valid(scan_node): return
	var sp = _screen(scan_node.global_position)
	if scan_t > 0.0:   # scanning: a sweeping bracket on the ship and a progress bar
		var k := 1.0 - scan_t / Data.SCAN_TIME
		if sp != null:
			var r := 40.0 + 10.0 * sin(t * 12.0)
			draw_arc(sp, r, -PI * 0.5, -PI * 0.5 + TAU * k, 40, CYAN_HI, 3.0)
			_text(sp + Vector2(-40, -r - 10), "SCANNING %d%%" % int(k * 100.0), 13, CYAN_HI)
		return
	if scan.is_empty(): return
	var rc := scan_rect()
	var col: Color = RED if scan.get("hostile", false) else CYAN_HI
	_box(rc, Color(0.02, 0.06, 0.1, 0.9), col, 10, 2)
	_text(rc.position + Vector2(16, 28), str(scan["title"]), 18, WHITE, HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 60)
	_text(rc.position + Vector2(16, 50), str(scan["sub"]), 13, col)
	_text(Vector2(rc.end.x - 30, rc.position.y + 26), "X", 16, Color(1, 1, 1, 0.7))
	var y := rc.position.y + 80
	for ln in scan["lines"]:
		_text(Vector2(rc.position.x + 16, y), str(ln[0]), 12, GOLD)
		_text(Vector2(rc.position.x + 110, y), str(ln[1]), 13, WHITE, HORIZONTAL_ALIGNMENT_LEFT, rc.size.x - 126)
		y += 30
	if sp != null: draw_arc(sp, 34.0, 0, TAU, 32, Color(col, 0.8), 2.0)

## Waypoint box: autopilot destination, else the current target.
func _way_box(way_r: Rect2) -> void:
	_box(way_r, PANEL, EDGE, 10, 2)
	var wp: Node3D = space.autopilot if space.autopilot != null else space.target
	var mission := false   # v1.5a: nothing picked: the box shows the mission waypoint
	if not (wp and is_instance_valid(wp)):
		var mwb: Dictionary = space.mission_waypoint()
		if not mwb.is_empty():
			wp = mwb["node"]
			mission = true
	var dcol := GOLD
	if wp and is_instance_valid(wp):
		if wp.get_meta("kind", "") == "enemy": dcol = RED
		var dia := way_r.position + Vector2(20, 24)
		draw_colored_polygon(PackedVector2Array([dia + Vector2(0, -9), dia + Vector2(9, 0), dia + Vector2(0, 9), dia + Vector2(-9, 0)]), dcol)
		_text(way_r.position + Vector2(36, 22), "MISSION" if mission else ("WAYPOINT" if space.autopilot != null else "TARGET"), 12, CYAN_HI)
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
	var sens := "NORMAL"
	var scol := GREEN
	if space.in_nebula > 0.0:
		sens = "DEGRADED"
		scol = GOLD
	elif space.hostiles_near(900.0) > 0:
		sens = "%d HOSTILE" % space.hostiles_near(900.0)
		scol = RED
	_text(way_r.position + Vector2(12, 82), "SCAN  " + sens, 12, scol)
	if space.target != null and is_instance_valid(space.target) and not space.scan_info(space.target).is_empty():
		_text(way_r.position + Vector2(12, 22), "TAP = SCAN", 10, CYAN_HI, HORIZONTAL_ALIGNMENT_RIGHT, way_r.size.x - 24)

# ---------------------------------------------------------------- comms: side screens + console
func _comms() -> void:
	if console_open: _roster()
	for side in ["l", "r"]: _side(side)   # callers draw over / beside the console panels

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
	var r := contacts_rect()
	var lg := msglog_rect()
	# ---- right edge: who you can call. Faces flush right, names beside them; tap a row to call.
	draw_rect(r, Color(0.02, 0.07, 0.14, 0.9))
	draw_line(r.position, Vector2(r.position.x, r.end.y), CYAN_HI, 2)
	_text(r.position + Vector2(0, 22), "CONTACTS", 15, WHITE, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 10)
	if GS.met.is_empty():
		draw_multiline_string(font, r.position + Vector2(10, 52), "Nobody yet. People you meet appear here.", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 20, 12, 3, Color(1, 1, 1, 0.7))
	var rh: float = Data.COMMS_ROW_H
	for k in mini(GS.met.size(), contact_rows()):
		var br := Rect2(r.position.x + 6, r.position.y + 32 + k * rh, r.size.x - 6, rh - 4)
		var id: String = GS.met[k]
		var c: Dictionary = Data.CHARACTERS[id]
		var ok := in_range(id)
		var m: String = GS.mood.get(id, "neutral")
		var mc: Color = {"friendly": GREEN, "neutral": CYAN_HI, "enraged": RED}[m]
		if not ok: mc = Color(0.55, 0.6, 0.66)
		var down := held.has("met_%d" % k)
		draw_rect(br, Color(mc, 0.25) if down else Color(0.05, 0.13, 0.23, 1.0 if ok else 0.6))
		draw_rect(br, Color(mc, 0.7 if ok else 0.35), false, 1.0)
		var fs := br.size.y
		var fr := Rect2(br.end.x - fs, br.position.y, fs, fs)   # face against the screen edge
		var ftex: Texture2D = _face_tex(c.get("face", ""), "normal") if c.get("face", "") != "" else null
		if ftex: draw_texture_rect(ftex, fr, false, Color(1, 1, 1, 1.0 if ok else 0.4))
		else: draw_circle(fr.get_center(), fs * 0.4, Color(c["color"], 0.9))
		var tw := br.size.x - fs - 12
		_text(Vector2(br.position.x + 6, br.position.y + 18), c["name"], 14, WHITE if ok else Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, tw)
		var sub: String = "TAP TO CALL" if ok else "OUT OF RANGE · %s" % Data.SYSTEMS[c["system"]]["name"].to_upper()
		_text(Vector2(br.position.x + 6, br.position.y + 34), sub, 10, Color(mc, 0.95) if ok else Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, tw)
	# ---- left edge: the message log, newest at the top; TYPE and VOICE under it
	draw_rect(lg, Color(0.02, 0.07, 0.14, 0.9))
	draw_line(Vector2(lg.end.x, lg.position.y), lg.end, CYAN_HI, 2)
	_text(lg.position + Vector2(10, 22), "LOG", 15, WHITE)
	_text(lg.position + Vector2(0, 22), "TAP LOG TO CLOSE", 9, CYAN_HI, HORIZONTAL_ALIGNMENT_RIGHT, lg.size.x - 10)
	var lr := Rect2(lg.position.x + 6, lg.position.y + 32, lg.size.x - 12, lg.size.y - 32 - 50)
	draw_rect(lr, Color(1, 1, 1, 0.08))
	var y := lr.position.y + 16
	for line in history:
		if y > lr.end.y - 6: break
		var mine := (line as String).begins_with("YOU:")
		var lines := maxi(1, int(ceil(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x / (lr.size.x - 12))))
		var room := maxi(1, int((lr.end.y - y) / 15.0) + 1)
		draw_multiline_string(font, Vector2(lr.position.x + 6, y), line, HORIZONTAL_ALIGNMENT_LEFT, lr.size.x - 12, 12, mini(4, room), GOLD if mine else Color(0.85, 0.92, 1.0))
		y += 15.0 * mini(lines, 4) + 5.0
	if roster_t > 0.95 and not roster_closing:
		_pill("type", "TYPE", _typer.visible, CYAN)
		_pill("talk", "LISTENING" if listening else "HOLD TO TALK", listening, GREEN if listening else CYAN, heard_text.left(18) if listening and heard_text != "" else "")
		_pill("voice", "VOICE", false, CYAN, "ON" if Sfx.voice_on() else "OFF")
	if _typer.visible:
		_typer.position = Vector2(lg.end.x + 8, lg.end.y - 44)
		_typer.size = Vector2(minf(420.0, S.x - lg.end.x - _panel_w() - 16), 40)

## TYPE: open the message box (the phone keyboard comes up).
# ---------------------------------------------------------------- v1.5j hold-to-talk
var listening := false
var heard_text := ""
var _listen_wait := 0.0     # after release: waiting for the browser's last words (seconds left)
var speech_override := ""   # tests: pretend the browser heard this ("" = use the browser)

## Can this device turn speech into text? (Web only, and only where the browser has speech recognition.)
func speech_supported() -> bool:
	if speech_override != "": return true
	if not OS.has_feature("web"): return false
	return bool(JavaScriptBridge.eval("!!(window.__hlSR && window.__hlSR.supported)", true))

func talk_press() -> void:
	roster_idle = 0.0
	if not speech_supported():
		flash_message("Voice input isn't available on this device or browser: type instead.")
		start_typing()
		return
	listening = true
	heard_text = ""
	_listen_wait = 0.0
	Sfx.stop_voice()   # nobody talks over you
	Sfx.play("comm_open", -10.0)
	if speech_override == "" and OS.has_feature("web"): JavaScriptBridge.eval("window.__hlListenStart && window.__hlListenStart()", true)

func talk_release() -> void:
	if not listening: return
	listening = false
	if speech_override == "" and OS.has_feature("web"): JavaScriptBridge.eval("window.__hlListenStop && window.__hlListenStop()", true)
	_listen_wait = Data.TALK_FINISH_WAIT

## Every frame while listening or just after: read what the browser heard; when it is done, hand the words to the
## same place typed text goes (the character's brain answers, and the voice provider speaks the answer).
func _tick_talk(dt: float) -> void:
	if not listening and _listen_wait <= 0.0: return
	var st := "listening"
	if speech_override != "":
		heard_text = speech_override
		st = "done" if not listening else "listening"
	elif OS.has_feature("web"):
		heard_text = str(JavaScriptBridge.eval("(window.__hlSR && window.__hlSR.text) || ''", true))
		st = str(JavaScriptBridge.eval("(window.__hlSR && window.__hlSR.state) || 'error'", true))
	if listening: return
	_listen_wait -= dt
	if st == "error" and heard_text == "":
		_listen_wait = 0.0
		flash_message("Didn't catch that: type instead.")
		start_typing()
		return
	if st == "done" or _listen_wait <= 0.0:
		_listen_wait = 0.0
		var said := heard_text.strip_edges()
		heard_text = ""
		if said == "":
			flash_message("Didn't catch that: hold TALK and speak, or type.")
			return
		_log("You: %s" % said)
		typed.emit(said)

func start_typing() -> void:
	roster_idle = 0.0
	_typer.visible = true
	_typer.grab_focus()
