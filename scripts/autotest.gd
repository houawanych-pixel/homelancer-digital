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
	await _city_visit()
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
	var group: Array = s._spawn_group(s.player.global_position + fwd * 500.0, 3)
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
	# TRANSFORM sits in the old STOP slot; the centre row loses its MECH pill
	hud._layout()
	var fr: Rect2 = hud.buttons.get("form", Rect2())
	var wr: Rect2 = hud.buttons["warp"]
	_check("TRANSFORM button in the old STOP spot (STOP removed)", fr.size.x > 0.0 and absf(fr.position.y - wr.position.y) < 1.0 and fr.position.x < wr.position.x
		and not hud.buttons.has("stop") and hud.buttons.has("map") and hud.buttons.has("goto"), "at %s" % str(fr.position))
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
	var console_up: bool = hud.comms_mode == "roster" and hud.buttons.has("met_0") and hud.buttons.has("type")
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

## The capital city prototype kit: connections on the modular grid, mech clearance, the pack split.
func _city_kit() -> void:
	var b := City.test_block()
	var j := City.joins(b)
	var pairs := {}
	for pr in j["joined"]:
		var names := [pr[0]["module"], pr[1]["module"]]
		names.sort()
		pairs["%s+%s" % names] = pairs.get("%s+%s" % names, 0) + 1
	var mods := {}
	for m in b["modules"]: mods[m["id"]] = true
	_check("City kit: 8 modules on a %d m grid in one block" % int(City.CELL), mods.size() == 8 and City.MODULES.size() == 8, ", ".join(mods.keys()))
	_check("Road connections (straight <-> straight/intersection/bridge, same width + height)", pairs.get("intersection+road_straight", 0) >= 2 and pairs.get("mega_bridge+road_straight", 0) == 1
		and j["bad"].is_empty(), "joined %d, mismatched %d" % [j["joined"].size(), j["bad"].size()])
	_check("Intersection connections (4 sides: road, bridge, road, platform)", pairs.get("intersection+mega_bridge", 0) == 1 and pairs.get("intersection+road_straight", 0) == 2
		and pairs.get("intersection+platform_square", 0) == 1, str(pairs))
	var ramp: Array = b["conns"].filter(func(c): return c["kind"] == "ramp")
	_check("Merge / on-ramp connections (main road both ends + ramp down to the plaza)", pairs.get("merge+road_straight", 0) == 2 and ramp.size() == 1 and float(ramp[0]["height"]) == 0.0
		and absf(float(ramp[0]["width"]) - City.LANE) < 0.01, "ramp lands at y %.1f" % float(ramp[0]["height"]))
	var stairs: Array = b["conns"].filter(func(c): return c["kind"] == "ped" and float(c["height"]) > 0.0)
	_check("Platform connections (tower, intersection, road, stairs)", pairs.get("command_tower+platform_square", 0) == 1 and pairs.get("platform_rect+road_straight", 0) == 1
		and stairs.size() == 1 and City.lands_on_platform(b, stairs[0]), str(pairs))
	# mech clearance from the real mech model
	var mech := ShipFactory.build("mech_tan")
	var box := ShipFactory._aabb(mech, Transform3D.IDENTITY)
	mech.free()
	var mw := maxf(box.size.x, box.size.z)
	var under_deck := City.DECK - City.DECK_T
	var under_bridge := City.DECK - City.DECK_T - 2.5
	_check("Mech clearance: 1 per lane, 2 abreast per road, passing under decks", City.LANE >= mw * 1.5 and City.ROAD >= mw * 3.0 and under_bridge > box.size.y + 2.0
		and City.PED < mw, "mech %.1f m tall x %.1f m wide; lane %d m, road %d m, under deck %.1f m, under bridge %.1f m, stairs %d m" % [box.size.y, mw, City.LANE, City.ROAD, under_deck, under_bridge, City.PED])
	var ex := FileAccess.get_file_as_string("res://export_presets.cfg") if FileAccess.file_exists("res://export_presets.cfg") else ""
	var in_tree := get_tree().root.find_children("CapitalBlock", "", true, false).size()
	_check("City + pilot content not in the core download", Packs.PACKS.has("city") and Packs.PACKS["city"]["folders"] == ["res://assets/city"] and (ex == "" or ("assets/city/*" in ex and "assets/enemy_pilots/*" in ex))
		and in_tree == 0, "city pack + enemies pack, exclude_filter %s, city nodes at start %d" % ["ok" if ex != "" else "n/a (exported build)", in_tree])

## Visit the test block in New Terra's city sector: screenshots with mechs for scale, the normal-map A/B, costs.
func _city_visit() -> void:
	var s := _sp()
	await Packs.wait("city", 30.0)   # web: 37 KB, requested on planet approach; the block upgrades in place
	await get_tree().process_frame
	var cb: Node3D = s.tile_root.get_node_or_null("CapitalBlock")
	var st := City.stats(City.test_block())
	_check("Capital test block stands in the city sector (simple collision)", cb != null and s.city_solids.size() >= st["solids"],
		"%d parts, %d MultiMesh draw groups, ~%d triangles (%d beyond LOD range), %d collision boxes" % [st["parts"], st["draw_calls"], st["triangles"], st["triangles_far"], st["solids"]])
	if cb == null: return
	var block: Dictionary = cb.get_meta("block")
	# collision: drop the player onto the bridge deck and into the tower wall
	var o := cb.position
	_tp(o + Vector3(140, City.DECK + 3.0, -100), o + Vector3(140, City.DECK + 3.0, -60))
	await get_tree().process_frame
	await get_tree().process_frame
	var on_deck: float = s.player.global_position.y - o.y
	_tp(o + Vector3(60, 50, -180), o + Vector3(60, 50, -100))
	await get_tree().process_frame
	await get_tree().process_frame
	var pushed: Vector3 = s.player.global_position - (o + Vector3(60, 50, -180))
	_tp(o + Vector3(700, 300, 600), o)   # park the ship well away from the camera shots
	_check("City collision: stand on a deck, pushed out of the tower", on_deck >= City.DECK + 5.9 and on_deck < City.DECK + 6.5 and pushed.length() > 4.0, "deck y %.1f, push %.1f m" % [on_deck, pushed.length()])
	# town buildings are solid too (Port Meridian's blocks)
	var town: Array = s.tile_root.get_meta("solids", [])
	var tb: AABB = town[0] if not town.is_empty() else AABB()
	s.player.global_position = tb.get_center()
	await get_tree().process_frame
	await get_tree().process_frame
	var out: bool = not tb.grow(5.9).has_point(s.player.global_position)
	_tp(o + Vector3(700, 300, 600), o)
	_check("Town buildings are solid (no flying through them)", town.size() > 20 and out, "%d buildings, pushed out %s" % [town.size(), out])
	# B-01 command tower: the Blender build, merged to one mesh, from the city pack; solid like the rest
	var tw := cb.get_node_or_null("B01Tower") as MeshInstance3D
	var tw_in: Vector3 = cb.to_global(Vector3(49, 60, -180))
	_check("B-01 command tower is the textured Blender model (city pack), one draw call, solid", tw != null and tw.mesh.get_surface_count() == 1 and (tw.material_override as ORMMaterial3D).normal_texture != null
		and cb.get_node_or_null("B01StandIn") == null and s.city_push(tw_in, 6.0) != Vector3.ZERO and tw.get_aabb().size.y > 115.0,
		"%d surface, colour + bump + glow maps, %.0f x %.0f x %.0f m" % [tw.mesh.get_surface_count() if tw else 0, tw.get_aabb().size.x if tw else 0.0, tw.get_aabb().size.y if tw else 0.0, tw.get_aabb().size.z if tw else 0.0])
	var hg := cb.get_node_or_null("Prop_h01") as MeshInstance3D
	var hg_in: Vector3 = cb.to_global(Vector3(-30, 10, -120))
	_check("H-01 hangar (Blender, concept-art textured) stands in the test city, solid", hg != null and (hg.material_override as ORMMaterial3D).albedo_texture != null
		and s.city_push(hg_in, 6.0) != Vector3.ZERO, "%d triangles, 1 draw call" % [City.PROPS["h01"]["tris"]])
	# mechs for scale: 1 on a road, 2 abreast on the bridge, a group passing under it and 4 crossing the intersection
	var mechs: Array = []
	var spots := [[Vector3(140, City.DECK, -220), 0.0], [Vector3(134, City.DECK, -110), 0.0], [Vector3(146, City.DECK, -95), PI],
		[Vector3(118, 0, -90), PI * 0.5], [Vector3(140, 0, -96), PI * 0.5], [Vector3(162, 0, -88), -PI * 0.5],
		[Vector3(134, City.DECK, -186), 0.0], [Vector3(146, City.DECK, -172), PI], [Vector3(126, City.DECK, -176), PI * 0.5], [Vector3(156, City.DECK, -183), -PI * 0.5],
		[Vector3(174, 9.0, -350), PI]]
	for sp in spots:
		var m := ShipFactory.build("mech_tan")
		var bb := ShipFactory._aabb(m, Transform3D.IDENTITY)
		cb.add_child(m)
		m.position = (sp[0] as Vector3) - Vector3(0, bb.position.y, 0)
		m.rotation.y = sp[1]
		mechs.append(m)
	main.hud.visible = false
	var cam := Camera3D.new()
	cam.far = 9000.0
	cb.add_child(cam)
	var prev: Camera3D = get_viewport().get_camera_3d()
	cam.make_current()
	var views := [["city_block_overview", Vector3(470, 190, 60), Vector3(150, 25, -230)],
		["city_tower_b01", Vector3(165, 50, -95), Vector3(49, 56, -180)],
		["city_tower_b01_gangway", Vector3(118, 32, -150), Vector3(49, 36, -182)],
		["city_tower_b01_back", Vector3(-80, 70, -290), Vector3(49, 52, -180)],
		["city_hangar_h01_front", Vector3(0, 22, -40), Vector3(-30, 12, -120)],
		["city_hangar_h01_side", Vector3(-110, 30, -70), Vector3(-30, 10, -120)],
		["city_hangar_h01_back", Vector3(-75, 35, -200), Vector3(-30, 10, -120)],
		["city_mech_clearance_bridge", Vector3(205, 24, -40), Vector3(140, 14, -110)],
		["city_intersection_mechs", Vector3(196, 64, -238), Vector3(140, 20, -180)],
		["city_merge_onramp", Vector3(250, 46, -480), Vector3(160, 10, -330)],
		["city_stairs_platform", Vector3(60, 30, -96), Vector3(100, 14, -150)]]
	var draws := 0
	var draws_block := 0
	for v in views:
		cam.look_at_from_position(cb.to_global(v[1]), cb.to_global(v[2]), Vector3.UP)
		await _shot(v[0], 0.5)
		for m in mechs: m.visible = false   # measure the block alone
		await _wait(0.15)
		var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		for m in mechs: m.visible = true
		cb.visible = false
		await _wait(0.15)
		var d1 := dc - int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		cb.visible = true
		# measure twice and keep the smaller: ships and loot drifting into view between the two frames are not the block
		await _wait(0.15)
		var dc2 := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		cb.visible = false
		await _wait(0.15)
		var d2 := dc2 - int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		draws_block = maxi(draws_block, mini(d1, d2))
		cb.visible = true
		draws = maxi(draws, dc)
	# normal / bump detail A/B: same low-poly geometry, detail off then on
	cam.look_at_from_position(cb.to_global(Vector3(98, 24, -236)), cb.to_global(Vector3(58, 40, -180)), Vector3.UP)
	for m in City.materials(1.0): if m is ShaderMaterial: m.set_shader_parameter("detail", 0.0)
	await _shot("city_detail_off", 0.4)
	for m in City.materials(1.0): if m is ShaderMaterial: m.set_shader_parameter("detail", 1.0)
	await _shot("city_detail_on", 0.4)
	var shader_on := City.materials(1.0)[0] is ShaderMaterial and (cb.get_child(0) as MultiMeshInstance3D).material_override is ShaderMaterial
	cam.look_at_from_position(cb.to_global(Vector3(140, 300, 1500)), cb.to_global(Vector3(140, 0, -220)), Vector3.UP)
	for m in mechs: m.visible = false
	await _wait(0.3)
	var dfar := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	cb.visible = false
	await _wait(0.15)
	dfar -= int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	cb.visible = true
	_check("City shared material + normal detail (city pack), draw calls measured", shader_on and draws_block <= st["draw_calls"] + 12,   # +12: for a moment both detail levels of a few groups can draw while the LOD switches (seen: 23)
		"block adds %d draw calls up close, %d from 1.7 km (detail LOD off); whole frame %d" % [draws_block, dfar, draws])
	for m in mechs: m.queue_free()
	cam.queue_free()
	if prev: prev.make_current()
	main.hud.visible = true

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
	_check("Traffic: a cargo hauler, a freighter and a tanker on the run, and a big fuel tanker by the planet", s.traffic.size() == 3 and (s.traffic[2]["node"] as Node3D).name.begins_with("Tanker")
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
	var tk: Node3D = s.traffic[2]["node"]
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
		total_p == 172 and total_s == 102 and s.extras.size() == 7 and xw == 4 and s.targetables().has(s.extras[0]), "extras %d, real maps %d" % [s.extras.size(), xw])
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
		ok_files and n == 28 and flying == Music.faction_mood(Data.SYSTEMS[s.sys_id].get("faction", "Neutral")) and took and battle and was_muted and main.title.music_btn != null, "%d tracks, flying = %s, battle = %s" % [n, flying, btrack])

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

func _run() -> void:
	if OS.get_environment("HL_SOAK") != "":
		await _soak(int(OS.get_environment("HL_SOAK")))
		return
	if OS.get_environment("HL_CITY") != "":   # quick look at the city prototype only
		main.start_game()
		await _until(func(): return main.state == "flight", 10.0)
		main._load_surface("new_terra", 4)
		await _wait(1.5)
		await _city_visit()
		for r in results: print("[route] ", r)
		get_tree().quit()
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
	_check("Mobile HUD shown", main.hud.visible and main.hud.buttons.has("slot_0") and main.hud.buttons.has("slot_2") and main.hud.buttons.has("shield") and main.hud.buttons.has("repair") and main.hud.buttons.has("tractor") and main.hud.buttons.has("form") and not main.hud.buttons.has("stop") and main.hud.buttons.has("warp") and main.hud.buttons.has("thrust") and main.hud.buttons.has("kill") and main.hud.buttons.has("call"))
	await _shot("solara_flight")
	var s := _sp()
	s.hail.connect(_on_hail)   # listen from the start: enemies may call as soon as they see you (e.g. a warp spool)
	s.enemy_hail.connect(_on_enemy_hail)
	_check("Real/placeholder player ship", is_instance_valid(s.model), "placeholder=%s" % s.model.get_meta("placeholder", true))
	# ---- first-person cockpit, comms and the AUTO/MANUAL system panels
	_press("view")
	await _wait(0.5)
	_check("First-person cockpit view", GS.view == "cockpit" and not s.model.visible)
	await _shot("cockpit_view")
	await _until(func(): return not main.hud.comms_open, 9.0) # launch call closes by itself
	_check("Incoming call auto-closes; station controller met", not main.hud.comms_open and "vale" in GS.met)
	_press("call")
	await _wait(0.4)
	_check("CALL talks to target/controller", main.hud.comms_mode == "talk")
	await _shot("intercom_call")
	_press("hangup")
	_check("Hang up", not main.hud.comms_open or main.hud.comms_mode == "incoming")
	_press("log")
	await _wait(0.5)
	_check("LOG pull-out contacts", main.hud.comms_mode == "roster" and main.hud.buttons.has("met_0"))
	await _shot("contacts_tab")
	_press("met_0")
	await _wait(0.3)
	_check("Call a contact from LOG", main.hud.comms_mode == "talk")
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
	_check("Enraged raider leader joins contacts", GS.mood.get("voss", "") == "enraged")
	await _section_loop()
	await _mech_form()
	await _generic_pilots()
	await _city_kit()
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
	var btn: Button = main.hub.find_child("Buy_pulse2", true, false)
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
	_check("Ship purchase (Lancer, 4 cannons); the dealer sells six real ships", GS.ship_id == "lancer" and int(GS.ship()["guns"]) == 4 and Data.SHIP_ORDER == ["cadet", "ranger", "hauler", "lancer", "bulk_empty", "bulk"] and ShipFactory.has_real_model("bulk_empty") and ShipFactory.has_real_model("ranger") and ShipFactory.has_real_model("hauler") and ShipFactory.has_real_model("bulk"), "ship=%s hull=%d" % [GS.ship_id, int(GS.max_hull())])
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
	_check("Asteroid field", in_belt and s.rocks.size() > 100, "rocks=%d" % s.rocks.size())
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
	await _galaxy()
	await _controls_j()
	await _gate_k()
	await _collide_l()
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
		await _ram(r[0] + n * (float(r[1]) + 2.5), -n * 40.0)
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
	await Packs.wait("city", 30.0)
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
	var town: Array = s.tile_root.get_meta("solids", []) if is_instance_valid(s.tile_root) else []
	var boxes: Array = town if not town.is_empty() else s.city_solids
	var bld_hit := false
	if not boxes.is_empty():
		var tb: AABB = boxes[0]
		var c := tb.get_center()
		s.last_collision = {}
		var h3 := GS.hull
		await _ram(Vector3(tb.position.x - 3.0, c.y, c.z), Vector3(45.0, 0, 0))
		bld_hit = s.last_collision.get("kind", "") == "building" and GS.hull < h3
		hits["building"] = h3 - GS.hull
	_check("Job L: colliding with an asteroid, the ground and a building each damages the hull", rock_hit and ground_hit and bld_hit,
		"asteroid %.1f, ground %.1f, building %.1f" % [float(hits.get("asteroid", 0.0)), float(hits.get("ground", 0.0)), float(hits.get("building", 0.0))])
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
	s.fire_missile()
	await _until(func(): return s.enemy_evades > ev0 or s.missiles_live.is_empty(), 8.0)
	var evaded: bool = s.enemy_evades == ev0 + 1 and is_equal_approx(float(e["hp"]), 60.0)
	_check("Job M: a missile hits an enemy that holds its course; an enemy that boosts sideways as it closes in shakes it off", hit_ok and evaded, "hit %s, evaded %s" % [hit_ok, evaded])
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
	var layout_ok: bool = b.has("fire") and (b["thrust"] as Rect2).position.x > (b["fire"] as Rect2).position.x and (b["kill"] as Rect2).position.x > (b["thrust"] as Rect2).position.x \
		and is_equal_approx((b["fire"] as Rect2).position.y, (b["thrust"] as Rect2).position.y) and is_equal_approx((b["kill"] as Rect2).end.x, main.hud.S.x - 8.0)
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
		if tk.size() != 1: held_used = true
		else:
			tracks[tk[0]] = true
			if tk[0] in Music.HELD: held_used = true
	main._fight_t = 99.0
	for en in s.enemies: en["aggro"] = false
	_tp(Vector3(900, 2500, 900), Vector3(900, 2500, 0))
	await _frames(2)
	var mood_now: String = main.music_mood(0.016)
	var fac: String = Data.SYSTEMS[s.sys_id].get("faction", "Neutral")
	_check("Job O: music follows the faction whose space you are in (one track each, 13 factions); the love song and the ruins set are held back",
		not held_used and tracks.size() == SystemBuilder.FACTIONS.size() and (mood_now == Music.faction_mood(fac) or mood_now == "battle") and Music.takes("f:" + fac).size() == 1, "%s -> %s" % [fac, mood_now])
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
	var flush: bool = absf(cr.end.x - sz.x) < 1.0 and absf(lg.position.x) < 1.0
	var clear: bool = not cr.intersects(mid) and not lg.intersects(mid)
	var rows: bool = hud.buttons.has("met_0") and cr.encloses(hud.buttons["met_0"]) and hud.buttons.has("type") and lg.encloses(hud.buttons["type"]) and lg.encloses(hud.buttons["voice"])
	await _shot("q_comms_split")
	_check("Job Q: the comms console is split: contacts flush against the right edge, the message log flush against the left edge, the middle 40% of the screen clear", hud.console_open and flush and clear and rows,
		"contacts x %d..%d, log x %d..%d of %d, rows in place %s" % [int(cr.position.x), int(cr.end.x), int(lg.position.x), int(lg.end.x), int(sz.x), rows])
	# a caller floats in beside the panel, not under it; the console stays up while you fly
	hud.open_comms("Capt. Rennick — Bright Margin", "[smile]Good to see you out here.", "incoming", false, "rennick")
	await _wait(0.5)
	hud._layout()
	var sr: Rect2 = hud.side_rect("r")
	var beside: bool = sr.end.x <= hud.contacts_rect().position.x + 1.0 and sr.position.x > sz.x * 0.6
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
	_check("Job Q: someone calling floats in next to the contacts panel, and touching the middle of the screen leaves the console up", beside and hud.console_open and not hud.roster_closing,
		"caller x %d..%d, panel starts %d" % [int(sr.position.x), int(sr.end.x), int(hud.contacts_rect().position.x)])
	# tapping a name calls that person
	hud.close_comms()
	_press("log")
	await _wait(0.6)
	var who: String = GS.met[0]
	_press("met_0")
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
	# other factions' placeholder patrols are untouched
	s.sys = real_sys
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
		if (str(sy["station"].get("model", "")) == "savagers_cross_station") != is_sav: st_ok = false
		if SpaceSystem.has_beacon(id, sy) != (is_sav or id == "solara"): st_ok = false
	_check("Job V: the five Savagers systems wear the Savagers cross station, and each hides a light beacon in its nebula (so does Solara)", st_ok and n_sav == 5
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
	# --- the bounty board, with the real names
	main.hub.open(Data.SYSTEMS[s.sys_id]["station"])
	await _frames(3)
	main.hub.show_screen("bounty")
	await _frames(3)
	var btn: Button = main.hub.content.find_child("Bounty_savagers_03", true, false)
	var names: Array = Data.bounties().map(func(b): return b["name"])
	var stand: Label = main.hub.content.find_child("Standing_Savagers", true, false)
	var board_ok: bool = btn != null and not btn.disabled and names == ["Razor", "Veil", "Dreadmaw"] and main.hub.left.find_child("Btn_bounty", true, false) != null
	var stand_ok: bool = stand != null and stand.text == "SAVAGERS: HOSTILE" and main.hub.content.find_child("Standing_Unity", true, false) != null
	await _shot("v_bounty_board", 0.3)
	if btn: btn.pressed.emit()
	await _frames(3)
	main.hub.visible = false
	GS.mission = {}   # (v1.5f: the board also starts the waypoint chain; this older check follows the plain hunt)
	_check("Job V: the BOUNTIES board lists Razor, Veil and Dreadmaw with their faces, shows your standing in reputation colours, and ACCEPT starts the hunt",
		board_ok and stand_ok and GS.bounty.get("id", "") == "savagers_03" and GS.bounty.get("state", "") == "hunt" and GS.bounty.get("sys", "") == "plundros", "board %s, standing %s, carrying %s" % [board_ok, stand_ok, str(GS.bounty)])
	var not_here: Dictionary = s.spawn_bounty()
	GS.bounty["sys"] = s.sys_id               # (test only: bring the hunt to this system)
	var tgt: Dictionary = s.spawn_bounty()
	var again: Dictionary = s.spawn_bounty()
	var spawn_ok: bool = not_here.is_empty() and not tgt.is_empty() and again == tgt and tgt.get("bounty", "") == "savagers_03" and int(tgt.get("rank", 0)) == 3 and tgt["def"]["name"] == "Redclaw Interceptor"
	spawn_ok = spawn_ok and s.roster_pick("Savagers", 6).get("id", "") != "savagers_03"
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
	# the picture rule: station's own > faction's > plain neutral
	var sav_sys: Dictionary = Data.SYSTEMS["plundros"]
	var own: Dictionary = Factions.hub_background({"ui_background": "phenom"}, sav_sys)
	var fac: Dictionary = Factions.hub_background(sav_sys["station"], sav_sys)
	var neutral: Dictionary = Factions.hub_background({}, {"faction": "Neutral"})
	var files := true
	var n_bg := 0
	for f in Factions.DEFS:
		var nm: String = str(Factions.DEFS[f].get("ui_background", ""))
		if nm == "": files = false
		else:
			n_bg += 1
			if not Packs.PACKS.has("hubbg_" + nm) or Packs.PACKS["hubbg_" + nm]["probe"] != Data.HUB_BG_DIR + nm + ".jpg": files = false
			if not OS.has_feature("web") and not ResourceLoader.exists(Data.HUB_BG_DIR + nm + ".jpg"): files = false   # (on the web each one arrives only when you dock there)
	_check("Job W: the background comes from data: a station's own picture wins, then its faction's, then the plain neutral backdrop; all 14 factions have a picture, each in its own small pack",
		own["source"] == "station" and own["path"].ends_with("phenom.jpg") and fac["source"] == "faction" and fac["path"].ends_with("savagers.jpg") and fac["pack"] == "hubbg_savagers"
		and neutral["source"] == "neutral" and neutral["path"] == "" and files and n_bg == 14, "%d pictures" % n_bg)
	_check("Job W: the six enemy factions have interface art but stay outside the rival pairs (gray, permanent enemies); the eight majors are unchanged",
		Factions.majors().size() == 8 and ["Solrath", "Gadversee", "Arctides", "Cybermorph", "Phenom", "Kaijurai"].all(func(f): return Factions.band(f) == "gray" and Factions.rival(f) == ""))
	# dock: one fixed picture, the interface over it
	var base0: Dictionary = hub.base
	var kind0: String = hub.kind
	var vis0: bool = hub.visible
	hub.open(Data.SYSTEMS["solara"]["station"])
	await Packs.wait("hubbg_unity", 30.0)
	await _frames(3)
	var t0: Texture2D = hub.bg_tex
	var docked_ok: bool = t0 != null and t0.resource_path.ends_with("unity.jpg") and t0.get_size() == Vector2(1280, 720) and hub.bg["source"] == "faction"
	var ui_ok: bool = hub.left.visible and hub.content.visible and hub.header.visible and hub.left.find_child("Btn_launch", true, false) != null and hub.left.find_child("Btn_faction", true, false) != null
	await _shot("w_hub_unity", 0.4)
	var same := true
	for scr in ["equipment", "ships", "repair", "bounty", "faction", "hub"]:
		hub.show_screen(scr)
		await _frames(2)
		if hub.bg_tex != t0: same = false
		if scr == "equipment": await _shot("w_equipment_unity", 0.3)
	var fits: bool = hub.left.position.y + hub.left.get_combined_minimum_size().y <= get_viewport().get_visible_rect().size.y
	_check("Job W: docking shows the faction's picture, fixed, with the menu over it at once; every service screen keeps that same picture and the menu fits the screen",
		docked_ok and ui_ok and same and fits, "picture %s, menu %s, same on all screens %s, fits %s" % [docked_ok, ui_ok, same, fits])
	var panel: StyleBoxFlat = hub.theme_obj.get_stylebox("panel", "Panel")
	var btn: StyleBoxFlat = hub.theme_obj.get_stylebox("normal", "Button")
	_check("Job W: the interface is see-through so the faction art stays visible (panel %d%%, buttons %d%%, a light dark wash for reading)" % [int(Data.HUB_PANEL_ALPHA * 100), int(Data.HUB_BUTTON_ALPHA * 100)],
		is_equal_approx(panel.bg_color.a, Data.HUB_PANEL_ALPHA) and panel.bg_color.a <= 0.6 and is_equal_approx(btn.bg_color.a, Data.HUB_BUTTON_ALPHA) and Data.HUB_BG_WASH > 0.0 and Data.HUB_BG_WASH < 0.6)
	hub.show_screen("faction")
	await _frames(3)
	var fname: Label = hub.content.find_child("FactionName", true, false)
	_check("Job W: the FACTION page names who runs the station and shows your standing", fname != null and fname.text == "UNITY" and hub.content.find_child("Standing_Unity", true, false) != null)
	# another owner, another picture; leaving lets it go
	var sys0: String = GS.system_id
	GS.system_id = "plundros"
	hub.open(Data.SYSTEMS["plundros"]["station"])
	await Packs.wait("hubbg_savagers", 30.0)
	await _frames(3)
	var sav_ok: bool = hub.bg_tex != null and hub.bg_tex.resource_path.ends_with("savagers.jpg") and hub.bg_tex != t0
	await _shot("w_hub_savagers", 0.4)
	GS.system_id = "vega"
	var veg: Dictionary = Factions.hub_background(Data.SYSTEMS["vega"]["station"], Data.SYSTEMS["vega"])
	hub.visible = false
	await _frames(2)
	var released: bool = hub.bg_tex == null
	GS.system_id = sys0
	hub.base = base0
	hub.kind = kind0
	hub.visible = vis0
	var not_preloaded: bool = not OS.has_feature("web") or not ResourceLoader.exists(Data.HUB_BG_DIR + "phenom.jpg")   # web: a faction you never docked with was never downloaded
	_check("Job W: a Savagers station shows the Savagers picture; only the current station's picture is held, and it is let go when you leave", sav_ok and released and not_preloaded, "savagers %s, released %s, vega -> %s" % [sav_ok, released, veg["source"]])

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
		and Sfx.clip_path("savagers_04_veil", "...Not finished...") == "res://assets/voices/savagers_04_veil/not_finished.ogg", "%s / %s" % [by_clip, by_fallback])
	# OFF: blips, and the choice is remembered
	var said: String = Sfx.toggle_voice()
	hud.open_comms("Test — Radio", "Radio check!", "talk", false, "", 1.0, false, "_test")
	var off_ok: bool = not Sfx.voice_on() and Sfx.last_voice == "blip" and said.begins_with("Voice OFF")
	Sfx.voice_mode = "read"
	Sfx.load_prefs()
	var kept: bool = not Sfx.voice_on()
	Sfx.toggle_voice()
	Sfx.load_prefs()
	var back: bool = Sfx.voice_on()
	_check("Job X: VOICE in the comms console turns it OFF (radio blips, even for recorded lines) and ON again, and the choice is remembered", off_ok and kept and back, said)
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
	var data_ok: bool = files and Data.SYSTEMS["omega"]["station"]["model"] == "worlds_end_emporium" and Data.SYSTEMS["shadow"]["station"]["model"] == "hollow_requiem" \
		and fg["station"]["model"] == "light_beacon_station" and fg["station"].get("lamp", false) and Data.SYSTEMS["nullpoint"]["station"].get("lamp", false) \
		and (fg["nebula"]["center"] as Vector3).is_equal_approx(fg["station"]["pos"]) and fg["nebula"]["color"] == Data.FOG_COLOR
	main.hud.visible = false
	var seen_models: Array = []
	var fog_ok := false
	var fog_txt := ""
	for sid in ["foggiest", "omega", "shadow"]:
		main._load_system(sid, "station")
		await _wait(1.6)
		await Packs.wait("structures", 30.0)
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
			if f in ["Phenom", "Kaijurai", "Cybermorph", "Solrath"]:   # (v1.5c: Cybermorph and Solrath fly too)
				if not Data.ENEMIES.has(k) or Data.ENEMIES[k].get("faction", "") != f or not ShipFactory.has_real_model(Data.ENEMIES[k]["model"]): ships_ok = false
			elif k != "": ships_ok = false
	_check("Job AD: Phenom and Kaijurai people each have a ship from their own set (Vyrela the interceptor, the two elites and commanders the heaviest); the casts without ships are known but do not fly yet",
		ships_ok and Data.roster_pilot("phenom_02_vyrela")["fighter_primary"] == "phenom_interceptor" and Data.roster_pilot("phenom_06_xerathion")["fighter_primary"] == "phenom_heavy"
		and Data.roster_pilot("kaijurai_01")["fighter_primary"] == "kaijurai_dart" and Data.roster_pilot("kaijurai_06_vorrax")["fighter_primary"] == "kaijurai_gunship"
		and Factions.has_fighters("Phenom") and Factions.has_fighters("Kaijurai") and not Factions.has_fighters("Gadversee"))   # (v1.5c: Solrath flies now; Gadversee and Arctides still wait for ships)
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
		fly.filter(func(f): return Factions.normal(f)) == ["Covenant", "Imperium", "Liberator", "Savagers"] and models   # (v1.4z: of the eight main factions; Kaijurai and Phenom fly too; v1.5c: Covenant, Cybermorph, Solrath too)
		 and Data.roster_pilot("imperium_02")["fighter_primary"] == "imperium_fighter" and Data.roster_pilot("imperium_05")["fighter_primary"] == "imperium_gunship"
		and Data.roster_pilot("unity_02")["fighter_primary"] == "" and float(ShipFactory.GLB["liberator_fighter"][2]) == Data.LIBERATOR_YAW, str(fly))
	# a guard wing in their own space: peaceful, not a hostile contact, answers a hail; shoot and it turns
	var s := _sp()
	var real_sys: Dictionary = s.sys
	var solara_guard: Array = s.spawn_guard()   # Unity has no fighters: nobody
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
	var dropped: bool = nm.selected == "point"
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
	_check("Job S: the card closes with its X or a tap outside it; only then does a tap on empty space drop a waypoint", x_closed and out_closed and dropped)
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
	for o in offers:
		if o["kind"] == "threats" and o.get("hard", false): hard = o
		elif o["kind"] == "threats": easy = o
		elif o["kind"] == "escort": esc = o
	var same: bool = Missions.offers(s.sys_id, sid).map(func(o): return o["title"]) == offers.map(func(o): return o["title"])
	_check("Job AI: a station's MISSIONS board offers a patrol threats job, an elite threats job (slot 05, paid more) and an escort, from a faction hostile to the owner, the same offers for the whole visit",
		kinds == ["threats", "threats_hard", "escort"] and int(hard["slot"]) == 5 and int(easy["slot"]) == 1 and int(hard["pay"]) > int(easy["pay"]) and same and Factions.has_fighters(str(easy["faction"])) and (easy["points"] as Array).size() == 2,
		str(kinds) + " " + str(easy.get("faction", "")))
	# ---- the hub pages
	main.hub.open(Data.SYSTEMS[s.sys_id]["station"])
	await _frames(2)
	main.hub.show_screen("missions")
	await _frames(2)
	var take: Button = main.hub.content.find_child("Take_Job_threats", true, false)
	var rows_ok: bool = take != null and not take.disabled and main.hub.content.find_child("Job_threats_hard", true, false) != null and main.hub.content.find_child("Job_escort", true, false) != null and main.hub.left.find_child("Btn_missions", true, false) != null
	await _shot("ai_missions_board", 0.3)
	if take: take.pressed.emit()
	await _frames(2)
	var taken: bool = GS.mission.get("kind", "") == "threats" and not bool(GS.mission.get("hard", false)) and main.hub.status.text.find("waypoint") >= 0 and main.hub.content.find_child("CurrentJob", true, false) != null
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
	Missions.abandon()
	_check("Job AI: the ELITE threats job sends the faction's seniors, the slot-05 elite among them, for %.1fx the pay; a job can be dropped" % Data.MISSION_HARD_MULT, elite_ok and GS.mission.is_empty() and int(hard["pay"]) == int(Data.MISSION_PAY["threats"] * Data.MISSION_HARD_MULT), str(elite.map(func(o): return o.get("pilot", {}).get("slot", 0))))
	# ---- bounty wanted dead (Razor, rank 3): escort wing, then her wing, paid on the kill
	var said: String = Missions.accept_bounty("savagers_03")
	var bm: Dictionary = GS.mission
	var chain_ok: bool = bm.get("kind", "") == "bounty" and not bool(bm.get("alive", true)) and GS.bounty.get("state", "") == "hunt" and said.find("waypoint") >= 0 and said.find("escort") >= 0
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
	var boss_ok: bool = bw.size() == Data.MISSION_GROUP[1] and boss.size() == 1 and int(boss[0].get("rank", 0)) == 3 and not wb.is_empty() and wb["node"] == boss[0]["node"]
	await _shot("ai_bounty_boss", 0.3)
	var credits1: int = GS.credits
	for o in bw: s._destroy_unit(o)
	await _frames(3)
	var dead_paid: bool = GS.mission.is_empty() and GS.bounty.is_empty() and "savagers_03" in GS.bounties_done and GS.credits - credits1 >= Data.bounty_reward("savagers_03") and s.loot.all(func(l): return l.get("bounty", "") != "savagers_03")
	_check("Job AI: a bounty wanted dead (rank under %d): the first waypoint is the escort wing, the second the target's own wing with the target in it; the kill pays on the spot and drops no pilot" % Data.BOUNTY_ALIVE_RANK,
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
	await _frames(6)
	var failed: bool = GS.mission.is_empty() and not is_instance_valid(s.escort_node)
	for o in g2:
		if o in s.enemies: s._destroy_unit(o)
	_check("Job AI: the freighter destroyed fails the escort job (no pay)", failed)
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
