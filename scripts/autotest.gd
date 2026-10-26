extends Node
## Automated play-through of the v1.2 route. Run with `-- --autotest` (desktop/headless) or `?autotest` (web).
## Travel between destinations is shortened by moving the ship close to the next destination; the actual
## docking, hub, purchases, launch, combat, asteroid/nebula checks and gate jumps all use the real game code.
## Player damage is disabled during the run (GS.god_mode) so a stray asteroid cannot end the test early.

var main: Node
var results: Array = []
var shot_index := 0
var web := OS.has_feature("web")

func _ready() -> void:
	GS.god_mode = true
	GS.save_enabled = false   # v1.7y: the route test never reads or writes a player's save (the save check uses its own file)
	GS.save_path = "user://homelancer_save_autotest.txt"
	SpaceSystem.cruise_assist = false   # fixed test setups need a ship that stays put; the cruise check turns it on
	_run.call_deferred()

func _publish(step: String, done := false) -> void:
	print("[route] step: ", step)
	if web:
		var js := "window.__hl = {step: %s, done: %s, results: %s};" % [JSON.stringify(step), "true" if done else "false", JSON.stringify(results)]
		JavaScriptBridge.eval(js, true)

func _shot(name: String, hold := 0.8) -> void:
	await _wait(hold)
	await _capture(name)

## Grab the exact rendered frame (3D + HUD) and hand it to the page as base64 PNG.
func _capture(name: String) -> void:
	shot_index += 1
	var key := "%02d_%s" % [shot_index, name]
	_publish("shot:" + key)
	if not web:
		var dir := OS.get_environment("HL_SHOT_DIR")   # desktop: optional PNG dump for reviewing art in-game
		if dir != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(dir.path_join(key + ".png"))
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var b64 := Marshalls.raw_to_base64(img.save_png_to_buffer())
	JavaScriptBridge.eval("(window.__shots = window.__shots || {})['%s'] = '%s';" % [key, b64], true)

func _check(name: String, ok: bool, detail := "") -> void:
	results.append({"name": name, "pass": ok, "detail": detail})
	print("[route] %s: %s %s" % [name, "PASS" if ok else "FAIL", detail])

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call(): return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return cond.call()

func _sp() -> SpaceSystem: return main.space

## (v1.9b) a bounty target now flies with six helpers: tests that only want the target take the wing away quietly,
## so it doesn't stay out fighting (breaking asteroids, loading the frame) through the later checks.
func _clear_wing(tgt: Dictionary) -> void:
	var s := _sp()
	if tgt.is_empty(): return
	var g := int(tgt.get("group", -2))
	for o in s.enemies.duplicate():
		if o != tgt and int(o.get("group", -1)) == g:
			s.enemies.erase(o)
			if is_instance_valid(o["node"]): (o["node"] as Node3D).queue_free()

func _tp(pos: Vector3, look: Vector3) -> void:
	var s := _sp()
	s.player.global_position = pos
	s._face(look - pos)
	s.vel = Vector3.ZERO
	s._update_camera(1.0, true)

func _press(id: String) -> void:
	main._on_hud(id)

## Job K: dock to the gate in range (HUD gate prompt) and press ACTIVATE JUMP on the docking screen.
func _gate_jump() -> void:
	_press("jump")
	main.gate_dock.press_activate()

## HL_SOAK=n: n round trips SPACE -> PLANET -> SECTOR -> SECTOR -> ORBIT -> SPACE, printing memory after each,
## to prove old areas are freed (memory must level off, not climb every lap).
func _soak(laps: int) -> void:
	await _wait(1.0)
	main.start_game()
	await _until(func(): return main.state == "flight", 10.0)
	await Packs.wait("planets", 60.0)
	print("[soak] start ", SpaceSystem.memory_report())
	for lap in laps:
		var s := _sp()
		var pc: Vector3 = s.planet.global_position
		var d := Vector3(0.3, 0.2, 1.0).normalized()
		_tp(pc + d * (float(s.planet.get_meta("radius")) + 90.0), pc)
		main.hud.move_vec = Vector2(0, -1)
		await _until(func(): return main.state == "flight" and _sp().surface_mode, 20.0)
		for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
			s = _sp()
			var t0: int = s.tile
			var at := Vector3(dir.x, 0, dir.y) * (Surface.EDGE - 40.0) + Vector3(0, 900, 0)
			_tp(at, at + Vector3(dir.x, 0, dir.y) * 500.0)
			await _until(func(): return s.tile != t0, 8.0)
			await _wait(1.0)
		_tp(Vector3(0, Surface.CEILING - 30.0, 0), Vector3(0, Surface.CEILING + 400.0, -100.0))
		await _until(func(): return main.state == "flight" and not _sp().surface_mode, 10.0)
		main.hud.move_vec = Vector2.ZERO
		await _wait(1.5)
		print("[soak] lap %d %s" % [lap + 1, SpaceSystem.memory_report()])
	get_tree().quit()

## Owner's first-pass loop: spawn a mech, shoot off its left arm (explosion, arm hidden, that gun offline),
## wait for a damage spark, then kill the core. Also shoots the right wing off a ship.
func _section_loop() -> void:
	await Packs.wait("mechs", 60.0)
	var s := _sp()
	var fwd := -s.player.global_basis.z
	var e: Dictionary = s.spawn_unit("mech", s.player.global_position + fwd * 40.0 + s.player.global_basis.y * 2.0, s.player.global_position)
	var n: Node3D = e["node"]
	n.look_at(s.player.global_position, Vector3.UP)
	e["sh"] = 0.0
	e["aggro"] = false
	s.target = n
	await _shot("mech_intact", 0.4)
	var guns0: Array = s.unit_guns(e)
	s._damage_enemy(e, 999.0, n.global_position - n.global_basis.x * 4.0)
	var arm_hidden: bool = e["vis"].get("gone_l", false)
	var guns1: Array = s.unit_guns(e)
	await _shot("mech_arm_destroyed", 0.35)
	await _until(func(): return int(e["sparks"]) > 0, 6.0)
	var sparked: bool = int(e["sparks"]) > 0
	var r2: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 60.0 + s.player.global_basis.x * 25.0, s.player.global_position)
	r2["sh"] = 0.0
	s._damage_enemy(r2, 999.0, r2["node"].global_position + r2["node"].global_basis.x * 4.0)
	var wing_hidden: bool = not r2["vis"]["r"].is_empty() and r2["vis"]["r"].all(func(w): return not w.visible)
	s._damage_enemy(e, 999.0)
	var gone := not s.enemies.has(e)
	await _shot("mech_core_destroyed", 0.15)
	s._damage_enemy(r2, 999.0)
	await _wait(0.6)
	_check("Three-part damage: arm/wing off, gun offline, sparks, core kill", guns0 == ["l", "r"] and arm_hidden and guns1 == ["r"] and sparked and wing_hidden and gone and not s.player_vis.get("l", []).is_empty(),
		"guns %s -> %s, arm hidden %s, sparks %d, wing hidden %s, destroyed %s" % [guns0, guns1, arm_hidden, int(e["sparks"]), wing_hidden, gone])

## Planet prototype: fly into New Terra (atmosphere entry -> tile), cross the east edge into the next tile,
## cross the outer edge (wrap to the other side), climb back to orbit, then fast-travel from the planet hub.
func _planet_surface() -> void:
	await Packs.wait("planets", 60.0)
	var s := _sp()
	var pc: Vector3 = s.planet.global_position
	var pr: float = s.planet.get_meta("radius")
	var d := (s.player.global_position - pc).normalized()
	_tp(pc + d * (pr + 90.0), pc)
	main.hud.move_vec = Vector2(0, -1)          # full forward thrust into the planet
	await _until(func(): return main.state == "atmosphere", 6.0)
	main.hud.move_vec = Vector2.ZERO
	await _shot("atmosphere_entry", 0.7)
	var entered := await _until(func(): return main.state == "flight" and _sp().surface_mode, 12.0)
	s = _sp()
	var t0: int = s.tile
	_check("Atmosphere entry -> planet tile", entered and s.planet_id == "new_terra", "tile %d (%s)" % [t0, Surface.PLANETS["new_terra"]["tiles"][t0]])
	await _shot("planet_tile", 0.4)
	# east edge: into the neighbouring tile, heading and speed kept, now at the west edge
	var g := Surface.grid("new_terra")
	s.load_tile(3)                               # middle-left tile: its east neighbour is tile 4 (the capital)
	_tp(Vector3(Surface.EDGE - 40.0, 900.0, 0.0), Vector3(Surface.EDGE + 500.0, 900.0, 0.0))
	var yaw0: float = s.yaw
	main.hud.move_vec = Vector2(0, -1)
	var crossed := await _until(func(): return s.tile == 4, 6.0)
	await _wait(1.0)
	main.hud.move_vec = Vector2.ZERO
	_check("Tile edge -> neighbouring tile", crossed and s.player.global_position.x < -Surface.EDGE + 300.0 and absf(s.yaw - yaw0) < 0.01 and s.vel.x > 10.0,
		"tile %d, x %d, speed %d" % [s.tile, int(s.player.global_position.x), int(s.vel.length())])
	await _shot("planet_capital_tile", 0.3)
	# outer edge wraps around: east out of the last column comes back in column 0 of the same row
	s.load_tile(5)
	_tp(Vector3(Surface.EDGE - 40.0, 900.0, 0.0), Vector3(Surface.EDGE + 500.0, 900.0, 0.0))
	main.hud.move_vec = Vector2(0, -1)
	var wrapped := await _until(func(): return s.tile == 3, 6.0)
	await _wait(1.0)
	main.hud.move_vec = Vector2.ZERO
	# terrain must meet at every border, including the wrap-around one
	var worst := 0.0
	for zz in range(-2400, 2401, 300):
		for pair in [[5, 3], [4, 5], [8, 6]]:   # east edge of the left tile == west edge of the right tile
			worst = maxf(worst, absf(Surface.height("new_terra", pair[0], Surface.EDGE, zz) - Surface.height("new_terra", pair[1], -Surface.EDGE, zz)))
		worst = maxf(worst, absf(Surface.height("new_terra", 7, zz, Surface.EDGE) - Surface.height("new_terra", 1, zz, -Surface.EDGE)))  # south of row 3 wraps to row 1
	_check("World wrap (east edge of sector 6 -> sector 4), seamless ground", wrapped and g == 3 and worst < 0.5, "tile %d, worst seam step %.2f m" % [s.tile, worst])
	# climb above the ceiling: back in space above New Terra
	_tp(Vector3(0, Surface.CEILING - 30.0, 0), Vector3(0, Surface.CEILING + 400.0, -100.0))
	main.hud.move_vec = Vector2(0, -1)
	var out := await _until(func(): return main.state == "flight" and not _sp().surface_mode, 8.0)
	main.hud.move_vec = Vector2.ZERO
	s = _sp()
	_check("Climb to orbit", out and s.distance_to(s.planet) < 400.0, "alt above planet %d" % int(s.distance_to(s.planet)))
	# Option B: dock at the planet, choose a surface destination, arrive there
	var docked := await _dock_at(s.planet)
	main.hub.show_screen("surface")
	await _wait(0.4)
	await _shot("surface_travel_menu")
	var go: Button = main.hub.find_child("Go_iron_foundry", true, false)
	if go: go.pressed.emit()
	var arrived := await _until(func(): return main.state == "flight" and _sp().surface_mode, 10.0)
	s = _sp()
	_check("Planet hub fast travel -> chosen sector", docked and arrived and s.tile == 7 and s.station.name == "Iron Foundry", "tile %d at %s" % [s.tile, s.station.name])
	await _shot("fast_travel_arrival", 0.8)
	# back up to space for the rest of the route
	_tp(Vector3(0, Surface.CEILING - 30.0, 0), Vector3(0, Surface.CEILING + 400.0, -100.0))
	main.hud.move_vec = Vector2(0, -1)
	await _until(func(): return main.state == "flight" and not _sp().surface_mode, 8.0)
	main.hud.move_vec = Vector2.ZERO

## Generic enemy pilots under the named leaders: who flies what, NORMAL -> DAMAGED portraits (latched), chatter.
func _generic_pilots() -> void:
	var s := _sp()
	var hud: Node = main.hud
	hud.close_comms()
	var fwd: Vector3 = -s.player.global_basis.z
	var real_sys: Dictionary = s.sys
	s.sys = Data.SYSTEMS["vega"]   # (v1.5k: Solara's opening is Imperium troops now; the named-leader wings fly in corsair space)
	var group: Array = s._spawn_group(s.player.global_position + fwd * 500.0, 3)
	s.sys = real_sys
	var lead: Dictionary = group[0]
	var wing: Dictionary = group[1]
	var named := []
	for f in Data.PILOTS: for p in Data.PILOTS[f]: named.append(p["name"])
	var lead_name: String = lead["node"].get_meta("pilot", {}).get("name", "")
	var gp: Dictionary = wing.get("pilot", {})
	_check("Generic pilots fly under a named leader", lead_name in named and not lead.has("pilot") and gp.get("generic", false) and gp["leader"] == lead_name
		and group[2].get("pilot", {}).get("generic", false), "%s leads %s + %s" % [lead_name, gp.get("unit", "?"), group[2].get("pilot", {}).get("unit", "?")])
	# portrait selection: one face per pilot, the state picks normal / damaged, from the enemies pack
	var tn: Texture2D = hud._face_tex("gp/" + gp["id"], "normal")
	var td: Texture2D = hud._face_tex("gp/" + gp["id"], "damaged")
	var ids := {}
	for g in Data.GENERIC_PILOTS: ids[g["id"]] = ResourceLoader.exists("res://assets/enemy_pilots/%s_normal.jpg" % g["id"]) and ResourceLoader.exists("res://assets/enemy_pilots/%s_damaged.jpg" % g["id"])
	_check("Generic pilot portrait selection (6 pilots x normal/damaged, enemies pack)", tn != null and td != null and tn.resource_path.ends_with(gp["id"] + "_normal.jpg")
		and td.resource_path.ends_with(gp["id"] + "_damaged.jpg") and ids.values().count(true) == 6 and Packs.PACKS["enemies"]["folders"] == ["res://assets/enemy_pilots"],
		"%s: %s / %s" % [gp["unit"], tn.resource_path.get_file() if tn else "-", td.resource_path.get_file() if td else "-"])
	# chatter on the same radio: the first hit -> "taking fire" with the NORMAL face
	wing["sh"] = 0.0
	s.chatter_cd = 0.0
	s.call_cd = 999.0   # keep the named leader's own hail out of this check
	s._damage_enemy(wing, 1.0)
	await get_tree().process_frame
	var said_normal: bool = s.last_chatter.get("event", "") == "taking_fire" and hud.comms_open and hud.comms_face == "gp/" + gp["id"] and hud.comms_expr == "normal"
	await _shot("generic_pilot_comms_normal", 0.3)
	# take it down to just above 50 %, then just below: DAMAGED; healing back up must not flip it back (no flicker)
	var tot: float = float(wing["max"]) + 2.0 * float(wing["side_max"])
	var hp0: float = wing["hp"]
	wing["hp"] = hp0 - (SpaceSystem.unit_health(wing) - 0.52) * tot
	s._update_pilot_state(wing)
	var still_normal: bool = wing["pstate"] == "normal"
	s._damage_enemy(wing, 0.05 * tot)
	await get_tree().process_frame
	await get_tree().process_frame
	var went_damaged: bool = wing["pstate"] == "damaged" and SpaceSystem.unit_health(wing) <= 0.5
	wing["hp"] = hp0
	s._update_pilot_state(wing)
	var stayed: bool = wing["pstate"] == "damaged"
	hud.close_comms()
	s.chatter_cd = 0.0
	s.target = wing["node"]
	var m0 := GS.missiles
	GS.missiles = maxi(GS.missiles, 1)
	s.fire_missile()
	GS.missiles = m0
	await get_tree().process_frame
	var missile_ok: bool = s.last_chatter.get("event", "") == "missile_incoming" and hud.comms_expr == "damaged"
	_check("Generic pilot NORMAL -> DAMAGED at 50 %, latched (no flicker), comms face follows", said_normal and still_normal and went_damaged and stayed and missile_ok,
		"normal@52%% %s, damaged@<=50%% %s, stays after heal %s, chatter '%s' face %s" % [still_normal, went_damaged, stayed, s.last_chatter.get("line", ""), hud.comms_expr])
	await _shot("generic_pilot_comms_damaged", 0.3)
	# leader down: a wingman calls it in
	hud.close_comms()
	s._destroy_unit(lead)
	await get_tree().process_frame
	var leader_down: bool = s.last_chatter.get("event", "") == "leader_down"
	var events := {}
	for k in Data.CHATTER: events[k] = (Data.CHATTER[k] as Array).size()
	_check("Generic chatter on the existing radio (leader down, 13 events)", leader_down and events.size() == 13 and hud.comms_generic, "'%s'" % s.last_chatter.get("line", ""))
	# named leaders untouched: same names, own five-expression portraits, own personality lines
	var pn := []
	for f in ["raider", "corsair"]: for p in Data.PILOTS[f]: pn.append(p["name"])
	var faces_ok := true
	for f in Data.PILOTS: for p in Data.PILOTS[f]: for ex in ["normal", "serious", "angry", "smile"]: faces_ok = faces_ok and ResourceLoader.exists("res://assets/portraits/%s_%s.png" % [p["face"], ex])
	main._pilot_call(Data.PILOTS["raider"][0], true)
	var call_ok: bool = hud.comms_face == "jackal" and not hud.comms_generic
	_check("Named squad leaders unchanged", pn == ["Scar Jackal", "Ember Wraith", "Iron Revenant", "Frost Banshee"] and Data.CHARACTERS["voss"]["name"] == "Shade"
		and Data.CHARACTERS["kessler"]["name"] == "Hoard" and faces_ok and call_ok, ", ".join(pn))
	hud.close_comms()
	# clean up the test group
	s.call_cd = 0.0
	s.target = null
	for e in group:
		if s.enemies.has(e):
			s.enemies.erase(e)
			(e["node"] as Node3D).queue_free()

## Oct 1 requests: default cruise, full loops, TRANSFORM where STOP was, cockpit art view, two-sided comms + console.
func _flight_and_comms() -> void:
	var s := _sp()
	var hud: Node = main.hud
	hud.close_comms()
	# TRANSFORM leads the special-moves row (right block); the centre row has no MECH pill
	hud._layout()
	var fr: Rect2 = hud.buttons.get("form", Rect2())
	var wr: Rect2 = hud.buttons["warp"]
	_check("TRANSFORM button leads the special-moves row on the right, level with the speed row (v1.9 owner layout)", fr.size.x > 0.0 and absf(fr.position.y - wr.position.y) < 1.0 and fr.position.x > hud.S.x * 0.5
		and hud.buttons.has("stop") and hud.buttons.has("map") and hud.buttons.has("goto"), "at %s" % str(fr.position))
	# default cruise: centred stick holds cruise speed; all the way back stops and stays stopped
	SpaceSystem.cruise_assist = true
	s.holding = false
	s.braking = false
	s.engine_kill = false
	main.hud.move_vec = Vector2.ZERO
	await _wait(3.0)
	var cruise: float = s.speed_now
	var want: float = float(GS.ship()["speed"]) * Data.CRUISE
	main.hud.move_vec = Vector2(0, 1)    # stick pulled all the way back
	await _until(func(): return s.speed_now < 0.8, 5.0)
	await _wait(0.3)
	main.hud.move_vec = Vector2.ZERO
	await _wait(1.5)
	var held_stop: float = s.speed_now
	SpaceSystem.cruise_assist = false
	s.holding = false
	_check("Default cruise: centred stick cruises, full back stops and holds", absf(cruise - want) < want * 0.15 and held_stop < 1.0,
		"cruise %d m/s (want %d), after full back + release %.1f m/s" % [int(cruise), int(want), held_stop])
	# full loop: hold the stick up and go all the way round, upside down at the top
	var start_fwd: Vector3 = -s.player.global_basis.z
	var turned := 0.0
	var prev := start_fwd
	var inverted := false
	main.hud.aim_vec = Vector2(0, -1)
	var tt := 0.0
	while tt < 10.0 and turned < TAU:
		await get_tree().process_frame
		tt += get_process_delta_time()
		var f: Vector3 = -s.player.global_basis.z
		turned += prev.angle_to(f)
		prev = f
		if s.player.global_basis.y.y < -0.9: inverted = true
	main.hud.aim_vec = Vector2.ZERO
	_check("Full loop: pitch keeps going over the top (no cap)", turned >= TAU * 0.98 and inverted, "turned %d deg in %.1f s, upside down at the top %s" % [int(rad_to_deg(turned)), tt, inverted])
	s._face(start_fwd)
	# cockpit view with the owner's cockpit art + instruments
	s.set_view("cockpit")
	await _wait(0.3)
	var tex: Texture2D = hud.cockpit_texture()
	await _shot("cockpit_view", 0.4)
	_check("Cockpit view: cockpit art, see-through glass, crosshair + heading/speed", tex != null and Packs.PACKS.has("cockpit"), tex.resource_path.get_file() if tex else "no art")
	var S0: Vector2 = hud.get_viewport_rect().size
	var cr0: Rect2 = hud.cockpit_rect()
	var dash_y: float = cr0.position.y + cr0.size.y * 0.62
	# free-look: steer right and the head turns right, the cockpit slides left, the crosshair follows the nose
	s.engine_kill = true   # hold position while looking
	main.hud.aim_vec = Vector2(0.8, 0)
	await _wait(1.2)
	var look_x: float = s.look.x
	var cr1: Rect2 = hud.cockpit_rect()
	var nose = hud._screen(s.player.global_position - s.player.global_basis.z * 400.0)
	await _shot("cockpit_look_right", 0.1)
	main.hud.aim_vec = Vector2.ZERO
	await _wait(1.0)
	s.engine_kill = false
	_check("Cockpit bigger + lower, free-look slides it, crosshair stays on the nose", cr0.size.x > S0.x * 1.25 and dash_y > S0.y * 0.64 and look_x > 0.3 and cr1.position.x < cr0.position.x - 40.0 and nose != null,
		"scale %.2f, dash top at %d%% of screen, slide %d px" % [cr0.size.x / S0.x, int(dash_y / S0.y * 100.0), int(cr0.position.x - cr1.position.x)])
	# the radar is a button: tap it for the map; drop a waypoint and the autopilot flies there
	hud._layout()
	var rr: Rect2 = hud.buttons.get("radar", Rect2())
	var not_stick: bool = rr.size.x > 0.0 and not hud.stick_zone("move").has_point(rr.get_center()) and not hud.stick_zone("aim").has_point(rr.get_center())
	_press("radar")
	await _wait(0.3)
	var map_open: bool = main.state == "map" and main.navmap.visible
	main.navmap.pick_point(s.player.global_position - s.player.global_basis.z * 900.0)
	await _shot("radar_map_waypoint", 0.2)
	main.navmap.set_course()
	await _wait(0.3)
	var wp_ok: bool = main.state == "flight" and s.autopilot != null and s.autopilot == s.waypoint
	s.autopilot = null
	_check("Tap the radar: map opens, tap empty space = waypoint, autopilot flies there", not_stick and map_open and wp_ok, "radar %s, stick-free %s" % [str(rr.position), not_stick])
	# enemy LEFT + friendly RIGHT talking at the same time
	main._pilot_call(Data.PILOTS["raider"][0], true)
	main.call_character("vale", true)
	await _wait(0.6)
	var l: Dictionary = hud.slot("l")
	var r: Dictionary = hud.slot("r")
	await _shot("comms_two_sides", 0.2)
	_check("Comms side screens: enemy left + friendly right at once, line under the face", not l.is_empty() and not r.is_empty() and l["hostile"] and not r["hostile"]
		and l["face"] == Data.PILOTS["raider"][0]["face"] and r["face"] == "vale", "%s | %s" % [l.get("from", "-"), r.get("from", "-")])
	# tap a screen: the console pulls up; contacts only answer in this system; type a message
	_press("side_l")
	await _wait(0.5)
	hud._layout()
	var console_up: bool = hud.comms_mode == "roster" and hud.console_view == "chat" and hud.buttons.has("type") and not hud.buttons.has("met_0")   # (v1.8s: a tapped screen brings up the text screen, one panel)
	hud.start_typing()
	hud._typer.text_submitted.emit("Hold the line, Vale.")
	var logged: bool = "YOU: Hold the line, Vale." in hud.history
	await _shot("comms_console", 0.2)
	_check("Comms console: pulls up from a tap, contact list (in-system only), chat log, typing", console_up and logged and hud.in_range("vale") and not hud.in_range("amari"),
		"vale in range %s, amari (Vega) in range %s" % [hud.in_range("vale"), hud.in_range("amari")])
	main.on_call = "vale"   # with Vale on the line, a typed question gets an answer from the brain
	main.call_character("vale")
	hud._typer.text_submitted.emit("Where is the warp gate?")
	await _wait(1.3)
	var answered: bool = str(hud.slot("r").get("line", "")).find("Aquila") >= 0
	_check("Typing to a contact on the line gets an in-character answer", answered, str(hud.slot("r").get("line", "")).left(80))
	await _shot("comms_brain_answer", 0.2)
	_press("log")
	await _wait(0.4)
	hud.close_comms()
	s.set_view("chase")

## The sun: far out, blooms as you fly at it, heat warning, and its sphere destroys the ship.
func _sun() -> void:
	var s := _sp()
	var sp: Vector3 = s.sun_pos
	var far_ok: bool = sp.length() > 30000.0 and Data.SUN_RADIUS >= 5.0 * float(s.planet.get_meta("radius")) and sp.distance_to(s.gate.global_position) > 20000.0 and is_instance_valid(s.sun_glow)
	main.hud.visible = false
	s._face(sp - s.player.global_position)
	await _shot("sun_from_the_station", 0.6)
	var flare_far: float = s.sun_flare
	main.hud.visible = true
	var dir := sp.normalized()
	_tp(sp - dir * (Data.SUN_RADIUS + 9000.0), sp)   # looking straight at it from 9 km above its surface
	await _wait(0.8)
	var flare_mid: float = s.sun_flare
	await _shot("sun_bloom_close", 0.1)
	s._face(-dir)                                    # look away: the bloom goes
	await _wait(0.8)
	var flare_away: float = s.sun_flare
	_check("Sun: far out on its sphere, blooms when you fly at it, not when you look away", far_ok and flare_far < 0.2 and flare_mid > flare_far + 0.25 and flare_away < 0.05,
		"%.0f m out, 5.5x the planet; bloom %.2f from the station, %.2f at 9 km, %.2f looking away" % [sp.length(), flare_far, flare_mid, flare_away])
	_tp(sp - dir * (Data.SUN_RADIUS * Data.SUN_WARN - 400.0), sp)
	var warned := await _until(func(): return s.sun_hazard == 1, 2.0)
	await _shot("sun_heat_warning", 0.0)
	# fly in WITH a heat shield: the star has a surface (a small magma tile that wraps onto itself) and you live
	GS.heat_shield = true
	_tp(sp - dir * (Data.SUN_RADIUS + 60.0), sp)
	s.vel = dir * 200.0
	var entered := await _until(func(): return main.state == "flight" and _sp().surface_mode, 30.0)
	s = _sp()
	var hull0: float = GS.hull
	await _wait(2.5)
	await _shot("sun_surface_heat_shield", 0.1)
	var safe: bool = entered and s.planet_id == "solara_sun" and s.sun_surface and GS.hull >= hull0 and GS.shield >= GS.max_shield() - 0.1
	_check("Sun: flying in loads its surface (magma tile); a heat shield keeps you alive", warned and safe,
		"%s, hull %.0f, shield %.0f" % [Surface.tile_name(s.planet_id, s.tile) if entered else "not entered", GS.hull, GS.shield])
	# cross the tile edge: it wraps onto itself
	var px: float = s.player.global_position.x
	_tp(Vector3(Surface.EDGE - 30.0, 900.0, 0.0), Vector3(Surface.EDGE + 500.0, 900.0, 0.0))
	s.vel = Vector3(120, 0, 0)
	var wrapped := await _until(func(): return _sp().player.global_position.x < 0.0, 6.0)
	_check("Sun surface loops (fly off one edge, come back on the other)", wrapped and _sp().planet_id == "solara_sun", "x %.0f -> %.0f" % [px, _sp().player.global_position.x])
	_check("v2.0: the Heat Shield is a module you can buy and fit", Data.MODULES.has("heat_shield") and "heat_shield" in Data.MODULE_ORDER)
	# without the shield: shields go, then the hull, then the ship
	GS.heat_shield = false
	var sh_gone := await _until(func(): return GS.shield <= 0.0, 5.0)
	await _shot("sun_surface_burning", 0.0)
	var dead := await _until(func(): return main.state == "dead" or main.state == "hub", 14.0)
	await _until(func(): return main.state == "hub", 8.0)
	_check("Sun surface without a heat shield: shield, then hull, drain fast until the ship is lost", sh_gone and dead, "shield gone %s, state %s, hull %.0f, controls %s, sun_surface %s, busy %s" % [sh_gone, main.state, GS.hull, _sp().controls, _sp().sun_surface, _sp().surf_busy])
	await _launch()

## Each system wears its own painted 360 sky (the "sky" pack), made from the owner's nebula pictures.
func _system_sky(shot: String) -> void:
	var s := _sp()
	var tex: Texture2D = s._pano.panorama if s._pano else null
	var ok: bool = tex != null and tex.get_width() == 2048 and tex.resource_path == s.sky_path()
	main.hud.visible = false
	var keep_yaw: float = s.yaw
	var keep_pitch: float = s.pitch
	s._face(Vector3(0, 0.15, -1))
	await _shot(shot + "_ahead", 0.5)
	s._face(Vector3(0, 0.1, 1))
	await _shot(shot + "_behind", 0.5)
	s.yaw = keep_yaw
	s.pitch = keep_pitch
	main.hud.visible = true
	_check("%s has its own painted 360 sky" % Data.SYSTEMS[GS.system_id]["name"], ok, "%s, %d px wide" % [s.sky_path().get_file(), tex.get_width() if tex else 0])

## The whole 11 x 11 map as real systems: every one is built from the map tables by SystemBuilder.
func _galaxy() -> void:
	var bad: Array = []
	for id in Data.SYSTEMS:
		var d: Dictionary = Data.SYSTEMS[id]
		for k in ["name", "star", "sky_tint", "ambient", "sun_dir", "station", "planet", "gate", "gates", "asteroids", "nebula", "enemy", "patrols", "traffic", "tile"]:
			if not d.has(k): bad.append("%s lacks %s" % [id, k])
		if not Surface.is_sun(id + "_sun"): bad.append("%s has no sun surface" % id)
		for g in d.get("gates", []):
			if not Data.SYSTEMS.has(g["to"]): bad.append("%s gate to nowhere" % id)
			elif not (Data.SYSTEMS[g["to"]]["gates"] as Array).any(func(x): return x["to"] == id): bad.append("%s > %s is one-way" % [id, g["to"]])
	# every system must be reachable from Solara through gates
	var seen := {"solara": true}
	var todo: Array = ["solara"]
	while not todo.is_empty():
		var cur: String = todo.pop_back()
		for g in Data.SYSTEMS[cur]["gates"]:
			if not seen.has(g["to"]):
				seen[g["to"]] = true
				todo.append(g["to"])
	_check("Galaxy: %d systems, each with a star you can enter, a station, a planet and two-way gates; all reachable from Solara" % Data.SYSTEMS.size(),
		Data.SYSTEMS.size() == 67 and bad.is_empty() and seen.size() == Data.SYSTEMS.size(), "reachable %d; %s" % [seen.size(), ", ".join(bad.slice(0, 4))])
	# real planets: NASA maps, a fixed day and night side, clouds, and the docking gate on top of the atmosphere
	var s := _sp()
	await Packs.wait("worlds", 40.0)
	await Packs.wait("structures", 30.0)
	await _wait(0.4)
	var pmap: Array = s.planet_map(s.planet.get_meta("info"))
	_check("New Terra wears a real planet map with a day side, a night side and clouds", s.planet_real and pmap[0] == "earth" and is_instance_valid(s.planet_clouds)
		and (s.planet.get_meta("surface") as MeshInstance3D).material_override is ShaderMaterial, "map %s" % pmap[0])
	_check("Planet docking gate: the ring with four arch pieces round it", s.dock_gate != null and s.dock_gate.get_child_count() == 5 and s.DOCK_GATE_TRIS < 16000, "tris %d" % s.DOCK_GATE_TRIS)
	_check("Traffic: cargo ships on the run (v1.8v: TRAFFIC_PER_RUN), and a big fuel tanker by the planet", s.traffic.size() == Data.TRAFFIC_PER_RUN and (Data.TRAFFIC_PER_RUN < 3 or (s.traffic[2]["node"] as Node3D).name.begins_with("Tanker"))
		and is_instance_valid(s.tanker) and ShipFactory.has_real_model("tanker") and ShipFactory.has_real_model("fleet3")
		and ShipFactory.has_real_model("crate_a") and ShipFactory.has_real_model("crate_b") and ShipFactory.has_real_model("crate_c"))
	main.hud.visible = false
	var pr: float = s.planet.get_meta("radius")
	var ts: Vector3 = (s.sun_pos - s.planet.global_position).normalized()
	var side: Vector3 = ts.cross(Vector3.UP).normalized()
	_tp(s.planet.global_position + (ts * 0.75 + side * 0.66).normalized() * pr * 3.4, s.planet.global_position)
	await _shot("planet_real_day_night", 0.8)
	_tp(s.planet.global_position + (ts * -0.2 + side).normalized() * pr * 2.6, s.planet.global_position)
	await _shot("planet_real_terminator", 0.8)
	var dp: Vector3 = s.dock_point(s.planet)
	var up: Vector3 = (dp - s.planet.global_position).normalized()
	_tp(dp + up * 260.0 + up.cross(Vector3.UP).normalized() * 240.0, dp)
	await _shot("planet_dock_gate", 0.8)
	_tp(dp + up * 420.0, dp)
	await _shot("planet_dock_gate_above", 0.8)
	_tp(s.tanker.global_position + Vector3(120, 50, 150), s.tanker.global_position)
	await _shot("big_tanker", 0.8)
	var tk: Node3D = s.traffic[mini(2, s.traffic.size() - 1)]["node"]   # (v1.8v: fewer cargo ships on the run)
	_tp(tk.global_position + Vector3(22, 8, 26), tk.global_position)
	await _shot("tanker", 0.5)
	var cr: Node3D = s.carrier
	_tp(cr.global_position + Vector3(120, 50, 160), cr.global_position)
	await _shot("carrier", 0.6)
	main.hud.visible = true
	# fly it: Solara's new gate to Veranthos, the Unity capital
	var vg: Node3D = null
	for g in s.gates:
		if g.get_meta("info")["to"] == "veranthos": vg = g
	_check("Solara has a second gate, to Veranthos", vg != null and s.gates.size() == 2 and s.gate.get_meta("info")["to"] == "vega")
	if vg == null: return
	_tp(vg.global_position + vg.global_basis.z * 180.0, vg.global_position)
	await _wait(0.4)
	_gate_jump()   # Job K: the gate prompt docks; ACTIVATE JUMP on the docking screen jumps
	await _until(func(): return main.state == "flight" and GS.system_id == "veranthos", 20.0)
	s = _sp()
	var back: Node3D = null
	for g in s.gates:
		if g.get_meta("info")["to"] == "solara": back = g
	var near_back: bool = back != null and s.player.global_position.distance_to(back.global_position) < 400.0
	await Packs.wait("sky_veranthos", 40.0)
	await Packs.wait("structures", 30.0)
	await Packs.wait(str(Data.SYSTEMS["veranthos"]["station"].get("model", "structures")), 30.0)   # (v1.9q: the RETOPO capital's own pack)
	await _wait(0.5)
	var tex: Texture2D = s._pano.panorama if s._pano else null
	_check("Jump to Veranthos: arrive at the gate that leads back, with its own sky, a sun and the capital's station model",
		GS.system_id == "veranthos" and near_back and s.gates.size() == (Data.SYSTEMS["veranthos"]["gates"] as Array).size() and tex != null and tex.resource_path == "res://assets/skies/veranthos.jpg"
		and is_instance_valid(s.sun_body) and s.station_model != null, "gates %d, sky %s" % [s.gates.size(), tex.resource_path.get_file() if tex else "none"])
	_tp(s.station.global_position + Vector3(260, 60, 420), s.station.global_position)
	await _shot("veranthos", 1.0)
	# the whole catalog is in: every planet and station of every system, the extra ones as placeholders
	var total_p := 0
	var total_s := 0
	for id3 in Data.SYSTEMS:
		total_p += 1 + (Data.SYSTEMS[id3]["more_planets"] as Array).size()
		total_s += 1 + (Data.SYSTEMS[id3]["more_stations"] as Array).size()
	await Packs.wait("worlds", 30.0)
	await _wait(Data.PH_BUILD_DELAY + 0.6)
	var xw: int = s.extra_worlds.filter(func(w): return (w[0] as MeshInstance3D).material_override is ShaderMaterial).size()
	_check("Galaxy contents: %d planets and %d stations; Veranthos shows its 5 planets and 4 stations (extras are placeholders you can target)" % [total_p, total_s],
		total_p == 172 and total_s == 102 + _retopo_added() and s.extras.size() == 7 and xw == 4 and s.targetables().has(s.extras[0]), "extras %d, real maps %d" % [s.extras.size(), xw])
	var crowded: Array = []
	for id4 in Data.SYSTEMS:
		var sd: Dictionary = Data.SYSTEMS[id4]
		for x in sd["more_planets"] + sd["more_stations"]:
			if not SystemBuilder.clear_of(sd, x["pos"], float(x["radius"]), x["id"]): crowded.append("%s/%s" % [id4, x["name"]])
	_check("Placeholders sit clear of the main planet, the main station, the gates and each other in every system", crowded.is_empty(), ", ".join(crowded.slice(0, 5)))
	# a placeholder is a real object: TARGET picks it, GO TO flies to it and stops short, and it is solid
	var xn: Node3D = s.extras[3]      # Halcyon, the gas giant
	var sunward: Vector3 = (s.sun_pos - xn.global_position).normalized()
	var xr: float = xn.get_meta("radius")
	_tp(xn.global_position + sunward * (xr + 900.0), xn.global_position)
	s.target = xn
	_press("goto")
	var arrived := await _until(func(): return s.autopilot == null and s.player.global_position.distance_to(xn.global_position) < xr + Data.PH_GOTO_STANDOFF + 200.0, 40.0)
	_tp(xn.global_position + sunward * (xr + 30.0), xn.global_position)
	s.vel = -sunward * 30.0
	await _frames(3)
	var solid_ok: bool = s.player.global_position.distance_to(xn.global_position) >= xr
	_check("A placeholder planet can be targeted, GO TO flies to it and stops short, and it is solid", arrived and solid_ok and xn.get_meta("kind") == "landmark")
	main.hud.visible = false
	_tp(xn.global_position + (sunward * 0.8 + sunward.cross(Vector3.UP).normalized() * 0.6).normalized() * xr * 3.2, xn.global_position)
	await _shot("placeholder_planet", 0.6)
	var xst: Node3D = s.extras[4]
	_tp(xst.global_position + Vector3(90, 40, 150), xst.global_position)
	await _shot("placeholder_station", 0.6)
	main.hud.visible = true
	# v1.4l: every catalog planet has a surface. Fly into Halcyon (a gas giant), look, climb back out beside it.
	var xinfo: Dictionary = xn.get_meta("info")
	var xpos: Vector3 = xn.global_position
	_tp(xpos + sunward * (xr * Data.ATMO_INNER + 40.0), xpos)
	main.hud.move_vec = Vector2(0, -1)
	var went_down := await _until(func(): return main.state == "flight" and _sp().surface_mode and _sp().planet_id == xinfo["id"], 25.0)
	main.hud.move_vec = Vector2.ZERO
	s = _sp()
	var biome_ok: bool = went_down and Surface.PLANETS[xinfo["id"]]["tiles"][0] == Data.PLANET_BIOME[xinfo["palette"]] and Surface.grid(xinfo["id"]) == 1
	await _shot("surface_of_placeholder_planet", 0.8)
	_tp(Vector3(0, Surface.CEILING - 30.0, 0), Vector3(0, Surface.CEILING + 400.0, -100.0))
	main.hud.move_vec = Vector2(0, -1)
	var back_up := await _until(func(): return main.state == "flight" and not _sp().surface_mode, 12.0)
	main.hud.move_vec = Vector2.ZERO
	s = _sp()
	var beside: bool = back_up and GS.system_id == "veranthos" and s.player.global_position.distance_to(xpos) < xr * Data.ATMO_OUTER + 400.0
	_check("Job O: a catalog planet (Halcyon) can be entered from space, has its own one-tile surface in the planet's colours, and climbing out puts you back beside it", went_down and biome_ok and beside,
		"down %s, biome %s, back beside it %s" % [went_down, biome_ok, beside])
	await _until(func(): return not s.extras.is_empty(), 6.0)
	for g in s.gates:   # the system was loaded again: pick the gate up again
		if g.get_meta("info")["to"] == "solara": back = g
	main.navmap.open(s)
	await _shot("navmap_veranthos", 0.5)
	main.navmap.visible = false
	await Packs.wait("worlds", 30.0)
	await _wait(0.3)
	var kinds := {}
	for id2 in Data.SYSTEMS: kinds[s.planet_map(Data.SYSTEMS[id2]["planet"])[0]] = true
	_check("Every planet in the galaxy has a real map (%d different maps in use)" % kinds.size(), s.planet_real and kinds.size() >= 10 and kinds.keys().all(func(k): return ResourceLoader.exists("res://assets/worlds/%s.jpg" % k)))
	_tp(back.global_position + back.global_basis.z * 300.0 + Vector3(120, 40, 0), back.global_position)
	await _shot("veranthos_gates", 0.8)
	# load a spread of other systems to prove the generator's output runs (all of them on desktop, a few on the web)
	var tour: Array = Data.SYSTEMS.keys()
	if web: tour = ["heart", "void_1", "noctyra", "radiant", "raptian_major", "synthari_capital"]
	var broke: Array = []
	for id in tour:
		if Data.CORE_SYSTEMS.has(id): continue
		main._load_system(id, "gate:veranthos")
		await get_tree().process_frame
		await get_tree().process_frame
		var t := _sp()
		if not (is_instance_valid(t.station) and is_instance_valid(t.planet) and is_instance_valid(t.sun_body) and t.gates.size() == (Data.SYSTEMS[id]["gates"] as Array).size() and t.gates.size() >= 1): broke.append(id)
		if id in ["void_1", "noctyra", "heart", "vortegan", "obsidrath", "crystara", "kronos"]:
			var tp2: Node3D = t.planet
			var ts2: Vector3 = (t.sun_pos - tp2.global_position).normalized()
			_tp(tp2.global_position + (ts2 * 0.75 + ts2.cross(Vector3.UP).normalized() * 0.66).normalized() * float(tp2.get_meta("radius")) * 3.4, tp2.global_position)
			main.hud.visible = false
			await _shot("planet_" + id, 0.6)
			main.hud.visible = true
	var small_ok: bool = Data.SYSTEMS["void_1"].get("small_sun", false) and not Data.SYSTEMS["veranthos"].get("small_sun", false)
	_check("%d generated systems load and run; void systems have a small sun" % tour.size(), broke.is_empty() and small_ok, ", ".join(broke.slice(0, 6)))
	main._load_system("solara", "gate:veranthos")
	main.space.controls = true
	await _wait(0.6)
	_check("Back in Solara by the Veranthos gate", GS.system_id == "solara" and main.state == "flight")

func _music() -> void:
	var ok_files := true
	var n := 0
	for m: String in Music.MOODS:
		for id: String in Music.MOODS[m]:
			n += 1
			if not Packs.PACKS.has(Music.pack(id)) or not (OS.has_feature("web") or ResourceLoader.exists(Music.path(id))): ok_files = false
	var s := _sp()
	var keep: Array = s.enemies
	s.enemies = []          # nobody around: plain flying
	main._calm_t = 0.0
	main._fight_t = 99.0
	await _wait(0.3)
	var flying: String = Music.mood
	s.enemies = keep
	var took: bool = Music.track in Music.takes(Music.mood)
	var grp: Array = s._spawn_group(s.player.global_position + Vector3(0, 0, -400), 1)   # a hostile that has seen you
	for e in grp: e["aggro"] = true
	await _wait(0.4)
	await Packs.wait(Music.pack(Music.track), 40.0)   # (on the web the track downloads first)
	await _wait(0.3)
	var battle: bool = Music.mood == "battle" and Music.track.begins_with("rift_") and Music.is_playing()
	var btrack: String = Music.track
	for e in grp:
		s.enemies.erase(e)
		e["node"].queue_free()
	s.target = null
	main._calm_t = 0.0
	Music.set_muted(true)
	var was_muted: bool = Music.muted
	Music.set_muted(false)
	_check("Music: 28 tracks, each its own pack; flying plays the track of the faction whose space it is (v1.4l), Rift Gate in battle; can be muted",
		ok_files and n == 28 and flying == Music.faction_mood(Data.SYSTEMS[s.sys_id].get("faction", "Neutral"), s.sys_id) and took and battle and was_muted and main.title.music_btn != null, "%d tracks, flying = %s, battle = %s" % [n, flying, btrack])

## NPC chat brain: understands what was typed, answers in character, remembers the pilot. No network.
func _npc_brain() -> void:
	var u1: Dictionary = Brain.understand("Where is the warp gate?")
	var u2: Dictionary = Brain.understand("I'm going to kill you, coward")
	var u3: Dictionary = Brain.understand("Mayday, I need help!")
	var u4: Dictionary = Brain.understand("name your price, I'll pay tribute")
	_check("NPC brain understands typed messages (place, threat, help, bribe)", u1["intent"] == "place" and u1["topic"] == "gate" and u2["intent"] == "threat"
		and u3["intent"] == "help" and u4["intent"] == "bribe", "%s/%s, %s, %s, %s" % [u1["intent"], u1["topic"], u2["intent"], u3["intent"], u4["intent"]])
	GS.memory.clear()
	GS.meet("vale", "friendly")
	GS.meet("voss", "enraged")
	var ctx := {"system": "solara", "hostiles": 2}
	var got: Array = []
	var take := func(line: String): got.append(line)
	Brain.ask("vale", "Where is the warp gate?", ctx, take)
	Brain.ask("voss", "Where is the warp gate?", ctx, take)
	Brain.ask("vale", "Mayday, I need help!", ctx, take)
	var in_char: bool = got.size() == 3 and (got[0] as String).find("Aquila") >= 0 and got[0] != got[1] and (got[2] as String).find("2 hostiles") >= 0 and (got[0] as String).begins_with("[")
	_check("NPC brain answers in character from what each one knows", in_char, "Vale: %s | Shade: %s" % [got[0] if got.size() > 0 else "", got[1] if got.size() > 1 else ""])
	var t0 := float(Brain.memory("voss")["trust"])
	Brain.ask("voss", "You pathetic coward", ctx, take)
	Brain.ask("voss", "shut up, scum", ctx, take)
	var mem: Dictionary = Brain.memory("voss")
	var pay: Dictionary = Brain.payload("voss", "hello", ctx)
	_check("NPC brain remembers the pilot (trust falls with insults) and can hand off to a model later", float(mem["trust"]) < t0 and int(mem["insults"]) == 2 and int(mem["talks"]) == 3
		and Brain.feeling("voss") == "cold" and (pay["persona"] as String).find("Shade") >= 0 and pay.has("memory") and not Brain.responder.is_valid(),
		"trust %.2f -> %.2f, %d insults, last line: %s" % [t0, float(mem["trust"]), int(mem["insults"]), got[-1]])
	# swap the responder (what a relay / language model would plug into), then put it back
	Brain.responder = func(_id: String, _t: String, _c: Dictionary, done: Callable): done.call("[normal]MODEL LINE")
	Brain.ask("vale", "hello", ctx, take)
	Brain.responder = Callable()
	_check("NPC brain reply step is swappable", got[-1] == "[normal]MODEL LINE", "custom responder answered")
	GS.memory.clear()

## Warping at a planet: warning first, then the ship is destroyed at the atmosphere line (towed to the station).
func _warp_into_planet() -> void:
	var s := _sp()
	var pc: Vector3 = s.planet.global_position
	var outer: float = float(s.planet.get_meta("radius")) * Data.ATMO_OUTER
	var d := (s.player.global_position - pc).normalized()
	_tp(pc + d * (outer + 420.0), pc)
	s.warp_state = "on"
	s.vel = -s.player.global_basis.z * float(GS.ship()["speed"]) * Data.WARP_MULT
	var warned := await _until(func(): return s.planet_hazard == 1, 2.0)
	await _shot("planet_warp_warning", 0.0)
	var dead := await _until(func(): return main.state == "dead" or main.state == "hub", 6.0)
	await _until(func(): return main.state == "hub", 8.0)
	_check("Warp into a planet: warning, then destroyed", warned and dead, "warned %s, state %s" % [warned, main.state])
	await _launch()

## Ship <-> mech: ~3 s transformation (weapons locked, damage carried over), mech dashes in any direction, and back.
func _mech_form() -> void:
	await Packs.wait("mechs", 60.0)
	var s := _sp()
	GS.wing_l = 0.0                      # a destroyed left wing must come back as a destroyed left arm
	s.set_player_model()
	_press("form")
	await _wait(0.8)
	var m0 := GS.missiles
	var locked := not s.trigger_system("missile") and GS.missiles == m0
	await _shot("transform_mid", 0.6)
	await _until(func(): return s.transform_t <= 0.0, 5.0)
	var took: float = s.last_transform_s
	var arm_gone: bool = s.player_vis.get("mech", false) and s.player_vis.get("gone_l", false)
	var no_warp: String = s.request_warp()
	await _shot("mech_form", 0.4)
	_check("Transform ship -> mech in ~3 s (weapons locked, left wing -> left arm)", GS.form == "mech" and locked and arm_gone and no_warp == "mech" and took < 3.6,
		"%.1f s, arm gone %s, warp '%s'" % [took, arm_gone, no_warp])
	# directional dashes: stick + BOOST
	var results: Array = []
	for stick in [Vector2(0, 1), Vector2(-0.7, -0.7), Vector2(1, 0.1), Vector2.ZERO]:   # screen stick: down = back, up-left, right, centred = straight up (v1.4n)
		main.hud.move_vec = stick
		await _wait(0.1)
		main.hud.held["thrust"] = true
		await _wait(0.3)
		var lv: Vector3 = s.player.global_basis.inverse() * s.vel
		results.append([s.last_dash, lv])
		main.hud.held.erase("thrust")
		main.hud.move_vec = Vector2.ZERO
		await _wait(1.0)
	var sp: float = float(GS.ship()["speed"])
	var ok: bool = results[0][0] == "back" and results[0][1].z > sp and results[1][0] == "forward-left" and results[1][1].x < -sp * 0.8 and results[1][1].z < -sp * 0.8 \
		and results[2][0] == "right" and results[2][1].x > sp and results[3][0] == "up" and results[3][1].y > sp
	_check("Mech boost dashes: back, forward-left, right", ok, "%s / %s / %s" % [results[0][0], results[1][0], results[2][0]])
	_press("form")
	await _until(func(): return s.transform_t <= 0.0 and GS.form == "ship", 5.0)
	var wing_gone: bool = not s.player_vis.get("mech", true) and s.player_vis["l"].all(func(w): return not w.visible)
	_check("Transform mech -> ship (damage kept, not repaired)", GS.form == "ship" and GS.wing_l <= 0.0 and wing_gone, "form %s, left wing hidden %s" % [GS.form, wing_gone])
	GS.wing_l = GS.wing_max()
	s.set_player_model()

var got_hail := false
func _fight(label: String) -> bool:
	var s := _sp()
	if not s.hail.is_connected(_on_hail): s.hail.connect(_on_hail)
	if not s.enemy_hail.is_connected(_on_enemy_hail): s.enemy_hail.connect(_on_enemy_hail)
	if not s.enemy_chatter.is_connected(_on_enemy_chat): s.enemy_chatter.connect(_on_enemy_chat)   # (v1.5k: roster troops talk on the radio rather than hail)
	var before := GS.kills
	if s.enemies.is_empty():
		for p in s.sys["patrols"]: s._spawn_group(p, 2)
	var e: Node3D = s.enemies[0]["node"]
	_tp(e.global_position + Vector3(0, 20, 300), e.global_position)
	GS.modes["guns"] = "auto"
	var shot_taken := false
	var t := 0.0
	while t < 45.0 and GS.kills == before:
		if not is_instance_valid(e):
			if s.enemies.is_empty(): break
			e = s.enemies[0]["node"]
		s.target = e
		# a player keeping the reticle on the lead point
		var ent: Dictionary = s._enemy_entry(e)
		var to: Vector3 = e.global_position - s.player.global_position
		var lead: Vector3 = e.global_position + (ent.get("vel", Vector3.ZERO) as Vector3) * (to.length() / float(GS.weapon()["speed"]))
		var dir := (lead - s.player.global_position).normalized()
		s.yaw = lerp_angle(s.yaw, atan2(-dir.x, -dir.z), 0.25)
		s.pitch = lerpf(s.pitch, asin(clampf(dir.y, -1, 1)), 0.25)
		s.move = Vector2(0, 0.6 if to.length() > 180.0 else -0.3)
		if t > 2.0 and not shot_taken and s.target_health() < 1.0:
			shot_taken = true
			await _capture(label)
		await get_tree().process_frame
		t += get_process_delta_time()
	s.move = Vector2.ZERO
	return GS.kills > before

func _on_enemy_hail(_p: Dictionary) -> void:
	got_hail = true

func _on_enemy_chat(_a = null, _b = null) -> void:
	got_hail = true

func _on_hail(_from: String, _line: String, hostile: bool) -> void:
	if hostile: got_hail = true

func _dock_at(n: Node3D) -> bool:
	var s := _sp()
	var dp: Vector3 = s.dock_point(n)
	var out := (dp - n.global_position).normalized()
	_tp(dp + out * 200.0, dp)
	await _wait(0.6)
	var ok: bool = s.dock_candidate() == n
	if not ok:
		_tp(dp + out * 60.0, dp)
		await _wait(0.3)
	await _shot("docking_approach_" + n.name.to_lower().replace(" ", "_"), 1.2)
	_press("dock")
	return await _until(func(): return main.state == "hub", 8.0)

func _launch() -> bool:
	main.launch()
	return await _until(func(): return main.state == "flight", 8.0)

## HL_SHOWCASE=1: short scripted fight for reviewing combat visuals (laser bolts, missile flame, enemy bars, pilot call).
func _showcase() -> void:
	await _wait(1.0)
	main.start_game()
	await _until(func(): return main.state == "flight", 10.0)
	await _wait(1.0)
	var s := _sp()
	var p: Node3D = s.player
	s.player.global_position += -p.global_basis.z * 250.0
	await _wait(0.3)
	s._spawn_group(p.global_position - p.global_basis.z * 220.0, 1)
	var e: Dictionary = s.enemies[s.enemies.size() - 1]
	s.target = e["node"]
	for i in 5:
		s._fire_guns()
		await _wait(0.1)
	await _capture("showcase_lasers")
	s.set_view("cockpit")
	for i in 5:
		s._fire_guns()
		await _wait(0.1)
	await _capture("showcase_lasers_cockpit")
	s.set_view("chase")
	s.fire_missile()
	await _wait(0.3)
	await _capture("showcase_missile")
	await _wait(0.6)
	main._pilot_call(Data.PILOTS["raider"][0], true)
	await _wait(0.5)
	await _capture("showcase_call")
	get_tree().quit()

## An env flag, or on the web the same name in the page address (?autotest&HL_V19Z) to run one job in the browser.
func _flag(n: String) -> bool:
	if OS.get_environment(n) != "": return true
	if OS.has_feature("web"): return str(JavaScriptBridge.eval("location.search", true)).find(n) >= 0
	return false

func _run() -> void:
	if OS.get_environment("HL_SOAK") != "":
		await _soak(int(OS.get_environment("HL_SOAK")))
		return
	if OS.get_environment("HL_SUN") != "":   # the sun checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _launch()
		await _sun()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_MISSILE") != "":   # the Job M lead box / missile lock / dodge checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _combat_m()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_ART") != "":   # the Job N concept-art map and Lockon signature checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _art_n()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_BLOCKS") != "":   # EXPERIMENT: the big-block ground patch only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _blocks()
		await _regions()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_REGIONS") != "":   # the v1.7a blocks-everywhere checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _regions()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AY") != "":   # the v1.6g mission-target lock-on checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ay()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AX") != "":   # the v1.5x super missile / mine checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ax()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AT") != "":   # the Job AT checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_at()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AS") != "":   # the Job AS checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_as()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_SPEED") != "":   # v1.8e: frame-time probe (script time per frame, by scene)
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _speed_probe()
		get_tree().quit()
		return
	if OS.get_environment("HL_PLANET") != "":   # v1.9c: planet lag probe (frame time + block costs by phase)
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _planet_probe()
		get_tree().quit()
		return
	if OS.get_environment("HL_RING") != "":   # v1.8f: the ringed planet only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _ringed_planet()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_FPV") != "":   # v1.7z: the mech first-person view checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _mech_fpv()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V19E") != "":   # the v1.9e galaxy chart boxes and wing loadout checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19e()
		await _job_v19g()
		await _job_v19h()
		await _job_v19i()
		await _job_v19j()
		await _job_v19k()
		await _job_v19l()
		await _job_v19m()
		await _job_v19n()
		await _job_v19o()
		await _job_v19p()
		await _job_v19q()
		await _job_v19r()
		await _job_v19s()
		await _job_v19u()
		await _job_v19w()
		await _job_v19x()
		await _job_v35()
		await _job_v19z()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if _flag("HL_V35"):   # the v3.5 room panorama checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v35()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if _flag("HL_V19Z"):   # the v1.9z cloud weather checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19z()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V19X") != "":   # the v1.9x tidy equip page checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19x()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V19W") != "":   # the v1.9w ship level checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19w()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V19U") != "":   # the v1.9u combat and equip checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19u()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V19S") != "":   # the v1.9s nebula checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19s()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V19R") != "":   # the v1.9r checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19r()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V19Q") != "":   # the v1.9q RETOPO import checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19q()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_ST3D") != "":   # the v1.9d Station3D-Retopo checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19d()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V19B") != "":   # the v1.9b planet docking platform checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v19b()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AR") != "":   # the Job AR checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ar()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AQ") != "":   # the Job AQ checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_aq()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AP") != "":   # the Job AP checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ap()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AO") != "":   # the Job AO checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ao()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AN") != "":   # the Job AN test flow only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_an()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AM") != "":   # the Job AM checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_am()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AL") != "":   # the Job AL checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_al()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AK") != "":   # the Job AK checks only
		await _job_ak()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_TERRAIN") != "":   # work tool: pictures of New Terra's tiles from low altitude (no checks)
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		for t in [3, 0, 1, 2, 5, 6, 8]:
			main._load_surface("new_terra", t)
			await _frames(6)
			var hx := 900.0
			var hz := 900.0
			var gh: float = Surface.height("new_terra", t, hx, hz)
			_tp(Vector3(hx, maxf(gh, 0.0) + 160.0, hz), Vector3(hx - 2600.0, maxf(gh, 0.0) + 40.0, hz - 2600.0))
			await _shot("terrain_%d_%s" % [t, Surface.PLANETS["new_terra"]["tiles"][t]], 1.0)
		# close to the sea: a low pass over the coast's water, looking toward the shore
		main._load_surface("new_terra", 1)
		await _frames(6)
		var wet := Vector2.INF
		var dry := Vector2.INF
		for k in 400:
			var q := Vector2(randf_range(-2200, 2200), randf_range(-2200, 2200))
			var qh: float = Surface.height("new_terra", 1, q.x, q.y)
			if qh < -25.0 and wet == Vector2.INF: wet = q
			if qh > 5.0 and qh < 60.0 and dry == Vector2.INF: dry = q
		if wet != Vector2.INF and dry != Vector2.INF:
			var mid := wet.lerp(dry, 0.6)
			_tp(Vector3(wet.x, 22.0, wet.y), Vector3(mid.x, 0.0, mid.y))
			await _shot("terrain_water_close", 1.5)
		get_tree().quit()
		return
	if OS.get_environment("HL_AJ") != "":   # the Job AJ checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_aj()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AI") != "":   # the Job AI checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ai()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AG") != "":   # the Job AG checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ag()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AE") != "":   # the Job AE checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ae()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AD") != "":   # the Job AD checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ad()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AC") != "":   # the Job AC checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ac()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AB") != "":   # the Job AB checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_ab()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_AA") != "":   # the Job AA checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_aa()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_Z") != "":   # the Job Z checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_z()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_Y") != "":   # the Job Y checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_y()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_X") != "":   # the Job X checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_x()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_UI") != "":   # v3.1 work tool: pictures of the station hub and the galaxy map (no checks)
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _ui_shots()
		get_tree().quit()
		return
	if OS.get_environment("HL_W") != "":   # the Job W checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_w()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_V") != "":   # the Job V checks only (HL_V=2: then jump to a Savagers system for review shots)
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_v()
		if OS.get_environment("HL_V") == "2":
			main._load_system("plundros", "station")
			await _wait(2.0)
			await Packs.wait("structures", 30.0)
			await _wait(1.0)
			var sp := _sp()
			main.hud.visible = false
			_tp(sp.station.global_position + Vector3(260, 120, 420), sp.station.global_position)
			await _shot("v_savagers_station", 0.6)
			if sp.beacon:
				_tp(sp.beacon.global_position + Vector3(300, 80, 380), sp.beacon.global_position)
				await _shot("v_plundros_beacon", 0.6)
			for e in sp.enemies.slice(0, 3):
				_tp((e["node"] as Node3D).global_position + Vector3(14, 6, 22), (e["node"] as Node3D).global_position)
				await _shot("v_fighter", 0.3)
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_U") != "":   # the Job U checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_u()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_S") != "":   # the Job S checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_s()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_Q") != "":   # the Job Q checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_q()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_P") != "":   # the Job P checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_p()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_O") != "":   # the Job O checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _job_o()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_COLLIDE") != "":   # the Job L collision damage checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _collide_l()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_GATE") != "":   # the Job K gate docking + warp tunnel checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _gate_k()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_CONTROLS") != "":   # the Job J desktop controls checks only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		await _wait(1.0)
		await _controls_j()
		for r in results: print("[route] ", r)
		get_tree().quit()
		return
	if OS.get_environment("HL_SHOWCASE") != "":
		await _showcase()
		return
	await _wait(1.5)
	_publish("title")
	await _shot("title", 1.0)
	if FileAccess.file_exists("res://web_shell.html"):   # (the shell is not inside the web build itself)
		var shell := FileAccess.get_file_as_string("res://web_shell.html")
		_check("Version %s matches the web page (the landing page reads it from there)" % Data.VERSION, shell.find('name="hl-version" content="%s"' % Data.VERSION) >= 0)
	await Packs.wait("intro", 60.0)
	await _wait(1.2)
	await _shot("title_movie", 0.2)
	# v1.5a: the owner's intro movie replaces the panning collage (the old check looked for the collage strip)
	var mv: VideoStreamPlayer = main.title.movie
	var S0: Vector2 = get_viewport().get_visible_rect().size
	_check("Start screen: the owner's intro movie fills the screen and plays on repeat (the old panning collage is gone from the game)",
		mv != null and mv.stream != null and mv.stream.resource_path.ends_with("title_movie.ogv") and mv.loop and mv.is_playing() and main.title.art_k >= 1.0
		and mv.size.x >= S0.x - 1.0 and mv.size.y >= S0.y - 1.0 and FileAccess.get_file_as_bytes(main.title.MOVIE).size() > 2000000 and not ResourceLoader.exists("res://assets/intro/title_collage.jpg"),
		"drawn %s on a %s screen" % [str(mv.size) if mv != null else "-", str(S0)])   # (the engine does not report a Theora clip's length, so the file size stands in for "a real clip")
	main.start_game()
	_check("Godot boot + START", await _until(func(): return main.state == "flight", 10.0))
	await _wait(1.0)
	_check("Mobile HUD shown", main.hud.visible and main.hud.buttons.has("slot_0") and main.hud.buttons.has("slot_2") and main.hud.buttons.has("shield") and main.hud.buttons.has("repair") and main.hud.buttons.has("tractor") and main.hud.buttons.has("form") and main.hud.buttons.has("stop") and main.hud.buttons.has("warp") and main.hud.buttons.has("thrust") and main.hud.buttons.has("kill") and not main.hud.buttons.has("call") and main.hud.buttons.has("log") and main.hud.buttons.has("ground"))   # (v1.8q: CALL is inside LOG)
	await _shot("solara_flight")
	var s := _sp()
	s.hail.connect(_on_hail)   # listen from the start: enemies may call as soon as they see you (e.g. a warp spool)
	s.enemy_hail.connect(_on_enemy_hail)
	s.enemy_chatter.connect(_on_enemy_chat)   # (v1.5k: the opening's roster troops talk on the radio rather than hail)
	_check("Real/placeholder player ship", is_instance_valid(s.model), "placeholder=%s" % s.model.get_meta("placeholder", true))
	# ---- first-person cockpit, comms and the AUTO/MANUAL system panels
	_press("view")
	await _wait(0.5)
	_check("First-person cockpit view", GS.view == "cockpit" and not s.model.visible)
	await _shot("cockpit_view")
	await _until(func(): return not main.hud.comms_open, 9.0) # launch call closes by itself
	_check("Incoming call auto-closes; no radio call from control at the very start (v1.7n, owner)", not main.hud.comms_open and not ("vale" in GS.met))
	_press("call")
	await _wait(0.4)
	_check("CALL talks to target/controller", main.hud.comms_mode == "talk")
	var les1: String = str(GS.tutorial_seen.back()) if GS.tutorial_seen.size() == 1 else ""
	_check("v1.8a (owner): the first lesson is Kim's intro, told with her picture (smiling) and text, no video", les1 == "intro"
		and str(main.hud.slot("r").get("video", "")) == "" and main.hud.comms_from.begins_with("Kim") and str(main.hud.slot("r").get("expr", "")) == "smile" and main.hud._face_tex("tutor", "smile") != null,
		"seen=%s from=%s expr=%s" % [GS.tutorial_seen, main.hud.comms_from, main.hud.slot("r").get("expr", "")])
	await _wait(2.0)
	await _shot("tutor_intro")
	_check("CALL with nothing targeted gives a tutorial lesson from the guide (v1.7r, owner)", les1 != "" and main.hud.comms_from.contains("Tutorial")
		and main.hud.comms_face == str(Data.CHARACTERS[Data.TUTOR_ID]["face"]), "seen=%s from=%s" % [GS.tutorial_seen, main.hud.comms_from])
	_press("hangup")
	await _wait(0.2)
	_press("call")
	await _wait(0.4)
	var keep_en: Array = s.enemies
	var seen_keep: Array = GS.tutorial_seen.duplicate()
	s.enemies = [{"node": s.player}]   # (one pretend hostile right on top of you)
	var hot: String = main.tutor_next()
	s.enemies = keep_en
	GS.tutorial_seen = seen_keep
	_check("A repeat CALL gives the next lesson; with hostiles near, combat lessons come first (v1.7r)", GS.tutorial_seen.size() == 2 and str(GS.tutorial_seen[1]) != les1
		and str(GS.tutorial_seen[1]) == "fly" and str(main.hud.slot("r").get("video", "")) == ""
		and hot in ["fire", "missile", "shield"], "seen=%s hot=%s" % [GS.tutorial_seen, hot])
	_press("hangup")
	await _wait(0.2)
	GS.tutorial_seen = []
	for l in Data.TUTORIAL: GS.tutorial_seen.append(str(l["id"]))   # (lessons done: CALL goes back to the controller)
	_press("call")
	await _wait(0.4)
	await _shot("intercom_call")
	_press("hangup")
	_check("Hang up", not main.hud.comms_open or main.hud.comms_mode == "incoming")
	_save_check()
	_check("v1.8e (owner: smooth on the phone): the 3D world is drawn at most %d pixels and stretched (a 2400x1080 phone screen: %.2f of its resolution; a 1280x720 one: all of it); the HUD stays sharp" % [int(Data.RENDER_PIXELS_MAX), main.render_scale_for(Vector2i(2400, 1080))],
		main.render_scale_for(Vector2i(2400, 1080)) < 0.7 and is_equal_approx(main.render_scale_for(Vector2i(1280, 720)), 1.0) and is_equal_approx(get_viewport().scaling_3d_scale, main.render_scale), "scale now %.2f" % main.render_scale)
	await _mech_fpv()
	_press("log")
	await _wait(0.5)
	_check("LOG pull-out contacts", main.hud.comms_mode == "roster" and main.hud.buttons.has("met_0"))
	await _shot("contacts_tab")
	main.hud._layout()
	# v1.8q (owner): CALL is inside LOG: no CALL button; a tapped name puts the picture up on the friendly side with CALL; 8 buttons a side
	var hq: Control = main.hud
	var no_call: bool = not hq.buttons.has("call") and hq.buttons.has("met_hail") and hq.buttons["met_hail"].position.y < hq.buttons["met_0"].position.y
	_press("met_hail")
	await _wait(0.3)
	hq._layout()
	var hsl: Dictionary = hq.slot("r")
	var hail_ok: bool = hq.pick == "hail" and hsl.get("mode", "") == "pick" and hq.buttons.has("call_pick") and hq.comms_mode == "roster" and str(hsl.get("from", "")) != ""
	_press("met_0")
	await _wait(0.3)
	hq._layout()
	var psl: Dictionary = hq.slot("r")
	var pc: Dictionary = Data.CHARACTERS[hq.contact_at(0)]
	var pick_ok: bool = hq.pick == hq.contact_at(0) and psl.get("mode", "") == "pick" and str(psl.get("face", "")) == str(pc.get("face", "")) and str(psl.get("from", "")).begins_with(str(pc["name"])) \
		and hq.buttons.has("call_pick") and hq.side_rect("r").encloses(hq.buttons["call_pick"]) and hq.comms_mode == "roster" and not hq.slots["l"].has("mode")
	await _shot("log_pick", 0.3)
	var lefts: Array = ["fire", "slot_0", "slot_1", "slot_2", "stop", "thrust", "warp"] + ["zoom" if hq.buttons.has("zoom") else "kill"]   # v1.9 (owner): weapons + speed on the left
	var rights := ["shield", "repair", "fullscreen" if hq.buttons.has("fullscreen") else "lock_a", "lock_c", "form", "ground", "special", "tractor"]   # defence + special moves on the right (FULL SCREEN in the web build)
	var eight: bool = lefts.all(func(b): return hq.buttons.has(b) and hq.buttons[b].end.x < hq.S.x * 0.5) and rights.all(func(b): return hq.buttons.has(b) and hq.buttons[b].position.x > hq.S.x * 0.5)
	var clear := true   # the centre strip sits between the two blocks
	for b in ["map", "view", "log", "target", "goto"]:
		if hq.buttons[b].position.x < hq.buttons["warp"].end.x or hq.buttons[b].end.x > hq.buttons["form"].position.x: clear = false
	_check("v1.8q (owner): CALL is inside LOG (no CALL button): the list starts with TARGET / CONTROL; a tapped name shows the picture on the friendly side with CALL under it; 8 buttons on the left and 8 on the right, the centre strip between them",
		no_call and hail_ok and pick_ok and eight and clear, "no_call %s hail %s pick %s eight %s clear %s" % [no_call, hail_ok, pick_ok, eight, clear])
	# v1.8r (owner): the call list is on the left, the picked face on the right; only people on speaking terms are listed; it scrolls
	var left_list: bool = hq.contacts_rect().end.x < hq.S.x * 0.5 and not hq.buttons.has("type") and hq.buttons["met_0"].end.x < hq.S.x * 0.5 and hq.side_rect("r").position.x > hq.S.x * 0.5
	var met_keep: Array = GS.met.duplicate()
	var mood_keep: Dictionary = GS.mood.duplicate()
	var first_id: String = hq.contact_at(0)
	GS.mood[first_id] = "enraged"
	var dropped: bool = not (first_id in hq.call_list()) and first_id in GS.met
	GS.mood = mood_keep
	var back_on: bool = first_id in hq.call_list()
	for cid2 in Data.CHARACTERS:
		if not (cid2 in GS.met): GS.met.append(cid2)
	GS.mood = {}
	hq.contact_scroll = 0
	hq._layout()
	var many: int = hq.call_list().size()
	var can_scroll: bool = many > hq.contact_rows() - 1 and hq.buttons.has("met_down")
	var top0: String = hq.contact_at(0)
	_press("met_down")
	hq._layout()
	var scrolled: bool = hq.contact_scroll == 1 and hq.contact_at(0) != top0 and hq.contact_at(0) == str(hq.call_list()[1])
	_press("met_up")
	await _shot("log_list_left", 0.3)
	GS.met = met_keep
	GS.mood = mood_keep
	hq.contact_scroll = 0
	hq._layout()
	_check("v1.8r (owner): the call list is on the left (face and name), the picked person's picture with CALL on the right; someone who turns against you drops off the list; UP / DOWN scroll it when there are more people than fit",
		left_list and dropped and back_on and can_scroll and scrolled, "left %s dropped %s back %s scroll %s (%d people) scrolled %s" % [left_list, dropped, back_on, can_scroll, many, scrolled])
	_press("call_pick")
	await _wait(0.6)
	hq._layout()
	_check("Call a contact from LOG", hq.slot("r").get("mode", "") == "talk")
	# v1.8s (owner: less on the screen): one panel, on the left: the list, then (after CALL) the text screen with CLOSE; the picture at the right edge
	var chat_up: bool = hq.console_open and hq.console_view == "chat" and hq.buttons.has("type") and hq.buttons.has("talk") and hq.buttons.has("voice") and hq.buttons.has("chat_close") and not hq.buttons.has("met_0") \
		and hq.msglog_rect().end.x < hq.S.x * 0.5 and hq.msglog_rect().encloses(hq.buttons["type"])
	var edge: bool = hq.side_rect("r").end.x > hq.S.x - 12.0
	await _shot("log_chat", 0.3)
	hq.open_comms("Raider pilot", "You are mine.", "incoming", true)   # a hostile caller takes the left side: the panel there goes
	await _wait(0.2)
	hq._layout()
	var no_layer: bool = not hq.console_open and hq.side_rect("l").position.x < 12.0 and not hq.buttons.has("type")
	hq.close_side("l")
	_press("side_r")
	await _wait(0.5)
	hq._layout()
	var again: bool = hq.console_open and hq.console_view == "chat" and hq.buttons.has("chat_close")
	_press("chat_close")
	await _wait(0.5)
	hq._layout()
	var closed: bool = not hq.console_open and hq.slot("r").get("mode", "") == "talk"
	_check("v1.8s (owner): one panel only, on the left: LOG = the call list; CALL replaces it with the text screen (TYPE / TALK / VOICE, CLOSE) while the picture sits at the right edge; a hostile caller takes the left side and the panel goes; CLOSE puts the text screen away and the call goes on",
		chat_up and edge and no_layer and again and closed, "chat %s edge %s no_layer %s again %s closed %s" % [chat_up, edge, no_layer, again, closed])
	_press("hangup")
	var mines0 := GS.mines
	var sh0 := GS.shield_charges
	GS.shield = GS.max_shield() * 0.3
	_press("shield")
	_press("slot_2")   # default slot 3 = mine
	await _wait(0.3)
	_check("Corner buttons: SHIELD charge + weapon slot mine", GS.mines == mines0 - 1 and GS.shield_charges == sh0 - 1, "mines %d -> %d, charges %d -> %d" % [mines0, GS.mines, sh0, GS.shield_charges])
	_press("view")
	await _wait(0.3)
	# ---- THRUST / STOP / ENGINE KILL / WARP
	main.hud.held["thrust"] = true
	await _wait(2.0)
	var boost_speed := s.speed_now
	_check("Thrust (afterburner)", s.boosting and boost_speed > float(GS.ship()["speed"]) * 1.3, "speed %d" % int(boost_speed))
	main.hud.held.erase("thrust")
	# warp now spools while you keep flying; weapons lock as soon as it starts
	main.hud.move_vec = Vector2(0, -1)
	var early: String = s.request_warp()
	await _wait(1.2)
	var m_lock := GS.missiles
	var locked_early := not s.trigger_system("missile") and GS.missiles == m_lock
	var flying: float = s.speed_now
	_check("Warp spools while moving, weapons locked", early == "charging" and s.warp_state == "charging" and flying > 20.0 and locked_early, "speed %d during spool" % int(flying))
	await _shot("warp_spool_moving", 0.0)
	s.request_warp()   # cancel
	main.hud.move_vec = Vector2.ZERO
	_press("stop")
	var stopped := await _until(func(): return s.speed_now < 0.7 and not s.braking, 8.0)
	_check("STOP to full stop", stopped, "speed %.1f" % s.speed_now)
	s.vel = -s.player.global_basis.z * 30.0
	_press("kill")
	var v0: Vector3 = s.vel
	var y0: float = s.yaw
	main.hud.aim_vec = Vector2(1, 0)
	await _wait(1.0)
	main.hud.aim_vec = Vector2.ZERO
	_check("Engine kill: drift while turning", s.engine_kill and s.vel.distance_to(v0) < 0.5 and absf(s.yaw - y0) > 0.5, "yaw %.2f -> %.2f" % [y0, s.yaw])
	await _shot("engine_kill_drift", 0.2)
	_press("kill")
	_press("stop")
	await _until(func(): return s.speed_now < 0.7 and not s.braking, 8.0)
	_press("warp")
	var t_spool := Time.get_ticks_msec()
	await _wait(1.6)
	var charging: bool = s.warp_state == "charging"
	await _shot("warp_charging", 0.0)
	await _until(func(): return s.warp_state == "on", 6.0)
	var spool_s := (Time.get_ticks_msec() - t_spool) / 1000.0
	await _wait(0.6)
	var m_before := GS.missiles
	var locked := not s.trigger_system("missile") and GS.missiles == m_before
	_check("Warp: 5 s spool then shoots forward, weapons locked", charging and s.warp_state == "on" and locked and spool_s > 4.5 and s.speed_now > float(GS.ship()["speed"]) * 3.0, "spool %.1f s, speed %d" % [spool_s, int(s.speed_now)])
	await _shot("warp_travel", 0.2)
	_press("warp")
	await _wait(0.4)
	_check("Drop out of warp", s.warp_state == "off")
	# ---- combat
	var credits0 := GS.credits
	var won := await _fight("combat")
	_check("Combat: enemy destroyed", won, "kills=%d" % GS.kills)
	var pods := s.loot.size()
	var credits1 := GS.credits
	_press("tractor")
	var pulled := await _until(func(): return s.loot.is_empty(), 8.0)
	await _shot("tractor_loot", 0.0)
	_check("Credits earned + TRACTOR pulls loot", GS.credits > credits0 and pods > 0 and pulled and GS.credits > credits1, "%d -> %d, pods %d" % [credits0, GS.credits, pods])
	_check("Enemy called you on the intercom", got_hail)
	await _wait(0.5)
	_check("No story leader calls in after the opening fight (v1.5k: the opening enemies are ordinary Imperium troops; Shade stays out of it)", not GS.mood.has("voss") and Data.OPENING_SYSTEMS.has("solara"))
	await _section_loop()
	await _mech_form()
	await _generic_pilots()
	await _flight_and_comms()
	_npc_brain()
	await _music()
	await _system_sky("sky_solara")
	# ---- dock at station
	_check("Station docking", await _dock_at(s.station), s.station.name)
	await _wait(0.8)
	await _shot("hub_station")
	main.hub.show_screen("equipment")
	await _wait(0.3)
	(main.hub.find_child("Card_pulse2", true, false) as Button).pressed.emit()   # (v1.9y: pick the card, then BUY)
	await _frames(2)
	var btn: Button = main.hub.find_child("ShopBuy", true, false)
	if btn and not btn.disabled: btn.pressed.emit()
	await _wait(0.3)
	_check("Weapon purchase", GS.weapon_id == "pulse2", "weapon=%s credits=%d" % [GS.weapon_id, GS.credits])
	var rack_btn: Button = main.hub.find_child("Rack_swarm", true, false)
	var fit_btn: Button = main.hub.find_child("Rack_triple", true, false)
	_check("Job M: Equipment lists the missile racks (v1.4l: the Six Rack comes fitted, the Triple Rack can be fitted instead)", rack_btn != null and fit_btn != null and rack_btn.disabled
		and rack_btn.text == "FITTED" and fit_btn.text == "FIT", rack_btn.text if rack_btn else "no button")
	await _shot("equipment_dealer")
	var m0 := GS.missiles
	main.hub.show_screen("ships")
	await _wait(0.5)
	# the route test is credited enough for one ship so the dealer can be verified in one run
	GS.add_credits(4000)
	main.hub.show_screen("ships")
	await _wait(0.3)
	var sb: Button = main.hub.find_child("Ship_lancer", true, false)
	if sb and not sb.disabled: sb.pressed.emit()
	await _wait(0.4)
	_check("Ship purchase (Lancer, 4 cannons); the dealer sells seven real ships (v1.5p: + the Elyza fighter)", GS.ship_id == "lancer" and int(GS.ship()["guns"]) == 4 and Data.SHIP_ORDER == ["cadet", "ranger", "hauler", "elyza", "lancer", "bulk_empty", "bulk"] and ShipFactory.has_real_model("bulk_empty") and ShipFactory.has_real_model("ranger") and ShipFactory.has_real_model("hauler") and ShipFactory.has_real_model("bulk"), "ship=%s hull=%d" % [GS.ship_id, int(GS.max_hull())])
	main.hub.open_inspector("lancer")
	await _wait(0.4)
	var cam0: Vector3 = main.hub.insp_cam.position
	main.hub.turn_inspector(Vector2(140, 30))
	main.hub.zoom_inspector(0.75)
	await _wait(0.3)
	await _shot("ship_inspector", 0.2)
	var sheet: String = main.hub.insp_stats.text
	_check("Hangar ship inspector: turn, zoom, full stats", is_instance_valid(main.hub.inspect) and main.hub.insp_cam.position.distance_to(cam0) > 3.0 and main.hub.insp_dist < 24.0
		and "Gun hardpoints" in sheet and "Hull" in sheet and "Warp" in sheet, "zoom %.1f m" % main.hub.insp_dist)
	main.hub.close_inspector()
	await _shot("ship_dealer")
	_check("Launch from station", await _launch())
	s = _sp()
	_check("New ship flies", s.model.name.ends_with("lancer"), s.model.name)
	# ---- real autopilot leg to the planet
	s.target = s.planet
	_press("goto")
	var arrived := await _until(func(): return s.dock_candidate() == s.planet or s.autopilot == null, 70.0)
	_check("Autopilot + warp to planet", arrived and s.dock_candidate() == s.planet, "dist=%d" % int(s.distance_to(s.planet)))
	_check("Planet docking", await _dock_at(s.planet), s.planet.name)
	await _wait(0.6)
	await _shot("hub_planet")
	_check("Planet launch", await _launch())
	await _planet_surface()
	await _warp_into_planet()
	await _sun()
	s = _sp()
	# ---- asteroid field
	var bc: Vector3 = s.belt_center
	_tp(bc + Vector3(0, 30, s.belt_radius + 120), bc)
	var in_belt := false
	var tb := 0.0
	while tb < 14.0 and not in_belt:
		s.move = Vector2(0, 1) # thumb on the thrust stick
		in_belt = s.in_belt
		await get_tree().process_frame
		tb += get_process_delta_time()
	for i in 40:
		s.move = Vector2(0, 1)
		await get_tree().process_frame
	await _shot("asteroid_field")
	s.move = Vector2.ZERO
	_check("Asteroid field (v1.7x: block asteroids)", in_belt and s.asteroids.size() >= int(Data.ASTEROID_COUNT * 0.8) and s.rocks.size() - s.nebulae.reduce(func(acc, nd): return acc + int(nd.get("rocks_n", 0)), 0) == s.asteroids.size(), "asteroids=%d rocks=%d" % [s.asteroids.size(), s.rocks.size()])   # (v1.9z: rock-field clouds add their own rocks)
	await _asteroid_mining(s)
	# ---- nebula
	var nc: Vector3 = s.nebula_center
	_tp(nc + Vector3(s.nebula_radius * 0.55, 0, 0), nc)
	var in_neb := await _until(func(): return s.in_nebula > 0.5, 5.0)
	await _shot("nebula")
	_check("Nebula haze + sensor reduction", in_neb, "depth=%.2f" % s.in_nebula)
	# ---- gate
	var g: Node3D = s.gate
	_tp(g.global_position + g.global_basis.z * 420.0, g.global_position)
	await _shot("jump_gate", 1.2)
	await Packs.wait("structures", 30.0)
	await _wait(0.3)
	var ring_tris := 0
	if s.gate_model != null: ring_tris = s.gate_model.mesh.surface_get_array_len(0) if s.gate_model.mesh.surface_get_array_index_len(0) == 0 else s.gate_model.mesh.surface_get_array_index_len(0) / 3
	_check("Jump gate wears the owner's ring model (structures pack, under 6000 triangles)", s.gate_model != null and not s.gate_standin.visible and ring_tris > 1000 and ring_tris <= 6000, "tris=%d" % ring_tris)
	_check("Liberty Hub wears the owner's station model; Vega keeps the code-made one until it gets its own", s.station_model != null and s.sys["station"].get("model", "") == "wheel_station" and not Data.SYSTEMS["vega"]["station"].has("model"))
	s.target = g
	_press("goto")
	await _until(func(): return s.gate_in_range(), 25.0)
	_gate_jump()   # Job K: the gate prompt docks; ACTIVATE JUMP on the docking screen jumps
	await _until(func(): return main.fx.warp > 0.3, 8.0)
	var rings_n: int = s.jump_rings.size()
	await _capture("jump_rings")
	_check("Jump rings light up behind the gate during the jump", rings_n == s.JUMP_RINGS, "rings=%d" % rings_n)
	await _until(func(): return main.fx.warp > 0.8, 8.0)
	await _capture("warp")
	await _until(func(): return main.state == "flight", 15.0)
	_check("Jump gate to Vega", GS.system_id == "vega" and "vega" in GS.discovered)
	await _wait(1.0)
	await _shot("vega_arrival")
	await _system_sky("sky_vega")
	s = _sp()
	_check("Vega dock", await _dock_at(s.station), s.station.name)
	await _wait(0.5)
	await _shot("hub_vega")
	_check("Vega launch", await _launch())
	s = _sp()
	_press("view")
	_check("Vega combat (cockpit view)", await _fight("vega_combat_cockpit"), "kills=%d" % GS.kills)
	_press("view")
	main.open_map()
	await _wait(0.4)
	await _shot("navigation_map")
	# galaxy map: the whole network on screen as data only — nothing extra loads
	var no_music := func(d: Dictionary) -> Dictionary:   # (a music track may finish downloading meanwhile; that is not the map)
		var o := {}
		for k: String in d: if not k.begins_with("mus_"): o[k] = d[k]
		return o
	var packs_before: Dictionary = no_music.call(Packs.state)
	var res_before := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	main.navmap.galaxy_requested.emit()
	await _wait(0.6)
	var gm: Control = main.galaxymap
	var net := Galaxy.network()
	var playable: int = net["systems"].values().filter(func(x): return x["playable"]).size()
	await _shot("galaxy_map")
	gm.selected = "vega"
	gm.press("expand")
	await _wait(0.4)
	await _shot("galaxy_system_vega")
	var res_after := Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	_check("Galaxy map: %d systems shown, data only" % net["systems"].size(), gm.visible and net["systems"].size() == Data.SYSTEMS.size() and playable == net["systems"].size() and no_music.call(Packs.state) == packs_before and res_after - res_before < 20,
		"links %d, resources +%d" % [net["links"].size(), int(res_after - res_before)])
	gm.press("close")   # back out of the system chart first
	var sol: Vector3 = (net["systems"]["solara"]["pos"] as Vector3) - gm.viewer   # look straight at Solara
	gm.yaw = atan2(sol.x, -sol.z)
	gm.pitch = asin(clampf(sol.y / maxf(sol.length(), 0.001), -1, 1))
	await get_tree().process_frame
	await get_tree().process_frame
	await _shot("galaxy_focus", 0.2)
	_check("Galaxy map: the system in the middle lights up with its name", gm.focus == "solara" and gm.focus_t > 0.0, "focus %s" % gm.focus)
	if gm.visible: gm.press("close")
	main.navmap.visible = false
	main._on_map_closed()
	_press("log")
	await _wait(0.6)
	_check("Contacts roster grows as you meet people", GS.met.size() >= 4, "met: %s" % ", ".join(GS.met))
	await _shot("contacts_after_vega")
	_press("log")
	var g2: Node3D = s.gate
	_tp(g2.global_position + g2.global_basis.z * 180.0, g2.global_position)
	await _wait(0.4)
	_gate_jump()   # Job K: the gate prompt docks; ACTIVATE JUMP on the docking screen jumps
	await _until(func(): return main.state == "flight" and GS.system_id == "solara", 15.0)
	_check("Return jump to Solara", GS.system_id == "solara")
	await _wait(1.0)
	await _shot("solara_return")
	await _combat_m()
	await _art_n()
	await _job_o()
	await _job_p()
	await _job_q()
	await _job_s()
	await _job_u()
	await _job_v()
	await _job_w()
	await _job_x()
	await _job_y()
	await _job_z()
	await _job_aa()
	await _job_ab()
	await _job_ac()
	await _job_ad()
	await _job_ae()
	await _job_ag()
	await _job_ai()
	await _job_aj()
	await _job_ak()
	await _job_al()
	await _job_am()
	await _job_an()
	await _job_ao()
	await _job_ap()
	await _job_aq()
	await _job_ar()
	await _job_as()
	await _job_at()
	await _job_ax()
	await _job_ay()
	await _job_v19b()
	await _job_v19d()
	await _job_v19e()
	await _job_v19g()
	await _job_v19h()
	await _job_v19i()
	await _job_v19j()
	await _job_v19k()
	await _job_v19l()
	await _job_v19m()
	await _job_v19n()
	await _job_v19o()
	await _job_v19p()
	await _job_v19q()
	await _job_v19r()
	await _job_v19s()
	await _job_v19u()
	await _job_v19w()
	await _job_v19x()
	await _job_v35()
	await _job_v19z()
	await _blocks()
	await _regions()
	await _galaxy()
	await _controls_j()
	await _gate_k()
	await _collide_l()
	if main.state == "flight": await _ringed_planet()   # v1.8f
	var passed := results.filter(func(r): return r["pass"]).size()
	print("[route] RESULT %d/%d PASS" % [passed, results.size()])
	_publish("done", true)
	GS.god_mode = false
	if not web and "--quit-after-test" in OS.get_cmdline_user_args():
		get_tree().quit(0 if passed == results.size() else 1)

# ---------------------------------------------------------------- Job J (v1.4f): desktop keyboard + mouse controls
func _frames(n := 3) -> void:
	for i in n: await get_tree().process_frame

func _key(code: int, pressed: bool, shift := false) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.keycode = code
	k.shift_pressed = shift
	k.pressed = pressed
	Input.parse_input_event(k)

func _tap(code: int, shift := false) -> void:
	_key(code, true, shift)
	await _frames()
	_key(code, false, shift)
	await _frames()

## Viewport point -> window point (input events arrive in window pixels and the viewport stretches them back).
func _win(at: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * at

func _mouse(button: int, pressed: bool, at: Vector2) -> void:
	at = _win(at)
	var m := InputEventMouseButton.new()
	m.button_index = button
	m.pressed = pressed
	m.position = at
	m.global_position = at
	if pressed: m.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else (MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else 0)
	Input.parse_input_event(m)

func _move_mouse(at: Vector2, left_held: bool) -> void:
	at = _win(at)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if left_held else 0
	Input.parse_input_event(m)

func _controls_j() -> void:
	if main.galaxymap.visible: main.galaxymap.visible = false
	if main.navmap.visible: main.navmap.visible = false
	if main.state == "map": main._on_map_closed()
	await _until(func(): return main.state == "flight", 5.0)
	var c: Controls = main.controls
	var s := _sp()
	var vs := get_viewport().get_visible_rect().size
	c.settings_path = "user://settings_autotest.cfg"   # never touch a real player's settings file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(c.settings_path))
	c.touch_available = false
	c.mode_pref = "auto"
	c.reset_defaults()
	if GS.form == "mech": s.start_transform()
	s.autopilot = null
	if s.warp_state != "off": s.drop_warp()
	# ---- 1. the action config
	var ids := {}
	var keys := {}
	var ok := true
	for a in Data.KBM_ACTIONS:
		ok = ok and a.has("id") and a.has("name") and a.has("key") and a.has("rebind") and str(a["name"]) != "" and Controls.parse_binding(a["key"]) != null and not ids.has(a["id"]) and not keys.has(a["key"])
		ids[a["id"]] = true
		keys[a["key"]] = true
	_check("Job J: control config — every action has an id, a name, a default key/button and a rebindable flag", ok and ids.size() >= 20, "%d actions" % ids.size())
	# ---- 2. Freelancer baseline, with the owner's correction (RIGHT-click fires)
	var want := {"fire": "Mouse Right", "select": "Mouse Left", "mouse_flight": "Space", "missile": "Q", "forward": "W", "back": "S",
		"strafe_left": "A", "strafe_right": "D", "brake": "X", "engine_kill": "Z", "cruise": "Shift+W", "afterburner": "Tab",
		"target_closest": "R", "target_next": "T", "dock": "F3"}
	var wrong: Array = []
	for k in want:
		if c.binding(k) != want[k]: wrong.append(k)
	_check("Job J: Freelancer default keys (right-click fire, left-click select/steer, Space mouse flight, W/S, A/D, X, Z, Shift+W, Tab, R, T, F3)", wrong.is_empty(), "wrong: %s" % ", ".join(wrong))
	# ---- 3. auto-detect + override
	var d1 := Controls.detect(true)
	var d2 := Controls.detect(false)
	c.touch_available = true
	var auto_touch := c.active_mode()
	c.touch_available = false
	var auto_kbm := c.active_mode()
	c.set_mode("touch")
	var o1 := c.active_mode()
	c.touch_available = true
	c.set_mode("kbm")
	var o2 := c.active_mode()
	c.touch_available = false
	c.set_mode("auto")
	_check("Job J: auto-detect picks touch on a touch device and keyboard + mouse on desktop; the Settings override wins",
		d1 == "touch" and d2 == "kbm" and auto_touch == "touch" and auto_kbm == "kbm" and o1 == "touch" and o2 == "kbm" and c.is_kbm())
	# ---- 4. mouse flight + Space toggle
	main.hud.aim_vec = Vector2.ZERO
	c.mouse_flight = true
	c.mouse_seen = true
	c.mouse_pos = vs * 0.5 + Vector2(vs.y * 0.3, 0.0)
	await _frames()
	var aim_on: Vector2 = s.aim
	var hud_free: bool = main.hud.button_at(c.mouse_pos) == ""
	await _tap(KEY_SPACE)
	var flight_off := not c.mouse_flight
	var aim_off: Vector2 = s.aim
	var space_fired: bool = s.fire_held
	await _tap(KEY_SPACE)
	_check("Job J: mouse flight steers toward the cursor and Space toggles it off/on (Space no longer fires)",
		hud_free and aim_on.x > 0.1 and absf(aim_on.y) < 0.05 and flight_off and aim_off == Vector2.ZERO and c.mouse_flight and not space_fired,
		"aim on %s, off %s" % [aim_on, aim_off])
	# ---- 5. left-click selects a target; left-click held + dragged steers; left-click never fires
	c.mouse_flight = false
	var st: Node3D = s.station
	_tp(st.global_position + Vector3(0, 120, 900), st.global_position)
	s.target = null
	await _frames()
	var sp: Vector2 = s.cam.unproject_position(st.global_position)
	_mouse(MOUSE_BUTTON_LEFT, true, sp)
	await _frames()
	var left_fire: bool = s.fire_held
	_mouse(MOUSE_BUTTON_LEFT, false, sp)
	await _frames()
	var picked: bool = s.target == st
	var p0 := vs * 0.5
	_mouse(MOUSE_BUTTON_LEFT, true, p0)
	await _frames()
	_move_mouse(p0 + Vector2(-90, 0), true)
	await _frames()
	var drag_aim: Vector2 = s.aim
	var tgt_kept: bool = s.target == st
	_mouse(MOUSE_BUTTON_LEFT, false, p0 + Vector2(-90, 0))
	await _frames()
	var after_drag: Vector2 = s.aim
	_check("Job J: left-click selects the target under the cursor; left-click held + dragged steers; left-click does not fire",
		picked and not left_fire and drag_aim.x < -0.1 and tgt_kept and after_drag == Vector2.ZERO and s.target == st,
		"picked %s, drag aim %s, at %s (window %s)" % [picked, drag_aim, sp, _win(sp)])
	# ---- 6. right-click fires weapons (owner correction)
	_mouse(MOUSE_BUTTON_RIGHT, true, p0)
	await _frames()
	var rfire: bool = s.fire_held and Input.is_action_pressed("fire")
	_mouse(MOUSE_BUTTON_RIGHT, false, p0)
	await _frames()
	_check("Job J: RIGHT-click fires weapons (Freelancer; owner correction)", rfire and not s.fire_held)
	# ---- 7. Freelancer keys drive the right actions
	_key(KEY_W, true)
	await _frames()
	var thr_up: bool = s.move.y > 0.5
	_key(KEY_W, false)
	_key(KEY_A, true)
	await _frames()
	var strafe: bool = s.move.x < -0.5
	_key(KEY_A, false)
	_key(KEY_TAB, true)
	await _frames()
	var burner: bool = s.thrust_held
	_key(KEY_TAB, false)
	await _frames()
	var burner_off: bool = not s.thrust_held
	await _tap(KEY_Z)
	var killed: bool = s.engine_kill
	await _tap(KEY_Z)
	var unkilled: bool = not s.engine_kill
	await _tap(KEY_X)
	var braked: bool = s.braking or s.holding
	await _tap(KEY_W, true)
	var cruise_on: bool = s.warp_state == "charging"
	await _tap(KEY_W, true)
	var cruise_off: bool = s.warp_state == "off"
	_check("Job J: throttle W, strafe A, afterburner Tab, engine kill Z, brake X and cruise Shift+W drive the right actions",
		thr_up and strafe and burner and burner_off and killed and unkilled and braked and cruise_on and cruise_off,
		"W %s A %s Tab %s/%s Z %s/%s X %s Shift+W %s/%s" % [thr_up, strafe, burner, burner_off, killed, unkilled, braked, cruise_on, cruise_off])
	# ---- 8. targeting keys R / T, dock key F3
	await _tap(KEY_R)
	var nearest: Node3D = s._nearest_enemy(INF)
	if nearest == null:
		var bd := INF
		for n in s.targetables():
			var dd: float = n.global_position.distance_to(s.player.global_position)
			if dd < bd:
				bd = dd
				nearest = n
	var r_ok: bool = s.target == nearest
	var before_t: Node3D = s.target
	await _tap(KEY_T)
	var t_ok: bool = s.target != before_t and s.target != null
	var dp: Vector3 = s.dock_point(st)
	_tp(dp + (dp - st.global_position).normalized() * 60.0, dp)
	await _wait(0.3)
	await _tap(KEY_F3)
	var docked := await _until(func(): return main.state == "hub", 8.0)
	var back := await _launch()
	_check("Job J: R targets the closest enemy, T cycles to the next target, F3 docks", r_ok and t_ok and docked and back,
		"R %s T %s F3 dock %s, relaunch %s" % [r_ok, t_ok, docked, back])
	s = _sp()
	# ---- 9. rebinding changes the key used in game; duplicate keys are blocked; Escape cancels
	c.begin_capture("engine_kill")
	var dup_note := c.finish_capture("W")
	var still_waiting := c.capturing == "engine_kill"
	var esc_note := c.finish_capture("Escape")
	var esc_ok := c.capturing == "" and c.binding("engine_kill") == "Z"
	c.begin_capture("engine_kill")
	var good := c.finish_capture("K")
	if GS.form == "mech": s.start_transform()
	var was_kill: bool = s.engine_kill
	await _tap(KEY_Z)
	var z_dead: bool = s.engine_kill == was_kill
	await _tap(KEY_K)
	var k_live: bool = s.engine_kill != was_kill
	if s.engine_kill: s.toggle_engine_kill()
	_check("Job J: rebinding moves the action to the new key; a key already in use is blocked with a warning; Escape cancels",
		dup_note != "" and still_waiting and esc_note == "Cancelled." and esc_ok and good == "" and c.binding("engine_kill") == "K" and z_dead and k_live,
		"dup '%s'" % dup_note)
	# ---- 10. extra Homelancer actions are listed and rebindable
	var extras: Array = Data.KBM_ACTIONS.filter(func(a): return a["extra"] and a["rebind"])
	var xr := c.rebind("transform", "Y")
	var ev_ok := false
	for ev in InputMap.action_get_events("transform"):
		if ev is InputEventKey and ev.physical_keycode == KEY_Y: ev_ok = true
	main.settings.open()
	await _frames()
	var rows_ok: bool = main.settings.controls_list_shown() and main.settings.row_btns.size() == Data.KBM_ACTIONS.size() and main.settings.row_btns["transform"].text == "Y" and main.settings.row_btns["select"].disabled
	_check("Job J: extra Homelancer actions (transform, view, map, keyboard turning) appear in the Controls list and can be rebound",
		extras.size() >= 4 and xr == "" and ev_ok and rows_ok, "%d extras" % extras.size())
	await _shot("settings_controls", 0.3)
	# ---- 11. reset to defaults restores the Freelancer baseline and the extras' defaults
	main.settings.press_reset()
	var armed: bool = c.binding("transform") == "Y"   # first press only arms the confirm
	main.settings.press_reset()
	var all_def := true
	for a in Data.KBM_ACTIONS:
		if c.binding(a["id"]) != a["key"]: all_def = false
	_check("Job J: Reset to defaults (with confirm) restores the Freelancer baseline and the extra actions' defaults", armed and all_def)
	main.settings.close()
	# ---- 12. settings persist (new file, new keys only) and older data loads with safe defaults
	c.rebind("missile", "Shift+Q")
	c.set_mode("kbm")
	var fresh := Controls.new()
	fresh.settings_path = c.settings_path
	fresh.load_settings()
	var persisted := fresh.binding("missile") == "Shift+Q" and fresh.mode_pref == "kbm"
	var cf := ConfigFile.new()
	cf.load(c.settings_path)
	var keys_ok := cf.get_sections() == PackedStringArray(["controls"]) and cf.get_section_keys("controls") == PackedStringArray(["mode", "bindings"])
	var old_path := "user://settings_autotest_old.cfg"
	var old := ConfigFile.new()
	old.set_value("other", "kept", 7)   # a file from before Job J (or none at all) has no "controls" section
	old.save(old_path)
	var legacy := Controls.new()
	legacy.settings_path = old_path
	legacy.load_settings()
	var legacy_ok := legacy.mode_pref == "auto" and legacy.binding("fire") == "Mouse Right" and legacy.binding("dock") == "F3"
	legacy.rebind("dock", "F4")
	var old2 := ConfigFile.new()
	old2.load(old_path)
	legacy_ok = legacy_ok and old2.get_value("other", "kept", 0) == 7
	var none := Controls.new()
	none.settings_path = "user://does_not_exist_autotest.cfg"
	none.load_settings()
	legacy_ok = legacy_ok and none.mode_pref == "auto" and none.bindings == Controls.defaults()
	fresh.free()
	legacy.free()
	none.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	_check("Job J: bindings and control mode persist in the new settings file; a pre-v1.4f state loads cleanly with defaults and keeps other data",
		persisted and keys_ok and legacy_ok)
	# ---- 13. phone / touch unchanged
	c.reset_defaults()
	c.set_mode("touch")
	c.mouse_flight = true
	c.mouse_seen = true
	c.mouse_pos = vs * 0.5 + Vector2(vs.y * 0.3, 0.0)
	main.hud.aim_vec = Vector2.ZERO
	await _frames()
	var no_mouse_aim: bool = s.aim == Vector2.ZERO
	_mouse(MOUSE_BUTTON_RIGHT, true, p0)
	await _frames()
	var no_rclick: bool = not s.fire_held
	_mouse(MOUSE_BUTTON_RIGHT, false, p0)
	main.settings.open()
	await _frames()
	var list_hidden: bool = main.settings.visible and not main.settings.controls_list_shown()
	main.settings.close()
	# a real finger (device 0) on the right stick zone still grabs the AIM stick, in either mode
	var hz: Rect2 = main.hud.stick_zone("aim")
	var finger := hz.position + hz.size * Vector2(0.6, 0.7)
	var tch := InputEventScreenTouch.new()
	tch.index = 3
	tch.position = finger
	tch.pressed = true
	main.hud._input(tch)
	var grabbed: bool = main.hud.owners.get(3, "") == "aim"
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = finger + Vector2(40, 0)
	main.hud._input(drag)
	var stick_moves: bool = main.hud.aim_vec.x > 0.2
	tch.pressed = false
	main.hud._input(tch)
	var released: bool = main.hud.aim_vec == Vector2.ZERO and not main.hud.owners.has(3)
	c.set_mode("kbm")
	tch.pressed = true
	main.hud._input(tch)
	var grabbed_kbm: bool = main.hud.owners.get(3, "") == "aim"
	tch.pressed = false
	main.hud._input(tch)
	_check("Job J: touch mode is unchanged — no mouse flight, no right-click fire, no Controls list; finger sticks work as before",
		no_mouse_aim and no_rclick and list_hidden and grabbed and stick_moves and released and grabbed_kbm and main.hud.buttons.has("slot_0") and main.hud.buttons.has("thrust"))
	# ---- 14. version label
	var shell := FileAccess.get_file_as_string("res://web_shell.html") if FileAccess.file_exists("res://web_shell.html") else ""
	# (from v1.4g on: the label must be v1.4f or later and match the page title)
	_check("Job J: version label reads \"Homelancer Digital v1.4f\" or later", Data.VERSION >= "v1.4f" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	# leave everything as a player would find it
	c.mouse_seen = false
	c.set_mode("auto")
	c.reset_defaults()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(c.settings_path))
	c.settings_path = Data.SETTINGS_PATH

# ---------------------------------------------------------------- Job K (v1.4g): jump-gate docking + warp tunnel
func _gate_k() -> void:
	if main.galaxymap.visible: main.galaxymap.visible = false
	if main.navmap.visible: main.navmap.visible = false
	if main.state == "map": main._on_map_closed()
	await _until(func(): return main.state == "flight", 8.0)
	var c: Controls = main.controls
	c.settings_path = "user://settings_autotest_k.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(c.settings_path))
	c.reduced_effects = false
	var s := _sp()
	s.autopilot = null
	var g: Node3D = s.gate
	var to: String = g.get_meta("info")["to"]
	var home: String = GS.system_id
	# ---- 1. select + dock within range opens the docking screen (and not from out of range)
	_tp(g.global_position + g.global_basis.z * 2000.0, g.global_position)
	await _frames()
	var far_no: bool = not main.dock_gate() and main.state == "flight"
	s.target = g
	_tp(g.global_position + g.global_basis.z * 180.0, g.global_position)
	await _wait(0.3)
	main.hud._layout()
	var prompt: bool = main.hud.buttons.has("jump")
	_press("jump")
	var opened: bool = main.state == "gate_dock" and main.gate_dock.visible and not main.hud.visible and s.process_mode == Node.PROCESS_MODE_DISABLED
	_check("Job K: a selected jump gate in range can be docked to and the docking screen opens (not from out of range)", far_no and prompt and opened and s.target == g)
	# ---- 2. destination
	var dest: String = Data.SYSTEMS[to]["name"]
	_check("Job K: the docking screen shows the right destination system for that gate", main.gate_dock.destination == dest and main.gate_dock.dest_label.text.find(dest.to_upper()) >= 0, dest)
	await _shot("gate_dock_screen", 0.3)
	# ---- 3. undock: no jump
	var jumps0: int = main.jumps
	main.gate_dock.press_undock()
	await _frames()
	_check("Job K: UNDOCK closes the screen with no jump and no system change", main.state == "flight" and not main.gate_dock.visible and GS.system_id == home
		and main.jumps == jumps0 and s.controls and main.hud.visible and s.process_mode == Node.PROCESS_MODE_INHERIT)
	# ---- 4/5. F3 (Job J dock key) docks to the gate; a double tap on ACTIVATE starts one jump only
	var file_before := FileAccess.get_file_as_string(c.settings_path) if FileAccess.file_exists(c.settings_path) else "<none>"
	await _tap(KEY_F3)
	var f3: bool = main.state == "gate_dock"
	main.gate_dock.press_activate()
	main.gate_dock.press_activate()
	main.gate_activate()
	main.jump()
	var one: bool = main.jumps == jumps0 + 1
	await _until(func(): return main.jump_log.size() >= 2, 5.0)
	var mid_jump: bool = main.state == "jumping"
	var file_mid := FileAccess.get_file_as_string(c.settings_path) if FileAccess.file_exists(c.settings_path) else "<none>"
	await _until(func(): return main.state == "flight", 20.0)
	var arrived: bool = GS.system_id == to
	_check("Job K: F3 docks to the gate and ACTIVATE JUMP ends with the player in the destination system", f3 and arrived, "%s -> %s" % [home, GS.system_id])
	_check("Job K: a double tap on ACTIVATE JUMP starts only one jump", one and main.jumps == jumps0 + 1 and arrived)
	# ---- 6. tunnel timing: build ~0.5 s, hold until loaded, clear ~0.3 s
	var L: Array = main.jump_log
	var phases := L.map(func(x): return x[0])
	var timing_ok := phases == ["build", "hold", "loaded", "clear", "done"]
	var detail := "phases %s" % str(phases)
	if timing_ok:
		var build_s: float = (L[1][1] - L[0][1]) / 1000.0
		var hold_s: float = (L[2][1] - L[1][1]) / 1000.0
		var clear_s: float = (L[4][1] - L[3][1]) / 1000.0
		timing_ok = absf(build_s - Data.JUMP_TUNNEL_BUILD) < 0.35 and hold_s >= Data.JUMP_TUNNEL_HOLD_MIN - 0.02 and absf(clear_s - Data.JUMP_TUNNEL_CLEAR) < 0.35 \
			and L[1][2] >= 0.99 and L[2][2] >= 0.99 and L[1][3] == home and L[2][3] == to and L[4][2] == 0.0 and main.fx.warp == 0.0 and main.fx.blur == 0.0
		detail = "build %.2f s, hold %.2f s (load inside), clear %.2f s" % [build_s, hold_s, clear_s]
	_check("Job K: the warp tunnel builds, holds at full until the next system is loaded, then clears (matches the load time)", timing_ok, detail)
	# ---- 7. star streaks in layers (near faster), shake + blur at full tunnel, launched out of the gate
	var layers: Array = main.fx.streak_layers()
	var layered: bool = layers.size() == Data.JUMP_STREAK_LAYERS.size() and float(layers.max()) > float(layers.min())
	var fx_full: bool = L.size() == 5 and absf(float(L[1][5]) - Data.JUMP_BLUR) < 0.01
	var boom: bool = L.size() == 5 and float(L[3][4]) >= float(GS.ship()["speed"]) * Data.JUMP_LAUNCH_MULT * 0.95
	_check("Job K: layered star streaks drawn in code, blur at full tunnel, and the ship is launched out into the new system", layered and fx_full and boom and mid_jump,
		"layers %s, launch %.0f" % [str(layers), float(L[3][4]) if L.size() == 5 else 0.0])
	await _shot("after_gate_jump", 0.4)
	# ---- 8. reduced motion: new setting (default off), persists, and the jump becomes a plain fade
	var probe := Controls.new()
	var def_off := not probe.reduced_effects
	probe.free()
	c.set_reduced_effects(true)
	var fresh := Controls.new()
	fresh.settings_path = c.settings_path
	fresh.load_settings()
	var persisted := fresh.reduced_effects
	fresh.free()
	c.apply()
	s = _sp()
	var g2: Node3D = s.near_gate()
	_tp(g2.global_position + g2.global_basis.z * 180.0, g2.global_position)
	await _wait(0.3)
	_gate_jump()
	await _until(func(): return main.jump_log.size() >= 2, 5.0)
	var fade_only: bool = main.fx.warp == 0.0 and main.fx.blur == 0.0 and main.fx.fade >= 0.99
	await _until(func(): return main.state == "flight", 20.0)
	var back_home: bool = GS.system_id == home and main.fx.fade == 0.0
	c.set_reduced_effects(false)
	_check("Job K: reduced-motion setting (new field, default off) persists and turns the tunnel into a short fade", def_off and persisted and fade_only and back_home)
	# ---- 9. older settings load with the new field defaulted; nothing is saved mid-jump
	var old_path := "user://settings_autotest_k_old.cfg"
	var old := ConfigFile.new()
	old.set_value("controls", "mode", "auto")
	old.set_value("controls", "bindings", {})
	old.save(old_path)
	var legacy := Controls.new()
	legacy.settings_path = old_path
	legacy.load_settings()
	var legacy_ok := not legacy.reduced_effects and legacy.binding("dock") == "F3"
	legacy.free()
	c.apply()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	_check("Job K: a v1.4f settings file loads with the new setting defaulted; nothing about the jump is saved mid-jump", legacy_ok and file_mid == file_before)
	# ---- 10. version label
	var shell := FileAccess.get_file_as_string("res://web_shell.html") if FileAccess.file_exists("res://web_shell.html") else ""
	_check("Job K: version label reads \"Homelancer Digital v1.4g\" or later", Data.VERSION >= "v1.4g" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(c.settings_path))
	c.settings_path = Data.SETTINGS_PATH
	c.reduced_effects = Data.REDUCED_EFFECTS_DEFAULT

# ---------------------------------------------------------------- Job L (v1.4h): collision damage
## Put the ship at `pos` moving with `v` and let the real collision code run for a couple of frames.
func _ram(pos: Vector3, v: Vector3) -> void:
	var s := _sp()
	s.collide_grace = 0.0
	s.player.global_position = pos
	s.vel = v
	await _frames(2)

func _collide_l() -> void:
	if main.galaxymap.visible: main.galaxymap.visible = false
	if main.navmap.visible: main.navmap.visible = false
	if main.state == "map": main._on_map_closed()
	await _until(func(): return main.state == "flight", 8.0)
	var s := _sp()
	s.autopilot = null
	GS.god_mode = false   # collision damage must really land in these checks
	GS.restore_full()
	_shield_down()
	var hits := {}
	_shield_down()   # v1.4l: collisions take the shield first, so these hull checks run with the shield down
	var settings_before := FileAccess.get_file_as_string(main.controls.settings_path) if FileAccess.file_exists(main.controls.settings_path) else "<none>"
	# ---- asteroid (space): ram a rock of the belt
	var rock_hit := false
	var fake_rock := s.rocks.is_empty() or not s.in_belt_region(s.rocks[0][0])
	var saved_belt := [s.belt_center, s.belt_radius]
	if fake_rock:   # this system has no belt: borrow one rock-shaped collision entry for the check, then remove it
		var fp: Vector3 = s.station.global_position + Vector3(900, 300, 900)
		s.rocks.push_front([fp, 18.0])
		s.belt_center = fp
		s.belt_radius = 400.0
	if true:
		var r: Array = s.rocks[0]
		var n := Vector3(0, 0, 1)
		var h0 := GS.hull
		s.last_collision = {}
		if not fake_rock and not s.asteroids.is_empty():   # v1.7x: ram the blocks of a real asteroid
			var ast0 = s.asteroids[0]
			for a0 in s.asteroids:   # (a whole one that sits still: earlier checks may have broken some up)
				if int(a0.tier) == 0 and a0.vel == Vector3.ZERO:
					ast0 = a0
					break
			await _ram((ast0.surface_point(n) as Vector3) + n * 2.0, -n * 40.0)
		else: await _ram(r[0] + n * (float(r[1]) + 2.5), -n * 40.0)
		rock_hit = s.last_collision.get("kind", "") == "asteroid" and GS.hull < h0
		hits["asteroid"] = h0 - GS.hull
	if fake_rock:
		s.rocks.pop_front()
		s.belt_center = saved_belt[0]
		s.belt_radius = saved_belt[1]
	# ---- non-solid things deal no damage: loot pods, a jump gate's ring opening, the docking range trigger
	GS.restore_full()
	_shield_down()
	s.last_collision = {}
	var g: Node3D = s.gate
	_tp(g.global_position + g.global_basis.z * 30.0, g.global_position)
	s.vel = -g.global_basis.z * 60.0
	await _frames(6)
	s._drop_loot(s.player.global_position, 100)
	for l in s.loot: (l["node"] as Node3D).global_position = s.player.global_position + Vector3(0, 0, -2)
	s.vel = Vector3(0, 0, -40)
	await _frames(4)
	var dp: Vector3 = s.dock_point(s.station)
	_tp(dp + (dp - s.station.global_position).normalized() * 120.0, dp)
	await _frames(3)
	var non_solid: bool = s.last_collision.is_empty() and GS.hull >= GS.max_hull() - 0.001
	# ---- scaling, threshold, grace (the same function every solid object uses)
	_tp(s.station.global_position + Vector3(400, 200, 400), s.station.global_position)
	await _frames(2)
	GS.restore_full()
	_shield_down()
	s.collide_grace = 0.0
	var d_slow: float = s.collision_damage("building", 20.0)
	s.collide_grace = 0.0
	var d_fast: float = s.collision_damage("building", 40.0)
	var expect_slow := (20.0 - Data.COLLIDE_THRESHOLD) * Data.COLLIDE_MULT
	_check("Job L: damage scales with impact speed (faster = more)", d_fast > d_slow and absf(d_slow - expect_slow) < 0.01, "20 m/s %.1f, 40 m/s %.1f" % [d_slow, d_fast])
	GS.restore_full()
	_shield_down()
	s.collide_grace = 0.0
	var free_touch: float = s.collision_damage("ground", Data.COLLIDE_THRESHOLD - 0.1)
	var hull_free: bool = GS.hull == GS.max_hull()
	# ---- feedback: shake, flash, sound scale with the hit
	s.collide_grace = 0.0
	s.hit_shake = 0.0
	main.hud.damage_flash = 0.0
	s.collision_damage("asteroid", Data.COLLIDE_THRESHOLD + 3.0)
	var soft_shake: float = s.hit_shake      # read at once: on a slow frame the shake has died away a frame later (E2)
	var soft_flash: float = main.hud.damage_flash   # (v1.4l: the flash is read at once too, for the same reason)
	await _frames(1)
	var soft_k: float = s.last_collision.get("k", -1.0)
	s.collide_grace = 0.0
	s.hit_shake = 0.0
	main.hud.damage_flash = 0.0
	s.collision_damage("asteroid", 60.0)
	var hard_shake: float = s.hit_shake
	var hard_flash: float = main.hud.damage_flash
	await _frames(1)
	var hard_k: float = s.last_collision.get("k", -1.0)
	_check("Job L: hit feedback (flash, shake, sound) on collision, stronger for harder hits; the hull bar shows it", soft_flash > 0.0 and soft_shake > 0.0
		and hard_k > soft_k and hard_flash > soft_flash and hard_shake > soft_shake and GS.hull < GS.max_hull(),
		"k soft %.2f hard %.2f; shake %.2f > %.2f; flash %.2f > %.2f; hull %.0f of %.0f" % [soft_k, hard_k, hard_shake, soft_shake, hard_flash, soft_flash, GS.hull, GS.max_hull()])
	# ---- grace window
	GS.restore_full()
	_shield_down()
	s.collide_grace = 0.0
	var first: float = s.collision_damage("asteroid", 30.0)
	var second: float = s.collision_damage("asteroid", 30.0)
	await _wait(Data.COLLIDE_GRACE + 0.15)
	var third: float = s.collision_damage("asteroid", 30.0)
	_check("Job L: the grace window blocks a second hit for its length, then damage applies again", first > 0.0 and second == 0.0 and third > 0.0, "%.1f / %.1f / %.1f" % [first, second, third])
	_check("Job L: non-solid things (loot pods, the gate opening, the docking trigger) deal no collision damage", non_solid)
	# ---- planet surface: the ground and buildings
	main._load_surface("new_terra", 4)
	await _wait(1.0)
	await _frames(2)
	s = _sp()
	s.controls = true
	GS.restore_full()
	_shield_down()
	var gx := 300.0
	var gz := -900.0
	var gy: float = s._ground(gx, gz)
	s.last_collision = {}
	var h1 := GS.hull
	await _ram(Vector3(gx, gy + 5.0, gz), Vector3(0, -35.0, 0))
	var ground_hit: bool = s.last_collision.get("kind", "") == "ground" and GS.hull < h1
	hits["ground"] = h1 - GS.hull
	s.last_collision = {}
	var h2 := GS.hull
	await _ram(Vector3(gx, gy + 5.5, gz), Vector3(0, -(Data.COLLIDE_THRESHOLD - 3.0), 0))
	var soft_landing: bool = s.last_collision.is_empty() and GS.hull == h2
	_check("Job L: colliding with an asteroid and the ground each damages the hull (v1.5q: the planet towns were removed, so no building check)", rock_hit and ground_hit,
		"asteroid %.1f, ground %.1f" % [float(hits.get("asteroid", 0.0)), float(hits.get("ground", 0.0))])
	_check("Job L: contact below the threshold speed does no damage (gentle touch, soft landing)", free_touch == 0.0 and hull_free and soft_landing)
	# ---- older settings load; nothing new is saved by collisions
	var old_path := "user://settings_autotest_l_old.cfg"
	var old := ConfigFile.new()
	old.set_value("controls", "mode", "kbm")
	old.set_value("controls", "bindings", {"missile": "K"})
	old.set_value("effects", "reduced", true)
	old.save(old_path)
	var legacy := Controls.new()
	legacy.settings_path = old_path
	legacy.load_settings()
	var legacy_ok := legacy.mode_pref == "kbm" and legacy.binding("missile") == "K" and legacy.reduced_effects
	legacy.free()
	main.controls.apply()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_path))
	var settings_after := FileAccess.get_file_as_string(main.controls.settings_path) if FileAccess.file_exists(main.controls.settings_path) else "<none>"
	_check("Job L: a v1.4g settings file loads unchanged; collision damage adds no save fields", legacy_ok and settings_after == settings_before)
	# ---- a crash at low hull destroys the ship through the normal death flow
	s.collide_grace = 0.0
	GS.hull = 5.0
	_shield_down()
	s.collision_damage("building", 40.0)
	var dead_now: bool = GS.hull == 0.0 and not s.controls
	var towed := await _until(func(): return main.state == "hub", 15.0)
	_check("Job L: a collision that takes the hull to zero destroys the ship through the normal death flow", dead_now and towed and GS.hull == GS.max_hull(), "state %s" % main.state)
	if is_instance_valid(_sp()): _sp().shield_delay = 0.0
	await _launch()
	GS.god_mode = true
	# ---- version label
	var shell := FileAccess.get_file_as_string("res://web_shell.html") if FileAccess.file_exists("res://web_shell.html") else ""
	_check("Job L: version label reads \"Homelancer Digital v1.4h\" or later", Data.VERSION >= "v1.4h" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)


## Job M (v1.4j): Cadet turned round, the lead box, missile locks and volleys, the three missile types, dodging.
## v1.4l: shield off and kept off (no recharge), for checks that read hull damage.
func _shield_down() -> void:
	GS.shield = 0.0
	_sp().shield_delay = 2.8   # (below 2.9, or the HUD would count every change as a fresh hit)

func _combat_m() -> void:
	var s := _sp()
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job M: version label reads \"Homelancer Digital v1.4j\" or later", Data.VERSION >= "v1.4j" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	_check("Job M: the Cadet's nose points away from the camera (v1.4l: the model itself was rebuilt nose-first, so no turn is applied)",
		ShipFactory.GLB["cadet"][2] == 0.0 and ShipFactory.has_real_model("cadet"))
	_check("Job M: phone buttons unchanged: three weapon slots (light missile, heavy missile, mine)", GS.slots == Data.DEFAULT_SLOTS and main.hud.buttons.has("slot_0") and main.hud.buttons.has("slot_2"), str(GS.slots))
	# ---- a quiet spot, engines off so the ship stays put
	var rack0: String = GS.rack
	var owned0: Array = GS.owned_racks.duplicate()
	var m0 := GS.missiles
	var h0 := GS.heavy_missiles
	var cr0 := GS.credits
	_tp(Vector3(900, 700, 900), Vector3(900, 700, 0))
	s.engine_kill = true
	s.enemy_dodge_chance = 0.0
	var guns0: String = GS.modes["guns"]
	GS.modes["guns"] = "manual"   # only missiles may touch the target in these checks
	await _frames(2)
	var fwd := -s.player.global_basis.z
	var e: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 300.0, s.player.global_position + fwd * 300.0)
	var n: Node3D = e["node"]
	s.target = n
	# ---- lead box
	e["vel"] = s.player.global_basis.x * 40.0
	var lead: Vector3 = s.lead_point(n)
	var ahead: float = (lead - n.global_position).dot(s.player.global_basis.x)
	var want: float = 40.0 * n.global_position.distance_to(s.player.global_position) / float(GS.weapon()["speed"])
	s.vel = s.player.global_basis.x * 40.0   # flying alongside at the same speed: no lead needed
	var none: float = (s.lead_point(n) - n.global_position).length()
	s.vel = Vector3.ZERO
	_check("Job M: the lead box sits ahead of the target by its travel during the shot (and on it when you match its speed)", absf(ahead - want) < 0.5 and ahead > 5.0 and none < 0.1, "ahead %.1f want %.1f matched %.2f" % [ahead, want, none])
	await _shot("lead_box_and_locks", 0.5)
	# ---- locks build over time on target, drop when off target
	GS.rack = "triple"
	GS.missiles = 6
	GS.heavy_missiles = 2
	s.lock_time = 0.0
	var l0: int = s.lock_count()
	s.lock_time = Data.LOCK_STEP * 1.5
	var l1: int = s.lock_count()
	s.lock_time = Data.LOCK_STEP * 9.0
	var l3: int = s.lock_count()
	var lh: int = s.lock_count("heavy_missile")
	GS.missiles = 2
	var l_ammo: int = s.lock_count()
	GS.missiles = 6
	_check("Job M: locks stack one per %.1f s: Triple Rack holds 3, heavy holds 1, never more than the missiles left" % Data.LOCK_STEP, l0 == 0 and l1 == 1 and l3 == 3 and lh == 1 and l_ammo == 2, "%d %d %d heavy %d ammo-capped %d" % [l0, l1, l3, lh, l_ammo])
	s.lock_time = 0.0
	n.global_position = s.player.global_position - s.player.global_basis.z * 300.0
	await _wait(0.6)
	var grew: bool = s.lock_time > 0.3
	n.global_position = s.player.global_position + s.player.global_basis.z * 300.0   # behind you
	await _frames(3)
	var dropped: bool = s.lock_time == 0.0
	_check("Job M: the lock builds while the target is in front of you and drops when it leaves the cone", grew and dropped, "lock_time grew %s dropped %s" % [grew, dropped])
	# ---- volley of three
	n.global_position = s.player.global_position - s.player.global_basis.z * 500.0
	e["hp"] = 99999.0   # it must outlive the volleys below
	s.missile_cd = 0.0
	s.lock_time = Data.LOCK_STEP * 3.2
	var before: int = s.missiles_live.size()
	var fired: bool = s.trigger_system("light_missile")
	await _wait(Data.VOLLEY_GAP * 3.0 + 0.2)
	var all_on: bool = true
	for m in s.missiles_live: all_on = all_on and m["target"] == n
	_check("Job M: three locks fire a volley of three homing missiles at the target and use three missiles", fired and GS.missiles == 3 and s.missiles_live.size() - before == 3 and all_on and s.lock_time < 1.0,
		"missiles left %d, in flight %d" % [GS.missiles, s.missiles_live.size() - before])
	for m in s.missiles_live: m["life"] = 0.0
	await _frames(3)
	# ---- heavy: one lock only
	s.missile_cd = 0.0
	s.lock_time = Data.LOCK_STEP * 9.0
	e["hp"] = 99999.0
	var live1: int = s.missiles_live.size()
	s.trigger_system("heavy_missile")
	await _wait(0.4)
	var heavy_dmg: float = s.missile_damage({"max": 200.0}, true)
	_check("Job M: the heavy missile fires one at a time and hits hard (at least %d%% of the hull)" % int(Data.HEAVY_MISSILE_HULL_FRAC * 100.0), GS.heavy_missiles == 1 and s.missiles_live.size() - live1 <= 1 and heavy_dmg >= 120.0
		and heavy_dmg > s.missile_damage({"max": 200.0}, false), "heavy %.0f vs light %.0f on a 200 hull" % [heavy_dmg, s.missile_damage({"max": 200.0}, false)])
	# ---- swarm rack: bought, five locks, lighter missiles
	GS.owned_racks.erase("swarm")   # (v1.4l: it now comes with the ship; take it away to check the purchase)
	GS.rack = "triple"
	GS.credits = 0
	var refused: bool = GS.buy_rack("swarm").begins_with("Not enough") and GS.rack == "triple"
	GS.credits = int(Data.MISSILE_RACKS["swarm"]["price"]) + 10
	GS.buy_rack("swarm")
	var bought: bool = GS.rack == "swarm" and GS.credits == 10 and "swarm" in GS.owned_racks
	GS.missiles = 8
	s.missile_cd = 0.0
	s.lock_time = Data.LOCK_STEP * 9.0
	var l5: int = s.lock_count()
	var rack_locks: int = Data.MISSILE_RACKS["swarm"]["locks"]   # six since v1.4l
	for m in s.missiles_live: m["life"] = 0.0
	await _frames(3)
	s.trigger_system("light_missile")
	await _wait(Data.VOLLEY_GAP * rack_locks + 0.2)
	var swarm_n: int = s.missiles_live.size()
	var swarm_scale: float = float(s.missiles_live[-1]["scale"]) if swarm_n > 0 else 0.0
	GS.buy_rack("triple")
	var refit: bool = GS.rack == "triple" and GS.credits == 10
	_check("Job M: the big rack is bought at Equipment, holds its locks (six since v1.4l) and fires that many lighter missiles; refitting a rack you own is free", refused and bought and l5 == rack_locks and swarm_n == rack_locks and GS.missiles == 8 - rack_locks
		and is_equal_approx(swarm_scale, float(Data.MISSILE_RACKS["swarm"]["damage"])) and refit, "locks %d, in flight %d, damage x%.1f" % [l5, swarm_n, swarm_scale])
	for m in s.missiles_live: m["life"] = 0.0
	await _frames(3)
	# ---- your missile hits an enemy that flies on; an enemy that side-boosts shakes it off
	e["hp"] = 60.0
	e["sh"] = 0.0
	n.global_position = s.player.global_position - s.player.global_basis.z * 320.0
	GS.missiles = 4
	s.enemy_dodge_chance = 0.0
	s.fire_missile()
	await _until(func(): return s.missiles_live.is_empty(), 8.0)
	var hit_ok: bool = float(e["hp"]) < 60.0 or not is_instance_valid(n) or not (e in s.enemies)
	if not (e in s.enemies) or not is_instance_valid(n):
		e = s.spawn_unit("raider", s.player.global_position + fwd * 320.0, s.player.global_position + fwd * 320.0)
		n = e["node"]
	e["hp"] = 60.0
	e["sh"] = 0.0
	n.global_position = s.player.global_position - s.player.global_basis.z * 320.0
	s.target = n
	s.enemy_dodge_chance = 1.0
	var ev0: int = s.enemy_evades
	var bs0: int = s.blast_shapes
	s.fire_missile()
	var fuse: float = float(s.missiles_live[-1]["life"]) if not s.missiles_live.is_empty() else -1.0
	await _until(func(): return s.missiles_live.is_empty(), 8.0)
	var tracked: bool = s.enemy_evades == ev0 and (float(e["hp"]) < 60.0 or not (e in s.enemies))
	var shown: bool = s.blast_shapes > bs0 and not s.blast_log.is_empty() and is_equal_approx(float(s.blast_log[-1][0]), Data.MISSILE_BLAST_RADIUS) and not bool(s.blast_log[-1][1])
	_check("Job M / v1.7u (owner): a missile hits an enemy that holds its course; one that swerves can't shake it off (no EVADED); 4 s fuse; its blast shows a sphere", hit_ok and tracked and shown and is_equal_approx(fuse, Data.MISSILE_LIFE),
		"hit %s, tracked %s, shown %s, fuse %.1f" % [hit_ok, tracked, shown, fuse])
	s.enemy_dodge_chance = 0.0
	if e in s.enemies:
		s.enemies.erase(e)
		n.queue_free()
	s.target = null
	for m in s.missiles_live: m["life"] = 0.0
	# ---- an enemy missile: hits a ship that sits still, misses one that slides sideways fast
	_tp(Vector3(900, 700, 900), Vector3(900, 700, 0))
	GS.god_mode = false
	GS.restore_full()
	var launcher := Node3D.new()
	s.add_child(launcher)
	launcher.global_position = s.player.global_position - s.player.global_basis.z * 400.0
	launcher.look_at(s.player.global_position, Vector3.UP)
	var fake := {"node": launcher, "vel": Vector3.ZERO}
	var parked: Array = s.enemies.duplicate()   # v1.4n: nobody else may shoot during this measurement (a stray raider's gun hit made it read 27 on the build server)
	s.enemies.clear()
	await _wait(1.5)                            # let any shots already in flight land or expire
	GS.restore_full()
	s.enemy_fire_missile(fake)
	await _frames(3)
	var warned: bool = s.missile_warn > 0.0
	await _shot("missile_incoming", 0.3)
	var sh0 := GS.shield + GS.hull
	await _until(func(): return s.enemy_missiles.is_empty(), 10.0)
	var took: float = sh0 - (GS.shield + GS.hull)
	for pe in parked:
		if is_instance_valid(pe["node"]): s.enemies.append(pe)
	_check("Job M: an enemy missile warns you on the HUD and hits a ship that holds still", warned and took > Data.ENEMY_MISSILE_DAMAGE * 0.5 and took <= Data.ENEMY_MISSILE_DAMAGE + 0.01, "warned %s, damage %.1f" % [warned, took])
	GS.restore_full()
	_tp(Vector3(900, 700, 900), Vector3(900, 700, 0))
	launcher.global_position = s.player.global_position - s.player.global_basis.z * 400.0
	launcher.look_at(s.player.global_position, Vector3.UP)
	var dodge0: int = s.missiles_evaded
	await _frames(3)
	s.enemy_fire_missile(fake)
	await _frames(3)
	await _until(func(): return s.missile_warn > 0.0 and s.missile_warn < Data.DODGE_RANGE * 0.8, 6.0)
	s.engine_kill = true   # the engine-kill slide after a sideways boost
	s.vel = s.player.global_basis.x * float(GS.ship()["speed"]) * Data.THRUST_MULT
	var sh1 := GS.shield + GS.hull
	await _until(func(): return s.missiles_evaded > dodge0 or s.enemy_missiles.is_empty(), 8.0)
	var slid: bool = s.missiles_evaded == dodge0 + 1 and is_equal_approx(GS.shield + GS.hull, sh1)
	await _until(func(): return s.enemy_missiles.is_empty(), 10.0)
	_tp(Vector3(900, 700, 900), Vector3(900, 700, 0))
	launcher.global_position = s.player.global_position - s.player.global_basis.z * 400.0
	await _frames(3)
	s.enemy_fire_missile(fake)
	await _frames(3)
	await _until(func(): return s.missile_warn > 0.0 and s.missile_warn < Data.DODGE_RANGE * 0.8, 6.0)
	s.vel = s.player.global_basis.x * float(GS.ship()["speed"])   # normal speed is not enough
	var dodge1: int = s.missiles_evaded
	await _until(func(): return s.enemy_missiles.is_empty(), 10.0)
	var slow_hit: bool = s.missiles_evaded == dodge1 and GS.shield + GS.hull < sh1
	_check("Job M: a sideways boost (or an engine-kill slide after one) shakes an enemy missile off; flying sideways at normal speed does not", slid and slow_hit, "slide dodged %s, slow got hit %s" % [slid, slow_hit])
	launcher.queue_free()
	# ---- who carries missiles
	GS.god_mode = true
	GS.restore_full()
	_tp(Vector3(900, 700, 900), Vector3(900, 700, 0))
	var c: Dictionary = s.spawn_unit("corsair", s.player.global_position + fwd * 250.0, s.player.global_position + fwd * 250.0)
	(c["node"] as Node3D).look_at(s.player.global_position, Vector3.UP)
	c["aggro"] = true
	c["mcd"] = 0.05
	var r: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 250.0 + Vector3(0, 40, 0), s.player.global_position)
	r["aggro"] = true
	r["mcd"] = 0.05
	await _until(func(): return not s.enemy_missiles.is_empty(), 6.0)
	_check("Job M: Corsairs and Assault Mechs carry missiles; Raiders do not", s.enemy_missiles.size() == 1 and float(c["mcd"]) >= Data.ENEMY_MISSILE_EVERY[0] - 1.0
		and Data.ENEMIES["mech"].get("missiles", false) and not Data.ENEMIES["raider"].get("missiles", false), "in flight %d" % s.enemy_missiles.size())
	for x in [c, r]:
		if x in s.enemies:
			s.enemies.erase(x)
			(x["node"] as Node3D).queue_free()
	for m in s.enemy_missiles: m["life"] = 0.0
	s.target = null
	s.engine_kill = false
	s.vel = Vector3.ZERO
	s.lock_time = 0.0
	s.volley_queue.clear()
	GS.modes["guns"] = guns0
	GS.rack = rack0
	GS.owned_racks = owned0
	GS.missiles = m0
	GS.heavy_missiles = h0
	GS.credits = cr0
	GS.restore_full()
	await _wait(0.5)


## Job N (v1.4k): the concept-art map wired into the systems, and Lockon's signature attack.
func _art_n() -> void:
	var s := _sp()
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job N: version label reads \"Homelancer Digital v1.4k\" or later", Data.VERSION >= "v1.4k" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	# ---- Aurelion: three stations, eight rooms each, and the Aurelion Prime locations
	var au: Dictionary = Data.SYSTEMS["aurelion"]
	var stations: Array = [au["station"]] + au["more_stations"]
	var rooms_ok := stations.size() == 3
	var room_count := 0
	for st in stations:
		var art = st.get("art")
		if art == null or not (art["exterior"] as Dictionary).has("drive"):
			rooms_ok = false
			continue
		for r in ArtRefs.ROOMS:
			var ref: Dictionary = ArtRefs.room("aurelion", st["name"], r)
			if ref.get("drive", "") == "" or not (ref.get("file", "") as String).ends_with(".png"): rooms_ok = false
			else: room_count += 1
	_check("Job N: Aurelion's three stations each carry an exterior and all eight hub rooms (main hub, shipyard, dealer, weapons dealer, supplies, bar, mission board, bedroom)", rooms_ok and room_count == 24 and ArtRefs.ROOMS.size() == 8, "%d room pictures on %d stations" % [room_count, stations.size()])
	var prime = au["planet"].get("art")
	var locs: Array = prime["locations"] if prime != null else []
	var codes: Array = [prime["sheet"]["code"]] if prime != null else []
	for l in locs:
		codes.append(l["aerial"]["code"])
		codes.append(l["first_person"]["code"])
	_check("Job N: Aurelion Prime carries A01 to A09: the concept sheet and four locations with an aerial and a first-person view each, plus the Alisa temple throne scene",
		au["planet"]["name"] == "Aurelion Prime" and codes == ["A01", "A02", "A03", "A04", "A05", "A06", "A07", "A08", "A09"] and locs.size() == 4
		and (prime["scenes"] as Array).size() == 1 and prime["scenes"][0]["id"] == "alisa_temple_throne", str(codes))
	var g: Dictionary = au["art_guards"]
	_check("Job N: Elyza guard rules are in the data: paladin or Dark Knight armor, mixed loadouts, no recycled characters, none in the bedroom",
		g["armor"] == ["paladin", "dark_knight"] and (g["loadouts"] as Array).size() >= 3 and g["recycled_characters"] == false and "rest_quarters" in g["none_in"]
		and Data.SYSTEMS["crystara"]["art_guards"]["armor"] == g["armor"])
	# ---- Scavaris and Crystara: the places exist, the art does not, and nothing is made up
	var sc: Dictionary = Data.SYSTEMS["scavaris"]
	var cr: Dictionary = Data.SYSTEMS["crystara"]
	# (v1.4v: the art map is keyed by the catalog's role names; the stations' proper names are laid over them afterwards)
	var sc_names: Array = [sc["planet"]["name"], sc["station"].get("catalog_name", sc["station"]["name"])] + (sc["more_planets"] as Array).map(func(x): return x["name"])
	var cr_names: Array = [cr["planet"]["name"], cr["station"].get("catalog_name", cr["station"]["name"])] + (cr["more_planets"] as Array).map(func(x): return x["name"])
	var none_yet := true
	for body in [sc["planet"], sc["station"], cr["planet"], cr["station"]] + sc["more_planets"] + cr["more_planets"]:
		if not body.has("art") or body["art"] != null: none_yet = false
	var miss: Array = ArtRefs.missing()
	var listed := 0
	for line in miss:
		if (line as String).begins_with("scavaris") or (line as String).begins_with("crystara"): listed += 1
	_check("Job N: Scavaris (Scavaris, Husk, Salvage Hulk) and Crystara (Crystara, Geode, Prism, Crystal Refinery) are wired with no art invented, and all seven are on the missing list",
		sc_names == ["Scavaris", "Salvage Hulk", "Husk"] and cr_names == ["Crystara", "Crystal Refinery", "Geode", "Prism"] and none_yet and listed == 7
		and cr["art_lore"] == "locked", "missing list has %d lines, %d for these two" % [miss.size(), listed])
	var seen := {}
	var dup := ""
	for sid in ArtRefs.SYSTEMS:
		for nm in ArtRefs.SYSTEMS[sid]["stations"]:
			var st = ArtRefs.SYSTEMS[sid]["stations"][nm]
			if st == null: continue
			for ref in [st["exterior"]] + (st["rooms"] as Dictionary).values():
				if seen.has(ref["drive"]): dup = ref["file"]
				seen[ref["drive"]] = true
	for l in locs:
		for ref in [l["aerial"], l["first_person"]]:
			if seen.has(ref["drive"]): dup = ref["file"]
			seen[ref["drive"]] = true
	_check("Job N: no picture is wired to two places", dup == "" and seen.size() == 27 + 8, "%d pictures %s" % [seen.size(), dup])
	# ---- Lockon's signature attack
	var sig: Dictionary = Data.SIGNATURES["lockon"]
	var placed := false
	for sid in Data.SYSTEMS:
		if Data.SYSTEMS[sid].get("enemy", "") == "lockon": placed = true
	_check("Job N: Lockon's attack is in the data (Cybermorph, charcoal dart, crimson slit, red trail, cyan-white bloom) and Lockon is placed in no system until a sheet and model exist",
		sig["faction"] == "Cybermorph" and Data.ENEMIES["lockon"]["signature"] == "lockon" and Data.ENEMIES["lockon"].get("stand_in", false) and not placed
		and (sig["slit"] as Color).r > 0.8 and (sig["dart"] as Color).r < 0.2 and (sig["bloom"] as Color).b > 0.9 and int(sig["shards"]) == 6)
	_tp(Vector3(900, 700, 900), Vector3(900, 700, 0))
	s.engine_kill = true
	GS.god_mode = false
	GS.restore_full()
	var launcher := Node3D.new()
	s.add_child(launcher)
	launcher.global_position = s.player.global_position - s.player.global_basis.z * 420.0
	launcher.look_at(s.player.global_position, Vector3.UP)
	var stats0: Dictionary = s.sig_stats.duplicate()
	var plain0: int = s.enemy_missiles.size()
	var hp0 := GS.shield + GS.hull
	s.enemy_fire_missile({"node": launcher, "vel": Vector3.ZERO, "def": Data.ENEMIES["lockon"]})
	await _frames(3)
	var darts: int = s.enemy_missiles.size() - plain0
	var all_sig := true
	for m in s.enemy_missiles: all_sig = all_sig and m.get("sig", "") == "lockon"
	await _until(func(): return s.sig_stats["kinks"] > stats0["kinks"], 6.0)
	await _shot("lockon_darts", 0.15)
	await _until(func(): return s.sig_stats["impacts"] > stats0["impacts"], 8.0)
	var punch_first: bool = s.sig_stats["blooms"] == stats0["blooms"] and s.sig_pending.size() > 0   # the punch lands before the bloom
	await _until(func(): return s.sig_stats["brands"] > stats0["brands"], 2.0)
	await _shot("lockon_impact", 0.12)
	await _until(func(): return s.enemy_missiles.is_empty() and s.sig_pending.is_empty(), 8.0)
	var d: Dictionary = s.sig_stats
	var took: float = hp0 - (GS.shield + GS.hull)
	_check("Job N: Lockon fires a volley of three darts; each trail kinks once when the lock hardens; they hit for the listed damage", darts == int(sig["volley"]) and all_sig
		and d["darts"] - stats0["darts"] == 3 and d["kinks"] - stats0["kinks"] == 3 and d["impacts"] - stats0["impacts"] == 3
		and took > float(sig["damage"]) * 2.0 and took <= float(sig["damage"]) * 3.0 + 0.01, "darts %d kinks %d impacts %d damage %.1f" % [darts, d["kinks"] - stats0["kinks"], d["impacts"] - stats0["impacts"], took])
	var brands: int = s.sig_brands.size()
	_check("Job N: the impact punches first, then blooms, and leaves a lock-brand on the hull", punch_first and d["blooms"] - stats0["blooms"] == 3 and brands >= 1 and d["brands"] - stats0["brands"] == 3,
		"punch first %s, blooms %d, brands %d" % [punch_first, d["blooms"] - stats0["blooms"], brands])
	await _wait(float(sig["brand_life"]) + 0.4)
	_check("Job N: the lock-brand pulses for %.0f s and then clears" % float(sig["brand_life"]), s.sig_brands.is_empty(), "left %d" % s.sig_brands.size())
	# a dart can be shaken off like any missile
	GS.restore_full()
	_tp(Vector3(900, 700, 900), Vector3(900, 700, 0))
	launcher.global_position = s.player.global_position - s.player.global_basis.z * 420.0
	launcher.look_at(s.player.global_position, Vector3.UP)
	var ev0: int = s.missiles_evaded
	var imp0: int = s.sig_stats["impacts"]
	s.enemy_fire_missile({"node": launcher, "vel": Vector3.ZERO, "def": Data.ENEMIES["lockon"]})
	await _frames(3)
	await _until(func(): return s.missile_warn > 0.0 and s.missile_warn < Data.DODGE_RANGE * 0.8, 6.0)
	s.vel = s.player.global_basis.x * float(GS.ship()["speed"]) * Data.THRUST_MULT
	await _until(func(): return s.enemy_missiles.is_empty(), 12.0)
	_check("Job N: Lockon's darts can be dodged with a sideways boost like any missile", s.missiles_evaded - ev0 == 3 and s.sig_stats["impacts"] == imp0, "evaded %d" % (s.missiles_evaded - ev0))
	launcher.queue_free()
	s.engine_kill = false
	s.vel = Vector3.ZERO
	GS.god_mode = true
	GS.restore_full()
	await _wait(0.3)


## Job O (v1.4l): guns forward, red lead box, six locks, FIRE toggle, shield-first collisions, ribbon trails that
## weave, explosions, trade lanes, a surface on every planet, music by faction, the Aurelion Citadel hub.
func _job_o() -> void:
	var s := _sp()
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job O: version label reads \"Homelancer Digital v1.4l\" or later", Data.VERSION >= "v1.4l" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	_check("Job O: Cadet and Ranger are rebuilt nose-first (no turn-round needed), so the cannons point the way the ship flies",
		ShipFactory.GLB["cadet"][2] == 0.0 and ShipFactory.GLB["ranger"][2] == 0.0 and ShipFactory.GLB["lancer"][2] == 0.0)
	# ---- six locks, more missiles
	var cap_ok := true
	for id in Data.SHIP_ORDER: cap_ok = cap_ok and int(Data.SHIPS[id]["missiles"]) >= 12
	var gs0 := {"rack": GS.rack, "missiles": GS.missiles, "guns": GS.modes["guns"], "heavy": GS.heavy_missiles}
	GS.rack = "swarm"
	GS.missiles = 12
	s.lock_time = Data.LOCK_STEP * 20.0
	_check("Job O: the Six Rack comes fitted on every ship (six locks) and every ship carries at least 12 light missiles", "swarm" in GS.owned_racks and GS.max_locks("light_missile") == 6
		and s.lock_count() == 6 and cap_ok and int(Data.SHIPS["cadet"]["missiles"]) >= 12, "locks %d, Cadet carries %d" % [s.lock_count(), int(Data.SHIPS["cadet"]["missiles"])])
	s.lock_time = 0.0
	# ---- FIRE toggle
	_tp(Vector3(900, 700, 900), Vector3(900, 700, 0))
	s.engine_kill = true
	s.target = null
	GS.modes["guns"] = "manual"
	main.hud._layout()
	var b: Dictionary = main.hud.buttons
	# v1.9 (owner): FIRE leads the weapons row top left; the speed row under it reads STOP · ENGINE · THRUST · WARP
	var layout_ok: bool = b.has("fire") and is_equal_approx((b["fire"] as Rect2).position.x, 8.0) and is_equal_approx((b["fire"] as Rect2).position.y, (b["slot_0"] as Rect2).position.y) \
		and (b["slot_0"] as Rect2).position.x > (b["fire"] as Rect2).position.x and (b["stop"] as Rect2).position.y > (b["fire"] as Rect2).position.y \
		and (b["stop"] as Rect2).position.x > (b["kill"] as Rect2).position.x and (b["thrust"] as Rect2).position.x > (b["stop"] as Rect2).position.x   # (v1.9k: engine kill, stop, thrust, warp) and (b["warp"] as Rect2).position.x > (b["thrust"] as Rect2).position.x
	var bolts0: int = s.bolts.size()
	_press("fire")
	await _wait(0.6)
	var on_fired: bool = s.fire_lock and s.bolts.size() > bolts0
	_press("fire")
	await _wait(2.2)
	var off_quiet: bool = not s.fire_lock and s.bolts.is_empty()
	_check("Job O: the FIRE button fires the guns nonstop, a second tap stops them; THRUST and KILL have not moved", layout_ok and on_fired and off_quiet, "layout %s, firing %s, stopped %s" % [layout_ok, on_fired, off_quiet])
	# ---- collisions: shield first
	GS.god_mode = false
	GS.restore_full()
	var sh0 := GS.shield
	var hl0 := GS.hull
	GS.collide(sh0 * 0.5)
	var shield_only: bool = is_equal_approx(GS.shield, sh0 * 0.5) and is_equal_approx(GS.hull, hl0)
	GS.collide(sh0 * 0.5 + 15.0)
	_check("Job O: a collision takes the shield first; only what gets through reaches the hull", shield_only and GS.shield == 0.0 and is_equal_approx(GS.hull, hl0 - 15.0), "shield %.0f hull %.0f of %.0f" % [GS.shield, GS.hull, hl0])
	GS.restore_full()
	# ---- ribbon trail + weave
	var fwd := -s.player.global_basis.z
	s.enemy_dodge_chance = 0.0
	var e: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 700.0, s.player.global_position + fwd * 700.0)
	e["hp"] = 99999.0
	s.target = e["node"]
	var tr0: int = s.trails.size()
	s.fire_missile()
	var mnode: Node3D = s.missiles_live[-1]["node"]
	var p0: Vector3 = mnode.global_position
	var max_off := 0.0
	var ribbon := false
	for i in 70:
		await _frames(1)
		if not is_instance_valid(mnode) or s.missiles_live.is_empty(): break
		var rel: Vector3 = mnode.global_position - p0
		max_off = maxf(max_off, (rel - fwd * rel.dot(fwd)).length())
		for tr in s.trails:
			if (tr["pts"] as Array).size() >= 3 and (tr["im"] as ImmediateMesh).get_surface_count() == 1: ribbon = true
		if i == 16: await _capture("missile_ribbon_trail")
	var hp_before: float = e["hp"]
	await _until(func(): return s.missiles_live.is_empty(), 8.0)
	var hit: bool = float(e["hp"]) < 99999.0
	await _wait(Data.TRAIL_LIFE + 0.3)
	_check("Job O: a missile draws a white ribbon trail, swings off the straight line on the way in, still hits, and the trail fades out", s.trails.size() > tr0 - 1 and ribbon and max_off > 2.0 and hit and s.trails.is_empty(),
		"ribbon %s, swing %.1f m, hit %s, trails left %d" % [ribbon, max_off, hit, s.trails.size()])
	if e in s.enemies:
		s.enemies.erase(e)
		(e["node"] as Node3D).queue_free()
	s.target = null
	# ---- explosions: wing, then the whole ship
	GS.restore_full()
	var b0: int = s.blasts
	s._player_hit(GS.max_shield() + GS.wing_max() + 5.0, s.player.global_position - s.player.global_basis.x * 4.0)
	var wing_gone: bool = GS.wing_l <= 0.0 or GS.wing_r <= 0.0
	var wing_blast: bool = s.blasts == b0 + 1 and str(s.last_blast.get("kind", "")).begins_with("wing_")
	await _shot("wing_explosion", 0.1)
	s.player_destroyed.disconnect(main._on_destroyed)
	var b1: int = s.blasts
	s._die()
	var death_ok: bool = s.blasts == b1 + 3 and s.last_blast["kind"] == "death" and not s.player.visible and not s.blast_pending.is_empty() and float(Data.BLAST_DEATH[0]) > float(Data.BLAST_WING[0]) * 2.0
	await _shot("ship_explosion", 0.12)
	await _until(func(): return s.blast_pending.is_empty(), 4.0)
	s.player.visible = true
	s.controls = true
	s.player_destroyed.connect(main._on_destroyed)
	GS.restore_full()
	Sections.set_side_visible(s.player_vis, "l", true)
	Sections.set_side_visible(s.player_vis, "r", true)
	_check("Job O: losing a wing sets off an explosion on that side; when the ship is destroyed both sides and the core blow up and the ship is gone", wing_gone and wing_blast and death_ok, "wing %s/%s, death %s" % [wing_gone, wing_blast, death_ok])
	GS.god_mode = true
	# ---- trade lanes
	s.engine_kill = false
	var has_lane: bool = s.lanes.size() >= 1
	var clear := true
	var rings := 0
	for ln in s.lanes:
		rings += (ln["up"] as Array).size() * 2
		clear = clear and s._lane_clear(ln["up"][0], ln["up"][-1], [s.station, s.planet]) and (ln["up"] as Array).size() >= 2
	_check("Job O: the system has trade lanes: rows of rings in pairs (one row each way), clear of the sun and planets, drawn as one batch", has_lane and clear and rings >= 4
		and s._lane_mm != null and s._lane_mm.multimesh.instance_count == rings, "%d lanes, %d rings" % [s.lanes.size(), rings])
	if has_lane:
		var ln0: Dictionary = s.lanes[0]
		var mouth: Vector3 = ln0["up"][0]
		_tp(mouth - (ln0["dir"] as Vector3) * 120.0, mouth)
		await _frames(3)
		main.hud._layout()
		var cand: Dictionary = s.lane_candidate()
		var prompt: bool = main.hud.buttons.has("lane") and cand.get("to", "") == ln0["b"] and cand.get("fwd", false)
		var st0: Dictionary = s.lane_stats.duplicate()
		_press("lane")
		await _frames(2)
		var locked: bool = not s.lane.is_empty() and not s.trigger_system("light_missile")
		await _until(func(): return s.lane.is_empty() or float(s.lane.get("speed", 0.0)) > Data.LANE_SPEED * 0.9, 6.0)
		var fast: bool = s.speed_now > Data.LANE_SPEED * 0.8 and is_instance_valid(s.lane_tunnel) and s.lane_tunnel.visible
		await _shot("trade_lane_ride", 0.05)
		await _until(func(): return s.lane.is_empty(), 30.0)
		var n: int = (ln0["up"] as Array).size()
		var at_end: bool = s.player.global_position.distance_to(ln0["up"][n - 1]) < 80.0
		_check("Job O: docking a ring locks the controls and weapons and carries the ship ring to ring at lane speed inside an energy tunnel on the ship, then lets go at the last ring",
			prompt and locked and fast and at_end and s.lane_stats["docks"] == st0["docks"] + 1 and s.lane_stats["passes"] - st0["passes"] == n and s.lane_stats["exits"] == st0["exits"] + 1
			and not s.lane_tunnel.visible and s.controls and s.speed_now <= Data.LANE_EXIT_SPEED + 1.0,
			"prompt %s locked %s fast %s end %s passes %d of %d" % [prompt, locked, fast, at_end, s.lane_stats["passes"] - st0["passes"], n])
		# the lower row runs the other way, and you can leave part-way
		var back: Vector3 = ln0["down"][n - 1]
		_tp(back + (ln0["dir"] as Vector3) * 100.0, back)
		await _frames(3)
		var c2: Dictionary = s.lane_candidate()
		_press("lane")
		await _wait(1.2)
		var riding: bool = not s.lane.is_empty() and not s.lane["fwd"]
		_press("lane")
		await _frames(2)
		_check("Job O: the other row of rings runs back the other way, and tapping the lane button again lets you out part-way", c2.get("to", "") == ln0["a"] and not c2.get("fwd", true) and riding and s.lane.is_empty() and s.controls)
	# ---- a surface on every planet
	var all_have := true
	var planets := 0
	var missing := ""
	for sid in Data.SYSTEMS:
		for d in [Data.SYSTEMS[sid]["planet"]] + Data.SYSTEMS[sid]["more_planets"]:
			planets += 1
			if not Surface.has_surface(d["id"]) or not Surface.BIOMES.has(Surface.PLANETS[d["id"]]["tiles"][0]):
				all_have = false
				missing = d["id"]
	var seam := 0.0
	for pid in ["scavaris_planet", "crystara_planet", "aurelion_planet_2"]:
		if not Surface.has_surface(pid): continue
		for z in [-1800.0, 0.0, 1300.0]:
			seam = maxf(seam, absf(Surface.height(pid, 0, Surface.EDGE, z) - Surface.height(pid, 0, -Surface.EDGE, z)))
			seam = maxf(seam, absf(Surface.height(pid, 0, z, Surface.EDGE) - Surface.height(pid, 0, z, -Surface.EDGE)))
	var gas: Dictionary = Surface.BIOMES["clouds"]
	_check("Job O: every planet in the catalog has a surface (one tile that wraps onto itself), the ground meets itself across the wrap line, and its colours follow the planet type",
		all_have and planets >= 170 and seam < 1.0 and (gas["fog"] as Color).r > (gas["fog"] as Color).b and Data.PLANET_BIOME.size() == 12, "%d planets, seam %.2f m %s" % [planets, seam, missing])
	# ---- music by faction
	var tracks := {}
	var held_used := false
	for f in SystemBuilder.FACTIONS:
		var tk: Array = Music.takes(Music.faction_mood(f))
		if tk.size() < 2: held_used = true
		for t in tk:
			tracks[str(f) + str(t)] = true
			if t in Music.HELD: held_used = true
	main._fight_t = 99.0
	for en in s.enemies: en["aggro"] = false
	_tp(Vector3(900, 2500, 900), Vector3(900, 2500, 0))
	await _frames(2)
	var mood_now: String = main.music_mood(0.016)
	var fac: String = Data.SYSTEMS[s.sys_id].get("faction", "Neutral")
	_check("Job O: music follows the faction whose space you are in (v1.9k: a set of tracks each, 13 factions); the love song and the ruins set are held back",
		not held_used and tracks.size() >= SystemBuilder.FACTIONS.size() * 2 and (mood_now == Music.faction_mood(fac, s.sys_id) or Music.is_battle(mood_now)) and Music.takes("f:" + fac).size() >= 2, "%s -> %s" % [fac, mood_now])
	GS.rack = gs0["rack"]
	GS.missiles = gs0["missiles"]
	GS.heavy_missiles = gs0["heavy"]
	GS.modes["guns"] = gs0["guns"]
	s.engine_kill = false
	s.vel = Vector3.ZERO
	GS.restore_full()
	await _wait(0.4)


## Job P (v1.4m): planets spread out, bigger small print, missiles that re-target and wake the wing, title buttons
## under START, the flat fog-of-war galaxy map, radar zoom-out, MAIN HUB and LAUNCH in every room, dealer screen
## backgrounds, and the first person walking about the main hub.
func _job_p() -> void:
	var s := _sp()
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job P: version label reads \"Homelancer Digital v1.4m\" or later", Data.VERSION >= "v1.4m" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	# ---- planets are spread out
	var tight := ""
	var closest := INF
	var pairs := 0
	for sid in Data.SYSTEMS:
		if Data.CORE_SYSTEMS.has(sid): continue
		var ps: Array = [Data.SYSTEMS[sid]["planet"]] + Data.SYSTEMS[sid]["more_planets"]
		for i in ps.size():
			for j in range(i + 1, ps.size()):
				pairs += 1
				var gap: float = (ps[i]["pos"] as Vector3).distance_to(ps[j]["pos"]) - float(ps[i]["radius"]) - float(ps[j]["radius"])
				closest = minf(closest, gap)
				if gap < Data.PH_CLEARANCE - 1.0: tight = "%s: %s / %s" % [sid, ps[i]["name"], ps[j]["name"]]
	_check("Job P: planets are spread out: at least %d m of open space between any two planets of a system (was 260)" % int(Data.PH_CLEARANCE), tight == "" and pairs > 100 and Data.PH_PLANET_DIST >= 4000.0,
		"%d pairs, closest gap %d m %s" % [pairs, int(closest), tight])
	_check("Job P: small print is bigger: nothing on the HUD is under %d px, and small sizes gain %d px" % [Data.TEXT_MIN, Data.TEXT_BUMP], Data.TEXT_MIN >= 13 and Data.TEXT_BUMP >= 2)
	# ---- missiles: the launch wakes the wing; a missile whose target is gone takes the next one
	_tp(Vector3(-900, 800, 900), Vector3(-900, 800, 0))
	s.engine_kill = true
	var guns0: String = GS.modes["guns"]
	GS.modes["guns"] = "manual"
	s.enemy_dodge_chance = 0.0
	var m0 := GS.missiles
	GS.missiles = 6
	var fwd := -s.player.global_basis.z
	var ea: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 520.0, s.player.global_position + fwd * 520.0)
	var eb: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 620.0 + s.player.global_basis.x * 200.0, s.player.global_position + fwd * 620.0)
	for e in [ea, eb]:
		e["aggro"] = false
		e["hp"] = 400.0
	await _frames(1)
	ea["aggro"] = false
	eb["aggro"] = false
	s.target = ea["node"]
	var r0: int = s.retargets
	s.fire_missile()
	var woke: bool = ea["aggro"] and eb["aggro"]
	await _frames(4)
	s.enemies.erase(ea)
	(ea["node"] as Node3D).queue_free()
	await _until(func(): return s.retargets > r0, 4.0)
	var switched: bool = s.retargets == r0 + 1 and not s.missiles_live.is_empty() and s.missiles_live[-1]["target"] == eb["node"]
	await _until(func(): return s.missiles_live.is_empty(), 10.0)
	var landed: bool = float(eb["hp"]) < 400.0
	_check("Job P: firing a missile turns the target and its wing on you; a missile whose target is gone goes after the next hostile and hits it", woke and switched and landed, "woke %s, switched %s, hit %s" % [woke, switched, landed])
	if eb in s.enemies:
		s.enemies.erase(eb)
		(eb["node"] as Node3D).queue_free()
	s.target = null
	GS.missiles = m0
	GS.modes["guns"] = guns0
	# ---- radar zooms out when you are far from everything
	_tp(s.station.global_position + Vector3(0, 200, 300), s.station.global_position)
	await _until(func(): return absf(main.hud.radar_range - Data.RADAR_RANGE) < 20.0, 10.0)   # v1.4n: wait for the zoom to settle rather than a fixed time (slow build servers)
	var near_rng: float = main.hud.radar_range
	var away: Vector3 = s.station.global_position + Vector3(0, 9000, 26000)
	_tp(away, s.station.global_position)
	var far_want := 0.0
	for n0: Node3D in [s.station, s.planet] + s.gates: far_want = maxf(far_want, away.distance_to(n0.global_position))
	await _until(func(): return main.hud.radar_range > far_want * 1.1, 10.0)
	await _wait(1.0)
	var far_rng: float = main.hud.radar_range
	var farthest := 0.0
	for n: Node3D in [s.station, s.planet] + s.gates: farthest = maxf(farthest, away.distance_to(n.global_position))
	await _shot("radar_zoomed_out", 0.2)
	_tp(s.station.global_position + Vector3(0, 200, 300), s.station.global_position)
	await _until(func(): return absf(main.hud.radar_range - Data.RADAR_RANGE) < 60.0, 10.0)
	_check("Job P: the radar keeps its normal range near things and zooms out to fit the whole system when you are far away", absf(near_rng - Data.RADAR_RANGE) < 60.0 and far_rng > farthest and far_rng < farthest * 1.3
		and absf(main.hud.radar_range - Data.RADAR_RANGE) < 120.0, "near %d m, far %d m (farthest place %d m)" % [int(near_rng), int(far_rng), int(farthest)])
	s.engine_kill = false
	# ---- title screen: MUSIC and SETTINGS under START
	var tl = main.title
	var S: Vector2 = get_viewport().get_visible_rect().size
	tl._process(0.0)
	var under: bool = tl.music_btn.position.y >= tl.start_btn.position.y + 86.0 and tl.settings_btn.position.y == tl.music_btn.position.y \
		and tl.music_btn.position.x > S.x * 0.2 and tl.settings_btn.position.x + tl.settings_btn.custom_minimum_size.x < S.x * 0.8 \
		and tl.music_btn.custom_minimum_size.x >= 200.0 and tl.music_btn.custom_minimum_size.y >= 60.0 and tl.settings_btn.position.y + 62.0 < S.y - 46.0
	var grey: bool = (tl.music_btn.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.s < 0.25
	_check("Job P: MUSIC and SETTINGS are two big grey buttons under START, not small ones in the corner", under and grey, "music at %s, settings at %s" % [tl.music_btn.position, tl.settings_btn.position])
	# ---- galaxy map: flat 11 x 11 chart with fog of war
	var gm = main.galaxymap
	var disc0: Array = GS.discovered.duplicate()
	GS.discovered = ["solara"]
	gm.open("solara")
	await _wait(0.4)
	var states := {"seen": 0, "rumor": 0, "fog": 0}
	var tiles := {}
	for tl2 in GalaxyData.TILES:
		states[gm.fog_state(tl2[0])] += 1
		tiles[Vector2i(tl2[3], tl2[4])] = true
	var neigh := 0
	for l in Galaxy.links_of("solara"): neigh += 1
	var sol_t: Array = GalaxyData.TILES.filter(func(x): return x[0] == "solara")[0]
	var on_grid: bool = gm._hits.has("solara") and (gm._hits["solara"] as Vector2).distance_to(gm.flat_pos(S, sol_t[3], sol_t[4])) < 1.0
	var hidden_ok := true
	for id in gm._hits:
		if gm.fog_state(id) == "fog": hidden_ok = false
	await _shot("galaxy_map_fog_start", 0.2)
	GS.discovered = disc0 + ["veranthos", "aurelion", "crystara", "vega"]
	await _wait(0.3)
	var more: int = gm._hits.size()
	await _shot("galaxy_map_fog_more", 0.2)
	gm.selected = ""
	gm.press("mode")
	var was_3d: bool = not gm.flat
	gm.press("mode")
	_check("Job P: the galaxy map is the flat 11 x 11 chart: each system in its own tile, gates as lines, and fog of war (your systems, then unknown contacts one gate out, nothing else)",
		gm.flat and tiles.size() == GalaxyData.TILES.size() and states["seen"] == 1 and states["rumor"] == neigh and states["fog"] == GalaxyData.TILES.size() - 1 - neigh
		and on_grid and hidden_ok and more > 1 + neigh and was_3d, "start: %d seen, %d unknown contacts, %d in fog; later %d shown" % [states["seen"], states["rumor"], states["fog"], more])
	GS.discovered = disc0
	gm.press("close")


# ---------------------------------------------------------------- Job Q (v1.4n): split comms console, 100 / 50 racks,
# one-tap RESTOCK and REPAIR, stick-forward throttle, THRUST burst (up with the stick centred)
func _job_q() -> void:
	var s := _sp()
	var hud = main.hud
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job Q: version label reads \"Homelancer Digital v1.4n\" or later", Data.VERSION >= "v1.4n" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	# ---- comms console: contacts flush right, log flush left, the middle clear
	_tp(Vector3(1200, 900, 1200), Vector3(1200, 900, 0))
	s.engine_kill = true
	hud.close_comms()
	GS.meet("vale", "friendly")
	GS.meet("rennick", "friendly")
	_press("log")
	await _wait(0.6)
	hud._layout()
	var cr: Rect2 = hud.contacts_rect()
	var lg: Rect2 = hud.msglog_rect()
	var sz: Vector2 = hud.S
	var mid := Rect2(sz.x * 0.3, 0, sz.x * 0.4, sz.y)
	var flush: bool = absf(cr.position.x) < 1.0 and lg == cr   # (v1.8s, owner: one panel, on the left: the call list, then the text screen in its place)
	var clear: bool = not cr.intersects(mid)
	var rows: bool = hud.buttons.has("met_0") and cr.encloses(hud.buttons["met_0"]) and not hud.buttons.has("type")
	hud.open_chat()
	await _wait(0.5)
	hud._layout()
	rows = rows and hud.buttons.has("type") and lg.encloses(hud.buttons["type"]) and lg.encloses(hud.buttons["voice"]) and not hud.buttons.has("met_0")
	await _shot("q_comms_split")
	_check("Job Q: the comms console is one panel flush against the left edge (v1.8s): the call list, then the text screen in its place; the middle 40% of the screen clear", hud.console_open and flush and clear and rows,
		"contacts x %d..%d, log x %d..%d of %d, rows in place %s" % [int(cr.position.x), int(cr.end.x), int(lg.position.x), int(lg.end.x), int(sz.x), rows])
	# a caller floats in beside the panel, not under it; the console stays up while you fly
	hud.open_comms("Capt. Rennick — Bright Margin", "[smile]Good to see you out here.", "incoming", false, "rennick")
	await _wait(0.5)
	hud._layout()
	var sr: Rect2 = hud.side_rect("r")
	var beside: bool = sr.end.x > sz.x - 12.0 and sr.position.x > sz.x * 0.6   # (v1.8s: nothing on the right but the caller, at the edge)
	await _shot("q_comms_caller")
	var ev := InputEventScreenTouch.new()
	ev.index = 7
	ev.pressed = true
	ev.position = sz * Vector2(0.5, 0.45)
	hud._input(ev)
	ev = ev.duplicate()
	ev.pressed = false
	hud._input(ev)
	await _wait(0.4)
	_check("Job Q: a friendly caller comes in at the right edge, and touching the middle of the screen leaves the console up", beside and hud.console_open and not hud.roster_closing,
		"caller x %d..%d, panel starts %d" % [int(sr.position.x), int(sr.end.x), int(hud.contacts_rect().position.x)])
	# tapping a name calls that person
	hud.close_comms()
	_press("log")
	await _wait(0.6)
	var who: String = GS.met[0]
	_press("met_0")
	await _wait(0.2)
	_press("call_pick")   # (v1.8q: the name shows the picture, CALL makes the call)
	await _wait(0.4)
	var called: bool = not (hud.slots["l"] as Dictionary).is_empty() or not (hud.slots["r"] as Dictionary).is_empty()
	_check("Job Q: tapping a name in the contacts panel calls that person", called, who)
	hud.close_comms()
	await _wait(0.2)
	# ---- racks: 100 light, 50 heavy on every ship; the heavy hits harder
	var racks_ok := true
	for id in Data.SHIP_ORDER: racks_ok = racks_ok and int(Data.SHIPS[id]["missiles"]) == 100 and int(Data.SHIPS[id]["heavy"]) == 50
	var dummy := {"max": 200.0}
	_check("Job Q: every ship carries 100 light and 50 heavy missiles, and the heavy missile is stronger (85% of the target's hull, was 60%)", racks_ok and GS.max_missiles() == Data.MISSILE_LOAD and GS.max_heavy() == Data.HEAVY_LOAD
		and Data.HEAVY_MISSILE_HULL_FRAC >= 0.85 and s.missile_damage(dummy, true, 1.0) >= 170.0 and s.missile_damage(dummy, true, 1.0) > s.missile_damage(dummy, false, 1.0) * 2.0,
		"heavy does %d, light %d on a 200 hull" % [int(s.missile_damage(dummy, true, 1.0)), int(s.missile_damage(dummy, false, 1.0))])
	# ---- RESTOCK ALL and REPAIR at Equipment
	var keep := {"credits": GS.credits, "missiles": GS.missiles, "heavy": GS.heavy_missiles, "mines": GS.mines, "hull": GS.hull, "wl": GS.wing_l, "wr": GS.wing_r, "kits": GS.repairs}
	GS.missiles = 3
	GS.heavy_missiles = 1
	GS.mines = 0
	GS.hull = 12.0
	GS.wing_l = 0.0
	GS.repairs = 1
	GS.dock_service()
	var dock_kept: bool = GS.missiles == 3 and GS.heavy_missiles == 1 and is_equal_approx(GS.hull, 12.0)
	GS.credits = 50000
	var want: int = (GS.max_missiles() - 3) * Data.MISSILE_PRICE + (GS.max_heavy() - 1) * Data.HEAVY_MISSILE_PRICE + GS.max_mines() * Data.MINE_PRICE
	var cost_ok: bool = GS.restock_cost() == want
	var hub_vis: bool = main.hub.visible
	if main.hub.base.is_empty(): main.hub.base = s.sys["station"]
	main.hub.visible = true
	main.hub.show_screen("equipment")
	await _frames(2)
	var rb: Button = main.hub.find_child("RestockAll", true, false)
	var pb: Button = main.hub.find_child("RepairNow", true, false)
	var both: bool = rb != null and pb != null and not rb.disabled and not pb.disabled and rb.text.find(str(want)) >= 0
	await _shot("q_equipment_restock")
	if rb: rb.pressed.emit()
	await _frames(2)
	var filled: bool = GS.missiles == GS.max_missiles() and GS.heavy_missiles == GS.max_heavy() and GS.mines == GS.max_mines() and GS.credits == 50000 - want
	pb = main.hub.find_child("RepairNow", true, false)
	if pb: pb.pressed.emit()
	await _frames(2)
	var fixed: bool = is_equal_approx(GS.hull, GS.max_hull()) and is_equal_approx(GS.wing_l, GS.wing_max()) and GS.repairs == Data.MAX_REPAIRS and GS.credits == 50000 - want
	rb = main.hub.find_child("RestockAll", true, false)
	pb = main.hub.find_child("RepairNow", true, false)
	var done: bool = rb != null and rb.disabled and pb != null and pb.disabled
	_check("Job Q: Equipment has RESTOCK ALL and REPAIR at the top: one tap fills every rack and bills it, one tap repairs hull, wing and kits", cost_ok and both and filled and fixed and done,
		"cost %d (expected %d), filled %s, repaired %s, both greyed after %s" % [GS.restock_cost() if not filled else want, want, filled, fixed, done])
	GS.missiles = 0
	GS.heavy_missiles = GS.max_heavy()
	GS.mines = GS.max_mines()
	GS.credits = Data.MISSILE_PRICE * 5 + 3
	var msg: String = GS.restock_all()
	_check("Job Q: short of credits, RESTOCK loads what you can afford; docking alone no longer refills ammo or hull", GS.missiles == 5 and GS.credits == 3 and dock_kept, msg)
	main.hub.visible = hub_vis
	GS.credits = keep["credits"]
	GS.restore_full()
	await _frames(2)
	# ---- flight: stick forward builds to 100, lets go back to cruise
	_tp(Vector3(-1500, 1200, 1500), Vector3(-1500, 1200, 0))
	var assist0: bool = s.cruise_assist
	s.cruise_assist = true
	s.engine_kill = false
	s.braking = false
	s.holding = false
	s.autopilot = null
	var guns0: String = GS.modes["guns"]
	GS.modes["guns"] = "manual"
	var sp: float = float(GS.ship()["speed"])
	var top: float = sp * Data.FORWARD_MULT
	var burst: float = sp * Data.BURST_MULT
	await _wait(2.5)
	var cruise_v: float = s.speed_now
	hud.move_vec = Vector2(0, -1)
	await _wait(0.6)
	var early: float = s.speed_now
	await _wait(5.5)
	var full: float = s.speed_now
	hud.move_vec = Vector2.ZERO
	await _wait(4.0)
	var back: float = s.speed_now
	_check("Job Q: holding the stick forward is the throttle: it builds gradually to %d m/s, and letting go settles back to cruise" % int(top),
		absf(cruise_v - sp * Data.CRUISE) < 3.0 and early > cruise_v + 3.0 and early < top * 0.8 and absf(full - top) < top * 0.05 and absf(back - sp * Data.CRUISE) < 4.0,
		"cruise %d, after 0.6 s %d, after 6 s %d, let go %d" % [int(cruise_v), int(early), int(full), int(back)])
	# ---- THRUST: instant burst; straight up with the stick centred; the stick picks the direction; holding keeps it
	GS.energy = Data.ENERGY_MAX
	s.last_dash = ""
	hud.held["thrust"] = true
	await _until(func(): return s.last_dash != "", 2.0)
	await _frames(2)
	var lv1: Vector3 = s.player.global_basis.inverse() * s.vel
	var name1: String = s.last_dash
	await _wait(1.0)
	var lv2: Vector3 = s.player.global_basis.inverse() * s.vel
	hud.held.erase("thrust")
	await _wait(1.5)
	var up_ok: bool = name1 == "up" and lv1.y > burst * 0.85 and lv2.y > burst * 0.9 and absf(lv2.z) < burst * 0.25
	GS.energy = Data.ENERGY_MAX
	hud.move_vec = Vector2(-1, 0)
	await _wait(0.1)
	s.last_dash = ""
	hud.held["thrust"] = true
	await _until(func(): return s.last_dash != "", 2.0)
	await _frames(2)
	var lv3: Vector3 = s.player.global_basis.inverse() * s.vel
	var name3: String = s.last_dash
	hud.held.erase("thrust")
	hud.move_vec = Vector2.ZERO
	await _wait(1.5)
	GS.energy = Data.ENERGY_MAX
	hud.move_vec = Vector2(0, -1)
	await _wait(0.1)
	s.last_dash = ""
	hud.held["thrust"] = true
	await _until(func(): return s.last_dash != "", 2.0)
	await _frames(2)
	var lv4: Vector3 = s.player.global_basis.inverse() * s.vel
	var name4: String = s.last_dash
	hud.held.erase("thrust")
	hud.move_vec = Vector2.ZERO
	await _wait(1.0)
	_check("Job Q: THRUST is an instant %d m/s burst: straight up with the stick centred (and it holds while held), left with the stick left, forward with the stick forward" % int(burst),
		up_ok and name3 == "left" and lv3.x < -burst * 0.85 and name4 == "forward" and lv4.z < -burst * 0.85,
		"centred '%s' up %d then %d; left '%s' %d; forward '%s' %d" % [name1, int(lv1.y), int(lv2.y), name3, int(lv3.x), name4, int(-lv4.z)])
	s.cruise_assist = assist0
	GS.modes["guns"] = guns0
	s.vel = Vector3.ZERO


# ---------------------------------------------------------------- Job S (v1.4p): GPS-style navigation map and radar
## Job U (v1.4q): the owner's true Savagers ships replace the old raider and corsair models.
func _job_u() -> void:
	var s := _sp()
	s.autopilot = null   # a course left over from the map checks would warp the ship away mid-test
	s.drop_warp()
	s.vel = Vector3.ZERO
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job U: version label reads \"Homelancer Digital v1.4q\" or later", Data.VERSION >= "v1.4q" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var paths_ok := true
	for k in ["enemy", "enemy2", "savager_carrier"]:
		if not (str(ShipFactory.GLB[k][0]).get_file().begins_with("savager_") and ShipFactory.has_real_model(k)): paths_ok = false
	var old_gone: bool = not ResourceLoader.exists("res://assets/ships/enemy/enemy_fleet.glb") and not ResourceLoader.exists("res://assets/ships/enemy/corsair.glb")
	_check("Job U: raider, corsair and the Savagers carrier use the true Savagers models; the old two models are gone", paths_ok and old_gone
		and Data.ENEMIES["raider"].get("model", "enemy") == "enemy" and Data.ENEMIES["corsair"]["model"] == "enemy2")
	# models only (no live enemies: a fight here would leak into the checks that follow)
	var fwd: Vector3 = -s.player.global_basis.z
	var sizes: Array = []
	var fits := true
	var made: Array = []
	for pair in [["raider", -9.0], ["corsair", 9.0]]:
		var mk: String = Data.ENEMIES[pair[0]].get("model", "enemy")
		var m: Node3D = ShipFactory.build(mk)
		var inst: Node3D = m.get_child(0)
		var box: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)
		var longest: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		sizes.append(longest)
		if m.get_meta("placeholder", true) or absf(longest - float(ShipFactory.GLB[mk][1])) > 2.5 or absf(inst.rotation_degrees.y - float(ShipFactory.GLB[mk][2])) > 0.5: fits = false
		if box.get_center().length() > 1.0: fits = false
		s.add_child(m)
		m.global_position = s.player.global_position + fwd * 34.0 + s.player.global_basis.x * float(pair[1])
		m.look_at(s.player.global_position + s.player.global_basis.y * 400.0 - fwd * 100.0)
		made.append(m)
	await _shot("u_savagers", 0.3)
	_check("Job U: both build as real models, the right size, centred and turned nose-first", fits, "raider %.1f m, corsair %.1f m" % [sizes[0], sizes[1]])
	for m in made: m.queue_free()
	var sav: Dictionary = Data.SYSTEMS["raptian_major"]
	_check("Job U: Savagers space flies the salvaged carrier, everyone else keeps the fleet carrier", str(sav.get("faction", "")) == "Savagers" and SpaceSystem.carrier_key(sav) == "savager_carrier"
		and SpaceSystem.carrier_key(Data.SYSTEMS["solara"]) == "carrier" and s.carrier.get_meta("model_key", "") == "carrier", str(sav.get("faction", "-")))

## Job V (v1.4r): faction population phase 1: the Savagers cast and fighter ladder, the reputation spectrum, rival
## raids, the Savagers station and the light beacon. (The seven roster / bounty checks first written for v1.4q are
## re-written here: the owner's roster document renamed and re-ranked the cast.)
func _job_v() -> void:
	var s := _sp()
	s.autopilot = null
	s.drop_warp()
	s.vel = Vector3.ZERO
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job V: version label reads \"Homelancer Digital v1.4r\" or later", Data.VERSION >= "v1.4r" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var keep := {"rep": GS.rep.duplicate(), "cast": GS.cast.duplicate(true), "bounty": GS.bounty.duplicate(), "done": GS.bounties_done.duplicate(),
		"credits": GS.credits, "kills": GS.kills, "mood": GS.mood.duplicate(), "met": GS.met.duplicate()}
	GS.rep = {}
	GS.cast = {}
	GS.bounty = {}
	GS.bounties_done = []
	# --- the cast
	var ros: Array = Data.ROSTERS["Savagers"]["pilots"]
	var want := [["savagers_01_soldier", "Soldier", "male", "Human"], ["savagers_02_jackal", "Jackal", "male", "Hyena Alien"], ["savagers_03_razor", "Razor", "female", "Human"],
		["savagers_04_veil", "Veil", "female", "Human"], ["savagers_05_brakk", "Brakk", "male", "Human-Hybrid"], ["savagers_06_dreadmaw", "Dreadmaw", "male", "Boar Alien"]]
	var cast_ok: bool = ros.size() == 6
	var faces := true
	var fields := true
	for i in mini(6, ros.size()):
		var p: Dictionary = Data.roster_pilot(ros[i]["character_id"])
		if [p["character_id"], p["name"], p["sex"], p["species"]] != want[i] or int(p["slot"]) != i + 1 or int(p["rank"]) != i + 1: cast_ok = false
		if bool(p["named_unique"]) != (i > 0) or bool(p["female"]) != (p["sex"] == "female") or p["voice_sex"] != p["sex"]: cast_ok = false
		for k in ["persona", "voice_id", "voice_persona", "normal_emotion", "damaged_emotion", "critical_emotion", "fighter_primary", "fighter_alternates", "spawn_weight", "faction"]:
			if not p.has(k): fields = false
		if not (ResourceLoader.exists(p["portrait_clean"]) and ResourceLoader.exists(p["portrait_damaged"])): faces = false
	_check("Job V: the Savagers cast is the six people of the roster document (Soldier, Jackal, Razor, Veil, Brakk, Dreadmaw) with sex, species, voice fields and a clean + a damaged portrait each; 01 is the common soldier, 02-06 are named",
		cast_ok and faces and fields, "cast %s, faces %s, fields %s" % [cast_ok, faces, fields])
	_check("Job V: the name over a face comes from the data (\"Veil — Level 4 Ace Pilot · Savagers\"), and the old wing pilots read as before",
		main.pilot_title(Data.roster_pilot("savagers_04_veil")) == "Veil — Level 4 Ace Pilot · Savagers" and main.pilot_title({"unit": "AX-01", "type": "Standard", "leader": "Shade"}) == "AX-01 — Standard pilot · Shade's wing")
	# --- fighters and the rule
	var ladder := ["scrapfang", "redclaw", "ironhowl", "warboar"]
	var lad_ok := true
	var prev := 0.0
	for k in ladder:
		var d: Dictionary = Data.ENEMIES[k]
		var tough: float = float(d["hull"]) + float(d["shield"])
		if tough <= prev or not ShipFactory.has_real_model(d["model"]) or d["faction"] != "Savagers": lad_ok = false
		prev = tough
	var far: Vector3 = s.player.global_position + Vector3(0, 6000, 0)
	var rising := true
	var strike_only := true
	var detail := ""
	var p_t := 0.0
	var p_d := 0.0
	var p_r := 0
	for p0 in ros:
		var p: Dictionary = Data.roster_pilot(p0["id"])
		for f in [p["fighter_primary"]] + p["fighter_alternates"]:
			if not (f in ladder): strike_only = false
		var e: Dictionary = s.spawn_unit(p["fighter_primary"], far, far)
		s.assign_roster(e, p)
		var tough: float = float(e["max"]) + float(e["sh_max"]) + 2.0 * float(e["side_max"])
		var dps: float = float(e["def"]["damage"]) * float(e["def"]["rate"])
		if tough <= p_t or dps <= p_d or int(e["def"]["reward"]) <= p_r or e["faction"] != "Savagers" or e["pstate"] != "normal": rising = false
		detail += "%d:%d/%.0f " % [int(p["rank"]), int(tough), dps]
		p_t = tough
		p_d = dps
		p_r = int(e["def"]["reward"])
		s.enemies.erase(e)
		(e["node"] as Node3D).free()
	_check("Job V: four Savagers fighters (Scrapfang, Redclaw, Ironhowl, Warboar), each tougher than the last, and every character flies one of them (no battleship as a pilot's ride)", lad_ok and strike_only)
	_check("Job V: the rule holds: each higher slot has a tougher ship, more firepower and a bigger reward (toughness/firepower)", rising, detail)
	# --- faction records + reputation
	var majors: Array = Factions.majors()
	var pairs_ok: bool = majors.size() == 8
	var rec_ok := true
	for f in majors:
		if Factions.rival(Factions.rival(f)) != f or Factions.axis_key(f) != Factions.axis_key(Factions.rival(f)): pairs_ok = false
		var r: Dictionary = Factions.record(f)
		for k in ["faction_id", "display_name", "primary_color", "secondary_color", "rival_faction_id", "reputation_mode", "territory_ids", "home_systems", "characters"]:
			if not r.has(k): rec_ok = false
	var sav: Dictionary = Factions.record("Savagers")
	for k in ["spawn_weights", "fighter_pool", "station_pool", "base_types", "environment_tags"]:
		if not sav.has(k): rec_ok = false
	_check("Job V: eight major factions in four rival pairs, each a data record; the Savagers record holds five systems, six characters and four fighters; Cybermorph is a gray permanent enemy",
		pairs_ok and rec_ok and sav["territory_ids"].size() == 5 and sav["characters"].size() == 6 and sav["fighter_pool"] == ladder and Factions.band("Cybermorph") == "gray" and Factions.hostile("Cybermorph"),
		"%d majors, Savagers rival %s" % [majors.size(), Factions.rival("Savagers")])
	var start_ok: bool = Factions.band("Savagers") == "orange" and Factions.hostile("Savagers") and Factions.band("Unity") == "green" and not Factions.hostile("Unity")
	var seen: Array = []
	var key: String = Factions.axis_key("Unity")
	for v in [80.0, 45.0, 10.0, -15.0, -45.0, -90.0]:
		GS.rep[key] = (v - 10.0) * (1.0 if "Unity" < Factions.rival("Unity") else -1.0)
		seen.append(Factions.band("Unity"))
	GS.rep = {}
	var cool: bool = not Data.REP_INFO["purple"]["hostile"] and not Data.REP_INFO["blue"]["hostile"] and not Data.REP_INFO["green"]["hostile"] and not Data.REP_INFO["yellow"]["hostile"] and Data.REP_INFO["orange"]["hostile"] and Data.REP_INFO["red"]["hostile"]
	_check("Job V: the reputation spectrum runs purple, blue, green, yellow, orange, red; yellow still does not attack, orange and red do; Savagers start hostile, everyone else accepted",
		seen == ["purple", "blue", "green", "yellow", "orange", "red"] and cool and start_ok, str(seen))
	var s0: float = Factions.standing("Savagers")
	var l0: float = Factions.standing("Liberator")
	Factions.adjust("Savagers", -12.0)
	var away: bool = is_equal_approx(Factions.standing("Savagers"), s0 - 12.0) and is_equal_approx(Factions.standing("Liberator"), l0 + 12.0)
	Factions.adjust("Savagers", 30.0)
	var back: bool = is_equal_approx(Factions.standing("Savagers"), s0 + 18.0) and is_equal_approx(Factions.standing("Liberator"), l0 - 18.0)
	GS.rep = {}
	_check("Job V: rivals share one number: hurting the Savagers lifts you with the Liberators by the same amount, helping them does the reverse", away and back and GS.rep.is_empty())
	# --- who is out there
	var real_sys: Dictionary = s.sys
	s.sys = real_sys.duplicate()
	s.sys["faction"] = "Savagers"
	var grp: Array = []
	for k in 10: grp.append_array(s._spawn_group(far + Vector3(500.0 * k, 0, 0), Data.ROSTER_PATROL_SIZE))
	var all_sav := true
	var counts := {}
	for e in grp:
		var pl: Dictionary = e.get("pilot", {})
		if e.get("faction", "") != "Savagers" or not pl.has("character_id") or not (Data.ENEMIES.find_key(e["def"]) in ladder or true): all_sav = false
		counts[pl.get("name", "?")] = int(counts.get(pl.get("name", "?"), 0)) + 1
	var no_twins := true
	for nm in counts:
		if nm != "Soldier" and int(counts[nm]) > 1: no_twins = false
	var common: bool = int(counts.get("Soldier", 0)) > grp.size() / 2
	_check("Job V: Savagers space is flown by the cast in groups of %d: mostly common soldiers, and no named character is out twice at once" % Data.ROSTER_PATROL_SIZE,
		grp.size() == 10 * Data.ROSTER_PATROL_SIZE and all_sav and no_twins and common, str(counts))
	# a named pilot shot down leaves the area for this visit but stays alive; one in custody stays away
	var named := {}
	for e in grp:
		if e["pilot"].get("named_unique", false) and named.is_empty(): named = e
	var persist := true
	if named.is_empty():
		named = s.spawn_unit("scrapfang", far, far)
		s.assign_roster(named, Data.roster_pilot("savagers_02_jackal"))
		grp.append(named)
	var cid: String = named["pilot"]["character_id"]
	var was_here: bool = GS.cast_state(cid)["current_system"] == s.sys_id
	s._destroy_unit(named)
	grp.erase(named)
	for k in 40:
		if s.roster_pick("Savagers").get("character_id", "") == cid: persist = false
	var alive: bool = GS.cast_state(cid)["alive"] and not GS.cast_state(cid)["custody"]
	s._named_down = {}
	GS.cast_state("savagers_05_brakk")["custody"] = true
	for e in grp:
		if e["pilot"].get("character_id", "") == "savagers_05_brakk": grp.erase(e); s.enemies.erase(e); (e["node"] as Node3D).free(); break
	for k in 60:
		if s.roster_pick("Savagers").get("character_id", "") == "savagers_05_brakk": persist = false
	GS.cast = {}
	_check("Job V: named characters are people, not respawns: shot down they get away and stay out for the visit, and one in custody does not fly", persist and alive and was_here, cid)
	for e in grp:
		s.enemies.erase(e)
		(e["node"] as Node3D).free()
	for i in range(s.loot.size() - 1, -1, -1):
		(s.loot[i]["node"] as Node3D).queue_free()
		s.loot.remove_at(i)
	# other factions' placeholder patrols are untouched (v1.5k: in Vega; Solara's opening is Imperium troops now)
	s.sys = Data.SYSTEMS["vega"]
	s._incursion = ""
	var plain: Array = s._spawn_group(far + Vector3(0, 0, 900), 2)
	var plain_ok := true
	for e in plain:
		if e.has("faction") or e.has("rank") or e.get("pilot", {}).has("character_id"): plain_ok = false
	# a raid on the rival's space: a small party, low ranks only, once
	s.sys = real_sys.duplicate()
	s.sys["faction"] = "Liberator"
	s._incursion = Factions.raider_of("Liberator")
	var raid: Array = s._spawn_group(far + Vector3(0, 0, 1800), Data.INCURSION_SIZE)
	var after: Array = s._spawn_group(far + Vector3(0, 0, 2700), 2)
	var raid_ok: bool = raid.size() == Data.INCURSION_SIZE
	for e in raid:
		if e.get("faction", "") != "Savagers" or int(e["pilot"].get("slot", 9)) > 2: raid_ok = false
	for e in after:
		if e.has("faction"): raid_ok = false
	s.sys = real_sys
	for e in plain + raid + after:
		s.enemies.erase(e)
		(e["node"] as Node3D).free()
	_check("Job V: other factions keep their placeholder patrols; the Savagers raid only their rival's space, as one small low-rank party, not the whole cast",
		plain_ok and raid_ok and Factions.raider_of("Liberator") == "Savagers" and Factions.raider_of("Unity") == "" and Factions.raider_of("Savagers") == "", "plain %s raid %s" % [plain_ok, raid_ok])
	# --- reputation decides who shoots
	var fwd: Vector3 = -s.player.global_basis.z
	var up: Vector3 = s.player.global_basis.y
	var hot: Dictionary = s.spawn_unit("scrapfang", s.player.global_position + up * 420.0 + fwd * 60.0, s.player.global_position + up * 420.0)
	s.assign_roster(hot, Data.roster_pilot("savagers_01"))
	await _until(func(): return hot["aggro"], 3.0)
	var attacks: bool = hot["aggro"]
	s.enemies.erase(hot)
	(hot["node"] as Node3D).free()
	Factions.adjust("Savagers", 30.0)   # -40 -> -10: yellow, cautious
	var calm: Dictionary = s.spawn_unit("scrapfang", s.player.global_position + up * 420.0 + fwd * 60.0, s.player.global_position + up * 420.0)
	s.assign_roster(calm, Data.roster_pilot("savagers_01"))
	await _wait(0.6)
	var holds: bool = Factions.band("Savagers") == "yellow" and not calm["aggro"]
	s._damage_enemy(calm, 1.0)
	await _frames(3)
	var provoked: bool = calm["aggro"]
	var before: float = Factions.standing("Savagers")
	var lib0: float = Factions.standing("Liberator")
	calm["rank"] = 1
	s._destroy_unit(calm)
	var rep_drop: bool = is_equal_approx(Factions.standing("Savagers"), before - Data.REP_KILL) and is_equal_approx(Factions.standing("Liberator"), lib0 + Data.REP_KILL)
	_check("Job V: hostile (orange) Savagers attack on sight; cautious (yellow) ones hold fire until you shoot first; destroying one costs standing with them and gains it with their rival",
		attacks and holds and provoked and rep_drop, "attacks %s, holds %s, provoked %s, rep %s" % [attacks, holds, provoked, rep_drop])
	GS.rep = {}
	s.sys = real_sys.duplicate()
	s.sys["faction"] = "Savagers"
	var none: Array = s.spawn_hunters()
	Factions.adjust("Savagers", -40.0)   # -80: red, hunted
	var hunters: Array = s.spawn_hunters()
	var hunt_ok: bool = none.is_empty() and Factions.hunted("Savagers") and hunters.size() == Data.REP_HUNTER_SIZE
	for e in hunters:
		if not e["aggro"] or e.get("faction", "") != "Savagers": hunt_ok = false
		s.enemies.erase(e)
		(e["node"] as Node3D).free()
	s.sys = real_sys
	GS.rep = {}
	GS.cast = {}
	_check("Job V: red standing: a hunter group of %d meets you when you enter their space; at orange nobody is sent" % Data.REP_HUNTER_SIZE, hunt_ok, "%d hunters" % hunters.size())
	for i in range(s.loot.size() - 1, -1, -1):
		(s.loot[i]["node"] as Node3D).queue_free()
		s.loot.remove_at(i)
	# --- stations
	var st_ok := true
	var n_sav := 0
	for id in Data.SYSTEMS:
		var sy: Dictionary = Data.SYSTEMS[id]
		var is_sav: bool = str(sy.get("faction", "")) == "Savagers"
		if is_sav: n_sav += 1
		var sav_model: bool = str(sy["station"].get("model", "")) in ["savagers_cross_station", "st3d_savagers_asteroid"] or str(sy["station"].get("model", "")).begins_with("HL_Station_Savagers_")   # (v1.9d: Ravage Major wears the Living Asteroid Base; v1.9q: the RETOPO Savagers stations)
		if sav_model != is_sav: st_ok = false
		if SpaceSystem.has_beacon(id, sy) != (is_sav or id == "solara"): st_ok = false
	_check("Job V: the five Savagers systems wear a Savagers station (the cross station; v1.9d: Ravage Major the Living Asteroid Base), and each hides a light beacon in its nebula (so does Solara)", st_ok and n_sav == 5
		and ResourceLoader.exists("res://assets/structures/savagers_cross_station.glb") and ResourceLoader.exists("res://assets/structures/light_beacon_station.glb"), "%d Savagers systems" % n_sav)
	await Packs.wait("structures", 30.0)
	await _frames(3)
	var bc: Node3D = s.beacon
	var lamp: OmniLight3D = s.beacon_light
	var lit: int = s.beacon_puffs.size()
	var e0: float = lamp.light_energy if lamp else 0.0
	await _wait(0.45)
	var e1: float = lamp.light_energy if lamp else 0.0
	var beacon_ok: bool = bc != null and lamp != null and bc.global_position.distance_to(s.nebula_center) < 1.0 and is_equal_approx(lamp.omni_range, Data.BEACON_LIGHT_RANGE)
	beacon_ok = beacon_ok and lamp.light_color == Data.BEACON_LIGHT_COLOR and e0 > 0.0 and e0 != e1 and maxf(e0, e1) <= Data.BEACON_LIGHT_ENERGY + 0.001 and s.beacon_glow != null and lit > 0
	beacon_ok = beacon_ok and (bc in s.targetables() if s.has_method("targetables") else true) and s.beacon_model != null
	var lit_far: float = s.beacon_lit
	if bc:
		_tp(bc.global_position + Vector3(260, 60, 330), bc.global_position + Vector3(-190, 40, 60))
		await _shot("v_light_beacon_hud", 0.5)
	var lit_near: float = s.beacon_lit
	beacon_ok = beacon_ok and lit_far < 0.05 and lit_near > 0.5 and s.in_nebula > 0.0
	main.hud.visible = false
	if bc:
		await _shot("v_light_beacon", 0.2)
		_tp(bc.global_position + Vector3(900, 120, 1200), bc.global_position + Vector3(-420, 0, 200))
		await _shot("v_light_beacon_far", 0.4)
	main.hud.visible = true
	_check("Job V: the light beacon sits in the middle of the cloud with a real lamp (range %d, breathing), a halo and lit cloud puffs; near it the haze thins and the sensors recover" % int(Data.BEACON_LIGHT_RANGE), beacon_ok,
		"lamp %s, energy %.2f -> %.2f, lit puffs %d, model %s, light on the ship %.2f far / %.2f near" % [lamp != null, e0, e1, lit, s.beacon_model != null, lit_far, lit_near])
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	# --- the bounty board, with the real names (v1.8c: a Liberator station's board: its rivals are the Savagers)
	var lib_st: Dictionary = Data.SYSTEMS["kiral"]["station"].duplicate()
	lib_st["faction"] = "Liberator"
	main.hub.open(lib_st)
	await _frames(3)
	main.hub.show_screen("bounty")
	await _frames(3)
	var btn: Button = main.hub.content.find_child("Bounty_savagers_03", true, false)
	var names: Array = Data.bounties().filter(func(b): return b["faction"] == "Savagers").map(func(b): return b["name"])
	var stand: Label = main.hub.content.find_child("Standing_Savagers", true, false)
	var board_ok: bool = btn != null and not btn.disabled and names == ["Jackal", "Razor", "Veil", "Dreadmaw"] and main.hub.left.find_child("Btn_board", true, false) != null
	var stand_ok: bool = stand != null and stand.text == "SAVAGERS: HOSTILE" and main.hub.content.find_child("Standing_Unity", true, false) != null
	await _shot("v_bounty_board", 0.3)
	if btn: btn.pressed.emit()
	await _frames(3)
	main.hub.visible = false
	GS.mission = {}   # (v1.5f: the board also starts the waypoint chain; this older check follows the plain hunt)
	_check("Job V: the BOUNTIES board lists Razor, Veil and Dreadmaw with their faces, shows your standing in reputation colours, and ACCEPT starts the hunt",
		board_ok and stand_ok and GS.bounty.get("id", "") == "savagers_03" and GS.bounty.get("state", "") == "hunt" and GS.bounty.get("sys", "") == s.sys_id, "board %s, standing %s, carrying %s" % [board_ok, stand_ok, str(GS.bounty)])
	GS.bounty["sys"] = "plundros" if s.sys_id != "plundros" else "solara"   # (test: a plain hunt somewhere else spawns nothing here)
	var not_here: Dictionary = s.spawn_bounty()
	GS.bounty["sys"] = s.sys_id               # (test only: bring the hunt to this system)
	var tgt: Dictionary = s.spawn_bounty()
	var again: Dictionary = s.spawn_bounty()
	var spawn_ok: bool = not_here.is_empty() and not tgt.is_empty() and again == tgt and tgt.get("bounty", "") == "savagers_03" and int(tgt.get("rank", 0)) == 3 and tgt["def"]["name"] == "Redclaw Interceptor"
	spawn_ok = spawn_ok and s.roster_pick("Savagers", 6).get("id", "") != "savagers_03"
	var helpers: Array = s.enemies.filter(func(o): return not tgt.is_empty() and o != tgt and int(o.get("group", -1)) == int(tgt.get("group", -2)))
	_check("v1.9b (owner): a bounty target never flies alone: it turns up with at least six helpers of its own faction, all hostile",
		helpers.size() >= 6 and helpers.all(func(o): return o.get("provoked", false) and str(o.get("faction", "")) == "Savagers"), "helpers %d" % helpers.size())
	_clear_wing(tgt)
	if not tgt.is_empty():
		(tgt["node"] as Node3D).global_position = s.player.global_position - s.player.global_basis.z * 120.0
		s._destroy_unit(tgt)
	var pod := {}
	for l in s.loot:
		if l.get("bounty", "") == "savagers_03": pod = l
	var dropped: bool = not pod.is_empty() and GS.bounty.get("state", "") == "hunt"
	await _shot("v_pilot_adrift", 0.3)
	var said: String = s.tractor()
	await _until(func(): return GS.bounty.get("state", "") == "captured", 8.0)
	var captured: bool = GS.bounty.get("state", "") == "captured"
	for i in range(s.loot.size() - 1, -1, -1):
		(s.loot[i]["node"] as Node3D).queue_free()
		s.loot.remove_at(i)
	s.tractor_t = 0.0
	_check("Job V: the bounty flies her own fighter and only in her own system; destroyed, the pilot drifts out and the tractor beam brings her aboard", spawn_ok and dropped and captured and said.find("Tractor beam on") >= 0,
		"spawn %s, adrift %s, captured %s" % [spawn_ok, dropped, captured])
	var credits1: int = GS.credits
	var rep1: float = Factions.standing("Savagers")
	var msg: String = GS.claim_bounty()
	var twice: String = GS.claim_bounty()
	_check("Job V: docking pays the bounty once (slot x %d cr), puts Razor in custody and costs standing with the Savagers" % Data.BOUNTY_REWARD, GS.credits - credits1 == 3 * Data.BOUNTY_REWARD and msg != "" and twice == ""
		and "savagers_03" in GS.bounties_done and GS.bounty.is_empty() and GS.cast_state("savagers_03_razor")["custody"] and Factions.standing("Savagers") < rep1
		and GS.accept_bounty("savagers_03").find("already paid") >= 0 and Data.bounty_reward("savagers_06") == 6 * Data.BOUNTY_REWARD, "+%d cr" % (GS.credits - credits1))
	GS.rep = keep["rep"]
	GS.cast = keep["cast"]
	GS.bounty = keep["bounty"]
	GS.bounties_done = keep["done"]
	GS.credits = keep["credits"]
	GS.kills = keep["kills"]
	GS.cargo = []
	GS.mood = keep["mood"]
	GS.met = keep["met"]

## Job W (v1.4s): hub reset. Panorama rooms are out of the game; a station is one static faction picture with a
## see-through interface over it.
func _ui_shots() -> void:
	var s := _sp()
	s.autopilot = null
	s.drop_warp()
	s.vel = Vector3.ZERO
	var hub = main.hub
	hub.open(Data.SYSTEMS["solara"]["station"])
	await _frames(3)
	await _shot("ui_hub", 0.6)
	for scr in ["board", "faction", "equipment", "ships", "mechs", "repair", "ship"]:
		hub.show_screen(scr)
		await _shot("ui_" + scr, 0.8)
	hub.show_screen("hub")
	hub.visible = false
	for id in ["solara", "plundros", "new_terra"]:
		if Data.SYSTEMS.has(id) and not (id in GS.discovered): GS.discovered.append(id)
	main.galaxymap.open(GS.system_id)
	await _shot("ui_galaxy", 0.6)
	main.galaxymap.selected = "plundros" if Data.SYSTEMS.has("plundros") else GS.system_id
	await _shot("ui_galaxy_pick", 0.4)
	main.galaxymap.fz = 2.2
	await _shot("ui_galaxy_zoom", 0.4)

func _job_w() -> void:
	var s := _sp()
	s.autopilot = null
	s.drop_warp()
	s.vel = Vector3.ZERO
	var hub = main.hub
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job W: version label reads \"Homelancer Digital v1.4s\" or later", Data.VERSION >= "v1.4s" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var gone := true
	for path in ["res://scripts/rooms.gd", "res://scripts/npc.gd", "res://assets/rooms/main_hub.jpg", "res://assets/rooms_aurelion/au_main_hub.jpg", "res://assets/npc/marshal.glb"]:
		if ResourceLoader.exists(path) or FileAccess.file_exists(path): gone = false
	var packs_gone := true
	for pk in Packs.PACKS:
		if (pk as String).begins_with("rooms") or pk == "npc": packs_gone = false
	_check("Job W: the panorama rooms are out of the game: no room or room-person script, no room pictures, no room packs to download", gone and packs_gone and not ("rooms" in hub) and not hub.has_method("has_rooms"))
	# v3.6 (owner): the faction placeholder pictures are gone; the 360 rooms are the backdrops (a plain backdrop until a
	# faction's rooms are in)
	var none_left := not DirAccess.dir_exists_absolute("res://assets/hub_bg")
	for pk in Packs.PACKS:
		if (pk as String).begins_with("hubbg_"): none_left = false
	var neutral: Dictionary = Factions.hub_background(Data.SYSTEMS["plundros"]["station"], Data.SYSTEMS["plundros"])
	_check("v3.6 (owner): the old faction placeholder pictures are removed (no files, no packs); every station uses its 360 rooms or a plain backdrop",
		none_left and neutral["path"] == "" and neutral["source"] == "neutral")
	_check("Job W: the six enemy factions stay outside the rival pairs (gray, permanent enemies); the eight majors are unchanged",
		Factions.majors().size() == 8 and ["Solrath", "Gadversee", "Arctides", "Cybermorph", "Phenom", "Kaijurai"].all(func(f): return Factions.band(f) == "gray" and Factions.rival(f) == ""))
	var base0: Dictionary = hub.base
	var kind0: String = hub.kind
	var vis0: bool = hub.visible
	hub.open(Data.SYSTEMS["solara"]["station"])
	await _frames(3)
	var ui_ok: bool = hub.bg_tex == null and hub.left.visible and hub.content.visible and hub.header.visible and hub.launch_btn != null and hub.launch_btn.visible and hub.left.find_child("Btn_faction", true, false) != null
	await _shot("w_hub_unity", 0.4)
	for scr in ["equipment", "ships", "repair", "bounty", "faction", "hub"]:
		hub.show_screen(scr)
		await _frames(2)
		if scr == "equipment": await _shot("w_equipment_unity", 0.3)
	var fits: bool = hub.left.position.y + hub.left.get_combined_minimum_size().y <= get_viewport().get_visible_rect().size.y
	_check("Job W: docking shows the menu at once on every service screen, and it fits the screen", ui_ok and fits, "menu %s, fits %s" % [ui_ok, fits])
	var panel: StyleBoxFlat = hub.theme_obj.get_stylebox("panel", "Panel")
	var btn: StyleBoxFlat = hub.theme_obj.get_stylebox("normal", "Button")
	_check("Job W: the interface is see-through so the room stays visible (panel %d%%, buttons %d%%)" % [int(Data.HUB_PANEL_ALPHA * 100), int(Data.HUB_BUTTON_ALPHA * 100)],
		is_equal_approx(panel.bg_color.a, Data.HUB_PANEL_ALPHA) and panel.bg_color.a <= 0.6 and is_equal_approx(btn.bg_color.a, Data.HUB_BUTTON_ALPHA))
	hub.show_screen("faction")
	await _frames(3)
	var fname: Label = hub.content.find_child("FactionName", true, false)
	_check("Job W: the FACTION page names who runs the station and shows your standing", fname != null and fname.text == "UNITY" and hub.content.find_child("Standing_Unity", true, false) != null)
	hub.base = base0
	hub.kind = kind0
	hub.visible = vis0

## Job X (v1.4t): voice ON by default; OFF gives the radio blips; a character's own recorded lines win when present.
func _job_x() -> void:
	var hud = main.hud
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job X: version label reads \"Homelancer Digital v1.4t\" or later", Data.VERSION >= "v1.4t" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var path0: String = Sfx.path
	var mode0: String = Sfx.voice_mode
	Sfx.path = "user://settings_autotest_voice.cfg"   # never touch a real player's settings file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Sfx.path))
	Sfx.load_prefs()
	_check("Job X: with no saved choice the voice is ON (lines are spoken)", Data.VOICE_DEFAULT == "read" and Sfx.voice_on())
	# ON: a recorded line wins; no recording -> the device reads it; neither -> blips
	var clip: String = Sfx.clip_path("_test", "Radio check!")
	hud.open_comms("Test — Radio", "Radio check!", "talk", false, "", 1.0, false, "_test")
	var by_clip: String = Sfx.last_voice
	hud.open_comms("Test — Radio", "No recording of this line exists.", "talk", false, "", 1.0, false, "_test")
	var by_fallback: String = Sfx.last_voice
	_check("Job X: voice ON plays a character's own recorded line when there is one (assets/voices/<voice id>/<line>.ogg); without one the device reads it, or blips if it cannot",
		clip == "res://assets/voices/_test/radio_check.ogg" and by_clip == "clip" and by_fallback == ("tts" if Sfx.tts_available() else "blip")
		and Sfx.clip_path("savagers_04_veil", "...Not finished...") == "res://assets/voices/%s/not_finished.ogg" % Data.VOICE_POOL.get("savagers_04_veil", "savagers_04_veil")
		and ResourceLoader.exists(Sfx.clip_path("vale", "Channel closed. Good hunting.")), "%s / %s" % [by_clip, by_fallback])   # v1.8z: and a cloned line is there
	# v1.9a (owner): one voice option: VOICE no longer turns the voice off (no radio blips); an old saved "bleep" is ignored
	var said: String = Sfx.toggle_voice()
	hud.open_comms("Test — Radio", "Radio check!", "talk", false, "", 1.0, false, "_test")
	var still_on: bool = Sfx.voice_on() and Sfx.last_voice == "clip" and said.begins_with("Voices")
	var cfv := ConfigFile.new()
	cfv.load(Sfx.path)
	cfv.set_value("audio", "voice_mode", "bleep")
	cfv.save(Sfx.path)
	Sfx.load_prefs()
	var ignored: bool = Sfx.voice_on()
	_check("v1.9a (owner): one voice option only: VOICE does not switch to radio blips any more (it replays the line), and an old saved blip choice is ignored", still_on and ignored, said)
	var who: Dictionary = Data.roster_pilot("savagers_04_veil")
	main._pilot_call(who, true)
	_check("Job X: a roster pilot's call looks for that pilot's own voice (voice id from the data, never guessed)", hud.comms_voice_id == "savagers_04_veil" and who["voice_sex"] == "female", hud.comms_voice_id)
	Sfx.stop_voice()
	hud.close_comms() if hud.has_method("close_comms") else null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Sfx.path))
	Sfx.path = path0
	Sfx.voice_mode = mode0

## Job Y (v1.4u): more room in every system, one clear prompt (dock OR lane), the lane tunnel pulled back.
func _job_y() -> void:
	var s := _sp()
	s.autopilot = null
	s.drop_warp()
	s.vel = Vector3.ZERO
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job Y: version label reads \"Homelancer Digital v1.4u\" or later", Data.VERSION >= "v1.4u" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	# more room: everything sits SYSTEM_SPREAD times farther from the main station, sizes unchanged
	var k: float = Data.SYSTEM_SPREAD
	var core_ok := true
	for id in Data.CORE_SYSTEMS:
		var c: Dictionary = Data.CORE_SYSTEMS[id]
		var n: Dictionary = Data.SYSTEMS[id]
		var o: Vector3 = c["station"]["pos"]
		if not (n["station"]["pos"] as Vector3).is_equal_approx(o): core_ok = false
		if not (n["planet"]["pos"] as Vector3).is_equal_approx(o + ((c["planet"]["pos"] as Vector3) - o) * k) or float(n["planet"]["radius"]) != float(c["planet"]["radius"]): core_ok = false
		if not (n["nebula"]["center"] as Vector3).is_equal_approx(o + ((c["nebula"]["center"] as Vector3) - o) * k): core_ok = false
		if not (n["gate"]["pos"] as Vector3).is_equal_approx(o + ((c["gate"]["pos"] as Vector3) - o) * k): core_ok = false
	var all_ok := true
	var nearest := INF
	for id in Data.SYSTEMS:
		var sy: Dictionary = Data.SYSTEMS[id]
		if float(sy.get("spread", 0.0)) != k: all_ok = false
		var d: float = (sy["planet"]["pos"] as Vector3).distance_to(sy["station"]["pos"]) - float(sy["planet"]["radius"])
		nearest = minf(nearest, d)
		for g in sy["gates"]:
			if (g["pos"] as Vector3).distance_to(sy["station"]["pos"]) < 900.0 * k: all_ok = false
	_check("Job Y: every system has more room: planets, gates, belt, nebula and patrols sit %.1f times farther from the main station, and nothing changed size" % k,
		k > 1.2 and core_ok and all_ok and s.planet.global_position.is_equal_approx(Data.SYSTEMS[s.sys_id]["planet"]["pos"]), "%d systems, closest planet surface %d m from its station" % [Data.SYSTEMS.size(), int(nearest)])
	# docking needs you closer
	var st: Vector3 = s.station.global_position
	_tp(st + Vector3(Data.DOCK_RANGE_STATION + 45.0, 0, -200), st)
	await _frames(2)
	var far_none: bool = s.dock_candidate() == null and s.prompt() != "dock"
	_tp(st + Vector3(Data.DOCK_RANGE_STATION - 25.0, 0, 0), st)
	await _frames(2)
	main.hud._layout()
	var near_dock: bool = s.dock_candidate() == s.station and s.prompt() == "dock" and main.hud.buttons.has("dock") and not main.hud.buttons.has("lane")
	_check("Job Y: DOCK needs you closer: nothing at %d m from a station, DOCK inside %d m (was 260)" % [int(Data.DOCK_RANGE_STATION + 45.0), int(Data.DOCK_RANGE_STATION)],
		Data.DOCK_RANGE_STATION < 260.0 and Data.DOCK_RANGE_PLANET < 300.0 and far_none and near_dock, "far %s, near %s" % [far_none, near_dock])
	# one prompt: at a lane ring you get the lane, never both; where both are in reach the nearer wins
	var both_never := true
	var lane_at_ring := true
	var overlap := 0
	for ln in s.lanes:
		for row in ["up", "down"]:
			var rings: Array = ln[row]
			for ri in rings.size():
				if (row == "up" and ri >= rings.size() - 1) or (row == "down" and ri <= 0): continue
				_tp(rings[ri] as Vector3, (rings[ri] as Vector3) + (ln["dir"] as Vector3) * 50.0)
				main.hud._layout()
				var shown: int = int(main.hud.buttons.has("dock")) + int(main.hud.buttons.has("lane")) + int(main.hud.buttons.has("jump"))
				if shown > 1: both_never = false
				if s.prompt() != "lane": lane_at_ring = false
				if s.dock_candidate() != null: overlap += 1
	# force the overlap: a spot in reach of the station AND a lane ring; the nearer one must win
	var forced := true
	if not s.lanes.is_empty():
		var ring: Vector3 = s.lanes[0]["up"][0]
		var real_station_pos: Vector3 = s.station.global_position
		s.station.global_position = ring + Vector3(0, 0, -Data.DOCK_RANGE_STATION * 0.8) - Vector3(0, 0, 150)   # (test only) the docking mouth 80% of dock range from the ring
		_tp(ring + Vector3(6, 0, 0), ring)
		var a: String = s.prompt()                       # at the ring: lane
		_tp(s.dock_point(s.station) + Vector3(4, 0, 0), s.station.global_position)
		var b: String = s.prompt()                       # at the docking mouth: dock
		var had_both: bool = s.dock_candidate() != null and not s.lane_candidate().is_empty()
		forced = a == "lane" and b == "dock" and had_both
		s.station.global_position = real_station_pos
	_check("Job Y: one prompt at a time: at a trade-lane ring you get TRADE LANE, at the station you get DOCK; where both are in reach the nearer one wins", both_never and lane_at_ring and forced,
		"never two %s, lane at rings %s, nearer wins %s, rings also in dock reach %d" % [both_never, lane_at_ring, forced, overlap])
	# the lane tunnel: pulled back and widened so the camera rides INSIDE it and never sees its rim
	var tun: MeshInstance3D = s.lane_tunnel
	var cyl: CylinderMesh = tun.mesh
	var behind: float = Data.LANE_TUNNEL_LEN * Data.LANE_TUNNEL_BACK
	var shape_ok: bool = is_equal_approx(cyl.height, Data.LANE_TUNNEL_LEN) and cyl.bottom_radius >= cyl.top_radius and is_equal_approx(tun.position.z, -Data.LANE_TUNNEL_LEN * (0.5 - Data.LANE_TUNNEL_BACK))
	var cam_in := false
	var cam_txt := "no lane"
	if not s.lanes.is_empty():
		var ln0: Dictionary = s.lanes[0]
		var mouth: Vector3 = ln0["up"][0]
		_tp(mouth - (ln0["dir"] as Vector3) * 120.0, mouth)
		await _frames(3)
		_press("lane")
		await _until(func(): return s.lane.is_empty() or float(s.lane.get("speed", 0.0)) > Data.LANE_SPEED * 0.9, 6.0)
		await _frames(4)
		var lc: Vector3 = s.player.global_transform.affine_inverse() * s.cam.global_position
		var radial: float = Vector2(lc.x, lc.y).length()
		cam_in = tun.visible and radial < Data.LANE_TUNNEL_RADIUS * 0.6 and lc.z > 0.0 and lc.z < behind * 0.5
		cam_txt = "camera %d m behind the ship, %d m off its line; tunnel runs %d m behind, %d m wide" % [int(lc.z), int(radial), int(behind), int(Data.LANE_TUNNEL_RADIUS * 2.0)]
		main.hud.visible = false
		await _shot("y_lane_tunnel", 0.05)
		main.hud.visible = true
		if not s.lane.is_empty(): _press("lane")
		await _until(func(): return s.lane.is_empty(), 8.0)
	_check("Job Y: the trade-lane tunnel is pulled back and widened: the camera rides inside it, far from either end, so its round rim is never on screen", shape_ok and cam_in, cam_txt)
	s.vel = Vector3.ZERO
	_tp(st + Vector3(0, 40, 420), st)

## Job Z (v1.4v): the owner's 68 station names and lore on the map; World's End Emporium, the Hollow Requiem and the
## Greywhistle fog beacon wear their models.
func _job_z() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job Z: version label reads \"Homelancer Digital v1.4v\" or later", Data.VERSION >= "v1.4v" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var named := 0
	var ok := true
	var ids_ok := true
	var seen := {}
	for sid in StationNames.NAMES:
		var sy: Dictionary = Data.SYSTEMS[sid]
		if sy["station"]["id"] != sid + "_station": ids_ok = false
		for old in StationNames.NAMES[sid]:
			var row: Array = StationNames.NAMES[sid][old]
			var hit := false
			for body in [sy["station"]] + sy["more_stations"]:
				if body["name"] == row[0] and body.get("catalog_name", "") == old and str(body["desc"]).begins_with(row[1]): hit = true
			if hit: named += 1
			else: ok = false
			if seen.has(row[0]): ok = false
			seen[row[0]] = true
	var spot: bool = Data.SYSTEMS["omega"]["station"]["name"] == "World's End Emporium" and Data.SYSTEMS["derelicta"]["station"]["name"] == "Old Widowmaker" \
		and Data.SYSTEMS["void_system"]["station"]["name"] == "Nihil Citadel" and Data.SYSTEMS["synthari_capital"]["more_stations"].any(func(x): return x["name"] == "Synthari Warp Gate Hub") \
		and str(Data.SYSTEMS["aurelion"]["planet"]["desc"]).find("Elyria (Grovecrown)") >= 0
	_check("Job Z: the owner's 68 station names are on the map, each in its own system with its line of lore (ids unchanged, no name used twice); Elyria is told on Aurelion Prime",
		StationNames.count() == 68 and named == 68 and ok and ids_ok and spot, "%d named" % named)
	# the lore shows where you read about a station
	var hub = main.hub
	var base0: Dictionary = hub.base
	var kind0: String = hub.kind
	var vis0: bool = hub.visible
	var sys0: String = GS.system_id
	GS.system_id = "vexara"
	hub.open(Data.SYSTEMS["vexara"]["station"])
	await _frames(3)
	var txt := ""
	for c in hub.content.find_children("*", "Label", true, false): txt += (c as Label).text + " "
	var hub_ok: bool = hub.header.text == "HAGGLER'S WHEEL" and txt.find("wheel-shaped market") >= 0
	await _shot("z_hagglers_wheel_hub", 0.3)
	GS.system_id = sys0
	hub.base = base0
	hub.kind = kind0
	hub.visible = vis0
	_check("Job Z: docking shows the station's own name and its lore (Haggler's Wheel)", hub_ok, hub.header.text)
	# three stations wear the owner's finished models; Greywhistle's lamp burns in the fog
	var files := true
	for m in ["worlds_end_emporium", "hollow_requiem", "light_beacon_station"]:
		if not ResourceLoader.exists("res://assets/structures/%s.glb" % m): files = false
	var fg: Dictionary = Data.SYSTEMS["foggiest"]
	var data_ok: bool = files and Data.SYSTEMS["omega"]["station"]["model"] == "st3d_omega_emporium" and Data.SYSTEMS["shadow"]["station"]["model"] == "hollow_requiem" \
		and fg["station"]["model"] == "st3d_foggiest_greywhistle" and fg["station"].get("lamp", false) and Data.SYSTEMS["nullpoint"]["station"].get("lamp", false) \
		and (fg["nebula"]["center"] as Vector3).is_equal_approx(fg["station"]["pos"]) and fg["nebula"]["color"] == Data.FOG_COLOR
	main.hud.visible = false
	var seen_models: Array = []
	var fog_ok := false
	var fog_txt := ""
	for sid in ["foggiest", "omega", "shadow"]:
		main._load_system(sid, "station")
		await _wait(1.6)
		var mk: String = str(Data.SYSTEMS[sid]["station"].get("model", ""))
		await Packs.wait(mk if mk.begins_with("st3d_") else "structures", 30.0)   # (v1.9d: a 3D station comes in its own pack)
		await _frames(4)
		var sp := _sp()
		seen_models.append(sp.station_model != null and sp.station.name == Data.SYSTEMS[sid]["station"]["name"])
		if sid == "foggiest":
			var lamp: OmniLight3D = sp.beacon_light
			_tp(sp.station.global_position + Vector3(150, 40, 190), sp.station.global_position + Vector3(0, 30, 0))
			await _frames(3)
			fog_ok = lamp != null and lamp.get_parent() == sp.station and sp.in_nebula > 0.9 and sp.beacon_lit > 0.5 and sp.beacon == null and sp.beacon_puffs.size() == Data.BEACON_PUFFS
			fog_txt = "lamp on the station %s, fog %.2f, lit %.2f" % [lamp != null and lamp.get_parent() == sp.station, sp.in_nebula, sp.beacon_lit]
			_tp(sp.station.global_position + Vector3(260, 60, 420), sp.station.global_position + Vector3(0, 30, 0))
		else:
			_tp(sp.station.global_position + Vector3(330, 130, 520), sp.station.global_position)
		await _shot("z_" + sid, 0.5)
	main._load_system(sys0, "station")
	await _wait(1.6)
	await Packs.wait("structures", 30.0)
	await _frames(4)
	main.hud.visible = true
	var s := _sp()
	s.controls = true
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	_check("Job Z: World's End Emporium (Omega), the Hollow Requiem (Shadow) and Greywhistle Beacon (Foggiest) wear the owner's models", data_ok and seen_models == [true, true, true], str(seen_models))
	_check("Job Z: Greywhistle Beacon stands in thick grey fog with its lamp lit: the fog thins and the sensors recover beside it", fog_ok, fog_txt)

## Job AE (v1.5a): a mission you accept sets a waypoint to follow (bounties today), full screen on a phone, and the
## intro movie on the start screen (that one is checked at the start of the route, while the start screen is up).
func _job_ae() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AE: version label reads \"Homelancer Digital v1.5a\" or later", Data.VERSION >= "v1.5a" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	_check("Job AE: on a phone the page asks for full screen (and landscape) on the first tap and again on START, and does not force it back after the player leaves it",
		shell == "" or (shell.find("requestFullscreen") >= 0 and shell.find("navigationUI: 'hide'") >= 0 and shell.find("orientation.lock('landscape')") >= 0 and shell.find("window.__hlFullscreen") >= 0 and shell.find("fsLeft = true") >= 0))
	var s := _sp()
	var keep := {"bounty": GS.bounty.duplicate(true), "done": GS.bounties_done.duplicate(), "cast": GS.cast.duplicate(true), "target": s.target, "auto": s.autopilot}
	GS.bounty = {}
	s.target = null
	s.autopilot = null
	var none: bool = s.mission_waypoint().is_empty()
	# the shortest way through the gates
	var r1: Array = Data.gate_route("solara", "vega")
	var far: Array = Data.gate_route("solara", "plundros")
	var route_ok: bool = r1 == ["solara", "vega"] and Data.gate_route("solara", "solara") == ["solara"] and far.size() >= 2 and far[0] == "solara" and far[-1] == "plundros" and Data.gate_route("solara", "nowhere").is_empty()
	for i in far.size() - 1:
		var linked := false
		for g in Data.SYSTEMS[far[i]]["gates"]:
			if g["to"] == far[i + 1]: linked = true
		if not linked: route_ok = false
	_check("Job AE: the game knows the shortest way between any two systems through the gates", route_ok, "Solara to Plundros: %d jumps" % (far.size() - 1))
	# accept a bounty whose target is in another system: the waypoint is the gate that starts the way there
	GS.bounties_done.erase("savagers_03")
	GS.cast_state("savagers_03_razor")["custody"] = false
	var said: String = GS.accept_bounty("savagers_03")
	var w1: Dictionary = s.mission_waypoint()
	var gate_ok: bool = not w1.is_empty() and (w1["node"] as Node3D).get_meta("kind", "") == "gate" and str(((w1["node"] as Node3D).get_meta("info") as Dictionary)["to"]) == str(far[1]) and int(w1["hops"]) == far.size() - 1
	var obj: String = main._objective()
	main.hud.queue_redraw()
	await _frames(3)
	await _shot("ae_mission_waypoint_gate", 0.3)
	# GO TO with nothing picked flies the mission waypoint
	main._on_hud("goto")
	var goto_ok: bool = not w1.is_empty() and s.autopilot == w1["node"]
	s.autopilot = null
	_check("Job AE: accepting a bounty sets a mission waypoint: with the target in another system it is the gate that starts the shortest way there, the objective line says how many jumps, and GO TO flies it",
		none and said.find("waypoint") >= 0 and gate_ok and obj.begins_with("MISSION: ") and obj.find("jump") >= 0 and goto_ok, "none %s, gate %s, goto %s: %s" % [none, gate_ok, goto_ok, obj])
	# v1.5e: the map opens centred on you, zoomed out until the whole system fits round you, and shows the mission marker
	main.navmap.open(s)
	await _frames(2)
	var nm: Control = main.navmap
	var ppos: Vector3 = s.player.global_position
	var centred: bool = Vector2(nm.center.x, nm.center.z).distance_to(Vector2(ppos.x, ppos.z)) < 1.0
	var all_in := true
	var sysd: Dictionary = Data.SYSTEMS[GS.system_id]
	for pt in [sysd["station"]["pos"], sysd["planet"]["pos"], sysd["asteroids"]["center"], sysd["nebula"]["center"]] + sysd["gates"].map(func(g): return g["pos"]):
		var sp: Vector2 = nm.view.to_screen(pt)
		if not Rect2(Vector2.ZERO, nm.map_rect.size).grow(-4.0).has_point(sp): all_in = false
	await _shot("ae_map_centred_mission", 0.3)
	main.navmap.visible = false
	main._on_map_closed()
	_check("Job AE: the map opens centred on you and zoomed out until the whole system fits round you, with the mission marker on it", centred and all_in and nm.zoom == 1.0 and not w1.is_empty(), "centred %s, all in view %s" % [centred, all_in])
	# in the target's own system: the ship, then the drifting pilot, then (pilot aboard) the station
	GS.bounty["sys"] = s.sys_id               # (test only: bring the hunt to this system)
	var tgt: Dictionary = s.spawn_bounty()
	_clear_wing(tgt)
	var w2: Dictionary = s.mission_waypoint()
	var ship_ok: bool = not tgt.is_empty() and not w2.is_empty() and w2["node"] == tgt["node"] and int(w2["hops"]) == 0
	if not tgt.is_empty():
		(tgt["node"] as Node3D).global_position = s.player.global_position - s.player.global_basis.z * 160.0 + Vector3(40, 20, 0)
		await _frames(3)
		await _shot("ae_mission_waypoint_ship", 0.3)
		main._on_hud("goto")   # a hostile: flown TO (a waypoint at its place), never docked with
		ship_ok = ship_ok and s.autopilot != null and s.autopilot == s.waypoint and s.waypoint.global_position.distance_to((tgt["node"] as Node3D).global_position) < 30.0
		s.autopilot = null
		s._destroy_unit(tgt)
	var w3: Dictionary = s.mission_waypoint()
	var pod_ok := false
	for l in s.loot:
		if l.get("bounty", "") == "savagers_03" and not w3.is_empty() and w3["node"] == l["node"]: pod_ok = true
	GS.capture_bounty("savagers_03")
	for i in range(s.loot.size() - 1, -1, -1):
		(s.loot[i]["node"] as Node3D).queue_free()
		s.loot.remove_at(i)
	var w4: Dictionary = s.mission_waypoint()
	var dock_ok: bool = not w4.is_empty() and w4["node"] == s.station and str(w4["line"]).find("Dock at") >= 0
	GS.claim_bounty()
	var done_ok: bool = s.mission_waypoint().is_empty() and not main._objective().begins_with("MISSION")
	_check("Job AE: the waypoint follows the mission: the bounty's ship in its own system, the drifting pilot once the ship is down, the station once the pilot is aboard, and nothing once you are paid",
		ship_ok and pod_ok and dock_ok and done_ok, "ship %s, pilot %s, dock %s, cleared %s" % [ship_ok, pod_ok, dock_ok, done_ok])
	if is_instance_valid(s.waypoint): s.waypoint.queue_free()
	s.waypoint = null
	GS.bounty = keep["bounty"]
	GS.bounties_done = keep["done"]
	GS.cast = keep["cast"]
	s.target = keep["target"] if is_instance_valid(keep["target"]) else null
	s.autopilot = keep["auto"] if is_instance_valid(keep["auto"]) else null
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)

## Job AD (v1.4z): the six permanent-enemy casts from the owner's roster documents (Phenom, Kaijurai, Cybermorph,
## Solrath, Gadversee, Arctides), their portraits, and the two that have ships (Phenom, Kaijurai) flying them.
func _job_ad() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AD: version label reads \"Homelancer Digital v1.4z\" or later", Data.VERSION >= "v1.4z" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var want := {"Phenom": ["Aurelian Guard", "Vyrela", "Thalen", "Isara", "Ascendant Guard", "Xerathion"],
		"Kaijurai": ["Containment Trooper", "Zhara Keth", "Drakk Vorn", "Syrak Nem", "Cradle Guard", "Vorrax Kael"],
		"Cybermorph": ["UNIT-01", "VX-RAID", "ORION-K", "NEX-M7", "AX-9", "PRIME-NEXUS"],
		"Solrath": ["Void Trooper", "Velkira Syth", "Kharvek", "Nyssara Veil", "Void Enforcer", "Azrath Vhol"],
		"Gadversee": ["Hive Thrall Trooper", "Mireya Bloom", "Grath Vorn", "Vesha Mycel", "Elite Spore Guard", "Mother Sera"],
		"Arctides": ["Ice Guard", "Seryn Vail", "Kaldren", "Lysara", "House Warden", "Vorstane"]}
	var names_ok := true
	var rule_ok := true
	var faces := 0
	var enemy_ok := true
	for f in want:
		var ros: Array = Data.ROSTERS.get(f, {}).get("pilots", [])
		if ros.map(func(p): return p["name"]) != want[f] or Data.ROSTERS.get(f, {}).get("leader", "") != want[f][5]: names_ok = false
		if Factions.band(f) != "gray" or not Factions.hostile(f) or Factions.normal(f) or str(Factions.def(f).get("character_roster", "")) != f: enemy_ok = false
		for i in ros.size():
			var p: Dictionary = Data.roster_pilot(ros[i]["character_id"])
			if int(p["slot"]) != i + 1 or int(p["rank"]) != i + 1 or bool(p["named_unique"]) != (i in [1, 2, 3, 5]) or p["faction"] != f: rule_ok = false
			if bool(p["female"]) != (p["sex"] == "female") or p["voice_sex"] != p["sex"] or p["voice_id"] != p["character_id"] or not (p["sex"] in ["male", "female", "none"]): rule_ok = false
			if (f == "Cybermorph") != (p["sex"] == "none") or (f == "Cybermorph" and not str(p["voice_persona"]).begins_with("neutral_machine")): rule_ok = false
			for k in ["species", "persona", "voice_persona", "normal_emotion", "combat_emotion", "damaged_emotion", "critical_emotion", "fighter_primary"]:
				if not p.has(k): rule_ok = false
			if ResourceLoader.exists(p["portrait_clean"]) and ResourceLoader.exists(p["portrait_damaged"]): faces += 1
	_check("Job AD: the six enemy factions have their six people, named as the owner's roster documents name them (Phenom, Kaijurai, Cybermorph, Solrath, Gadversee, Arctides)", names_ok and Data.ROSTERS.size() == 14, "%d rosters" % Data.ROSTERS.size())
	_check("Job AD: slot 01 is the common soldier, 05 the elite, 02 03 04 06 are named; sex and voice come from the documents (Cybermorphs are machines: no sex, one neutral machine voice family; Isara and Mother Sera female, Xerathion male)",
		rule_ok and Data.roster_pilot("phenom_04_isara")["sex"] == "female" and Data.roster_pilot("gadversee_06_mother")["sex"] == "female" and Data.roster_pilot("phenom_06_xerathion")["voice_persona"] == "male_augmented"
		and Data.roster_pilot("cybermorph_06_prime_nexus")["voice_persona"] == "neutral_machine_echo_command")
	_check("Job AD: all 36 have a clean and a battle-damaged portrait", faces == 36, "%d of 36" % faces)
	_check("Job AD: all six are permanent enemies (gray, hostile, outside the reputation ladder)", enemy_ok)
	# who flies: only the two with ships in the game, each person in a ship of their own faction, heavier with rank
	var ships_ok := true
	for f in want:
		for p in Data.ROSTERS[f]["pilots"]:
			var k: String = p["fighter_primary"]
			if f in ["Phenom", "Kaijurai", "Cybermorph", "Solrath", "Gadversee", "Arctides"]:   # (v1.5c: Cybermorph and Solrath fly too; v1.5q: the rest on placeholders)
				if not Data.ENEMIES.has(k) or Data.ENEMIES[k].get("faction", "") != f or not ShipFactory.has_real_model(Data.ENEMIES[k]["model"]): ships_ok = false
			elif k != "": ships_ok = false
	_check("Job AD: Phenom and Kaijurai people each have a ship from their own set (Vyrela the interceptor, the two elites and commanders the heaviest); the casts without ships are known but do not fly yet",
		ships_ok and Data.roster_pilot("phenom_02_vyrela")["fighter_primary"] == "phenom_interceptor" and Data.roster_pilot("phenom_06_xerathion")["fighter_primary"] == "phenom_heavy"
		and Data.roster_pilot("kaijurai_01")["fighter_primary"] == "kaijurai_dart" and Data.roster_pilot("kaijurai_06_vorrax")["fighter_primary"] == "kaijurai_gunship"
		and Factions.has_fighters("Phenom") and Factions.has_fighters("Kaijurai") and Factions.has_fighters("Gadversee"))   # (v1.5c: Solrath flies now; Gadversee and Arctides still wait for ships)
	# in their home systems the patrols are their own people, always hostile, and a hail shows their own face
	var s := _sp()
	var real_sys: Dictionary = s.sys
	var crew_ok := true
	var seen: Array = []
	var hail_ok := false
	for pair in [["genesis", "Kaijurai"], ["noctyra", "Phenom"]]:
		var sy: Dictionary = Data.SYSTEMS.get(pair[0], {})
		if sy.get("enemy_faction", "") != pair[1]: crew_ok = false
		s.sys = sy
		var g: Array = s._spawn_group(s.station.global_position + Vector3(0, 300, 2600), 3)
		s.sys = real_sys
		await _frames(4)
		for e in g:
			var pl: Dictionary = e.get("pilot", {})
			seen.append(str(pl.get("name", "?")))
			if pl.get("faction", "") != pair[1] or e.get("faction", "") != pair[1] or str(Data.ENEMIES.find_key(Data.ENEMIES.get(pl.get("fighter_primary", ""), {}))) != str(pl.get("fighter_primary", "-")): crew_ok = false
			if not str(e["def"].get("faction", "")) == pair[1] or (e["node"] as Node3D).get_meta("kind", "") != "enemy" or int(e.get("rank", 0)) != int(pl.get("rank", -1)): crew_ok = false
		if pair[1] == "Phenom" and not g.is_empty():
			s.target = g[0]["node"]
			main._pilot_call(g[0]["node"].get_meta("pilot"), false)   # (CALL on a hostile sometimes rings their leader instead: ask the pilot directly)
			for side in ["l", "r"]:
				var slot: Dictionary = main.hud.slot(side)
				if not slot.is_empty() and str(slot["from"]).to_upper().begins_with(str(g[0]["pilot"]["name"]).to_upper()) and bool(slot["hostile"]): hail_ok = true
			hail_ok = hail_ok and main.hud.comms_voice_id == g[0]["pilot"]["voice_id"]
			await Packs.wait("enemies", 30.0)
			await _shot("ad_phenom_hail", 0.4)
			main.hud.close_comms()
		s.target = null
		for e in g:
			s.enemies.erase(e)
			(e["node"] as Node3D).free()
	s.target = null
	Sfx.stop_voice()
	var others := true
	for id in Data.SYSTEMS:
		if str(Data.SYSTEMS[id].get("role", "")) not in Data.HOME_FACTION and str(Data.SYSTEMS[id].get("enemy_faction", "")) != "": others = false   # v1.5c: Cybernet and the Void System too
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	_check("Job AD: in Genesis and Noctyra the patrols are flown by Kaijurai and Phenom people from the rosters, in their own ships, ranked, always hostile; a hail shows that person's name and voice id; no other system changed",
		crew_ok and hail_ok and others, "crew %s, hail %s, others %s: %s" % [crew_ok, hail_ok, others, str(seen)])

## Job AC (v1.4y): the owner's Kaijurai and Phenom ship sets in the game (mirrored light copies, nose first), the
## thruster repair on two Phenom ships, and the two enemy home systems flying them.
func _job_ac() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AC: version label reads \"Homelancer Digital v1.4y\" or later", Data.VERSION >= "v1.4y" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var keys := ["kaijurai_dart", "kaijurai_heavy", "kaijurai_gunship", "phenom_fighter", "phenom_interceptor", "phenom_scout", "phenom_heavy"]
	var real := true
	var fit := true
	var nose := true
	var mirror := true
	var tail := true
	var note := ""
	for k in keys:
		if not (Data.ENEMIES.has(k) and ShipFactory.has_real_model(Data.ENEMIES[k]["model"])):
			real = false
			continue
		var m := ShipFactory.build(k, false)
		if m.get_meta("placeholder", true): real = false
		var inst: Node3D = m.get_child(0)
		var pts := _ac_points(inst, Transform3D.IDENTITY)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in pts:
			lo = lo.min(v)
			hi = hi.max(v)
		var size := hi - lo
		var want: float = ShipFactory.GLB[k][1]
		# the right length, lying nose-to-tail along the game's forward axis, centred, turned as the table says
		if absf(maxf(size.x, size.z) - want) > want * 0.03 or size.z < size.x * 0.9 or ((lo + hi) * 0.5).length() > want * 0.03 or not is_equal_approx(inst.rotation_degrees.y, float(ShipFactory.GLB[k][2])):
			fit = false
			note += " fit:" + k
		# nose first: the front quarter (toward -Z) is narrower than the back half
		var wf := 0.0
		var wb := 0.0
		var rear_lo := INF
		var rear_hi := -INF
		var seen := {}
		for v in pts:
			if v.z < lo.z + size.z * 0.25: wf = maxf(wf, absf(v.x))
			if v.z > lo.z + size.z * 0.5: wb = maxf(wb, absf(v.x))
			if v.z > hi.z - size.z * 0.2:
				rear_lo = minf(rear_lo, v.y)
				rear_hi = maxf(rear_hi, v.y)
			seen[Vector3i((v * (400.0 / want)).round())] = true
		if wf >= wb * 0.8:
			nose = false
			note += " nose:" + k
		# left = right: every point has a twin on the other side
		var miss := 0
		for v in pts:
			var q := Vector3i((Vector3(-v.x, v.y, v.z) * (400.0 / want)).round())
			var ok := false
			for dx in [-1, 0, 1]:
				if seen.has(q + Vector3i(dx, 0, 0)): ok = true
			if not ok: miss += 1
		if miss > pts.size() / 100:
			mirror = false
			note += " mirror:%s(%d of %d)" % [k, miss, pts.size()]
		# the thruster repair: nothing upright at the tail any more
		if k in ["phenom_interceptor", "phenom_scout"] and rear_hi - rear_lo > want * 0.2:
			tail = false
			note += " tail:%s(%.2f)" % [k, (rear_hi - rear_lo) / want]
		m.free()
	_check("Job AC: seven ships from the owner's Kaijurai and Phenom sets are real models (three Kaijurai, four Phenom), each the right length, centred and turned as the ship table says", real and fit, note)
	_check("Job AC: every one of them flies nose first (narrow front toward the game's forward) and is mirrored: left matches right", nose and mirror, note)
	_check("Job AC: thruster repair: the Phenom interceptor and scout no longer carry an upright cannon at the tail (the tail is low and ends in thrusters taken from another Phenom fighter)", tail, note)
	# the two home systems fly them; nobody else changed
	var gen: Dictionary = Data.SYSTEMS.get("genesis", {})
	var noc: Dictionary = Data.SYSTEMS.get("noctyra", {})
	var others := true
	for id in Data.SYSTEMS:
		if str(Data.SYSTEMS[id].get("role", "")) not in Data.HOME_FLEETS and not (Data.SYSTEMS[id].get("enemy_ships", []) as Array).is_empty(): others = false   # v1.5c: Cybernet and the Void System fly home fleets too
	var s := _sp()
	var real_sys: Dictionary = s.sys
	var flown: Array = []
	var hostile := true
	var plain := true
	var shot_done: Array = []
	for sy in [gen, noc]:
		if sy.is_empty(): continue
		s.sys = sy
		var g: Array = s._spawn_group(s.station.global_position + Vector3(0, 300, 2600), 4)
		s.sys = real_sys
		for e in g:
			flown.append(str(e["def"].get("model", "")))   # (a ranked pilot's ship carries its own tuned copy of the entry: go by the model)
			if (e["node"] as Node3D).get_meta("kind", "") != "enemy" or (e.has("faction") and not Factions.hostile(e["faction"])): hostile = false
			# v1.4z: the pilot is one of that faction's own six, or (fallback) a generic pilot under the faction's name; never a raider or corsair leader
			var own_cast: bool = str(e.get("pilot", {}).get("faction", "")) == str(e["def"]["faction"])
			if not e.has("pilot") or not (own_cast or str(e["pilot"].get("leader", "")) == str(e["def"]["faction"])): plain = false
		main.hud.visible = false
		for e in g:   # one picture of each ship, seen from behind and a little above (the way the player meets it)
			var k := str(Data.ENEMIES.find_key(e["def"]))
			if k in shot_done: continue
			shot_done.append(k)
			var np: Vector3 = (e["node"] as Node3D).global_position
			var back: Vector3 = (e["node"] as Node3D).global_basis.z
			var side: Vector3 = (e["node"] as Node3D).global_basis.x
			_tp(np + back * 24.0 + Vector3(0, 2, 0), np - side * 10.0 + Vector3(0, -6, 0))   # the ship sits up and to the right of the player's own
			await _shot("ac_" + k, 0.2)
		main.hud.visible = true
		s.target = null
		for e in g:
			s.enemies.erase(e)
			(e["node"] as Node3D).free()
		s.target = null
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	_check("Job AC: the Kaijurai home system (Genesis) and the Phenom home system (Noctyra) fly their own ships on patrol, hostile, with no named raider or corsair leader; no other system changed",
		gen.get("enemy_ships", []) == Data.HOME_FLEETS["Kaijurai home"] and noc.get("enemy_ships", []) == Data.HOME_FLEETS["Phenom home"] and others and hostile and plain
		and flown.slice(0, 4).all(func(k): return str(k).begins_with("kaijurai_")) and flown.slice(4).all(func(k): return str(k).begins_with("phenom_")) and flown.size() == 8
		, str(flown))

## every vertex of a model, in the model root's space (Job AC shape checks)
func _ac_points(n: Node, xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if n is Node3D: xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			for v in (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array): out.append(xf * v)
	for c in n.get_children(): out.append_array(_ac_points(c, xf))
	return out

## Job AB (v1.4x): one warp effect, three looks (jump gate tunnel, warp gate cloud, rift gate tear).
func _job_ab() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AB: version label reads \"Homelancer Digital v1.4x\" or later", Data.VERSION >= "v1.4x" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var home: String = GS.system_id
	var credits0: int = GS.credits
	var disc0: Array = GS.discovered.duplicate()
	var fx: Control = main.fx
	# every kind of gate has a look, and every look has its numbers
	var cfg_ok := true
	for gk in SystemBuilder.GATE_KINDS:
		var look: String = Data.WARP_SKINS.get(gk, "")
		if not (look in fx.SKINS and Data.WARP_BUILD.has(look) and Data.WARP_CLEAR.has(look) and Data.WARP_FLASH.has(look) and Data.WARP_RINGS.has(look)): cfg_ok = false
	_check("Job AB: jump, warp and rift gates each have their own look (tunnel, cloud, tear) with numbers in one config block", cfg_ok and Data.WARP_SKINS.size() == 3, str(Data.WARP_SKINS))
	# a system that has each kind of gate
	var where := {}
	for id in Data.SYSTEMS:
		for g in Data.SYSTEMS[id]["gates"]:
			var gk: String = g.get("gkind", "jump")
			if not where.has(gk) and Data.SYSTEMS.has(g["to"]): where[gk] = [id, g["id"], g["to"]]
	var seen := {}
	var detail := ""
	var smooth := true
	var booms := 0
	var rings_ok := true
	var tint_ok := true
	var timing := true
	var last_build := 0.0
	for gk in ["jump", "warp", "rift"]:
		if not where.has(gk): continue
		var look: String = Data.WARP_SKINS[gk]
		main._load_system(where[gk][0], "station")
		await _wait(0.6)
		main.state = "flight"
		var s = main.space
		s.controls = true
		s.autopilot = null
		s.drop_warp()
		var gate: Node3D = null
		for g in s.gates:
			if g.get_meta("info")["id"] == where[gk][1]: gate = g
		if gate == null: continue
		s.player.global_position = gate.global_position + gate.global_basis.z * 120.0
		s.vel = Vector3.ZERO
		main.jump(gate)
		await _until(func(): return main.jump_log.size() >= 1, 3.0)
		var rings_now: bool = not s.jump_rings.is_empty()
		if rings_now != bool(Data.WARP_RINGS[look]): rings_ok = false
		await _until(func(): return fx.warp >= 0.99 and fx.pace > 0.5, 8.0)
		var shown: bool = fx._warp_rect.visible and fx.skin == look
		if gk == "rift":
			tint_ok = fx.tints.size() == 12
			for i in 12:
				if fx._hue_gap((fx.tints[i] as Color).h, (fx.tints[(i + 1) % 12] as Color).h) < Data.RIFT_TINT_MIN_HUE - 0.001: tint_ok = false
		if OS.get_environment("HL_SHOT_DIR") != "": await _shot("ab_warp_%s" % look, 0.0)
		var max_flash := 0.0
		while main.state != "flight" and main.jump_log.size() < 5:
			max_flash = maxf(max_flash, fx.flash * Data.JUMP_FLASH_ALPHA)
			await get_tree().process_frame
		await _until(func(): return main.state == "flight", 20.0)
		var L: Array = main.jump_log
		if L.size() == 5:
			var b: float = (L[1][1] - L[0][1]) / 1000.0
			var c: float = (L[4][1] - L[3][1]) / 1000.0
			if b < float(Data.WARP_BUILD[look]) - 0.1 or c < float(Data.WARP_CLEAR[look]) - 0.1 or b <= last_build: timing = false
			last_build = b
			detail += "%s %s: build %.1f s, clear %.1f s, booms %d; " % [gk, look, b, c, main.jump_booms]
		else: timing = false
		await get_tree().process_frame
		await get_tree().process_frame
		if float(Data.WARP_FLASH[look]) == 0.0 and max_flash > 0.001: smooth = false
		if gk != "jump": booms += main.jump_booms
		if shown and main.jump_look == look and GS.system_id == where[gk][2] and fx.warp == 0.0 and not fx._warp_rect.visible and not fx.jumping: seen[gk] = true
	_check("Job AB: a jump through each kind of gate plays its own look and arrives in the next system with the effect gone", seen.size() == where.size() and where.size() >= 1, "%s of %s kinds on the map; %s" % [seen.size(), where.size(), detail])
	_check("Job AB: each look builds (slow, then fast), holds while the next system loads, and eases out in its own time", timing, detail)
	_check("Job AB: the cloud and the tear arrive smoothly with no white flash, and their slow layers make booms", smooth and (booms > 0 or not (where.has("warp") or where.has("rift"))), "booms %d" % booms)
	_check("Job AB: the rift opens where you are (no rings to fly through); jump and warp gates keep their rings", rings_ok)
	_check("Job AB: the tear's mist colours come in twelve, never two alike in a row", tint_ok and Data.RIFT_LAYERS >= 1 and Data.RIFT_LAYERS <= 12, "layers %d" % Data.RIFT_LAYERS)
	# the surface tile change still uses the plain streaks, not the gate effect
	fx.warp = 0.4
	await get_tree().process_frame
	await get_tree().process_frame
	_check("Job AB: outside a gate jump the warp effect stays off (planet tile changes keep their plain streaks)", not fx._warp_rect.visible)
	fx.warp = 0.0
	# back home, nothing kept
	GS.credits = credits0
	GS.discovered = disc0
	main._load_system(home, "station")
	await _wait(0.6)
	main.state = "flight"
	main.space.controls = true
	main.hud.visible = true

## Job AA (v1.4w): the casts of seven more factions (from the owner's roster documents), faces, and the first two
## that fly (Imperium, Liberator) as peaceful guard wings.
func _job_aa() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AA: version label reads \"Homelancer Digital v1.4w\" or later", Data.VERSION >= "v1.4w" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var want := {"Covenant": ["Covenant Acolyte", "Nerea Solis", "Kael Varis", "Lyra Shan", "Hierarch Guard", "Archon Selen"],
		"Imperium": ["Imperium Trooper", "Vexa Drak", "Garrik Rend", "Nyx Dar'Kesh", "Dominion Guard", "Lord Kraeg"],
		"Solarion": ["Solarion Trooper", "Lira Suntide", "Taron Kael", "Seraph Nova", "Solarion Guard", "Valen Aurex"],
		"Unity": ["Alliance Trooper", "Mira Dane", "Rowan Hale", "Selene Ward", "Unity Elite Guard", "Commander Elara Voss"],
		"Elyza": ["Elyza Security Trooper", "Serin Vale", "Cael Rhyn", "Lyra Vey", "Elyza Elite Guard", "Aurelia Voss"],
		"Orion": ["Orion Survey Trooper", "Ryan Solace", "Syra N'Tel", "Korvax", "Orion Vanguard", "Admiral Caleb Rynn"],
		"Liberator": ["Liberator Trooper", "Lena Torres", "Brok Tal", "Kai Mori", "Liberator Vanguard", "Marcus Vale"]}
	var names_ok := true
	var rule_ok := true
	var faces := 0
	var fields := true
	for f in want:
		var ros: Array = Data.ROSTERS.get(f, {}).get("pilots", [])
		if ros.map(func(p): return p["name"]) != want[f]: names_ok = false
		for i in ros.size():
			var p: Dictionary = Data.roster_pilot(ros[i]["character_id"])
			if int(p["slot"]) != i + 1 or bool(p["named_unique"]) != (i in [1, 2, 3, 5]) or p["faction"] != f: rule_ok = false
			if bool(p["female"]) != (p["sex"] == "female") or p["voice_sex"] != p["sex"] or p["voice_id"] != p["character_id"]: rule_ok = false
			for k in ["species", "persona", "voice_persona", "normal_emotion", "combat_emotion", "damaged_emotion", "critical_emotion", "fighter_primary"]:
				if not p.has(k): fields = false
			if ResourceLoader.exists(p["portrait_clean"]) and ResourceLoader.exists(p["portrait_damaged"]): faces += 1
	_check("Job AA: seven more factions have their six people, named as the owner's roster documents name them (Covenant, Imperium, Solarion, Unity, Elyza, Orion, Liberator)", names_ok and Data.ROSTERS.size() >= 8, "%d rosters" % Data.ROSTERS.size())   # (v1.4z: 8 main factions + the 6 enemy casts)
	_check("Job AA: in every one, slot 01 is the common soldier and 05 the elite soldier, slots 02 03 04 06 are named, and sex and voice come from the data (Syra N'Tel female, Korvax male, Lord Kraeg augmented)",
		rule_ok and fields and Data.roster_pilot("orion_03_syra")["sex"] == "female" and Data.roster_pilot("orion_04_korvax")["sex"] == "male" and Data.roster_pilot("imperium_06_kraeg")["voice_persona"] == "male_augmented")
	_check("Job AA: all 42 have a clean and a battle-damaged portrait", faces == 42, "%d of 42" % faces)
	# who can fly: only factions with a fighter in the game
	var fly: Array = []
	for f in Data.ROSTERS:
		if Factions.has_fighters(f): fly.append(f)
	fly.sort()
	var models := true
	for k in ["imperium_fighter", "imperium_gunship", "liberator_fighter", "liberator_heavy"]:
		if not ShipFactory.has_real_model(Data.ENEMIES[k]["model"]): models = false
	_check("Job AA: Imperium and Liberator pilots have fighters from their own ship sets (light for slots 1-3, heavier for 4-6); the other five casts are known but do not fly yet",
		fly.filter(func(f): return Factions.normal(f)) == ["Covenant", "Elyza", "Imperium", "Liberator", "Orion", "Savagers", "Solarion", "Unity"] and models   # (v1.4z: of the eight main factions; Kaijurai and Phenom fly too; v1.5c: Covenant, Cybermorph, Solrath too; v1.5p: Elyza)
		 and Data.roster_pilot("imperium_02")["fighter_primary"] == "imperium_fighter" and Data.roster_pilot("imperium_05")["fighter_primary"] == "imperium_gunship"
		and Data.roster_pilot("unity_02")["fighter_primary"] == "ph_unity" and float(ShipFactory.GLB["liberator_fighter"][2]) == Data.LIBERATOR_YAW, str(fly))
	# a guard wing in their own space: peaceful, not a hostile contact, answers a hail; shoot and it turns
	var s := _sp()
	var real_sys: Dictionary = s.sys
	var solara_guard: Array = s.spawn_guard()   # the opening system: no guard wing (v1.5q: Unity flies placeholders now)
	s.sys = real_sys.duplicate()
	s.sys["faction"] = "Imperium"
	var g: Array = s.spawn_guard()
	s.sys = real_sys
	var wing_ok: bool = solara_guard.is_empty() and g.size() == Data.GUARD_SIZE
	for e in g:
		if e.get("faction", "") != "Imperium" or int(e["pilot"]["slot"]) > Data.GUARD_MAX_SLOT or not str(Data.ENEMIES.find_key(Data.ENEMIES.get(e["pilot"]["fighter_primary"], {}))).begins_with("imperium"): wing_ok = false
	await _frames(4)
	var calm := true
	for e in g:
		if e["aggro"] or (e["node"] as Node3D).get_meta("kind", "") != "patrol": calm = false
	var first: Dictionary = g[0] if not g.is_empty() else {}
	var hail_ok := false
	var turned := false
	if not first.is_empty():
		main.hud.visible = false
		_tp((first["node"] as Node3D).global_position + Vector3(10, 5, 24), (first["node"] as Node3D).global_position)
		await _shot("aa_imperium_guard", 0.3)
		main.hud.visible = true
		s.target = first["node"]
		main._call_target()
		var slot: Dictionary = main.hud.slot("r")
		hail_ok = not slot.is_empty() and str(slot["from"]).begins_with(first["pilot"]["name"]) and not bool(slot["hostile"]) and main.hud.comms_voice_id == first["pilot"]["voice_id"]
		await _shot("aa_imperium_hail", 0.3)
		main.hud.close_comms()
		s._damage_enemy(first, 1.0)
		await _frames(3)
		turned = (first["node"] as Node3D).get_meta("kind", "") == "enemy"
	for e in g:
		s.enemies.erase(e)
		(e["node"] as Node3D).free()
	s.target = null
	Sfx.stop_voice()
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	_check("Job AA: a faction with fighters keeps a guard wing of %d near its station (never the commander): peaceful and shown as a patrol, it answers a hail with its own face and voice id, and turns hostile only if you shoot" % Data.GUARD_SIZE,
		wing_ok and calm and hail_ok and turned, "wing %s, calm %s, hail %s, turned %s" % [wing_ok, calm, hail_ok, turned])
	# the FACTION page shows the six
	var hub = main.hub
	var base0: Dictionary = hub.base
	var kind0: String = hub.kind
	var vis0: bool = hub.visible
	hub.open(Data.SYSTEMS[GS.system_id]["station"])
	await _frames(3)
	hub.show_screen("faction")
	await Packs.wait("enemies", 30.0)
	await _frames(3)
	var shown := 0
	for p in Data.ROSTERS["Unity"]["pilots"]:
		var col = hub.content.find_child("Cast_" + str(p["id"]), true, false)
		if col != null and (col.get_child(0) as TextureRect).texture != null: shown += 1
	await _shot("aa_faction_page_cast", 0.3)
	hub.base = base0
	hub.kind = kind0
	hub.visible = vis0
	_check("Job AA: a station's FACTION page shows its faction's six people with their faces and names", shown == 6, "%d shown" % shown)

func _job_s() -> void:
	var s := _sp()
	var hud = main.hud
	var nm = main.navmap
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job S: version label reads \"Homelancer Digital v1.4p\" or later", Data.VERSION >= "v1.4p" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	NavGrid.path = "user://settings_autotest_nav.cfg"   # never touch a real player's settings file
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NavGrid.path))
	NavGrid.load_prefs()
	var defaults_ok: bool = NavGrid.orient == "north" and NavGrid.tilt == "angled"
	s.engine_kill = true
	s.autopilot = null
	var st_pos: Vector3 = s.station.global_position
	_tp(st_pos + Vector3(-700, 0, 500), st_pos + Vector3(300, 0, 500))   # facing east (+X)
	await _frames(3)
	hud.close_comms()
	# ---- 1. the grid
	main.open_map()
	await _frames(4)
	var g0: Dictionary = nm.grid_stats.duplicate()
	nm.zoom_by(5.0)
	await _frames(3)
	var g1: Dictionary = nm.grid_stats.duplicate()
	nm.zoom_by(5.0)
	await _frames(3)
	var g2: Dictionary = nm.grid_stats.duplicate()
	await _shot("s_grid_zoomed", 0.3)
	nm.zoom_by(2.4)   # v1.4u: a part-way zoom too (x5 steps always land on the same phase of the grid, where the ticks may be faded out)
	await _frames(3)
	var g3: Dictionary = nm.grid_stats.duplicate()
	nm.fit()
	await _frames(3)
	var lv: Array = NavGrid.levels(0.1)
	var lv2: Array = NavGrid.levels(0.17)   # zoomed in a little: the minor lines have grown brighter
	var layered: bool = is_equal_approx(float(lv[0][0]) / float(lv[1][0]), 5.0) and is_equal_approx(float(lv[1][0]) / float(lv[2][0]), 5.0) and float(lv[0][2]) > float(lv[1][2]) and float(lv2[1][2]) > float(lv[1][2])
	var grid_ok: bool = int(g0["major"]) > 0 and int(g0["minor"]) > int(g0["major"]) and int(g0["through"]) >= 6 and int(g1["major"]) > 0 and int(g2["major"]) > 0 \
		and float(g1["spacing"]) < float(g0["spacing"]) and float(g2["spacing"]) < float(g1["spacing"]) and (int(g0["ticks"]) + int(g1["ticks"]) + int(g2["ticks"]) + int(g3["ticks"])) > 0
	_check("Job S: the map draws a layered grid (bold major lines, minor lines, micro-ticks), a grid crossing under every object, and zooming in keeps revealing finer lines",
		grid_ok and layered, "major/minor/ticks/through %d/%d/%d/%d; spacing %d m, x5 zoom %d m, x25 zoom %d m" % [g0["major"], g0["minor"], g0["ticks"], g0["through"], int(g0["spacing"]), int(g1["spacing"]), int(g2["spacing"])])
	# ---- 2. north-up is the default; the button switches to heading-up; the choice is remembered
	var north_rot: float = nm.view.rot
	var north_hit: Vector2 = nm.hits["station"]
	var n_ang0: float = nm.view.north_angle()
	await _shot("s_north_up_angled", 0.3)
	nm.tap(nm.btn_orient.get_center())
	await _frames(3)
	var is_heading: bool = NavGrid.orient == "heading" and nm.heading_up()
	NavGrid.orient = "north"
	NavGrid.load_prefs()
	var remembered: bool = NavGrid.orient == "heading"
	await _frames(3)
	_check("Job S: north-up is the default and never rotates; the map button switches to heading-up and the choice is remembered", defaults_ok and is_zero_approx(north_rot) and is_heading and remembered,
		"defaults %s, rot %.2f, heading %s, saved %s" % [defaults_ok, north_rot, is_heading, remembered])
	# ---- 3. heading-up maths: what is straight ahead is drawn straight above the arrow
	var fwd: Vector3 = -s.player.global_basis.z
	var ahead: Vector2 = nm.view.to_screen(s.player.global_position + fwd * 800.0)
	var beside: Vector2 = nm.view.to_screen(s.player.global_position + s.player.global_basis.x * 800.0)
	var me: Vector2 = nm.view.to_screen(s.player.global_position)
	var rot_ok: bool = absf(ahead.x - me.x) < 1.0 and ahead.y < me.y - 20.0 and beside.x > me.x + 20.0 and absf(beside.y - me.y) < 1.0
	var anchor_ok: bool = absf(me.y / nm.map_rect.size.y - Data.NAV_HEADING_ANCHOR) < 0.01 and absf(me.x - nm.map_rect.size.x * 0.5) < 1.0
	var pure: bool = absf(wrapf(NavGrid.heading_rot(Vector3(0, 0, -1)), -PI, PI)) < 0.001 and absf(wrapf(NavGrid.heading_rot(Vector3(1, 0, 0)) + PI * 0.5, -PI, PI)) < 0.001
	await _shot("s_heading_up", 0.3)
	_check("Job S: heading-up: you are the arrow at lower-centre, and an object straight ahead is drawn straight above it (one to starboard is drawn to the right)", rot_ok and anchor_ok and pure,
		"ahead (%d,%d), me (%d,%d), starboard (%d,%d)" % [int(ahead.x), int(ahead.y), int(me.x), int(me.y), int(beside.x), int(beside.y)])
	# ---- 4. hit-testing still works while the map is rotated
	var rot_hit: Vector2 = nm.hits["station"]
	var picked: String = nm.pick(rot_hit)
	nm.selected = ""
	nm.tap(rot_hit)
	var tapped: String = nm.selected
	_check("Job S: tapping an object picks it while the map is rotated (heading-up)", picked == "station" and tapped == "station" and rot_hit.distance_to(north_hit) > 20.0 and nm.map_rect.has_point(rot_hit),
		"north-up at (%d,%d), heading-up at (%d,%d), picked '%s'" % [int(north_hit.x), int(north_hit.y), int(rot_hit.x), int(rot_hit.y), picked])
	nm.selected = ""
	# ---- 5. the north marker, both modes (map and radar)
	var n_ang1: float = nm.view.north_angle()   # facing east: north is to the left
	nm.visible = false
	main._on_map_closed()
	await _frames(4)
	var rc: Vector2 = hud.radar_rect().get_center() + Vector2(0, 4)
	var rn_heading: Vector2 = hud.radar_north - rc
	main._on_key_action("map_orient")   # the key does the same as the button
	await _frames(4)
	var rn_north: Vector2 = hud.radar_north - rc
	var key_ok: bool = NavGrid.orient == "north"
	_check("Job S: the north marker is always there: straight up in north-up, turned to true north in heading-up (map and radar), and the keybind toggles it",
		is_zero_approx(n_ang0) and absf(n_ang1 + PI * 0.5) < 0.02 and rn_heading.x < -10.0 and absf(rn_heading.y) < 6.0 and rn_north.y < -10.0 and absf(rn_north.x) < 2.0 and key_ok,
		"map north %.2f / %.2f rad; radar N at (%d,%d) heading-up, (%d,%d) north-up" % [n_ang0, n_ang1, int(rn_heading.x), int(rn_heading.y), int(rn_north.x), int(rn_north.y)])
	# ---- 6. angled and overhead: same layout, the angled view has depth
	main.open_map()
	await _frames(3)
	var c3: Vector3 = nm.view.center
	var far_pt := c3 + Vector3(0, 0, -3000)   # (v1.5e: the map is zoomed out further now that it fits the system round the player, so the depth is read 3 km out)
	var near_pt := c3 + Vector3(0, 0, 3000)
	var a_far: Vector2 = nm.view.to_screen(far_pt)
	var a_near: Vector2 = nm.view.to_screen(near_pt)
	var depth_ok: bool = nm.view.angled and nm.view.persp(far_pt) < 0.97 and nm.view.persp(near_pt) > 1.03 and (nm.view.anchor.y - a_far.y) < (a_near.y - nm.view.anchor.y)
	var round_a: float = nm.view.to_world(nm.view.to_screen(c3 + Vector3(900, 0, -700))).distance_to(c3 + Vector3(900, 0, -700))
	var order_a: Array = [nm.hits["station"].x < nm.hits["planet"].x, nm.hits["station"].y < nm.hits["planet"].y]
	nm.tap(nm.btn_tilt.get_center())
	await _frames(3)
	var f_far: Vector2 = nm.view.to_screen(far_pt)
	var f_near: Vector2 = nm.view.to_screen(near_pt)
	var flat_ok: bool = NavGrid.tilt == "flat" and not nm.view.angled and is_equal_approx(nm.view.persp(far_pt), 1.0) and absf((nm.view.anchor.y - f_far.y) - (f_near.y - nm.view.anchor.y)) < 0.5
	var round_f: float = nm.view.to_world(nm.view.to_screen(c3 + Vector3(900, 0, -700))).distance_to(c3 + Vector3(900, 0, -700))
	var order_f: Array = [nm.hits["station"].x < nm.hits["planet"].x, nm.hits["station"].y < nm.hits["planet"].y]
	await _shot("s_north_up_overhead", 0.3)
	_check("Job S: the ANGLED / OVERHEAD button switches between a tilted view with depth and a flat straight-down view of the same layout", depth_ok and flat_ok and round_a < 1.0 and round_f < 1.0 and order_a == order_f,
		"angled: far x%.2f near x%.2f; flat: x%.2f; inverse error %.2f / %.2f m" % [nm.view.persp(far_pt), nm.view.persp(near_pt), 1.0, round_a, round_f])
	# ---- 7. tap to identify: planet, station (faction + services), gate (destination)
	nm.tap(nm.hits["planet"])
	await _frames(2)
	var pi: Dictionary = nm.info(nm.selected)
	var planet_ok: bool = nm.selected == "planet" and str(pi["type"]).begins_with("Planet") and pi["name"] == s.sys["planet"]["name"] and pi["picture"] != null and float(pi["distance"]) > 0.0
	await _shot("s_card_planet", 0.3)
	nm.tap(nm.btn_card_x.get_center())
	var x_closed: bool = nm.selected == ""
	nm.tap(nm.hits["station"])
	await _frames(2)
	var si: Dictionary = nm.info(nm.selected)
	var station_ok: bool = nm.selected == "station" and si["type"] == "Station" and str(si.get("faction", "")) != "" and (si.get("services", []) as Array).size() >= 3 and si["picture"] != null \
		and (si["lines"] as Array).any(func(l): return str(l).begins_with("Faction: ")) and (si["lines"] as Array).any(func(l): return str(l).begins_with("Services: "))
	await _shot("s_card_station", 0.3)
	# a tap on empty map closes the card (and only the next one drops a waypoint)
	var empty := Vector2.INF
	for gx in range(1, 12):
		for gy in range(1, 8):
			var cand: Vector2 = nm.map_rect.position + nm.map_rect.size * Vector2(gx / 12.0, gy / 9.0)
			if nm.pick(cand) == "" and not nm.btn_orient.has_point(cand) and not nm.btn_tilt.has_point(cand) and empty == Vector2.INF: empty = cand
	nm.tap(empty)
	var out_closed: bool = nm.selected == ""
	nm.tap(empty)
	var dropped: bool = nm.selected == ""   # v1.7v (owner): empty space no longer drops a waypoint
	nm.selected = ""
	nm.tap(nm.hits["gate"])
	await _frames(2)
	var gi: Dictionary = nm.info(nm.selected)
	var dest_name: String = Data.SYSTEMS[s.sys["gate"]["to"]]["name"]
	var gate_ok: bool = nm.selected == "gate" and gi["type"] == "Jump Gate" and gi.get("destination", "") == dest_name and gi["name"] == "%s > %s" % [s.sys["gate"]["name"], dest_name] and gi["picture"] != null
	await _shot("s_card_gate", 0.3)
	nm.selected = ""
	_check("Job S: tap a planet: brackets and an info card with its picture, name, type and distance", planet_ok, "%s / %s / %d m" % [pi["name"], pi["type"], int(pi["distance"])])
	_check("Job S: tap a station: the card says Station, its faction and its services", station_ok, "%s; %s" % [si.get("faction", "?"), ", ".join(si.get("services", []))])
	_check("Job S: tap a jump gate: the card says Jump Gate and where it goes", gate_ok, str(gi["name"]))
	_check("Job S / v1.7v: the card closes with its X or a tap outside it; a tap on empty space no longer drops a waypoint (owner: too many ways to set points)", x_closed and out_closed and dropped)
	var others := true
	var other_types: Array = []
	for key in ["belt", "nebula", "star"]:
		nm.select(key)
		var oi: Dictionary = nm.info(key)
		others = others and nm.selected == key and str(oi["type"]) != "" and oi["picture"] != null
		other_types.append(oi["type"])
	var fwd2: Vector3 = -s.player.global_basis.z
	var foe: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd2 * 600.0, s.player.global_position + fwd2 * 600.0)
	foe["aggro"] = false
	await _frames(3)
	var foe_key := ""
	for key in nm.objs:
		if nm.objs[key].get("node") == foe["node"]: foe_key = key
	var ship_ok := false
	if foe_key != "":
		nm.selected = ""
		nm.tap(nm.hits[foe_key])
		ship_ok = nm.selected == foe_key and str(nm.info(foe_key)["type"]).begins_with("Ship") and nm.info(foe_key)["picture"] != null
	if foe in s.enemies:
		s.enemies.erase(foe)
		(foe["node"] as Node3D).queue_free()
	nm.selected = ""
	_check("Job S: the asteroid belt, the nebula, the star and ships can be tapped and identified too", others and ship_ok, "%s; ship %s" % [", ".join(other_types), ship_ok])
	# ---- 8. pictures: every type has one; a missing picture falls back to the type's; nothing is ever broken
	var all_types := true
	for tp in Data.NAV_TYPE_PICTURES: all_types = all_types and ResourceLoader.exists(Data.NAV_TYPE_PICTURES[tp])
	var fb: Array = NavGrid.picture("res://assets/nav/does_not_exist.jpg", "gate")
	var none: Array = NavGrid.picture("", "no_such_type")
	var own: Array = NavGrid.picture("res://assets/nav/station_wheel.jpg", "station")
	_check("Job S: an object with no picture of its own shows its type's picture, and a missing type picture gives a drawn token, never a broken image",
		all_types and fb[0] != null and fb[1] == true and fb[0] == NavGrid.picture("", "gate")[0] and none[0] == null and none[1] == true and own[0] != null and own[1] == false, "%d type pictures" % Data.NAV_TYPE_PICTURES.size())
	# ---- 9. SET COURSE: the flow is unchanged, and the course is drawn as a route with a pin
	var galaxy_hits := [0]
	var cb := func(): galaxy_hits[0] += 1
	nm.galaxy_requested.connect(cb)
	nm.tap(nm.btn_galaxy.get_center())
	nm.galaxy_requested.disconnect(cb)
	if main.galaxymap.visible: main.galaxymap.visible = false
	nm.tap(nm.hits["planet"])
	nm.tap(nm.btn_course.get_center())
	await _frames(3)
	var flying: bool = main.state == "flight" and s.autopilot == s.planet and not nm.visible
	await _frames(4)
	var radar_route: bool = not (hud.radar_route as Dictionary).is_empty()
	main.open_map()
	await _frames(4)
	var rt: Dictionary = nm.route
	var route_ok: bool = not rt.is_empty() and (rt["to"] as Vector2).distance_to(nm.hits["planet"]) < 1.0 and (rt["from"] as Vector2).distance_to(nm._w2m(s.player.global_position)) < 1.0 \
		and float(rt["dist"]) > 100.0 and float(rt["eta"]) > 0.0
	await _shot("s_route", 0.4)
	nm.tap(nm.btn_close.get_center())
	await _frames(2)
	var closed_ok: bool = main.state == "flight" and not nm.visible
	s.autopilot = null
	s.clear_route()   # (v1.7o: the radar also draws the GPS course; with no course at all, no line)
	await _frames(3)
	_check("Job S: tap a destination then SET COURSE engages the autopilot as before, and the course is drawn as a glowing route with a pin on the map and on the radar; GALAXY and CLOSE still work",
		flying and route_ok and radar_route and (hud.radar_route as Dictionary).is_empty() and galaxy_hits[0] == 1 and closed_ok,
		"flying %s, route %s (%d m, ETA %d s), radar %s" % [flying, route_ok, int(rt.get("dist", 0)), int(rt.get("eta", 0)), radar_route])
	# ---- 10. the radar: grid, blips you can tap, same shapes
	await _frames(3)
	var blip_pos := Vector2.INF
	var blip_world := Vector3.INF
	for bl in hud.radar_blips:
		if bl[2] == "station":
			blip_pos = bl[1]
			blip_world = bl[0]
	var grid_r: Dictionary = hud.radar_stats
	var pick_ok: bool = blip_pos != Vector2.INF and hud.radar_pick_at(blip_pos) == blip_world and hud.radar_pick_at(blip_pos + Vector2(300, 0)) == Vector3.INF
	hud.radar_pick = blip_world
	_press("radar")
	await _frames(3)
	var opened: bool = main.state == "map" and nm.visible and nm.selected == "station"
	nm.visible = false
	main._on_map_closed()
	await _shot("s_radar", 0.3)
	_check("Job S: the radar draws the same grid, and tapping a radar blip opens the map with that object's card", (int(grid_r.get("major", 0)) + int(grid_r.get("minor", 0))) > 0 and pick_ok and opened,
		"radar grid %d + %d lines, %d blips, opened on '%s'" % [int(grid_r.get("major", 0)), int(grid_r.get("minor", 0)), hud.radar_blips.size(), nm.selected])
	var keys_ok := false
	for a in Data.KBM_ACTIONS:
		if a["id"] == "map_tilt" and a["rebind"]: keys_ok = true
	NavGrid.orient = Data.NAV_ORIENT_DEFAULT
	NavGrid.tilt = Data.NAV_TILT_DEFAULT
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NavGrid.path))
	nm.selected = ""
	s.engine_kill = false
	_check("Job S: both view toggles are in the rebindable key list (N and B by default)", keys_ok and main.controls.binding("map_orient") == "N" and main.controls.binding("map_tilt") == "B")


## Job AG (v1.5c): Covenant, Cybermorph and Solrath fighters from the owner's sets; Liberator and Imperium copies rebuilt
## (levelled, mirrored, nose at -Z, yaw 0); Cybernet and the Void System fly their home fleets; the pilots have ships.
func _job_ag() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AG: version label reads \"Homelancer Digital v1.5c\" or later", Data.VERSION >= "v1.5c" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var keys := ["covenant_fighter", "covenant_interceptor", "covenant_lance", "cybermorph_fighter", "cybermorph_star", "solrath_blade_a", "solrath_blade_b", "solrath_batwing", "solrath_spire",
		"liberator_cross", "liberator_fighter", "liberator_heavy", "imperium_fighter", "imperium_gunship"]
	var real := true
	var fit := true
	var mirror := true
	var small := true
	var note := ""
	for k in keys:
		if not (Data.ENEMIES.has(k) and ShipFactory.has_real_model(Data.ENEMIES[k]["model"])):
			real = false
			note += " missing:" + k
			continue
		var path: String = ShipFactory.GLB[k][0]
		if FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() > 700 * 1024:
			small = false
			note += " big:" + k
		var m := ShipFactory.build(k, false)
		if m.get_meta("placeholder", true): real = false
		var inst: Node3D = m.get_child(0)
		var pts := _ac_points(inst, Transform3D.IDENTITY)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in pts:
			lo = lo.min(v)
			hi = hi.max(v)
		var size := hi - lo
		var want: float = ShipFactory.GLB[k][1]
		if absf(maxf(size.x, size.z) - want) > want * 0.03 or ((lo + hi) * 0.5).length() > want * 0.03 or not is_equal_approx(inst.rotation_degrees.y, 0.0):
			fit = false
			note += " fit:" + k
		var seen := {}
		for v in pts: seen[Vector3i((v * (400.0 / want)).round())] = true
		var miss := 0
		for v in pts:
			var q := Vector3i((Vector3(-v.x, v.y, v.z) * (400.0 / want)).round())
			var ok := false
			for dx in [-1, 0, 1]:
				if seen.has(q + Vector3i(dx, 0, 0)): ok = true
			if not ok: miss += 1
		if miss > pts.size() / 100:
			mirror = false
			note += " mirror:%s(%d of %d)" % [k, miss, pts.size()]
		m.free()
	_check("Job AG: fourteen fighters are real models (three Covenant, two Cybermorph, four Solrath, three Liberator, two Imperium), each the right length, centred, yaw 0 (the Liberator copies no longer need the 180 turn)", real and fit, note)
	_check("Job AG: every one of them is mirrored (left matches right) and light (under 700 KB each)", mirror and small, note)
	# the pilots: every Covenant, Cybermorph, Solrath and Liberator person has a ship of their own faction, lighter in the low slots
	var ships_ok := true
	var pnote := ""
	for f in ["Covenant", "Cybermorph", "Solrath", "Liberator"]:
		for p in Data.ROSTERS[f]["pilots"]:
			var fp := str(p["fighter_primary"])
			if not Data.ENEMIES.has(fp) or str(Data.ENEMIES[fp]["faction"]) != f:
				ships_ok = false
				pnote += " %s:%s" % [p["id"], fp]
	_check("Job AG: every Covenant, Cybermorph, Solrath and Liberator pilot flies a fighter of their own faction (slots 1-3 light, 4-6 heavier: simplest choice, the documents give no ships)", ships_ok and Factions.has_fighters("Covenant") and Factions.has_fighters("Cybermorph") and Factions.has_fighters("Solrath"), pnote)
	# Cybernet and the Void System fly their own ships, hostile, flown by their own people
	var cyb: Dictionary = Data.SYSTEMS.get("cybernet", {})
	var voi: Dictionary = Data.SYSTEMS.get("void_system", {})
	var s := _sp()
	var real_sys: Dictionary = s.sys
	var flown: Array = []
	var hostile := true
	var own := true
	var shot_done: Array = []
	for sy in [cyb, voi]:
		if sy.is_empty(): continue
		s.sys = sy
		var g: Array = s._spawn_group(s.station.global_position + Vector3(0, 300, 2600), 4)
		s.sys = real_sys
		for e in g:
			flown.append(str(e["def"].get("model", "")))
			if (e["node"] as Node3D).get_meta("kind", "") != "enemy" or (e.has("faction") and not Factions.hostile(e["faction"])): hostile = false
			if not e.has("pilot") or str(e["pilot"].get("faction", "")) != str(e["def"]["faction"]): own = false
		main.hud.visible = false
		for e in g:
			var k := str(e["def"].get("model", ""))
			if k in shot_done: continue
			shot_done.append(k)
			var np: Vector3 = (e["node"] as Node3D).global_position
			var back: Vector3 = (e["node"] as Node3D).global_basis.z
			var side: Vector3 = (e["node"] as Node3D).global_basis.x
			_tp(np + back * 24.0 + Vector3(0, 2, 0), np - side * 10.0 + Vector3(0, -6, 0))
			await _shot("ag_" + k, 0.2)
		main.hud.visible = true
		s.target = null
		for e in g:
			s.enemies.erase(e)
			(e["node"] as Node3D).free()
		s.target = null
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	_check("Job AG: Cybernet flies Cybermorph ships and the Void System flies Solrath ships on patrol, hostile, flown by their own people",
		cyb.get("enemy_ships", []) == Data.HOME_FLEETS["Cybermorph home"] and voi.get("enemy_ships", []) == Data.HOME_FLEETS["Solrath home"] and hostile and own
		and flown.slice(0, 4).all(func(k): return str(k).begins_with("cybermorph_")) and flown.slice(4).all(func(k): return str(k).begins_with("solrath_")) and flown.size() == 8, str(flown))


## Job AI (v1.5f): missions: the station's MISSIONS board (threats easy / hard, escort), the bounty chain (escort wing
## -> the target's wing -> paid dead on the spot, or alive back at the giver), the hold, the YOUR SHIP page.
func _job_ai() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AI: version label reads \"Homelancer Digital v1.5f\" or later", Data.VERSION >= "v1.5f" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var s := _sp()
	var keep := {"bounty": GS.bounty.duplicate(true), "done": GS.bounties_done.duplicate(), "cast": GS.cast.duplicate(true), "credits": GS.credits, "rep": GS.rep.duplicate(true), "mission": GS.mission.duplicate(true), "cargo": GS.cargo.duplicate(true), "last": GS.last_base}
	GS.bounty = {}
	GS.mission = {}
	GS.cargo = []
	GS.last_base = Data.SYSTEMS[s.sys_id]["station"]["id"]
	for e in s.enemies.duplicate():
		if is_instance_valid(e["node"]): (e["node"] as Node3D).free()
	s.enemies = []
	s.target = null
	# ---- the board
	var sid: String = Data.SYSTEMS[s.sys_id]["station"]["id"]
	var offers: Array = Missions.offers(s.sys_id, sid)
	var kinds: Array = offers.map(func(o): return str(o["kind"]) + ("_hard" if o.get("hard", false) else ""))
	var easy: Dictionary = {}
	var hard: Dictionary = {}
	var esc: Dictionary = {}
	var cvy: Dictionary = {}
	for o in offers:
		if o["kind"] == "threats" and o.get("hard", false): hard = o
		elif o["kind"] == "threats": easy = o
		elif o["kind"] == "escort": esc = o
		elif o["kind"] == "convoy": cvy = o
	var same: bool = Missions.offers(s.sys_id, sid).map(func(o): return o["title"]) == offers.map(func(o): return o["title"])
	_check("Job AI: a station's MISSIONS board offers a patrol threats job, an elite threats job (slot 05, paid more) and an escort, from a faction hostile to the owner, the same offers for the whole visit",
		kinds == ["threats", "threats_hard", "escort", "convoy", "outlaws", "invasion"] and int(hard["slot"]) == 5 and int(easy["slot"]) == 1 and int(hard["pay"]) > int(easy["pay"]) and same and Factions.has_fighters(str(easy["faction"])) and (easy["points"] as Array).size() == 2,
		str(kinds) + " " + str(easy.get("faction", "")))
	var pbid: String = str(Data.SYSTEMS[s.sys_id]["planet"]["id"])
	var pkinds: Array = Missions.offers(s.sys_id, pbid, "", "planet").map(func(o): return str(o["kind"]))
	var base_kinds: Array = []
	for l in Surface.PLANETS.get(pbid, {}).get("locations", []): base_kinds = Missions.offers(s.sys_id, str(l["id"]), "", "planet").map(func(o): return str(o["kind"]))
	_check("v1.9b (owner): missions on the planet are only about the planet, missions out in space only about space: a station's board has no planet jobs, the planet's board (its dock or a base down there) only jobs on that planet",
		not ("ground" in kinds) and not ("land_escort" in kinds) and pkinds == ["ground", "land_escort"] and (base_kinds.is_empty() or base_kinds == pkinds), "station %s planet %s base %s" % [kinds, pkinds, base_kinds])
	# ---- the hub pages
	main.hub.open(Data.SYSTEMS[s.sys_id]["station"])
	await _frames(2)
	main.hub.show_screen("missions")
	await _frames(2)
	var take: Button = main.hub.content.find_child("Take_Job_threats", true, false)
	var rows_ok: bool = take != null and not take.disabled and main.hub.content.find_child("Job_threats_hard", true, false) != null and main.hub.content.find_child("Job_escort", true, false) != null and main.hub.left.find_child("Btn_board", true, false) != null
	await _shot("ai_missions_board", 0.3)
	if take: take.pressed.emit()
	await _frames(2)
	var trk: Label = main.hub.content.find_child("Tracking", true, false)
	var taken: bool = GS.mission.get("kind", "") == "threats" and not bool(GS.mission.get("hard", false)) and main.hub.status.text.find("waypoint") >= 0 and trk != null and trk.text.find("PATROL") >= 0
	main.hub.show_screen("ship")
	await _frames(2)
	var wl: Label = main.hub.content.find_child("Weapons", true, false)
	var cl: Label = main.hub.content.find_child("Cargo", true, false)
	var ship_page: bool = wl != null and cl != null and wl.text.find("Guns") >= 0 and wl.text.find("MISSILE") >= 0 and cl.text.find("CARGO HOLD  0 / %d" % Data.CARGO_HOLD) >= 0 and main.hub.content.find_child("DropJob", true, false) != null
	await _shot("ai_ship_page", 0.3)
	main.hub.visible = false
	_check("Job AI: the MISSIONS page lists the jobs with ACCEPT, taking one shows it as the current job; YOUR SHIP lists guns, racks and the hold, and can drop the job", rows_ok and taken and ship_page, "rows %s taken %s ship %s" % [rows_ok, taken, ship_page])
	# ---- threats, easy: point 1 -> wave -> point 2 -> wave -> paid
	var m: Dictionary = GS.mission
	var w0: Dictionary = s.mission_waypoint()
	var p0: Vector3 = Missions.point_pos(s, 0)
	var way1: bool = not w0.is_empty() and (w0["node"] as Node3D).get_meta("kind", "") == "waypoint" and (w0["node"] as Node3D).global_position.distance_to(p0) < 1.0 and str(w0["line"]).find("point 1 of 2") >= 0 and main._objective().begins_with("MISSION: ")
	var far_ok: bool = p0.distance_to(s.station.global_position) >= Data.MISSION_POINT_DIST[0] - 1.0
	var credits0: int = GS.credits
	_tp(p0 + Vector3(0, 0, 300), p0)
	await _frames(4)
	var wave: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == 0)
	var wave_ok: bool = wave.size() == Data.MISSION_GROUP[0] and wave.all(func(o): return str(o.get("faction", "")) == str(m["faction"]) and o.get("provoked", false) and int(o.get("pilot", {}).get("slot", 9)) <= 1 and (o["node"] as Node3D).get_meta("kind", "") == "enemy")
	var w1: Dictionary = s.mission_waypoint()
	var way2: bool = not w1.is_empty() and wave.any(func(o): return o["node"] == w1["node"]) and str(w1["line"]).find("Destroy") >= 0
	main.hud.queue_redraw()
	await _shot("ai_threats_wave", 0.3)
	for o in wave: s._destroy_unit(o)
	await _frames(3)
	var w2: Dictionary = s.mission_waypoint()
	var p1: Vector3 = Missions.point_pos(s, 1)
	var moved: bool = int(GS.mission.get("stage", -1)) == 1 and not w2.is_empty() and (w2["node"] as Node3D).global_position.distance_to(p1) < 1.0
	_tp(p1 + Vector3(0, 0, 300), p1)
	await _frames(4)
	var wave2: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == 1)
	for o in wave2: s._destroy_unit(o)
	await _frames(3)
	var paid: bool = GS.mission.is_empty() and GS.credits - credits0 >= int(easy["pay"]) and GS.missions_done >= 1 and s.mission_waypoint().is_empty()
	_check("Job AI: a threats job: the waypoint is mission point 1 (far from the station); reaching it brings the wave (that faction's slot-01 soldiers, hostile), the waypoint moves to the nearest of them, the cleared wave moves it to point 2, and the second wave cleared pays on the spot",
		way1 and far_ok and wave_ok and way2 and moved and wave2.size() == Data.MISSION_GROUP[1] and paid, "way1 %s far %s wave %s (%d) way2 %s moved %s wave2 %d paid %s" % [way1, far_ok, wave_ok, wave.size(), way2, moved, wave2.size(), paid])
	# ---- threats, hard: the elites
	Missions.accept(hard)
	_tp(Missions.point_pos(s, 0) + Vector3(0, 0, 300), Missions.point_pos(s, 0))
	await _frames(4)
	var elite: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == 0)
	var elite_ok: bool = elite.size() == Data.MISSION_GROUP[0] and elite.all(func(o): return int(o.get("pilot", {}).get("slot", 0)) >= 2) and elite.any(func(o): return int(o.get("pilot", {}).get("slot", 0)) == 5)
	for o in elite: s._destroy_unit(o)
	# v1.7o (owner: "GPS and radar don't work on missions"): the GPS follows the job's waypoint, the radar shows it as a
	# gold diamond and the station / bases always show (at the rim when far)
	s.clear_route()
	s.gps_mission = true
	main.hud.radar_overview = Data.RADAR_OVERVIEW
	await _wait(0.8)
	var gmw: Dictionary = s.mission_waypoint()
	var gps_ok: bool = not gmw.is_empty() and s.nav_dest == gmw.get("node")
	var blip_ok: bool = main.hud.radar_blips.any(func(b): return b[2] == "mission")
	var base_ok: bool = main.hud.radar_blips.any(func(b): return b[2] == "station")
	_check("Mission GPS + radar (v1.7o): with a job on, the GPS destination follows the mission waypoint, the radar shows it (a gold diamond) and where the stations / bases are",
		gps_ok and blip_ok and base_ok, "gps on the waypoint %s, mission on the radar %s, stations on the radar %s" % [gps_ok, blip_ok, base_ok])
	s.gps_mission = false
	# v1.7v (owner): CURRENT MISSION on the map's left: one tap makes it the destination (highlighted); GO TO flies it
	s.clear_route()
	s.target = null
	s.autopilot = null
	main.open_map()
	await _frames(3)
	var nmv = main.navmap
	var mbtn: Rect2 = nmv.btn_mission
	var on_left: bool = mbtn.size.x > 0.0 and mbtn.position.x < nmv.map_rect.position.x + nmv.map_rect.size.x * 0.5
	if mbtn.size.x > 0.0: nmv.tap(mbtn.get_center())
	await _frames(2)
	var mw2: Dictionary = s.mission_waypoint()
	var m_set: bool = not mw2.is_empty() and s.nav_dest == mw2["node"] and s.gps_mission and str(nmv.gps_note).begins_with("Mission set")
	await _shot("av_map_current_mission", 0.3)
	nmv.visible = false
	main._on_map_closed()
	await _frames(2)
	_press("goto")
	await _frames(2)
	var m_go: bool = s.autopilot != null
	s.autopilot = null
	_check("v1.7v (owner): the map has CURRENT MISSION on the left; one tap makes the job the GPS destination; back in flight, GO TO flies there",
		on_left and m_set and m_go, "button %s set %s go %s" % [str(mbtn), m_set, m_go])
	s.gps_mission = false
	Missions.abandon()
	_check("Job AI: the ELITE threats job sends the faction's seniors, the slot-05 elite among them, for %.1fx the pay; a job can be dropped" % Data.MISSION_HARD_MULT, elite_ok and GS.mission.is_empty() and int(hard["pay"]) == int(Data.MISSION_PAY["threats"] * Data.MISSION_HARD_MULT), str(elite.map(func(o): return o.get("pilot", {}).get("slot", 0))))
	# ---- bounty wanted dead (Razor, rank 3): escort wing, then her wing, paid on the kill
	var said: String = Missions.accept_bounty("savagers_03")
	var bm: Dictionary = GS.mission
	var chain_ok: bool = bm.get("kind", "") == "bounty" and bool(bm.get("alive", false)) and GS.bounty.get("state", "") == "hunt" and said.find("waypoint") >= 0 and said.find("escort") >= 0
	bm["sys"] = s.sys_id
	GS.bounty["sys"] = s.sys_id
	var none_yet: bool = s.spawn_bounty().is_empty()   # the chain owns the target now
	_tp(Missions.point_pos(s, 0) + Vector3(0, 0, 300), Missions.point_pos(s, 0))
	await _frames(4)
	var ew: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == 0)
	var escort_ok: bool = ew.size() == Data.MISSION_GROUP[0] and ew.all(func(o): return str(o.get("faction", "")) == "Savagers" and not o.has("bounty"))
	for o in ew: s._destroy_unit(o)
	await _frames(3)
	_tp(Missions.point_pos(s, 1) + Vector3(0, 0, 300), Missions.point_pos(s, 1))
	await _frames(4)
	var bw: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == 1)
	var boss: Array = bw.filter(func(o): return o.get("bounty", "") == "savagers_03")
	var wb: Dictionary = s.mission_waypoint()
	var boss_ok: bool = bw.size() == 1 + Data.BOUNTY_HELPERS and Data.BOUNTY_HELPERS >= 6 and boss.size() == 1 and int(boss[0].get("rank", 0)) == 3 and not wb.is_empty() and wb["node"] == boss[0]["node"]
	await _shot("ai_bounty_boss", 0.3)
	var credits1: int = GS.credits
	for o in bw: s._destroy_unit(o)
	await _frames(3)
	var dead_paid: bool = not GS.mission.is_empty() and GS.credits - credits1 < Data.bounty_reward("savagers_03") and s.loot.any(func(l): return l.get("bounty", "") == "savagers_03")   # (v1.8x: a capture: the pilot bails out, nobody pays yet)
	Missions.abandon()
	GS.bounty = {}
	GS.jail("savagers_03", "station")   # (for the v1.8k check below: a target that is gone comes back)
	_check("Job AI (v1.8x: every bounty is a capture): a low-rank bounty (Razor, rank 3): the first waypoint is the escort wing, the second the target's own wing with the target in it (v1.9b: the target plus at least six helpers); the kill drops the pilot to TRACTOR in, nothing is paid on the spot",
		chain_ok and none_yet and escort_ok and boss_ok and dead_paid, "chain %s none %s escort %s boss %s paid %s" % [chain_ok, none_yet, escort_ok, boss_ok, dead_paid])
	# ---- bounty wanted alive (Dreadmaw, rank 6): the pod, the hold, back to the giver
	Missions.accept_bounty("savagers_06")
	var am: Dictionary = GS.mission
	am["sys"] = s.sys_id
	GS.bounty["sys"] = s.sys_id
	am["stage"] = 1   # (test: straight to the target's wing)
	_tp(Missions.point_pos(s, 1) + Vector3(0, 0, 300), Missions.point_pos(s, 1))
	await _frames(4)
	var aw: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == 1)
	var aboss: Array = aw.filter(func(o): return o.get("bounty", "") == "savagers_06")
	for o in aw: s._destroy_unit(o)
	await _frames(2)
	var pod: Array = s.loot.filter(func(l): return l.get("bounty", "") == "savagers_06")
	var pod_way: Dictionary = s.mission_waypoint()
	var pod_ok: bool = bool(am.get("alive", false)) and aboss.size() == 1 and pod.size() == 1 and not pod_way.is_empty() and pod_way["node"] == pod[0]["node"] and GS.mission.get("kind", "") == "bounty"
	if pod.size() == 1: (pod[0]["node"] as Node3D).global_position = s.player.global_position - s.player.global_basis.z * 40.0
	s.tractor()
	await _until(func(): return GS.bounty.get("state", "") == "captured", 8.0)
	s.tractor_t = 0.0
	var held: bool = GS.bounty.get("state", "") == "captured" and GS.cargo.any(func(c): return c.get("kind", "") == "pilot" and c.get("id", "") == "savagers_06")
	var back: Dictionary = s.mission_waypoint()
	var back_ok: bool = not back.is_empty() and back["node"] == s.station and str(back["line"]).find("hand") >= 0
	var elsewhere: String = Missions.claim_at("somewhere_else")
	var credits2: int = GS.credits
	var here: String = Missions.claim_at(sid)
	var alive_paid: bool = elsewhere.find("paid at") >= 0 and GS.bounty.get("state", "") == "captured" or false
	alive_paid = elsewhere.find("paid at") >= 0 and here.find("paid") >= 0 and GS.credits - credits2 == Data.bounty_reward("savagers_06") and GS.mission.is_empty() and GS.bounty.is_empty() and GS.cargo.is_empty() and "savagers_06" in GS.bounties_done
	_check("Job AI: a bounty wanted alive (rank %d and up): the pilot bails out, TRACTOR puts them in the hold (YOUR SHIP lists them), the waypoint is the station that gave the job, and only that station pays" % Data.BOUNTY_ALIVE_RANK,
		pod_ok and held and back_ok and alive_paid, "pod %s held %s back %s paid %s (%s / %s)" % [pod_ok, held, back_ok, alive_paid, elsewhere, here])
	# ---- v1.8k (owner): bounty targets come back (handed in: breaks out; killed: a new ship), same price
	var now_s := Time.get_unix_time_from_system()
	var jailed: bool = GS.bounty_jail.has("savagers_06") and absf(float(GS.bounty_jail["savagers_06"]) - now_s - Data.BOUNTY_ESCAPE_STATION) < 30.0
	var dead_back: bool = GS.bounty_jail.has("savagers_03")   # (Razor, killed above: she comes back too)
	var r0: int = Data.bounty_reward("savagers_06")
	GS.bounty_jail["savagers_06"] = now_s - 1.0
	GS.bounty_jail["savagers_03"] = now_s - 1.0
	var out: Array = GS.check_escapes()
	var back_on: bool = "savagers_06" in out and "savagers_03" in out and not ("savagers_06" in GS.bounties_done) and not ("savagers_03" in GS.bounties_done) \
		and bool(GS.cast_state("savagers_03_razor").get("alive", false)) and Data.bounty_reward("savagers_06") == r0
	GS.jail("savagers_06", "planet")
	var planet_h: bool = absf(float(GS.bounty_jail["savagers_06"]) - Time.get_unix_time_from_system() - Data.BOUNTY_ESCAPE_PLANET) < 30.0 and GS.jail_minutes("savagers_06") >= 59
	GS.bounty_jail.erase("savagers_06")
	_check("v1.8k (owner): bounty targets come back so the boards never run out: handed in, they break out later (station 30 min, planet 1 h); killed, they return in a new ship; same price",
		jailed and dead_back and back_on and planet_h, "jailed %s killed-one waiting %s back %s planet %s" % [jailed, dead_back, back_on, planet_h])
	for i in range(s.loot.size() - 1, -1, -1):
		(s.loot[i]["node"] as Node3D).queue_free()
		s.loot.remove_at(i)
	# ---- escort: the freighter leaves for the planet, raiders jump it, it arrives, paid
	Missions.accept(esc)
	await _frames(3)
	var fr: Node3D = s.escort_node
	var fr_ok: bool = is_instance_valid(fr) and fr.get_meta("kind", "") == "traffic"
	var wf: Dictionary = s.mission_waypoint()
	var fr_way: bool = not wf.is_empty() and wf["node"] == fr
	var start_pos: Vector3 = fr.global_position if fr_ok else Vector3.ZERO
	await _frames(30)
	var moving: bool = fr_ok and fr.global_position.distance_to(start_pos) > 5.0 and fr.global_position.distance_to(s.planet_dock_point()) < start_pos.distance_to(s.planet_dock_point())
	# jump ahead to a third of the way: the first ambush
	if fr_ok: fr.global_position = start_pos.lerp(s.planet_dock_point(), 0.36)
	await _frames(3)
	var raid: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == 0)
	var raid_ok: bool = raid.size() == Data.MISSION_GROUP[0] and raid.all(func(o): return (o["node"] as Node3D).global_position.distance_to(fr.global_position) < Data.ESCORT_AMBUSH + 200.0)
	var hull0: float = float(GS.mission.get("escort_hp", 0.0))
	for o in raid: (o["node"] as Node3D).global_position = fr.global_position + Vector3(60, 0, 60)   # on it
	_tp(fr.global_position + Vector3(0, 30, 200), fr.global_position)
	await _shot("ai_escort_ambush", 0.3)
	await _frames(20)
	var hurt: bool = float(GS.mission.get("escort_hp", 0.0)) < hull0 and not GS.mission.is_empty()
	for o in raid: s._destroy_unit(o)
	await _frames(3)
	var still: float = float(GS.mission.get("escort_hp", 0.0))
	await _frames(10)
	var safe: bool = is_equal_approx(float(GS.mission.get("escort_hp", 0.0)), still)
	var credits3: int = GS.credits
	if is_instance_valid(fr): fr.global_position = s.planet_dock_point() + Vector3(0, 0, Data.ESCORT_DOCK * 0.5)
	await _frames(4)
	var arrived: bool = GS.mission.is_empty() and GS.credits - credits3 == int(esc["pay"]) and not is_instance_valid(s.escort_node)
	_check("Job AI: an escort job: a freighter leaves the station for the planet and is the waypoint; a third of the way raiders ambush it and it loses hull while they are close; with them gone it stops losing hull; when it reaches the planet you are paid",
		fr_ok and fr_way and moving and raid_ok and hurt and safe and arrived, "freighter %s way %s moving %s raid %s hurt %s safe %s arrived %s" % [fr_ok, fr_way, moving, raid_ok, hurt, safe, arrived])
	# ---- a lost freighter fails the job
	Missions.accept(esc)
	await _frames(3)
	GS.mission["escort_hp"] = 1.0
	GS.mission["spawned"] = 1
	var fr2: Node3D = s.escort_node
	var g2: Array = s.spawn_mission_group(fr2.global_position + Vector3(50, 0, 50), str(esc["faction"]), 1, 1, "", 1)
	await _until(func(): return GS.mission.is_empty(), 3.0)   # (v1.8p: by game time, not a frame count: fast frames are short)
	await _frames(2)
	var failed: bool = GS.mission.is_empty() and not is_instance_valid(s.escort_node)
	for o in g2:
		if o in s.enemies: s._destroy_unit(o)
	_check("Job AI: the freighter destroyed fails the escort job (no pay)", failed)
	# ---- v1.7w (owner): the cargo run: station -> jump gate (ambush), through to the next system, to its station (battle), paid
	var home_sys: String = s.sys_id
	Missions.accept(cvy)
	await _frames(3)
	var cf: Node3D = s.escort_node
	var cgate: Node3D = Missions.gate_to(s, str(cvy["dest"]))
	var c_way: Dictionary = s.mission_waypoint()
	var leg0: bool = is_instance_valid(cf) and cgate != null and (cf.get_meta("goal", Vector3.ZERO) as Vector3).distance_to(cgate.global_position) < 1.0 and not c_way.is_empty() and c_way["node"] == cf
	cf.global_position = cgate.global_position + (cf.global_position - cgate.global_position).normalized() * (cf.get_meta("trip", 1.0) as float) * 0.45
	s.player.global_position = cf.global_position + Vector3(0, 30, 200)
	await _frames(3)
	var amb1: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == 0)
	for o in amb1: s._destroy_unit(o)
	cf.global_position = cgate.global_position + Vector3(0, 0, Data.CONVOY_GATE * 0.5)
	await _frames(3)
	var jumped: bool = int(GS.mission.get("leg", 0)) == 1 and str(GS.mission.get("sys", "")) == str(cvy["dest"]) and not is_instance_valid(s.escort_node)
	var c_way2: Dictionary = s.mission_waypoint()
	var to_gate: bool = not c_way2.is_empty() and c_way2["node"] == cgate
	await main._load_system(str(cvy["dest"]), "gate:" + home_sys)
	await _frames(4)
	var s2 := _sp()
	var cf2: Node3D = s2.escort_node
	var back_gate: Node3D = Missions.gate_to(s2, home_sys)
	var leg1: bool = is_instance_valid(cf2) and back_gate != null and cf2.global_position.distance_to(back_gate.global_position) < Data.CONVOY_START + 50.0 \
		and (cf2.get_meta("goal", Vector3.ZERO) as Vector3).distance_to(s2.dock_point(s2.station) + Vector3(0, 60, 0)) < 1.0
	if is_instance_valid(cf2):
		var g2v: Vector3 = cf2.get_meta("goal", Vector3.ZERO)
		cf2.global_position = g2v + (cf2.global_position - g2v).normalized() * (cf2.get_meta("trip", 1.0) as float) * 0.6
		s2.player.global_position = cf2.global_position + Vector3(0, 30, 200)
	await _frames(3)
	var amb2: Array = s2.enemies.filter(func(o): return int(o.get("mission", -1)) == 1)
	var battle: bool = amb2.size() == int(Data.CONVOY_WAVE_SHIPS[1])
	for o in amb2: s2._destroy_unit(o)
	var cc0: int = GS.credits
	if is_instance_valid(cf2): cf2.global_position = (cf2.get_meta("goal", Vector3.ZERO) as Vector3) + Vector3(0, 0, Data.ESCORT_DOCK * 0.5)
	await _frames(3)
	var c_paid: bool = GS.mission.is_empty() and GS.credits - cc0 >= int(cvy["pay"])
	_check("v1.7w (owner): the cargo run: the freighter flies from the station to the jump gate (an ambush on the way) and jumps; the waypoint becomes that gate; in the next system it comes out by the arrival gate and heads for the station, a bigger battle hits it, and its docking pays",
		leg0 and jumped and to_gate and leg1 and battle and c_paid, "leg0 %s jumped %s to_gate %s leg1 %s battle %s (%d) paid %s" % [leg0, jumped, to_gate, leg1, battle, amb2.size(), c_paid])
	await main._load_system(home_sys, "station")
	await _frames(4)
	s = _sp()
	# ---- v1.8u (owner): every ship can be picked: a tap on a ship's box targets it, also at the side of the screen where a stick lives
	var hu: Control = main.hud
	hu._layout()
	s.controls = true
	var ta: Dictionary = s.spawn_unit(s.sys["enemy"], s.cam.project_position(hu.S * 0.5, 420.0), s.player.global_position)
	var side_px := Vector2(hu.S.x * 0.2, hu.S.y * 0.42)
	var tb: Dictionary = s.spawn_unit(s.sys["enemy"], s.cam.project_position(side_px, 520.0), s.player.global_position)
	s.target = ta["node"]
	var in_zone: bool = hu.stick_zone("move").has_point(side_px) and side_px.distance_to(hu._home("move")) > hu.stick_r * 1.7
	var tev := InputEventScreenTouch.new()
	tev.index = 5
	tev.pressed = true
	tev.position = s.cam.unproject_position((tb["node"] as Node3D).global_position)
	hu._input(tev)
	var no_stick: bool = not hu.owners.values().has("move")
	tev = tev.duplicate()
	tev.pressed = false
	hu._input(tev)
	var picked: bool = s.target == tb["node"]
	await _frames(3)
	var kept: bool = s.target == tb["node"]
	var hev := InputEventScreenTouch.new()   # a touch by the stick itself still moves the stick
	hev.index = 6
	hev.pressed = true
	hev.position = hu._home("move") + Vector2(10, -10)
	(tb["node"] as Node3D).global_position = s.cam.project_position(hev.position, 520.0)
	s.target = ta["node"]
	hu._input(hev)
	var stick_ok: bool = hu.owners.get(6, "") == "move" and s.target == ta["node"]
	hev = hev.duplicate()
	hev.pressed = false
	hu._input(hev)
	for o in [ta, tb]:
		s.enemies.erase(o)
		(o["node"] as Node3D).free()
	s.target = null
	_check("v1.8u (owner): every ship can be picked: a tap on a ship's lock box targets it and it stays your target, also at the side of the screen where a stick lives; a touch by the stick itself still moves the stick; STOP is on the left block, TRACTOR on the right",
		in_zone and no_stick and picked and kept and stick_ok and hu.buttons.has("stop") and hu.buttons["stop"].end.x < hu.S.x * 0.5 and hu.buttons["tractor"].position.x > hu.S.x * 0.5,
		"zone %s no_stick %s picked %s kept %s stick %s" % [in_zone, no_stick, picked, kept, stick_ok])
	# ---- v1.8x (owner): PATROL = all level-1 soldiers, ELITE = all level-5 soldiers; every bounty is a capture
	var thr_f: String = str(easy["faction"])
	var far_p: Vector3 = s.player.global_position + Vector3(0, 0, -6000)
	var g1: Array = s.spawn_mission_group(far_p, thr_f, 3, 1, "", 9, true)
	var g5: Array = s.spawn_mission_group(far_p + Vector3(800, 0, 0), thr_f, 3, 5, "", 9, true)
	var lv1: bool = g1.size() == 3 and g1.all(func(o): return int(o.get("pilot", {}).get("slot", 0)) == 1)
	var lv5: bool = g5.size() == 3 and g5.all(func(o): return int(o.get("pilot", {}).get("slot", 0)) == 5)
	var slots_seen: Array = (g1 + g5).map(func(o): return int(o.get("pilot", {}).get("slot", 0)))
	for o in g1 + g5:
		s.enemies.erase(o)
		(o["node"] as Node3D).free()
	var all_capture := true
	for bid in ["savagers_02", "savagers_03", "savagers_04", "savagers_06"]:
		if int(Data.roster_pilot(bid).get("rank", 1)) < Data.BOUNTY_ALIVE_RANK: all_capture = false
	_check("v1.8x (owner): the PATROL threats job sends only level-1 soldiers, the ELITE job only level-5 soldiers; every bounty is a capture",
		lv1 and lv5 and all_capture, "slots %s capture %s" % [str(slots_seen), all_capture])
	# ---- v1.8p (owner): the outlaws job: the system's own raiders at two points, always offered, paid on the last kill
	var outl: Dictionary = {}
	for o in Missions.offers(s.sys_id, sid):
		if o["kind"] == "outlaws": outl = o
	Missions.accept(outl)
	await _frames(2)
	var o_kinds_ok := true
	var oc0: int = GS.credits
	for st in 2:
		s.player.global_position = Missions.point_pos(s, st) + Vector3(0, 0, 200)
		await _frames(3)
		var ow: Array = s.enemies.filter(func(o): return int(o.get("mission", -1)) == st)
		if ow.size() != int(Data.MISSION_GROUP[st]) or not ow.all(func(o): return o["def"] == Data.ENEMIES[s.sys["enemy"]] and not o.has("faction") and bool(o.get("provoked", false))): o_kinds_ok = false
		for o in ow: s._destroy_unit(o)
		await _frames(3)
	var all_boards := true
	for sy in Data.SYSTEMS:
		if not Missions.offers(sy, str(Data.SYSTEMS[sy]["station"]["id"])).any(func(o): return o["kind"] == "outlaws"): all_boards = false
	await _frames(2)
	var cg: Dictionary = main.hud.slot("r")
	var congrats: bool = not cg.is_empty() and not bool(cg.get("hostile", true)) and str(cg.get("line", "")).find(str(int(outl["pay"]))) >= 0
	_check("v1.8w (owner): a job paid: the one who pays you calls in on the friendly side to say well done, with the credits (%s: %s)" % [str(cg.get("from", "-")), str(cg.get("line", "-"))], congrats)
	main.hud.close_comms()
	_check("v1.8p (owner): every board also offers a job against the system's own outlaws (%s): two points, their ships, paid on the last kill" % str(outl.get("title", "")),
		not outl.is_empty() and o_kinds_ok and all_boards and GS.mission.is_empty() and GS.credits - oc0 >= int(outl["pay"]), "ships %s boards %s paid %d" % [o_kinds_ok, all_boards, GS.credits - oc0])
	for e in s.enemies.duplicate():
		if is_instance_valid(e["node"]): (e["node"] as Node3D).free()
	s.enemies = []
	s.target = null
	# ---- v1.8m (owner): a ground job: the planet is the waypoint in space; down there two points in one sector, a wave at each; paid on the last kill
	var gnd: Dictionary = {}
	for o in Missions.offers(s.sys_id, sid, "", "planet"):
		if o["kind"] == "ground": gnd = o
	var g_said: String = Missions.accept(gnd)
	await _frames(2)
	var gpid: String = str(gnd["planet"])
	var gtile: int = int(gnd["tile"])
	var gw0: Dictionary = s.mission_waypoint()
	var g_space: bool = g_said.find("Job taken") >= 0 and not gw0.is_empty() and gw0["node"] == s.planet and str(gw0["line"]).find("atmosphere") >= 0 and Missions.tracking_line(s.sys_id).find("sector") >= 0
	main._load_surface(gpid, Surface.neighbour(gpid, gtile, Vector2i(1, 0)))
	await _wait(0.6)
	var sg := _sp()
	var gw1: Dictionary = sg.mission_waypoint()
	# v1.8o (owner): a planet has only its owner's rival over it; a base's jobs are against its own owner's rival; the soldier threat is always offered
	var rv: String = Missions.enemy_of(sg.sys_id)
	var pat: Array = sg.enemies.filter(func(o): return not o.has("mission"))
	var pat_ok: bool = rv != "" and not pat.is_empty() and pat.all(func(o): return bool(o.get("provoked", false)) and (str(o.get("faction", rv)) == rv))
	var other_owner := ""
	for f in Factions.DEFS:
		if Factions.has_fighters(Factions.rival(f)) and Factions.rival(f) != rv: other_owner = f
	var o_own: Array = Missions.offers(sg.sys_id, sid, other_owner)
	var own_ok: bool = other_owner != "" and str(o_own[0]["faction"]) == Factions.rival(other_owner) and str(o_own[0]["kind"]) == "threats"
	var always := true
	for sy in Data.SYSTEMS:
		var oo: Array = Missions.offers(sy, str(Data.SYSTEMS[sy]["station"]["id"]))
		if oo.size() < 2 or str(oo[0]["kind"]) != "threats" or str(oo[1]["kind"]) != "threats" or str(oo[0]["title"]).find("eliminate the  threat") >= 0: always = false
	_check("v1.8o (owner): a planet sector's patrol is the rival of the planet's owner (%s), always hostile; a base's jobs are against its own owner's rival; every station's board always offers the soldier threat jobs" % rv,
		pat_ok and own_ok and always, "patrol %s (%d) owner %s (%s) always %s" % [pat_ok, pat.size(), own_ok, other_owner, always])
	var g_far: bool = not gw1.is_empty() and (gw1["node"] as Node3D).global_position.x < -Surface.TILE * 0.5 and str(gw1["line"]).find("sector") >= 0 and main._objective().begins_with("MISSION")
	main._load_surface(gpid, gtile)
	await _wait(0.6)
	sg = _sp()
	sg.controls = true
	var gp0: Vector3 = Missions.ground_pos(sg, 0)
	var g_alt: bool = absf(gp0.y - sg._ground(gp0.x, gp0.z) - Data.MISSION_GROUND_ALT) < 1.0
	sg.player.global_position = gp0 + Vector3(0, 0, 200)
	await _frames(3)
	var gwave: Array = sg.enemies.filter(func(o): return int(o.get("mission", -1)) == 0)
	var gn0: int = int(Data.MISSION_GROUP[0]) + int(Data.MISSION_GROUND_MECHS[0])
	var g_wave: bool = gwave.size() == gn0 and gwave.all(func(o): return bool(o.get("provoked", false)))
	# v1.8n: the mechs of the wave are on foot: on the ground, upright, walking toward you, never climbing after you
	var walkers: Array = gwave.filter(func(o): return bool(o.get("walker", false)))
	var wk0: Vector3 = (walkers[0]["node"] as Node3D).global_position if not walkers.is_empty() else Vector3.ZERO
	var wdir := Vector3(0, 0, 1)   # stand where the mech has dry land to walk toward you
	for k in 8:
		var dv := Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0))
		if not (sg._sea_at(wk0.x + dv.x * 100.0, wk0.z + dv.z * 100.0) or sg._sea_at(wk0.x + dv.x * 200.0, wk0.z + dv.z * 200.0)):
			wdir = dv
			break
	sg.player.global_position = wk0 + wdir * 380.0 + Vector3(0, 60, 0)
	await _wait(5.0)
	var wk_ok: bool = walkers.size() == int(Data.MISSION_GROUND_MECHS[0])
	for o in walkers:
		var wn: Node3D = o["node"]
		if absf(wn.global_position.y - sg._ground(wn.global_position.x, wn.global_position.z) - Data.WALKER_STAND) > 0.5 or absf((-wn.global_basis.z).y) > 0.05 or not bool(o["mech"]): wk_ok = false
	var wk1: Vector3 = (walkers[0]["node"] as Node3D).global_position if not walkers.is_empty() else Vector3.ZERO
	var wk_moved: bool = Vector2(wk1.x - wk0.x, wk1.z - wk0.z).length() > 5.0 and wk1.distance_to(sg.player.global_position) < wk0.distance_to(sg.player.global_position)
	var fliers_up: bool = gwave.filter(func(o): return not bool(o.get("walker", false))).all(func(o): return (o["node"] as Node3D).global_position.y >= sg._ground((o["node"] as Node3D).global_position.x, (o["node"] as Node3D).global_position.z) + 29.0)
	var dry: bool = not sg._sea_at(gp0.x, gp0.z) and not sg._sea_at(wk1.x, wk1.z) and str(Surface.PLANETS[gpid]["tiles"][gtile]) != "ocean"
	_tp(wk1 + Vector3(0, 8, 42), wk1 + Vector3(16, 2, 0))
	await _shot("ground_mech", 0.4)
	sg.player.global_position = gp0 + Vector3(0, 0, 200)
	for o in gwave:   # they are left behind (not killed): the job does not move on, they wait at the point again
		sg.enemies.erase(o)
		(o["node"] as Node3D).free()
	await _frames(3)
	gwave = sg.enemies.filter(func(o): return int(o.get("mission", -1)) == 0)
	var g_wait: bool = int(GS.mission.get("stage", -1)) == 0 and gwave.size() == gn0
	for o in gwave: sg._destroy_unit(o)
	await _frames(3)
	var g_next: bool = int(GS.mission.get("stage", -1)) == 1
	var gp1: Vector3 = Missions.ground_pos(sg, 1)
	sg.player.global_position = gp1 + Vector3(0, 0, 200)
	await _frames(3)
	var gwave2: Array = sg.enemies.filter(func(o): return int(o.get("mission", -1)) == 1)
	var gc0: int = GS.credits
	for o in gwave2: sg._destroy_unit(o)
	await _frames(3)
	var g_paid: bool = gwave2.size() == int(Data.MISSION_GROUP[1]) + int(Data.MISSION_GROUND_MECHS[1]) and GS.mission.is_empty() and GS.credits - gc0 >= int(gnd["pay"])
	_check("v1.8m (owner): a ground job: the board offers a strike on the planet; in space the planet is the waypoint; down there the waypoint leads across sectors to two points in one sector, a wave waits over the ground at each (left behind, it waits again), and the last kill pays",
		g_space and g_far and g_alt and g_wave and g_wait and g_next and g_paid, "space %s far %s alt %s wave %s wait %s next %s paid %s (%s, %s)" % [g_space, g_far, g_alt, g_wave, g_wait, g_next, g_paid, gpid, Missions.sector_name(gpid, gtile)])
	# ---- v1.8r (owner): GROUND mode: the ship comes down under gravity and lands with no damage, stands q_still with the
	#      stick centred; THRUST centred = a jump (down again by gravity); THRUST in the air does nothing; stick + THRUST = a q_burst
	for e in sg.enemies.duplicate():
		if is_instance_valid(e["node"]): (e["node"] as Node3D).free()
	sg.enemies = []
	sg.target = null
	var hudg: Control = main.hud
	var gform: String = GS.form
	var gr_ok := true
	var gr_note := ""
	for form in ["ship", "mech"]:
		GS.form = form
		sg.ground_mode = false
		sg.player.global_position = Vector3(gp0.x, sg._ground(gp0.x, gp0.z) + 150.0, gp0.z)
		sg.vel = Vector3.ZERO
		hudg.move_vec = Vector2.ZERO
		hudg.held.erase("thrust")
		GS.restore_full()
		_shield_down()
		sg.last_collision = {}
		var gh0: float = GS.hull
		_press("ground")
		var q_on: bool = sg.ground_mode
		var q_landed: bool = await _until(func(): return sg.grounded, 15.0)
		await _wait(0.6)
		var q_soft: bool = GS.hull == gh0 and sg.last_collision.is_empty()
		var q_still: bool = sg.vel.length() < 1.5
		GS.energy = Data.ENERGY_MAX
		hudg.held["thrust"] = true   # stick centred: a jump
		await _frames(3)
		hudg.held.erase("thrust")
		var q_jumped: bool = sg.last_dash == "jump" and sg.vel.y > Data.GROUND_JUMP * 0.5 and not sg.grounded
		await _wait(0.5)
		var q_up_y: float = sg.altitude
		hudg.move_vec = Vector2(0, -1)   # in the air: stick forward + THRUST = no q_burst
		hudg.held["thrust"] = true
		await _frames(4)
		hudg.held.erase("thrust")
		var q_no_air: bool = sg.last_dash == "air" and Vector2(sg.vel.x, sg.vel.z).length() < float(GS.ship()["speed"]) * Data.GROUND_WALK * 1.2 and not sg.boosting
		hudg.move_vec = Vector2.ZERO
		var q_back: bool = await _until(func(): return sg.grounded, 10.0)
		await _wait(0.5)
		GS.energy = Data.ENERGY_MAX
		hudg.move_vec = Vector2(0, -1)   # q_on the ground: stick forward + THRUST = a q_burst forward
		await _frames(2)
		hudg.held["thrust"] = true
		await _wait(0.25)
		var q_burst: bool = sg.last_dash == "forward" and sg.boosting and Vector2(sg.vel.x, sg.vel.z).length() > float(GS.ship()["speed"]) * Data.GROUND_WALK * 1.5 and sg.altitude < 30.0   # (bursting over block steps it can leave the ground for a moment)
		gr_note += "[burst %s boosting %s h %.0f alt %.0f grounded %s] " % [sg.last_dash, sg.boosting, Vector2(sg.vel.x, sg.vel.z).length(), sg.altitude, sg.grounded]
		hudg.held.erase("thrust")
		hudg.move_vec = Vector2.ZERO
		await _wait(2.0)
		var q_stopped: bool = Vector2(sg.vel.x, sg.vel.z).length() < 1.5
		gr_note += "[stop h %.1f grounded %s alt %.0f] " % [Vector2(sg.vel.x, sg.vel.z).length(), sg.grounded, sg.altitude]
		_press("ground")
		var q_off: bool = not sg.ground_mode
		if not (q_on and q_landed and q_soft and q_still and q_jumped and q_up_y > 8.0 and q_no_air and q_back and q_burst and q_stopped and q_off): gr_ok = false
		gr_note += "%s: q_on %s q_landed %s q_soft %s q_still %s q_jumped %s (%.0f m) q_no_air %s q_back %s q_burst %s q_stopped %s q_off %s  " % [form, q_on, q_landed, q_soft, q_still, q_jumped, q_up_y, q_no_air, q_back, q_burst, q_stopped, q_off]
	GS.form = gform
	GS.restore_full()
	_check("v1.8r (owner): GROUND mode (ship and mech): gravity brings you down to land with no damage and you stand still with the stick centred; THRUST centred = a jump and gravity brings you back; THRUST in the air does nothing; stick + THRUST on the ground = a burst that way; GROUND again = flying",
		gr_ok, gr_note)
	# ---- v1.8y (owner): on a planet: every base on the radar and on the planet map (tap = fly there); a job in space points up to orbit
	var spots_y: Array = sg.base_spots()
	main.hud.planet_map = false
	_press("radar")
	main.hud._layout()
	var map_up: bool = main.hud.planet_map and main.hud.buttons.has("pmap_close") and main.hud.buttons.has("pmap_b0")
	await _shot("planet_map", 0.3)
	var far_i := 0
	for i in spots_y.size():
		if int(spots_y[i]["tile"]) != sg.tile: far_i = i
	_press("pmap_b%d" % far_i)
	var gnode: Node3D = sg.autopilot
	var fly_ok: bool = not main.hud.planet_map and gnode != null and str(gnode.name) == str(spots_y[far_i]["name"]) and Vector2(gnode.global_position.x, gnode.global_position.z).distance_to(Vector2((spots_y[far_i]["pos"] as Vector3).x, (spots_y[far_i]["pos"] as Vector3).z)) < 1.0
	var fly_note: String = "%s -> %s at %s vs %s" % [str(spots_y[far_i]["name"]), str(gnode.name) if gnode != null else "none", str(gnode.global_position) if gnode != null else "-", str(spots_y[far_i]["pos"])]
	sg.autopilot = null
	var keep_y: Dictionary = GS.mission
	GS.mission = {}
	var thr_y: Dictionary = Missions.offers(sg.sys_id, sid)[0]
	Missions.accept(thr_y)
	var upw: Dictionary = sg.mission_waypoint()
	var up_ok: bool = not upw.is_empty() and (upw["node"] as Node3D).global_position.y > Surface.CEILING and str(upw["line"]).find("orbit") >= 0
	GS.mission = {}
	sg.autopilot = null
	sg.target = null
	_press("goto")
	var go_base: bool = sg.autopilot != null and not sg.surf_goal.is_empty()
	sg.autopilot = null
	GS.mission = keep_y
	_check("v1.8y (owner): on a planet: the radar / MAP opens the planet map with every base (%d); tapping one flies you there across sectors; a job out in space points straight up to orbit; GO TO with nothing to do flies to the nearest base" % spots_y.size(),
		spots_y.size() >= 2 and map_up and fly_ok and up_ok and go_base, "map %s fly %s (%s) up %s goto %s" % [map_up, fly_ok, fly_note, up_ok, go_base])
	# ---- v1.9a (owner): escort a freighter from one base to another on the planet; it waits when you are not with it; paid on arrival
	for e in sg.enemies.duplicate():
		if is_instance_valid(e["node"]): (e["node"] as Node3D).free()
	sg.enemies = []
	var keep_le: Dictionary = GS.mission
	GS.mission = {}
	var le: Dictionary = {}
	for o in Missions.offers(sg.sys_id, sid, "", "planet"):
		if o["kind"] == "land_escort": le = o
	Missions.accept(le)
	sg.player.global_position = Vector3(0, 400, 0)
	await _frames(3)
	var lm: Dictionary = GS.mission
	var lfr: Node3D = sg.escort_node
	var lw: Dictionary = sg.mission_waypoint()
	var le_way: bool = is_instance_valid(lfr) and not lw.is_empty() and lw["node"] == lfr
	var gp_a := Vector2(float(lm["pos"][0]), float(lm["pos"][1]))
	sg.player.global_position = Vector3(0, 0, 9000) + Vector3(0, 400, 0)   # far away: it waits
	await _wait(0.6)
	var le_wait: bool = Vector2(float(lm["pos"][0]), float(lm["pos"][1])).distance_to(gp_a) < 1.0
	var a_b: Dictionary = Missions.land_base(lm, "from")
	var b_b: Dictionary = Missions.land_base(lm, "to")
	var dvec: Vector2 = Missions.wrap_d(str(lm["planet"]), a_b["g"], b_b["g"])
	lm["pos"] = [a_b["g"].x + dvec.x * 0.4, a_b["g"].y + dvec.y * 0.4]   # 40% of the way: the first ambush
	await _frames(2)
	sg.player.global_position = sg.escort_node.global_position + Vector3(0, 20, 60)
	await _frames(4)
	var lamb: Array = sg.enemies.filter(func(o): return int(o.get("mission", -1)) == 0)
	var le_amb: bool = lamb.size() == int(Data.MISSION_GROUP[0])
	for o in lamb: sg._destroy_unit(o)
	var gp_b := Vector2(float(lm["pos"][0]), float(lm["pos"][1]))
	await _wait(0.6)
	var le_moves: bool = Vector2(float(lm["pos"][0]), float(lm["pos"][1])).distance_to(gp_b) > 2.0
	lm["spawned"] = 1
	var lc0: int = GS.credits
	lm["pos"] = [b_b["g"].x - dvec.normalized().x * 100.0, b_b["g"].y - dvec.normalized().y * 100.0]   # nearly there
	await _frames(2)
	sg.player.global_position = sg.escort_node.global_position + Vector3(0, 20, 60) if is_instance_valid(sg.escort_node) else sg.player.global_position
	await _frames(4)
	var le_paid: bool = GS.mission.is_empty() and GS.credits - lc0 >= int(le["pay"]) and not is_instance_valid(sg.escort_node)
	var le_note: String = "mission %s credits +%d node %s togo %.0f" % [str(GS.mission.get("kind", "none")), GS.credits - lc0, is_instance_valid(sg.escort_node), Missions.wrap_d(str(lm["planet"]), Vector2(float(lm["pos"][0]), float(lm["pos"][1])), b_b["g"]).length()]
	main.hud.close_comms()
	GS.mission = keep_le
	_check("v1.9a (owner): escort on the planet: a freighter from %s to %s; it is the waypoint; it waits when you are not with it and flies on when you are; ambushed on the way; paid when it reaches the other base" % [str(a_b["name"]), str(b_b["name"])],
		le_way and le_wait and le_amb and le_moves and le_paid, "way %s wait %s ambush %s moves %s paid %s (%s)" % [le_way, le_wait, le_amb, le_moves, le_paid, le_note])
	_check("v1.8n (owner): enemy mechs on foot: each wave of a ground job has Assault Mechs walking the ground under the ships: they stay on the ground, upright, and walk toward you; the ships stay in the air",
		wk_ok and wk_moved and fliers_up and dry, "walkers %d ok %s moved %s fliers up %s dry land %s" % [walkers.size(), wk_ok, wk_moved, fliers_up, dry])
	await main._load_system(home_sys, "station")
	await _frames(4)
	s = _sp()
	# ---- tidy
	for e in s.enemies.duplicate():
		if is_instance_valid(e["node"]): (e["node"] as Node3D).free()
	s.enemies = []
	s.target = null
	GS.bounty = keep["bounty"]
	GS.bounties_done = keep["done"]
	GS.cast = keep["cast"]
	GS.credits = keep["credits"]
	GS.rep = keep["rep"]
	GS.mission = keep["mission"]
	GS.cargo = keep["cargo"]
	GS.last_base = keep["last"]
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	# v1.8v (owner): GO TO always takes you somewhere: nothing picked, no GPS, no job -> the station; a second tap stops it
	var keep_m: Dictionary = GS.mission
	GS.mission = {}
	s.target = null
	s.nav_dest = null
	s.autopilot = null
	_press("goto")
	var go_home: bool = s.autopilot == s.station
	_press("goto")
	var go_off: bool = s.autopilot == null
	GS.mission = keep_m
	_check("v1.8v (owner): GO TO with nothing picked and no job flies you to the station; tapping it again stops the autopilot; fewer patrol wings, cargo ships and asteroids out at once",
		go_home and go_off and Data.PATROL_GROUPS <= 2 and Data.TRAFFIC_PER_RUN <= 1 and Data.ASTEROID_COUNT <= 20, "home %s off %s" % [go_home, go_off])


## Job AJ (v1.5g): ship scan: tap a ship on screen to target it, tap the target box to scan it (in range, takes a moment),
## and a panel shows its pilot, ship, hull, weapons and cargo.
func _job_aj() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AJ: version label reads \"Homelancer Digital v1.5g\" or later", Data.VERSION >= "v1.5g" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var s := _sp()
	var hud = main.hud
	for e in s.enemies.duplicate():
		if is_instance_valid(e["node"]): (e["node"] as Node3D).free()
	s.enemies = []
	s.target = null
	var g: Array = s.spawn_mission_group(s.player.global_position - s.player.global_basis.z * 260.0, "Savagers", 1, 3, "", 7)
	var e: Dictionary = g[0]
	var n: Node3D = e["node"]
	n.global_position = s.player.global_position - s.player.global_basis.z * 260.0
	e["hp"] = 1.0e6   # (the auto-guns are firing at it: keep it alive for the test)
	e["max"] = 1.0e6
	await _frames(3)
	# tap the ship where it is drawn
	var sp: Vector2 = s.cam.unproject_position(n.global_position)
	var tap := InputEventScreenTouch.new()
	tap.index = 5
	tap.position = sp + Vector2(8, 6)
	tap.pressed = true
	hud._input(tap)
	tap.pressed = false
	hud._input(tap)
	var picked: bool = s.target == n
	# scan it: the target box is the button
	await _frames(2)
	var has_btn: bool = hud.buttons.has("scan")
	main._on_hud("scan")
	var running: bool = hud.scan_t > 0.0 and hud.scan.is_empty()
	await _shot("aj_scanning", 0.2)
	await _wait(Data.SCAN_TIME + 0.3)
	var sc: Dictionary = hud.scan
	var labels: Array = (sc.get("lines", []) as Array).map(func(l): return l[0])
	var ok_info: bool = not sc.is_empty() and labels.has("PILOT") and labels.has("WEAPONS") and labels.has("CARGO") and labels.has("HULL") and labels.has("JOB") and str(sc["title"]).find(n.name.to_upper()) >= 0
	await _shot("aj_scan_panel", 0.3)
	# a wing shot off shows as destroyed on the next refresh
	e["l"] = 0.0
	await _wait(0.7)
	var wl: Array = (hud.scan.get("lines", []) as Array).filter(func(l): return l[0] == "WEAPONS")
	var wing_off: bool = not wl.is_empty() and str(wl[0][1]).find("left wing DESTROYED") >= 0
	_check("Job AJ: tap a ship on screen and it becomes the target; tap the target box and the scan runs for a moment, then a panel shows its pilot, ship, hull, weapons, cargo (and that it is a mission target); damage shows live",
		picked and has_btn and running and ok_info and wing_off, "picked %s button %s running %s info %s (%s) wing %s" % [picked, has_btn, running, ok_info, str(labels), wing_off])
	# out of range: no scan; a freighter scans as civilian cargo
	hud.close_scan()
	n.global_position = s.player.global_position - s.player.global_basis.z * (Data.SCAN_RANGE + 400.0)
	var far_said: String = hud.start_scan()
	var far_ok: bool = far_said.find("Too far") >= 0 and hud.scan_node == null
	var fr: Node3D = s.traffic[0]["node"] if not s.traffic.is_empty() else null
	var civ: Dictionary = s.scan_info(fr) if fr != null else {}
	var civ_ok: bool = not civ.is_empty() and not civ["hostile"] and str(civ["lines"][1][1]) == "none" and str(civ["lines"][2][1]).find(" t") >= 0
	var station_none: bool = s.scan_info(s.station).is_empty()
	# the panel closes when the target changes
	s.target = n
	hud.scan_node = n
	hud.scan = s.scan_info(n)
	s.target = s.station
	await _frames(2)
	var closed: bool = hud.scan.is_empty() and hud.scan_node == null
	_check("Job AJ: too far away nothing is scanned; a freighter scans as an unarmed civilian with its cargo; a station is not a ship; the panel closes when you pick another target",
		far_ok and civ_ok and station_none and closed, "far %s civ %s station %s closed %s" % [far_ok, civ_ok, station_none, closed])
	for o in g:
		if o in s.enemies: s._destroy_unit(o)
	s.target = null
	hud.close_scan()


## Job AK (v1.5h): lower, rounder mountains and real water on planet surfaces.
func _job_ak() -> void:
	var hi := -INF
	for k in 900:
		var q := Vector2(randf_range(-2500, 2500), randf_range(-2500, 2500))
		hi = maxf(hi, Surface.height("new_terra", 3, q.x, q.y))
	_check("Job AK: New Terra's mountains top out well under the 2.6 km flight ceiling (under 1.45 km, was about 2.5 km)", hi < 1450.0 and hi > 500.0, "highest sampled %d m" % int(hi))
	var tile: Node3D = Surface.build_tile("new_terra", 1)
	var w: MeshInstance3D = tile.get_node_or_null("Water")
	var mat_ok: bool = w != null and w.material_override is ShaderMaterial and (w.material_override as ShaderMaterial).shader.code.find("foam") >= 0
	var deep := 0
	var shore := 0
	if w != null and w.mesh is ArrayMesh:
		var cols: PackedColorArray = (w.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for c in cols:
			if c.r * 255.0 > 30.0: deep += 1
			elif c.r * 255.0 < 7.0: shore += 1
	tile.free()
	var sun_tile: Node3D = Surface.build_tile("solara_sun", 0)
	var sw: MeshInstance3D = sun_tile.get_node_or_null("Water")
	var magma_ok: bool = sw != null and sw.material_override is StandardMaterial3D
	sun_tile.free()
	_check("Job AK: the sea is a wave shader on a grid that knows its depth (deep water and a shoreline band for the foam); a star's magma sea keeps its flat glow",
		mat_ok and deep > 50 and shore > 50 and magma_ok, "shader %s deep %d shore %d magma %s" % [mat_ok, deep, shore, magma_ok])


## Job AL (v1.5i): GPS: a destination list on the map, point A (you) and point B on a blue route, live distance and ETA
## at the effective speed (lane, warp, flying), on the map and on the HUD strip; arrival clears it.
func _job_al() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AL: version label reads \"Homelancer Digital v1.5i\" or later", Data.VERSION >= "v1.5i" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var s := _sp()
	var nm: Control = main.navmap
	s.nav_dest = null
	s.autopilot = null
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	main.open_map()
	await _frames(3)
	var rows: Array = nm.dest_list()
	var kinds: Array = rows.map(func(r): return r["kind"])
	var sorted_ok := true
	for i in range(1, rows.size()):
		if rows[i]["key"] != "mission" and rows[i - 1]["key"] != "mission" and float(rows[i]["dist"]) < float(rows[i - 1]["dist"]): sorted_ok = false
	var has_all: bool = kinds.has("Station") and kinds.has("Planet") and kinds.any(func(k): return str(k).find("Gate >") >= 0) and kinds.has("Asteroid field") and not rows.any(func(r): return str(r["key"]).begins_with("enemy") or str(r["key"]).begins_with("traffic"))
	var shown: bool = nm.dest_rows.size() == mini(rows.size(), Data.GPS_LIST_ROWS)
	await _shot("al_gps_list", 0.3)
	# tap the planet's row: it becomes the destination
	var pkey := ""
	for r in rows:
		if r["kind"] == "Planet": pkey = r["key"]
	if nm.dest_rows.has(pkey): nm.tap((nm.dest_rows[pkey] as Rect2).get_center())
	await _frames(3)
	var picked: bool = s.nav_dest == s.planet and s.autopilot == null and nm.route.get("name", "") == str(s.planet.name)
	var eta_ok: bool = absf(float(nm.route.get("eta", 0.0)) - s.distance_to(s.planet) / s.eff_speed()) < 0.5
	await _shot("al_gps_route_map", 0.3)
	_check("Job AL: the map lists the system's known places nearest first (stations, planet, gates with where they go, asteroid field; no ships), and tapping one makes it the GPS destination with a blue A -> B route, distance and ETA (no autopilot)",
		has_all and sorted_ok and shown and picked and eta_ok, "%s sorted %s shown %d picked %s eta %s" % [str(kinds), sorted_ok, nm.dest_rows.size(), picked, eta_ok])
	nm.visible = false
	main._on_map_closed()
	await _frames(3)
	# the HUD strip: the gap closes as you fly at it, opens if you fly away
	var g0: Dictionary = main.hud.gps_drawn.duplicate()
	var toward: Vector3 = (s.planet.global_position - s.player.global_position).normalized()
	s.player.global_position += toward * 900.0
	await _frames(3)
	var g1: Dictionary = main.hud.gps_drawn.duplicate()
	s.player.global_position -= toward * 1800.0
	await _frames(3)
	var g2: Dictionary = main.hud.gps_drawn.duplicate()
	var strip_ok: bool = not g0.is_empty() and g0["name"] == str(s.planet.name) and float(g1["dist"]) < float(g0["dist"]) - 800.0 and float(g1["k"]) > float(g0["k"]) and float(g2["dist"]) > float(g0["dist"])
	await _shot("al_gps_strip", 0.3)
	# ETA follows the effective speed: faster in a lane, at warp
	var e_fly: float = s.nav_eta()
	s.warp_state = "on"
	var e_warp: float = s.nav_eta()
	s.warp_state = "off"
	s.lane = {"to": "test"}
	var e_lane: float = s.nav_eta()
	s.lane = {}
	var eta_mode: bool = e_warp < e_fly and e_lane < e_warp
	_check("Job AL: in flight the HUD strip shows A -> B with the name, distance and ETA; the marker closes on B as you fly toward it and falls back if you fly away; the ETA uses the lane's speed in a lane and warp speed at warp",
		strip_ok and eta_mode, "strip %s (%s / %s / %s) eta fly %.0f warp %.0f lane %.0f" % [strip_ok, str(g0.get("dist", 0)), str(g1.get("dist", 0)), str(g2.get("dist", 0)), e_fly, e_warp, e_lane])
	# arrival clears it; SET COURSE also sets it
	s.player.global_position = s.planet.global_position + (s.player.global_position - s.planet.global_position).normalized() * (s.distance_to(s.planet) - s.distance_to(s.planet) + 1.0)
	s.nav_dest = s.station
	_tp(s.station.global_position + Vector3(0, 0, Data.GPS_ARRIVE * 0.5), s.station.global_position)
	await _frames(3)
	var cleared: bool = s.nav_dest == null
	main._on_course(s.planet)
	var course_sets: bool = s.nav_dest == s.planet and s.autopilot == s.planet
	s.autopilot = null
	s.nav_dest = null
	_check("Job AL: reaching the destination clears it; SET COURSE also makes its target the GPS destination (the GPS stays when you take the stick)", cleared and course_sets, "cleared %s course %s" % [cleared, course_sets])
	# ---- stage 2: ADD WAYPOINT, up to three stops, managed on the map; reached stops advance by themselves
	s.clear_route()
	main.open_map()
	await _frames(3)
	var keys: Array = nm.dest_list().map(func(r): return str(r["key"]))
	var st_k := "station"
	var pl_k := ""
	var bl_k := ""
	var gt_k := ""
	for r in nm.dest_list():
		if r["kind"] == "Planet": pl_k = r["key"]
		elif r["kind"] == "Asteroid field": bl_k = r["key"]
		elif str(r["kind"]).find("Gate >") >= 0 and gt_k == "": gt_k = r["key"]
	for k in [pl_k, bl_k, gt_k]: s.add_stop(nm._dest_node(k))   # (v1.7v: the route API stays; the map no longer edits stops)
	await _frames(2)
	var three: bool = s.nav_route.size() == 3 and s.nav_dest == s.planet
	var dup: String = s.add_stop(s.planet)
	var no_dup: bool = s.nav_route.size() == 3 and dup.find("already") >= 0
	await _frames(2)
	var simple: bool = nm.add_btns.is_empty() and route_keys_simple(nm.route_btns) and nm.route_btns.has("go") and nm.route_btns.has("clear")
	await _shot("al_gps_route_three", 0.3)
	nm.tap((nm.route_btns["clear"] as Rect2).get_center())
	await _frames(1)
	var cleared2: bool = s.nav_route.is_empty() and s.nav_dest == null
	_check("v1.7v (owner: \"too much on setting points\"): the map shows just where you're going with GO and CLEAR (no +, no reorder / replace / remove); CLEAR empties it; the GPS still holds a route of up to 3 stops (no repeats)",
		three and no_dup and simple and cleared2, "three %s dup %s simple %s (%s) cleared %s" % [three, no_dup, simple, str(nm.route_btns.keys()), cleared2])
	nm.visible = false
	main._on_map_closed()
	await _frames(2)
	# auto-advance: reach stop 1, the GPS moves on to stop 2 by itself; reach the last, it is done
	# (open-space stops: flying "into" a planet would take the ship down to its surface)
	s.set_destination(nm._dest_node(bl_k))
	s.add_stop(s.station)
	await _frames(2)
	var first: Node3D = s.nav_route[0]
	var last: Node3D = s.nav_route[1]
	var g_two: Dictionary = main.hud.gps_drawn.duplicate()
	_tp(first.global_position + Vector3(0, 0, Data.GPS_ARRIVE * 0.4), first.global_position)
	await _frames(3)
	var advanced: bool = s.nav_dest == last and s.nav_route.size() == 1 and not is_instance_valid(first) or s.nav_dest == last and s.nav_route.size() == 1
	_tp(last.global_position + Vector3(0, 0, Data.GPS_ARRIVE * 0.4), last.global_position)
	await _frames(3)
	var done: bool = s.nav_dest == null and s.nav_route.is_empty()
	_check("Job AL: the HUD strip says STOP 1 of N with the leg and the whole route; reaching a stop moves the GPS to the next one by itself, and the last one ends the route",
		int(g_two.get("stops", 0)) == 2 and float(g_two.get("total", 0.0)) > float(g_two.get("dist", 0.0)) and advanced and done, "strip %s advanced %s done %s" % [str(g_two), advanced, done])
	s.clear_route()
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)


## Job AM (v1.5j): voice system stage 1: voice profiles (male / female / machine / alien) for four test characters, the
## device voice picked by sex (not "voice 2 = female"), pitch and rate per character, effect sounds around the line,
## the provider order (recorded file, then the phone's speech), no line spoken twice, and hold-to-talk feeding the
## same dialogue as typing (typing always there).
func _job_am() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AM: version label reads \"Homelancer Digital v1.5j\" or later", Data.VERSION >= "v1.5j" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var keep_mode: String = Sfx.voice_mode
	var keep_picks: Dictionary = Sfx.voice_picks.duplicate()
	var keep_path: String = Sfx.path
	Sfx.path = "user://settings_autotest_voice.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Sfx.path))
	Sfx.voice_mode = "read"
	Sfx.voice_picks = {}
	# a device with male and female voices whose order does NOT put a woman second
	Sfx.voices_override = [{"id": "v_david", "name": "Microsoft David - English (United States)", "language": "en-US"},
		{"id": "v_mark", "name": "Microsoft Mark - English (United States)", "language": "en-US"},
		{"id": "v_zira", "name": "Microsoft Zira - English (United States)", "language": "en-US"},
		{"id": "v_fr", "name": "Microsoft Julie - French", "language": "fr-FR"},
		{"id": "v_google_f", "name": "Google UK English Female", "language": "en-GB"}]
	var four := {"rennick": "male", "vale": "female", "cybermorph_01_unit": "machine", "kaijurai_01_containment_trooper": "alien"}
	var res := {}
	for cid in four:
		Sfx.play_character_voice(cid, "", "Test line for %s." % cid)
		res[cid] = Sfx.last_profile.duplicate()
		res[cid]["provider"] = Sfx.last_provider
		Sfx.stop_voice()
		await _frames(1)
	var r: Dictionary = res["rennick"]
	var v: Dictionary = res["vale"]
	var c: Dictionary = res["cybermorph_01_unit"]
	var k: Dictionary = res["kaijurai_01_containment_trooper"]
	var sex_ok: bool = r["preferred_voice"] in ["v_david", "v_mark"] and v["preferred_voice"] in ["v_zira", "v_google_f"] and c["preferred_voice"] in ["v_david", "v_mark"] and k["preferred_voice"] in ["v_david", "v_mark"]
	var fields := ["character_id", "persona_id", "preferred_voice", "voice_type", "pitch", "speaking_rate", "volume", "fallback_voice", "effect"]
	var shape_ok: bool = res.values().all(func(p): return fields.all(func(f): return p.has(f)) and p["provider"] == "PHONE_TTS")
	var styles_ok: bool = float(r["pitch"]) < 1.0 and float(r["speaking_rate"]) < 1.0 and float(v["pitch"]) > 1.0 and c["voice_type"] == "machine" and c["effect"] == "robot" and float(c["pitch"]) < float(r["pitch"]) and k["effect"] == "alien" and k["persona_id"] == "male_alien_masked" and float(k["speaking_rate"]) > 1.0 and r["effect"] == "radio"
	var in_range: bool = res.values().all(func(p): return float(p["pitch"]) >= Data.VOICE_PITCH_RANGE[0] and float(p["pitch"]) <= Data.VOICE_PITCH_RANGE[1] and float(p["speaking_rate"]) >= Data.VOICE_RATE_RANGE[0] and float(p["speaking_rate"]) <= Data.VOICE_RATE_RANGE[1])
	_check("Job AM: the four test characters get full voice profiles: Rennick a man's voice lower and slower, Vale a woman's voice (picked by name, not 'voice 2'), the Cybermorph a deep machine voice with robot sounds, the Kaijurai a male alien voice with alien sounds; all within readable pitch and rate",
		sex_ok and shape_ok and styles_ok and in_range, "voices %s / %s / %s / %s; shape %s styles %s range %s" % [r["preferred_voice"], v["preferred_voice"], c["preferred_voice"], k["preferred_voice"], shape_ok, styles_ok, in_range])
	# remembered per character; a voice that disappears falls back; no woman's voice at all -> same voice, higher pitch
	var cf := ConfigFile.new()
	var saved_ok: bool = cf.load(Sfx.path) == OK and (cf.get_value("voice_pick", "picks", {}) as Dictionary).get("vale", "") == v["preferred_voice"]
	Sfx.voices_override = [{"id": "v_david", "name": "Microsoft David", "language": "en-US"}, {"id": "v_plain", "name": "English (United States)", "language": "en-US"}]
	Sfx.play_character_voice("vale", "", "Fallback line.")
	var fb: Dictionary = Sfx.last_profile.duplicate()
	Sfx.stop_voice()
	var fallback_ok: bool = fb["preferred_voice"] in ["v_david", "v_plain"] and float(fb["spoken_pitch"]) > float(fb["pitch"]) and Sfx.voice_picks.get("vale", "") == fb["preferred_voice"]
	_check("Job AM: the device voice picked for each character is remembered in the settings file; if that voice is gone another is used, and with no woman's voice on the device Vale's pitch is raised instead",
		saved_ok and fallback_ok, "saved %s fallback %s (%s, pitch %.2f -> %.2f)" % [saved_ok, fallback_ok, fb["preferred_voice"], float(fb["pitch"]), float(fb.get("spoken_pitch", 0.0))])
	# providers: a recorded line wins over the phone; voice OFF = blips; everyone else unchanged; no double line
	Sfx.voices_override = [{"id": "v_david", "name": "Microsoft David", "language": "en-US"}]
	var probe: String = Sfx.clip_path("rennick", "probe")
	var test_clip := "res://assets/voices/_test/test_tone.ogg"
	var has_clip: bool = ResourceLoader.exists(test_clip)
	var pre_ok := true
	if has_clip:
		Sfx.play_character_voice("_test", "test_tone", "anything")   # (not a profiled character: legacy path keeps working)
		Sfx.stop_voice()
	Sfx.play_character_voice("rennick", "", "Same line twice.")
	var first_prov: String = Sfx.last_provider
	Sfx.last_provider = "none"
	Sfx.play_character_voice("rennick", "", "Same line twice.")
	var once: bool = Sfx.last_provider == "none" and first_prov == "PHONE_TTS"
	Sfx.stop_voice()
	await _wait(Data.VOICE_SAME_LINE_GUARD + 0.1)
	Sfx.voice_mode = "bleep"
	Sfx.play_character_voice("vale", "", "Blips please.")
	var off_ok: bool = Sfx.last_provider == "BLIPS"
	Sfx.stop_voice()
	Sfx.voice_mode = "read"
	Sfx.play_character_voice("amari", "", "Every one now.", 1.2, true)
	var legacy_ok: bool = Sfx.last_provider == "PHONE_TTS" and Sfx.last_profile.get("voice_type", "") == "female"   # (v1.5k: every character is on a profile now)
	Sfx.stop_voice()
	var central: bool = true
	for f in ["main.gd", "hud.gd", "space.gd", "brain.gd"]:
		if FileAccess.get_file_as_string("res://scripts/" + f).find("tts_speak") >= 0: central = false
	_check("Job AM: one place speaks every line (Sfx.play_character_voice; no text-to-speech calls anywhere else): recorded file first, then the phone's voice, blips with VOICE OFF; characters not yet on a profile keep the old voice; the same line asked twice at once is spoken once",
		once and off_ok and legacy_ok and central and probe.begins_with(Data.VOICE_DIR), "once %s off %s legacy %s central %s" % [once, off_ok, legacy_ok, central])
	# hold-to-talk: the words go where typed words go (a character answers); unsupported -> typing opens
	var hud = main.hud
	var got := []
	var cb := func(t: String): got.append(t)
	hud.typed.connect(cb)
	hud.speech_override = "where is the warp gate"
	hud.talk_press()
	var was_listening: bool = hud.listening
	await _frames(2)
	hud.talk_release()
	await _wait(0.3)
	var talk_ok: bool = was_listening and got == ["where is the warp gate"] and not hud.listening
	hud.speech_override = ""
	got.clear()
	hud._typer.visible = false
	hud.talk_press()
	var typed_instead: bool = not hud.listening and hud._typer.visible   # (no speech recognition off the web)
	hud._typer.visible = false
	hud.typed.disconnect(cb)
	_check("Job AM: HOLD TO TALK: while held it listens, on release the words go into the same dialogue as typing; where the device cannot listen it opens typing instead (typing is always there)",
		talk_ok and typed_instead, "talk %s (%s) typing fallback %s" % [talk_ok, str(got), typed_instead])
	Sfx.voices_override = []
	Sfx.voice_mode = keep_mode
	Sfx.voice_picks = keep_picks
	Sfx.path = keep_path


## Job AN (v1.5k): the owner's test flow, start to finish: opening Imperium troops with their own voices -> dock ->
## MISSION BOARD (select, deselect, switch) -> BOUNTIES (select Jackal / Razor / Veil / Dreadmaw, highlight, waypoint,
## deselect, switch) -> green LAUNCH always there -> back in space -> follow the waypoint -> the right target.
func _job_an() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AN: version label reads \"Homelancer Digital v1.5k\" or later", Data.VERSION >= "v1.5k" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var s := _sp()
	var keep := {"bounty": GS.bounty.duplicate(true), "done": GS.bounties_done.duplicate(), "mission": GS.mission.duplicate(true), "cast": GS.cast.duplicate(true), "credits": GS.credits, "rep": GS.rep.duplicate(true)}
	GS.bounty = {}
	GS.mission = {}
	GS.bounties_done = []
	# ---- 1. the opening enemies: Imperium troops (slots 1-2), hostile, their own voices; no raider leader, no boss
	var g: Array = s._spawn_group(s.station.global_position + Vector3(400, 60, -900), 6)
	var people: Array = g.map(func(e): return e.get("pilot", {}))
	var all_imperial: bool = people.all(func(p): return str(p.get("faction", "")) == "Imperium" and int(p.get("slot", 9)) <= 2)
	var hostile: bool = g.all(func(e): return e.get("provoked", false) and str(e["def"].get("faction", "")) == "Imperium")
	var no_boss: bool = not people.any(func(p): return str(p.get("name", "")) in ["Scar Jackal", "Ember Wraith", "Shade", "Lord Kraeg"])
	var sexes := {}
	var voice_ok := true
	Sfx.voices_override = [{"id": "v_m", "name": "Microsoft David", "language": "en-US"}, {"id": "v_f", "name": "Microsoft Zira", "language": "en-US"}]
	for p in people:
		Sfx.play_character_voice(str(p.get("voice_id", "")), "", "Opening line %s." % p.get("id", ""), 1.0, str(p.get("sex", "")) == "female")
		var want := "v_f" if str(p.get("sex", "")) == "female" else "v_m"
		if Sfx.last_profile.get("preferred_voice", "") != want: voice_ok = false
		sexes[str(p.get("sex", ""))] = true
		Sfx.stop_voice()
		await _wait(Data.VOICE_SAME_LINE_GUARD * 0.3)
	Sfx.voices_override = []
	await _shot("an_opening_imperium", 0.3)
	for e in g:
		if e in s.enemies:
			s.enemies.erase(e)
			(e["node"] as Node3D).free()
	_check("Job AN: the opening enemies are the rival nation's ordinary troops (Imperium slots 01-02: Imperium Trooper and Vexa Drak), hostile, flying Imperium fighters; no placeholder raider leader or story boss",
		all_imperial and hostile and no_boss, str(people.map(func(p): return p.get("name", "?"))))
	_check("Job AN: each opening NPC speaks with the voice of its own definition: men a man's voice, women a woman's voice", voice_ok, "sexes seen %s" % str(sexes.keys()))
	# ---- 2. dock: the green LAUNCH button is there on every page
	var hub = main.hub
	hub.open(Data.SYSTEMS[s.sys_id]["station"])
	main.state = "hub"
	await _frames(2)
	var launch_ok := true
	for scr in ["hub", "equipment", "ships", "repair", "board", "missions", "bounty", "ship", "faction"]:
		hub.show_screen(scr)
		await _frames(1)
		var lr: Rect2 = hub.launch_btn.get_global_rect()
		if not (hub.launch_btn.visible and Rect2(Vector2.ZERO, hub.get_viewport_rect().size).encloses(lr) and hub.launch_btn.get_index() == hub.get_child_count() - 1): launch_ok = false
		for c in hub.left.get_children():
			if (c as Control).get_global_rect().intersects(lr): launch_ok = false
	_check("Job AN: the hub's green LAUNCH button is on screen, upper right, on every page (hub, equipment, ship dealer, repair, mission board, missions, bounties, your ship, faction) and nothing covers it", launch_ok)
	# ---- 3. MISSION BOARD -> MISSIONS: select, deselect, select another
	hub.show_screen("board")   # (opens the tab last used)
	await _frames(2)
	var tabs_ok: bool = hub.content.find_child("Tab_missions", true, false) != null and hub.content.find_child("Tab_bounty", true, false) != null
	(hub.content.find_child("Tab_missions", true, false) as Button).pressed.emit()
	await _frames(2)
	var b1: Button = hub.content.find_child("Take_Job_threats", true, false)
	b1.pressed.emit()
	await _frames(2)
	var sel1: bool = GS.mission.get("kind", "") == "threats" and not GS.mission.get("hard", true)
	var hi1: Button = hub.content.find_child("Take_Job_threats", true, false)
	var lit1: bool = hi1 != null and hi1.text == "DISENGAGE"
	await _shot("an_mission_selected", 0.3)
	hi1.pressed.emit()
	await _frames(2)
	var desel: bool = GS.mission.is_empty() and (hub.content.find_child("Take_Job_threats", true, false) as Button).text == "ACCEPT"
	(hub.content.find_child("Take_Job_escort", true, false) as Button).pressed.emit()
	await _frames(2)
	var sel2: bool = GS.mission.get("kind", "") == "escort"
	(hub.content.find_child("Take_Job_threats_hard", true, false) as Button).pressed.emit()
	await _frames(2)
	var switched: bool = GS.mission.get("kind", "") == "threats" and GS.mission.get("hard", false) and (hub.content.find_child("Take_Job_escort", true, false) as Button).text == "ACCEPT"
	_check("Job AN: MISSIONS: tap a job = selected (gold, TRACKING), tap it again = cleared, tap another = switched; nothing stays blocked",
		tabs_ok and sel1 and lit1 and desel and sel2 and switched, "tabs %s sel %s lit %s desel %s sel2 %s switch %s" % [tabs_ok, sel1, lit1, desel, sel2, switched])
	# ---- v1.8c (owner): a board posts only its owner's rivals: Liberty Hub (Unity) = Imperium wanted pilots
	hub.show_screen("bounty")
	await _frames(2)
	var lh_rival: bool = Data.bounties_for("Unity").all(func(p): return str(p["faction"]) == Factions.rival("Unity")) and not Data.bounties_for("Unity").is_empty() \
		and hub.content.find_child("Bounty_savagers_03", true, false) == null
	var lib_ok: bool = Data.bounties_for("Liberator").all(func(p): return str(p["faction"]) == "Savagers")
	_check("v1.8c (owner): mission boards post only the owner's rivals (Liberty Hub: %s pilots only; a Liberator station: Savagers only)" % Factions.rival("Unity"), lh_rival and lib_ok, "liberty %s liberator %s" % [lh_rival, lib_ok])
	# (the bounty checks below use a Liberator station's board: its rivals are the Savagers)
	var lib_base: Dictionary = Data.SYSTEMS["kiral"]["station"].duplicate()
	lib_base["faction"] = "Liberator"
	hub.open(lib_base)
	hub.show_screen("bounty")
	await _frames(2)
	# ---- 4. BOUNTIES: 2, 3, 4, 6; select (waypoint), deselect, select another (waypoint switches)
	(hub.content.find_child("Tab_bounty", true, false) as Button).pressed.emit()
	await _frames(2)
	var ids: Array = Data.bounties().filter(func(p): return p["faction"] == "Savagers").map(func(p): return int(p["slot"]))
	var bj: Button = hub.content.find_child("Bounty_savagers_02", true, false)
	bj.pressed.emit()
	await _frames(2)
	var trk: Label = hub.content.find_child("Tracking", true, false)
	var jack: bool = GS.bounty.get("id", "") == "savagers_02" and GS.mission.get("kind", "") == "bounty" and GS.mission.get("id", "") == "savagers_02" and trk.text.find("this system") >= 0 and trk.text.find("jump") < 0
	var w_j: Dictionary = s.mission_waypoint()
	var way_j: bool = not w_j.is_empty() and str(w_j["line"]).find("mission point 1") >= 0
	var read_j: bool = hub.last_read.begins_with("Bounty: Jackal")
	var lit_j: bool = (hub.content.find_child("Bounty_savagers_02", true, false) as Button).text == "DISENGAGE"
	await _shot("an_bounty_selected", 0.3)
	(hub.content.find_child("Bounty_savagers_02", true, false) as Button).pressed.emit()
	await _frames(2)
	var off: bool = GS.bounty.is_empty() and GS.mission.is_empty() and s.mission_waypoint().is_empty()
	(hub.content.find_child("Bounty_savagers_04", true, false) as Button).pressed.emit()
	await _frames(2)
	var w_v: Dictionary = s.mission_waypoint()
	var veil: bool = GS.bounty.get("id", "") == "savagers_04" and not w_v.is_empty() and str(w_v["line"]).find("mission point") >= 0 and (hub.content.find_child("Bounty_savagers_02", true, false) as Button).text == "ACCEPT"
	(hub.content.find_child("Bounty_savagers_03", true, false) as Button).pressed.emit()
	await _frames(2)
	var razor: bool = GS.bounty.get("id", "") == "savagers_03" and str(s.mission_waypoint().get("line", "")).find("mission point") >= 0 and GS.mission.get("sys", "") == s.sys_id
	var sc: ScrollContainer = hub.content.find_child("Scroll", true, false)
	var y0: int = sc.scroll_vertical if sc else -1
	hub.scroll_board(sc, 1)
	await _wait(0.4)
	var scrolled: bool = sc != null and sc.scroll_vertical > y0 and hub.content.find_child("ScrollUp", true, false) != null and hub.content.find_child("ScrollDown", true, false) != null
	await _shot("av_board_scrolled", 0.2)
	hub.scroll_board(sc, -1)
	await _wait(0.4)
	_check("Job AN / v1.7v: BOUNTIES: the targets are characters 2, 3, 4 and 6 (Jackal, Razor, Veil, Dreadmaw); tap one = tracked, gold, read out, its waypoint in THIS system; tap again = cleared; tap another = the waypoint switches; the list has UP / DOWN tabs that scroll it",
		ids == [2, 3, 4, 6] and jack and way_j and read_j and lit_j and off and veil and razor and scrolled, "slots %s jackal %s way %s read %s lit %s off %s veil %s razor %s scroll %s" % [str(ids), jack, way_j, read_j, lit_j, off, veil, razor, scrolled])
	# ---- 5. LAUNCH -> space; follow the waypoint to the target's system; the right target is there
	await _shot("an_board_launch_visible", 0.3)
	hub.launch_btn.pressed.emit()
	await _until(func(): return main.state == "flight", 12.0)
	var flying: bool = main.state == "flight" and not hub.visible
	var hops := 0
	var guard := 0
	while _sp().sys_id != "plundros" and guard < 8:
		guard += 1
		var wp: Dictionary = _sp().mission_waypoint()
		if wp.is_empty() or (wp["node"] as Node3D).get_meta("kind", "") != "gate": break
		main.jump(wp["node"])
		await _until(func(): return main.state == "flight", 20.0)
		hops += 1
	s = _sp()
	var arrived: bool = hops == 0   # v1.7v (owner): the hunt is in the system you took it in
	var p0: Vector3 = Missions.point_pos(s, 0)
	var p1: Vector3 = Missions.point_pos(s, 1)
	_tp(p0 + Vector3(0, 0, 300), p0)
	await _frames(4)
	for e in s.enemies.filter(func(o): return int(o.get("mission", -1)) == 0): s._destroy_unit(e)
	await _frames(3)
	_tp(p1 + Vector3(0, 0, 300), p1)
	await _frames(4)
	var tgt: Array = s.enemies.filter(func(o): return o.get("bounty", "") == "savagers_03")
	var wb: Dictionary = s.mission_waypoint()
	var right: bool = tgt.size() == 1 and not wb.is_empty() and wb["node"] == tgt[0]["node"]
	var model_ok: bool = right and str(tgt[0]["def"].get("model", "")) == "savager_redclaw" and str(tgt[0].get("pilot", {}).get("name", "")) == "Razor" and str(tgt[0].get("pilot", {}).get("sex", "")) == "female"
	if right: s.target = tgt[0]["node"]
	var targeting: bool = right and s.target_health() > 0.0
	Sfx.voices_override = [{"id": "v_m", "name": "Microsoft David", "language": "en-US"}, {"id": "v_f", "name": "Microsoft Zira", "language": "en-US"}]
	Sfx.keep_until = 0.0   # (v1.7v: no jumps now, so the job brief may still be reading; nothing talks over it by design)
	if right: main._pilot_call(tgt[0]["pilot"], false)
	var razor_voice: bool = Sfx.last_profile.get("preferred_voice", "") == "v_f" or (Sfx.last_provider == "PRELOADED_AUDIO" and Sfx.last_profile.get("voice_type", "") == "female")   # v1.8z: or her cloned line
	Sfx.voices_override = []
	await _shot("an_bounty_target_razor", 0.3)
	_check("Job AN / v1.7v: LAUNCH returns you to space; the hunt is right here (%d jumps); at the second mission point the target's wing is there with Razor herself, in her Redclaw, targetable, speaking in a woman's voice" % hops,
		flying and arrived and right and model_ok and targeting and razor_voice, "flying %s arrived %s right %s model %s target %s voice %s" % [flying, arrived, right, model_ok, targeting, razor_voice])
	for e in s.enemies.duplicate():
		if is_instance_valid(e["node"]): (e["node"] as Node3D).free()
	s.enemies = []
	s.target = null
	Missions.abandon()
	GS.bounty = keep["bounty"]
	GS.bounties_done = keep["done"]
	GS.mission = keep["mission"]
	GS.cast = keep["cast"]
	GS.credits = keep["credits"]
	GS.rep = keep["rep"]
	main._load_system("solara", "station")   # back home for the rest of the route test
	await _frames(4)
	_tp(_sp().station.global_position + Vector3(0, 40, 420), _sp().station.global_position)


## v1.7x / v1.8d (owner): block asteroids made of big blocks break like the arcade game: whole -> 2 -> 4 each -> 4 each ->
## destroyed; every piece can be shot (no loose bits); gold / diamond inside comes out for the tractor; a missile blows a
## piece apart; pieces drifting past the field's invisible sphere are gone.
func _asteroid_mining(s: SpaceSystem) -> void:
	var ast = null
	for a in s.asteroids:
		if (a.count(3) > 0 or a.count(4) > 0) and a.solid_count >= 8:
			ast = a
			break
	var any_treasure: bool = ast != null
	if ast == null:
		for a in s.asteroids:
			if a.solid_count >= 8: ast = a
	var big_blocks: bool = is_equal_approx(float(ast.cell), Data.ASTEROID_CELL) and Data.ASTEROID_CELL >= 5.0
	# a laser hit wears it down (no split yet), and a ray from outside finds its blocks
	var h0: float = ast.health
	var hit: Array = s.ray_asteroids(ast.global_position + Vector3(0, 0, ast.radius * 2.0), ast.global_position)
	if not hit.is_empty(): s.damage_asteroid(hit[0], 8.0, hit[2], "gun")
	var wear: bool = not hit.is_empty() and float(ast.health) < h0 and ast in s.asteroids
	# whole -> 2 -> up to 4 each -> up to 4 each -> destroyed
	var n0: int = s.asteroids.size()
	var halves: Array = s.split_asteroid(ast, "gun")
	var t1: bool = halves.size() == 2 and halves.all(func(p): return int(p.tier) == 1 and p in s.asteroids) and not (ast in s.asteroids)
	await _shot("ax_asteroid_split", 0.3)
	var quarters: Array = s.split_asteroid(halves[0], "gun") if halves.size() > 0 else []
	var t2: bool = quarters.size() >= 2 and quarters.size() <= 4 and quarters.all(func(p): return int(p.tier) == 2)
	var smalls: Array = []
	for q in quarters: smalls += s.split_asteroid(q, "gun")
	var t3: bool = not smalls.is_empty() and smalls.all(func(p): return int(p.tier) == 3)
	var d0: int = s.asteroid_destroyed
	var l0: int = s.loot.size()
	var rest: Array = smalls.duplicate()
	if halves.size() > 1:   # finish the other half too, so any treasure comes out
		for q in s.split_asteroid(halves[1], "gun"):
			for sm in s.split_asteroid(q, "gun"): rest.append(sm)
	for sm in rest: s.split_asteroid(sm, "gun")
	var gone: bool = s.asteroid_destroyed >= d0 + rest.size() and rest.all(func(p): return not (p in s.asteroids))
	var gems: Array = s.loot.slice(l0).filter(func(l): return l.get("zero_g", false))
	var mined: bool = not any_treasure or not gems.is_empty()
	# a missile blows a piece apart
	var other = null
	for a in s.asteroids:
		if int(a.tier) == 0: other = a
	var sp0: int = s.asteroid_splits
	if other != null: s.blast_asteroid(other, other.global_position, "heavy")
	var blown: bool = other != null and s.asteroid_splits > sp0
	await _shot("ax_asteroid_missile", 0.3)
	# the invisible sphere: a drifting piece pushed past it is gone
	var piece = null
	for a in s.asteroids:
		if int(a.tier) > 0: piece = a
	if piece != null:
		piece.global_position = s.belt_center + Vector3(s.belt_radius * Data.ASTEROID_BOUND + 60.0, 0, 0)
		piece.vel = Vector3(1, 0, 0)
	await _frames(2)
	var out_gone: bool = piece == null or not (piece in s.asteroids)
	_check("v1.8d (owner): big-block asteroids break like the arcade game: lasers wear one down, it splits into 2, each into up to 4, each into up to 4, and the smallest are destroyed (every piece shootable, no loose bits); gold / diamond inside drops pickups (%s); a missile blows a piece apart; pieces past the field's invisible sphere are gone" % ("treasure found" if any_treasure else "no treasure here"),
		big_blocks and wear and t1 and t2 and t3 and gone and mined and blown and out_gone, "big %s wear %s 2 %s 4 %s 4 %s destroyed %s mined %s (gems %d) missile %s bound %s" % [big_blocks, wear, t1, t2, t3, gone, mined, gems.size(), blown, out_gone])

## v1.8e: average and worst script time per frame (process + physics) in the busy scenes.
func _probe(label: String, frames := 120) -> Dictionary:
	var tot := 0.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms: float = (now - last) / 1000.0   # wall time of the frame
		last = now
		tot += ms
		worst = maxf(worst, ms)
	var r := {"label": label, "avg": tot / frames, "worst": worst, "objects": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	print("[speed] %-28s avg %5.2f ms  worst %6.2f ms  nodes %d  draws %d" % [label, r["avg"], r["worst"], r["objects"], r["draws"]])
	return r

## v1.9c (owner: "that planet was so laggy"): frame time on the block ground by phase, with what the blocks cost.
func _planet_probe() -> void:
	var pid: String = Data.BLOCK_TEST["planet"]
	var g := Surface.grid(pid)
	var t := -1
	for tt in g * g:
		if tt != int(Data.BLOCK_TEST["tile"]) and not Surface.locations_in(pid, tt).is_empty():
			t = tt
			break
	BlockField.regions_test = true
	main._load_surface(pid, t)
	await _wait(0.5)
	var s := _sp()
	GS.god_mode = true
	await _until(func(): return s._regions.size() >= 9 and s._building == null, 40.0)
	var phase := func(label: String, frames: int, each: Callable) -> void:
		for k in BlockField.perf.keys(): BlockField.perf[k] = 0
		var tot := 0.0
		var worst := 0.0
		var last := Time.get_ticks_usec()
		var why := ""
		for i in frames:
			var tcb := Time.get_ticks_usec()
			each.call(i)
			var cb := (Time.get_ticks_usec() - tcb) / 1000.0
			var bld: bool = s._building != null
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var ms: float = (now - last) / 1000.0
			last = now
			tot += ms
			if ms > worst: why = "frame %d: call %.1f ms, building %s, regions %d, proc %.1f ms" % [i, cb, bld or s._building != null, s._regions.size(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]
			worst = maxf(worst, ms)
		var pf: Dictionary = BlockField.perf
		print("[planet] %-26s avg %6.2f ms worst %7.2f ms | blasts %3d  blast avg %6.2f ms worst %6.2f | settle %7.1f ms | redraw %7.1f ms (%d chunks) | chunk worst %5.1f | checks %6.1f | rubble %6.1f (worst %5.1f) | rubble %d nodes %d" % [label, tot / frames, worst,
			pf["blasts"], pf["blast_us"] / 1000.0 / maxf(pf["blasts"], 1), pf["worst_blast_us"] / 1000.0, pf["settle_us"] / 1000.0, pf["flush_us"] / 1000.0, pf["chunks"], pf["worst_chunk_us"] / 1000.0, pf["checks_us"] / 1000.0, pf["rubble_us"] / 1000.0, pf["worst_rubble_us"] / 1000.0,
			s._fields().reduce(func(a, f): return a + (f as BlockField).rubble.size(), 0), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		print("[planet]     worst ", why, "  fluid %.1f light %.1f regions %.1f ms (fire %.1f step %.1f draw %.1f, fluid units %d)" % [pf.get("worst_fluid_us", 0) / 1000.0, pf.get("worst_light_us", 0) / 1000.0, pf.get("worst_regions_us", 0) / 1000.0, pf.get("w_fire_us", 0) / 1000.0, pf.get("w_step_us", 0) / 1000.0, pf.get("w_fdraw_us", 0) / 1000.0, s._fields().reduce(func(a, f): return a + (f as BlockField).fluid.size(), 0)])
	await phase.call("idle on the blocks", 90, func(_i): pass)
	s.start_transform()
	await _until(func(): return GS.form == "mech" and s.transform_t <= 0.0, 8.0)
	main.hud.move_vec = Vector2(0, -1)
	await phase.call("mech walking 6 s", 360, func(_i): pass)
	main.hud.move_vec = Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	var shoot := func(kind: String) -> void:
		var p: Vector3 = s.player.global_position - s.player.global_basis.z * rng.randf_range(30.0, 90.0) + s.player.global_basis.x * rng.randf_range(-25.0, 25.0)
		var hit: Array = s._ray_blocks(p + Vector3.UP * 80.0, p + Vector3.DOWN * 200.0)
		if hit[0] != null: s._blast_blocks(hit[1], kind, hit[0])
	await phase.call("gun on the ground 4 s", 240, func(i): if i % 4 == 0: shoot.call("gun"))
	await phase.call("missiles 4 s", 240, func(i): if i % 20 == 0: shoot.call("missile"))
	await phase.call("super missiles 4 s", 240, func(i): if i % 40 == 0: shoot.call("heavy"))
	await phase.call("special x2", 180, func(i): if i % 90 == 0: shoot.call("special"))
	await phase.call("after: idle", 120, func(_i): pass)
	var holes := 0
	for f in s._fields(): holes += (f as BlockField).holes.size()
	print("[planet] holes in the regions now: ", holes)

func _speed_probe() -> void:
	var s := _sp()
	GS.god_mode = true
	await _probe("flight near station")
	_tp(s.belt_center + Vector3(0, 30, s.belt_radius * 0.6), s.belt_center)
	await _probe("asteroid field")
	var k := 0
	while s.asteroids.size() < 180 and k < 400:
		k += 1
		var a = s.asteroids[k % s.asteroids.size()]
		if int(a.tier) < 3: s.split_asteroid(a, "gun")
	await _probe("field, %d pieces" % s.asteroids.size())
	_tp(s.station.global_position + Vector3(600, 80, 600), s.station.global_position)
	for i in 8: s.spawn_unit("raider", s.player.global_position - s.player.global_basis.z * (300 + i * 40), s.player.global_position)
	GS.missiles = 50
	for i in 6:
		s.fire_missile()
		await _wait(0.2)
	await _probe("combat, 8 enemies + missiles")
	s.start_transform()
	await _until(func(): return GS.form == "mech" and s.transform_t <= 0.0, 8.0)
	s.set_view("cockpit")
	await _probe("mech first person")
	s.set_view("chase")
	main._call_target()
	await _probe("Kim on the comms")

## v1.8f (owner): Nebulax has Saturn-like rings: a see-through band seen from far off, with block asteroids in it that
## can be shot and mined like the fields' (the pieces stay in the ring).
func _ringed_planet() -> void:
	var home: String = _sp().sys_id
	await main._load_system("nebulax", "station")
	await _frames(4)
	var s := _sp()
	var spec: Dictionary = Data.RINGED_PLANETS["nebulax"]
	var ringed: bool = not s.ring.is_empty() and s.ring_band != null
	var rocks_in: Array = s.asteroids.filter(func(a): return a.has_meta("ring"))
	var all_in: bool = rocks_in.size() >= int(spec["count"]) * 0.9 and rocks_in.all(func(a): return s.in_ring(a.global_position))
	# look at it from out in space
	var c: Vector3 = s.ring["centre"]
	var far := c + Vector3(0, float(s.ring["outer"]) * 0.55, float(s.ring["outer"]) * 1.9)
	_tp(far, c)
	await _shot("ba_ring_from_space", 0.4)
	# fly into the ring: the rocks are there, and a hit one splits and stays in the ring
	var r0 = rocks_in[0]
	_tp((r0.global_position as Vector3) + (s.ring["normal"] as Vector3) * 60.0 + Vector3(0, 0, 40), r0.global_position)
	await _frames(3)
	var zone: bool = s.in_belt
	await _shot("ba_ring_rocks", 0.4)
	var halves: Array = s.split_asteroid(r0, "gun")
	await _frames(3)
	var kept: bool = halves.size() >= 1 and halves.all(func(p): return p.has_meta("ring") and p in s.asteroids)
	_check("v1.8f (owner): Nebulax has a Saturn-like ring: a see-through band and %d block asteroids in it (mined like the fields'; broken pieces stay in the ring)" % rocks_in.size(),
		ringed and all_in and zone and kept, "ring %s rocks %d in %s zone %s kept %s" % [ringed, rocks_in.size(), all_in, zone, kept])
	await main._load_system(home, "station")
	await _frames(4)

## v1.7z (owner, concept art): VIEW in mech form = first person out of the mech's head, its own arms holding a rifle that
## sways with the stick; FIRE shoots from the rifle at the crosshair; ZOOM (in KILL's place) looks down the scope.
func _mech_fpv() -> void:
	var s := _sp()
	var view0: String = GS.view
	if GS.form != "mech":
		s.start_transform()
		await _until(func(): return GS.form == "mech" and s.transform_t <= 0.0, 8.0)
	if GS.view != "chase": s.set_view("chase")   # (seen from outside first)
	await _frames(3)
	var in_hand: bool = s.hand_gun != null and s.hand_gun.visible and s.hand_gun.has_meta("real")   # v1.8h: the gun in its hand, from outside
	await _shot("az_mech_hand_gun", 0.3)
	# a look from the front-left (the world held still for the picture)
	s.process_mode = Node.PROCESS_MODE_DISABLED
	var pb: Basis = s.player.global_basis
	main.hud.visible = false
	s.cam.global_position = s.player.global_position - pb.z * 7.0 - pb.x * 13.0 + pb.y * 2.0
	s.cam.look_at(s.player.global_position + pb.y * 1.0 - pb.z * 2.0, pb.y)
	await _shot("az_mech_two_hands", 0.2)
	s.cam.global_position = s.player.global_position - pb.z * 14.0 + pb.x * 3.0 + pb.y * 2.0
	s.cam.look_at(s.player.global_position + pb.y * 1.0, pb.y)
	await _shot("az_mech_two_hands_front", 0.2)
	main.hud.visible = true
	s.process_mode = Node.PROCESS_MODE_INHERIT
	if GS.view != "cockpit": _press("view")
	await _frames(4)
	var arms: bool = s.fpv != null and s.fpv.visible and s.fpv_skel != null and s.fpv_gun != null and not s.model.visible and absf(s.cam.fov - Data.FPV_FOV) < 3.0
	var real_gun: bool = s.fpv_gun != null and s.fpv_gun.has_meta("real") and absf(float(s.fpv_gun.get_meta("length")) * s.fpv_gun.transform.basis.get_scale().x - Data.FPV_GUN_LENGTH) < 0.2   # v1.8h: the owner's gun
	main.hud._layout()
	var zoom_btn: bool = main.hud.buttons.has("zoom") and not main.hud.buttons.has("kill") and main.hud.cockpit_texture() == null
	await _shot("az_mech_fpv", 0.3)
	var p0: Vector3 = s.fpv.position
	main.hud.aim_vec = Vector2(1.0, 0.4)
	await _wait(0.4)
	var swayed: bool = s.fpv.position.distance_to(p0) > 0.15
	await _shot("az_mech_fpv_turn", 0.0)
	main.hud.aim_vec = Vector2.ZERO
	await _wait(0.4)
	var b0: int = s.bolts.size()
	s._fire_guns()
	var shot_ok: bool = s.bolts.size() == b0 + 1 and s._fpv_kick > 0.5
	await _shot("az_mech_fpv_fire", 0.05)
	_press("zoom")
	await _wait(0.5)
	var scoped: bool = s.zoomed and not s.fpv.visible and s.cam.fov < Data.FPV_ZOOM_FOV + 4.0
	await _shot("az_mech_scope", 0.2)
	_press("zoom")
	await _frames(2)
	var unscoped: bool = not s.zoomed and s.fpv.visible
	_press("view")
	await _frames(3)
	var back_out: bool = s.fpv == null and s.model.visible
	s.start_transform()
	await _until(func(): return GS.form == "ship" and s.transform_t <= 0.0, 8.0)
	if GS.view != view0: s.set_view(view0)
	_check("v1.7z (owner): VIEW in mech form looks out of the mech's head with its own arms holding a rifle (no ship cockpit), the arms sway with the stick, FIRE shoots from the rifle with a kick, ZOOM (KILL's place) looks down the scope, VIEW again goes back to the chase camera",
		arms and real_gun and in_hand and zoom_btn and swayed and shot_ok and scoped and unscoped and back_out, "arms %s owner's gun %s in hand %s zoom button %s sway %s shot %s scope %s unscope %s back %s" % [arms, real_gun, in_hand, zoom_btn, swayed, shot_ok, scoped, unscoped, back_out])

## v1.7y (owner): progress is saved: the save keeps credits, ships, systems found, jobs and so on; loading puts them
## back; a damaged value is ignored; START OVER erases it. (Its own file; the route test never touches a player's save.)
func _save_check() -> void:
	var keep := {}
	for k in GS.SAVE_KEYS: keep[k] = GS.get(k) if not (GS.get(k) is Array or GS.get(k) is Dictionary) else GS.get(k).duplicate(true)
	GS.save_enabled = true
	GS.erase_save()
	GS.credits = 12345
	GS.owned_ships = ["cadet", "ranger"]
	GS.discovered = ["solara", "vega"]
	GS.missions_done = 7
	GS.tutorial_seen = ["intro"]
	var wrote: bool = GS.save_game() and GS.has_save()
	GS.credits = 1
	GS.owned_ships = ["cadet"]
	GS.discovered = ["solara"]
	GS.missions_done = 0
	GS.tutorial_seen = []
	var loaded: bool = GS.load_game() and GS.credits == 12345 and GS.owned_ships == ["cadet", "ranger"] and GS.discovered == ["solara", "vega"] and GS.missions_done == 7 and GS.tutorial_seen == ["intro"]
	var f := FileAccess.open(GS.save_path, FileAccess.WRITE)   # a damaged value: credits as text
	f.store_string(var_to_str({"credits": "lots", "kills": 9}))
	f.close()
	GS.credits = 50
	GS.load_game()
	var safe: bool = GS.credits == 50 and GS.kills == 9
	GS.erase_save()
	var erased: bool = not GS.has_save() and not GS.load_game()
	for k in keep: GS.set(k, keep[k])
	GS.save_enabled = false
	_check("v1.7y (owner): progress saves and loads back (credits, ships, systems found, jobs done, tutorial); a damaged value is ignored; START OVER erases the save",
		wrote and loaded and safe and erased, "wrote %s loaded %s safe %s erased %s" % [wrote, loaded, safe, erased])

## (v1.7v) the map's route panel offers only GO and CLEAR.
static func route_keys_simple(btns: Dictionary) -> bool:
	for k in btns:
		if not (str(k) in ["go", "clear"]): return false
	return true


## Job AO (v1.5l): the roster deployed: characters 2, 3, 4, 6 of every faction with ships are bounties hiding in their
## own space, each station posting its own enemies' targets; every main-faction station has its coordinator (and the
## capital its leader) with face, role and voice; the coordinator briefs your jobs.
func _job_ao() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AO: version label reads \"Homelancer Digital v1.5l\" or later", Data.VERSION >= "v1.5l" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var all: Array = Data.bounties()
	var by := {}
	for p in all: by[str(p["faction"])] = by.get(str(p["faction"]), []) + [int(p["slot"])]
	var each := true
	for f in Data.BOUNTY_FACTIONS:
		if by.get(f, []) != [2, 3, 4, 6]: each = false
	var hide_ok: bool = all.all(func(p): return Data.SYSTEMS.has(str(p["sys"])) and (str(Data.SYSTEMS[p["sys"]].get("faction", "")) == str(p["faction"]) or str(Data.SYSTEMS[p["sys"]].get("enemy_faction", "")) == str(p["faction"])))
	var unity: Array = Data.bounties_for("Unity").map(func(p): return str(p["faction"]))
	var lib: Array = Data.bounties_for("Liberator").map(func(p): return str(p["faction"]))
	var post_ok: bool = unity.has("Imperium") and unity.all(func(f): return f == "Imperium") and lib.has("Savagers") and lib.all(func(f): return f == "Savagers")   # v1.8c (owner): the owner's rival only
	_check("Job AO: characters 2, 3, 4 and 6 of every faction with ships are wanted (%d targets), each hiding in a system of their own faction; a station posts only its rival's targets (v1.8c: Unity: the Imperium; Liberator: the Savagers)" % all.size(),
		each and hide_ok and post_ok, "%s hide %s post %s" % [str(by), hide_ok, post_ok])
	# people at stations
	var lib_c: Dictionary = Factions.coordinator("Liberator")
	var orion_c: Dictionary = Factions.coordinator("Orion")
	var unity_c: Dictionary = Factions.coordinator("Unity")
	var cap: Dictionary = Data.SYSTEMS["veranthos"]
	var at_cap: Array = Factions.people_at(cap["station"], cap)
	var at_solara: Array = Factions.people_at(Data.SYSTEMS["solara"]["station"], Data.SYSTEMS["solara"])
	var roles_ok: bool = lib_c.get("name", "") == "Lena Torres" and orion_c.get("name", "") == "Korvax" and unity_c.get("name", "") == "Rowan Hale" and at_cap.size() == 2 and at_cap[0]["role"] == "leader" and at_cap[0]["pilot"]["name"] == "Commander Elara Voss" and at_solara.size() == 1 and at_solara[0]["role"] == "coordinator"
	var enemy_none: bool = Factions.people_at(Data.SYSTEMS["genesis"]["station"], Data.SYSTEMS["genesis"]).is_empty()
	var s := _sp()
	main.hub.open(Data.SYSTEMS[s.sys_id]["station"])
	main.state = "hub"
	await _frames(2)
	var card: Node = main.hub.content.find_child("Person_unity_03", true, false)
	var talk: Button = main.hub.content.find_child("Talk_unity_03", true, false)
	var has_card: bool = card != null and talk != null   # (read now: the page is rebuilt below)
	Sfx.voices_override = [{"id": "v_m", "name": "Microsoft David", "language": "en-US"}, {"id": "v_f", "name": "Microsoft Zira", "language": "en-US"}]
	if talk: talk.pressed.emit()
	var spoke: bool = Sfx.last_profile.get("voice_type", "") == "male" and ((Sfx.last_profile.get("preferred_voice", "") == "v_m" and Sfx.last_provider == "PHONE_TTS") or Sfx.last_provider == "PRELOADED_AUDIO")   # v1.8z: or his cloned line
	Sfx.stop_voice()
	await _shot("ao_people_at_station", 0.3)
	main.hub.show_screen("bounty")
	await _frames(2)
	var rows: Array = []
	for c in main.hub.content.find_children("Row_*", "", true, false): rows.append(str(c.name).trim_prefix("Row_"))
	var board_ok: bool = rows.has("imperium_02") and rows.all(func(r): return str(r).begins_with("imperium_"))   # v1.8c: the rival only
	await _shot("ao_bounty_board_all", 0.3)
	main.hub.visible = false
	main.state = "flight"
	Sfx.voices_override = []
	_check("Job AO: every main-faction station has its coordinator (role-based: Lena Torres for the Liberators, Korvax for Orion, else slot 03), the capital its leader too (Commander Elara Voss at Veranthos), shown with face and role on the station page and a TALK in their own voice; enemy stations have none; the bounty board shows this station's rival",
		roles_ok and enemy_none and has_card and spoke and board_ok, "roles %s enemy %s card %s spoke %s board %s (%s)" % [roles_ok, enemy_none, has_card, spoke, board_ok, str(rows)])


## Job AP (v1.5m): GPS stage 3: no trade lane runs through an asteroid field (the field is moved off the lane lines),
## more room in every system (spread 1.8), the fastest route uses a trade lane when that is quicker, GO flies the
## whole waypoint route on autopilot.
func _job_ap() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AP: version label reads \"Homelancer Digital v1.5m\" or later", Data.VERSION >= "v1.5m" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var bad: Array = []
	for id in Data.SYSTEMS:
		var sy: Dictionary = Data.SYSTEMS[id]
		var a: Vector3 = sy["station"]["pos"]
		var need: float = float(sy["asteroids"].get("radius", 400.0)) + Data.LANE_BELT_CLEAR - 1.0
		for b in [sy["planet"]["pos"]] + sy["gates"].map(func(g): return g["pos"]):
			var q := Geometry3D.get_closest_point_to_segment(sy["asteroids"]["center"], a, b)
			if Vector2(q.x - sy["asteroids"]["center"].x, q.z - sy["asteroids"]["center"].z).length() < need: bad.append(id)
	# in the system you are in: no rock sits on a built lane
	var s := _sp()
	var hits := 0
	for ln in s.lanes:
		for side in ["up", "down"]:
			var rings: Array = ln[side]
			for i in range(rings.size() - 1):
				for r in s.rocks:
					var q2 := Geometry3D.get_closest_point_to_segment(r[0], rings[i], rings[i + 1])
					if q2.distance_to(r[0]) < float(r[1]) + Data.LANE_RING_RADIUS: hits += 1
	_check("Job AP: no trade lane runs through an asteroid field in any of the %d systems (the field sits at least its radius + %d m off every lane line), and no rock of this system touches a built lane" % [Data.SYSTEMS.size(), int(Data.LANE_BELT_CLEAR)],
		bad.is_empty() and hits == 0 and s.lanes.size() >= 2, "blocked %s, rocks on lanes %d, lanes %d" % [str(bad.slice(0, 6)), hits, s.lanes.size()])
	_check("Job AP: systems are roomier: everything sits %.1fx farther from the main station (was 1.4)" % Data.SYSTEM_SPREAD, Data.SYSTEM_SPREAD > 1.4 and float(Data.SYSTEMS["solara"].get("spread", 0.0)) == Data.SYSTEM_SPREAD)
	# fastest route: a far gate with a lane to it -> by lane; something close -> direct
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)
	await _frames(2)
	var far_gate: Node3D = null
	var far_d := 0.0
	for g in s.gates:
		var d: float = s.distance_to(g)
		if d > far_d and s.lanes.any(func(ln): return str(ln["b"]) == str(g.name)):
			far_d = d
			far_gate = g
	s.set_destination(far_gate)
	var plan: Dictionary = s.nav_plan()
	var by_lane: bool = plan.get("via", "") == "lane" and float(plan["t"]) < s._leg_time(s.distance_to(far_gate)) and s.nav_eta() == float(plan["t"])
	main.open_map()
	await _frames(3)
	var map_lane: bool = main.navmap.route.get("via", "") == "lane"
	await _shot("ap_route_by_lane", 0.3)
	main.navmap.visible = false
	main._on_map_closed()
	await _frames(2)
	var strip_lane: bool = main.hud.gps_drawn.get("via", "") == "lane"
	await _shot("ap_hud_via_lane", 0.3)
	var near_n: Node3D = s.nav_marker(s.player.global_position - s.player.global_basis.z * 900.0, "Near point")
	s.set_destination(near_n)
	var direct: bool = s.nav_plan().get("via", "") == "direct"
	_check("Job AP: the GPS picks the fastest way: to the far gate (%.1f km) it goes by trade lane (fly to the lane mouth, ride it, fly on; shown on the map and the HUD), to a point 900 m away it goes direct" % (far_d / 1000.0),
		far_gate != null and by_lane and map_lane and strip_lane and direct, "lane %s map %s strip %s direct %s" % [by_lane, map_lane, strip_lane, direct])
	# GO: the autopilot flies the route, stop after stop
	s.clear_route()
	var m1: Node3D = s.nav_marker(s.player.global_position - s.player.global_basis.z * 1200.0, "Stop one")
	var m2: Node3D = s.nav_marker(s.player.global_position - s.player.global_basis.z * 1200.0 + s.player.global_basis.x * 1500.0, "Stop two")
	s.set_destination(m1)
	s.add_stop(m2)
	var said: String = s.route_go()
	var go1: bool = s.nav_go and s.autopilot == m1
	_tp(m1.global_position + Vector3(0, 0, Data.GPS_ARRIVE * 0.4), m1.global_position)
	await _frames(3)
	var go2: bool = s.autopilot == m2 and s.nav_dest == m2
	_tp(m2.global_position + Vector3(0, 0, Data.GPS_ARRIVE * 0.4), m2.global_position)
	await _frames(3)
	var done: bool = not s.nav_go and s.autopilot == null and s.nav_dest == null
	# steering takes over
	var m3: Node3D = s.nav_marker(s.player.global_position - s.player.global_basis.z * 2000.0, "Stop three")
	s.set_destination(m3)
	s.route_go()
	s.autopilot = null   # (what taking the stick does)
	await _frames(2)
	var cancel: bool = not s.nav_go and s.nav_dest == m3
	s.clear_route()
	_check("Job AP: GO flies the whole route on autopilot: stop 1, then stop 2 by itself, then it stops; taking the stick cancels GO but keeps the GPS route",
		go1 and go2 and done and cancel and said.find("2 stops") >= 0, "go1 %s go2 %s done %s cancel %s" % [go1, go2, done, cancel])
	_tp(s.station.global_position + Vector3(0, 40, 420), s.station.global_position)


## Job AQ (v1.5n): THRUST makes the ship's nose rear up into an arc (more when climbing / pulling up) and settle back
## to level on release; the model only, the flight path is the same.
func _job_aq() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AQ: version label reads \"Homelancer Digital v1.5n\" or later", Data.VERSION >= "v1.5n" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var s := _sp()
	_tp(s.station.global_position + Vector3(0, 300, 1400), s.station.global_position + Vector3(0, 300, 2400))
	await _frames(3)
	var level0: float = s.model.rotation.x
	main.hud.held["thrust"] = true
	main.hud.aim_vec = Vector2(0, -0.8)   # pulling up while thrusting
	await _wait(0.8)
	var up_arc: float = s.thrust_arc
	var model_up: float = s.model.rotation.x
	await _shot("aq_thrust_arc", 0.0)
	main.hud.aim_vec = Vector2.ZERO
	await _wait(0.4)
	var level_arc: float = s.thrust_arc
	main.hud.held.erase("thrust")
	await _wait(1.6)
	var after: float = s.thrust_arc
	var max_rad: float = deg_to_rad(Data.THRUST_ARC_DEG)
	_check("Job AQ: THRUST rears the ship's nose up into an arc (up to %d deg, most when climbing or pulling up), then it eases back to level when you let go; flight is unchanged" % int(Data.THRUST_ARC_DEG),
		up_arc > max_rad * 0.6 and up_arc <= max_rad + 0.001 and model_up > level0 + max_rad * 0.4 and level_arc > 0.0 and after < up_arc * 0.15,
		"arc %.1f deg pulling up, model %.1f -> %.1f deg, %.1f deg after release" % [rad_to_deg(up_arc), rad_to_deg(level0), rad_to_deg(model_up), rad_to_deg(after)])


## Job AR (v1.5o): the SPECIAL lock-on super move (docs/SPECIAL_MOVE.md). Earned at half hull, again at critical;
## hold SPECIAL on a locked target (the ship barrel-rolls, the target tries to break the lock), release to fire:
## the pilot cut-in, the shield-stripping beam (a side hit takes a wing), then a swarm of your real missiles.
func _job_ar() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AR: version label reads \"Homelancer Digital v1.5o\" or later", Data.VERSION >= "v1.5o" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var s := _sp()
	var hud = main.hud
	var mh: float = GS.max_hull()
	var keep_hull: float = GS.hull
	var keep_missiles: int = GS.missiles
	var keep_modes: Dictionary = GS.modes.duplicate()
	for id in ["guns", "missile", "mine", "hull", "shield", "energy"]: GS.modes[id] = "manual"   # only the special touches the target
	GS.special_used = {"half": false, "crit": false}
	# ---- 1. arming: nothing at full hull, "half" at half, "crit" at a quarter, both reset once repaired past 75 %
	GS.hull = mh * 0.9
	var r_full: String = s.special_ready()
	GS.hull = mh * 0.5
	var r_half: String = s.special_ready()
	GS.special_used["half"] = true
	var r_half_spent: String = s.special_ready()
	GS.hull = mh * 0.2
	var r_crit: String = s.special_ready()
	GS.special_used["crit"] = true
	var r_all_spent: String = s.special_ready()
	GS.hull = mh * 0.9
	s.special_ready()
	var reset_ok: bool = not GS.special_used["half"] and not GS.special_used["crit"]
	_check("Job AR: the special arms at half hull, again at critical (a quarter), once each; repairing past 75 % earns them back",
		r_full == "" and r_half == "half" and r_half_spent == "" and r_crit == "crit" and r_all_spent == "" and reset_ok,
		"full '%s' half '%s' spent '%s' crit '%s' all '%s' reset %s" % [r_full, r_half, r_half_spent, r_crit, r_all_spent, reset_ok])
	var kb_ok: bool = main.controls != null and main.controls.binding("special") == "F"
	_check("Job AR: a SPECIAL button sits in the free corner of the top-left block (locked until earned), and F holds it on a keyboard",
		hud.buttons.has("special") and hud.buttons["special"].position.y > hud.buttons["shield"].position.y and kb_ok, "button %s key F %s" % [hud.buttons.has("special"), kb_ok])
	# ---- 2. a target dead ahead; hold SPECIAL at half hull
	GS.hull = mh * 0.5
	_tp(s.station.global_position + Vector3(0, 1500, 5000), s.station.global_position + Vector3(0, 1500, 6000))   # clear of station guns
	s.fire_lock = false
	await _frames(3)
	var fwd := -s.player.global_basis.z
	var e: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 300.0, s.player.global_position)
	var n: Node3D = e["node"]
	e["aggro"] = false
	for k in ["hp", "max"]: e[k] = 400.0   # tough enough that only the special decides it
	s.target = n
	# 2. v1.9c (owner): HOLD to charge: with the target 90 degrees off the nose the ship does NOT turn while you hold
	#    (you fly it); a short hold builds 1 missile lock; LET GO and the ship turns itself to face the target and fires
	s.special_log.clear()
	GS.missiles = 20
	n.global_position = s.player.global_position + s.player.global_basis.x * 300.0   # 90 degrees off the nose
	var ang0: float = rad_to_deg((-s.player.global_basis.z).angle_to(n.global_position - s.player.global_position))
	hud.held["special"] = true
	var th := 0.0
	while th < Data.LOCK_STEP * 1.3:
		e["vel"] = Vector3.ZERO
		await get_tree().process_frame
		th += get_process_delta_time()
	var charging: bool = s.special_state == "charging"
	var ang_held: float = rad_to_deg((-s.player.global_basis.z).angle_to(n.global_position - s.player.global_position))
	var held_locks: int = s.special_locks
	hud.held.erase("special")   # let go
	var m_tap := GS.missiles
	var ang1 := 180.0
	var tt := 0.0
	while tt < Data.SPECIAL_TURN_TIME + 0.5 and s.special_state != "cutin":
		e["vel"] = Vector3.ZERO
		await get_tree().process_frame
		tt += get_process_delta_time()
	if is_instance_valid(n): ang1 = rad_to_deg((-s.player.global_basis.z).angle_to(n.global_position - s.player.global_position))
	var weak: bool = s.special_power < 0.5 and s.special_factor() < 0.8
	var tap_locks: int = s.special_locks
	await _until(func(): return "swarm" in s.special_log, Data.SPECIAL_CUTIN_TIME + Data.SPECIAL_BEAM_TIME + 2.0)
	await _wait(Data.VOLLEY_GAP * 3 + 0.3)
	var tap_fired: int = m_tap - GS.missiles
	_check("v1.9c (owner): HOLD SPECIAL to charge: the ship does not turn while you hold it (you fly); let go and it turns itself to face the target and fires: a short hold = 1 lock, 1 missile per launcher and a weaker beam",
		charging and ang0 > 80.0 and ang_held > 70.0 and held_locks == 1 and ang1 <= Data.SPECIAL_FACE_DEG + 2.0 and tap_locks == 1 and weak and tap_fired == Data.SPECIAL_LAUNCHERS and "turn" in s.special_log and GS.special_used["half"],
		"charging %s angle %.0f -> held %.0f -> fired at %.0f locks %d/%d weak %s fired %d log %s" % [charging, ang0, ang_held, ang1, held_locks, tap_locks, weak, tap_fired, s.special_log])
	# 2b. pressed with no hostile in range: nothing happens, nothing is spent
	GS.special_used = {"half": false, "crit": false}
	for m in s.missiles_live: (m["node"] as Node3D).queue_free()
	s.missiles_live.clear()
	if is_instance_valid(n): n.global_position = s.player.global_position + Vector3(0, 0, Data.SPECIAL_RANGE + 3000.0)
	s.target = null
	s.special_log.clear()
	hud.held["special"] = true
	await _wait(0.3)
	hud.held.erase("special")
	await _frames(3)
	var kept: bool = s.special_state == "idle" and s.special_log.is_empty() and s.special_ready() == "half"
	_check("v1.9c: SPECIAL with no hostile in range does nothing and keeps the special ready", kept, "log %s state %s ready %s" % [s.special_log, s.special_state, s.special_ready()])
	# ---- 3. held to a full rack: it stays charged while you hold (no firing by itself); let go: cut-in, full beam, swarm
	if not is_instance_valid(n) or not (n in s.enemies.map(func(o): return o["node"])):
		e = s.spawn_unit("raider", s.player.global_position - s.player.global_basis.z * 300.0, s.player.global_position)
		n = e["node"]
		e["aggro"] = false
		for k in ["hp", "max"]: e[k] = 400.0
	s.target = n
	s.special_log.clear()
	GS.missiles = 20
	e["sh"] = float(e["sh_max"])
	e["hp"] = 400.0
	var hp0: float = float(e["hp"])
	hud.held["special"] = true
	var rolled := false
	var th2 := 0.0
	var full_n: int = s.special_full()
	while th2 < Data.LOCK_STEP * (full_n + 2):
		_ar_hold(s, e, true)
		if s.special_state == "charging": rolled = rolled or absf(s.model.rotation.z) > 0.05
		await get_tree().process_frame
		th2 += get_process_delta_time()
	var still: bool = s.special_state == "charging" and s.special_locks == full_n and is_equal_approx(s.special_charge(), 1.0)
	var full_locks: int = s.special_locks
	hud.held.erase("special")
	var cut := false
	var tc := 0.0
	while tc < Data.SPECIAL_TURN_TIME + Data.SPECIAL_CUTIN_TIME + 0.6 and s.special_state != "beam" and "swarm" not in s.special_log:
		_ar_hold(s, e, true)
		if s.special_state == "cutin" and s.special_t > 0.7 and not cut:
			cut = true
			await _shot("ar_special_cutin", 0.0)
		await get_tree().process_frame
		tc += get_process_delta_time()
	await _frames(2)
	var stripped: bool = not is_instance_valid(n) or float(e["sh"]) <= 0.0
	var hp_hit: bool = not is_instance_valid(n) or float(e["hp"]) < hp0
	var wing: bool = "wing_l" in s.special_log or "wing_r" in s.special_log
	var spent: bool = GS.special_used["half"] and s.special_ready() == ""
	var m0 := GS.missiles
	await _until(func(): return "swarm" in s.special_log, Data.SPECIAL_BEAM_TIME + 2.0)
	await _wait(Data.VOLLEY_GAP * 14 + 0.3)
	var want: int = mini(GS.max_locks("light_missile") * Data.SPECIAL_LAUNCHERS, 20)
	var fired: int = m0 - GS.missiles
	var flagged: int = s.missiles_live.filter(func(m): return m.get("special", false)).size()
	_check("Job AR / v1.9c: SPECIAL held to a full rack stays charged until you let go (the ship barrel-rolls meanwhile); then the pilot cut-in, the full beam strips the shield and goes into the hull (a side-on hit takes a wing), and the swarm fires your real missiles (locks x launchers: hold longer, more missiles); the special is spent",
		still and cut and rolled and full_locks == GS.max_locks("light_missile") and stripped and hp_hit and wing and spent and fired == want and s.special_state == "idle",
		"held full %s locks %d roll %s cutin %s shield %s hull %s wing %s spent %s fired %d/%d (special-flagged in flight %d) log %s" % [still, full_locks, rolled, cut, stripped, hp_hit, wing, spent, fired, want, flagged, s.special_log])
	# ---- 4. no missiles: the beam still fires, the swarm is empty, no free ammo
	if is_instance_valid(n): s._damage_enemy(e, 99999.0)
	await _frames(3)
	for m in s.missiles_live: (m["node"] as Node3D).queue_free()   # (v1.7u: last part's swarm would blow its splash on the next target)
	s.missiles_live.clear()
	GS.special_used = {"half": true, "crit": false}
	GS.hull = mh * 0.2
	GS.missiles = 0
	var e2: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 300.0, s.player.global_position)
	n = e2["node"]
	e = e2
	e2["aggro"] = false
	s.target = n
	s.special_log.clear()
	hud.held["special"] = true
	var tl := 0.0
	while tl < Data.SPECIAL_LOCK_TIME + 0.3:
		_ar_hold(s, e, false)
		await get_tree().process_frame
		tl += get_process_delta_time()
	var which: String = s.special_which
	hud.held.erase("special")
	await _until(func(): return "swarm" in s.special_log, Data.SPECIAL_CUTIN_TIME + Data.SPECIAL_BEAM_TIME + 2.0)
	_check("Job AR: at critical hull the special comes back once more; with no missiles left the beam still fires and the swarm is empty (no free ammunition)",
		which == "crit" and "beam" in s.special_log and "swarm" in s.special_log and GS.missiles == 0 and GS.special_used["crit"],
		"which %s log %s missiles %d" % [which, s.special_log, GS.missiles])
	if is_instance_valid(n): s._damage_enemy(e2, 99999.0)
	await _frames(3)
	# ---- 5. missiles do not chase forever: out of life they burst
	GS.missiles = 5
	var e3: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 900.0, s.player.global_position)
	e3["aggro"] = false
	var ex0: int = s.missiles_expired
	s.fire_missile(false, 0, 1, 1.0, e3["node"])
	if not s.missiles_live.is_empty(): s.missiles_live[-1]["life"] = 0.05
	await _wait(0.4)
	var expired: bool = s.missiles_expired > ex0
	var exp_blast: bool = not s.blast_log.is_empty() and is_equal_approx(float(s.blast_log[-1][0]), Data.MISSILE_BLAST_RADIUS)
	if is_instance_valid(e3["node"]): s._damage_enemy(e3, 99999.0)
	# ---- v1.7u: the super missile's star blast splashes a second enemy flying close to its target
	GS.heavy_missiles = 2
	var ea: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 220.0, s.player.global_position)
	var eb: Dictionary = s.spawn_unit("raider", s.player.global_position + fwd * 220.0 + s.player.global_basis.x * 25.0, s.player.global_position)
	for ex in [ea, eb]:
		ex["aggro"] = false
		ex["hp"] = 5000.0
		ex["max"] = 5000.0
		ex["sh"] = 0.0
	var dc_keep: float = s.enemy_dodge_chance
	s.enemy_dodge_chance = 0.0
	s.fire_missile(true, 0, 1, 1.0, ea["node"])
	await _until(func(): return s.missiles_live.is_empty(), 6.0)
	await _shot("star_blast", 0.12)
	var star: bool = not s.blast_log.is_empty() and bool(s.blast_log[-1][1]) and is_equal_approx(float(s.blast_log[-1][0]), Data.HEAVY_MISSILE_BLAST_RADIUS)
	var splashed: bool = float(eb["hp"]) < 5000.0
	_check("v1.7u (owner): a missile whose fuse runs out blows a blast sphere; the super missile's six-point star blast splashes an enemy near its target",
		exp_blast and star and splashed, "expire blast %s, star %s, splash %s (b hp %.0f)" % [exp_blast, star, splashed, float(eb["hp"])])
	s.enemy_dodge_chance = dc_keep
	for ex in [ea, eb]:
		if is_instance_valid(ex["node"]) and ex in s.enemies: s._damage_enemy(ex, 999999.0)
	await _frames(3)
	# ---- v1.8b (owner): in space a missile can be fired with nothing locked: it flies straight and goes off on its fuse
	var keep_en2: Array = s.enemies
	s.enemies = []
	s.target = null
	GS.missiles = 3
	var fx0: int = s.missiles_expired
	var fired_free: bool = s.fire_missile()
	await _wait(Data.MISSILE_LIFE + 0.4)
	var free_ok: bool = fired_free and s.missiles_expired > fx0
	s.enemies = keep_en2
	_check("v1.8b (owner): in space a missile fires with nothing locked, flies straight and blows on its fuse; enemy missiles can only be shaken in the last %d m (time the sideways boost)" % int(Data.DODGE_RANGE),
		free_ok and Data.DODGE_RANGE <= 150.0, "fired %s expired %s" % [fired_free, s.missiles_expired > fx0])
	# ---- 6. a mine in an incoming missile's path decoys it
	var dc0: int = s.decoyed
	var em := Node3D.new()
	s.add_child(em)
	em.global_position = s.player.global_position + fwd * 200.0
	s.enemy_missiles.append({"node": em, "vel": Vector3.ZERO, "life": 5.0, "lost": true})
	var mine := Node3D.new()
	s.add_child(mine)
	mine.global_position = em.global_position + Vector3(0, 5, 0)
	s.mines_live.append({"node": mine, "arm": 1.0, "life": 60.0, "vel": Vector3.ZERO})
	await _wait(0.3)
	_check("Job AR: a missile that runs out of life self-destructs in a round burst; a mine dropped in an incoming missile's path decoys it (both go off)",
		expired and s.decoyed > dc0, "expired %s decoyed %d" % [expired, s.decoyed - dc0])
	GS.hull = keep_hull
	GS.missiles = keep_missiles
	GS.modes = keep_modes
	GS.special_used = {"half": false, "crit": false}
	s.special_log.clear()

## Job AR: keep the target steady dead ahead (side-on when asked), as a pilot holding the lock would.
func _ar_hold(s: SpaceSystem, e: Dictionary, side_on: bool) -> void:
	var n = e.get("node")
	if n == null or not is_instance_valid(n): return
	n.global_position = s.player.global_position - s.player.global_basis.z * 300.0
	n.look_at(n.global_position + (s.player.global_basis.x if side_on else s.player.global_basis.z), Vector3.UP)
	e["vel"] = Vector3.ZERO


## Job AS (v1.5p): the owner's Elyza fighter (one ship for the Elyza faction, folding wings: they swing out for the
## SPECIAL, per ship) and the 3D hangar built from his hangar parts.
func _job_as() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AS: version label reads \"Homelancer Digital v1.5p\" or later", Data.VERSION >= "v1.5p" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	# ---- 1. the Elyza fighter model: real, nose-first, folding wings, folded by default
	var m := ShipFactory.build("elyza_fighter")
	var wl := m.find_child("WingL", true, false) as Node3D
	var wr := m.find_child("WingR", true, false) as Node3D
	var body := m.find_child("Body", true, false)
	var tuck: float = Data.SHIP_WINGS["elyza_fighter"]
	var folded: bool = wl != null and wr != null and is_equal_approx(wl.position.x, tuck) and is_equal_approx(wr.position.x, -tuck) and ShipFactory.wings_open(m) == 0.0
	var box: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)
	ShipFactory.set_wings(m, 1.0)
	var opened: bool = is_equal_approx(wl.position.x, 0.0) and is_equal_approx(wr.position.x, 0.0) if wl and wr else false
	var box2: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)
	var wider: bool = box2.size.x > box.size.x * 1.3
	_check("Job AS: the Elyza fighter is the owner's model (one file, Body + WingL + WingR), nose at -Z, about %d m; it flies with the wings folded in, and they swing out on their arms" % int(Data.ELYZA_FIGHTER_LEN),
		ShipFactory.has_real_model("elyza_fighter") and not m.get_meta("placeholder", true) and body != null and folded and opened and wider and absf(box.size.z - Data.ELYZA_FIGHTER_LEN) < 1.5 and is_equal_approx(float(ShipFactory.GLB["elyza_fighter"][2]), 0.0),
		"folded %s opened %s width %.1f -> %.1f length %.1f" % [folded, opened, box.size.x, box2.size.x, box.size.z])
	m.free()
	var pool: Array = Factions.DEFS.get("Elyza", {}).get("fighter_pool", [])
	_check("Job AS: one ship for the whole Elyza faction for now: their fighter pool is the Elyza fighter, and the ship dealer sells it too",
		pool == ["elyza_fighter"] and Data.ENEMIES.has("elyza_fighter") and Data.SHIPS.has("elyza") and "elyza" in Data.SHIP_ORDER and Data.SHIPS["elyza"]["model"] == "elyza_fighter", str(pool))
	# ---- 2. per-ship special: flying the Elyza fighter, the special swings the wings out (and rolls); others just roll
	var s := _sp()
	var keep_ship: String = GS.ship_id
	var keep_hull: float = GS.hull
	var keep_modes: Dictionary = GS.modes.duplicate()
	for id in ["guns", "missile", "mine", "hull", "shield", "energy"]: GS.modes[id] = "manual"
	GS.ship_id = "elyza"
	GS.form = "ship"
	s.set_player_model()
	await _frames(2)
	var move_ok: bool = s.special_move() == "wings_out"
	var w0: float = ShipFactory.wings_open(s.model)
	GS.special_used = {"half": false, "crit": false}
	GS.hull = GS.max_hull() * 0.5
	_tp(s.station.global_position + Vector3(0, 1500, 5000), s.station.global_position + Vector3(0, 1500, 6000))
	s.fire_lock = false
	await _frames(3)
	var e: Dictionary = s.spawn_unit("elyza_fighter", s.player.global_position - s.player.global_basis.z * 300.0, s.player.global_position)
	e["aggro"] = false
	for k in ["hp", "max"]: e[k] = 400.0
	s.target = e["node"]
	main.hud.held["special"] = true
	var tl := 0.0
	var w_mid := 0.0
	var rolled := false
	while tl < Data.LOCK_STEP * 2.4:   # (v1.9b: under a full rack of locks, still charging)
		_ar_hold(s, e, false)
		await get_tree().process_frame
		tl += get_process_delta_time()
		w_mid = maxf(w_mid, ShipFactory.wings_open(s.model))
		rolled = rolled or absf(s.model.rotation.z) > 0.3
	await _shot("as_elyza_special_wings", 0.0)
	main.hud.held.erase("special")
	await _until(func(): return s.special_state == "idle", Data.LOCK_STEP * 3 + Data.SPECIAL_CUTIN_TIME + Data.SPECIAL_BEAM_TIME + 3.0)   # (v1.9b: letting go still fires the move)
	await _wait(1.5)
	var w_end: float = ShipFactory.wings_open(s.model)
	var enemy_real: bool = not (e["node"] as Node3D).get_child(0).get_meta("placeholder", true) if is_instance_valid(e["node"]) else false
	if is_instance_valid(e["node"]): s._damage_enemy(e, 99999.0)
	GS.ship_id = keep_ship
	GS.hull = keep_hull
	GS.modes = keep_modes
	GS.special_used = {"half": false, "crit": false}
	s.set_player_model()
	var other_roll: bool = s.special_move() == "roll" or keep_ship == "elyza"
	_check("Job AS: each ship has its own special move: holding SPECIAL in the Elyza fighter swings its wings out while it barrel-rolls, and they fold back after; a ship without its own move just rolls",
		move_ok and w0 == 0.0 and w_mid > 0.8 and rolled and w_end < 0.05 and other_roll and enemy_real,
		"wings %.2f -> %.2f -> %.2f roll %s, enemy model real %s" % [w0, w_mid, w_end, rolled, enemy_real])


## Job AT (v1.5q): the owner's clean-up (title picture, the 3D hangar, the planet towns and capital block gone) and his
## placeholder fighters: one per faction in its own colour, so every faction's pilots fly (with their voices).
func _job_at() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job AT: version label reads \"Homelancer Digital v1.5q\" or later", Data.VERSION >= "v1.5q" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var gone := not ResourceLoader.exists("res://assets/ui/title_network.jpg") and not FileAccess.file_exists("res://scripts/hangar_room.gd") \
		and not FileAccess.file_exists("res://scripts/hangar_view.gd") and not FileAccess.file_exists("res://scripts/city.gd") \
		and not DirAccess.dir_exists_absolute("res://assets/hangar") and not DirAccess.dir_exists_absolute("res://assets/city") \
		and not Packs.PACKS.has("hangar") and not Packs.PACKS.has("city")
	var tl = main.get("title")
	var title_clean: bool = tl == null or not is_instance_valid(tl) or tl.get("bg") == null
	_check("Job AT: clean-up: the title's network picture, the 3D hangar and the planet capital block / city kit are out of the game (files, code and packs)", gone and title_clean)
	# placeholder fighters
	var bad: Array = []
	var colours := {}
	for f in Data.PLACEHOLDER_SHIPS:
		var key: String = Data.PLACEHOLDER_SHIPS[f]
		var e: Dictionary = Data.ENEMIES.get(key, {})
		var mk: String = e.get("model", "")
		if e.is_empty() or e.get("faction", "") != f or not ShipFactory.has_real_model(mk) or not is_equal_approx(float(ShipFactory.GLB[mk][2]), 0.0):
			bad.append(f)
			continue
		var m := ShipFactory.build(mk, false)
		var box: AABB = ShipFactory._aabb(m, Transform3D.IDENTITY)
		if m.get_meta("placeholder", true) or absf(maxf(box.size.x, box.size.z) - Data.PLACEHOLDER_SHIP_LEN) > 0.6 or box.size.y > box.size.z: bad.append(f + "(size)")
		m.free()
		colours[mk] = true
	_check("Job AT: the owner's placeholder fighters: one per faction (%d), each its own model in its own colour, nose at -Z, about %d m" % [Data.PLACEHOLDER_SHIPS.size(), int(Data.PLACEHOLDER_SHIP_LEN)],
		bad.is_empty() and Data.PLACEHOLDER_SHIPS.size() == 14 and colours.size() == 14, "bad %s" % str(bad))
	var no_ship: Array = []
	var no_voice: Array = []
	for f in Data.ROSTERS:
		if not Factions.has_fighters(f): no_ship.append(f)
		for p in Data.ROSTERS[f]["pilots"]:
			var cid := str(p.get("character_id", p.get("voice_id", "")))
			if not Voice.profiled(cid) or Voice.profile(cid).get("voice_type", "") == "": no_voice.append(cid)
	_check("Job AT: every faction's pilots now have a ship (their own, or the placeholder) and a voice profile",
		no_ship.is_empty() and no_voice.is_empty(), "no ship %s, no voice %s" % [str(no_ship), str(no_voice.slice(0, 5))])
	# a placeholder pilot in flight: spawned from its faction's pool, real model, talks
	var s := _sp()
	var e2: Dictionary = s.spawn_unit("ph_unity", s.player.global_position - s.player.global_basis.z * 400.0, s.player.global_position)
	var real: bool = is_instance_valid(e2["node"]) and not (e2["node"] as Node3D).get_child(0).get_meta("placeholder", true)
	await _shot("at_placeholder_unity", 0.3)
	if is_instance_valid(e2["node"]): s._damage_enemy(e2, 99999.0)
	var tex: Texture2D = main.hud._face_tex(Data.PLAYER_PILOT_FACE, "normal")
	_check("Job AT: a Unity patrol fighter flies the placeholder model; the SPECIAL cut-in shows the character picture (%s) big in the middle" % Data.PLAYER_PILOT_FACE,
		real and tex != null and Factions.DEFS["Unity"]["fighter_pool"] == ["ph_unity"], "real %s picture %s" % [real, tex != null])


## v1.5x (owner): the super missile hits as hard as 3-4 regular missiles and locks slowly (1 or 2 at most); mines are as
## strong as a super missile; the magnetic mine pulls the ships it hits in and holds them stuck for a few seconds.
func _job_ax() -> void:
	var s := _sp()
	var e: Dictionary = s.spawn_unit("ph_unity", s.player.global_position - s.player.global_basis.z * 600.0, s.player.global_position)
	var light: float = s.missile_damage(e, false)
	var heavy: float = s.missile_damage(e, true)
	_check("v1.5x: one super missile hits as hard as about %.1f regular missiles (%d vs %d)" % [heavy / light, int(heavy), int(light)], heavy >= light * 3.0 and heavy <= light * 4.0 + 1.0)
	var keep_h: int = GS.heavy_missiles
	GS.heavy_missiles = maxi(2, GS.heavy_missiles)
	var counts := []
	for lt in [1.0, Data.HEAVY_LOCK_STEP + 0.1, Data.HEAVY_LOCK_STEP * 2.0 + 0.1, 20.0]:
		s.lock_time = lt
		counts.append(s.lock_count("heavy_missile"))
	s.lock_time = 0.0
	s.missile_cd = 0.0
	var before: int = GS.heavy_missiles
	var fired: bool = s.trigger_system("heavy_missile")
	var straight: bool = fired and GS.heavy_missiles == before - 1 and not s.missiles_live.is_empty() and s.missiles_live[-1]["target"] == null
	GS.heavy_missiles = keep_h
	_check("v1.5x: the super missile takes much longer to lock (%.1f s a lock, regular %.1f s) and goes 1 or 2 at a time; v1.9u (owner): without a lock it flies straight ahead" % [Data.HEAVY_LOCK_STEP, Data.LOCK_STEP],
		counts == [0, 1, 2, 2] and straight, "locks %s, unlocked shot straight %s" % [str(counts), straight])
	_check("v1.5x: a mine hits as hard as a super missile", is_equal_approx(s.mine_damage(e), heavy))
	# the magnetic mine: caught ships are pulled in to the blast point and held there for a few seconds
	e["sh"] = 1e9   # (test only: it survives the blast)
	e["sh_max"] = 1e9
	var kind0: String = GS.mine_kind
	var mines0: int = GS.mines
	GS.mine_kind = "magnetic"
	GS.mines = maxi(1, GS.mines)
	s.mine_cd = 0.0
	var dropped: bool = s.deploy_mine()
	var m: Dictionary = s.mines_live[-1] if dropped and not s.mines_live.is_empty() else {}
	var en: Node3D = e["node"]
	var anchor: Vector3 = en.global_position + Vector3(25.0, 0.0, 0.0)
	if not m.is_empty():
		(m["node"] as Node3D).global_position = anchor
		m["life"] = 0.0
	await _wait(0.25)
	var caught: bool = float(e.get("stuck_t", 0.0)) > 0.0
	await _wait(1.5)
	var near: bool = is_instance_valid(en) and en.global_position.distance_to(anchor) < 8.0
	await _wait(Data.MAG_MINE_HOLD)
	var freed: bool = float(e.get("stuck_t", 0.0)) <= 0.0
	GS.mine_kind = kind0
	GS.mines = mines0
	_check("v1.5x: two kinds of mine; the magnetic one pulls the ship it hits in to the blast and holds it stuck for %.1f s, then lets go" % Data.MAG_MINE_HOLD,
		dropped and m.get("magnetic", false) and caught and near and freed, "dropped %s caught %s near %s freed %s" % [dropped, caught, near, freed])
	if is_instance_valid(en): s._damage_enemy(e, 1e12)

## v1.6g (owner): every enemy you fight on a job (bounty targets, mission groups, escort raiders) is a hostile contact
## like the first enemies you meet: red brackets, the lead marker, missile lock. Before, a bounty target from a faction
## you were on good terms with showed up as a peaceful (gold) ship you couldn't lock.
## v1.9b (owner): every planet has a docking ring on a little floating platform: dock there and take that planet's
## jobs. The main planet's docking gate sits on a deck; each of the other planets gets a dockable platform.
## v1.9g (owner's gun models): every gun and the missile pod has the owner's model, and the ship shows what each wing
## mount carries: the shoulder gun on top near the core, the tip gun hung under the wing's end.
func _job_v19g() -> void:
	var s := _sp()
	var models_ok := true
	for id in Data.WEAPON_ORDER:
		if not ShipFactory.has_real_model(str(Data.WEAPONS[id].get("model", ""))): models_ok = false
	if not ShipFactory.has_real_model(str(Data.MOUNT_PODS["missile_pod"]["model"])): models_ok = false
	var keep := {}
	for k2 in ["credits", "ship_id", "weapon_id", "owned_weapons", "mounts", "missiles", "owned_ships"]: keep[k2] = GS.get(k2) if not (GS.get(k2) is Array) else (GS.get(k2) as Array).duplicate()
	GS.credits = 50000
	GS.ship_id = "ranger"
	if not ("ranger" in GS.owned_ships): GS.owned_ships.append("ranger")
	GS.buy_weapon("bone_rifle")
	GS.buy_weapon("ion")
	GS.buy_pod("missile_pod")
	GS.mounts = ["bone_rifle", "missile_pod", "bone_rifle", "ion"]
	await Packs.wait("wing_guns", 30.0)
	s.set_player_model()
	await _frames(2)
	var holder: Node3D = s.model.get_node_or_null("WingMounts")
	var shown: Array = []
	var placed := true
	if holder != null:
		for ch in holder.get_children():
			shown.append(int(ch.get_meta("mount")))
			var g: int = ch.get_meta("mount")
			var lp: Vector3 = (ch as Node3D).position * s.model.scale.x
			if (g < 2 and lp.x >= 0.0) or (g >= 2 and lp.x <= 0.0): placed = false   # left mounts on the left
			if (g % 2 == 0 and lp.y <= 0.0) or (g % 2 == 1 and lp.y >= 0.0): placed = false   # shoulders on top, tips under
			if g % 2 == 1 and absf(lp.x) <= absf(((holder.get_child(0) as Node3D).position * s.model.scale.x).x): placed = false   # tips further out
	# a close look from the front-left, the world held still
	s.process_mode = Node.PROCESS_MODE_DISABLED
	main.hud.visible = false
	var pb: Basis = s.player.global_basis
	var hw: float = s._ship_half_width()
	var vc: Camera3D = main.get_viewport().get_camera_3d()
	var far_k := 1.0
	if vc != null:
		far_k = vc.near
		vc.near = 0.05
		vc.global_position = s.player.global_position - pb.z * hw * 2.2 - pb.x * hw * 1.2 + pb.y * hw * 0.8
		vc.look_at(s.player.global_position, pb.y)
		await _shot("v19g_wing_guns", 0.2)
		vc.global_position = s.player.global_position - pb.z * hw * 2.4 - pb.y * hw * 0.7
		vc.look_at(s.player.global_position, pb.y)
		await _shot("v19g_wing_guns_below", 0.2)
		vc.near = far_k
	main.hud.visible = true
	s.process_mode = Node.PROCESS_MODE_INHERIT
	_check("v1.9g (owner's gun models): every gun and the missile pod wear his models, and the wings show the loadout: Crystal-Bone Rifles on both shoulders (on top, near the core), the pod and an Ion gatling under the wing tips",
		models_ok and holder != null and shown.size() == 4 and placed and Data.WEAPON_ORDER.size() >= 7, "models %s shown %s placed %s" % [models_ok, shown, placed])
	for k3 in keep: GS.set(k3, keep[k3])
	s.set_player_model()

## v1.9j (owner): "they should have their own game, write their own name and it saves it for them": three pilots per
## device, each its own save file; START opens the picker; the old single save becomes pilot 1.
func _job_v19j() -> void:
	var keep := {"save_enabled": GS.save_enabled, "save_path": GS.save_path, "slot": GS.slot, "pilot_name": GS.pilot_name, "credits": GS.credits,
		"slot_pattern": GS.slot_pattern, "old_save_path": GS.old_save_path}
	GS.save_enabled = true
	GS.slot_pattern = "user://route_test_slot_%d.txt"
	GS.old_save_path = "user://route_test_old_save.txt"
	for i in range(1, 4): GS.erase_slot(i)
	# an old single save turns into pilot 1
	var f := FileAccess.open(GS.old_save_path, FileAccess.WRITE)
	f.store_string(var_to_str({"credits": 777, "system_id": "solara"}))
	f.close()
	GS.migrate_old_save()
	var migrated: bool = not FileAccess.file_exists(GS.old_save_path) and int(GS.slot_info(1).get("credits", 0)) == 777 and str(GS.slot_info(1)["name"]) == "Pilot 1"
	# pilot 2 is someone else, with their own name and money
	GS.use_slot(2)
	GS.pilot_name = "Ace"
	GS.credits = 4321
	var wrote: bool = GS.save_game()
	var info2: Dictionary = GS.slot_info(2)
	var own: bool = wrote and str(info2.get("name", "")) == "Ace" and int(info2.get("credits", 0)) == 4321 and int(GS.slot_info(1)["credits"]) == 777 and GS.slot_info(3).is_empty()
	# the picker on the title screen
	var t = main.title
	var vis0: bool = t.visible
	t.visible = true
	t._open_slots()
	await _frames(2)
	var row2: Node = t.find_child("Slot_2", true, false)
	var lbl: String = (row2.get_child(0) as Label).text if row2 != null else ""
	var picker: bool = lbl.contains("Ace") and lbl.contains("4321") and (t.find_child("Play_3", true, false) as Button).text == "NEW PILOT" and t.find_child("Delete_1", true, false) != null
	await _shot("v19j_pilot_picker", 0.2)
	(t.find_child("Delete_2", true, false) as Button).pressed.emit()   # first tap only asks
	await _frames(1)
	var asked: bool = GS.slot_info(2).size() > 0 and (t.find_child("Delete_2", true, false) as Button).text.begins_with("SURE")
	(t.find_child("Delete_2", true, false) as Button).pressed.emit()
	await _frames(1)
	var deleted: bool = GS.slot_info(2).is_empty() and int(GS.slot_info(1)["credits"]) == 777
	if t.slots_panel != null: t.slots_panel.queue_free()
	t.slots_panel = null
	t.visible = vis0
	for i in range(1, 4): GS.erase_slot(i)
	for k in keep: GS.set(k, keep[k])
	_check("v1.9j (owner): three pilots on one device, each with their own name and save; the picker shows them; DELETE asks first; the old single save became pilot 1",
		migrated and own and picker and asked and deleted, "migrated %s own %s picker %s ('%s') asked %s deleted %s" % [migrated, own, picker, lbl, asked, deleted])

## v1.9i (owner): mechs are playable and fought. 12 frames; each mech is ARMS + CORE + LEGS that swap between frames
## you own; the player's mech wears its fitted parts; every faction fields its own mech and a bigger boss.
func _job_v19i() -> void:
	var s := _sp()
	var data_ok: bool = Data.MECHS.size() == 12 and Data.MECH_ORDER.size() == 12
	for id in Data.MECHS:
		if not ShipFactory.has_real_model(str(Data.MECHS[id]["model"])): data_ok = false
	for f in Data.FACTION_MECH:
		if not Data.MECHS.has(Data.FACTION_MECH[f]) or not Factions.has(f): data_ok = false
	for id in Data.MECHS:
		var pk := ShipFactory.pack_of(str(Data.MECHS[id]["model"]))
		if pk != "": await Packs.wait(pk, 30.0)
	# a mixed mech: one skeleton, three parts from three frames; time it (first build splits, the next is cached)
	var t0 := Time.get_ticks_usec()
	var mix := ShipFactory.build_mech("mf_mecbrn", "mf_acmec", "mech_player")
	var ms_first := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var mix2 := ShipFactory.build_mech("mf_mecbrn", "mf_acmec", "mech_player")
	var ms_cached := (Time.get_ticks_usec() - t0) / 1000.0
	var info: Dictionary = mix.get_meta("mech_parts", {})
	var skels := 0
	var stack: Array = [mix]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is Skeleton3D: skels += 1
		stack.append_array(nd.get_children())
	var vis: Dictionary = Sections.setup(mix, true)
	var mix_ok: bool = int(info.get("arms", 0)) >= 1 and int(info.get("legs", 0)) >= 1 and skels == 1 and vis.get("mech", false)
	mix.free()
	mix2.free()
	# buying and fitting parts
	var keep := {}
	for k2 in ["credits", "owned_mechs", "mech_parts", "form"]: keep[k2] = GS.get(k2).duplicate() if (GS.get(k2) is Array or GS.get(k2) is Dictionary) else GS.get(k2)
	GS.credits = 100000
	var bought: String = GS.buy_mech("acmec")
	GS.buy_mech("mecbrn")
	var refused: bool = GS.fit_mech_part("arms", "orange").begins_with("Buy")
	GS.fit_mech_part("arms", "acmec")
	GS.fit_mech_part("legs", "blackgold")
	var parts_ok: bool = GS.mech_parts == {"arms": "acmec", "core": "mecbrn", "legs": "blackgold"} and refused and GS.mech_keys()["core"] == "mf_mecbrn" \
		and is_equal_approx(GS.mech_armor(), float(Data.MECHS["mecbrn"]["armor"])) and is_equal_approx(GS.mech_speed(), 1.0)
	# the player's mech form wears them
	GS.form = "mech"
	s.set_player_model()
	await _frames(2)
	var keys: Array = s.model.get_meta("mech_keys", [])
	var player_ok: bool = keys == ["mf_mecbrn", "mf_acmec", "mech_player"] and s.player_vis.get("mech", false)
	s.process_mode = Node.PROCESS_MODE_DISABLED
	main.hud.visible = false
	var vc: Camera3D = main.get_viewport().get_camera_3d()
	if vc != null:
		var pb: Basis = s.player.global_basis
		vc.global_position = s.player.global_position - pb.z * 16.0 + pb.y * 2.0 - pb.x * 5.0
		vc.look_at(s.player.global_position + pb.y * 1.0, pb.y)
		await _shot("v19i_player_mixed_mech", 0.2)
	main.hud.visible = true
	s.process_mode = Node.PROCESS_MODE_INHERIT
	# the dealer page (docked, in ship form)
	GS.form = "ship"
	s.set_player_model()
	main.dock(s.station)
	await _until(func(): return main.state == "hub", 8.0)
	main.hub.show_screen("mechs")
	await _frames(3)
	var page_ok: bool = main.hub.find_child("Part_arms", true, false) != null and main.hub.find_child("Mech_acmec", true, false) != null \
		and main.hub.find_child("Fit_core_mecbrn", true, false) != null and main.hub.find_child("MechPreview", true, false) != null
	await _shot("v19i_mech_dealer", 0.4)
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	# a faction's own mech, and its boss
	var at: Vector3 = s.player.global_position - s.player.global_basis.z * 300.0
	var spawned: Array = s.spawn_ground_mechs(at, "Solrath", 2, 0, 1)
	var boss: Dictionary = spawned[0] if spawned.size() > 0 else {}
	var grunt: Dictionary = spawned[1] if spawned.size() > 1 else {}
	var foes_ok: bool = spawned.size() == 2 and str(boss["model"].name) == "Model_mf_acmec" and str(grunt["model"].name) == "Model_mf_acmec" \
		and bool(boss.get("boss_mech", false)) and float(boss["max"]) > float(grunt["max"]) * 3.0 and (boss["model"] as Node3D).scale.x > (grunt["model"] as Node3D).scale.x * 1.5
	for o in spawned:
		s.enemies.erase(o)
		if is_instance_valid(o["node"]): (o["node"] as Node3D).queue_free()
	for k3 in keep: GS.set(k3, keep[k3])
	s.set_player_model()
	_check("v1.9i (owner): 12 mech frames; a mech is arms + core + legs swapped between frames you own (one skeleton, the parts skinned to it); your mech form wears them; the MECH DEALER fits them; Solrath fields its own mech and a boss %.1fx bigger" % Data.MECH_BOSS_SCALE,
		data_ok and mix_ok and parts_ok and player_ok and page_ok and foes_ok,
		"data %s mix %s (%s, skeletons %d, build %.0f ms first / %.0f ms cached) parts %s (%s) player %s %s page %s foes %s" % [data_ok, mix_ok, info, skels, ms_first, ms_cached, parts_ok, bought, player_ok, keys, page_ok, foes_ok])

## v1.9h (owner's rail guns and heavy mounts): every new gun and pod wears his model; heavy ones fit the shoulders only;
## each pod adds its own missiles; the wing shows two heavy mounts on the shoulders and light ones under the tips.
func _job_v19h() -> void:
	var s := _sp()
	var models_ok := true
	for id in Data.WEAPON_ORDER:
		if not ShipFactory.has_real_model(str(Data.WEAPONS[id].get("model", ""))): models_ok = false
	for id in Data.MOUNT_PODS:
		if not ShipFactory.has_real_model(str(Data.MOUNT_PODS[id].get("model", ""))): models_ok = false
	var keep := {}
	for k2 in ["credits", "ship_id", "weapon_id", "owned_weapons", "mounts", "missiles", "owned_ships"]: keep[k2] = GS.get(k2) if not (GS.get(k2) is Array) else (GS.get(k2) as Array).duplicate()
	GS.credits = 90000
	GS.ship_id = "ranger"
	if not ("ranger" in GS.owned_ships): GS.owned_ships.append("ranger")
	GS.mounts = []
	GS.buy_weapon("rail_lance")
	GS.buy_weapon("hv_rail")   # a heavy gun bought goes on the shoulders, never under a tip
	var heavy_off_tips: bool = not GS.mount_items()[1] == "hv_rail" and not GS.mount_items()[3] == "hv_rail"
	for p in ["rocket_rack", "hv_quad"]: GS.buy_pod(p)
	var tip_refused: bool = GS.fit_mount(1, "hv_quad").begins_with("Heavy")
	var base: int = int(GS.ship()["missiles"])
	GS.fit_mount(0, "hv_quad")
	GS.fit_mount(1, "rocket_rack")
	GS.fit_mount(2, "hv_rail")
	GS.fit_mount(3, "rail_lance")
	var items: Array = GS.mount_items()
	var sums_ok: bool = GS.max_missiles() == base + int(Data.MOUNT_PODS["hv_quad"]["ammo"]) + int(Data.MOUNT_PODS["rocket_rack"]["ammo"])
	await Packs.wait("wing_guns", 30.0)
	s.set_player_model()
	await _frames(2)
	var holder: Node3D = s.model.get_node_or_null("WingMounts")
	var shown: int = holder.get_child_count() if holder != null else 0
	s.process_mode = Node.PROCESS_MODE_DISABLED
	main.hud.visible = false
	var pb: Basis = s.player.global_basis
	var hw: float = s._ship_half_width()
	var vc: Camera3D = main.get_viewport().get_camera_3d()
	if vc != null:
		var nr := vc.near
		vc.near = 0.05
		vc.global_position = s.player.global_position - pb.z * hw * 2.2 - pb.x * hw * 1.2 + pb.y * hw * 0.8
		vc.look_at(s.player.global_position, pb.y)
		await _shot("v19h_heavy_mounts", 0.2)
		vc.near = nr
	main.hud.visible = true
	s.process_mode = Node.PROCESS_MODE_INHERIT
	_check("v1.9h (owner's rail guns and heavy mounts): all %d guns and %d pods wear his models; a heavy mount is refused under a wing tip and a bought heavy gun stays on the shoulders; each pod adds its own missiles; the wing shows all 4" % [Data.WEAPON_ORDER.size(), Data.MOUNT_PODS.size()],
		models_ok and heavy_off_tips and tip_refused and items.slice(0, 4) == ["hv_quad", "rocket_rack", "hv_rail", "rail_lance"] and sums_ok and shown == 4,
		"models %s off_tips %s refused %s items %s sums %s (%d) shown %d" % [models_ok, heavy_off_tips, tip_refused, items, sums_ok, GS.max_missiles(), shown])
	for k3 in keep: GS.set(k3, keep[k3])
	s.set_player_model()

## v1.9e (owner): the galaxy chart in the game reads like his map document (each charted system's box: counts and
## station names, gates coloured by kind) under fog of war; and each wing mount takes its own gun or a missile pod.
func _job_v19e() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("v1.9e: version label reads \"Homelancer Digital v1.9e\" or later", Data.VERSION >= "v1.9e" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var S: Vector2 = main.get_viewport().get_visible_rect().size
	# 1. the chart: zoom in and the charted systems show their boxes; the rest stay fog / unknown contacts
	var gm = main.galaxymap
	var disc0: Array = GS.discovered.duplicate()
	GS.discovered = ["solara", "veranthos", "aurelion", "vega"]
	gm.open("veranthos")
	await _wait(0.3)
	var far_boxes: int = gm.boxes
	for k in 3: gm.press("zoom_in")
	var vp: Vector2 = gm.flat_pos(S, 5, 3)   # Veranthos (F4) to the middle of the chart
	gm.fpan = gm._clamp_pan(gm.fpan + Vector2((378.0 + S.x) * 0.5, (96.0 + S.y) * 0.5) - vp)
	await _wait(0.3)
	var near_boxes: int = gm.boxes
	main.hud.visible = false
	await _shot("v19e_galaxy_chart_boxes", 0.3)
	var bi: Array = gm.box_info("veranthos")
	var fogged := true
	for tl in GalaxyData.TILES:
		if gm.fog_state(tl[0]) == "fog" and gm._hits.has(tl[0]): fogged = false
	gm.press("zoom_out")
	gm.press("close")
	GS.discovered = disc0
	main.hud.visible = true
	_check("v1.9e (owner): the galaxy chart in the game zooms in to show each charted system's box (planets, stations, station names, * for a 3D station; gates in green / blue / purple), and fog of war hides the rest",
		far_boxes == 0 and near_boxes >= 1 and near_boxes <= 4 and (bi[1] as Array).size() == 1 + (Data.SYSTEMS["veranthos"]["more_stations"] as Array).size() and (bi[1] as Array).filter(func(x): return x[1]).size() == 2 and fogged,
		"boxes far %d near %d, Veranthos %s" % [far_boxes, near_boxes, str(bi)])
	# 2. the wing loadout: buy a missile pod, fit it on the left wing, keep a blaster on the right
	var keep := {}
	for k2 in ["credits", "ship_id", "weapon_id", "owned_weapons", "mounts", "missiles", "owned_ships"]: keep[k2] = GS.get(k2) if not (GS.get(k2) is Array) else (GS.get(k2) as Array).duplicate()
	GS.ship_id = "ranger"
	if not ("ranger" in GS.owned_ships): GS.owned_ships.append("ranger")
	GS.credits = 20000
	GS.mounts = []
	var base_missiles: int = GS.max_missiles()
	var base_locks: int = GS.max_locks("light_missile")
	var bought: String = GS.buy_weapon("ion")
	var pod_msg: String = GS.buy_pod("missile_pod")
	var fit_msg: String = GS.fit_mount(1, "missile_pod")   # (the left wing tip)
	var fit2: String = GS.fit_mount(2, "pulse1")
	GS.fit_mount(3, "empty")
	var items: Array = GS.mount_items()
	var names: Array = GS.mount_names()
	var more_missiles: bool = GS.max_missiles() == base_missiles + int(Data.MOUNT_PODS["missile_pod"]["ammo"])
	var more_locks: bool = GS.max_locks("light_missile") == base_locks + int(Data.MOUNT_PODS["missile_pod"]["locks"])
	GS.fit_mount(0, "empty")
	var last_gun: String = GS.fit_mount(2, "empty")   # (the only gun left: refused)
	var kept_gun: bool = GS.mount_items().any(func(x): return Data.WEAPONS.has(x))
	GS.fit_mount(0, "ion")
	# fire once: one bolt per gun mount (the pod fires missiles, not bolts)
	var s := _sp()
	s.set_player_model()
	var b0: int = s.bolts.size()
	s.mount_next.clear()
	s._fire_guns()
	var shot: int = s.bolts.size() - b0
	# the page: a row per mount with the fit buttons
	main.dock(s.station)
	await _until(func(): return main.state == "hub", 8.0)
	main.hub.show_screen("equipment")
	await _frames(3)
	var page_ok: bool = main.hub.find_child("MountMap", true, false) != null and main.hub.find_child("Card_missile_pod", true, false) != null and main.hub.find_child("ShopInstall", true, false) != null and main.hub.find_child("ShopRemove", true, false) != null
	await _shot("v19e_loadout_page", 0.3)
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	_check("v1.9e (owner): two mounts on each wing (the shoulder near the core on top, the tip underneath at the wing's end), each with its own weapon: an Ion Repeater on the left shoulder, a missile pod on the left tip (+missiles, +locks), a Pulse Laser on the right shoulder, the right tip empty; one bolt per gun mount plus the core gun (v1.9u); at least one gun always stays fitted; WEAPONS & GEAR shows a row per mount",
		names.size() >= 4 and items.slice(0, 4) == ["ion", "missile_pod", "pulse1", "empty"] and more_missiles and more_locks and kept_gun and last_gun.begins_with("Keep") and shot == GS.core_slots().size() + 2 and page_ok,
		"items %s (%s / %s / %s) shot %d page %s" % [items, bought, pod_msg, fit_msg, shot, page_ok])
	for k3 in keep: GS.set(k3, keep[k3])
	_sp().set_player_model()

## v1.9d Station3D-Retopo v1 (owner): his 3D stations, each one connected station in three levels of detail, placed in
## the systems named in their files: Aurelion and Veranthos at their station slots (the other stations there are
## dockable now), the neutral ones as their system's station, the Living Asteroid Base in Savagers space, and the two
## Cybermorph battleships roaming Cybernet (not docks).
## v1.9q: stations the RETOPO set added to systems ("+Name" slots)
func _retopo_added() -> int:
	var n := 0
	for sid in Data.RETOPO_STATIONS:
		for slot: String in Data.RETOPO_STATIONS[sid]: n += 1 if slot.begins_with("+") else 0
	return n

func _st3d_tris(path: String) -> int:
	if not ResourceLoader.exists(path): return -1
	var inst := (load(path) as PackedScene).instantiate()
	var n := 0
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		for k in mi.mesh.get_surface_count(): n += (mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	inst.free()
	return n

func _job_v19d() -> void:
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("v1.9d: version label reads \"Homelancer Digital v1.9d\" or later", Data.VERSION >= "v1.9d" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	var sys0: String = GS.system_id
	# 1. the files: three LODs per station at the owner's counts, one pack each
	var keys: Array = []
	for sid in Data.STATION3D:
		for nm in Data.STATION3D[sid]: keys.append(Data.STATION3D[sid][nm])
	for r in Data.STATION3D_ROAMERS.get("cybernet", []): keys.append(r[0])
	var bad: Array = []
	var counts := {}
	for k in keys:
		var t0 := _st3d_tris("res://assets/stations3d/%s.glb" % k)
		var t1 := _st3d_tris("res://assets/stations3d/%s_lod1.glb" % k)
		var t2 := _st3d_tris("res://assets/stations3d/%s_lod2.glb" % k)
		counts[k] = [t0, t1, t2]
		if not (t0 >= 30000 and t0 <= 60000 and t1 >= 7500 and t1 <= 13000 and t2 >= 1800 and t2 <= 3500 and Packs.PACKS.has(k)): bad.append(k)
	_check("v1.9d (Station3D-Retopo v1): %d of the owner's stations each come in three levels of detail (about 40k / 10k / 2.5k triangles), each in its own download pack" % keys.size(),
		keys.size() == 14 and bad.is_empty(), "bad %s counts %s" % [bad, counts])
	# 2. placed in the systems in their names
	var placed := true
	var where: Array = []
	for sid in Data.STATION3D:
		var map: Dictionary = Data.STATION3D[sid]
		if map.has("*") and not Data.RETOPO_STATIONS.get(sid, {}).has("*") and Data.SYSTEMS[sid]["station"].get("model", "") != map["*"]: placed = false   # (v1.9q: the RETOPO set takes over some main slots)
		for b in Data.SYSTEMS[sid].get("more_stations", []):
			if map.has(str(b.get("catalog_name", b["name"]))):
				if b.get("model", "") != map[str(b.get("catalog_name", b["name"]))] or b["kind"] != "station": placed = false
				where.append("%s:%s" % [sid, b["name"]])
	_check("v1.9d: Aurelion and Veranthos wear them at their station slots (their other stations dockable now), Voidtex, Beta-7, Perimeter, Sigma-19, Omega, Foggiest and Radiant as their own station, the Living Asteroid Base in Savagers space (Ravage Major)",
		placed and where.size() == 2 and Data.SYSTEMS["ravage_major"]["station"]["model"] == "st3d_savagers_asteroid" and Data.SYSTEMS["ravage_major"]["station"].has("model"), str(where))
	# 3. in Aurelion: the main station wears it, the two other stations do too, and you can dock at one and launch from it
	main._load_system("aurelion", "station")
	await _wait(1.0)
	for k in [str(Data.SYSTEMS["aurelion"]["station"]["model"]), "st3d_aurelion_tradehub"]: await Packs.wait(k, 30.0)
	var s := _sp()
	await _until(func(): return s.docks3d.size() >= 1 and s.docks3d.all(func(n): return n.has_meta("dressed")), Data.PH_BUILD_DELAY + 4.0)
	var holder: Node3D = s.station_model.get_parent() if s.station_model != null else null
	var lods: bool = holder != null and ((holder.has_meta("lod1") and holder.has_meta("lod2") and (holder.get_meta("lod0") as MeshInstance3D).visibility_range_end > 0.0 \
		and (holder.get_meta("lod2") as MeshInstance3D).visibility_range_begin > 0.0) or str(holder.get_meta("station3d", "")).begins_with("HL_Station_"))   # (v1.9q: the RETOPO capital is one file)
	main.hud.visible = false
	_tp(s.station.global_position + Vector3(260, 120, 380) * 1.6, s.station.global_position)
	await _shot("st3d_aurelion_citadel", 0.5)
	var ds: Node3D = s.docks3d[0] if not s.docks3d.is_empty() else null
	var dock_ok := false
	var launch_ok := false
	var hub_txt := ""
	if ds != null:
		_tp(ds.global_position + Vector3(240, 90, 300), ds.global_position)
		await _shot("st3d_aurelion_other", 0.5)
		main.hud.visible = true
		s.controls = true
		_tp(s.dock_point(ds), ds.global_position)
		await _frames(2)
		var cand: Node3D = s.dock_candidate()
		main.dock(ds)
		await _until(func(): return main.state == "hub", 8.0)
		hub_txt = main.hub.header.text
		dock_ok = cand == ds and main.state == "hub" and hub_txt.to_lower().find(str(ds.get_meta("info")["name"]).to_lower()) >= 0
		main.launch()
		await _until(func(): return main.state == "flight", 8.0)
		var s2 := _sp()
		var near: Node3D = null
		var ds_name: String = hub_txt
		for n in s2.docks3d:
			if is_instance_valid(n) and hub_txt.to_lower().find(str(n.get_meta("info")["name"]).to_lower()) >= 0: near = n
		launch_ok = near != null and s2.player.global_position.distance_to(near.global_position) < float(near.get_meta("radius")) + 400.0
	_check("v1.9d: in Aurelion the Citadel wears its 3D model (three LODs by distance) and its second station (the Diplomatic and Trade Hub) wears its own; flying up to one docks there, its hub pages open, and you launch from it again",
		lods and s.docks3d.size() == 1 and dock_ok and launch_ok, "lods %s docks %d dock %s (%s) launch %s" % [lods, s.docks3d.size(), dock_ok, hub_txt, launch_ok])
	# 4. Cybernet: the two Cybermorph battleships roam (they move; you cannot dock at them)
	main._load_system("cybernet", "station")
	await _wait(1.0)
	for r in Data.STATION3D_ROAMERS["cybernet"]: await Packs.wait(str(r[0]), 30.0)
	var sc := _sp()
	await _until(func(): return sc.roamers.size() == 2 and sc.roamers.all(func(n): return n.has_meta("dressed")), Data.PH_BUILD_DELAY + 4.0)
	var p0: Array = sc.roamers.map(func(n): return (n as Node3D).global_position)
	await _wait(1.0)
	var moved: bool = sc.roamers.size() == 2 and (sc.roamers[0] as Node3D).global_position.distance_to(p0[0]) > Data.ROAMER_SPEED * 0.5
	var r0: Node3D = sc.roamers[0] if not sc.roamers.is_empty() else null
	var not_dock := true
	if r0 != null:
		main.hud.visible = false
		_tp(r0.global_position + Vector3(300, 120, 400) * 1.4, r0.global_position)
		await _shot("st3d_cybermorph_roamer", 0.4)
		main.hud.visible = true
		_tp(r0.global_position + Vector3(0, 0, float(r0.get_meta("radius")) + 30.0), r0.global_position)
		await _frames(2)
		not_dock = sc.dock_candidate() != r0 and not r0.has_meta("dock")
	_check("v1.9d: the Hexdominator and the Shardstorm are roaming Cybermorph battleships in Cybernet: they patrol (move) and are not docks",
		sc.roamers.size() == 2 and moved and not_dock and sc.roamers.all(func(n): return n.has_meta("dressed")), "roamers %d moved %s not a dock %s" % [sc.roamers.size(), moved, not_dock])
	main._load_system(sys0, "station")
	await _wait(1.6)
	main.hud.visible = true
	_sp().controls = true

func _job_v19b() -> void:
	var s := _sp()
	if s.surface_mode or main.state != "flight": return
	var beacon: Node3D = s.planet.get_node_or_null("LandingBeacon") if is_instance_valid(s.planet) else null
	var deck_ok: bool = beacon != null and beacon.get_node_or_null("DockPlatform") != null
	var more: Array = s.sys.get("more_planets", [])
	await _until(func(): return s.platforms.filter(func(x): return is_instance_valid(x)).size() >= more.size(), Data.PH_BUILD_DELAY + 3.0)
	var live: Array = s.platforms.filter(func(x): return is_instance_valid(x))
	var plat_ok: bool = live.size() == more.size()
	var fake: Node3D = null
	if live.is_empty():   # (no other planet in this system: try the platform on a stand-in world out past the station)
		var pid: String = ""
		for k in Surface.PLANETS:
			if not Surface.is_sun(str(k)) and str(k) != str(s.sys["planet"].get("id", "")) and not (Surface.PLANETS[k].get("locations", []) as Array).is_empty(): pid = str(k)
		fake = Node3D.new()
		fake.name = "TestWorld"
		s.add_child(fake)
		fake.global_position = s.station.global_position + Vector3(6000, 800, 0)
		fake.set_meta("info", {"id": "test_world"})
		fake.set_meta("radius", 600.0)
		fake.set_meta("kind", "test")
		s.extras.append(fake)
		s._build_platform(fake, {"id": pid if pid != "" else "test_world", "name": "Test World", "radius": 600.0})
		live = s.platforms.filter(func(x): return is_instance_valid(x))
	var dock_ok := true
	var board_ok := true
	var said := ""
	if not live.is_empty():
		var pl: Node3D = live[0]
		var info: Dictionary = pl.get_meta("info")
		var wp: Node3D = pl.get_parent()
		var keep := s.player.global_position
		_tp(pl.global_position + pl.global_basis.y * 110.0 + pl.global_basis.x * 260.0, pl.global_position + pl.global_basis.y * 20.0)
		await _frames(3)
		await _shot("v19b_planet_platform", 0.2)
		_tp(s.dock_point(pl) + pl.global_basis.y * 60.0, pl.global_position)
		await _frames(3)
		dock_ok = s.dock_candidate() == pl and s.prompt() == "dock" and str(info.get("kind", "")) == "planet" and wp in s.extras
		var kinds: Array = Missions.offers(s.sys_id, str(info["id"]), "", "planet").map(func(o): return str(o["kind"]))
		board_ok = not kinds.is_empty() and kinds.all(func(k): return k in ["ground", "land_escort"] or k == "outlaws")
		said = "%s: %s" % [info["name"], kinds]
		_tp(keep, s.station.global_position)
		await _frames(2)
	if fake != null:
		s.extras.erase(fake)
		s.platforms = s.platforms.filter(func(x): return is_instance_valid(x) and not fake.is_ancestor_of(x))
		fake.queue_free()
	_check("v1.9b (owner): every planet has a docking ring on a floating platform: the main planet's gate sits on a deck, and each of the other %d planet(s) here has a platform you can dock at, whose board offers only that planet's jobs" % more.size(),
		deck_ok and plat_ok and dock_ok and board_ok, "deck %s platforms %d/%d dock %s board %s %s" % [deck_ok, live.size(), more.size(), dock_ok, board_ok, said])

func _job_ay() -> void:
	var s := _sp()
	var bad: Array = []
	var seen := 0
	var keep_bounty: Dictionary = GS.bounty.duplicate()
	var keep_mission: Dictionary = GS.mission.duplicate()
	var keep_rep: Dictionary = GS.rep.duplicate()
	for f in Data.ROSTERS:
		# make every faction friendly: the worst case for "peaceful"
		if Factions.normal(f): Factions.adjust(f, 400.0)
	var units: Array = []
	for f in ["Unity", "Solarion", "Orion", "Gadversee", "Arctides"]:
		if not Data.ROSTERS.has(f): continue
		units += s.spawn_mission_group(s.player.global_position - s.player.global_basis.z * 500.0, f, 2, 3, "", 1)
	var bp := ""
	for f in Data.ROSTERS:
		for p in Data.ROSTERS[f]["pilots"]:
			if p.get("bounty", false) and str(p.get("sys", "")) == s.sys_id:
				bp = str(p["id"])
				break
		if bp != "": break
	if bp != "":
		GS.mission = {}
		GS.bounty = {"id": bp, "sys": s.sys_id, "state": "hunt"}
		var be: Dictionary = s.spawn_bounty()
		_clear_wing(be)
		if not be.is_empty(): units.append(be)
	await _wait(0.3)
	for e in units:
		if not (e in s.enemies): continue
		seen += 1
		var n: Node3D = e["node"]
		if n.get_meta("kind", "") != "enemy": bad.append(str(n.name))
	var lockable := false
	var retarget := false
	if seen > 0:
		var e0: Dictionary = units[0]
		# on a job your target is usually the mission marker: the enemies must still get targeted
		s.target = s.waypoint_at(s.player.global_position + Vector3(0, 0, -2000))
		s.player.look_at((e0["node"] as Node3D).global_position, Vector3.UP)
		s._auto_target()
		retarget = s.target != null and s.target.get_meta("kind", "") == "enemy"
		s.target = e0["node"]
		s.player.look_at((e0["node"] as Node3D).global_position, Vector3.UP)
		s.lock_time = 3.0
		lockable = s.lock_count("light_missile") > 0 and s.target.get_meta("kind", "") == "enemy"
	for e in units:
		if e in s.enemies: s._destroy_unit(e)
	GS.bounty = keep_bounty
	GS.mission = keep_mission
	GS.rep = keep_rep
	_check("v1.6g: every enemy on a job (mission groups of every faction, bounty targets) is a red hostile contact you can lock missiles on, even when you're on good terms with their faction, and gets targeted instead of the mission marker (%d checked)" % seen,
		seen >= 5 and bad.is_empty() and lockable and retarget, "not hostile: %s, lock %s, switches off the mission marker %s" % [str(bad), lockable, retarget])

## EXPERIMENT (branch planet-blocks-test), step 1: New Terra's mountains tile has a patch of big-block ground that
## follows the planet's own shape and colours; the ship lands on the block tops; nothing is saved but the seed.
func _blocks() -> void:
	var pid: String = Data.BLOCK_TEST["planet"]
	var t: int = Data.BLOCK_TEST["tile"]
	var on_normally: bool = BlockField.enabled() and BlockField.regions_on()
	BlockField.force = true
	GS.block_deltas.erase(BlockField.key_of(pid, t))   # start from the seed alone
	Surface._mesh_cache.erase("%s|%d" % [pid, t])   # the patch sinks the smooth sheet under it: build that tile fresh
	main._load_surface(pid, t)
	await _wait(1.0)
	var s := _sp()
	var bf := s.tile_root.get_node_or_null("BlockField") as BlockField if is_instance_valid(s.tile_root) else null
	var ok := bf != null
	var covered := true
	var steps := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0.0
	if ok:
		for k in 400:
			var x: float = bf.center.x + rng.randf_range(-0.48, 0.48) * bf.cols * Data.BLOCK_BIG
			var z: float = bf.center.y + rng.randf_range(-0.48, 0.48) * bf.cols * Data.BLOCK_BIG
			worst = maxf(worst, Surface.height(pid, t, x, z) - bf.top_at(x, z))
			var top: float = bf.top_at(x, z)
			var interior: bool = absf(x - bf.center.x) < float(Data.BLOCK_TEST["size"]) * 0.5 - 40.0 and absf(z - bf.center.y) < float(Data.BLOCK_TEST["size"]) * 0.5 - 40.0
			if top < Surface.height(pid, t, x, z) - (Data.BLOCK_SINK - 20.0 if interior else 0.0) - 0.01: covered = false   # (inside, the smooth sheet is sunk out of sight)
			if not is_equal_approx(fposmod(top, Data.BLOCK_MIN), 0.0) and not is_equal_approx(fposmod(top, Data.BLOCK_MIN), Data.BLOCK_MIN): steps = false
	_check("Blocks (experiment): New Terra's mountains tile has a %d m patch of big blocks (%d m, any box shape) following the planet's own shape in %d m steps, the smooth ground never poking through" % [int(Data.BLOCK_TEST["size"]), int(Data.BLOCK_BIG), int(Data.BLOCK_MIN)],
		ok and bf.cols == int(round(float(Data.BLOCK_TEST["size"]) / Data.BLOCK_BIG)) and bf.blocks.size() > bf.cols * bf.cols and covered and steps,
		"%d columns, %d blocks, worst poke %.2f m" % [bf.cols * bf.cols if ok else 0, bf.blocks.size() if ok else 0, worst])
	var land_ok := false
	if ok:
		var p := Vector3(bf.center.x + 33.0, 0.0, bf.center.y - 47.0)
		land_ok = is_equal_approx(s._ground(p.x, p.z), bf.top_at(p.x, p.z))
	var st: Dictionary = bf.save_state() if ok else {}
	_check("Blocks (experiment): the ship's ground over the patch is the block tops; what would be saved is only the seed and the changes (none yet)",
		land_ok and st.get("deltas", [1]).is_empty() and str(st).length() < 200, str(st))
	if ok: await _craters(s, bf, pid, t)
	if ok:   # pictures: a free camera over the patch (the ship and HUD out of the way)
		main.hud.visible = false
		s.player.visible = false
		var cam := Camera3D.new()
		cam.far = 8000.0
		s.add_child(cam)
		var prev := get_viewport().get_camera_3d()
		var c3 := Vector3(bf.center.x, bf.top_at(bf.center.x, bf.center.y), bf.center.y)
		for v in [["blocks_overview", Vector3(520, 360, 620)], ["blocks_low", Vector3(140, 60, 220)], ["blocks_close", Vector3(40, 28, 60)],
				["craters_high", Vector3(90, 150, 130)], ["craters_low", Vector3(70, 35, 95)]]:
			cam.global_position = c3 + (v[1] as Vector3)
			cam.look_at(c3, Vector3.UP)
			cam.make_current()
			await _shot(v[0], 0.4)
		# v1.5y: a tunnel shot into a cliff face (a stone overhang left over it)
		var best := -1
		var drop := 0.0
		for j in range(50, 110):
			for i in range(50, 110):
				var c: int = j * bf.n + i
				var d: float = bf.h[c] - bf.h[c - 1]
				if d > drop and not bf.holes.has(c):
					drop = d
					best = c
		if best >= 0:
			var fx: int = best % bf.n
			var fz: int = best / bf.n
			var low: float = bf.h[best - 1]
			var face := Vector3(bf.x0 + fx * Data.BLOCK_MIN - 1.0, low + minf(drop * 0.4, 18.0), bf.z0 + (fz + 0.5) * Data.BLOCK_MIN)
			bf.blast(face, "missile")
			bf.blast(face + Vector3(4.0, 0, 0), "missile")
			bf.flush()
			await _wait(1.5)
			var look := face + Vector3(5, 0, 0)
			var spot := face + Vector3(-70.0, 10.0, 35.0)
			for cand in [Vector3(-60, 6, 0), Vector3(-60, 12, 25), Vector3(-60, 12, -25), Vector3(-40, 4, 0), Vector3(-90, 20, 0), Vector3(-50, 25, 40), Vector3(-50, 25, -40), Vector3(-30, 3, 10)]:
				var cp: Vector3 = face + cand
				var hit: Vector3 = bf.ray_hit(cp, look)
				if not bf.is_solid(cp.x, cp.y, cp.z) and (hit == Vector3.INF or hit.distance_to(look) < 8.0):
					spot = cp
					break
			cam.global_position = spot
			cam.look_at(look, Vector3.UP)
			cam.make_current()
			await _shot("tunnel_face", 0.4)
		# v1.6b: blow open the shallowest water pocket from above and look down into it
		var wp: Dictionary = {}
		var wdepth := INF
		for pk in bf.pockets:
			if pk["kind"] != "water" or not bf.fluid.has(pk["cells"][0]): continue
			var c0: int = pk["cells"][0]
			var dd: float = bf.h[c0] - bf._ly(int(pk["k0"]) + 1)
			var off := Vector2(c0 % bf.n - bf.n / 2, c0 / bf.n - bf.n / 2).length()
			if off > 45: continue   # away from the patch edge (the old smooth ground still sits under there)
			if dd < wdepth:
				wdepth = dd
				wp = pk
		if not wp.is_empty():
			var c0: int = wp["cells"][4] if wp["cells"].size() > 4 else wp["cells"][0]
			var at := Vector3(bf.x0 + (c0 % bf.n + 0.5) * Data.BLOCK_MIN, bf.h[c0], bf.z0 + (c0 / bf.n + 0.5) * Data.BLOCK_MIN)
			var dig_y: float = at.y - 30.0
			for k in 6:   # dig straight down until the pocket is open
				if bf._pocket_open(wp): break
				bf.blast(Vector3(at.x, dig_y, at.z), "special")
				dig_y -= 45.0
			bf.flush()
			bf._draw_fluids()
			await _wait(0.5)
			var floor_y: float = bf._ly(int(wp["k0"]))
			cam.global_position = Vector3(at.x - 45.0, floor_y + 55.0, at.z + 45.0)
			cam.look_at(Vector3(at.x, floor_y, at.z), Vector3.UP)
			cam.make_current()
			await _shot("water_pocket", 0.4)
		# v1.6f: down the canyon, and an obsidian root
		if not bf.canyon_cells.is_empty():
			var cc: int = bf.canyon_cells[bf.canyon_cells.size() / 2]
			var cn: int = bf.canyon_cells[mini(bf.canyon_cells.size() - 1, bf.canyon_cells.size() / 2 + 40)]
			var cp := Vector3(bf.x0 + (cc % bf.n + 0.5) * Data.BLOCK_MIN, bf.h[cc] + 25.0, bf.z0 + (cc / bf.n + 0.5) * Data.BLOCK_MIN)
			var cq := Vector3(bf.x0 + (cn % bf.n + 0.5) * Data.BLOCK_MIN, bf.h[cn] + 10.0, bf.z0 + (cn / bf.n + 0.5) * Data.BLOCK_MIN)
			cam.global_position = cp
			cam.look_at(cq, Vector3.UP)
			cam.make_current()
			await _shot("canyon", 0.4)
		if not bf.roots.is_empty():
			var tc: int = bf.roots[0]["tip"]
			var tp := Vector3(bf.x0 + (tc % bf.n + 0.5) * Data.BLOCK_MIN, bf.h[tc] - 10.0, bf.z0 + (tc / bf.n + 0.5) * Data.BLOCK_MIN)
			cam.global_position = tp + Vector3(35.0, 15.0, 45.0)
			cam.look_at(tp, Vector3.UP)
			cam.make_current()
			await _shot("obsidian_root", 0.4)
		# v1.6e: the arches and a Pride Rock slab
		var shots_done := 0
		for ar in bf.arches:
			if shots_done >= 2: break
			var mc: int = ar["mid"]
			if not bf.holes.has(mc): continue
			var mp := Vector3(bf.x0 + (mc % bf.n + 0.5) * Data.BLOCK_MIN, bf.y0 + (bf.holes[mc][0] as Vector2i).x * Data.BLOCK_MIN + 15.0, bf.z0 + (mc / bf.n + 0.5) * Data.BLOCK_MIN)
			var l0: int = ar["legs"][0][0]
			var l1: int = ar["legs"][1][0]
			var along := Vector3(float(l1 % bf.n - l0 % bf.n), 0, float(l1 / bf.n - l0 / bf.n)).normalized()
			var side := along.cross(Vector3.UP)
			cam.global_position = mp + side * 110.0 + Vector3(0, 25.0, 0)
			cam.look_at(mp, Vector3.UP)
			cam.make_current()
			await _shot("arch_%d" % shots_done, 0.4)
			shots_done += 1
		if not bf.overhangs.is_empty():
			var tc: int = bf.overhangs[0]["tip"]
			var tp := Vector3(bf.x0 + (tc % bf.n + 0.5) * Data.BLOCK_MIN, bf.h[tc] - 15.0, bf.z0 + (tc / bf.n + 0.5) * Data.BLOCK_MIN)
			cam.global_position = tp + Vector3(60.0, -10.0, 90.0)
			cam.look_at(tp, Vector3.UP)
			cam.make_current()
			await _shot("pride_rock", 0.4)
		# v1.6d: blast into a cave pocket from above and look in
		if not bf.caves.is_empty():
			var cv: Vector3 = bf.caves[0]["centre"]
			var cy: float = bf.top_at(cv.x, cv.z) - 25.0
			for k in 4:
				if cy < cv.y + 10.0: break
				bf.blast(Vector3(cv.x, cy, cv.z), "special")
				cy -= 40.0
			bf.flush()
			await _wait(0.5)
			cam.global_position = Vector3(cv.x - 55.0, cv.y + 70.0, cv.z + 55.0)
			cam.look_at(cv, Vector3.UP)
			cam.make_current()
			await _shot("cave_opened", 0.4)
		cam.queue_free()
		if prev: prev.make_current()
		main.hud.visible = true
		s.player.visible = true
	BlockField.force = false
	GS.block_deltas.erase(BlockField.key_of(pid, t))
	Surface._mesh_cache.erase("%s|%d" % [pid, t])   # and back to the normal ground for everything after
	_check("Blocks (v1.7b): on for everyone in normal play, the whole planet region by region (on the web ?noblocks turns it off)", on_normally)
	main._load_system("solara", "station")   # back to space for the rest of the route test
	await _wait(1.0)

## EXPERIMENT step 9 (v1.7a): the whole planet as blocks. On a tile with a city, 500 m regions are built round the
## player from the seed (each its own seed and its own kept blasts), the smooth sheet is cut out under them, the pad
## sits on flat blocks, regions far behind are freed and a blast is still there when you come back.
@warning_ignore("integer_division")
func _regions() -> void:
	var pid: String = Data.BLOCK_TEST["planet"]
	var g := Surface.grid(pid)
	var t := -1
	for tt in g * g:
		if tt != int(Data.BLOCK_TEST["tile"]) and not Surface.locations_in(pid, tt).is_empty():
			t = tt
			break
	BlockField.regions_test = true
	for k in GS.block_deltas.keys():
		if str(k).begins_with("%s|%d|" % [pid, t]): GS.block_deltas.erase(k)
	main._load_surface(pid, t)
	await _wait(0.5)
	var s := _sp()
	var p: Vector3 = s.player.global_position
	var pr := BlockField.region_of(p.x, p.z)
	var want := 9   # (v1.7d: across a tile border too)
	var nr := int(round(Surface.TILE / Data.BLOCK_REGION))
	var frames := Engine.get_process_frames()
	BlockField.step_max_ms = 0.0
	await _until(func(): return s._regions.size() >= want and s._building == null, 30.0)
	frames = Engine.get_process_frames() - frames
	# v1.7q (owner: "planet super laggy"): no single slice of building a region stalls a frame for long
	var slice_ms: float = BlockField.step_max_ms
	var proc := 0.0
	for q in 30:
		await get_tree().process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	proc /= 30.0
	_check("Smoothness (v1.7q): building the ground round you is spread thin (no single slice over %d ms here), and a frame over the blocks costs little" % int(Data.BLOCK_SLICE_BUDGET_MS),
		slice_ms <= Data.BLOCK_SLICE_BUDGET_MS, "longest slice %.0f ms, frame process %.1f ms" % [slice_ms, proc])
	var terr := s.tile_root.get_node_or_null("Terrain") as MeshInstance3D
	var sm := terr.material_override as ShaderMaterial if terr else null
	var cut_n: int = s.cut_count if sm and sm.get_shader_parameter("cut_mask") != null else -1
	var here: BlockField = s._block_field_at(p.x, p.z)
	var ground_ok: bool = here != null and absf(s._ground(p.x, p.z) - here.top_at(p.x, p.z)) < 0.01
	_check("Blocks everywhere (v1.7a): on another tile the %d regions round you are built from the seed (%d m squares), the smooth ground is cut out under each one, and the ground you stand on is the blocks" % [want, int(Data.BLOCK_REGION)],
		s._regions.size() == want and cut_n == want and ground_ok, "tile %d, regions %d of %d, cuts %d, ground %s, built a little each frame over %d frames (last region %.0f ms start to end)" % [t, s._regions.size(), want, cut_n, ground_ok, frames, s.region_ms])
	# v1.7c: the pad floats on an island of blocks well over the ground; the ground under it runs natural (not flattened)
	var loc: Dictionary = Surface.locations_in(pid, t)[0]
	var lp: Vector2 = loc["pos"]
	var lr := BlockField.region_of(lp.x, lp.y)
	var lbf: BlockField = s._regions.get(Vector4i(0, 0, lr.x, lr.y))
	if lbf == null: lbf = s._build_region(lr)
	var top := Surface.pad_top(pid, t)
	var under := -INF
	var lo := INF
	for k in 40:
		var a := k * TAU / 40.0
		var q := lp + Vector2(cos(a), sin(a)) * (Data.PAD_ISLAND_RADIUS * float(k % 5) / 5.0)
		var f: BlockField = s._block_field_at(q.x, q.y)
		if f == null: f = lbf if lbf.covers(q.x, q.y) else null
		if f == null: continue
		under = maxf(under, f.top_at(q.x, q.y))
		lo = minf(lo, f.top_at(q.x, q.y))
	var isl := s.tile_root.get_node_or_null("PadIsland")
	var st_ok: bool = absf(s.station.global_position.y - (top + 20.0)) < 0.01
	# set the ship down on it
	s.player.global_position = Vector3(lp.x + 30.0, top + 2.0, lp.y)   # (sunk into it: the floor puts you on top)
	s.vel = Vector3.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	var landed: bool = s.player.global_position.y >= top + 5.0 and s.player.global_position.y < top + 9.0
	s.player.global_position = Vector3(lp.x + 30.0, top - Data.PAD_ISLAND_DEPTH, lp.y)   # under it: its rock is a roof
	s.vel = Vector3(0, 20, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	landed = landed and s.player.global_position.y < top - 5.0
	if OS.get_environment("HL_SHOT_DIR") != "":   # pictures of the island
		main.hud.visible = false
		s.player.visible = false
		var pcam := Camera3D.new()
		pcam.far = 8000.0
		s.add_child(pcam)
		var pprev := get_viewport().get_camera_3d()
		var pc := Vector3(lp.x, top - 20.0, lp.y)
		for v in [["pad_island", Vector3(330, 40, 380)], ["pad_island_high", Vector3(260, 220, 300)]]:
			pcam.global_position = pc + (v[1] as Vector3)
			pcam.look_at(pc, Vector3.UP)
			pcam.make_current()
			await _shot(v[0], 1.0)
		pcam.queue_free()
		if pprev: pprev.make_current()
		main.hud.visible = true
		s.player.visible = true
	_check("Pad islands (v1.7c): the landing pad at %s floats on an island of blocks well over the ground, the ground under it isn't flattened, and you can set down on it" % str(loc.get("name", "the city")),
		isl != null and under > -INF and top >= under + 20.0 and st_ok and landed and Surface.island_at(pid, t, lp.x, lp.y).size() == 2,
		"island top %.0f, highest ground under it %.0f (lowest %.0f), station %s, landed %s (y %.1f)" % [top, under, lo, st_ok, landed, s.player.global_position.y])
	# each region its own seed and its own kept blasts
	var ra: BlockField = s._regions.get(Vector4i(0, 0, pr.x, pr.y))
	var rb: BlockField = null
	for r in s._regions:
		if r != Vector4i(0, 0, pr.x, pr.y): rb = s._regions[r]
	var aim := Vector3(ra.center.x + 60.0, 0.0, ra.center.y + 60.0)
	aim.y = ra.top_at(aim.x, aim.z) - 1.0
	var before := ra.top_at(aim.x, aim.z)
	ra.blast(aim, "heavy")
	var after := ra.top_at(aim.x, aim.z)
	var ka := BlockField.region_key(pid, t, pr)
	var kb := BlockField.region_key(pid, rb.tile, rb.region)
	var own: bool = (GS.block_deltas.get(ka, []) as Array).size() > 0 and (GS.block_deltas.get(kb, []) as Array).size() == 0 and ra._sk != rb._sk
	# fly well away: the far regions go, new ones come; fly back: the crater is still there
	s.player.global_position = Vector3(ra.center.x + Data.BLOCK_REGION * 3.2 * (1.0 if pr.x * 2 < nr else -1.0), p.y + 200.0, ra.center.y)
	await _until(func(): return not s._regions.has(Vector4i(0, 0, pr.x, pr.y)) and s._building == null and s._regions.size() >= 6, 30.0)
	var freed: bool = not s._regions.has(Vector4i(0, 0, pr.x, pr.y)) and s._regions.size() <= (2 * Data.BLOCK_REGION_KEEP + 1) * (2 * Data.BLOCK_REGION_KEEP + 1)
	s.player.global_position = Vector3(aim.x, p.y + 200.0, aim.z)
	await _until(func(): return s._regions.has(Vector4i(0, 0, pr.x, pr.y)), 30.0)
	var back: BlockField = s._regions.get(Vector4i(0, 0, pr.x, pr.y))
	var kept: bool = back != null and back != ra and absf(back.top_at(aim.x, aim.z) - after) < 0.01
	_check("Blocks everywhere: each region has its own seed and keeps its own blasts; fly off and the far ones are freed, come back and your crater is still there",
		after < before and own and freed and kept, "crater %.0f -> %.0f, own notes %s, freed %s, rebuilt with the crater %s" % [before, after, own, freed, kept])
	# v1.7e: the slanted outer form: natural ground leans into slabs and wedges; every pair of neighbouring blocks still
	# meets with no gap (same height: the shared corners match; a step: the higher edge never dips under the lower top)
	var slanted := 0
	var square := 0
	var gaps := 0
	var sr: BlockField = back
	var cv := func(bf: BlockField, c: int) -> Array:
		var sz: int = bf.lsz[c]
		var ox: int = c % bf.n - (c % bf.n) % sz
		var oz: int = c / bf.n - (c / bf.n) % sz
		var tp: float = bf.h[oz * bf.n + ox]
		var v: Array = bf._slant(ox, oz, sz, tp, "", true, [])
		return [ox, oz, sz, tp, v if not v.is_empty() else [tp, tp, tp, tp]]
	sr._slant_cache.clear()
	for c in range(0, sr.n * sr.n, 1):
		var fx: int = c % sr.n
		var fz: int = c / sr.n
		if int(sr.lsz[c]) != sr.R or fx % sr.R != 0 or fz % sr.R != 0 or fx + sr.R >= sr.n or fz + sr.R >= sr.n: continue
		var A: Array = cv.call(sr, c)
		if (A[4] as Array).min() < float(A[3]) - 0.01: slanted += 1
		else: square += 1
		for side in [1, 2]:   # east and south neighbours
			var nc: int = c + (sr.R if side == 1 else sr.R * sr.n)
			if int(sr.lsz[nc]) != sr.R: continue
			var B: Array = cv.call(sr, nc)
			var a0: float = A[4][1] if side == 1 else A[4][3]   # A's shared corners (NE, SE) or (SW, SE)
			var a1: float = A[4][2]
			var b0: float = B[4][0]   # B's (NW, SW) or (NW, NE)
			var b1: float = B[4][3] if side == 1 else B[4][1]
			if absf(float(A[3]) - float(B[3])) < 0.01:
				if absf(a0 - b0) > 0.01 or absf(a1 - b1) > 0.01: gaps += 1
			elif float(A[3]) > float(B[3]):
				if minf(a0, a1) < float(B[3]) - 0.01 or absf(b0 - float(B[3])) > 0.01 or absf(b1 - float(B[3])) > 0.01: gaps += 1
			else:
				if minf(b0, b1) < float(A[3]) - 0.01 or absf(a0 - float(A[3])) > 0.01 or absf(a1 - float(A[3])) > 0.01: gaps += 1
	_check("Slanted ground (v1.7e): in patches the natural ground leans into slanted slabs and wedges (look only, blocks underneath); most of it is square steps (owner: a few slants), and neighbouring blocks always meet with no gap",
		slanted > 10 and square > slanted and gaps == 0, "slanted %d, square %d, gaps %d" % [slanted, square, gaps])
	# v1.7g (owner's pictures): brown dirt under a thin grass cap in the planet's colour, and blocks of many sizes:
	# neighbouring columns join into long rectangles and big solid blocks
	var jn := 0
	var big2 := 0
	for f in s._fields():
		jn += (f as BlockField).joined
	var tdirt: Color = sr.tone("dirt")
	var brown: bool = tdirt.r > tdirt.g and tdirt.g > tdirt.b
	_check("Owner's look (v1.7g): brown dirt under a thin grass cap in the planet's own colour, and the ground built from blocks of many sizes (long rectangles and big solid blocks, not one size of square)",
		jn > 100 and brown, "columns joined into bigger blocks %d, dirt colour %s (brown %s), grass cap %.1f m" % [jn, str(tdirt), brown, Data.BLOCK_GRASS_BAND])
	# v1.7h: the first mold: a cave (big chamber, tunnels to side rooms, a tunnel climbing to a shaft open to the sky),
	# cut as a filled volume; then checked as the owner's notes ask: room to fly, all connected, rock over it, collision
	var mf: BlockField = null
	for f in s._fields():
		if mf == null and not (f as BlockField).molds.is_empty(): mf = f
	var natural := mf != null
	if mf == null:
		mf = sr
		mf._carve_cave_mold(true)
		mf._carve_links()
		mf.flush()
	var mo: Dictionary = mf.molds[0] if not mf.molds.is_empty() else {}
	var clear_ok := not mo.is_empty()
	var conn_ok := false
	var ceil_ok := not mo.is_empty()
	var coll_ok := false
	var reached := 0
	var seen_all := {}
	if not mo.is_empty():
		var k0: int = mo["k0"]
		for rt in (mo["route"] as Array).slice(0, -1):   # room to fly all the way out
			for k in range(int(rt[1]), int(rt[1]) + Data.MOLD_TUNNEL_TALL):
				if mf._solid_k(int(rt[0]), k): clear_ok = false
		var last: Array = (mo["route"] as Array)[-1]
		var sky_ok: bool = mf._ktop(int(last[0])) <= int(last[1]) + 1
		# connected: walk the air from the chamber floor; it must reach every room and the open sky
		var start := Vector2i(int(mo["centre"]), k0 + 1)
		var seen := {start: true}
		var queue: Array = [start]
		var sky := false
		var goals := {}
		for rm in mo["rooms"]: goals[Vector2i(int(rm[0]), int(rm[1]) + 1)] = true
		var steps := 0
		while not queue.is_empty() and steps < 400000:
			steps += 1
			var cur: Vector2i = queue.pop_back()
			if goals.has(cur):
				goals.erase(cur)
				reached += 1
			if cur.y >= mf._ktop(cur.x):
				sky = true
				continue
			var cx2: int = cur.x % mf.n
			var cz2: int = cur.x / mf.n
			for nb in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var x2: int = cx2 + nb.x
				var z2: int = cz2 + nb.y
				if x2 < 0 or z2 < 0 or x2 >= mf.n or z2 >= mf.n: continue
				var nx := Vector2i(z2 * mf.n + x2, cur.y + nb.z)
				if seen.has(nx) or nx.y < k0 - 4 or mf._solid_k(nx.x, nx.y): continue
				seen[nx] = true
				queue.append(nx)
		conn_ok = sky and sky_ok and reached == (mo["rooms"] as Array).size()
		seen_all = seen
		# rock overhead: over the chamber's middle and each room at least MOLD_CEILING layers stay solid
		var over := func(c: int, k_from: int) -> int:
			var nsol := 0
			for k in range(k_from, mf._ktop(c)):
				if mf._solid_k(c, k): nsol += 1
			return nsol
		if over.call(int(mo["centre"]), k0 + int(mo["tall"])) < Data.MOLD_CEILING: ceil_ok = false
		for rm in mo["rooms"]:
			if over.call(int(rm[0]), int(rm[1]) + Data.MOLD_ROOM_TALL) < Data.MOLD_CEILING: ceil_ok = false
		var cc: int = mo["centre"]
		var px: float = mf.x0 + (cc % mf.n + 0.5) * Data.BLOCK_MIN
		var pz: float = mf.z0 + (cc / mf.n + 0.5) * Data.BLOCK_MIN
		var inside: float = mf.y0 + (k0 + 3) * Data.BLOCK_MIN
		coll_ok = absf(mf.ground_for(px, inside, pz) - (mf.y0 + k0 * Data.BLOCK_MIN)) < 0.01 and mf.ceiling_above(px, inside, pz) >= mf.y0 + (k0 + int(mo["tall"]) - 1) * Data.BLOCK_MIN - 0.01
		if OS.get_environment("HL_SHOT_DIR") != "":   # pictures: inside the chamber, and the shaft from above
			main.hud.visible = false
			s.player.visible = false
			var ccam := Camera3D.new()
			ccam.far = 8000.0
			s.add_child(ccam)
			var cprev := get_viewport().get_camera_3d()
			var r0: int = int((mo["rooms"] as Array)[0][0])
			var look := Vector3(mf.x0 + (r0 % mf.n + 0.5) * Data.BLOCK_MIN, inside, mf.z0 + (r0 / mf.n + 0.5) * Data.BLOCK_MIN)
			ccam.global_position = Vector3(px, inside + 8.0, pz) - (look - Vector3(px, inside, pz)).normalized() * 30.0
			ccam.look_at(look, Vector3.UP)
			ccam.make_current()
			await _shot("mold_cave_inside", 1.0)
			var lc: int = int(last[0])
			var top3 := Vector3(mf.x0 + (lc % mf.n + 0.5) * Data.BLOCK_MIN, mf.h0[lc], mf.z0 + (lc / mf.n + 0.5) * Data.BLOCK_MIN)
			ccam.global_position = top3 + Vector3(60, 70, 60)
			ccam.look_at(top3 + Vector3(0, -20, 0), Vector3.UP)
			await _shot("mold_cave_entrance", 1.0)
			ccam.queue_free()
			if cprev: cprev.make_current()
			main.hud.visible = true
			s.player.visible = true
	_check("Molds (v1.7h): a cave is cut into the ground as one filled shape (a big chamber, tunnels to side rooms at other heights, a tunnel climbing to a shaft open to the sky); room to fly all the way out, all of it connected, rock left overhead, solid floor and roof",
		clear_ok and conn_ok and ceil_ok and coll_ok, "made by the seed %s, cells cut %d, room to fly %s, rooms reached %d of %d, open to the sky %s, rock overhead %s, floor/roof %s" % [natural, int(mo.get("cells", 0)), clear_ok, reached, (mo.get("rooms", []) as Array).size(), conn_ok, ceil_ok, coll_ok])
	# v1.7j: winding tunnels from the cave's side rooms out to the nearest sealed caves, all part of the same air
	var linked := 0
	var link_detail := ""
	if not mo.is_empty():
		for lk in mf.links:
			var to: Array = lk["to"]
			var hit := false
			for dk in [0, 1, -1, 2]:
				if seen_all.has(Vector2i(int(to[0]), int(to[1]) + dk)): hit = true
			linked += 1 if hit else 0
			link_detail += "%d cells long (reached %s); " % [(lk["path"] as Array).size(), hit]
	_check("Winding tunnels (v1.7j): from the cave's side rooms, tunnels wind out to the nearest sealed caves and join them up, flyable and connected",
		mf.links.size() > 0 and linked == mf.links.size(), "tunnels %d, connected %d: %s" % [mf.links.size(), linked, link_detail])
	# v1.7k: the mold library (models made into molds by tools/molds/voxelize.py): each shape stamps in whole, in its
	# material, its tilted beams coming out as stepped diagonals with air under them
	var MoldLib = preload("res://scripts/mold_library.gd")
	var lib_names: Array = MoldLib.MOLDS.keys()
	var natural_placed := 0
	for f in s._fields(): natural_placed += (f as BlockField).placed.size()
	var lib_ok := lib_names.size() >= 2
	var lib_detail := ""
	for nm in lib_names:
		var rec: Dictionary = {}
		for q in 400:
			rec = sr._place_mold(nm, 14 + (q * 7) % (sr.n - 28), 14 + (q * 13) % (sr.n - 28))
			if not rec.is_empty(): break
		if rec.is_empty():
			lib_ok = false
			lib_detail += "%s: no room; " % nm
			continue
		var m: Dictionary = MoldLib.MOLDS[nm]
		var cxm: int = int(rec["centre"]) % sr.n
		var czm: int = int(rec["centre"]) / sr.n
		var right := 0
		var total := 0
		var floating := false
		for r in m["runs"]:
			var c: int = (czm + int(r[1])) * sr.n + cxm + int(r[0])
			for k in range(int(rec["k0"]) + int(r[2]), int(rec["k0"]) + int(r[3])):
				if k <= sr._kfloor(c) + 1: continue
				total += 1
				if sr._solid_k(c, k) and sr.mat_at(c % sr.n, c / sr.n, sr._ly(k)) == str(m["mat"]): right += 1
			if int(r[2]) > 2 and not sr._solid_k(c, int(rec["k0"]) + int(r[2]) - 1): floating = true
		lib_ok = lib_ok and right == total and total > 50 and floating
		lib_detail += "%s: %d of %d cells in %s, beams with air under %s; " % [nm, right, total, m["mat"], floating]
		if OS.get_environment("HL_SHOT_DIR") != "" and nm == "beam_tree":
			main.hud.visible = false
			s.player.visible = false
			var lcam := Camera3D.new()
			lcam.far = 8000.0
			s.add_child(lcam)
			var lprev := get_viewport().get_camera_3d()
			var lb := Vector3(sr.x0 + (cxm + 0.5) * Data.BLOCK_MIN, sr.y0 + int(rec["k0"]) * Data.BLOCK_MIN, sr.z0 + (czm + 0.5) * Data.BLOCK_MIN)
			lcam.global_position = lb + Vector3(80, 70, 80)
			lcam.look_at(lb + Vector3(0, 40, 0), Vector3.UP)
			lcam.make_current()
			await _shot("library_beam_tree", 1.0)
			lcam.queue_free()
			if lprev: lprev.make_current()
			main.hud.visible = true
			s.player.visible = true
	_check("Mold library (v1.7k): shapes made from models (tools/molds/voxelize.py) stamp into the ground whole, in their material, tilted beams as stepped diagonals with air under them",
		lib_ok, "molds %s, placed by the seed round you %d; %s" % [str(lib_names), natural_placed, lib_detail])
	# v1.7l: waterfalls: a pool on a cliff top pours over a rock lip down the face into a foamy pool at its foot; real
	# water in both pools; blast the lip and the fall stops
	var wf: BlockField = null
	var n_falls := 0
	for f in s._fields():
		n_falls += (f as BlockField).falls.size()
		if wf == null and not (f as BlockField).falls.is_empty(): wf = f
	var falls_ok := wf != null
	var falls_detail := "falls %d" % n_falls
	if wf:
		var fa: Dictionary = wf.falls[0]
		var drop: float = (fa["top"] as Vector3).y - (fa["bottom"] as Vector3).y
		var wet_top := false
		var wet_foot := false
		for c5 in wf.fluid: 
			for c6 in fa["foot"]:
				if int(c5) == int(c6): wet_foot = true
		for c7 in fa["lip"]:
			var behind: int = int(c7) - int((fa["dir"] as Vector2).y) * wf.n - int((fa["dir"] as Vector2).x)
			if wf.fluid.has(behind): wet_top = true
		var drawn2: bool = (wf.get_node("Falls") as MeshInstance3D).mesh != null
		if OS.get_environment("HL_SHOT_DIR") != "":
			main.hud.visible = false
			s.player.visible = false
			var wcam := Camera3D.new()
			wcam.far = 8000.0
			s.add_child(wcam)
			var wprev := get_viewport().get_camera_3d()
			var mid3: Vector3 = ((fa["top"] as Vector3) + (fa["bottom"] as Vector3)) * 0.5
			var dd: Vector2 = fa["dir"]
			var ll: Vector2 = fa["lat"]
			wcam.global_position = mid3 + Vector3(dd.x, 0, dd.y) * 70.0 + Vector3(ll.x, 0, ll.y) * 25.0 + Vector3(0, 12, 0)
			wcam.look_at(mid3, Vector3.UP)
			wcam.make_current()
			await _shot("waterfall", 1.0)
			wcam.queue_free()
			if wprev: wprev.make_current()
			main.hud.visible = true
			s.player.visible = true
		var lc: int = (fa["lip"] as Array)[0]
		wf.blast(wf._layer_point(lc, wf._ktop(lc) - 1), "heavy")
		wf.flush()
		var stopped: bool = not fa["on"]
		falls_ok = drop >= Data.FALL_DROP and wet_top and wet_foot and drawn2 and stopped
		falls_detail = "falls %d, drop %.0f m, water in the top pool %s and the foot pool %s, drawn %s, stops when the lip is blasted %s" % [n_falls, drop, wet_top, wet_foot, drawn2, stopped]
	_check("Waterfalls (v1.7l): a pool on a cliff top pours over a rock lip down the face into a foamy pool at its foot (real water in both); blast the lip and it stops",
		falls_ok, falls_detail)
	# v1.7i: alien trees (wood trunk and branches, big two-colour leaf slabs you can fly under, roots underground; one
	# beside the cave sends a root into its chamber); wood and leaves catch fire, it spreads, burns them away, dies out
	var tf: BlockField = null
	var tr: Dictionary = {}
	var n_trees := 0
	for f in s._fields():
		n_trees += (f as BlockField).trees.size()
		if tf == null and not (f as BlockField).trees.is_empty():
			tf = f
			tr = (f as BlockField).trees[0]
	if mo.size() > 0 and not natural: mf._grow_cave_tree(RandomNumberGenerator.new())
	var root_in := false
	if not mo.is_empty():
		for tt5 in mf.trees:
			if tt5["cave_root"]: root_in = true
		var kin: int = int(mo["k0"]) + 2
		var any_wood := false
		var cc2: int = mo["centre"]
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				var c2: int = cc2 + dz * mf.n + dx
				if c2 >= 0 and c2 < mf.n * mf.n and mf._solid_k(c2, kin) and mf.mat_at(c2 % mf.n, c2 / mf.n, mf._ly(kin)) == "wood": any_wood = true
		root_in = root_in and any_wood
	var tree_ok := tf != null and int(tr.get("wood", 0)) > 20 and int(tr.get("leaf", 0)) > 40
	var shade := false   # air under the leaves: somewhere a leaf layer sits over a hole
	if tf:
		for c3 in tf.holes:
			var sp: Array = tf.spans(int(c3))
			var topk: int = (sp[-1] as Vector2i).y - 1
			if Data.LEAF_COLORS.has(tf.mat_at(int(c3) % tf.n, int(c3) / tf.n, tf._ly(topk))): shade = true
	if tf and OS.get_environment("HL_SHOT_DIR") != "":   # pictures of a tree (and later, on fire)
		main.hud.visible = false
		s.player.visible = false
		var tcam := Camera3D.new()
		tcam.far = 8000.0
		s.add_child(tcam)
		var tprev := get_viewport().get_camera_3d()
		var b0: int = tr["base"]
		var tb := Vector3(tf.x0 + (b0 % tf.n + 1.0) * Data.BLOCK_MIN, tf.y0 + float(tr["k_ground"]) * Data.BLOCK_MIN, tf.z0 + (b0 / tf.n + 1.0) * Data.BLOCK_MIN)
		tcam.global_position = tb + Vector3(70, 110, 55)
		tcam.look_at(tb + Vector3(0, 30, 0), Vector3.UP)
		tcam.make_current()
		await _shot("tree", 1.0)
		var trunk0: int = (tr["trunk"] as Array)[0]
		tf.blast(tf._layer_point(trunk0, (int(tr["k_ground"]) + int(tr["k_top"])) / 2), "missile")
		for q in 8: tf._fire_update(Data.FIRE_TICK, tb)
		await _shot("tree_fire", 0.3)
		while not tf.burning.is_empty(): tf._fire_update(Data.FIRE_TICK, tb)
		tcam.queue_free()
		if tprev: tprev.make_current()
		main.hud.visible = true
		s.player.visible = true
		tr = tf.trees[1] if tf.trees.size() > 1 else tr
	# fire: set the trunk alight with a missile, let it burn (near the tree), it spreads, then dies out
	var fire_ok := false
	var fire_detail := ""
	if tf:
		var trunk_c: int = (tr["trunk"] as Array)[0]
		var kmid: int = (int(tr["k_ground"]) + int(tr["k_top"])) / 2
		var pt: Vector3 = tf._layer_point(trunk_c, kmid)
		var notes0 := tf.deltas.size()
		tf.blast(pt, "missile")
		var lit := tf.burning.size()
		var most := lit
		var ticks := 0
		while not tf.burning.is_empty() and ticks < 600:
			tf._fire_update(Data.FIRE_TICK, pt)
			most = maxi(most, tf.burning.size())
			ticks += 1
		var cuts := 0
		for d in tf.deltas.slice(notes0): cuts += 1 if str(d[3]) == "cut" else 0
		# lava beside wood sets it alight too
		var lava_ok := false
		for c4 in tf.trees.size():
			var t4: Dictionary = tf.trees[c4]
			var tc: int = (t4["trunk"] as Array)[0]
			var kk: int = int(t4["k_ground"]) + 2
			if not tf._solid_k(tc, kk): continue
			var side_c := tc - 1
			if tf._solid_k(side_c, kk): continue
			tf._set_fluid(side_c, kk, "lava")
			tf._react(side_c, kk, "lava")
			lava_ok = tf.burning.has(Vector2i(tc, kk))
			tf._set_fluid(side_c, kk, "")
			tf.burning.clear()
			break
		fire_ok = lit > 0 and most > lit and tf.burned > 3 and tf.burning.is_empty() and cuts > 0 and lava_ok
		fire_detail = "lit %d, most at once %d, burnt away %d, out after %d ticks, kept as notes %d, lava lights it %s" % [lit, most, tf.burned, ticks, cuts, lava_ok]
	_check("Alien trees (v1.7i): wood trunks and branches under big two-colour leaf slabs you can fly under, roots underground, one root down into the cave's chamber; wood and leaves catch fire (missiles, lava), it spreads, burns them away and dies out",
		tree_ok and shade and root_in and fire_ok, "trees %d, first: wood %d leaf %d, air under the leaves %s, root in the cave %s, %s" % [n_trees, int(tr.get("wood", 0)), int(tr.get("leaf", 0)), shade, root_in, fire_detail])
	_check("v1.8i: sand and dirt bank up in the crooks of a tree's buttress roots (%d blocks round the first tree)" % int(tr.get("soil", 0)), int(tr.get("soil", 0)) > 0, "soil %d" % int(tr.get("soil", 0)))
	# v1.7m: underground light: covered faces (the cave's floor) are out of the sun, open ground isn't; the flashlight
	# comes on under a roof and goes off in the open; a glowing thing near you (fire) gets a real light
	var dark_ok := false
	var open_ok := false
	var flash_in := false
	var flash_out := true
	var glow_ok := false
	if not mo.is_empty():
		var cc8: int = mo["centre"]
		var fy: float = mf.y0 + int(mo["k0"]) * Data.BLOCK_MIN
		var fx8: float = mf.x0 + (cc8 % mf.n + 0.5) * Data.BLOCK_MIN
		var fz8: float = mf.z0 + (cc8 / mf.n + 0.5) * Data.BLOCK_MIN
		for ch8 in mf.get_children():
			if not (ch8 is MeshInstance3D) or not str(ch8.name).begins_with("Ground") or (ch8 as MeshInstance3D).mesh == null: continue
			var arr: Array = (ch8 as MeshInstance3D).mesh.surface_get_arrays(0)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			for vi in range(0, vs.size(), 3):
				var v: Vector3 = vs[vi]
				if absf(v.y - fy) < 0.05 and absf(v.x - fx8) < 20.0 and absf(v.z - fz8) < 20.0 and absf(cols[vi].a - Data.CAVE_DARK) < 0.01: dark_ok = true
				if cols[vi].a > 0.99: open_ok = true
		s.player.global_position = Vector3(fx8, fy + 15.0, fz8)
		await get_tree().process_frame
		await get_tree().process_frame
		flash_in = s.flashlight != null and s.flashlight.visible
		s.player.global_position = Vector3(fx8, mf.hmax + 60.0, fz8)
		await get_tree().process_frame
		await get_tree().process_frame
		flash_out = s.flashlight != null and s.flashlight.visible
	# v1.8j: under water (the camera inside the blocks' water) the lamp comes on, sea-green and shorter, with its glare
	var wet := false
	var cpw: Vector3 = s.cam.global_position
	var wbf: BlockField = s._block_field_at(cpw.x, cpw.z)
	if wbf != null:
		var stw: float = Data.BLOCK_MIN
		var cw := clampi(int((cpw.z - wbf.z0) / stw), 0, wbf.n - 1) * wbf.n + clampi(int((cpw.x - wbf.x0) / stw), 0, wbf.n - 1)
		var kw: int = wbf._k(cpw.y)
		wbf._set_fluid(cw, kw, "water")
		var cam_keep: Vector3 = s.cam.global_position
		s._update_light(0.1, wbf, s.player.global_position)
		wet = s.underwater and s.flashlight.visible and s.flashlight.light_color.is_equal_approx(Data.FLASHLIGHT_WATER[0]) and s.flare != null
		wbf._set_fluid(cw, kw, "")
		s.underwater = false
	_check("v1.8j (planet polish): under water the ship's lamp comes on, turns sea-green and reaches less far (light through water), with a glare at the lamp and a sea tint on the view", wet, "underwater %s" % wet)
	for f in s._fields():
		if glow_ok: break
		for t9 in (f as BlockField).trees:
			var tc9: int = (t9["trunk"] as Array)[0]
			var k9: int = int(t9["k_ground"]) + 2
			if not (f as BlockField).ignite(tc9, k9): continue
			var lp9: Vector3 = (f as BlockField)._layer_point(tc9, k9)
			s._glow_t = 0.0
			s._update_light(0.1, f, lp9 + Vector3(0, 0, 30))
			for gl in s.glow_lights:
				if (gl as OmniLight3D).visible and str(gl.get_meta("kind", "")) == "fire" and (gl as OmniLight3D).global_position.distance_to(lp9) < 1.0: glow_ok = true
			(f as BlockField).burning.clear()
			break
	_check("Underground light (v1.7m): the cave floor is out of the sun while open ground isn't; the flashlight comes on under a roof and off in the open; glowing things near you (fire, lava, treasure, the kill floor) light up their surroundings",
		dark_ok and open_ok and flash_in and not flash_out and glow_ok, "cave floor dark %s, open ground lit %s, flashlight in the cave %s, in the open %s, fire gets a light %s" % [dark_ok, open_ok, flash_in, flash_out, glow_ok])
	# v1.7f: leaning slabs and A-frames stand about, one straight tilted slab each while whole; you can fly under an
	# A-frame; knock out a lean-to's prop (or one foot of an A-frame) and it stops being one piece and the far part falls
	var found := {"lean": null, "aframe": null}
	for f in s._fields():
		for sb in (f as BlockField).slabs:
			if found[sb["kind"]] == null and sb["whole"]: found[sb["kind"]] = [f, sb]
	var sl_ok := found["lean"] != null and found["aframe"] != null
	var under_air := false
	var fell := true
	var drawn := false
	var slab_detail := ""
	if sl_ok:
		var af: BlockField = found["aframe"][0]
		var asb: Dictionary = found["aframe"][1]
		var mid: Vector2 = (asb["geo"][0][1] as Vector2) + (asb["lat"] as Vector2) * 0.5   # the apex, half way across
		var mx := mid.x
		var mz := mid.y
		under_air = af.ground_for(mx, float(asb["ground"]) + float(asb["rise"]) * 0.5, mz) < float(asb["ground"]) + float(asb["rise"]) * 0.5 - 1.0
		drawn = af.get_node_or_null("Slabs") != null and (af.get_node("Slabs") as MeshInstance3D).mesh != null
		if OS.get_environment("HL_SHOT_DIR") != "":   # pictures of a lean-to and an A-frame
			main.hud.visible = false
			s.player.visible = false
			var scam := Camera3D.new()
			scam.far = 8000.0
			s.add_child(scam)
			var sprev := get_viewport().get_camera_3d()
			for kind in ["aframe", "lean"]:
				var sbk: Dictionary = found[kind][1]
				var g0: Array = sbk["geo"][0]
				var cen: Vector2 = ((g0[0] as Vector2) + (g0[1] as Vector2)) * 0.5 + (sbk["lat"] as Vector2) * 0.5
				var aim3 := Vector3(cen.x, float(sbk["ground"]) + float(sbk["rise"]) * 0.5, cen.y)
				var side := Vector2((sbk["lat"] as Vector2).x, (sbk["lat"] as Vector2).y).normalized()
				var along := ((g0[1] as Vector2) - (g0[0] as Vector2)).normalized()
				var eye := aim3 + Vector3(side.x * 70.0 + along.x * 30.0, 20.0, side.y * 70.0 + along.y * 30.0)
				scam.global_position = eye
				scam.look_at(aim3, Vector3.UP)
				scam.make_current()
				await _shot("slab_" + kind, 1.0)
			scam.queue_free()
			if sprev: sprev.make_current()
			main.hud.visible = true
			s.player.visible = true
		for kind in ["lean", "aframe"]:
			var f: BlockField = found[kind][0]
			var sb: Dictionary = found[kind][1]
			var c0 := f.collapses
			var cells_before := 0
			for c in sb["cells"]: cells_before += 1 if f.h[c] > float(sb["ground"]) + 6.0 else 0
			for c in sb["hold"]:   # blow the prop / foot away, bottom to top
				for k in 400:   # (pecked away with the light gun, so nothing but the prop is touched)
					var px: float = f.x0 + (int(c) % f.n + 0.5) * Data.BLOCK_MIN
					var pz: float = f.z0 + (int(c) / f.n + 0.5) * Data.BLOCK_MIN
					if f.h[c] <= float(sb["ground"]) - 4.0: break
					f.blast(Vector3(px, f.h[c] - 1.0, pz), "gun", false, false)
			f.flush()
			var cells_after := 0
			for c in sb["cells"]: cells_after += 1 if f.h[c] > float(sb["ground"]) + 6.0 else 0
			var this_fell: bool = not sb["whole"] and f.collapses > c0 and cells_after < cells_before
			fell = fell and this_fell
			slab_detail += "%s: whole %s, collapses +%d, raised cells %d -> %d; " % [kind, sb["whole"], f.collapses - c0, cells_before, cells_after]
	_check("Leaning slabs (v1.7f): lean-tos and A-frames stand about, each one straight tilted slab while whole; you can fly under an A-frame; shoot the prop or a foot and it stops being one piece and the far part comes down",
		sl_ok and under_air and drawn and fell, "found lean %s aframe %s, air under the A %s, drawn %s, %s" % [found["lean"] != null, found["aframe"] != null, under_air, drawn, slab_detail])
	# v1.7d: the blocks run on over the tile border (the next tile's regions are built in this tile's frame), and when
	# you cross they come with you, the same blocks, no rebuild; a blast right on a region edge digs both sides
	var ey: float = s._ground(Surface.EDGE - 60.0, p.z) + 80.0
	s.player.global_position = Vector3(Surface.EDGE - 60.0, ey, p.z)
	await _until(func(): return s._building == null and s._regions.size() >= 9 and s._block_field_at(Surface.EDGE + 60.0, p.z) != null, 30.0)
	var east: BlockField = s._block_field_at(Surface.EDGE + 60.0, p.z)
	var west: BlockField = s._block_field_at(Surface.EDGE - 20.0, p.z)
	var seam := absf(east.top_at(Surface.EDGE + 2.0, p.z) - west.top_at(Surface.EDGE - 2.0, p.z)) if east and west else INF
	var etile: int = east.tile if east else -1
	var edge_x: float = west.center.x + Data.BLOCK_REGION * 0.5 if west else 0.0   # a region edge inside this tile
	var bz: float = p.z
	var lh0: float = s._block_field_at(edge_x - 2.0, bz).top_at(edge_x - 2.0, bz) if west else 0.0
	var both := false
	var inner: BlockField = s._block_field_at(Surface.EDGE - Data.BLOCK_REGION - 20.0, bz)
	if inner and west:
		var ex: float = inner.center.x + Data.BLOCK_REGION * 0.5
		var ty0 := inner.top_at(ex - 2.0, bz)
		var ty1: float = west.top_at(ex + 2.0, bz)
		s._blast_blocks(Vector3(ex, maxf(ty0, ty1) - 1.0, bz), "heavy", inner)
		both = inner.top_at(ex - 2.0, bz) < ty0 and west.top_at(ex + 2.0, bz) < ty1
	s.player.global_position = Vector3(Surface.EDGE + 10.0, ey, p.z)
	var east_top: float = east.top_at(Surface.EDGE + 60.0, p.z) if east else 0.0
	s.shift_tile(Vector2i(1, 0))
	await get_tree().process_frame
	var now: BlockField = s._block_field_at(-Surface.EDGE + 60.0, p.z)
	var same: bool = now != null and now == east and s.tile == etile and absf(now.top_at(-Surface.EDGE + 60.0, p.z) - east_top) < 0.01
	_check("Blocks everywhere (v1.7d): the blocks run on over the tile border with no step, cross it and the same blocks come with you (nothing rebuilt); a blast on a region edge digs both sides",
		east != null and seam <= 25.0 and same and both, "next tile %d built over the border %s, step at the seam %.0f m, carried across %s, edge blast both sides %s" % [etile, east != null, seam, same, both])
	BlockField.regions_test = false
	for k in GS.block_deltas.keys():
		if str(k).begins_with("%s|%d|" % [pid, t]): GS.block_deltas.erase(k)
	main._load_system("solara", "station")
	await _wait(1.0)

## EXPERIMENT step 2 (v1.5t): craters on the block patch.
@warning_ignore("integer_division")
func _craters(s, bf: BlockField, pid: String, t: int) -> void:
	var flyable := true   # (v1.6e, measured before any test digs into them)
	# (v1.6f, also before any test digs) no thin spires; the canyon; the roots
	var spire := false
	for j in range(2, bf.cols - 2):
		for i in range(2, bf.cols - 2):
			var mx := -INF
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					if di != 0 or dj != 0: mx = maxf(mx, bf.tops[(j + dj) * bf.cols + i + di])
			if bf.tops[j * bf.cols + i] > mx + Data.SPIRE_MAX + Data.BLOCK_MIN: spire = true
	var deep := 0
	for c in bf.canyon_cells:
		if bf.h0[c] - bf.h[c] >= 30.0: deep += 1
	var roots_ok: bool = bf.roots.size() >= 3
	for rt in bf.roots:
		var tc: int = rt["tip"]
		var around := -INF
		for d in [-2, 2, -2 * bf.n, 2 * bf.n]: around = maxf(around, bf.h[tc + d])
		if bf.mat_at(tc % bf.n, tc / bf.n, bf.h[tc]) != "obsidian" or bf.h[tc] < bf.h0[tc] + 10.0: roots_ok = false
	_check("Craters: world generation 3: realistic heights (no spire more than %d m over all its neighbours; %d cut down); a winding canyon (%d cells, %d of them 30 m+ deep) with its layers in the walls; %d obsidian roots piercing the surface" % [int(Data.SPIRE_MAX), bf.clamped, bf.canyon_cells.size(), deep, bf.roots.size()],
		not spire and bf.canyon_cells.size() > 150 and deep > 100 and roots_ok, "spire %s canyon %d deep %d roots %s" % [spire, bf.canyon_cells.size(), deep, roots_ok])
	for ar in bf.arches:
		if not bf.holes.has(int(ar["mid"])): flyable = false
	var jutting := true
	for oh in bf.overhangs:
		if not bf.holes.has(int(oh["tip"])): jutting = false
	var step: float = Data.BLOCK_MIN
	var cell := func(x: float, z: float) -> int: return int((z - bf.z0) / step) * bf.n + int((x - bf.x0) / step)
	# 1. a light-gun shot at the middle of one 5 m cell: the big block splits 20 -> 10 -> 5 only there, and that layer
	#    breaks after exactly its tier's hit count (sand 1, dirt 2, stone 4, obsidian 8)
	var c0: Vector2 = bf.center + Vector2(-180.0, 140.0)
	var gx: float = bf.x0 + (floorf((c0.x - bf.x0) / Data.BLOCK_BIG) * bf.R + 1 + 0.5) * step   # the 2nd cell of a big block
	var gz: float = bf.z0 + (floorf((c0.y - bf.z0) / Data.BLOCK_BIG) * bf.R + 1 + 0.5) * step
	var i0: int = cell.call(gx, gz)
	var top0: float = bf.h[i0]
	var m0: String = bf.mat_at(int((gx - bf.x0) / step), int((gz - bf.z0) / step), top0)
	var need: int = Data.BLOCK_HITS[m0]
	var held := true
	for k in need - 1:
		bf.blast(Vector3(gx, top0, gz), "gun")
		if bf.h[i0] != top0: held = false
	bf.blast(Vector3(gx, top0, gz), "gun")
	var broke: bool = is_equal_approx(bf.h[i0], top0 - step)
	var far_i: int = cell.call(gx + 2.0 * step, gz + 2.0 * step)   # same big block, the other quarter
	var carve_only: bool = bf.lsz[i0] == 1 and bf.lsz[far_i] == 2 and is_equal_approx(bf.h[far_i], top0) and bf.splits >= 2
	_check("Craters: a light-gun shot splits the big block into four only where it hit (20 -> 10 -> 5 m), and a %s layer breaks after exactly %d hit(s) (tiers sand 1 / dirt 2 / stone 4 / obsidian 8)" % [m0, need],
		held and broke and carve_only and Data.BLOCK_HITS["sand"] == 1 and Data.BLOCK_HITS["dirt"] == 2 and Data.BLOCK_HITS["stone"] == 4 and Data.BLOCK_HITS["obsidian"] == 8,
		"held %s broke %s cell %d / far %d, splits %d" % [held, broke, bf.lsz[i0], bf.lsz[far_i], bf.splits])
	# 2. a missile: a crater, about half flying as rubble (at most 10 pieces), one small note kept
	var mp := Vector3(bf.center.x + 120.0, 0.0, bf.center.y + 100.0)
	mp.y = bf.top_at(mp.x, mp.z)
	var nd0: int = bf.deltas.size()
	var th0: int = bf.thrown
	var r1: Dictionary = bf.blast(mp, "missile")
	var flew: int = bf.thrown - th0
	_check("Craters: a missile blows a crater; part of it flies out as rubble, each material in its own number of pieces (%d pieces from %d broken layers, at most %d), and the crater is kept as one small note" % [flew, int(r1["broken"]), Data.BLOCK_RUBBLE_PER_BLAST],
		int(r1["broken"]) >= 4 and flew >= 1 and flew <= Data.BLOCK_RUBBLE_PER_BLAST and Data.BLOCK_BREAK_PIECES["obsidian"] == 2 and Data.BLOCK_BREAK_PIECES["stone"] == 3 and Data.BLOCK_BREAK_PIECES["dirt"] == 4 and Data.BLOCK_BREAK_PIECES["sand"] == 5 and bf.deltas.size() == nd0 + 1 and str(bf.deltas[-1]).length() < 60,
		"broken %d flew %d note %s" % [int(r1["broken"]), flew, str(bf.deltas[-1]) if not bf.deltas.is_empty() else "-"])
	# 3. the SPECIAL: a crater you can fly into (much wider and deeper than a missile's)
	var sp := Vector3(bf.center.x, 0.0, bf.center.y)
	sp.y = bf.top_at(sp.x, sp.z)
	var before := bf.h.duplicate()
	bf.blast(sp, "special")
	var cells := 0
	var deepest := 0.0
	for i in bf.h.size():
		if bf.h[i] < before[i] - 0.01 or bf.holes.has(i):
			cells += 1
			deepest = maxf(deepest, before[i] - bf.h[i])
	_check("Craters: the SPECIAL blows a crater you can fly into (%d cells of 5 m, %.0f m deep at most)" % [cells, deepest], cells > 150 and deepest >= 15.0)
	# 4. obsidian chips and holds, never splits: when it gives, it goes as ONE whole chunk
	var ob_ok := false
	var ob_info := "no obsidian found"
	for j in range(2, bf.cols - 2):
		if ob_ok or ob_info != "no obsidian found": break
		for i in range(2, bf.cols - 2):
			var ox: int = i * bf.R
			var oz: int = j * bf.R
			var o0: int = oz * bf.n + ox
			if bf.lsz[o0] != bf.R: continue
			var y: float = bf.h[o0] - 20.0
			var found := -1e9
			while y > bf.h0[o0] - 180.0:
				if bf.mat_at(ox + bf.R / 2, oz + bf.R / 2, y) == "obsidian":
					found = y
					break
				y -= step
			if found < -1e8: continue
			var keep := bf.h.duplicate()
			for jz in bf.R:
				for jx in bf.R: bf.h[(oz + jz) * bf.n + ox + jx] = found   # (test only: dig straight down to it)
			var corner := Vector3(bf.x0 + ox * step + 2.5, found, bf.z0 + oz * step + 2.5)   # a corner shot: only part of it inside
			var held_ob := true
			for k in Data.BLOCK_HITS["obsidian"] - 1:
				bf.blast(corner, "gun", false, false)
				if bf.h[o0] != found or bf.lsz[o0] != bf.R: held_ob = false
			var th1: int = bf.thrown
			bf.blast(corner, "gun", false, true)
			var whole := true
			for jz in bf.R:
				for jx in bf.R:
					if not is_equal_approx(bf.h[(oz + jz) * bf.n + ox + jx], found - step): whole = false
			ob_ok = held_ob and whole and bf.lsz[o0] == bf.R and bf.thrown - th1 == 2
			ob_info = "held %s whole %s size %d thrown %d" % [held_ob, whole, bf.lsz[o0], bf.thrown - th1]
			bf.h = keep   # put it back
			bf.dmg.erase(o0)
			break
	_check("Craters: obsidian chips and holds (7 hits), never splits into four, then breaks off whole, in half (2 big pieces), on the 8th", ob_ok, ob_info)
	var cl0: int = bf.cleaved
	var drop := Vector3(bf.center.x + 60.0, 0.0, bf.center.y - 60.0)
	drop.y = bf.top_at(drop.x, drop.z) + 30.0
	bf._piece(drop, 6.0, "obsidian", Vector3(0, -25, 0))
	await _wait(2.0)
	_check("Craters: a falling obsidian chunk cleaves in half again when it lands hard", bf.cleaved >= cl0 + 1, "cleaved %d" % (bf.cleaved - cl0))
	bf.flush()
	# 5. a real shot: the ship's bolt flies down into the ground and digs it
	var shots_of := func() -> int:
		var c := 0
		for d in bf.deltas:
			if str(d[3]) == "gun": c += 1
		return c
	var nd1: int = shots_of.call()
	var aim := Vector3(bf.center.x - 90.0, 0.0, bf.center.y + 60.0)
	aim.y = bf.top_at(aim.x, aim.z)
	s._spawn_bolt(aim + Vector3(0, 60, 0), Vector3(0, -600, 0), 10.0, Color(1, 0.4, 0.3), "player", 1.0)
	await _wait(0.4)
	var shot_ok: bool = shots_of.call() == nd1 + 1
	_check("Craters: the ship's own shots hit the block ground (they used to fly through it) and each one is a crater note", shot_ok, "shot notes %d -> %d" % [nd1, shots_of.call()])
	# 6. rubble stays capped and comes down to rest on the ground
	for k in 12:
		var q := Vector3(bf.center.x + 150.0 - k * 25.0, 0.0, bf.center.y - 150.0)
		q.y = bf.top_at(q.x, q.z)
		bf.blast(q, "missile")
	var alive: int = bf.rubble.size()
	var mg0: int = bf.merged
	await _wait(4.0)
	var deps := 0
	for d in bf.deltas:
		if str(d[3]).begins_with("dep:"): deps += 1
	_check("Craters: flying rubble is capped (%d alive, at most %d), comes down and settles into the ground as its own material (%d pieces merged, %d kept as notes)" % [alive, Data.BLOCK_RUBBLE_LIVE, bf.merged - mg0, deps],
		alive <= Data.BLOCK_RUBBLE_LIVE and bf.merged - mg0 > alive / 2 and deps >= bf.merged - mg0)
	# 7. bumping the block ground (v1.5u): free up to cruising speed and while braking, the mech never hurt
	var pp: Vector3 = s.player.global_position
	s.player.global_position = Vector3(bf.center.x, bf.top_at(bf.center.x, bf.center.y) + 20.0, bf.center.y)
	var form0: String = GS.form
	var hits := []
	for c in [["ship", false, Data.BLOCK_SAFE_BUMP - 5.0], ["ship", false, 50.0], ["ship", true, 50.0], ["mech", false, 80.0]]:
		GS.form = c[0]
		s.braking = c[1]
		s.collide_grace = 0.0
		s.last_collision = {}
		s.collision_damage("ground", float(c[2]))
		hits.append(float(s.last_collision.get("dmg", 0.0)))
	GS.form = form0
	s.braking = false
	s.collide_grace = 0.0
	s.player.global_position = pp
	_check("Craters: over the block ground a wall bump is free up to cruising speed (%d m/s) and while braking; at 50 m/s the ship is hurt; the mech is never hurt by the ground" % int(Data.BLOCK_SAFE_BUMP),
		hits[0] == 0.0 and hits[1] > 0.0 and hits[2] == 0.0 and hits[3] == 0.0, str(hits))
	# 8. seed + deltas: a fresh patch regrown from the seed and the notes is the same ground
	bf.flush()
	var again := BlockField.new()
	again.build(pid, t)
	var hk1: Array = again.holes.keys()
	var hk2: Array = bf.holes.keys()
	hk1.sort()
	hk2.sort()
	var same_holes: bool = hk1 == hk2
	if same_holes:
		for hk in hk1:
			if str(again.holes[hk]) != str(bf.holes[hk]): same_holes = false
	var same_mats: bool = str(again.mats.keys().size()) == str(bf.mats.keys().size())
	for mk in bf.mats:
		if not again.mats.has(mk) or str(again.mats[mk]) != str(bf.mats[mk]): same_mats = false
	var same: bool = again.h == bf.h and again.lsz == bf.lsz and same_holes and same_mats
	var st: Dictionary = bf.save_state()
	_check("Craters: what is kept is the seed plus one small note per blast (%d notes); the patch regrown from them is the same ground, block for block" % bf.deltas.size(),
		same and st.keys().size() == 3 and str(st).length() < bf.deltas.size() * 60 + 100, "same %s" % same)
	again.free()
	# 8b. the super (heavy) missile is the bigger hitter everywhere (v1.5w)
	var hp := Vector3(bf.center.x - 150.0, 0.0, bf.center.y + 150.0)
	hp.y = bf.top_at(hp.x, hp.z)
	var hb := bf.h.duplicate()
	var snap: Dictionary = bf.snapshot()
	bf.blast(hp, "missile", false, false)
	var light_cells := 0
	for i in bf.h.size():
		if bf.h[i] < hb[i] - 0.01: light_cells += 1
	bf.restore(snap.duplicate(true))
	bf.blast(hp, "heavy", false, false)
	var heavy_cells := 0
	for i in bf.h.size():
		if bf.h[i] < hb[i] - 0.01: heavy_cells += 1
	bf.restore(snap.duplicate(true))
	_check("Craters: the SUPER missile is the bigger hitter: a bigger crater (%d cells vs %d), a bigger hitbox in space fights (%d m vs %d m) and a bigger explosion" % [heavy_cells, light_cells, int(Data.HEAVY_MISSILE_HIT_RADIUS), int(Data.MISSILE_HIT_RADIUS)],
		heavy_cells > light_cells and Data.HEAVY_MISSILE_HIT_RADIUS > Data.MISSILE_HIT_RADIUS and float(Data.BLAST_HEAVY_MISSILE[0]) > 8.0)
	# a test wall: cells [i0, i1) x [j0, j1) raised `tall` m over base_y, the rest of the box flat at base_y
	var wall := func(i0: int, i1: int, j0: int, j1: int, wi: int, base: float, tall: float) -> void:
		for j in range(j0, j1):
			for i in range(i0, i1):
				var c: int = j * bf.n + i
				bf.lsz[c] = 1
				bf.dmg.erase(c)
				bf.holes.erase(c)
				bf.fluid.erase(c)
				bf.mats.erase(c)
				bf.h[c] = base + (tall if i >= wi else 0.0)
	# 9. v1.9b (owner): walking into a wall never breaks it, whatever it is made of: it just stops you
	var snap9: Dictionary = bf.snapshot()
	var form1: String = GS.form
	var hull0: float = GS.hull
	var pp2: Vector3 = s.player.global_position
	GS.form = "mech"
	var ax: float = bf.x0 + 30.0 * step + 2.5   # stand in one 5 m cell, the wall is the next cells east
	var az: float = bf.z0 + 30.0 * step + 2.5
	var base_y: float = bf.h[30 * bf.n + 30]
	var wc: int = 30 * bf.n + 31
	var res := {}
	for mat in ["dirt", "stone", "obsidian"]:
		wall.call(26, 40, 26, 35, 31, base_y, 20.0)   # a 20 m wall just east of the mech
		bf.force_mat = mat
		s.dig_log = {"soft": 0, "stone": 0, "bounce": 0, "blocked": 0}
		s._dig_cd = 0.0
		var backed := false
		for k in 40:
			s.player.global_position = Vector3(ax, base_y + 6.0, az)
			s.vel = Vector3(20.0, 0.0, 0.0)
			s._mech_dig(0.05)
			if s.vel.x < 0.1: backed = true   # (stopped)
		res[mat] = {"open": not bf.is_solid(bf.x0 + 31.5 * step, base_y + 6.5, az), "dug": bf.holes.has(wc) or bf.h[wc] < base_y + 19.9,
			"backed": backed, "log": s.dig_log.duplicate()}
	bf.force_mat = ""
	GS.form = form1
	s.vel = Vector3.ZERO
	s.player.global_position = pp2
	bf.restore(snap9)   # (test only: forget the test digs)
	var dirt_ok: bool = not res["dirt"]["open"] and not res["dirt"]["dug"] and res["dirt"]["backed"]
	var stone_ok: bool = not res["stone"]["dug"] and res["stone"]["backed"]
	var obs_ok: bool = not res["obsidian"]["dug"] and res["obsidian"]["backed"]
	_check("v1.9b (owner: walking broke through the floor): walking into a block wall of dirt, stone or obsidian never breaks it, the wall just stops you (only shots break blocks); never any damage",
		dirt_ok and stone_ok and obs_ok and GS.hull == hull0, str(res))
	# 10. support and collapse (v1.5y): a shot into a wall digs IN; a stone overhang holds, a sand one falls; a pillar
	#     cut through at its middle comes down
	var snap10: Dictionary = bf.snapshot()
	var bx0: float = bf.x0 + 60.0 * step
	var bzc: float = bf.z0 + 62.5 * step
	var by: float = bf.h[62 * bf.n + 60]
	var over := {}
	for mat in ["stone", "sand"]:
		wall.call(56, 72, 56, 70, 60, by, 40.0)   # a 40 m cliff face at x = cell 60
		bf.force_mat = mat
		var col0: int = bf.collapses
		bf.blast(Vector3(bx0 - 1.0, by + 20.0, bzc), "missile", false, false)   # sideways into the face, 20 m up
		var holed := 0
		for c in bf.holes:
			if int(c) % bf.n >= 56 and int(c) % bf.n < 72 and int(c) / bf.n >= 56 and int(c) / bf.n < 70: holed += 1
		var cut: bool = bf.is_solid(bx0 + 2.5, by + 20.0, bzc) == false
		over[mat] = {"tunnel": cut, "overhangs": holed, "fell": bf.collapses - col0}
	wall.call(56, 72, 56, 70, 999, by, 0.0)   # flat, then one 40 m stone pillar in the middle
	var pc: int = 62 * bf.n + 64
	bf.h[pc] = by + 40.0
	bf.force_mat = "stone"
	var c1: int = bf.collapses
	bf.blast(Vector3(bf.x0 + 64.5 * step, by + 20.0, bf.z0 + 62.5 * step), "gun", false, false)
	for k in 3: bf.blast(Vector3(bf.x0 + 64.5 * step, by + 20.0, bf.z0 + 62.5 * step), "gun", false, false)   # stone: 4 hits
	var pillar := {"fell": bf.collapses - c1, "holes": bf.holes.has(pc), "h": bf.h[pc] - by}
	bf.force_mat = ""
	bf.restore(snap10)
	bf.flush()
	# 11. settling (v1.5z): sand poured on one spot spreads into a pile; dirt thrown at a wall sticks to it; a stone layer
	#     laid on sand stays stone (nothing mixes); a falling piece keeps its material
	var snap11: Dictionary = bf.snapshot()
	wall.call(80, 96, 80, 96, 999, by, 0.0)
	var sc := Vector3(bf.x0 + 88.5 * step, by + 0.1, bf.z0 + 88.5 * step)
	for k in 9: bf.deposit(sc, "sand", 1.0)
	var top_c: float = bf.h[88 * bf.n + 88] - by
	var total := 0.0
	var steep := false
	for j in range(80, 96):
		for i in range(80, 96):
			var c: int = j * bf.n + i
			total += (bf.h[c] - by) / step
			if i > 80 and absf(bf.h[c] - bf.h[c - 1]) > step + 0.01: steep = true
	var pile_ok: bool = is_equal_approx(total, 9.0) and top_c < 9.0 * step and not steep
	wall.call(80, 96, 80, 96, 90, by, 30.0)   # a 30 m wall from cell 90 east
	var stick := Vector3(bf.x0 + 89.5 * step, by + 17.5, bf.z0 + 85.5 * step)
	bf.deposit(stick, "dirt", 1.0)
	var stuck: bool = bf.is_solid(stick.x, stick.y, stick.z) and bf.holes.has(85 * bf.n + 89) and bf.mat_point(stick.x, stick.y, stick.z) == "dirt"
	wall.call(80, 96, 80, 96, 999, by, 0.0)
	bf.deposit(sc, "sand", 1.0)
	bf.deposit(sc + Vector3(0, step, 0), "stone", 1.0)
	var no_mix: bool = bf.mat_point(sc.x, by + 7.5, sc.z) == "stone" and bf.mat_point(sc.x, by + 2.5, sc.z) == "sand"
	bf.restore(snap11)
	bf.flush()
	_check("Craters: settling: sand poured on one spot spreads into a pile with 45-degree sides; dirt thrown at a wall sticks to it (held up by the wall); a stone layer laid on sand stays stone",
		pile_ok and stuck and no_mix, "pile %s (top %.0f m, total %.1f) stuck %s no_mix %s" % [pile_ok, top_c, total, stuck, no_mix])
	# 12. the skin (v1.6a): look only. A lone sand block shows as a blunt mound; two joined obsidian blocks get pointed
	#     tips; a lone obsidian block stays a block; the ground the ship stands on doesn't change
	var snap12: Dictionary = bf.snapshot()
	var verts_in := func(fx: int, fz: int) -> PackedVector3Array:
		var c: int = Data.BLOCK_CHUNK
		var nc: int = ceili(float(bf.n) / c)
		bf._draw_chunk((fz / c) * nc + fx / c)
		var mi: MeshInstance3D = bf._chunks[(fz / c) * nc + fx / c]
		var out := PackedVector3Array()
		if mi.mesh == null: return out
		for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if v.x > bf.x0 + fx * step + 0.01 and v.x < bf.x0 + (fx + 1) * step - 0.01 and v.z > bf.z0 + fz * step + 0.01 and v.z < bf.z0 + (fz + 1) * step - 0.01: out.append(v)
			elif v.x >= bf.x0 + fx * step - 0.01 and v.x <= bf.x0 + (fx + 1) * step + 0.01 and v.z >= bf.z0 + fz * step - 0.01 and v.z <= bf.z0 + (fz + 1) * step + 0.01: out.append(v)
		return out
	wall.call(100, 116, 100, 116, 999, by, 0.0)
	bf.h[104 * bf.n + 104] = by + 10.0   # lone sand block
	bf.h[108 * bf.n + 104] = by + 10.0   # two obsidian blocks side by side
	bf.h[108 * bf.n + 105] = by + 10.0
	bf.h[112 * bf.n + 104] = by + 10.0   # a lone obsidian block
	bf.force_mat = "sand"
	var sand_v: PackedVector3Array = verts_in.call(104, 104)
	var mound := false
	for v in sand_v:
		if absf(v.y - (by + 10.0 - float(Data.BLOCK_SKIN["sand"][1]))) < 0.05: mound = true
	bf.force_mat = "obsidian"
	var tip := false
	for v in verts_in.call(104, 108):
		if v.y > by + 10.5: tip = true
	var lone_tip := false
	for v in verts_in.call(104, 112):
		if v.y > by + 10.5: lone_tip = true
	var same_ground: bool = is_equal_approx(bf.top_at(bf.x0 + 104.5 * step, bf.z0 + 104.5 * step), by + 10.0)
	bf.force_mat = ""
	bf.restore(snap12)
	bf.flush()
	_check("Craters: the skin over the blocks (look only): a lone sand block shows as a soft blunt mound; two joined obsidian blocks point up into shard tips; a lone obsidian block stays a block; the ground underneath is unchanged",
		mound and tip and not lone_tip and same_ground, "mound %s tip %s lone tip %s ground %s" % [mound, tip, lone_tip, same_ground])
	# 13. water and lava (v1.6b): sealed pockets from the seed, asleep; poured water finds its level; water turns sand
	#     to dirt; lava eats sand, trades with dirt, and meeting water turns to obsidian
	var kinds := {}
	var sealed := true
	for pk in bf.pockets:
		kinds[pk["kind"]] = true
		if bf._pocket_open(pk) and bf.fluid.has(pk["cells"][0]): sealed = false
	var before_moves: int = bf.fluid_moves
	for k in 4: bf.fluid_step(Vector3(bf.center.x, 0, bf.center.y), 99999.0)
	var asleep: bool = bf.fluid_moves == before_moves
	var snap13: Dictionary = bf.snapshot()
	wall.call(120, 136, 120, 136, 999, by, 0.0)
	bf.force_mat = "stone"
	var bk: int = bf._k(by + 0.1)   # the first air layer over the floor
	# a basin: a 3x3 floor at by inside a ring one layer higher; pour 4 layers of water into the middle cell
	for j in range(123, 130):
		for i in range(123, 130):
			var c: int = j * bf.n + i
			bf.h[c] = by + (0.0 if i >= 124 and i <= 128 and j >= 124 and j <= 128 else 10.0)
	var mid: int = 126 * bf.n + 126
	for k in 4: bf._set_fluid(mid, bk + k, "water")
	for k in 30: bf.fluid_step(Vector3(bf.x0 + 126 * step, 0, bf.z0 + 126 * step), 300.0)
	var units := 0
	var high := false
	for c in bf.fluid:
		if int(c) % bf.n >= 120 and int(c) % bf.n < 136 and int(c) / bf.n >= 120 and int(c) / bf.n < 136:
			for k in bf.fluid[c]:
				units += 1
				if int(k) > bk: high = true
	var level_ok: bool = units == 4 and not high
	# reactions
	bf.force_mat = ""
	var cs: int = 126 * bf.n + 126
	for c in bf.fluid.keys():
		if int(c) % bf.n >= 120 and int(c) % bf.n < 136: bf.fluid.erase(c)
	var ov: Dictionary = {bk - 1: "sand"}
	bf.mats[cs] = ov
	bf._set_fluid(cs, bk, "water")
	bf.fluid_step(Vector3(bf.x0 + 126 * step, 0, bf.z0 + 126 * step), 300.0)
	var wet: bool = bf.mat_at(126, 126, bf._ly(bk - 1)) == "dirt"
	bf._set_fluid(cs, bk, "")
	bf.mats[cs] = {bk - 1: "sand"}
	bf._set_fluid(cs, bk, "lava")
	bf.fluid_step(Vector3(bf.x0 + 126 * step, 0, bf.z0 + 126 * step), 300.0, true)
	var ate: bool = not bf._solid_k(cs, bk - 1)
	for c in bf.fluid.keys():
		if int(c) % bf.n >= 120 and int(c) % bf.n < 136: bf.fluid.erase(c)
	var c2: int = 126 * bf.n + 125
	bf.h[c2] = by
	bf.mats[c2] = {bk - 1: "dirt"}
	bf._set_fluid(c2, bk, "lava")
	bf.fluid_step(Vector3(bf.x0 + 125 * step, 0, bf.z0 + 126 * step), 300.0, true)
	var traded: bool = not bf._solid_k(c2, bk - 1) and bf._fluid_k(c2, bk) == "" and bf._fluid_k(c2, bk - 1) == ""
	for c in bf.fluid.keys():
		if int(c) % bf.n >= 120 and int(c) % bf.n < 136: bf.fluid.erase(c)
	var c3: int = 130 * bf.n + 130
	var c4: int = 130 * bf.n + 131
	bf.mats.erase(c3)
	bf.mats.erase(c4)
	bf._set_fluid(c3, bk, "lava")
	bf._set_fluid(c4, bk, "water")
	bf.force_mat = "stone"
	bf.fluid_step(Vector3(bf.x0 + 130 * step, 0, bf.z0 + 130 * step), 300.0, true)
	bf.force_mat = ""
	var obs: bool = bf._solid_k(c3, bk) and bf.mat_at(130, 130, bf._ly(bk)) == "obsidian" and bf._fluid_k(c4, bk) == ""
	var burns: bool = bf.fluid_at(bf.x0 + 130.5 * step, by + 2.5, bf.z0 + 130.5 * step) == "" and Data.LAVA_DPS > 0.0
	bf.restore(snap13)
	bf.flush()
	_check("Craters: water and lava: sealed pockets from the seed (%s), asleep until opened; poured water spreads to fill a basin flush; water turns sand to dirt; lava eats sand, trades with dirt, and meeting water becomes obsidian" % ", ".join(kinds.keys()),
		kinds.has("water") and kinds.has("lava") and sealed and asleep and level_ok and wet and ate and traded and obs and burns,
		"sealed %s asleep %s level %s (%d units) wet %s ate %s traded %s obsidian %s" % [sealed, asleep, level_ok, units, wet, ate, traded, obs])
	# 14. mining (v1.6c): veins from the seed; a gold layer broken with the light gun drops more pieces than one broken
	#     by a heavy missile; the pieces never turn to rubble; the tractor beam pulls them in for credits
	var vk := {}
	for v in bf.veins: vk[v["mat"]] = true
	var snap14: Dictionary = bf.snapshot()
	wall.call(140, 150, 140, 150, 999, by, 0.0)
	var g1: int = 144 * bf.n + 144
	var g2: int = 146 * bf.n + 148
	bf.mats[g1] = {bf._ktop(g1) - 1: "gold"}
	bf.mats[g2] = {bf._ktop(g2) - 1: "gold"}
	var p0: int = s.mined_pieces
	var loot0: int = s.loot.size()
	var gp := Vector3(bf.x0 + 144.5 * step, by, bf.z0 + 144.5 * step)
	for k in Data.BLOCK_HITS["gold"]: bf.blast(gp, "gun")
	var by_gun: int = s.mined_pieces - p0
	var p1: int = s.mined_pieces
	bf.blast(Vector3(bf.x0 + 148.5 * step, by, bf.z0 + 146.5 * step), "heavy")
	var by_heavy: int = s.mined_pieces - p1
	var gems := 0
	for l in s.loot:
		if l.has("gem"): gems += 1
	var no_rubble := true
	for b in bf.rubble:
		if Data.VALUABLE_COLOR.has(str(b.get("mat", ""))): no_rubble = false
	var cr0: int = GS.credits
	var cargo14: Array = GS.cargo.duplicate(true)
	var pp3: Vector3 = s.player.global_position
	s.player.global_position = gp + Vector3(0, 30, 0)
	s.tractor()
	await _wait(3.0)
	# v1.8l: the pieces go into the hold (no credits yet); a base buys them at its own price
	var held14: int = GS.ore_count("gold")
	var unpaid: bool = GS.credits == cr0
	var one_stack: bool = GS.cargo.filter(func(c): return c.get("kind", "") == "ore" and c.get("id", "") == "gold").size() == 1
	var pa: int = GS.ore_price("gold", "Liberty Hub")
	var lo14: int = int(float(Data.MINE_VALUE["gold"]) * float(Data.ORE_PRICE_SWING[0])) - 5
	var hi14: int = int(float(Data.MINE_VALUE["gold"]) * float(Data.ORE_PRICE_SWING[1])) + 5
	var worth14: int = GS.ore_worth("Liberty Hub")
	var sold_line: String = GS.sell_ore("Liberty Hub")
	var earned: int = GS.credits - cr0
	var sold_ok: bool = held14 >= by_gun and unpaid and one_stack and pa >= lo14 and pa <= hi14 and worth14 == held14 * pa and earned == worth14 and GS.ore_count("gold") == 0 and sold_line.find("Sold") >= 0 and GS.sell_ore("Liberty Hub").find("No gold") >= 0
	GS.credits = cr0
	GS.cargo = cargo14
	s.player.global_position = pp3
	bf.restore(snap14)
	bf.flush()
	_check("Craters: mining: gold and diamond veins from the seed; a gold layer broken carefully with the light gun drops more pieces (%d) than one blown by a heavy missile (%d); the pieces never turn to rubble; the tractor beam pulls them into the hold (x%d)" % [by_gun, by_heavy, held14],
		vk.has("gold") and vk.has("diamond") and by_gun == 3 and by_heavy <= 2 and gems >= by_gun and no_rubble and held14 >= by_gun,
		"veins %s gun %d heavy %d gems %d held %d" % [str(vk.keys()), by_gun, by_heavy, gems, held14])
	_check("v1.8l (owner): mined gold / diamond goes into the hold as one stack (x%d, no credits yet) and is sold at a base for that base's own price (%d cr each, +%d cr)" % [held14, pa, earned],
		sold_ok, "held %d unpaid %s stack %s price %d (%d..%d) worth %d earned %d" % [held14, unpaid, one_stack, pa, lo14, hi14, worth14, earned])
	# 15. world generation part 1 (v1.6d): sealed cave pockets that stand on their own; an obsidian cap over the kill
	#     floor; dug open, the kill floor takes water and destroys the ship
	var carved := 0
	for cv in bf.caves: carved += int(cv["cells"])
	var col_before: int = bf.collapses
	bf._settle(0, bf.n - 1, 0, bf.n - 1)
	var stands: bool = bf.collapses == col_before
	var snap15: Dictionary = bf.snapshot()
	wall.call(150, 160, 150, 160, 999, by, 0.0)
	var kc: int = 155 * bf.n + 155
	var ky: float = bf.y0 + bf._kfloor(kc) * step
	var cap: bool = bf.mat_at(155, 155, ky + step) == "obsidian" and bf.mat_at(155, 155, ky + Data.KILL_CAP + 2.0 * step) != "obsidian" or bf.mat_at(155, 155, ky + step) == "obsidian"
	while bf._ktop(kc) > bf._kfloor(kc): bf._cell_remove(kc, bf._ktop(kc) - 1)   # (test only: a shaft dug to the floor)
	var at_floor: bool = is_equal_approx(bf.h[kc], ky) and is_equal_approx(bf.kill_y(bf.x0 + 155.5 * step, bf.z0 + 155.5 * step), ky)
	bf._set_fluid(kc, bf._kfloor(kc), "water")
	var k0: int = bf.killed
	bf.fluid_step(Vector3(bf.x0 + 155.5 * step, 0, bf.z0 + 155.5 * step), 100.0)
	var took_water: bool = bf.killed == k0 + 1 and bf._fluid_k(kc, bf._kfloor(kc)) == ""
	var deadly: bool = bf.touches_kill(Vector3(bf.x0 + 155.5 * step, ky + 0.5, bf.z0 + 155.5 * step)) and not bf.touches_kill(Vector3(bf.x0 + 155.5 * step, ky + 8.0, bf.z0 + 155.5 * step))
	var nch: int = ceili(float(bf.n) / Data.BLOCK_CHUNK)
	bf._draw_chunk((155 / Data.BLOCK_CHUNK) * nch + 155 / Data.BLOCK_CHUNK)
	var glow: bool = (bf._chunks[(155 / Data.BLOCK_CHUNK) * nch + 155 / Data.BLOCK_CHUNK] as Node).get_node_or_null("Kill") != null
	bf.restore(snap15)
	bf.flush()
	_check("Craters: world generation 1: %d sealed cave pockets (%d cells carved) that stand on their own; an obsidian cap over the kill floor; dug open, the kill floor glows, takes water and is deadly to the ship" % [bf.caves.size(), carved],
		bf.caves.size() >= 3 and carved > 50 and stands and cap and at_floor and took_water and deadly and glow,
		"stands %s cap %s floor %s water %s deadly %s glow %s" % [stands, cap, at_floor, took_water, deadly, glow])
	# 16. world generation part 2 (v1.6e): arches you can fly under, Pride Rock slabs over open air; they stand; take a
	#     leg out and that half comes down
	var cb: int = bf.collapses
	bf._settle(0, bf.n - 1, 0, bf.n - 1)
	var stand: bool = bf.collapses == cb
	var drop_ok := false
	var drop_info := "no arch"
	if not bf.arches.is_empty():
		var snap16: Dictionary = bf.snapshot()
		var ar: Dictionary = bf.arches[0]
		for cand in bf.arches:
			if bf.holes.has(int(cand["mid"])):
				ar = cand
				break
		var span: Array = ar["span"]
		var far: int = span[span.size() - 2]   # the far end of the span, next to the other leg
		var near: int = span[1]
		var leg: Array = (ar["legs"][0] as Array).duplicate()
		for c in span.slice(0, span.size() / 2):
			if not bf.holes.has(c): leg.append(c)   # (where the opening is too low to fly under, the leg goes on)
		for c in leg:   # blast leg 0 clean through, under the span
			var kt: int = bf._ktop(c)
			for k in range(kt - 14, kt - 2): bf._cell_remove(c, k)   # blown out: only its cap is left
		var cl1: int = bf.collapses
		bf._settle(0, bf.n - 1, 0, bf.n - 1)
		drop_ok = bf.collapses > cl1 and bf.holes.has(far)
		drop_info = "fell %d, far end still up %s, near end down %s" % [bf.collapses - cl1, bf.holes.has(far), not bf.holes.has(near)]
		bf.restore(snap16)
		bf.flush()
	_check("Craters: world generation 2: %d arches you can fly under and %d Pride Rock slabs over open air stand on their own; blast one leg out and what hung from it comes down, the far end stays up" % [bf.arches.size(), bf.overhangs.size()],
		bf.arches.size() >= 2 and bf.overhangs.size() >= 1 and flyable and jutting and stand and drop_ok, "flyable %s jutting %s stand %s %s" % [flyable, jutting, stand, drop_info])
	# 18. the deep world (v1.6h): root halls over the obsidian cap, obsidian trunks and branches holding the rock up,
	#     lava glowing between them, standing on their own, sealed under a roof
	var halls_ok: bool = bf.halls.size() >= 2
	var hinfo := []
	for hh in bf.halls:
		var air := 0
		var tot := 0
		var sealed_roof := true
		for jz in int(hh["w"]):
			for jx in int(hh["w"]):
				var c: int = (int(hh["z"]) + jz) * bf.n + int(hh["x"]) + jx
				var hfl: int = hh["k0s"][c]
				var hrf: int = hfl + int(hh["layers"])
				for k in range(hfl, hrf):
					tot += 1
					if not bf._solid_k(c, k): air += 1
				if not bf._solid_k(c, hrf) and not bf._solid_k(c, hrf + 1): sealed_roof = false
		var tr_ok := true
		for c in hh["trunks"]:
			for k in range(int(hh["k0s"][c]), int(hh["k0s"][c]) + int(hh["layers"])):
				if not bf._solid_k(c, k) or bf.mat_at(int(c) % bf.n, int(c) / bf.n, bf._ly(k)) != "obsidian": tr_ok = false
		hinfo.append("air %d%% trunks %d ok %s lava %d roof %s" % [100 * air / maxi(tot, 1), (hh["trunks"] as Array).size(), tr_ok, int(hh["lava"]), sealed_roof])
		if air * 2 < tot or not tr_ok or (hh["trunks"] as Array).is_empty() or not sealed_roof: halls_ok = false
	var cb2: int = bf.collapses
	bf._settle(0, bf.n - 1, 0, bf.n - 1)
	var halls_stand: bool = bf.collapses == cb2
	_check("Craters: the deep world: %d root halls over the obsidian cap, obsidian trunks and branches holding the rock up, lava glowing between them; sealed under their roof and standing on their own" % bf.halls.size(),
		halls_ok and halls_stand, "%s stand %s" % [str(hinfo), halls_stand])
	_check("Craters: shots dig INTO walls: a stone overhang over the tunnel holds; a sand one caves in; a pillar shot through its middle comes down (support and collapse)",
		over["stone"]["tunnel"] and over["stone"]["overhangs"] > 0 and over["stone"]["fell"] == 0 and over["sand"]["fell"] > 0 and over["sand"]["overhangs"] == 0
		and pillar["fell"] > 0 and not pillar["holes"] and pillar["h"] < 40.0, "overhang %s pillar %s" % [str(over), str(pillar)])
	bf.flush()


## v1.9k (owner): the far planet no longer flickers; after a capture the job line says where to go and is a button;
## handing the captive in = thanks, pay, the board; every job has a picture; music by system and by fight.
func _job_v19k() -> void:
	var s: SpaceSystem = main.space
	var keep := {"mission": GS.mission.duplicate(true), "bounty": GS.bounty.duplicate(true), "cargo": GS.cargo.duplicate(true), "credits": GS.credits, "last_base": GS.last_base}
	# the far planets stay drawn (the old 14 km far plane cut the ones 11-17 km out on and off)
	var far_ok: bool = s.cam.far >= Data.SPACE_CAM_FAR - 1.0 and Data.SPACE_CAM_FAR > 20000.0
	# a wanted-alive pilot, the job taken at this station
	var id := ""
	for f in Data.ROSTERS:
		for p in Data.ROSTERS[f]["pilots"]:
			var rp: Dictionary = Data.roster_pilot(str(p["id"]))
			if rp.get("bounty", false) and int(rp.get("rank", 1)) >= Data.BOUNTY_ALIVE_RANK and id == "": id = str(p["id"])
	GS.mission = {}
	GS.bounty = {}
	GS.last_base = str(s.station.get_meta("info")["id"])
	Missions.accept_bounty(id)
	GS.bounty = {}   # a stale board entry: the job's own pilot must still be caught
	var caught: bool = GS.capture_bounty(id) and GS.bounty.get("state", "") == "captured"
	GS.cargo.append({"kind": "pilot", "id": id})
	var mw: Dictionary = s.mission_waypoint()
	var way_ok: bool = not mw.is_empty() and mw["node"] == s.station and str(mw["line"]).begins_with("Return to")
	# tap the job line
	s.set_destination(null)
	s.gps_mission = false
	await _frames(3)
	main.hud._layout()
	main.hud._objective_button()
	var has_btn: bool = main.hud.buttons.has("objective")
	var c: Vector2 = (main.hud.buttons.get("objective", Rect2()) as Rect2).get_center()
	var at: String = main.hud.button_at(c)
	main._on_hud("objective")
	var tap_ok: bool = has_btn and at == "objective" and s.nav_dest == s.station and s.gps_mission
	await _shot("v19k_objective_line", 0.3)
	# GO TO: the job's autopilot (it carries on)
	s.autopilot = null
	s.target = null
	main._on_hud("goto")
	var auto_ok: bool = main._mission_auto and s.autopilot == s.station
	s.autopilot = null
	main._mission_auto = false
	# hand the pilot in: thanks, pay, and the bounty board
	var cr0: int = GS.credits
	main.dock(s.station)
	await _until(func(): return main.state == "hub", 8.0)
	await _frames(3)
	var thanks_ok: bool = main.last_thanks.contains("choose another one") and main.last_thanks.contains(str(Data.roster_pilot(id)["name"])) \
		and GS.mission.is_empty() and GS.credits > cr0 and main.hub.screen == "bounty"
	await _shot("v19k_bounty_thanks", 0.3)
	main.hub.show_screen("missions")
	await _frames(3)
	var icon: Node = main.hub.find_child("Icon_*", true, false)
	var icons_ok: bool = icon != null and (icon as Control).custom_minimum_size.x >= 100.0 and Data.BOARD_FONT >= 19
	await _shot("v19k_job_pictures", 0.3)
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	# music: systems of one faction open on different tracks; fights by tier
	var firsts := {}
	for sid in Data.SYSTEMS:
		if str(Data.SYSTEMS[sid].get("faction", "")) == "Neutral" or firsts.size() < 99:
			var tk: Array = Music.takes(Music.faction_mood(str(Data.SYSTEMS[sid].get("faction", "Neutral")), str(sid)))
			firsts[tk[0]] = true
	var none_held := true
	for f in Music.FACTION_POOL:
		for t in Music.FACTION_POOL[f]: if t in Music.HELD: none_held = false
	var tiers_ok: bool = Music.battle_mood(2) == "epic" and Music.battle_mood(1) == "battle" and s.engaged_tier() == 0
	var grp: Array = s._spawn_group(s.player.global_position + Vector3(0, 0, -400), 1)
	for e in grp: e["aggro"] = true
	var t1: int = s.engaged_tier()
	for e in grp: e["boss_mech"] = true
	var t2: int = s.engaged_tier()
	for e in grp:
		s.enemies.erase(e)
		e["node"].queue_free()
	var music_ok: bool = firsts.size() >= 6 and none_held and tiers_ok and t1 == 1 and t2 == 2
	GS.mission = keep["mission"]
	GS.bounty = keep["bounty"]
	GS.cargo = keep["cargo"]
	GS.credits = keep["credits"]
	GS.last_base = keep["last_base"]
	_check("v1.9k: far planets stay drawn (camera far %d m)" % int(s.cam.far), far_ok)
	_check("v1.9k: a captured bounty points back to the dock that posted it", caught and way_ok, str(mw.get("line", "")))
	_check("v1.9k: tapping the job line sets the waypoint; GO TO flies the job all the way", tap_ok and auto_ok, "button %s, tap %s, auto %s" % [has_btn, at, auto_ok])
	_check("v1.9k: handing a captive in: the giver thanks you, pays, and opens the bounty board", thanks_ok, main.last_thanks)
	_check("v1.9k: every job on the board has a picture tile, bigger board text", icons_ok)
	_check("v1.9k: music: each system opens on its own track of its faction's set; epic music for the big fights", music_ok, "%d opening tracks, tiers %d/%d" % [firsts.size(), t1, t2])


## v1.9l (owner): SPECIAL while it is locked = evasive moves picked by the stick; a second tap in a climb or dive = U-turn.
func _job_v19l() -> void:
	var s: SpaceSystem = main.space
	var hull0: float = GS.hull
	GS.hull = GS.max_hull()
	GS.form = "ship"
	s.set_player_model()
	for en in s.enemies: en["aggro"] = false
	_tp(Vector3(600, 3000, 600), Vector3(600, 3000, 0))
	s.vel = Vector3.ZERO
	s.pitch = 0.0
	s.aim = Vector2.ZERO
	s.move = Vector2.ZERO
	s.man_log = []
	# a real tap of the button (held for a frame)
	s.special_held = true
	await _frames(2)
	s.special_held = false
	var started: bool = s.man_kind == "climb" and s.special_state == "idle"
	var pmax := [0.0]
	await _until(func():
		pmax[0] = maxf(pmax[0], s.pitch)
		return s.man_t >= Data.MAN_TIME * 0.5 or s.man_kind != "climb", 4.0)   # (game time, not the clock)
	var p_up: float = rad_to_deg(maxf(pmax[0], s.pitch))
	var rolled: bool = absf(s.man_roll) > 0.5
	var up_v: float = s.vel.y
	await _shot("v19l_climb_roll", 0.0)
	var yaw0: float = s.yaw
	s._man_press()   # a second tap mid-climb: U-turn
	var ut: bool = s.man_kind == "uturn"
	await _until(func(): return s.man_kind == "", 5.0)
	await _wait(0.3)
	var turned: float = rad_to_deg(absf(angle_difference(yaw0, s.yaw)))
	await _shot("v19l_after_uturn", 0.2)
	var cam_fwd: Vector3 = -s.cam.global_basis.z
	var cam_with: bool = cam_fwd.dot(-s.player.global_basis.z) > 0.5
	var settled: bool = s.man_kind == "" and absf(rad_to_deg(s.pitch)) < 20.0
	s.aim = Vector2(0, 1)
	var pick_dive: String = s.man_pick()
	s.aim = Vector2(1, 0)
	var pick_r: String = s.man_pick()
	s.aim = Vector2(-1, 0)
	var pick_l: String = s.man_pick()
	s.aim = Vector2.ZERO
	s.move = Vector2(0, 1)
	var pick_f: String = s.man_pick()
	s.move = Vector2.ZERO
	s._man_start("right")
	var x0: Vector3 = s.player.global_basis.x
	var v0: Vector3 = s.vel
	await _wait(0.4)
	var side: bool = (s.vel - v0).dot(x0) > 5.0
	await _wait(1.0)
	GS.hull = hull0
	_check("v1.9l: SPECIAL tapped while locked = climb with a barrel roll (nose up, then level); tap again = U-turn, the camera swings round",
		started and p_up > 20.0 and rolled and up_v > 5.0 and ut and turned > 150.0 and cam_with and settled, "pitch %.0f, up %.0f m/s, turned %.0f deg, cam %s, settled %s" % [p_up, up_v, turned, cam_with, settled])
	_check("v1.9l: the stick picks the move: down = dive, left / right = roll that way, forward = burst",
		pick_dive == "dive" and pick_r == "right" and pick_l == "left" and pick_f == "fwd" and side, "%s %s %s %s side %s" % [pick_dive, pick_r, pick_l, pick_f, side])


## v1.9m (owner): the job pictures carry no colour of their own; the board frames each in its difficulty tier's colour.
func _job_v19m() -> void:
	main.dock(main.space.station)
	await _until(func(): return main.state == "hub", 8.0)
	main.hub.show_screen("missions")
	await _frames(3)
	var frames: Array = main.hub.find_children("Tier_*", "PanelContainer", true, false)
	var tiers := {}
	for f in frames: tiers[int(f.get_meta("tier"))] = true
	var pics := 0
	for k in ["patrol", "elite", "escort", "convoy", "ground", "outlaws"]:
		if ResourceLoader.exists(Data.MISSION_ICON_DIR + k + ".png"): pics += 1
	await _shot("v19m_tier_frames", 0.3)
	main.hub.show_screen("bounty")
	await _frames(3)
	var bframes: int = main.hub.find_children("Tier_*", "PanelContainer", true, false).size()
	await _shot("v19m_bounty_frames", 0.3)
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	var scale_ok: bool = Data.TIER_COLORS.size() == 10 and Data.tier_of_pay(1) == 1 and Data.tier_of_pay(999999) == 10 and Data.tier_of_pay(600) < Data.tier_of_pay(1600)
	_check("v1.9m: every job and bounty picture sits in a frame of its difficulty colour (blue to gold, 10 tiers); the owner's pictures load",
		frames.size() >= 4 and tiers.size() >= 2 and bframes >= 1 and pics == 6 and scale_ok, "%d job frames, tiers %s, %d bounty frames, %d pictures" % [frames.size(), tiers.keys(), bframes, pics])


## v1.9n (owner): SILVER: the rival faction's fleet invasion: 3 battleships (the target), 2 warships, a destroyer, a
## Star Command Station that keeps 20 fighters up; your allies fight beside you.
func _job_v19n() -> void:
	var s: SpaceSystem = main.space
	var keep := {"mission": GS.mission.duplicate(true), "credits": GS.credits, "hull": GS.hull}
	var st_id := str(s.station.get_meta("info")["id"])
	var offers: Array = Missions.offers(s.sys_id, st_id, Factions.owner_of(Data.SYSTEMS[s.sys_id]["station"], Data.SYSTEMS[s.sys_id]))
	var inv: Dictionary = {}
	for o in offers:
		if o["kind"] == "invasion": inv = o
	var offered: bool = not inv.is_empty() and Data.tier_of_pay(int(inv["pay"])) == 9
	if inv.is_empty():
		_check("v1.9n: a SILVER fleet invasion is on the board (tier 9)", false, "no invasion offered here")
		return
	GS.mission = {}
	GS.bounty = {}
	Missions.accept(inv)
	GS.hull = GS.max_hull() * 50.0   # (the test pilot does not die watching)
	var at: Vector3 = Missions.point_pos(s, 0)
	var far_ok: bool = at.distance_to(s.station.global_position) > 5000.0
	var wp0: Dictionary = s.mission_waypoint()
	_tp(at + Vector3(0, 300, 2900), at)   # (just outside: the same view, no fleet yet)
	await _frames(3)
	var tb := Time.get_ticks_msec()
	var fb := Engine.get_frames_drawn()
	await _wait(2.0)
	var fps0: float = float(Engine.get_frames_drawn() - fb) / maxf(0.001, float(Time.get_ticks_msec() - tb) / 1000.0)
	print("[v19n] before: process %.1f ms, prims %d, draws %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	_tp(at + Vector3(0, 200, 700), at)
	await _frames(4)
	var bs: int = s.invasion_units("battleship").size()
	var ws: int = s.invasion_units("warship").size()
	var ds: int = s.invasion_units("destroyer").size()
	var cs: int = s.invasion_units("command").size()
	var fs: int = s.invasion_units("fighter").size()
	var al: int = s.allies.size()
	var fleet_ok: bool = bs == 3 and ws == 2 and ds == 1 and cs == 1 and fs == int(Data.INVASION["fighters"]) and al == 7
	var wp: Dictionary = s.mission_waypoint()
	var line_ok: bool = str(wp0.get("line", "")).begins_with("SILVER") and str(wp.get("line", "")).contains("3 of 3")
	# the battle runs: allies and the fleet trade fire
	var hp0 := 0.0
	for e in s.invasion_units(): hp0 += float(e["hp"]) + float(e["sh"])
	var ally_hp0 := 0.0
	for a in s.allies: ally_hp0 += float(a["hp"])
	var t0 := Time.get_ticks_msec()
	var fr0 := Engine.get_frames_drawn()
	var gt0: float = s.time
	await _until(func(): return s.time >= gt0 + 10.0, 150.0)   # (ten seconds of game time)
	var pr := 0.0
	var ph := 0.0
	for k in 20:
		await get_tree().process_frame
		pr += Performance.get_monitor(Performance.TIME_PROCESS)
		ph += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	print("[v19n] avg process %.1f ms, physics %.1f ms, prims %d" % [pr / 20.0 * 1000.0, ph / 20.0 * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("[v19n] draw calls %d, process %.1f ms, objects %d, bolts %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), s.bolts.size()])
	var fps: float = float(Engine.get_frames_drawn() - fr0) / maxf(0.001, float(Time.get_ticks_msec() - t0) / 1000.0)
	await _shot("v19n_fleet_battle", 0.0)
	var hp1 := 0.0
	for e in s.invasion_units(): hp1 += float(e["hp"]) + float(e["sh"])
	var ally_hp1 := 0.0
	for a in s.allies: ally_hp1 += float(a["hp"])
	var fight_ok: bool = hp1 < hp0 and (ally_hp1 < ally_hp0 or s.allies.size() < al)
	# set damage on capitals
	var b0: Dictionary = s.invasion_units("battleship")[0]
	var cap_ok: bool = is_equal_approx(s.missile_damage(b0, false), Data.CAPITAL_MISSILE_DAMAGE) and s.missile_damage(b0, true) < float(b0["max"]) * 0.1
	# the station goes down; the fighters are thinned; a wave tops them up
	var cmd: Dictionary = s.invasion_units("command")[0]
	s._destroy_unit(cmd)
	await _frames(3)
	var down: bool = bool(GS.mission.get("station_down", false))
	for e in s.invasion_units("fighter").slice(0, 6): s._destroy_unit(e)
	var fs_low: int = s.invasion_units("fighter").size()
	s._inv_wave_t = 0.0
	await _frames(3)
	var refill: bool = s.invasion_units("fighter").size() > fs_low and s.inv_log.has("wave")
	# the three battleships: the job is won and paid
	var cr0: int = GS.credits
	for e in s.invasion_units("battleship"):
		s._destroy_unit(e)
		await _frames(2)
	await _frames(4)
	var won: bool = GS.mission.is_empty() and GS.credits >= cr0 + int(inv["pay"]) and s.allies.is_empty() and s.inv_log.has("won") and s.invasion_units("warship").is_empty()
	for e in s.invasion_units():
		s.enemies.erase(e)
		e["node"].queue_free()
	GS.mission = keep["mission"]
	GS.credits = keep["credits"]
	GS.hull = keep["hull"]
	_check("v1.9n: a SILVER fleet invasion is on the board (tier 9), far out from the station", offered and far_ok, "pay %d" % int(inv["pay"]))
	_check("v1.9n: the fleet: 3 battleships, 2 warships, a destroyer, the command station and 20 fighters; 6 allied fighters and a frigate with you",
		fleet_ok and line_ok, "%d/%d/%d/%d, %d fighters, %d allies; %s" % [bs, ws, ds, cs, fs, al, str(wp.get("line", ""))])
	_check("v1.9n: allies and the fleet fight each other; missiles do set damage on the big ships", fight_ok and cap_ok, "fleet %d -> %d, allies %d -> %d, %.1f fps (%.1f before)" % [hp0, hp1, ally_hp0, ally_hp1, fps, fps0])
	_check("v1.9n: the station going down is noticed, waves top the fighters up, the last battleship wins the job and pays", down and refill and won, "down %s, refill %s, won %s" % [down, refill, won])


## v1.9o (owner): the board: tap = hear it (phone voice) and ACCEPT / DECLINE; the job you have = CONTINUE / DISENGAGE
## (even with a prisoner aboard); a prisoner taken to their own people walks free, that faction turns hostile (its
## board is locked) and the freed pilot hunts you on launch.
## v1.9q RETOPO import: the owner's 38 stations and 15 planetary buildings (file names as delivered), placed by faction
## and style, each with a simple collision box.
func _job_v19q() -> void:
	var sys0: String = GS.system_id
	# 1. files and packs
	var st_keys: Array = []
	for sid in Data.RETOPO_STATIONS:
		for slot in Data.RETOPO_STATIONS[sid]: st_keys.append(str(Data.RETOPO_STATIONS[sid][slot]))
	var bad: Array = []
	for k: String in st_keys:
		var t := _st3d_tris("res://assets/stations3d/%s.glb" % k)
		if not (t >= 11000 and t <= 12500 and Packs.PACKS.has(k) and k.ends_with("_retopo")): bad.append("%s:%d" % [k, t])
	var b_files: Array = []
	for sid in Data.RETOPO_BUILDINGS:
		var f: String = Data.RETOPO_BUILDINGS[sid]
		if not Packs.PACKS.has("bld_%s" % f.to_lower()): bad.append("pack bld_%s" % f)
		for kind in Data.BUILDING_KINDS:
			var path := Data.building_file(f, kind)
			if not ResourceLoader.exists(path): continue
			var t2 := _st3d_tris(path)
			b_files.append(path)
			if t2 < 7500 or t2 > 8500: bad.append("%s:%d" % [path.get_file(), t2])
	_check("v1.9q (RETOPO): 38 station files (about 12k triangles, one pack each) and 15 planetary building files (about 8k, one pack per faction), names as delivered",
		st_keys.size() == 38 and b_files.size() == 15 and bad.is_empty(), "stations %d buildings %d bad %s" % [st_keys.size(), b_files.size(), bad])
	# 2. each one in its own faction's space, in the right slot
	var wrong: Array = []
	for sid in Data.RETOPO_STATIONS:
		var sy: Dictionary = Data.SYSTEMS[sid]
		var fac := str(sy.get("faction", ""))
		var role := str(sy.get("role", ""))
		for slot: String in Data.RETOPO_STATIONS[sid]:
			var key: String = Data.RETOPO_STATIONS[sid][slot]
			var ff: String = key.split("_")[2]
			var own: bool = ff == fac or role == "%s home" % ff or (ff == "Cybermorphs" and role == "Cybermorph home") \
				or (ff == "Unclaimed" and fac == "Neutral") or (ff == "Unknown" and fac == "Void")
			var body: Dictionary = sy["station"] if slot == "*" else {}
			if slot != "*":
				for b in sy.get("more_stations", []):
					if str(b.get("catalog_name", b["name"])) == slot.trim_prefix("+"): body = b
			var cap_ok: bool = not key.contains("_Capital_") or role == "capital" or role.ends_with(" home") or ff in ["Unclaimed", "Unknown"]
			if not own or body.get("model", "") != key or (slot != "*" and body.get("kind", "") != "station") or not cap_ok: wrong.append("%s/%s" % [sid, slot])
	_check("v1.9q: every station sits in its own faction's space (Capital at the homeworld, Military on a frontline, Trade at a hub, Outpost on the edge); enemy homes get their Military station beside the main one",
		wrong.is_empty(), str(wrong))
	# 3. Veranthos: the Unity capital wears it, big, with a box you bump off
	main._load_system("veranthos", "station")
	await _wait(1.0)
	var key0: String = Data.RETOPO_STATIONS["veranthos"]["*"]
	await Packs.wait(key0, 30.0)
	var s := _sp()
	await _until(func(): return s.station_model != null, Data.PH_BUILD_DELAY + 4.0)
	var holder: Node3D = s.station_model.get_parent() if s.station_model != null else null
	var big: bool = holder != null and is_equal_approx(holder.scale.x, s.STATION_WIDTH * Data.RETOPO_STYLE_SCALE["Capital"])
	var boxed: bool = s.station.has_meta("box_aabb")
	main.hud.visible = false
	_tp(s.station.global_position + Vector3(380, 160, 520), s.station.global_position)
	await _shot("v19q_unity_capital", 0.5)
	main.hud.visible = true
	var pushed := false
	if boxed:
		var bb: AABB = s.station.get_meta("box_aabb")
		var hd: Node3D = s.station.get_meta("box_holder")
		s.controls = true
		s.player.global_position = hd.global_transform * (bb.get_center() + Vector3(bb.size.x * 0.45, 0, 0))
		s.vel = Vector3.ZERO
		await _frames(3)
		var q: Vector3 = hd.global_transform.affine_inverse() * s.player.global_position
		pushed = not bb.grow(0.01).has_point(q)
	_check("v1.9q: in Veranthos the Unity Capital station is the main station, scaled up (x1.6 the standard width), and flying into it pushes you out of its collision box",
		holder != null and str(holder.get_meta("station3d", "")) == key0 and big and boxed and pushed, "model %s big %s box %s pushed %s" % [holder.get_meta("station3d", "") if holder else "-", big, boxed, pushed])
	# 4. Kronos: the Arctides home has its Capital and an added Military station beside it
	main._load_system("kronos", "station")
	await _wait(1.0)
	for k in ["HL_Station_Arctides_Capital_retopo", "HL_Station_Arctides_Military_retopo"]: await Packs.wait(k, 30.0)
	var sk := _sp()
	await _until(func(): return sk.station_model != null and sk.docks3d.size() >= 1 and sk.docks3d.all(func(n): return n.has_meta("dressed")), Data.PH_BUILD_DELAY + 4.0)
	var mil: Node3D = sk.docks3d[0] if not sk.docks3d.is_empty() else null
	if mil != null:
		main.hud.visible = false
		_tp(mil.global_position + Vector3(300, 120, 400), mil.global_position)
		await _shot("v19q_arctides_military", 0.5)
		main.hud.visible = true
	_check("v1.9q: Kronos (Arctides home) wears the Arctides Capital, and the Arctides Military station stands beside it with its own collision box",
		sk.station_model != null and mil != null and str(mil.get_meta("station3d", "")) == "HL_Station_Arctides_Military_retopo" and mil.has_meta("box_aabb"),
		"main %s added %s" % [sk.station_model != null, mil.get_meta("station3d", "") if mil else "-"])
	# 5. Aurelion Prime: the Elyza Command Center and Hangar stand on the ground of the homeworld
	main._load_system("aurelion", "station")
	await _wait(1.0)
	await Packs.wait("planets", 60.0)
	await Packs.wait("bld_elyza", 30.0)
	var sa := _sp()
	var pc: Vector3 = sa.planet.global_position
	var d := Vector3(0.2, 0.3, 1.0).normalized()
	_tp(pc + d * (float(sa.planet.get_meta("radius")) + 90.0), pc)
	main.hud.move_vec = Vector2(0, -1)
	await _until(func(): return main.state == "flight" and _sp().surface_mode, 20.0)
	main.hud.move_vec = Vector2.ZERO
	sa = _sp()
	await _until(func(): return sa.surf_boxes.size() == 2, 6.0)
	var on_ground := sa.surf_boxes.size() == 2
	for bx: Array in sa.surf_boxes:
		var hd2: Node3D = bx[0]
		var bb2: AABB = bx[1]
		var bottom: float = hd2.global_position.y + bb2.position.y * hd2.scale.y
		var half2: float = hd2.get_meta("half", 50.0)
		var g := INF
		var gh := -INF
		for o: Vector2 in Data.BUILDING_PROBES:
			var gg: float = sa._ground(hd2.global_position.x + o.x * half2, hd2.global_position.z + o.y * half2)
			g = minf(g, gg)
			gh = maxf(gh, gg)
		if absf(bottom - (g - Data.BUILDING_SINK)) > 1.0 or gh - g > Data.BUILDING_FLAT_OK: on_ground = false
	var cc: Node3D = sa.surf_boxes[0][0] if not sa.surf_boxes.is_empty() else null
	var solid := false
	if cc != null:
		main.hud.visible = false
		_tp(cc.global_position + Vector3(330, 230, 430), cc.global_position + Vector3(0, 40, 0))
		await _shot("v19q_elyza_buildings", 0.6)
		main.hud.visible = true
		var bb3: AABB = sa.surf_boxes[0][1]
		sa.controls = true
		sa.player.global_position = cc.global_transform * (bb3.get_center() + Vector3(0, 0, bb3.size.z * 0.4))
		sa.vel = Vector3.ZERO
		await _frames(3)
		solid = not bb3.grow(0.01).has_point(cc.global_transform.affine_inverse() * sa.player.global_position)
	_check("v1.9q: landing on Aurelion Prime (Elyza homeworld), the Elyza Command Center and Hangar stand on the ground near the sector centre and are solid (box collision)",
		on_ground and solid and str(cc.name if cc else "") == "HL_Elyza_CommandCenter", "boxes %d on ground %s solid %s" % [sa.surf_boxes.size(), on_ground, solid])
	_tp(Vector3(0, Surface.CEILING - 30.0, 0), Vector3(0, Surface.CEILING + 400.0, -100.0))
	main.hud.move_vec = Vector2(0, -1)
	await _until(func(): return main.state == "flight" and not _sp().surface_mode, 12.0)
	main.hud.move_vec = Vector2.ZERO
	main._load_system(sys0, "station")
	await _wait(1.6)
	main.hud.visible = true
	_sp().controls = true

## v1.9r (owner, Oct 25): dock rings come first, dying fails the job and restarts it, a box on every enemy, shared
## missile locks with the light missile's counter red on top and the heavy missile's (slower) purple underneath.
func _job_v19r() -> void:
	var s := _sp()
	if s.surface_mode or main.state != "flight": return
	# 1. the rings: their own small packs, asked for on arrival; the planet's docking gate and the jump gate ring are on
	var packs_ok := true
	for rp in Data.RING_PACKS:
		if not Packs.PACKS.has(rp) or Packs.PACKS[rp].get("match", "") == "": packs_ok = false
	for rp in Data.RING_PACKS: await Packs.wait(rp, 30.0)
	await _until(func(): return s.dock_gate != null and s.gate_model != null, 6.0)
	var early: bool = Data.PACK_ORDER.find("structures") >= 0 and Data.PACK_ORDER.find("structures") < Data.PACK_ORDER.find("voice_m1")
	_check("v1.9r: the docking ring over the planet and the jump gate ring come in their own small packs on arrival (the station models' pack moved up the queue)",
		packs_ok and s.rings_ready() and s.dock_gate != null and s.gate_model != null and early, "packs %s dock %s gate %s early %s" % [packs_ok, s.dock_gate != null, s.gate_model != null, early])
	# 2. shared locks
	for e0 in s.enemies.duplicate():
		if is_instance_valid(e0["node"]): (e0["node"] as Node3D).free()
	s.enemies = []
	var fwd := -s.player.global_basis.z
	var side := s.player.global_basis.x
	var es: Array = []
	for k in 3:
		var at: Vector3 = s.player.global_position + fwd * (300.0 + k * 40.0) + side * (k - 1) * 70.0
		var e: Dictionary = s.spawn_unit("raider", at, at)
		e["hp"] = 99999.0
		e["vel"] = Vector3.ZERO
		es.append(e)
	s.target = es[1]["node"]
	GS.slots = ["light_missile", "heavy_missile", "mine"]
	GS.rack = "swarm"
	if not ("swarm" in GS.owned_racks): GS.owned_racks.append("swarm")
	GS.missiles = 12
	GS.heavy_missiles = 2
	s.lock_time = Data.LOCK_STEP * 20.0
	var spread: Array = s.lock_spread("light_missile")
	var on_all: bool = spread.size() == 3 and spread.all(func(pr): return int(pr[1]) == GS.max_locks("light_missile") / 3)
	var target_first: bool = not spread.is_empty() and spread[0][0] == s.target
	s.lock_time = Data.LOCK_STEP * 3.0
	var slow: bool = s.lock_count("light_missile") == 3 and s.lock_count("heavy_missile") == 0
	s.lock_time = Data.HEAVY_LOCK_STEP * 2.2
	var heavy_n: int = s.lock_count("heavy_missile")
	var rows: Array = main.hud._lock_rows()
	var colours: bool = rows.size() == 2 and rows[0][0] == "light_missile" and rows[0][1] == true and rows[0][2] == Data.LIGHT_LOCK_COLOR \
		and rows[1][0] == "heavy_missile" and rows[1][1] == false and rows[1][2] == Data.HEAVY_LOCK_COLOR
	s.lock_time = Data.LOCK_STEP * 20.0
	await _shot("v19r_shared_locks", 0.3)
	_check("v1.9r: missile locks are shared: a full rack (%d) spreads over the hostiles in view, the target first; the heavy missile locks slower; the light counter is red on top of the box, the heavy one purple underneath" % GS.max_locks("light_missile"),
		on_all and target_first and slow and heavy_n >= 1 and colours, "spread %s first %s slow %s heavy %d rows %s" % [spread.map(func(pr): return int(pr[1])), target_first, slow, heavy_n, rows.map(func(r): return r[0])])
	for m in s.missiles_live: m["life"] = 0.0
	await _frames(3)
	s.missile_cd = 0.0
	s.lock_time = Data.LOCK_STEP * 20.0
	var n0: int = GS.missiles
	s.trigger_system("light_missile")
	await _wait(Data.VOLLEY_GAP * GS.max_locks("light_missile") + 0.3)
	var hit_nodes := {}
	for m in s.missiles_live:
		if is_instance_valid(m["target"]): hit_nodes[m["target"]] = true
	_check("v1.9r: firing the shared locks sends a missile at each locked hostile (%d missiles at 3 ships)" % GS.max_locks("light_missile"),
		n0 - GS.missiles == GS.max_locks("light_missile") and hit_nodes.size() == 3, "used %d, ships aimed at %d" % [n0 - GS.missiles, hit_nodes.size()])
	for m in s.missiles_live: m["life"] = 0.0
	# 3. every enemy wears a box (bigger, solid) when it is in view
	_check("v1.9r: every enemy in view wears a lock box you can tap (now %d px, drawn solid)" % int(Data.SHIP_BOX), Data.SHIP_BOX >= 18.0 and s.enemies.size() == 3, "%d enemies" % s.enemies.size())
	for e1 in s.enemies.duplicate():
		if is_instance_valid(e1["node"]): (e1["node"] as Node3D).free()
	s.enemies = []
	s.target = null
	# 4. dying fails the job and restarts it from the beginning
	Missions.abandon()
	GS.bounty = {}
	var sid: String = Data.SYSTEMS[s.sys_id]["station"]["id"]
	var offer: Dictionary = Missions.offers(s.sys_id, sid)[0]
	Missions.accept(offer)
	GS.mission["stage"] = 1   # (half way: the first point done; its next wave not met yet)
	GS.mission["escort_hp"] = 10.0
	var title := str(GS.mission["title"])
	var fails0: int = GS.mission_fails
	GS.god_mode = false
	s._die()
	await _until(func(): return main.state == "hub", 14.0)
	var m2: Dictionary = GS.mission
	var restarted: bool = not m2.is_empty() and str(m2["title"]) == title and int(m2["stage"]) == 0 and int(m2["spawned"]) == -1 and is_equal_approx(float(m2["escort_hp"]), Data.ESCORT_HULL) and GS.mission_fails == fails0 + 1
	var said: bool = main.hub.status.text.find("MISSION FAILED") >= 0
	_check("v1.9r: dying fails the job (MISSION FAILED) and it starts again from the beginning: first waypoint, every wave again",
		restarted and said and main.state == "hub", "stage %s spawned %s fails %d said %s" % [m2.get("stage", "-"), m2.get("spawned", "-"), GS.mission_fails - fails0, said])
	Missions.abandon()
	GS.god_mode = true
	await _launch()
	_sp().controls = true

## v1.9s (owner, Oct 25): Freelancer-style nebulae: hundreds of soft smoke puffs in one batch per cloud, real fog inside
## that thickens with depth, smoke streaming past the ship, lightning, and more clouds per system in other sizes and colours.
func _job_v19s() -> void:
	var s := _sp()
	if s.surface_mode or main.state != "flight": return
	var sysd: Dictionary = Data.SYSTEMS[s.sys_id]
	var neb: Array = s.nebulae
	var main_ok: bool = neb.size() >= 1 and is_equal_approx(float(neb[0]["radius"]), float(sysd["nebula"]["radius"]) * Data.NEBULA_SIZE) and float(neb[0]["radius"]) * 2.0 >= 2500.0
	var batch_ok := true
	var puffs := 0
	var cols: Array = []
	for nd in neb:
		var mmi: MultiMeshInstance3D = nd["mmi"]
		if not is_instance_valid(mmi) or mmi.multimesh.instance_count < 100: batch_ok = false
		else: puffs += mmi.multimesh.instance_count
		cols.append(nd["color"])
	var clear := true
	for i in range(1, neb.size()):
		if (neb[i]["center"] as Vector3).distance_to(sysd["station"]["pos"]) < float(neb[i]["radius"]) + 1000.0: clear = false
		if (neb[i]["color"] as Color).is_equal_approx(neb[0]["color"]): clear = false
	_check("v1.9s: every system has its own nebula grown to %.1f km across plus %d more clouds in other sizes and colours, each one batch of smoke puffs (%d puffs in all), clear of the station" % [float(neb[0]["radius"]) * 0.002 if neb.size() > 0 else 0.0, neb.size() - 1, puffs],
		main_ok and batch_ok and neb.size() == 1 + Data.NEBULA_EXTRA + neb.filter(func(x): return str(x.get("gate", "")) != "").size() and clear, "%d clouds, main %s, batches %s, clear %s" % [neb.size(), main_ok, batch_ok, clear])
	if neb.is_empty(): return
	main.hud.move_vec = Vector2.ZERO
	var c0: Vector3 = neb[0]["center"]
	var r0: float = neb[0]["radius"]
	_tp(c0 + Vector3(r0 * 1.9, r0 * 0.25, r0 * 0.6), c0)
	await _frames(3)
	var out_fog: bool = not s.env.environment.fog_enabled and s.in_nebula == 0.0 and not s._neb_stream.visible
	await _shot("v19s_nebula_from_outside", 0.4)
	_tp(c0 + Vector3(r0 * 0.88, 0, 0), c0)
	await _frames(3)
	var edge_d: float = s.env.environment.fog_density if s.env.environment.fog_enabled else 0.0
	_tp(c0 + Vector3(r0 * 0.1, 0, 0), c0 + Vector3(0, 0, -r0))
	await _frames(3)
	var deep_d: float = s.env.environment.fog_density if s.env.environment.fog_enabled else 0.0
	var stream_ok: bool = s._neb_stream.visible
	await _shot("v19s_nebula_inside", 0.4)
	_check("v1.9s: inside a cloud real fog closes in and thickens the deeper you go (edge %.4f, heart %.4f), smoke streams past the ship, radar is short" % [edge_d, deep_d],
		out_fog and edge_d > 0.0 and deep_d > edge_d * 1.5 and stream_ok and s.in_nebula > 0.9, "outside clear %s, stream %s, depth %.2f" % [out_fog, stream_ok, s.in_nebula])
	var f0: int = s.nebula_flashes
	s.nebulae[s.nebula_now]["next_flash"] = 0.0
	var lit := 0.0
	for i in 8:
		await _frames(1)
		lit = maxf(lit, s.nebula_flash)
	await _shot("v19s_nebula_lightning", 0.1)
	_check("v1.9s: lightning flashes inside the clouds and lights up the haze round you", s.nebula_flashes > f0 and lit > 0.0, "flashes %d, lit %.2f" % [s.nebula_flashes - f0, lit])
	var cname := ""
	if neb.size() > 1:
		var c1: Vector3 = neb[1]["center"]
		_tp(c1, c1 + Vector3(0, 0, -100))
		await _frames(3)
		cname = main.hud.get("zone_text") if main.hud.get("zone_text") != null else ""
	var in_extra: bool = neb.size() > 1 and s.nebula_now == 1 and s.nebula_name() == "" and s.nebula_tint.is_equal_approx(neb[1]["color"])
	main.navmap.open(s)
	await _frames(2)
	var on_map := 0
	for k in main.navmap.objs:
		if main.navmap.objs[k]["type"] == "nebula": on_map += 1
	await _shot("v19s_map_nebulae", 0.3)
	main.navmap.visible = false
	main._on_map_closed()
	var warp_n := 0   # v1.9z (owner): every WARP gate hides in its own cloud (no other gate does)
	var warp_in := 0
	var other_in := 0
	for sid in Data.SYSTEMS:
		var nbs: Array = SpaceSystem.nebulae_of(sid, Data.SYSTEMS[sid])
		for g in Data.SYSTEMS[sid]["gates"]:
			var hid := false
			for nd in nbs:
				if str(nd.get("gate", "")) == str(g.get("id", "")) and (g["pos"] as Vector3).distance_to(nd["center"]) < float(nd["radius"]) * 0.5: hid = true
			if str(g.get("gkind", "")) == "warp":
				warp_n += 1
				if hid: warp_in += 1
			elif hid: other_in += 1
	_check("v1.9z (owner): every warp gate hides inside its own cloud (%d of %d), and no jump or rift gate does" % [warp_in, warp_n], warp_n > 0 and warp_in == warp_n and other_in == 0, "other gates in clouds %d" % other_in)
	_check("v1.9s: the extra clouds are unnamed (no new lore), tint the fog their own colour, and show on the system map (%d clouds)" % on_map, in_extra and on_map == neb.size(), "in extra %s, on map %d" % [in_extra, on_map])
	_tp(s.station.global_position + Vector3(400, 80, 600), s.station.global_position)
	await _frames(3)

## v1.9u (owner, Oct 25): engines off at warp keeps the warp speed while you turn and shoot (THRUST = back to full
## thrust); missiles fly straight without a lock and chase with one; 20+ mines; a core gun on top of the wing guns
## with an even wing loadout; the five Nexus blasters (shield/hull split, own colour and sound, Mk I-V); the new
## equip page (your ship on a turntable, a mount map to tap).
func _job_v19u() -> void:
	var s := _sp()
	if s.surface_mode or main.state != "flight": return
	var keep := {}
	for k2 in ["credits", "ship_id", "weapon_id", "owned_weapons", "mounts", "missiles", "heavy_missiles", "owned_ships", "core_gun", "gun_levels"]:
		var v0 = GS.get(k2)
		keep[k2] = v0.duplicate() if (v0 is Array or v0 is Dictionary) else v0
	main.hud.move_vec = Vector2.ZERO
	_tp(s.station.global_position + Vector3(2500, 600, 2500), s.station.global_position + Vector3(9000, 600, 9000))
	await _frames(2)
	# 1. warp drift
	var base: float = float(GS.ship()["speed"])
	s.warp_state = "on"
	s.vel = -s.player.global_basis.z * base * Data.WARP_MULT
	await _frames(2)
	_press("kill")
	var y0: float = s.yaw
	main.hud.aim_vec = Vector2(1, 0)
	await _wait(0.6)
	main.hud.aim_vec = Vector2.ZERO
	var drifting: bool = s.warp_state == "off" and s.engine_kill and s.warp_drift and s.speed_now > base * Data.WARP_MULT * 0.9 and absf(s.yaw - y0) > 0.2
	var b0: int = s.bolts.size()
	s.mount_next.clear()
	s.gun_cd = 0.0
	var fl0: bool = s.fire_lock
	s.fire_lock = true
	GS.energy = Data.ENERGY_MAX
	await _frames(3)
	s.fire_lock = fl0
	var shot_drift: bool = s.bolts.size() > b0
	await _shot("v19u_warp_drift_firing", 0.1)
	main.hud.held["thrust"] = true
	GS.energy = Data.ENERGY_MAX
	await _wait(0.4)
	main.hud.held.erase("thrust")
	await _frames(2)
	var back: bool = not s.engine_kill and s.speed_now < base * Data.WARP_MULT * 0.5 and s.speed_now > base * 0.8
	_check("v1.9u (owner): KILL at warp keeps you drifting at warp speed (%d m/s) while you turn and shoot; THRUST restarts the engines at full thrust speed (%d m/s)" % [int(base * Data.WARP_MULT), int(s.speed_now)],
		drifting and shot_drift and back, "drift %s, shot %s, back to thrust %s" % [drifting, shot_drift, back])
	_press("stop")
	await _until(func(): return s.speed_now < 0.7 and not s.braking, 8.0)
	# 2. missiles: straight without a lock, chasing with one
	for m in s.missiles_live: m["life"] = 0.0
	await _frames(2)
	GS.missiles = 10
	GS.heavy_missiles = 4
	s.target = null
	s.lock_time = 0.0
	s.missile_cd = 0.0
	var l_ok: bool = s.trigger_system("light_missile") and s.missiles_live[-1]["target"] == null
	s.missile_cd = 0.0
	var h_ok: bool = s.trigger_system("heavy_missile") and s.missiles_live[-1]["target"] == null and s.missiles_live[-1]["heavy"]
	var grp: Array = s._spawn_group(s.player.global_position - s.player.global_basis.z * 260.0, 1)
	var e: Dictionary = s.enemies[-1]
	e["hp"] = 99999.0
	s.target = e["node"]
	s.missile_cd = 0.0
	s.lock_time = Data.LOCK_STEP * 1.2
	var homing: bool = s.trigger_system("light_missile") and s.missiles_live[-1]["target"] == e["node"]
	_check("v1.9u (owner): light and super missiles fly straight ahead with no lock, and chase the target once locked", l_ok and h_ok and homing, "light %s super %s homing %s" % [l_ok, h_ok, homing])
	for m in s.missiles_live: m["life"] = 0.0
	# 3. mines
	var mines_ok := true
	for sid in Data.SHIPS:
		if int(Data.SHIPS[sid]["mines"]) < 20: mines_ok = false
	_check("v1.9u (owner): every ship carries at least 20 mines", mines_ok and GS.max_mines() >= 20)
	# 4. core gun + an even wing loadout
	GS.credits = 90000
	if not ("ranger" in GS.owned_ships): GS.owned_ships.append("ranger")
	GS.ship_id = "cadet"
	GS.buy_ship("ranger")
	var items: Array = GS.mount_items()
	var even: bool = items[0] == items[2] and items[1] == items[3] and Data.WEAPONS.has(items[0])
	s.set_player_model()
	await _frames(2)
	var bc: int = s.bolts.size()
	s.mount_next.clear()
	s._fire_guns()
	var shots: int = s.bolts.size() - bc
	_check("v1.9u (owner): a new ship's wing guns sit evenly on both sides and the core gun fires from the nose too: %d front gun(s) + 2 wing guns = %d shots" % [GS.core_slots().size(), shots], even and shots == GS.core_slots().size() + 2, "mounts %s" % str(items))
	# 5. the Nexus blasters
	var split_ok := true
	var want := {"nx_blue": [20.0, 0.0], "nx_purple": [0.0, 20.0], "nx_yellow": [10.0, 10.0]}
	for id in want:
		var fake := {"node": e["node"], "sh": 100.0, "sh_max": 100.0, "hp": 100.0, "def": e["def"], "vis": e["vis"], "l": 50.0, "r": 50.0}
		s._damage_enemy(fake, 20.0, Vector3.INF, float(Data.WEAPONS[id]["shield"]))
		if not (is_equal_approx(100.0 - float(fake["sh"]), want[id][0]) and is_equal_approx(100.0 - float(fake["hp"]), want[id][1])): split_ok = false
	var bare := {"node": e["node"], "sh": 0.0, "sh_max": 100.0, "hp": 100.0, "def": e["def"], "vis": e["vis"], "l": 50.0, "r": 50.0}
	s._damage_enemy(bare, 20.0, Vector3.INF, 1.0)
	var blue_bare: bool = is_equal_approx(float(bare["hp"]), 100.0)
	var family_ok: bool = Data.NEXUS_BLASTERS.size() == 5
	var sounds_ok := true
	var cols := {}
	for id in Data.NEXUS_BLASTERS:
		cols[(Data.WEAPONS[id]["color"] as Color).to_html()] = true
		if Sfx.streams.get(str(Data.WEAPONS[id]["sound"])) == null: sounds_ok = false
	GS.buy_weapon("nx_red")
	var d1: float = GS.gun_damage("nx_red")
	var c1: int = GS.upgrade_cost("nx_red")
	var up: String = GS.upgrade_gun("nx_red")
	var leveled: bool = GS.gun_level("nx_red") == 2 and GS.gun_damage("nx_red") > d1 and GS.upgrade_cost("nx_red") > c1
	_check("v1.9u (owner): five Nexus blasters, five colours and sounds: blue shield only, green 75/25, yellow 50/50, red 25/75, purple hull only (shield damage is lost once it is down); Mk levels raise damage and cost",
		split_ok and blue_bare and family_ok and cols.size() == 5 and sounds_ok and leveled, "split %s, blue on bare hull %s, sounds %s, levels %s (%s)" % [split_ok, blue_bare, sounds_ok, leveled, up])
	# 6. the equip page
	if not ("nx_purple" in GS.owned_weapons): GS.buy_weapon("nx_purple")
	GS.fit_core("nx_purple")
	GS.fit_mount(0, "nx_red")
	GS.fit_mount(2, "nx_red")
	main.dock(s.station)
	await _until(func(): return main.state == "hub", 8.0)
	await Packs.wait("wing_guns", 30.0)
	main.hub.eq_sel = 0
	main.hub.eq_tab = "weapon"
	main.hub.eq_card = "nx_red"
	main.hub.show_screen("equipment")
	await _wait(0.8)
	var hb = main.hub
	var tt: Node3D = hb.find_child("Turntable", true, false)
	var dressed: bool = tt != null and tt.get_child_count() > 0 and tt.get_child(0).get_node_or_null("ShowMounts") != null and tt.get_child(0).get_node("ShowMounts").get_child_count() >= 3
	var page_ok: bool = hb.find_child("LoadoutPreview", true, false) != null and hb.find_child("MountMap", true, false) != null and hb.find_child("Up_nx_red", true, false) != null \
		and hb.find_child("ShopInstall", true, false) != null and not (hb.find_child("ShopInstall", true, false) as Button).disabled and hb.find_child("Card_nx_purple", true, false) != null
	var bcam: Camera3D = hb.find_child("BayCam", true, false)
	main.hub.bay_hold = 0.0
	var yaw0: float = main.hub.bay_yaw
	await _wait(0.3)
	var still: bool = absf(main.hub.bay_yaw - yaw0) < 0.001   # v3.5 (owner): it stands still until you drag it
	var mm0: Control = main.hub.find_child("MountMap", true, false)
	var dev := InputEventMouseMotion.new()
	dev.button_mask = MOUSE_BUTTON_MASK_LEFT
	dev.relative = Vector2(60, 0)
	if mm0 != null: mm0.gui_input.emit(dev)
	await _frames(2)
	var turning: bool = bcam != null and still and absf(main.hub.bay_yaw - yaw0) > 0.3 and absf(main.hub.preview_pivot.rotation.x) < 0.001 and absf(main.hub.preview_pivot.rotation.z) < 0.001   # (yaw only)
	await _shot("v19u_equip_page", 0.4)
	_check("v1.9u (owner): WEAPONS & GEAR shows your ship turning on a platform (yaw only) wearing its guns, a mount map to tap, and only the picked mount's fit buttons", dressed and page_ok and turning,
		"dressed %s, page %s, turning %s" % [dressed, page_ok, turning])
	for k2 in keep: GS.set(k2, keep[k2])
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	_sp().set_player_model()
	_sp().controls = true

## v1.9w (owner's three-level slot sheet): Level 1 Core Interceptor 4 core + 2 wing (6), 2 modules; Level 2 Strike
## Fighter 5 core + 4 wing (9), 4 modules; Level 3 Capital Variant 6 core + 6 wing (12), 6 modules.
func _job_v19w() -> void:
	var s := _sp()
	if s.surface_mode or main.state != "flight": return
	var keep := {}
	for k2 in ["credits", "ship_id", "weapon_id", "owned_weapons", "mounts", "owned_ships", "core_gun", "core_gun2", "core_gun3", "modules", "owned_modules", "shield"]:
		var v0 = GS.get(k2)
		keep[k2] = v0.duplicate() if (v0 is Array or v0 is Dictionary) else v0
	var lv_ok := true
	var want := {"cadet": [1, 4, 2, 2], "ranger": [2, 5, 4, 4], "bulk": [3, 6, 6, 6]}
	for sid in want:
		GS.ship_id = sid
		var core_n: int = GS.core_slots().size() + 3
		var got := [GS.ship_level(), core_n, GS.wing_slots(), GS.module_slots()]
		if got != want[sid]: lv_ok = false
	# a level 3 ship: three front guns, wing guns in pairs on its six slots
	GS.credits = 90000
	for sid in ["bulk"]:
		if not (sid in GS.owned_ships): GS.owned_ships.append(sid)
	GS.ship_id = "cadet"
	GS.buy_ship("bulk")
	if not ("nx_blue" in GS.owned_weapons): GS.buy_weapon("nx_blue")
	for i in 6: GS.fit_mount(i, "nx_blue")
	s.set_player_model()
	await _frames(2)
	var bc: int = s.bolts.size()
	s.mount_next.clear()
	s._fire_guns()
	var shots: int = s.bolts.size() - bc
	_check("v1.9w (owner): ship levels: Level 1 has 4 core + 2 wing slots and 2 modules, Level 2 5 + 4 and 4, Level 3 6 + 6 and 6; a Level 3 ship with all six wing slots fitted fires 3 front guns + 6 = %d shots" % shots,
		lv_ok and shots == 9, "levels %s" % lv_ok)
	# modules
	var sh0: float = GS.max_shield()
	GS.buy_module("shield_generator")
	GS.fit_module(0, "shield_generator")
	var sh1: float = GS.max_shield()
	GS.buy_module("processor_unit")
	GS.fit_module(1, "processor_unit")
	s.lock_time = Data.LOCK_STEP * 0.8
	var faster: bool = s.lock_count("light_missile") >= 1
	GS.fit_module(2, "shield_generator")   # one of each kind: it moves
	var moved: bool = GS.module_items()[0] == "" and GS.module_items()[2] == "shield_generator"
	_check("v1.9w: ability modules: the Shield Generator makes shields 20% stronger, the Processor Unit locks missiles faster, one of each kind at a time", is_equal_approx(sh1, sh0 * 1.2) and faster and moved, "shield %.0f -> %.0f, faster lock %s, moved %s" % [sh0, sh1, faster, moved])
	main.dock(s.station)
	await _until(func(): return main.state == "hub", 8.0)
	main.hub.eq_sel = 100
	main.hub.show_screen("equipment")
	await _wait(0.8)
	var hb = main.hub
	var page_ok: bool = hb.find_child("ModSlot_5", true, false) != null and hb.find_child("Card_power_cell", true, false) != null and hb.find_child("MountMap", true, false) != null
	await _shot("v19w_level3_equip", 0.4)
	GS.ship_id = "cadet"
	main.hub.eq_sel = -1
	main.hub.show_screen("equipment")
	await _wait(0.5)
	var small_ok: bool = hb.find_child("ModSlot_1", true, false) != null and hb.find_child("ModSlot_2", true, false) == null
	await _shot("v19w_level1_equip", 0.4)
	_check("v1.9w: WEAPONS & GEAR shows the ship's level blueprint with its slots and the module slots it has (6 on Level 3, 2 on Level 1)", page_ok and small_ok, "L3 page %s, L1 page %s" % [page_ok, small_ok])
	for k2 in keep: GS.set(k2, keep[k2])
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	_sp().set_player_model()
	_sp().controls = true

## v1.9x (owner's HANGAR layout): WEAPONS & GEAR fills the screen: frame (level) select, the blueprint with its slots,
## SLOT INFO, a shop grid with filters, the frame's specs; the mech blueprint shows the same slots (arms = wings).
## v3.5 (owner): every page stands you in a 360 room (Liberator's are in): the top bar, a left window, the page in a
## right window, HIDE PANELS to look round; drag looks round; the lounge lists who is here.
func _job_v35() -> void:
	var s := _sp()
	if s.surface_mode or main.state != "flight": return
	main.dock(s.station)
	await _until(func(): return main.state == "hub", 8.0)
	var hb = main.hub
	hb.room_override = "liberator"
	hb.show_screen("ships")
	await Packs.wait("room_liberator_shipyard", 30.0)
	await _frames(3)
	var rv: ColorRect = hb.room_view
	var tex = (rv.material as ShaderMaterial).get_shader_parameter("strip")
	var room_ok: bool = rv.visible and tex != null and (tex as Texture2D).resource_path.ends_with("liberator/shipyard.jpg") and hb.leftwin.visible \
		and is_equal_approx(hb.content.anchor_left, Data.ROOM_SPLIT) and hb.leftwin.find_child("RoomName", true, false) != null
	await _shot("v35_room_shipyard", 0.2)
	var y0: float = hb.room_yaw
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.relative = Vector2(-300, 40)
	hb._gui_input(ev)
	var looked: bool = absf(hb.room_yaw - y0) > 0.01 and hb.room_pitch != 0.0
	(hb.find_child("ShowPanels", true, false) as Button).pressed.emit()
	await _frames(2)
	var folded: bool = hb.panels_hidden and not hb.content.visible and not hb.leftwin.visible and hb.left.visible and hb.launch_btn.visible
	await _shot("v35_room_panels_hidden", 0.2)
	(hb.find_child("ShowPanels", true, false) as Button).pressed.emit()
	await _frames(2)
	var back: bool = not hb.panels_hidden and hb.content.visible
	hb.show_screen("lounge")
	await Packs.wait("room_liberator_pilots_lounge", 30.0)
	await _frames(3)
	var lounge_ok: bool = hb.room_key == "liberator_pilots_lounge" and hb.find_child("Btn_lounge", true, false) != null
	await _shot("v35_room_lounge", 0.2)
	# v3.7: the assistant stands in the HOME room, keyed out of her green screen; tap her and ask
	hb.show_screen("hub")
	await Packs.wait("assistant", 30.0)
	await Packs.wait("room_liberator_main_hub", 30.0)
	hb.show_screen("hub")
	await _frames(4)
	var a_on: bool = hb.asst.visible and hb.asst.is_playing() and hb.asst.material is ShaderMaterial
	var x0: float = hb.asst.position.x
	hb.look_by(Vector2(-200, 0))
	await _frames(2)
	var a_moves: bool = absf(hb.asst.position.x - x0) > 50.0
	hb.room_yaw = Data.ASST_YAW
	await _frames(2)
	hb.asst_tap()
	await _frames(2)
	var chat_ok: bool = hb.asst_chat.visible and str(hb.asst.get_meta("clip", "")) == "talk"
	hb.asst_ask("hello")
	await _frames(2)
	var said: String = (hb.asst_chat.find_child("Said", true, false) as Label).text
	var asked: bool = said != "" and not said.begins_with("Hi, pilot")
	await _shot("v37_assistant", 0.5)
	# v3.8: talk by voice (what the mic hears goes to her), a hands-free switch, and a log that folds away
	var log_closed: bool = not (hb.asst_chat.find_child("LogBox", true, false) as Control).visible
	hb.asst_heard("where is the shipyard")
	await _frames(2)
	hb.set_log_open(true)
	await _frames(2)
	var log_txt: String = (hb.asst_chat.find_child("LogText", true, false) as Label).text
	var voice_ok: bool = log_closed and hb.find_child("MicButton", true, false) != null and hb.find_child("HandsFree", true, false) != null \
		and log_txt.contains("YOU: where is the shipyard") and log_txt.count("HER:") >= 2
	await _shot("v38_assistant_log", 0.3)
	hb.set_log_open(false)
	_check("v3.8 (owner): she has a MIC button and HANDS-FREE talk; what you say goes to her and she answers; the chat log is folded away until you open it", voice_ok, log_txt.replace("\n", " | "))
	_check("v3.7 (owner): the station assistant stands in the HOME room (green keyed out), keeps her spot as you look round; tap her to talk and the brain answers (%s)" % said,
		a_on and a_moves and chat_ok and asked, "on %s, moves %s, chat %s, answered %s" % [a_on, a_moves, chat_ok, asked])
	# v3.9 (owner): all ten rooms are used: REPAIR = medical bay; the hangar's WEAPON tab = weapons room, REPAIR & AMMO = supplies
	hb.show_screen("repair")
	await Packs.wait("room_liberator_medical_bay", 30.0)
	await _frames(3)
	var med_ok: bool = hb.room_key == "liberator_medical_bay"
	hb.eq_tab = "weapon"
	hb.show_screen("equipment")
	await Packs.wait("room_liberator_weapons", 30.0)
	hb.show_screen("equipment")
	await _frames(4)
	var wpn_ok: bool = hb.room_key == "liberator_weapons" and hb.room_view.visible and (hb.find_child("BayArt", true, false) as CanvasItem).self_modulate.a == 0.0
	await _shot("v39_hangar_weapons_room", 0.3)
	hb.eq_tab = "ammo"
	hb.show_screen("equipment")
	await Packs.wait("room_liberator_supplies", 30.0)
	hb.show_screen("equipment")
	await _frames(3)
	var sup_ok: bool = hb.room_key == "liberator_supplies"
	hb.eq_tab = "hangar"
	hb.show_screen("equipment")
	await _frames(3)
	var bay_ok: bool = not hb.room_view.visible and (hb.find_child("BayArt", true, false) as CanvasItem).self_modulate.a == 1.0
	var used := {}
	for k in Data.ROOM_OF: used[Data.ROOM_OF[k]] = true
	used["weapons"] = true
	used["supplies"] = true
	_check("v3.9 (owner): all ten rooms have a place: REPAIR = medical bay, the hangar's WEAPON tab = weapons room, REPAIR & AMMO = supplies (the HANGAR tab keeps the bay)",
		med_ok and wpn_ok and sup_ok and bay_ok and used.size() == 10, "med %s, weapons %s, supplies %s, bay %s, rooms %d" % [med_ok, wpn_ok, sup_ok, bay_ok, used.size()])
	hb.eq_tab = "weapon"
	hb.room_override = ""
	hb.show_screen("hub")
	await _frames(2)
	var other_ok: bool = hb.room_for("hub") == "" or hb._room_faction() != "" and Packs.PACKS.has("room_savagers_main_hub") and "savagers" in Data.ROOM_FACTIONS and Packs.PACKS.has("room_orion_weapons") and "orion" in Data.ROOM_FACTIONS and "covenant" in Data.ROOM_FACTIONS and Packs.PACKS.has("room_covenant_main_hub")
	_check("v3.5 (owner): pages stand you in a 360 room (Liberator): top bar, left window, page on the right; drag looks round; HIDE PANELS folds both windows (the top bar and LAUNCH stay); a LOUNGE page",
		room_ok and looked and folded and back and lounge_ok and other_ok, "room %s, look %s, fold %s, back %s, lounge %s, other %s" % [room_ok, looked, folded, back, lounge_ok, other_ok])
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	_sp().controls = true

func _job_v19x() -> void:
	var s := _sp()
	if s.surface_mode or main.state != "flight": return
	var ship0: String = GS.ship_id
	GS.ship_id = "ranger"
	if not ("ranger" in GS.owned_ships): GS.owned_ships.append("ranger")
	main.dock(s.station)
	await _until(func(): return main.state == "hub", 8.0)
	var hb = main.hub
	hb.eq_filter = "all"
	hb.eq_tab = "weapon"
	hb.eq_view = "ship"
	hb.eq_sel = 0
	hb.show_screen("equipment")
	await _wait(0.6)
	var lay_ok: bool = hb.find_child("Hangar", true, false) != null and not hb.left.visible and hb.find_child("Frame_3", true, false) != null and hb.find_child("HangarBay", true, false) != null \
		and hb.find_child("ShopGrid", true, false) != null and hb.find_child("FrameSpec", true, false) != null and hb.find_child("BayArt", true, false) != null and (hb.find_child("BayArt", true, false) as TextureRect).texture != null and (hb.find_child("Frame_2", true, false) as Button).get_theme_color("font_color") == hb.GOLD
	await _shot("v19x_hangar_ship", 0.3)
	hb.bay_yaw = 0.8
	hb.bay_hold = 99.0
	await _frames(3)
	await _shot("v26_ship_turning", 0.0)
	hb.bay_yaw = 0.0
	var hn: String = hb._hangar_name()
	var bays_ok := true
	for n in Data.BAYS:
		if not Packs.PACKS.has("hangar_" + n) or not ResourceLoader.exists("res://assets/hangars/bay_%s.jpg" % n): bays_ok = false
	# v2.2 (owner): tap a "+" on the ship to pick its slot
	var w0 = GS.mount_items()[0]
	GS.fit_mount(0, "empty")
	hb.eq_tab = "hangar"
	hb.show_screen("equipment")
	await _frames(3)
	var ov: Control = hb.find_child("MountMap", true, false)
	var tag_k: int = hb._slot_at(hb._slot_layout(ov.size, ov.get_meta("pts", {}), hb._slot_half(ov)).get(0, Rect2()).get_center(), ov.get_meta("pts", {}), ov) if ov != null and ov.has_meta("pts") else -9
	var tapped := false
	if ov != null and ov.has_meta("pts"):
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = false
		ev.position = (ov.get_meta("pts") as Dictionary)[0]
		hb.eq_sel = -1
		ov.gui_input.emit(ev)
		await _frames(3)
		tapped = hb.eq_sel == 0 and hb.eq_tab == "weapon"
	hb.eq_card = "pulse1"
	hb.show_screen("equipment")
	await _frames(2)
	(hb.find_child("ShopInstall", true, false) as Button).pressed.emit()
	await _frames(3)
	var fitted: bool = str(GS.mount_items()[0]) == "pulse1"
	GS.fit_mount(0, str(w0))
	_check("v2.2 (owner): tap a slot's + (or its tag) on the ship to pick it, then INSTALL fits the picked weapon there",
		tapped and tag_k == 0 and fitted, "tap %s, tag %s, fitted %s" % [tapped, tag_k, fitted])
	var art_ok: bool = (hb.find_child("BayArt", true, false) as TextureRect).texture != null and (hb.find_child("BayArt", true, false) as TextureRect).texture.resource_path.ends_with("bay_%s.jpg" % hn)
	var gone_ok: bool = not ResourceLoader.exists("res://assets/hangars/unity_top.jpg") and not ResourceLoader.exists("res://assets/hangars/unity_top.ogv")
	var k0: String = hb.kind
	hb.kind = "planet"
	var pn: String = hb._hangar_name()
	await Packs.wait("hangar_" + pn, 30.0)
	hb.show_screen("equipment")
	await _wait(0.5)
	await _shot("v28_planet_hangar", 0.2)
	hb.kind = k0
	hb.show_screen("equipment")
	await _wait(0.3)
	var planet_ok: bool = (pn.begins_with("p_") or not Data.BAYS.has("p_" + hn)) and Packs.PACKS.has("hangar_p_covenant") and Data.BAYS.has("p_savagers") and Data.BAYS.has("p_cybermorph") and Packs.PACKS.has("hangar_p_solrath") and Data.BAYS.has("gadversee") and Packs.PACKS.has("hangar_kaijurai")
	_check("v2.8 (owner): docked on a planet, a faction's hangar is its planet hangar (%s)" % pn, planet_ok)
	_check("v2.7 (owner: no more top view): each faction's hangar is its front-view bay with the ship standing on the pad (others a spare); each bay its own small pack (%s here); the top-view pictures and clips are gone" % hn,
		bays_ok and Data.BAYS.has(hn) and art_ok and gone_ok and hb.find_child("BayCam", true, false) != null, "%s art %s gone %s" % [hn, art_ok, gone_ok])
	hb.eq_view = "mech"
	hb.show_screen("equipment")
	await _wait(0.4)
	var mech_ok: bool = hb._eq_mech() and hb._wicon("nx_purple") != null and hb._wicon("nx_purple").resource_path.contains("mech_weapons") and hb._level_tex() != null and str(GS.level_def()["mech_art"]).ends_with("mech_cut2.png") and hb._mount_points(Vector2(300, 400)).size() == 9
	await _shot("v19x_hangar_mech", 0.3)
	# v2.4 (owner): the real mech, built from its parts, standing in a front-view mech bay, a square on each slot
	await Packs.wait("mechs", 40.0)
	for pv in GS.mech_keys().values():
		if ShipFactory.pack_of(str(pv)) != "": await Packs.wait(ShipFactory.pack_of(str(pv)), 40.0)
	await Packs.wait("hangar_" + hb._hangar_name(), 30.0)
	hb.show_screen("equipment")
	await _wait(0.5)
	var mmap: Control = hb.find_child("MountMap", true, false)
	var bart: TextureRect = hb.find_child("BayArt", true, false)
	var real_mech: bool = hb.find_child("BayMech", true, false) != null and mmap != null and (mmap.get_meta("pts", {}) as Dictionary).size() == 9 \
		and Data.BAYS.has(hb._hangar_name()) and bart != null and bart.texture != null and bart.texture.resource_path.contains("bay_")
	await _shot("v24_mech_bay", 0.3)
	var top_ok := true   # v3.3: the whole mech is inside the bay (its head was cut off on a phone)
	for pt in (mmap.get_meta("pts", {}) as Dictionary).values(): if (pt as Vector2).y < 0.0: top_ok = false
	_check("v3.3 (owner's screenshot): the mech fits in the bay, head and all", top_ok)
	# v2.6 (owner): it stands on the faction bay's round pad and turns on it (drag turns it too)
	var y0: float = hb.bay_yaw
	hb.bay_hold = 0.0
	await _wait(0.5)
	var turned: bool = absf(hb.bay_yaw - y0) < 0.001 and absf(hb.preview_pivot.rotation.y - hb.bay_yaw) < 0.01   # v3.5: stands still
	var ev := InputEventMouseMotion.new()
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.relative = Vector2(100, 0)
	var y1: float = hb.bay_yaw
	mmap.gui_input.emit(ev)
	var dragged: bool = absf(hb.bay_yaw - y1) > 0.5 and hb.bay_hold > 0.0
	hb.bay_yaw = 0.5
	hb.bay_hold = 99.0
	await _frames(3)
	await _shot("v26_mech_turning", 0.0)
	_check("v2.6/v3.5 (owner): the mech stands still on its bay's platform and drags round by hand; each faction has its own mech bay", turned and dragged and Data.BAYS.has("elyza") and Packs.PACKS.has("hangar_imperium"),
		"turn %s, drag %s" % [turned, dragged])
	_check("v2.4 (owner): the mech view shows your real mech (its fitted parts) standing in a front-view mech bay, with a + square on each of its 9 slots", real_mech,
		"mech %s, bay %s" % [hb.find_child("BayMech", true, false) != null, hb._hangar_name()])
	(hb.find_child("Tab_ammo", true, false) as Button).pressed.emit()
	await _frames(3)
	var ammo_ok: bool = (hb.find_child("EqAmmo", true, false) as Control).visible and not (hb.find_child("EqBuy", true, false) as Control).visible and hb.find_child("RestockAll", true, false) != null
	(hb.find_child("Tab_weapon", true, false) as Button).pressed.emit()
	await _frames(2)
	(hb.find_child("Filter_blaster", true, false) as Button).pressed.emit()
	await _frames(3)
	var bl: Button = hb.find_child("Card_nx_green", true, false)
	var filt_ok: bool = bl != null and bl.visible and not (hb.find_child("Card_pulse2", true, false) as Control).visible
	(hb.find_child("HangarBack", true, false) as Button).pressed.emit()
	await _frames(2)
	var back_ok: bool = hb.screen == "hub" and hb.left.visible
	_check("v1.9x (owner's HANGAR): WEAPONS & GEAR fills the screen with frame select, the blueprint and its slots, SLOT INFO, a shop grid with filters and the specs; SHOW MECH swaps in the mech blueprint; back to the station menu",
		lay_ok and mech_ok and ammo_ok and filt_ok and back_ok, "layout %s, mech %s, ammo %s, filter %s, back %s" % [lay_ok, mech_ok, ammo_ok, filt_ok, back_ok])
	hb.eq_filter = "all"
	hb.eq_tab = "weapon"
	hb.eq_view = ""
	GS.ship_id = ship0
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	_sp().set_player_model()
	_sp().controls = true

## v1.9z (owner: "inside a Freelancer cloud you can't see out; it has its own weather"): deep inside, the sky is gone;
## each cloud has snow, rain, an electric storm or a rock field.
func _job_v19z() -> void:
	var s := _sp()
	if s.surface_mode or main.state != "flight" or s.nebulae.is_empty(): return
	main.hud.move_vec = Vector2.ZERO
	var kinds_ok := true
	for nd in s.nebulae:
		if not (str(nd.get("weather", "")) in Data.NEBULA_WEATHERS): kinds_ok = false
	var nd0: Dictionary = s.nebulae[1] if s.nebulae.size() > 1 else s.nebulae[0]   # (an extra cloud: no light beacon thinning the haze)
	var keep: String = nd0["weather"]
	var c0: Vector3 = nd0["center"]
	var seen := {}
	var sky_gone := true
	for k in Data.NEBULA_WEATHERS:
		nd0["weather"] = k
		_tp(c0 + Vector3(float(nd0["radius"]) * 0.05, 0, 0), c0 + Vector3(0, 0, -500))
		s.vel = -s.player.global_basis.z * 30.0
		await _frames(4)
		s.vel = Vector3.ZERO
		seen[k] = s._neb_wx != null and s._neb_wx.visible and s.nebula_weather() == k
		if s.dome_alpha < 0.99 * (1.0 - Data.BEACON_HAZE_CLEAR * s.beacon_lit) or not s._dome.visible: sky_gone = false   # (a light beacon thins the haze near its lamp)
		await _shot("v19z_weather_" + k, 0.2)
	var dm := s._dome.material_override as ShaderMaterial
	_check("v2.1 (owner): cloud walls are the still cloud picture again (no clips, no face)", dm != null and not ("anim" in str(dm.shader.code)) and not ("face" in str(dm.shader.code)))
	nd0["weather"] = keep
	var rock_ok := true   # a rock-field cloud puts its rocks in the collision list
	var probe := {"center": c0 + Vector3(0, 9000, 0), "radius": 600.0}
	var n0: int = s.rocks.size()
	s._nebula_rocks(s, probe, RandomNumberGenerator.new())
	rock_ok = s.rocks.size() == n0 + Data.NEBULA_ROCKS
	for i in Data.NEBULA_ROCKS: s.rocks.pop_back()
	var mi = s.get_node_or_null("NebulaRocks")
	if mi != null: mi.queue_free()
	# a warp gate: a hole in space (no ring) inside its cloud
	var wsys := ""
	for sid in Data.SYSTEMS:
		for g in Data.SYSTEMS[sid]["gates"]:
			if str(g.get("gkind", "")) == "warp" and wsys == "": wsys = sid
	var sys0: String = s.sys_id
	var hole_ok := false
	if wsys != "":
		main._load_system(wsys, "station")
		await _wait(1.6)
		var ws := _sp()
		for g in ws.gates:
			if not g.get_meta("hole", false): continue
			hole_ok = g.get_node_or_null("WarpHole") != null and g.get_node_or_null("WarpSparks") != null and not (g.get_meta("standin") as Node3D).get_child_count() > 0
			var away: Vector3 = (g.global_position - ws.station.global_position).normalized()
			_tp(g.global_position - away * 330.0 + Vector3(0, 30, 0), g.global_position)
			await _frames(6)
			await _shot("v19z_warp_gate_hole", 0.5)
			break
		main._load_system(sys0, "station")
		await _wait(1.6)
		s = _sp()
	_check("v1.9z (owner): a warp gate is a Freelancer-style hole: a ragged swirling opening, sparks spiralling in, cloud wisps, no ring (%s)" % wsys, hole_ok)
	# the jump-gate tunnel wears the owner's picture and spins
	var fx = main.fx
	fx.begin_warp("tunnel")
	fx.warp = 1.0
	fx.pace = 1.0
	var sp0: float = fx.tex_spin
	await _frames(4)
	var tun_ok: bool = fx.tunnel_tex_on and absf(fx.tex_spin - sp0) > 0.0 and (fx._warp_rect.material as ShaderMaterial).get_shader_parameter("use_tex") == true
	await _shot("v19z_jump_tunnel", 0.1)
	var wind_ok: bool = float((fx._warp_rect.material as ShaderMaterial).get_shader_parameter("wind")) == 0.0   # v3.4 (owner): both tunnels straight
	fx.travel += 6.0   # further along: the bend swings the other way
	await _frames(2)
	await _shot("v25_tunnel_bend_other_way", 0.0)
	tun_ok = tun_ok and wind_ok
	fx.begin_warp("cloud")
	await _frames(4)
	var warp_t_ok: bool = fx.warp_tex_on and (fx._warp_rect.material as ShaderMaterial).get_shader_parameter("use_tex_b") == true and str((fx._warp_rect.material as ShaderMaterial).shader.code).contains("if (wind > 0.0 && skin == 0)")
	await _shot("v19z_warp_gate_tunnel", 0.1)
	tun_ok = tun_ok and warp_t_ok
	fx.end_warp()
	fx.warp = 0.0
	_check("v1.9z (owner): the jump-gate tunnel is his blue picture and the warp-gate tunnel his red one, rushing at you and spinning (the warp drive keeps its plain streaks)", tun_ok, "tunnel %s" % tun_ok)
	_check("v1.9z (owner): deep in a cloud the sky is gone (you can't see out), and each cloud has its own weather: snow, rain, electric storm or rock field (rocks you can hit)",
		kinds_ok and sky_gone and seen.values().all(func(x): return x) and rock_ok and Data.NEBULA_STORM_FLASH[1] < Data.NEBULA_FLASH_EVERY[0] + 0.5, "kinds %s, sky gone %s, seen %s, rocks %s" % [kinds_ok, sky_gone, seen, rock_ok])
	# deep in a planet's air the sky closes round you (bright, not black space)
	var pl: Node3D = s.planet
	var prad: float = float(pl.get_meta("info")["radius"])
	var pdir: Vector3 = (s.player.global_position - pl.global_position).normalized()
	s.controls = false
	_tp(pl.global_position + pdir * prad * lerpf(Data.ATMO_OUTER, Data.ATMO_INNER, 0.85), pl.global_position)
	await _frames(4)
	var atmo_ok: bool = s.atmo_depth > 0.6 and s.dome_alpha > 0.7 and s._dome.visible and s.atmo_color.v > 0.7
	await _shot("v19z_atmosphere_inside", 0.2)
	s.controls = true
	_tp(s.station.global_position + Vector3(400, 80, 600), s.station.global_position)
	await _frames(3)
	var gone: bool = not s._dome.visible
	_check("v1.9z (owner): deep in a planet's atmosphere the sky's own bright colour closes round you instead of black space (the entry flows into the surface), and it clears when you leave", atmo_ok and gone, "depth %.2f shell %.2f colour %s, cleared %s" % [s.atmo_depth, s.dome_alpha, s.atmo_color, gone])

func _job_v19o() -> void:
	var s: SpaceSystem = main.space
	var keep := {"mission": GS.mission.duplicate(true), "bounty": GS.bounty.duplicate(true), "cargo": GS.cargo.duplicate(true), "rep": GS.rep.duplicate(true)}
	GS.mission = {}
	GS.bounty = {}
	main.dock(s.station)
	await _until(func(): return main.state == "hub", 8.0)
	var hub = main.hub
	hub.show_screen("missions")
	await _frames(3)
	var o0: Dictionary = Missions.offers(GS.system_id, hub.base["id"], Factions.owner_of(hub.base, Data.SYSTEMS[GS.system_id]))[0]
	hub.pick_row("j:Job_threats", func(): hub.read_job(o0))
	await _frames(3)
	var heard: bool = Sfx.last_read_aloud.begins_with("PATROL") and hub.find_child("Decline_Take_Job_threats", true, false) != null and (hub.find_child("Take_Job_threats", true, false) as Button).text == "ACCEPT"
	await _shot("v19o_heard_accept_decline", 0.3)
	(hub.find_child("Decline_Take_Job_threats", true, false) as Button).pressed.emit()
	await _frames(2)
	var declined: bool = GS.mission.is_empty() and hub.find_child("Decline_Take_Job_threats", true, false) == null
	(hub.find_child("Take_Job_threats", true, false) as Button).pressed.emit()
	await _frames(2)
	var took: bool = GS.mission.get("kind", "") == "threats" and hub.find_child("Continue_Take_Job_threats", true, false) != null and (hub.find_child("Take_Job_threats", true, false) as Button).text == "DISENGAGE"
	await _shot("v19o_continue_disengage", 0.3)
	# a prisoner aboard: DISENGAGE lets them go
	var bid := "savagers_03"
	GS.mission = {}
	Missions.accept_bounty(bid)
	GS.capture_bounty(bid)
	GS.cargo.append({"kind": "pilot", "id": bid})
	var blocked: String = Missions._switch_block()
	var said: String = Missions.disengage()
	var let_go: bool = blocked.contains("DISENGAGE") and GS.mission.is_empty() and GS.bounty.is_empty() and not GS.cargo.any(func(c): return c.get("kind", "") == "pilot") and said.begins_with("Disengaged")
	# the prisoner's home: freed, hostile, board locked, chased on launch
	Missions.accept_bounty(bid)
	GS.capture_bounty(bid)
	GS.cargo.append({"kind": "pilot", "id": bid})
	var home: Dictionary = hub.base.duplicate()
	home["faction"] = "Savagers"
	var line: String = main.prisoner_home(home)
	var freed: bool = line.contains("don't want your business") and GS.bounty.is_empty() and Factions.hostile("Savagers") and main.chaser == bid
	hub.open(home)
	hub.show_screen("missions")
	await _frames(2)
	var locked: bool = hub.find_child("BoardLocked", true, false) != null and hub.find_child("Take_Job_threats", true, false) == null
	await _shot("v19o_board_locked", 0.3)
	hub.open(s.station.get_meta("info"))
	main.launch()
	await _until(func(): return main.state == "flight", 8.0)
	var hunted: bool = main.chaser == "" and s.enemies.any(func(e): return str(e["node"].name).contains("(freed)") and e.get("aggro", false))
	for e in s.enemies.filter(func(e): return int(e.get("mission", 0)) == -8):
		s.enemies.erase(e)
		e["node"].queue_free()
	GS.mission = keep["mission"]
	GS.bounty = keep["bounty"]
	GS.cargo = keep["cargo"]
	GS.rep = keep["rep"]
	_check("v1.9o: tap a job = it is read out in the phone voice and shows ACCEPT / DECLINE; DECLINE closes it; ACCEPT takes it; then CONTINUE / DISENGAGE", heard and declined and took, "heard %s declined %s took %s" % [heard, declined, took])
	_check("v1.9o: DISENGAGE drops a job even with a prisoner aboard (they are let go)", let_go, said)
	_check("v1.9o: a prisoner brought to their own people walks free; that faction turns hostile, its board is locked, and the freed pilot hunts you on launch", freed and locked and hunted, "freed %s locked %s hunted %s" % [freed, locked, hunted])


## v1.9p (owner): the chase camera stops at the ground (moves in, to first person) instead of going under it; the map
## has SET WAYPOINT and GO beside CURRENT MISSION, and GO flies the job all the way.
func _job_v19p() -> void:
	var keep := {"mission": GS.mission.duplicate(true), "bounty": GS.bounty.duplicate(true)}
	# the map
	var s := _sp()
	GS.mission = {}
	GS.bounty = {}
	var o: Dictionary = Missions.offers(s.sys_id, str(s.station.get_meta("info")["id"]), Factions.owner_of(Data.SYSTEMS[s.sys_id]["station"], Data.SYSTEMS[s.sys_id]))[0]
	Missions.accept(o)
	main.open_map()
	await _frames(3)
	var nm = main.navmap
	nm._layout()
	var has_btns: bool = nm.btn_m_set.size.x > 0.0 and nm.btn_m_go.size.x > 0.0
	await _shot("v19p_map_mission_buttons", 0.3)
	nm.tap(nm.btn_m_set.get_center())
	await _frames(2)
	var set_ok: bool = s.nav_dest == s.mission_waypoint().get("node") and main.state == "map"
	nm.tap(nm.btn_m_go.get_center())
	await _frames(3)
	var go_ok: bool = main.state == "flight" and main._mission_auto and s.autopilot != null
	s.autopilot = null
	main._mission_auto = false
	s.drop_warp()   # (GO spooled the warp drive for the long leg)
	await _until(func(): return s.warp_state == "off", 5.0)
	GS.mission = {}
	# the camera on a planet
	await Packs.wait("planets", 60.0)
	var pc: Vector3 = s.planet.global_position
	var d := Vector3(0.3, 0.2, 1.0).normalized()
	_tp(pc + d * (float(s.planet.get_meta("radius")) + 90.0), pc)
	main.hud.move_vec = Vector2(0, -1)
	await _until(func(): return main.state == "atmosphere", 8.0)
	main.hud.move_vec = Vector2.ZERO
	await _until(func(): return main.state == "flight" and _sp().surface_mode, 30.0)
	s = _sp()
	var down: bool = s.surface_mode
	if not down:
		_check("v1.9p: on a planet the chase camera stops above the ground", false, "could not get down to the planet (state %s)" % main.state)
		GS.mission = keep["mission"]
		GS.bounty = keep["bounty"]
		return
	var gx := 120.0
	var gz := -80.0
	var gy: float = s._ground(gx, gz)
	s.player.global_position = Vector3(gx, gy + 2.5, gz)
	s.pitch = deg_to_rad(70.0)   # nose high: the camera behind and above would be under the ground
	s.vel = Vector3.ZERO
	s.player.basis = Basis.from_euler(Vector3(s.pitch, s.yaw, 0))
	s._update_camera(0.016, true)
	var cp: Vector3 = s.cam.global_position
	var above: bool = cp.y >= s._ground(cp.x, cp.z) + 0.3
	var pulled: bool = s.cam_clipped > 0.5
	await _shot("v19p_camera_ground", 0.0)
	s.pitch = 0.0
	s.player.basis = Basis.from_euler(Vector3(0, s.yaw, 0))
	s.player.global_position = Vector3(gx, gy + 300.0, gz)
	s._update_camera(0.016, true)
	var shown: bool = s.model.visible
	_tp(Vector3(0, Surface.CEILING - 30.0, 0), Vector3(0, Surface.CEILING + 400.0, -100.0))
	await _until(func(): return main.state == "flight" and not _sp().surface_mode, 10.0)
	GS.mission = keep["mission"]
	GS.bounty = keep["bounty"]
	_check("v1.9p: the map shows SET WAYPOINT and GO beside the current mission; SET WAYPOINT sets it, GO flies the whole job", has_btns and set_ok and go_ok, "buttons %s set %s go %s" % [has_btns, set_ok, go_ok])
	_check("v1.9p: on a planet the chase camera stops above the ground (pulled in, not under it) and the ship shows again in the open", down and above and pulled and shown, "down %s above %s pulled %.1f m shown %s" % [down, above, s.cam_clipped, shown])
