class_name Breakout
extends Control
## v9.2 (owner): the hub lockdown. Dock where your standing is HOSTILE or worse and the alarm goes off: the station's
## people hunt you through the hub and you are locked out of launching until you fight your way to the hangar.
## Evee is not with you here.
##
## v9.6 (owner's rules for the mini game):
## - No cover. Every guard wears a FORCE FIELD; it only drops while they fire (the aim and the shot), so that is when
##   you can hit them. A red line shows who is about to fire and at which spot: duck or side-step, then fire back.
## - Left stick: down = duck, left / right = side-step (let go = back to your spot). Right stick (or the mouse, or a
##   drag on the right half) aims; you fire on your own while the sight is on a guard (its field stops the shot
##   unless it is firing).
## - Rank decides how many hits a guard takes: their roster rank, 1 (common trooper) to 6 (the faction's leader).
## - Guards move left and right, each inside its own ZONE of the floor (Data.BREAKOUT_ZONES), so nobody wanders all
##   over the picture; a zone holds one guard at a time and newcomers walk in from the side.
## - Sometimes a guard rushes you: then it is a LASER BLADE duel, rock-paper-scissors style. The guard winds up a
##   strike from the LEFT, the RIGHT or HIGH: side-step away from it (left strike -> step right, right strike -> step
##   left) or duck under a high one, and you counter and land a hit; get it wrong and you are cut. Their hits to beat
##   are their rank again.
## - Waves: each room has its waves (Data.BREAKOUT_WAVES: five, and in the hangar five and then ten), at most
##   Data.BREAKOUT_MAX_ON_FLOOR on the floor at once; after the last wave their boss comes out (a named squad leader,
##   the faction's leader in the hangar).
## The guards are the owner's character pictures for now (his animated fighters replace them later).

signal cleared            # made it to the hangar
signal room_changed(i: int)

var faction := ""
var rooms: Array = []     # room keys in order, e.g. ["main_hub", "pilots_lounge", "shipyard"]
var room_i := 0
var strip: Texture2D      # the room picture (the lockdown one if there is one)
var tint := Color(1, 1, 1)
var hp := 100.0
var enemies: Array = []   # the guards on the floor (see _spawn)
var queue: Array = []     # guards still to come in this wave (roster slots)
var wave_i := 0
var boss_out := false
var lane := 0             # -1 left, 0 middle, 1 right (side-step)
var ducked := false
var aim := Vector2(0.5, 0.45)   # the sight, as a fraction of the screen
var duel: Dictionary = {}       # the guard you are fighting blade to blade (empty = none)
var duel_phase := ""            # "windup" (the strike is coming) / "recover"
var duel_side := ""             # "left" / "right" / "high"
var duel_t := 0.0
var shots_fired := 0      # (tests)
var hits_taken := 0       # (tests)
var dodged := 0           # (tests) enemy shots that missed because you ducked or side-stepped
var shield_blocks := 0    # (tests) shots that bounced off a force field
var counters := 0         # (tests) blade strikes you dodged and answered
var cuts := 0             # (tests) blade strikes that got you
var state := "fight"      # fight / clear / down / done
var state_t := 0.0
var cast := {}            # slot -> {"name", "rank", "full": Texture2D, "portrait": Texture2D} (v9.3)
var squad_leader := {}    # the boss of this room (from the cast)
var stick_hold: Variant = null   # (tests) a left stick held in place
var _rng := RandomNumberGenerator.new()
var _fire_cd := 0.0
var _tracers: Array = []  # {a, b, t, col}
var _pops: Array = []     # {p, text, t, col}
var _alarm_t := 0.0
var _pan := 0.0
var _lstick := Vector2.ZERO
var _touch_l := -1
var _touch_r := -1
var _touch_l0 := Vector2.ZERO
var _touch_r_last := Vector2.ZERO
var _siren: AudioStreamPlayer
var _siren_pb: AudioStreamGeneratorPlayback
var _siren_phase := 0.0
var _siren_t := 0.0
var _serial := 0
var font: Font = ThemeDB.fallback_font

const COLORS := {"liberator": Color(0.2, 0.75, 0.7), "savagers": Color(0.95, 0.45, 0.15), "elyza": Color(0.35, 0.55, 1.0), "orion": Color(0.3, 0.85, 0.45),
	"unity": Color(0.4, 0.7, 1.0), "covenant": Color(0.75, 0.6, 1.0), "imperium": Color(0.95, 0.25, 0.25), "solarion": Color(1.0, 0.8, 0.3)}

func start(fac: String, room_list: Array) -> void:
	faction = fac
	rooms = room_list
	room_i = 0
	_rng.seed = hash(fac + str(Time.get_ticks_msec()))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	_start_siren()
	_load_cast()
	_enter_room()
	if not Packs.pack_ready.is_connected(_on_pack): Packs.pack_ready.connect(_on_pack)

## v9.3: on the web the lockdown pictures and the cast arrive a moment later: swap them in as they land.
func _on_pack(pk: String) -> void:
	if not visible or state == "done": return
	if pk == "chars_" + faction:
		_load_cast()
		squad_leader = cast.get(_boss_slot(), {})
	elif room_i < rooms.size() and pk == "room_hostile_%s_%s" % [faction, rooms[room_i]]:
		strip = _room_texture(str(rooms[room_i]))
	queue_redraw()

## v9.3: the faction's six people from the roster (names from the game's lore), with their cut-out pictures.
func _load_cast() -> void:
	cast = {}
	var fk := ""
	for k in Data.ROSTERS:
		var kl := str(k).to_lower()
		if kl == faction or kl.begins_with(faction) or faction.begins_with(kl): fk = str(k)
	if fk == "": return
	for p in Data.ROSTERS[fk].get("pilots", []):
		var cid := str(p.get("character_id", ""))
		if cid == "": continue
		var fp := "res://assets/characters/%s/%s_full.webp" % [faction, cid]
		var pp := "res://assets/characters/%s/%s_portrait.webp" % [faction, cid]
		cast[int(p.get("slot", 0))] = {"name": str(p.get("name", "")), "id": cid, "rank": int(p.get("rank", p.get("slot", 1))),
			"full": load(fp) if ResourceLoader.exists(fp) else null, "portrait": load(pp) if ResourceLoader.exists(pp) else null}

func _boss_slot() -> int:
	if room_i == rooms.size() - 1: return Data.BREAKOUT_FINAL_LEADER
	var ls: Array = Data.BREAKOUT_LEADER_SLOTS
	return int(ls[room_i % ls.size()])

func _rank_of(slot: int) -> int:
	return clampi(int(cast.get(slot, {}).get("rank", slot)), 1, 6)

func _enter_room() -> void:
	hp = Data.BREAKOUT_HP
	lane = 0
	ducked = false
	aim = Vector2(0.5, 0.45)
	state = "fight"
	state_t = 0.0
	duel = {}
	_tracers.clear()
	_pops.clear()
	_pan = _rng.randf_range(0.05, 0.75)
	strip = _room_texture(str(rooms[room_i]))
	enemies.clear()
	wave_i = 0
	boss_out = false
	squad_leader = cast.get(_boss_slot(), {})
	_start_wave()
	room_changed.emit(room_i)
	queue_redraw()

func waves() -> Array:
	var w: Array = Data.BREAKOUT_WAVES
	return w[mini(room_i, w.size() - 1)]

func _start_wave() -> void:
	queue.clear()
	var n: int = int(waves()[wave_i])
	var ss: Array = Data.BREAKOUT_SOLDIER_SLOTS
	for i in n: queue.append(int(ss[(i + wave_i) % ss.size()]))
	_fill_floor(true)

## Free zones get the next guards in the queue (walking in from the nearer side).
func _fill_floor(at_once := false) -> void:
	var used := {}
	for e in enemies:
		if e["hp"] > 0 and not e["boss"]: used[int(e["zone"])] = true
	var zones: Array = Data.BREAKOUT_ZONES
	var on_floor := enemies.filter(func(e): return e["hp"] > 0).size()
	for zi in zones.size():
		if queue.is_empty() or on_floor >= Data.BREAKOUT_MAX_ON_FLOOR: break
		if used.has(zi): continue
		_spawn(int(queue.pop_front()), zi, false, at_once)
		on_floor += 1

func _spawn(slot: int, zi: int, boss: bool, at_once := false) -> Dictionary:
	var z: Array = Data.BREAKOUT_BOSS_ZONE if boss else Data.BREAKOUT_ZONES[zi]
	var x := _rng.randf_range(float(z[0]), float(z[1]))
	var from_left := x < 0.5
	_serial += 1
	var rk := _rank_of(slot)
	var e := {"id": _serial, "slot": slot, "rank": rk, "hp": rk, "max": rk, "zone": zi, "boss": boss, "x0": float(z[0]), "x1": float(z[1]), "depth": float(z[2]),
		"x": x if at_once else (-0.08 if from_left else 1.08), "goal": x, "dir": 1.0 if from_left else -1.0,
		"state": "patrol" if at_once else "enter", "t": _rng.randf_range(Data.BREAKOUT_CALM[0], Data.BREAKOUT_CALM[1]) + (0.6 if at_once else 0.0),
		"lane": 0, "flash": 0.0, "dead_t": 0.0, "muzzle": 0.0, "ripple": 0.0, "rush": 0.0, "flip": _rng.randf() < 0.5, "leader": boss}
	enemies.append(e)
	return e

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
			if not duel.is_empty(): _update_duel(dt)
			_update_enemies(dt)
			if duel.is_empty(): _auto_fire(dt)
			if hp <= 0.0:
				state = "down"
				state_t = 0.0
			else: _waves_step()
		"clear":
			if state_t > Data.BREAKOUT_CLEAR_PAUSE: next_room()
		"down":
			if state_t > Data.BREAKOUT_DOWN_PAUSE: _enter_room()   # back up, same room, from its first wave
	queue_redraw()

func _waves_step() -> void:
	var alive := enemies.filter(func(e): return e["hp"] > 0).size()
	if not queue.is_empty():
		_fill_floor()
		return
	if alive > 0: return
	if wave_i < waves().size() - 1:
		wave_i += 1
		_start_wave()
	elif not boss_out:
		boss_out = true
		squad_leader = cast.get(_boss_slot(), {})
		var b := _spawn(_boss_slot(), -1, true)
		_pops.append({"p": Vector2(size.x * 0.5, size.y * 0.3), "text": "%s COMES OUT" % (str(squad_leader.get("name", "THE SQUAD LEADER")).to_upper()), "t": 1.6, "col": Color(1, 0.85, 0.4)})
		b["t"] = 1.4
	else:
		state = "clear"
		state_t = 0.0

func next_room() -> void:
	room_i += 1
	if room_i >= rooms.size():
		state = "done"
		visible = false
		_stop_siren()
		cleared.emit()
		return
	_enter_room()

## A guard's force field is up unless it is firing (the aim and the shot), dead, or blade-fighting you.
func shielded(e: Dictionary) -> bool:
	return e["hp"] > 0 and not (e["state"] in ["aim", "fire"]) and duel.get("id", -1) != e["id"]

func _update_enemies(dt: float) -> void:
	for e in enemies:
		e["muzzle"] = maxf(0.0, float(e["muzzle"]) - dt)
		e["ripple"] = maxf(0.0, float(e["ripple"]) - dt)
		e["flash"] = maxf(0.0, float(e["flash"]) - dt)
		if e["hp"] <= 0:
			e["dead_t"] = float(e["dead_t"]) + dt
			continue
		if duel.get("id", -1) == e["id"]: continue
		var hold := not duel.is_empty()   # (while you duel one of them the rest hold their fire)
		e["t"] -= dt
		match e["state"]:
			"enter":   # walking in from the side to its zone
				e["x"] = move_toward(float(e["x"]), float(e["goal"]), dt * Data.BREAKOUT_WALK * 1.6)
				if absf(float(e["x"]) - float(e["goal"])) < 0.002: e["state"] = "patrol"
			"patrol":   # back and forth inside its own zone
				e["x"] = float(e["x"]) + float(e["dir"]) * dt * Data.BREAKOUT_WALK
				if e["x"] >= e["x1"]:
					e["x"] = e["x1"]
					e["dir"] = -1.0
				elif e["x"] <= e["x0"]:
					e["x"] = e["x0"]
					e["dir"] = 1.0
				if e["t"] <= 0.0 and not hold:
					if duel.is_empty() and not e["boss"] and _rng.randf() < Data.BREAKOUT_RUSH_CHANCE and enemies.all(func(o): return o["state"] != "rush"):
						e["state"] = "rush"
						e["rush"] = 0.0
					else:
						e["state"] = "aim"
						e["t"] = Data.BREAKOUT_AIM_TIME * (0.8 if e["boss"] else 1.0)
						e["lane"] = lane   # it aims where you are now
			"aim":
				if e["t"] <= 0.0:
					_enemy_fire(e)
					e["state"] = "fire"
					e["t"] = Data.BREAKOUT_FIRE_TIME
			"fire":   # just fired: still open for a moment, then the field comes back
				if e["t"] <= 0.0:
					e["state"] = "patrol"
					e["t"] = _rng.randf_range(Data.BREAKOUT_CALM[0], Data.BREAKOUT_CALM[1])
			"rush":   # runs at you: then it is blades
				e["rush"] = minf(1.0, float(e["rush"]) + dt / Data.BREAKOUT_RUSH_TIME)
				e["x"] = lerpf(float(e["x"]), 0.5, dt * 2.0)
				if e["rush"] >= 1.0: start_duel(e)

func _enemy_fire(e: Dictionary) -> void:
	var from := _enemy_head(e)
	e["muzzle"] = 0.09
	var to := Vector2(size.x * (0.5 + 0.28 * float(e["lane"])), size.y * 0.98)
	_tracers.append({"a": from, "b": to, "t": 0.12, "col": Color(1.0, 0.25, 0.2)})
	Sfx.play("blaster_red", -8.0)
	if ducked or lane != int(e["lane"]):
		dodged += 1
		return
	hp -= Data.BREAKOUT_DMG_PER_RANK * float(e["rank"]) + Data.BREAKOUT_DMG_BASE
	hits_taken += 1
	Sfx.play("hull_hit", -6.0)

## You fire on your own while the sight is on a guard. Its force field stops the shot unless it is firing.
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
	_tracers.append({"a": from, "b": _enemy_rect(e).get_center(), "t": 0.06, "col": Color(0.5, 0.9, 1.0)})
	Sfx.play("blaster_blue", -12.0)
	if shielded(e):
		e["ripple"] = 0.25
		shield_blocks += 1
		return
	_hurt(e)

func _hurt(e: Dictionary) -> void:
	e["hp"] = int(e["hp"]) - 1
	e["flash"] = 0.1
	if e["hp"] <= 0:
		_pops.append({"p": _enemy_head(e), "text": ("%s DOWN" % str(cast.get(int(e["slot"]), {}).get("name", "LEADER")).to_upper()) if e["boss"] else "DOWN", "t": 1.0, "col": Color(1, 0.85, 0.4)})
		Sfx.play("explosion", -14.0)
		if duel.get("id", -1) == e["id"]: duel = {}

func target_under_sight() -> Variant:
	var p := aim * size
	for e in enemies:
		if e["hp"] > 0 and e["state"] != "enter" and _enemy_rect(e).has_point(p): return e
	return null

## ---------------------------------------------------------------- the laser blade duel
func start_duel(e: Dictionary) -> void:
	duel = e
	e["state"] = "duel"
	_duel_next()

func _duel_next() -> void:
	duel_phase = "windup"
	duel_side = ["left", "right", "high"][_rng.randi() % 3]
	duel_t = Data.BREAKOUT_DUEL_WINDUP * (0.85 if duel.get("boss", false) else 1.0)

## The right answer to each strike: step away from the side it comes from, duck under a high one.
static func dodge_for(side: String) -> String:
	return {"left": "right", "right": "left", "high": "duck"}[side]

func stance_name() -> String:
	if ducked: return "duck"
	return "left" if lane < 0 else ("right" if lane > 0 else "stand")

func _update_duel(dt: float) -> void:
	duel_t -= dt
	if duel_t > 0.0: return
	if duel_phase == "windup":   # the strike lands now: did you read it?
		if stance_name() == dodge_for(duel_side):
			counters += 1
			_pops.append({"p": Vector2(size.x * 0.5, size.y * 0.35), "text": "COUNTER!", "t": 0.7, "col": Color(0.5, 1, 0.7)})
			Sfx.play("blaster_blue", -6.0)
			_hurt(duel)
		else:
			cuts += 1
			hp -= Data.BREAKOUT_BLADE_DMG
			hits_taken += 1
			_pops.append({"p": Vector2(size.x * 0.5, size.y * 0.35), "text": "CUT!", "t": 0.7, "col": Color(1, 0.4, 0.35)})
			Sfx.play("hull_hit", -4.0)
		duel_phase = "recover"
		duel_t = Data.BREAKOUT_DUEL_RECOVER
		if duel.is_empty() or duel["hp"] <= 0: duel = {}
	else:
		_duel_next()

## ---------------------------------------------------------------- layout (shared by drawing, aiming and the tests)
func _view_off() -> Vector2:   # side-stepping moves the view; ducking drops it
	return Vector2(-float(lane) * size.x * 0.06, size.y * (0.08 if ducked else 0.0))

func _enemy_scale(e: Dictionary) -> float:
	var s := lerpf(0.78, 1.08, float(e["depth"]))
	if e["state"] == "rush": s *= lerpf(1.0, 1.7, float(e["rush"]))
	return s * (1.12 if e["boss"] else 1.0)

func _enemy_base(e: Dictionary) -> Vector2:   # where its feet are
	var y := lerpf(0.66, 0.84, float(e["depth"]))
	if e["state"] == "rush": y = lerpf(y, 0.98, float(e["rush"]))
	return Vector2(float(e["x"]) * size.x, y * size.y) + _view_off()

func _enemy_h(e: Dictionary) -> float:
	return size.y * 0.42 * _enemy_scale(e)

func _enemy_rect(e: Dictionary) -> Rect2:   # the body you can hit
	var b := _enemy_base(e)
	var h := _enemy_h(e)
	var w := h * 0.3
	return Rect2(b.x - w * 0.5, b.y - h * 0.95, w, h * 0.8)

func _enemy_head(e: Dictionary) -> Vector2:
	var b := _enemy_base(e)
	return b - Vector2(0, _enemy_h(e) * 0.85)

func aim_at(e: Dictionary) -> void:   # (tests and a nudge for touch) put the sight on a guard
	aim = _enemy_rect(e).get_center() / size

## ---------------------------------------------------------------- drawing
func _draw() -> void:
	var S := size
	var off := _view_off()
	if strip != null:
		var th := float(strip.get_height())
		var vw := th * S.x / S.y * 0.86
		var sx := clampf(_pan * float(strip.get_width()) + off.x * 0.6, 0.0, strip.get_width() - vw)
		var sy := th * 0.07 + off.y * 0.25
		draw_texture_rect_region(strip, Rect2(Vector2.ZERO, S), Rect2(sx, sy, vw, th * 0.86), tint)
	else:
		draw_rect(Rect2(Vector2.ZERO, S), Color(0.18, 0.03, 0.03))
	var pulse := 0.5 + 0.5 * sin(_alarm_t * TAU * 1.1)
	draw_rect(Rect2(Vector2.ZERO, S), Color(1.0, 0.05, 0.02, 0.06 + 0.1 * pulse))
	var col: Color = COLORS.get(faction, Color(0.9, 0.2, 0.2))
	var order := enemies.duplicate()
	order.sort_custom(func(a, b): return _enemy_base(a).y < _enemy_base(b).y)
	for e in order:
		if duel.get("id", -1) != e["id"]: _draw_guard(e, col)
	for t in _tracers: draw_line(t["a"], t["b"], t["col"], 4.0)
	for e in enemies:   # who is about to fire, and at which spot
		if e["hp"] > 0 and e["state"] == "aim":
			var to := Vector2(S.x * (0.5 + 0.28 * float(e["lane"])), S.y * 0.98)
			draw_line(_enemy_head(e), to, Color(1, 0.1, 0.1, 0.35 + 0.4 * pulse), 2.0)
	if not duel.is_empty(): _draw_duel(S, col)
	if duel.is_empty():
		var a := aim * S
		var tgt: Variant = target_under_sight()
		var open: bool = tgt != null and not shielded(tgt) and not ducked
		var sc := Color(1, 0.35, 0.3) if open else (Color(0.5, 0.85, 1.0) if tgt != null else Color(1, 1, 1, 0.9))
		draw_arc(a, 26, 0, TAU, 32, sc, 3.0)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]: draw_line(a + d * 14, a + d * 38, sc, 3.0)
	for p in _pops: draw_string(font, p["p"] - Vector2(160, 30), p["text"], HORIZONTAL_ALIGNMENT_CENTER, 320, 26, p["col"])
	_draw_hud(S, pulse)
	_draw_sticks(S)

## One guard: the cut-out picture (or a drawn figure), its force field round it while it is up, its hits left.
func _draw_guard(e: Dictionary, col: Color) -> void:
	var who: Dictionary = cast.get(int(e["slot"]), {})
	var b := _enemy_base(e)
	var h := _enemy_h(e)
	var dead: bool = e["hp"] <= 0
	var mod := Color(1, 1, 1)
	if e["flash"] > 0.0: mod = Color(2.2, 1.4, 1.4)
	if dead:
		var k := clampf(float(e["dead_t"]) / 0.7, 0.0, 1.0)
		if k >= 1.0: return
		mod.a = 1.0 - k
		draw_set_transform(b, (-1.0 if e["flip"] else 1.0) * k * 1.3, Vector2.ONE)
	var o := Vector2.ZERO if dead else b
	var bob := sin(_alarm_t * 6.0 + float(e["id"])) * h * 0.008 if e["state"] in ["patrol", "enter", "rush"] else 0.0
	var tex: Texture2D = who.get("full")
	if tex != null:
		var w := h * float(tex.get_width()) / float(tex.get_height())
		draw_texture_rect(tex, Rect2(o + Vector2(-w * 0.5, -h + bob), Vector2(w, h)), false, mod)
	else:   # (no pictures for this faction yet: a drawn figure)
		var w2 := h * 0.3
		draw_rect(Rect2(o + Vector2(-w2 * 0.5, -h * 0.78), Vector2(w2, h * 0.78)), Color(0.1, 0.1, 0.12, mod.a))
		draw_circle(o + Vector2(0, -h * 0.88), w2 * 0.35, Color(0.1, 0.1, 0.12, mod.a))
		draw_rect(Rect2(o + Vector2(-w2 * 0.5, -h * 0.78), Vector2(w2, h * 0.05)), Color(col, mod.a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if dead: return
	if shielded(e):   # the force field
		var c := Vector2(b.x, b.y - h * 0.5)
		var rr := Vector2(h * 0.28, h * 0.56)
		var fa := 0.10 + 0.05 * sin(_alarm_t * 4.0 + float(e["id"])) + 0.5 * float(e["ripple"])
		var pts := PackedVector2Array()
		for i in 41: pts.append(c + Vector2(cos(TAU * i / 40.0) * rr.x, sin(TAU * i / 40.0) * rr.y))
		draw_colored_polygon(pts, Color(col.r, col.g, col.b, fa))
		draw_polyline(pts, Color(col.lightened(0.4), minf(1.0, 0.45 + float(e["ripple"]) * 2.0)), 2.0)
	if e["muzzle"] > 0.0:
		var mp := b + Vector2(h * (0.12 if e["flip"] else -0.12), -h * 0.62)
		draw_circle(mp, h * 0.05, Color(1.0, 0.85, 0.4, 0.9))
		draw_circle(mp, h * 0.025, Color(1, 1, 1))
	# hits left: one pip per hit (rank 1 .. 6)
	var n := int(e["max"])
	var pw := 9.0
	var x0 := b.x - n * (pw + 3) * 0.5
	for i in n:
		draw_rect(Rect2(x0 + i * (pw + 3), b.y - h - 14, pw, 6), Color(1, 0.3, 0.25) if i < int(e["hp"]) else Color(0, 0, 0, 0.5))
	if e["boss"]: draw_string(font, Vector2(b.x - 130, b.y - h - 22), str(who.get("name", "SQUAD LEADER")).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 260, 16, col)

## The duel: the guard close up with its blade, and where the strike is coming from.
func _draw_duel(S: Vector2, col: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, S), Color(0, 0, 0, 0.35))
	var who: Dictionary = cast.get(int(duel["slot"]), {})
	var tex: Texture2D = who.get("full")
	var h := S.y * 1.05
	var wind := (1.0 - clampf(duel_t / Data.BREAKOUT_DUEL_WINDUP, 0.0, 1.0)) if duel_phase == "windup" else 0.0
	var lean: float = float({"left": -1.0, "right": 1.0, "high": 0.0}.get(duel_side, 0.0)) * wind * S.x * 0.03
	var c := Vector2(S.x * 0.5 + lean - float(lane) * S.x * 0.12, S.y * 1.12 + (S.y * 0.06 if ducked else 0.0))
	if tex != null:
		var w := h * float(tex.get_width()) / float(tex.get_height())
		draw_texture_rect(tex, Rect2(c + Vector2(-w * 0.5, -h), Vector2(w, h)), false, Color(2.0, 1.4, 1.4) if duel["flash"] > 0.0 else Color(1, 1, 1))
	if duel_phase == "windup":   # the laser blade, raised on the side the strike comes from
		var root := c + Vector2(0, -h * 0.55)
		var tip: Vector2
		match duel_side:
			"left": tip = root + Vector2(-S.x * 0.22, -S.y * 0.25).rotated(-wind * 0.4)
			"right": tip = root + Vector2(S.x * 0.22, -S.y * 0.25).rotated(wind * 0.4)
			_: tip = root + Vector2(0, -S.y * 0.42)
		draw_line(root, tip, Color(col.lightened(0.3), 0.35), 18.0)
		draw_line(root, tip, Color(1, 1, 1, 0.95), 5.0)
		var arrow: String = {"left": "<  STRIKE FROM THE LEFT", "right": "STRIKE FROM THE RIGHT  >", "high": "^  HIGH STRIKE  ^"}[duel_side]
		draw_string(font, Vector2(0, S.y * 0.2), arrow, HORIZONTAL_ALIGNMENT_CENTER, S.x, 30, Color(1, 0.75, 0.4, 0.6 + 0.4 * wind))
	var n := int(duel["max"])
	var x0 := S.x * 0.5 - n * 18 * 0.5
	for i in n: draw_rect(Rect2(x0 + i * 18, S.y * 0.12, 14, 8), Color(1, 0.3, 0.25) if i < int(duel["hp"]) else Color(0, 0, 0, 0.5))
	draw_string(font, Vector2(0, S.y * 0.1), "BLADES  ·  %s" % str(who.get("name", "GUARD")).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, S.x, 22, col)
	draw_string(font, Vector2(0, S.y * 0.93), "Step away from the strike  ·  duck under a high one", HORIZONTAL_ALIGNMENT_CENTER, S.x, 18, Color(1, 1, 1, 0.75))

func _draw_hud(S: Vector2, pulse: float) -> void:
	draw_rect(Rect2(0, 0, S.x, 44), Color(0.25, 0, 0, 0.55 + 0.25 * pulse))
	var left := enemies.filter(func(e): return e["hp"] > 0).size() + queue.size()
	var wtxt := "BOSS" if boss_out else "WAVE %d/%d" % [wave_i + 1, waves().size()]
	draw_string(font, Vector2(16, 30), "LOCKDOWN  ·  %s SECURITY  ·  TO THE HANGAR (%d/%d)  ·  %s  ·  %d LEFT" % [faction.to_upper(), room_i + 1, rooms.size(), wtxt, left],
		HORIZONTAL_ALIGNMENT_LEFT, S.x - 32, 20, Color(1, 0.9, 0.85))
	var bw := 280.0
	draw_rect(Rect2(16, 54, bw, 14), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(16, 54, bw * maxf(0.0, hp) / Data.BREAKOUT_HP, 14), Color(0.4, 1.0, 0.6))
	draw_string(font, Vector2(16 + bw + 10, 67), "DUCKING" if ducked else ("SIDE-STEP %s" % ("LEFT" if lane < 0 else "RIGHT") if lane != 0 else ""), HORIZONTAL_ALIGNMENT_LEFT, 240, 16, Color(1, 1, 1))
	var por: Texture2D = squad_leader.get("portrait") if not squad_leader.is_empty() else null
	if por != null:   # the boss of this room, square portrait fitted whole into a square frame
		var box := Rect2(16, 78, 120, 120)
		draw_rect(box, Color(0, 0, 0, 0.55))
		var sc := minf(box.size.x / por.get_width(), box.size.y / por.get_height())
		var ps := Vector2(por.get_width(), por.get_height()) * sc
		draw_texture_rect(por, Rect2(box.position + (box.size - ps) * 0.5, ps), false, Color(1, 1, 1) if boss_out else Color(0.55, 0.55, 0.6))
		draw_rect(box, Color(1, 0.35, 0.3, 0.9), false, 2.0)
		draw_string(font, Vector2(16, 216), str(squad_leader["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 260, 16, Color(1, 0.9, 0.85))
		draw_string(font, Vector2(16, 234), "SQUAD LEADER  ·  RANK %d" % _rank_of(_boss_slot()), HORIZONTAL_ALIGNMENT_LEFT, 260, 13, Color(1, 0.55, 0.5))
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
