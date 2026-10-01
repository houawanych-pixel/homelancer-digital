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
	_check("Capital test block stands in the city sector (simple collision)", cb != null and s.city_solids.size() == st["solids"],
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
		["city_tower_b01", Vector3(-30, 40, -300), Vector3(60, 52, -180)],
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
		draws_block = maxi(draws_block, dc - int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
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
	_check("City shared material + normal detail (city pack), draw calls measured", shader_on and draws_block <= st["draw_calls"] + 2,
		"block adds %d draw calls up close, %d from 1.7 km (detail LOD off); whole frame %d" % [draws_block, dfar, draws])
	for m in mechs: m.queue_free()
	cam.queue_free()
	if prev: prev.make_current()
	main.hud.visible = true

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
	if OS.get_environment("HL_SHOWCASE") != "":
		await _showcase()
		return
	await _wait(1.5)
	_publish("title")
	await _shot("title", 1.0)
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
	await _shot("equipment_dealer")
	var m0 := GS.missiles
	main.hub.show_screen("ships")
	await _wait(0.5)
	# the route test is credited enough for one ship so the dealer can be verified in one run
	GS.add_credits(1500)
	main.hub.show_screen("ships")
	await _wait(0.3)
	var sb: Button = main.hub.find_child("Ship_ranger", true, false)
	if sb and not sb.disabled: sb.pressed.emit()
	await _wait(0.4)
	_check("Ship purchase", GS.ship_id == "ranger", "ship=%s hull=%d" % [GS.ship_id, int(GS.max_hull())])
	await _shot("ship_dealer")
	_check("Launch from station", await _launch())
	s = _sp()
	_check("New ship flies", s.model.name.ends_with("ranger"), s.model.name)
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
	s.target = g
	_press("goto")
	await _until(func(): return s.gate_in_range(), 25.0)
	_press("jump")
	await _until(func(): return main.fx.warp > 0.8, 8.0)
	await _capture("warp")
	await _until(func(): return main.state == "flight", 15.0)
	_check("Jump gate to Vega", GS.system_id == "vega" and "vega" in GS.discovered)
	await _wait(1.0)
	await _shot("vega_arrival")
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
	var packs_before: Dictionary = Packs.state.duplicate()
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
	_check("Galaxy map: %d systems shown, data only" % net["systems"].size(), gm.visible and net["systems"].size() >= 50 and playable == 2 and Packs.state == packs_before and res_after - res_before < 20,
		"links %d, resources +%d" % [net["links"].size(), int(res_after - res_before)])
	gm.press("close")
	gm.press("close")
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
	_press("jump")
	await _until(func(): return main.state == "flight" and GS.system_id == "solara", 15.0)
	_check("Return jump to Solara", GS.system_id == "solara")
	await _wait(1.0)
	await _shot("solara_return")
	var passed := results.filter(func(r): return r["pass"]).size()
	print("[route] RESULT %d/%d PASS" % [passed, results.size()])
	_publish("done", true)
	GS.god_mode = false
	if not web and "--quit-after-test" in OS.get_cmdline_user_args():
		get_tree().quit(0 if passed == results.size() else 1)
