class_name Breakout
extends Control
## v9.2 (owner): the hub lockdown. Dock where your standing is HOSTILE or worse and the alarm goes off: the station's
## people hunt you through the hub and you are locked out of launching until you fight your way to the hangar. Each
## room is a small cover shooter: five soldiers and their squad leader behind cover (an overturned table, crates ...).
## Left stick: down = duck behind your own cover, left / right = side-step out and back. Right stick (or the mouse, or
## a drag on the right half) aims; you fire on your own while the sight is on an enemy who is out of cover.
## Enemies pop up, aim (a red line shows who and where) and fire at the spot you were in: duck or side-step to dodge.
## Evee is not with you here. Placeholder soldiers are drawn shapes until the owner's animated NPCs are in.

signal cleared            # made it to the hangar
signal room_changed(i: int)

var faction := ""
var rooms: Array = []     # room keys in order, e.g. ["main_hub", "pilots_lounge", "shipyard"]
var room_i := 0
var strip: Texture2D      # the room picture (hostile if there is one)
var tint := Color(1, 1, 1)
var hp := 100.0
var enemies: Array = []   # {x, y, s, cover, hp, max, leader, state, t, lane, aim_t, flash}
var lane := 0             # -1 left, 0 middle, 1 right (side-step)
var ducked := false
var aim := Vector2(0.5, 0.45)   # the sight, as a fraction of the screen
var shots_fired := 0      # (tests)
var hits_taken := 0       # (tests)
var dodged := 0           # (tests) enemy shots that missed because you ducked or side-stepped
var state := "fight"      # fight / clear / down / done
var state_t := 0.0
var _rng := RandomNumberGenerator.new()
var _fire_cd := 0.0
var _tracers: Array = []  # {a, b, t, col}
var _pops: Array = []     # {p, text, t, col}
var _alarm_t := 0.0
var _pan := 0.0           # where in the room strip the view looks (0..1)
var _lstick := Vector2.ZERO
var _rstick := Vector2.ZERO
var _touch_l := -1
var _touch_r := -1
var _touch_l0 := Vector2.ZERO
var _touch_r_last := Vector2.ZERO
var _siren: AudioStreamPlayer
var _siren_pb: AudioStreamGeneratorPlayback
var _siren_phase := 0.0
var _siren_t := 0.0
var font: Font = ThemeDB.fallback_font

const COLORS := {"liberator": Color(0.2, 0.75, 0.7), "savagers": Color(0.95, 0.45, 0.15), "elyza": Color(0.35, 0.55, 1.0), "orion": Color(0.3, 0.85, 0.45)}

func start(fac: String, room_list: Array) -> void:
	faction = fac
	rooms = room_list
	room_i = 0
	_rng.seed = hash(fac + str(Time.get_ticks_msec()))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	_start_siren()
	_enter_room()

func _enter_room() -> void:
	hp = Data.BREAKOUT_HP
	lane = 0
	ducked = false
	aim = Vector2(0.5, 0.45)
	state = "fight"
	state_t = 0.0
	_tracers.clear()
	_pops.clear()
	_pan = _rng.randf_range(0.05, 0.75)
	strip = _room_texture(str(rooms[room_i]))
	enemies.clear()
	# five soldiers and the squad leader, each behind their own cover, spread across the room at three depths
	var n: int = Data.BREAKOUT_SOLDIERS + 1
	for i in n:
		var leader := i == n - 1
		var depth := _rng.randf_range(0.0, 1.0) if not leader else 0.35
		var x := (float(i) + 0.5) / float(n) + _rng.randf_range(-0.04, 0.04)
		if leader: x = 0.5 + _rng.randf_range(-0.12, 0.12)
		var mx: float = Data.BREAKOUT_LEADER_HP if leader else Data.BREAKOUT_SOLDIER_HP
		enemies.append({"x": clampf(x, 0.08, 0.92), "y": lerpf(0.56, 0.7, depth), "s": lerpf(0.75, 1.15, depth) * (1.18 if leader else 1.0),
			"cover": ["table", "crate", "console"][_rng.randi() % 3] if not leader else "table", "hp": mx, "max": mx, "leader": leader,
			"state": "hide", "t": _rng.randf_range(0.6, 2.8), "lane": 0, "flash": 0.0})
	room_changed.emit(room_i)
	queue_redraw()

func _room_texture(rn: String) -> Texture2D:
	var hp_path := "res://assets/rooms_hostile/%s/%s.jpg" % [faction, rn]
	tint = Color(1, 1, 1)
	if ResourceLoader.exists(hp_path): return load(hp_path)
	var np := "res://assets/rooms/%s/%s.jpg" % [faction, rn]
	tint = Color(1.0, 0.55, 0.5)   # (no lockdown picture for this faction yet: the normal room, lit red)
	if ResourceLoader.exists(np): return load(np)
	return null

## ---------------------------------------------------------------- input
func _input(e: InputEvent) -> void:
	if not visible: return
	var S := size
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			if t.position.x < S.x * 0.5 and _touch_l < 0:
				_touch_l = t.index
				_touch_l0 = t.position
			elif t.position.x >= S.x * 0.5 and _touch_r < 0:
				_touch_r = t.index
				_touch_r_last = t.position
		else:
			if t.index == _touch_l:
				_touch_l = -1
				_lstick = Vector2.ZERO
			if t.index == _touch_r: _touch_r = -1
		accept_event()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _touch_l: _lstick = ((d.position - _touch_l0) / 70.0).limit_length(1.0)
		elif d.index == _touch_r:
			aim += (d.position - _touch_r_last) / S * 1.3
			_touch_r_last = d.position
		accept_event()
	elif e is InputEventMouseMotion and not DisplayServer.is_touchscreen_available():
		aim = (e as InputEventMouseMotion).position / S
	aim = aim.clamp(Vector2(0.02, 0.05), Vector2(0.98, 0.95))

var stick_hold: Variant = null   # (tests) a left stick held in place
func _read_sticks(dt: float) -> void:
	if stick_hold != null:
		set_stance(stick_hold)
		return
	var l := _lstick
	var kb := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	if kb.length() > 0.1: l = kb
	var jl := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if jl.length() > 0.3: l = jl
	var jr := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if jr.length() > 0.2: aim = (aim + jr * dt * 0.9).clamp(Vector2(0.02, 0.05), Vector2(0.98, 0.95))
	set_stance(l)

## The left stick: pushed down = duck; left / right = side-step; let go = back to your spot.
func set_stance(l: Vector2) -> void:
	ducked = l.y > 0.55 and absf(l.y) >= absf(l.x)
	lane = 0
	if not ducked and absf(l.x) > 0.5: lane = -1 if l.x < 0.0 else 1

## ---------------------------------------------------------------- the fight
func _process(dt: float) -> void:
	if not visible: return
	_alarm_t += dt
	_feed_siren(dt)
	state_t += dt
	for t in _tracers: t["t"] -= dt
	_tracers = _tracers.filter(func(t): return t["t"] > 0.0)
	for p in _pops: p["t"] -= dt
	_pops = _pops.filter(func(p): return p["t"] > 0.0)
	match state:
		"fight":
			_read_sticks(dt)
			_update_enemies(dt)
			_auto_fire(dt)
			if hp <= 0.0:
				state = "down"
				state_t = 0.0
			elif enemies.all(func(e): return e["hp"] <= 0.0):
				state = "clear"
				state_t = 0.0
		"clear":
			if state_t > Data.BREAKOUT_CLEAR_PAUSE: next_room()
		"down":
			if state_t > Data.BREAKOUT_DOWN_PAUSE: _enter_room()   # back up, same room, all of them again
	queue_redraw()

func next_room() -> void:
	room_i += 1
	if room_i >= rooms.size():
		state = "done"
		visible = false
		_stop_siren()
		cleared.emit()
		return
	_enter_room()

func _update_enemies(dt: float) -> void:
	for e in enemies:
		if e["hp"] <= 0.0: continue
		e["t"] -= dt
		e["flash"] = maxf(0.0, e["flash"] - dt)
		match e["state"]:
			"hide":
				if e["t"] <= 0.0:
					e["state"] = "aim"
					e["t"] = Data.BREAKOUT_AIM_TIME * (0.8 if e["leader"] else 1.0)
					e["lane"] = lane   # it aims where you are now
			"aim":
				if e["t"] <= 0.0:
					_enemy_fire(e)
					e["state"] = "up"
					e["t"] = _rng.randf_range(0.5, 1.1)
			"up":
				if e["t"] <= 0.0:
					e["state"] = "hide"
					e["t"] = _rng.randf_range(Data.BREAKOUT_HIDE[0], Data.BREAKOUT_HIDE[1])

func _enemy_fire(e: Dictionary) -> void:
	var from := _enemy_head(e)
	var to := Vector2(size.x * (0.5 + 0.28 * float(e["lane"])), size.y * 0.98)
	_tracers.append({"a": from, "b": to, "t": 0.12, "col": Color(1.0, 0.25, 0.2)})
	Sfx.play("blaster_red", -8.0)
	if ducked or lane != int(e["lane"]):
		dodged += 1
		return
	var dmg: float = Data.BREAKOUT_LEADER_DMG if e["leader"] else Data.BREAKOUT_SOLDIER_DMG
	hp -= dmg
	hits_taken += 1
	Sfx.play("hull_hit", -6.0)

## You fire on your own while the sight is on an enemy who is out of cover (and you are not ducking).
func _auto_fire(dt: float) -> void:
	_fire_cd -= dt
	if ducked or _fire_cd > 0.0: return
	var t: Variant = target_under_sight()
	if t == null: return
	_fire_cd = 1.0 / Data.BREAKOUT_FIRE_RATE
	shoot(t)

func shoot(e: Dictionary) -> void:
	shots_fired += 1
	var from := Vector2(size.x * (0.5 + 0.18 * float(lane)), size.y)
	_tracers.append({"a": from, "b": _enemy_head(e) + Vector2(0, 20), "t": 0.06, "col": Color(0.5, 0.9, 1.0)})
	Sfx.play("blaster_blue", -12.0)
	e["hp"] -= Data.BREAKOUT_SHOT_DMG
	e["flash"] = 0.08
	if e["hp"] <= 0.0:
		_pops.append({"p": _enemy_head(e), "text": "SQUAD LEADER DOWN" if e["leader"] else "DOWN", "t": 1.0, "col": Color(1, 0.85, 0.4)})
		Sfx.play("explosion", -14.0)

func exposed(e: Dictionary) -> bool:
	return e["hp"] > 0.0 and e["state"] in ["aim", "up"]

func target_under_sight() -> Variant:
	var p := aim * size
	for e in enemies:
		if exposed(e) and _enemy_rect(e).has_point(p): return e
	return null

## ---------------------------------------------------------------- layout (shared by drawing, aiming and the tests)
func _view_off() -> Vector2:   # side-stepping moves the view; ducking drops it
	return Vector2(-float(lane) * size.x * 0.08, size.y * (0.1 if ducked else 0.0))

func _enemy_base(e: Dictionary) -> Vector2:
	return Vector2(e["x"] * size.x, e["y"] * size.y) + _view_off()

func _enemy_h(e: Dictionary) -> float:
	return size.y * 0.24 * float(e["s"])

func _enemy_rect(e: Dictionary) -> Rect2:
	var b := _enemy_base(e)
	var h := _enemy_h(e)
	var w := h * 0.42
	return Rect2(b.x - w * 0.5, b.y - h, w, h * 0.6)   # (the part above the cover)

func _enemy_head(e: Dictionary) -> Vector2:
	var b := _enemy_base(e)
	return b - Vector2(0, _enemy_h(e) * 0.9)

func aim_at(e: Dictionary) -> void:   # (tests and a nudge for touch) put the sight on an enemy
	var r := _enemy_rect(e)
	aim = (r.get_center()) / size

## ---------------------------------------------------------------- drawing
func _draw() -> void:
	var S := size
	var off := _view_off()
	# the room
	if strip != null:
		var th := float(strip.get_height())
		var vw := th * S.x / S.y * 0.86
		var sx := clampf(_pan * float(strip.get_width()) + off.x * 0.6, 0.0, strip.get_width() - vw)
		var sy := th * 0.07 + off.y * 0.25
		draw_texture_rect_region(strip, Rect2(Vector2.ZERO, S), Rect2(sx, sy, vw, th * 0.86), tint)
	else:
		draw_rect(Rect2(Vector2.ZERO, S), Color(0.18, 0.03, 0.03))
	# the alarm: the room pulses red
	var pulse := 0.5 + 0.5 * sin(_alarm_t * TAU * 1.1)
	draw_rect(Rect2(Vector2.ZERO, S), Color(1.0, 0.05, 0.02, 0.07 + 0.12 * pulse))
	var col: Color = COLORS.get(faction, Color(0.9, 0.2, 0.2))
	# the enemies (back to front) and their cover
	var order := enemies.duplicate()
	order.sort_custom(func(a, b): return a["y"] < b["y"])
	for e in order: _draw_enemy(e, col)
	# shots
	for t in _tracers: draw_line(t["a"], t["b"], t["col"], 4.0)
	# aim lines: who is about to fire, and at which spot
	for e in enemies:
		if e["hp"] > 0.0 and e["state"] == "aim":
			var to := Vector2(S.x * (0.5 + 0.28 * float(e["lane"])), S.y * 0.98)
			draw_line(_enemy_head(e), to, Color(1, 0.1, 0.1, 0.35 + 0.4 * pulse), 2.0)
	# your own cover across the bottom (bigger when you duck)
	var ch := S.y * (0.32 if ducked else 0.16)
	var cx := S.x * 0.5 - float(lane) * S.x * 0.3
	var cw := S.x * 0.7
	draw_rect(Rect2(cx - cw * 0.5, S.y - ch, cw, ch), Color(0.08, 0.08, 0.1, 0.95))
	draw_rect(Rect2(cx - cw * 0.5, S.y - ch, cw, 8), Color(0.35, 0.36, 0.4))
	# the sight
	var a := aim * S
	var on := target_under_sight() != null and not ducked
	var sc := Color(1, 0.35, 0.3) if on else Color(1, 1, 1, 0.9)
	draw_arc(a, 26, 0, TAU, 32, sc, 3.0)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]: draw_line(a + d * 14, a + d * 38, sc, 3.0)
	# words
	for p in _pops: draw_string(font, p["p"] - Vector2(80, 30), p["text"], HORIZONTAL_ALIGNMENT_CENTER, 160, 22, p["col"])
	_draw_hud(S, pulse)
	_draw_sticks(S)

func _draw_enemy(e: Dictionary, col: Color) -> void:
	var b := _enemy_base(e)
	var h := _enemy_h(e)
	var w := h * 0.42
	var up := exposed(e)
	var dead: bool = e["hp"] <= 0.0
	var body := Color(0.1, 0.1, 0.12) if not dead else Color(0.1, 0.1, 0.1, 0.5)
	if e["flash"] > 0.0: body = Color(1, 1, 1)
	if up and not dead:   # head, helmet stripe in the faction colour, shoulders, rifle
		var top := b.y - h
		draw_rect(Rect2(b.x - w * 0.5, top + h * 0.22, w, h * 0.5), body)
		draw_circle(Vector2(b.x, top + h * 0.12), w * 0.28, body)
		draw_rect(Rect2(b.x - w * 0.3, top + h * 0.06, w * 0.6, h * 0.05), col)
		draw_rect(Rect2(b.x - w * 0.5, top + h * 0.22, w, h * 0.06), col)
		draw_rect(Rect2(b.x - w * 0.9, top + h * 0.34, w * 0.9, h * 0.05), Color(0.3, 0.3, 0.32))
		if e["leader"]: draw_string(font, Vector2(b.x - 80, top - 8), "SQUAD LEADER", HORIZONTAL_ALIGNMENT_CENTER, 160, 16, col)
		var bw := w * 1.1   # their health
		draw_rect(Rect2(b.x - bw * 0.5, top - 4, bw, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(b.x - bw * 0.5, top - 4, bw * float(e["hp"]) / float(e["max"]), 4), Color(1, 0.3, 0.25))
	# the cover in front of them
	var cw := w * (2.6 if e["cover"] == "table" else 1.8)
	var chh := h * (0.42 if e["cover"] == "table" else 0.48)
	var cr := Rect2(b.x - cw * 0.5, b.y - chh, cw, chh)
	match e["cover"]:
		"table":   # an overturned table: the top towards you, the legs sticking up
			draw_rect(cr, Color(0.16, 0.14, 0.15))
			draw_rect(Rect2(cr.position, Vector2(cr.size.x, 5)), Color(0.45, 0.42, 0.4))
			for k in [0.15, 0.85]: draw_rect(Rect2(cr.position.x + cr.size.x * k - 3, cr.position.y - chh * 0.35, 6, chh * 0.35), Color(0.3, 0.28, 0.27))
		"crate":
			draw_rect(cr, Color(0.25, 0.2, 0.12))
			draw_rect(cr, Color(0.55, 0.42, 0.2), false, 3.0)
			draw_line(cr.position, cr.end, Color(0.55, 0.42, 0.2), 2.0)
		_:
			draw_rect(cr, Color(0.12, 0.13, 0.16))
			draw_rect(Rect2(cr.position + Vector2(6, 6), Vector2(cr.size.x - 12, cr.size.y * 0.35)), Color(0.2, 0.5, 0.8, 0.8))

func _draw_hud(S: Vector2, pulse: float) -> void:
	draw_rect(Rect2(0, 0, S.x, 44), Color(0.25, 0, 0, 0.55 + 0.25 * pulse))
	var left := enemies.filter(func(e): return e["hp"] > 0.0).size()
	draw_string(font, Vector2(16, 30), "LOCKDOWN  ·  %s STATION SECURITY  ·  FIGHT TO THE HANGAR (%d/%d)  ·  %d LEFT" % [faction.to_upper(), room_i + 1, rooms.size(), left],
		HORIZONTAL_ALIGNMENT_LEFT, S.x - 32, 20, Color(1, 0.9, 0.85))
	var bw := 280.0
	draw_rect(Rect2(16, 54, bw, 14), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(16, 54, bw * maxf(0.0, hp) / Data.BREAKOUT_HP, 14), Color(0.4, 1.0, 0.6))
	draw_string(font, Vector2(16 + bw + 10, 67), "DUCKING" if ducked else ("SIDE-STEP %s" % ("LEFT" if lane < 0 else "RIGHT") if lane != 0 else ""), HORIZONTAL_ALIGNMENT_LEFT, 240, 16, Color(1, 1, 1))
	if state == "clear":
		draw_string(font, Vector2(0, S.y * 0.4), "ROOM CLEAR" if room_i < rooms.size() - 1 else "HANGAR REACHED", HORIZONTAL_ALIGNMENT_CENTER, S.x, 48, Color(0.5, 1, 0.6))
	elif state == "down":
		draw_string(font, Vector2(0, S.y * 0.4), "YOU WENT DOWN. AGAIN...", HORIZONTAL_ALIGNMENT_CENTER, S.x, 44, Color(1, 0.4, 0.35))

func _draw_sticks(S: Vector2) -> void:
	var lc := Vector2(130, S.y - 130)
	var rc := Vector2(S.x - 130, S.y - 130)
	for c in [lc, rc]: draw_arc(c, 80, 0, TAU, 40, Color(1, 1, 1, 0.25), 3.0)
	draw_circle(lc + _lstick * 60.0, 30, Color(1, 1, 1, 0.3))
	draw_string(font, lc + Vector2(-80, 104), "DUCK / SIDE-STEP", HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(1, 1, 1, 0.6))
	draw_string(font, rc + Vector2(-80, 104), "AIM (AUTO FIRE)", HORIZONTAL_ALIGNMENT_CENTER, 160, 14, Color(1, 1, 1, 0.6))

## ---------------------------------------------------------------- the alarm (a two-tone siren, made on the fly)
func _start_siren() -> void:
	if _siren != null: return
	_siren = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.25
	_siren.stream = gen
	_siren.volume_db = -20.0
	add_child(_siren)
	_siren.play()
	_siren_pb = _siren.get_stream_playback() as AudioStreamGeneratorPlayback

func _feed_siren(dt: float) -> void:
	if _siren_pb == null: return
	_siren_t += dt
	var on := _siren_t < Data.BREAKOUT_SIREN_SECONDS   # it wails at the start of the lockdown, then the fight takes over
	var n := _siren_pb.get_frames_available()
	for i in n:
		var f := 660.0 if fmod(_siren_t + float(i) / 22050.0, 0.9) < 0.45 else 880.0
		_siren_phase = fmod(_siren_phase + f / 22050.0, 1.0)
		var v := (0.35 * sin(_siren_phase * TAU)) if on else 0.0
		_siren_pb.push_frame(Vector2(v, v))

func _stop_siren() -> void:
	if _siren != null:
		_siren.stop()
		_siren.queue_free()
		_siren = null
		_siren_pb = null
