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

## Station interior as panorama rooms: look around (wraps), tap markers, zoom through doors, dealer screens, talk.
func _station_rooms() -> void:
	await Packs.wait("rooms", 60.0)
	var hub: Control = main.hub
	hub.show_screen("hub")
	var rm: Rooms = hub.rooms
	await _wait(0.3)
	var in_room: bool = hub.has_rooms() and rm.visible and rm.room == "main_hub" and rm.tex != null and rm.tex.get_width() > 3000 and not hub.content.visible
	await _shot("room_main_hub_front", 0.2)
	# look around: the picture scrolls and wraps forever, the tilt is limited
	var p0: float = rm.pan
	for i in 40: rm.drag(Vector2(-400, 0))
	var wrapped: bool = rm.pan >= 0.0 and rm.pan < 1.0
	rm.pan = Rooms.strip_u(0.75)
	rm._vel = 0.0
	for i in 10: rm.drag(Vector2(0, -300))
	var tilt_ok: bool = absf(rm.tilt) <= 1.0
	rm.tilt = 0.0
	await _shot("room_main_hub_back", 0.2)
	rm.pan = (Rooms.VIEW_W + Rooms.BRIDGE * 0.5) / float(rm.tex.get_width())   # the join between the two views
	await _shot("room_main_hub_join", 0.2)
	_check("Station rooms: docking opens the Main Hub panorama; drag looks around and wraps", in_room and wrapped and tilt_ok and is_equal_approx(p0, Rooms.strip_u(0.25)),
		"%s, picture %d px wide, %d markers" % [Rooms.ROOMS[rm.room]["name"], rm.tex.get_width() if rm.tex else 0, Rooms.ROOMS[rm.room]["spots"].size()])
	# the LOOK stick turns the view; what comes to the middle lights up green and the green button uses it
	rm.open("main_hub")
	await _wait(0.2)
	var f0: int = rm.focus   # arriving, the service desk is straight ahead
	var pan0: float = rm.pan
	rm.look = Vector2(1, 0.4)
	await _wait(1.0)
	rm.look = Vector2.ZERO
	var turned: bool = rm.pan > pan0 + 0.08 and rm.tilt > 0.5 and rm.tilt <= 1.0
	rm.tilt = 0.0
	var sp2: Array = Rooms.ROOMS["main_hub"]["spots"]
	var want := -1
	for i in sp2.size(): if sp2[i]["act"] == "room:mission": want = i
	rm.pan = Rooms.strip_u(sp2[want]["u"])
	await _wait(0.2)
	var lit: bool = rm.focus == want
	await _shot("room_green_ready", 0.2)
	rm.pan = Rooms.strip_u(0.385)   # nothing near the middle here: no green, no button
	await _wait(0.2)
	var none: bool = rm.focus == -1
	rm.pan = Rooms.strip_u(sp2[want]["u"])
	await _wait(0.2)
	rm.tap(rm.go_rect().get_center())
	await _until(func(): return not rm.busy, 3.0)
	_check("Station rooms: LOOK stick turns the view; the marker in view lights green and the green button uses it",
		f0 >= 0 and turned and lit and none and rm.room == "mission", "ahead %s, turned %s, green %s, clear %s, in view: %s -> %s" % [f0 >= 0, turned, lit, none, sp2[want]["label"], rm.room])
	rm.open("main_hub")
	await _wait(0.2)
	# tap the DOCKING BAY sign: zoom through the door into the next room
	var spots: Array = Rooms.ROOMS["main_hub"]["spots"]
	var di := -1
	for i in spots.size(): if spots[i]["act"] == "room:docking": di = i
	rm.tap(rm.spot_pos(spots[di]["u"], spots[di]["v"]))
	var zooming: bool = rm.busy
	await _until(func(): return not rm.busy, 3.0)
	await _shot("room_docking_bay", 0.2)
	_check("Station rooms: tapping a door zooms into the next room", zooming and rm.room == "docking", rm.room)
	# every room's picture exists and every door leads somewhere real
	var all_ok := true
	for id: String in Rooms.ROOMS:
		if not ResourceLoader.exists(Rooms.path(id)): all_ok = false
		for sp: Dictionary in Rooms.ROOMS[id]["spots"]:
			var act: String = sp["act"]
			if act.begins_with("room:") and not Rooms.ROOMS.has(act.substr(5)): all_ok = false
			if act.begins_with("talk:") and not Data.CHARACTERS.has(act.substr(5)): all_ok = false
	for id in ["mission", "market", "bar", "hangar", "apartment"]:
		rm.open(id)
		if id == "mission": rm.use(1)   # Cmdr. Vale answers from the chat brain
		await _shot("room_" + id, 0.25)
	var talked: bool = false
	rm.open("mission")
	rm.use(1)
	talked = rm.caption != "" and rm.caption_who == "Cmdr. Vale"
	_check("Station rooms: 7 rooms, all doors valid, people talk", all_ok and Rooms.ROOMS.size() == 7 and talked, "%s: %s" % [rm.caption_who, rm.caption.left(60)])
	# a dealer marker opens the old dealer screen; STATION brings the room back where you were
	rm.open("main_hub")
	rm.use(1)
	var dealer: bool = hub.screen == "ships" and not rm.visible and hub.content.visible
	hub.show_screen("hub")
	_check("Station rooms: dealer markers open the dealer screens and STATION returns to the room", dealer and rm.visible and rm.room == "main_hub", hub.screen)

## Music by mood: the right mood for where you are, a take from that mood, every track present and wired.
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
	var took: bool = Music.track in Music.MOODS.get(Music.mood, [])
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
	_check("Music: 28 tracks by mood (space when flying Solara, Rift Gate in battle), each its own pack, can be muted",
		ok_files and n == 28 and flying == "space" and took and battle and was_muted and main.title.music_btn != null, "%d tracks, flying = %s, battle = %s" % [n, flying, btrack])

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
	for stick in [Vector2(0, 1), Vector2(-0.7, -0.7), Vector2(1, 0.1)]:   # screen stick: down = back, up-left, right
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
		and results[2][0] == "right" and results[2][1].x > sp
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
	await _shot("title_collage", 0.2)
	var tw: float = main.title.art.get_width() * (get_viewport().get_visible_rect().size.y / main.title.art.get_height()) if main.title.art else 0.0
	_check("Start screen: the owner's collage as one looping strip, panning slowly", main.title.art != null and main.title.art.resource_path.ends_with("title_collage.jpg")
		and main.title.art.get_width() > 2500 and main.title.art_k >= 1.0 and tw / main.title.PAN_SPEED > 120.0, "one loop takes %.0f s" % (tw / main.title.PAN_SPEED))
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
	await _station_rooms()
	main.hub.show_screen("equipment")
	await _wait(0.3)
	var btn: Button = main.hub.find_child("Buy_pulse2", true, false)
	if btn and not btn.disabled: btn.pressed.emit()
	await _wait(0.3)
	_check("Weapon purchase", GS.weapon_id == "pulse2", "weapon=%s credits=%d" % [GS.weapon_id, GS.credits])
	var rack_btn: Button = main.hub.find_child("Rack_swarm", true, false)
	var fit_btn: Button = main.hub.find_child("Rack_triple", true, false)
	_check("Job M: Equipment sells the missile racks (Triple fitted, Swarm for sale)", rack_btn != null and fit_btn != null and fit_btn.disabled
		and rack_btn.text.find(str(Data.MISSILE_RACKS["swarm"]["price"])) >= 0, rack_btn.text if rack_btn else "no button")
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
	var hits := {}
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
	s.collide_grace = 0.0
	var d_slow: float = s.collision_damage("building", 20.0)
	s.collide_grace = 0.0
	var d_fast: float = s.collision_damage("building", 40.0)
	var expect_slow := (20.0 - Data.COLLIDE_THRESHOLD) * Data.COLLIDE_MULT
	_check("Job L: damage scales with impact speed (faster = more)", d_fast > d_slow and absf(d_slow - expect_slow) < 0.01, "20 m/s %.1f, 40 m/s %.1f" % [d_slow, d_fast])
	GS.restore_full()
	s.collide_grace = 0.0
	var free_touch: float = s.collision_damage("ground", Data.COLLIDE_THRESHOLD - 0.1)
	var hull_free: bool = GS.hull == GS.max_hull()
	# ---- feedback: shake, flash, sound scale with the hit
	s.collide_grace = 0.0
	s.hit_shake = 0.0
	main.hud.damage_flash = 0.0
	s.collision_damage("asteroid", Data.COLLIDE_THRESHOLD + 3.0)
	var soft_shake: float = s.hit_shake      # read at once: on a slow frame the shake has died away a frame later (E2)
	await _frames(1)
	var soft_k: float = s.last_collision.get("k", -1.0)
	var soft_flash: float = main.hud.damage_flash
	s.collide_grace = 0.0
	s.hit_shake = 0.0
	main.hud.damage_flash = 0.0
	s.collision_damage("asteroid", 60.0)
	var hard_shake: float = s.hit_shake
	await _frames(1)
	var hard_k: float = s.last_collision.get("k", -1.0)
	_check("Job L: hit feedback (flash, shake, sound) on collision, stronger for harder hits; the hull bar shows it", soft_flash > 0.0 and soft_shake > 0.0
		and hard_k > soft_k and main.hud.damage_flash > soft_flash and hard_shake > soft_shake and GS.hull < GS.max_hull(),
		"k soft %.2f hard %.2f; shake %.2f > %.2f" % [soft_k, hard_k, hard_shake, soft_shake])
	# ---- grace window
	GS.restore_full()
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
	s.collision_damage("building", 40.0)
	var dead_now: bool = GS.hull == 0.0 and not s.controls
	var towed := await _until(func(): return main.state == "hub", 15.0)
	_check("Job L: a collision that takes the hull to zero destroys the ship through the normal death flow", dead_now and towed and GS.hull == GS.max_hull(), "state %s" % main.state)
	await _launch()
	GS.god_mode = true
	# ---- version label
	var shell := FileAccess.get_file_as_string("res://web_shell.html") if FileAccess.file_exists("res://web_shell.html") else ""
	_check("Job L: version label reads \"Homelancer Digital v1.4h\" or later", Data.VERSION >= "v1.4h" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)


## Job M (v1.4j): Cadet turned round, the lead box, missile locks and volleys, the three missile types, dodging.
func _combat_m() -> void:
	var s := _sp()
	var shell := FileAccess.get_file_as_string("res://web_shell.html")
	_check("Job M: version label reads \"Homelancer Digital v1.4j\" or later", Data.VERSION >= "v1.4j" and (shell == "" or shell.find("<title>Homelancer Digital %s</title>" % Data.VERSION) >= 0), Data.VERSION)
	_check("Job M: the Cadet model is turned round (nose away from the camera); the other ships are unchanged",
		is_equal_approx(ShipFactory.GLB["cadet"][2], 180.0) and ShipFactory.GLB["ranger"][2] == 0.0 and ShipFactory.GLB["lancer"][2] == 0.0)
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
	GS.credits = 0
	var refused: bool = GS.buy_rack("swarm").begins_with("Not enough") and GS.rack == "triple"
	GS.credits = int(Data.MISSILE_RACKS["swarm"]["price"]) + 10
	GS.buy_rack("swarm")
	var bought: bool = GS.rack == "swarm" and GS.credits == 10 and "swarm" in GS.owned_racks
	GS.missiles = 8
	s.missile_cd = 0.0
	s.lock_time = Data.LOCK_STEP * 9.0
	var l5: int = s.lock_count()
	for m in s.missiles_live: m["life"] = 0.0
	await _frames(3)
	s.trigger_system("light_missile")
	await _wait(Data.VOLLEY_GAP * 5.0 + 0.2)
	var swarm_n: int = s.missiles_live.size()
	var swarm_scale: float = float(s.missiles_live[-1]["scale"]) if swarm_n > 0 else 0.0
	GS.buy_rack("triple")
	var refit: bool = GS.rack == "triple" and GS.credits == 10
	_check("Job M: the Swarm Rack is bought at Equipment, holds five locks and fires five lighter missiles; refitting a rack you own is free", refused and bought and l5 == 5 and swarm_n == 5 and GS.missiles == 3
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
	s.enemy_fire_missile(fake)
	await _frames(3)
	var warned: bool = s.missile_warn > 0.0
	await _shot("missile_incoming", 0.3)
	var sh0 := GS.shield + GS.hull
	await _until(func(): return s.enemy_missiles.is_empty(), 10.0)
	var took: float = sh0 - (GS.shield + GS.hull)
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
	var sc_names: Array = [sc["planet"]["name"], sc["station"]["name"]] + (sc["more_planets"] as Array).map(func(x): return x["name"])
	var cr_names: Array = [cr["planet"]["name"], cr["station"]["name"]] + (cr["more_planets"] as Array).map(func(x): return x["name"])
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
