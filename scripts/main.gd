extends Node
## Homelancer Digital v1.2 — game flow: title -> launch -> flight <-> docking -> hub -> launch, jump gates, map.

const SpaceScript := preload("res://scripts/space.gd")
const HudScript := preload("res://scripts/hud.gd")
const HubScript := preload("res://scripts/hub.gd")
const MapScript := preload("res://scripts/navmap.gd")
const GalaxyMapScript := preload("res://scripts/galaxymap.gd")
const FxScript := preload("res://scripts/fx.gd")

var state := "title"
var space: SpaceSystem
var ui: CanvasLayer
var hud: Control
var hub: Control
var navmap: Control
var galaxymap: Control
var fx: Control
var title: Control
var docked_node_kind := "station"
var visited := {}
var autotest := false

func _ready() -> void:
	_input_map()
	ui = CanvasLayer.new()
	add_child(ui)
	hud = HudScript.new()
	hud.visible = false
	ui.add_child(hud)
	hub = HubScript.new()
	ui.add_child(hub)
	navmap = MapScript.new()
	ui.add_child(navmap)
	galaxymap = GalaxyMapScript.new()
	ui.add_child(galaxymap)
	navmap.galaxy_requested.connect(func(): galaxymap.open(GS.system_id))
	fx = FxScript.new()
	ui.add_child(fx)
	hud.pressed.connect(_on_hud)
	hud.typed.connect(_on_typed)
	hub.launch_requested.connect(launch)
	hub.map_requested.connect(func(): navmap.open(null))
	hub.descend_requested.connect(descend_to)
	navmap.closed.connect(_on_map_closed)
	navmap.course_set.connect(_on_course)
	GS.changed.connect(_on_gs_changed)
	_build_title()
	_load_system("solara", "station")
	space.controls = false
	# optional content arrives in the background after the game is up (see scripts/packs.gd)
	get_tree().create_timer(1.5).timeout.connect(func(): for pk in ["sky", "rooms", "enemies", "cockpit", "mechs", "lancer", "planets"]: Packs.request(pk))
	autotest = "--autotest" in OS.get_cmdline_user_args() or _web_flag("autotest")
	if autotest:
		var runner: Node = load("res://scripts/autotest.gd").new()
		runner.main = self
		add_child(runner)

func _web_flag(f: String) -> bool:
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		return q is String and (q as String).find(f) >= 0
	return false

func _input_map() -> void:
	var keys := {"transform": [KEY_T], "forward": [KEY_W], "back": [KEY_S], "strafe_left": [KEY_A], "strafe_right": [KEY_D],
		"yaw_left": [KEY_LEFT, KEY_Q], "yaw_right": [KEY_RIGHT, KEY_E], "pitch_up": [KEY_UP], "pitch_down": [KEY_DOWN], "fire": [KEY_SPACE]}
	for a in keys:
		if not InputMap.has_action(a): InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)

# ---------------------------------------------------------------- title
func _build_title() -> void:
	title = load("res://scripts/title.gd").new()
	ui.add_child(title)
	title.start_pressed.connect(start_game)

func start_game() -> void:
	if state != "title": return
	title.visible = false
	title.release()
	state = "launching"
	GS.restore_full()
	_launch_sequence("Liberty Hub")

# ---------------------------------------------------------------- systems
func _load_system(id: String, arrival: String) -> void:
	_new_space("Space_" + id)
	GS.system_id = id
	if not (id in GS.discovered): GS.discovered.append(id)
	space.setup(id, arrival)
	_connect_space()

## Planet surface: the same flight scene, built as one tile of a planet (see surface.gd).
func _load_surface(pid: String, t: int) -> void:
	_new_space("Surface_%s_%d" % [pid, t])
	space.setup_surface(pid, t)
	GS.system_id = space.sys_id
	_connect_space()

func _new_space(nm: String) -> void:
	if is_instance_valid(space):
		space.queue_free()
		remove_child(space)
	space = SpaceScript.new()
	space.name = nm
	add_child(space)
	move_child(space, 0)

func _connect_space() -> void:
	space.atmosphere_entered.connect(enter_atmosphere)
	space.tile_edge.connect(_on_tile_edge)
	space.leave_atmosphere.connect(leave_atmosphere)
	space.enemy_killed.connect(_on_kill)
	space.player_destroyed.connect(_on_destroyed)
	space.message.connect(func(t): hud.flash_message(t))
	space.system_used.connect(func(sid, txt): hud.flash_message(txt); hud.pulse(sid))
	space.hail.connect(_on_hail)
	space.enemy_hail.connect(_on_enemy_hail)
	space.enemy_chatter.connect(_on_enemy_chatter)
	hud.space = space

func _on_gs_changed() -> void:
	if state == "flight" and is_instance_valid(space) and GS.shield < GS.max_shield() and space.shield_delay >= 2.9:
		hud.hurt()

## Which music fits right now (moods: scripts/music.gd; the owner's guide is in docs/DESIGN.md §19).
var _fight_t := 0.0     # seconds since hostiles were last on you
var _calm_t := 0.0      # "calm after a victory" time left
var _kills_seen := 0
func music_mood(dt: float) -> String:
	if state == "title": return "intro"
	if state == "hub": return "heart" if hub.rooms.visible and hub.rooms.room == "apartment" else ""
	if not is_instance_valid(space) or not is_instance_valid(space.player): return Music.mood
	if state != "flight": return Music.mood          # docking, jumping, map: keep what is playing
	var fighting: bool = space.hostiles_engaged() > 0
	if fighting:
		if _fight_t > 0.0 or Music.mood != "battle": _kills_seen = GS.kills   # a new fight begins: count kills from here
		_fight_t = 0.0
		return "battle"
	if _fight_t == 0.0 and Music.mood == "battle" and GS.kills > _kills_seen: _calm_t = 26.0   # won it (not just got away)
	_fight_t += dt
	if Music.mood == "battle" and _fight_t < 4.0: return "battle"   # do not drop the battle music for a short gap
	if _calm_t > 0.0:
		_calm_t -= dt
		return "heart"
	if space.surface_mode: return "explore"
	if space.in_nebula > 0.0 or space.player.global_position.length() > 9000.0: return "void"
	return "dark" if space.sys.get("enemy", "") == "corsair" else "space"

func _process(_dt: float) -> void:
	Music.want(music_mood(_dt))
	if state == "title" and is_instance_valid(space):
		# slow attract-mode orbit around Liberty Hub
		var t := Time.get_ticks_msec() / 1000.0
		space.cam.global_position = space.station.global_position + Vector3(cos(t * 0.08) * 330, 90, sin(t * 0.08) * 330)
		space.cam.look_at(space.station.global_position, Vector3.UP)
	if state == "flight":
		hud.objective = _objective()
		if space.surface_mode:
			fx.clouds = space.corner_haze * 0.75   # inside the wrap-corner cloud bank
			if space.corner_haze > 0.0: fx.cloud_tint = (Surface.biome(space.planet_id, space.tile)["fog"] as Color).lerp(Color.WHITE, 0.45)
		else:
			# outer atmosphere of a planet: haze thickens and the nose glows the deeper (and faster) you go
			var k: float = space.atmo_depth
			fx.clouds = k * 0.38
			fx.heat = k * clampf(space.speed_now / 90.0, 0.25, 1.0) * 0.7
			if k > 0.0 and is_instance_valid(space.planet):
				var pid: String = space.planet.get_meta("info")["id"]
				if Surface.has_surface(pid): fx.cloud_tint = Surface.biome(pid, 4 if Surface.grid(pid) == 3 else 0)["horizon"].lerp(Color.WHITE, 0.5)
		if not ("rennick" in GS.met) and GS.system_id == "solara" and not hud.comms_open:
			for tr in space.traffic:
				if tr["node"].global_position.distance_to(space.player.global_position) < 600.0:
					_meet("rennick", "friendly")
					break
	_web_state()

var _web_t := 0.0
## Small read-only status for browser test harnesses (window.__hlstate).
func _web_state() -> void:
	if not OS.has_feature("web"): return
	_web_t += get_process_delta_time()
	if _web_t < 0.25: return
	_web_t = 0.0
	var d := {"state": state, "system": GS.system_id, "credits": GS.credits, "missiles": GS.missiles, "repairs": GS.repairs}
	if is_instance_valid(space) and is_instance_valid(space.player):
		d["speed"] = snappedf(space.speed_now, 0.1)
		d["yaw"] = snappedf(space.yaw, 0.001)
		d["pitch"] = snappedf(space.pitch, 0.001)
		d["strafe"] = snappedf(space.move.x, 0.01)
		d["auto"] = GS.is_auto("guns")
		d["view"] = GS.view
	JavaScriptBridge.eval("window.__hlstate = %s;" % JSON.stringify(d), true)

func _objective() -> String:
	if space.surface_mode:
		var has_port: bool = space.station.get_meta("kind", "") == "station"
		return "PLANET: %s  ·  climb above %d m for orbit" % [("dock at " + space.station.name) if has_port else "fly on — the planet wraps around", int(Surface.CEILING)]
	var enemy_name: String = Data.ENEMIES[space.sys["enemy"]]["name"]
	var st: String = space.sys["station"]["name"]
	var pl: String = space.sys["planet"]["name"]
	var gt: String = space.sys["gate"]["name"]
	if GS.system_id == "solara":
		if GS.kills == 0: return "OBJECTIVE: Destroy a %s (aim — lasers fire on their own, missiles finish it)" % enemy_name
		if not visited.has("liberty_hub_2"): return "OBJECTIVE: Dock at %s to repair and spend your credits" % st
		if not visited.has("new_terra"): return "OBJECTIVE: Land on %s — MAP > select planet > SET COURSE" % pl
		return "OBJECTIVE: Cross the belt and nebula to the %s" % gt
	if not visited.has("frontier_exchange"): return "OBJECTIVE: Dock at %s" % st
	return "OBJECTIVE: Explore Vega, fight %ss, or return via the %s" % [enemy_name.to_lower(), gt]

# ---------------------------------------------------------------- HUD buttons
func _on_hud(id: String) -> void:
	if state != "flight": return
	if id.begins_with("sys_"):
		var sid := id.substr(4)
		if sid == "guns":
			hud.flash_message("Weapons fire automatically on target (AUTO) or with the FIRE button (MANUAL).")
		else:
			space.trigger_system(sid)
		return
	if id.begins_with("mode_"):
		var parts := id.split("_")
		GS.modes[parts[1]] = parts[2]
		GS.changed.emit()
		var labels := {"shield": "Shield recharge", "hull": "Hull repair", "energy": "Energy recharge", "guns": "Weapons", "missile": "Missiles", "mine": "Mines"}
		var how := {"shield": "boosts when shields drop to zero", "hull": "uses a kit below 35% hull", "energy": "refills below 15% energy",
			"guns": "fire when a hostile is in the reticle", "missile": "launch after a 1.5 s lock", "mine": "drop when a hostile is on your tail"}
		hud.flash_message("%s: %s" % [labels[parts[1]], ("AUTO — " + how[parts[1]]) if parts[2] == "auto" else "MANUAL — tap the panel"])
		return
	if id.begins_with("slot_"):
		space.fire_slot(int(id.substr(5)))
		return
	match id:
		"missile": space.trigger_system("missile")
		"shield": space.trigger_system("shield")
		"repair": space.trigger_system("hull")
		"tractor":
			var tm: String = space.tractor()
			hud.flash_message(tm)
			if space.tractor_t > 0.0: Sfx.play("tractor", -6.0)
		"target": space.cycle_target()
		"view":
			space.set_view("cockpit" if GS.view == "chase" else "chase")
			hud.flash_message("View: %s" % ("first-person cockpit" if GS.view == "cockpit" else "chase camera"))
		"stop":
			space.full_stop()
			hud.flash_message("Braking to a full stop.")
		"form":
			match space.start_transform():
				"mech": hud.flash_message("Transforming to MECH… weapons locked for 3 s.")
				"ship": hud.flash_message("Transforming to SHIP… weapons locked for 3 s.")
				"warp": hud.flash_message("Can't transform during warp.")
				"loading": hud.flash_message("Mech frame still downloading — try again in a moment.")
		"kill":
			if GS.form == "mech": hud.flash_message("Mechs don't drift — use BOOST with the stick to dash any direction.")
			elif space.warp_active(): hud.flash_message("Drop out of warp first.")
			else: hud.flash_message("Engines OFF — drifting. You can still turn and shoot." if space.toggle_engine_kill() else "Engines restarted.")
		"warp":
			match space.request_warp():
				"charging": hud.flash_message("Warp spooling — 5 s. Weapons locked. Keep flying!")
				"atmosphere": hud.flash_message("The warp drive can't run inside an atmosphere.")
				"mech": hud.flash_message("Mechs have no warp drive — transform to SHIP to warp.")
				"busy": hud.flash_message("Finish transforming first.")
				"cancelled": hud.flash_message("Warp charge cancelled. Weapons unlocked.")
				"off": hud.flash_message("Dropped out of warp. Weapons unlocked.")
		"call":
			_call_target()
		"log":
			if hud.comms_mode == "roster": hud.close_roster()
			else: hud.open_log()
		"voice":
			hud.flash_message(Sfx.toggle_voice())
			if hud.comms_open: Sfx.speak(hud.comms_line, hud.comms_voice, hud.comms_female)
		"hangup":
			if hud.comms_open:
				hud.close_comms()
				hud.flash_message("Call ended.")
		"goto":
			if space.target and is_instance_valid(space.target) and space.target.get_meta("kind", "") != "enemy":
				space.autopilot = space.target
				hud.flash_message("Autopilot engaged: %s" % space.target.name)
			elif space.autopilot != null:
				space.autopilot = null
				hud.flash_message("Autopilot off.")
			else:
				hud.flash_message("Select a station, planet or gate with TARGET or MAP first.")
		"nav": open_map()
		"dock":
			var n: Node3D = space.dock_candidate()
			if n: dock(n)
		"jump":
			if space.gate_in_range(): jump()
		"side_l", "side_r":   # tap a comms screen: the console (log, contacts, type) pulls up
			if hud.comms_mode != "roster": hud.open_log()
		"type": hud.start_typing()
		"radar": open_map()   # tap the radar: the map, where you can set a course or drop a waypoint
		_:
			if id.begins_with("met_"):
				var k := int(id.substr(4))
				if k < GS.met.size():
					var cid: String = GS.met[k]
					if hud.in_range(cid): call_character(cid)
					else: hud.flash_message("%s is in %s — out of comms range. Only people in this system can be called." % [Data.CHARACTERS[cid]["name"], Data.SYSTEMS[Data.CHARACTERS[cid]["system"]]["name"]])

## CALL: hail whatever you have targeted, otherwise the local station controller.
func _call_target() -> void:
	var tgt: Node3D = space.target
	if tgt and is_instance_valid(tgt) and tgt.get_meta("kind", "") == "enemy":
		var leader: String = Data.ENEMY_LEADER[space.sys["enemy"]]
		if tgt.has_meta("pilot") and (not (leader in GS.met) or randf() < 0.6): _pilot_call(tgt.get_meta("pilot"), false)
		elif leader in GS.met: call_character(leader)
		else: hud.open_comms(tgt.name + " pilot", space.TAUNTS[randi() % space.TAUNTS.size()], "talk", true)
		return
	if tgt and is_instance_valid(tgt) and tgt == space.planet and GS.system_id == "solara":
		call_character("oduya")
		return
	for tr in space.traffic:
		if tgt == tr["node"]:
			call_character("rennick")
			return
	call_character("vale" if GS.system_id == "solara" else "amari")

var on_call := ""   # who you're talking to (for typed messages)

## You typed into the comms console: whoever is on the line answers.
func _on_typed(txt: String) -> void:
	var side := "r" if hud.slot("r").get("mode", "") == "talk" else ("l" if hud.slot("l").get("mode", "") == "talk" else "")
	if on_call == "" or side == "":
		hud.flash_message("Message logged — nobody is on the line. Call someone from LOG first.")
		return
	var who := on_call
	var ctx := {"system": GS.system_id, "hostiles": space.hostiles_near(900.0), "hull": GS.hull / GS.max_hull(), "kills": GS.kills,
		"credits": GS.credits, "on_planet": space.surface_mode}
	await get_tree().create_timer(0.9).timeout   # a beat before they answer
	if hud.slot(side).get("mode", "") != "talk": return
	Brain.ask(who, txt, ctx, func(line: String): say_as(who, line))

## Put a line in a character's mouth (comms screen, face, voice). The brain's replies come through here.
func say_as(id: String, line: String) -> void:
	var c: Dictionary = Data.CHARACTERS[id]
	on_call = id
	hud.open_comms("%s — %s" % [c["name"], c["role"]], line, "talk", GS.mood.get(id, "friendly") == "enraged",
		c.get("face", ""), float(c.get("voice", 1.0)), bool(c.get("female", false)))

func call_character(id: String, incoming := false) -> void:
	var c: Dictionary = Data.CHARACTERS[id]
	if not incoming: on_call = id
	if not (id in GS.met): GS.meet(id, "enraged" if c["lines"].has("enraged") else "friendly")
	var m: String = GS.mood.get(id, "friendly")
	var pool: Array = c["lines"].get(m, c["lines"].values()[0])
	var line: String = pool[randi() % pool.size()]
	if (id == "vale" or id == "amari") and not incoming: line = _comms_line()
	hud.open_comms("%s — %s" % [c["name"], c["role"]], line, "incoming" if incoming else "talk", m == "enraged",
		c.get("face", ""), float(c.get("voice", 1.0)), bool(c.get("female", false)))

## First meetings: they join the LOG roster and usually call you.
func _meet(id: String, m: String, call := true) -> void:
	if GS.meet(id, m) and call: call_character(id, true)

func _comms_line() -> String:
	var n := space.hostiles_near(900.0)
	if n > 0: return "[serious]Pilot, %d hostile%s on your scope. Weapons free — stay sharp." % [n, "" if n == 1 else "s"]
	if space.in_nebula > 0.0: return "[serious]We're losing your signal in the nebula. Sensors will be short-ranged in there."
	if space.in_belt: return "[serious]Rocks everywhere out there. Throttle down and watch your hull."
	if GS.hull < GS.max_hull() * 0.5: return "[sad]You're leaking plasma. Dock with us for free repairs."
	var o := _objective().replace("OBJECTIVE: ", "")
	return "[normal]Traffic control here. Recommended: %s." % o.to_lower()

func open_map() -> void:
	if space.surface_mode:
		hud.flash_message("%s — tiles wrap around the planet. Dock at a town for fast travel." % Surface.tile_name(space.planet_id, space.tile))
		return
	state = "map"
	hud.close_comms()
	space.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	navmap.open(space)

func _on_map_closed() -> void:
	if state == "map":
		state = "flight"
		space.process_mode = Node.PROCESS_MODE_INHERIT
		hud.visible = true

func _on_course(n: Node3D) -> void:
	_on_map_closed()
	space.target = n
	space.autopilot = n
	hud.flash_message("Course set: %s. Autopilot engaged — steer to cancel." % n.name)

func _unhandled_input(e: InputEvent) -> void:
	if state == "flight" and e.is_action_pressed("transform"): _on_hud("form")
	# any manual aim cancels autopilot
	if state == "flight" and space.autopilot != null and hud.aim_vec.length() > 0.35:
		space.autopilot = null
		hud.flash_message("Autopilot off.")

## An enemy pilot (face from the enemy dossiers) taunts you over the radio.
func _pilot_call(p: Dictionary, incoming := true) -> void:
	if not p.has("lines"):   # a generic wing pilot: no personal lines, they answer with squad chatter
		var ch: Array = Data.CHATTER["target_acquired"]
		hud.open_comms("%s — %s pilot · %s's wing" % [p["unit"], p["type"], p.get("leader", "?")], ch[randi() % ch.size()],
			"incoming" if incoming else "talk", true, "gp/" + str(p["id"]), float(p["voice"]), bool(p["female"]))
		return
	var lines: Array = p["lines"]
	hud.open_comms("%s — Unit %s" % [p["name"], p["unit"]], lines[randi() % lines.size()], "incoming" if incoming else "talk", true,
		p["face"], float(p["voice"]), bool(p["female"]))

func _on_enemy_hail(p: Dictionary) -> void:
	if hud.side_busy(true): return
	var leader: String = Data.ENEMY_LEADER[space.sys["enemy"]]
	if leader in GS.met and randf() < 0.35: call_character(leader, true)
	else: _pilot_call(p)

## A generic pilot (AX-01..06, flying under a named leader) on the same radio: short line, NORMAL or DAMAGED
## portrait from the enemies pack (waveform until the pack is there). Never cuts off a named leader mid-sentence.
func _on_enemy_chatter(p: Dictionary, line: String) -> void:
	var l: Dictionary = hud.slot("l")
	if hud.side_busy(true): return
	if not l.is_empty() and not l["generic"] and float(l["timer"]) > 3.0: return   # let a named leader finish
	hud.open_comms("%s — %s pilot · %s's wing" % [p["unit"], p["type"], p["leader"]], line, "incoming", true,
		"gp/" + p["id"], float(p["voice"]), bool(p["female"]))
	hud.comms_timer = 3.5

func _on_hail(from: String, line: String, hostile: bool) -> void:
	if hud.side_busy(hostile): return
	var leader: String = Data.ENEMY_LEADER[space.sys["enemy"]]
	if hostile and leader in GS.met: call_character(leader, true)
	else: hud.open_comms(from, line, "incoming", hostile)

func _on_kill(reward: int, who: String) -> void:
	GS.kills += 1
	GS.add_credits(reward)
	hud.flash_message("%s destroyed. +%d credits." % [who, reward])
	var leader: String = Data.ENEMY_LEADER[space.sys["enemy"]]
	if not (leader in GS.met): _meet.call_deferred(leader, "enraged")

# ---------------------------------------------------------------- docking / hub / launch
func dock(n: Node3D) -> void:
	if state != "flight": return
	state = "docking"
	space.controls = false
	space.autopilot = null
	space.drop_warp()
	hud.visible = false
	var info: Dictionary = n.get_meta("info")
	docked_node_kind = info["kind"]
	fx.caption = "DOCKING"
	fx.sub = info["name"].to_upper()
	var p: Node3D = space.player
	var approach: Vector3 = space.dock_point(n)
	var inside: Vector3 = n.global_position + Vector3(0, 0, 44) if info["kind"] == "station" else n.global_position + (approach - n.global_position).normalized() * (float(n.get_meta("radius")) + 4.0)
	var tw := create_tween()
	tw.tween_method(func(k: float): _fly_along(p, approach, k), 0.0, 1.0, 1.6)
	tw.tween_method(func(k: float): _fly_along(p, inside, k), 0.0, 1.0, 1.2)
	tw.parallel().tween_property(fx, "fade", 1.0, 1.0).set_delay(0.3)
	await tw.finished
	space.visible = false
	space.process_mode = Node.PROCESS_MODE_DISABLED
	GS.restore_full()
	GS.last_base = info["id"]
	visited[info["id"]] = true
	if info["id"] == "new_terra": GS.meet("oduya", "friendly")
	if info["id"] == "frontier_exchange": GS.meet("amari", "friendly")
	if info["id"] == "liberty_hub" and GS.kills > 0: visited["liberty_hub_2"] = true
	hub.open(info)
	state = "hub"
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""

var _fly_from := Vector3.ZERO
var _fly_last_k := 1.0
func _fly_along(p: Node3D, goal: Vector3, k: float) -> void:
	if k < _fly_last_k or k == 0.0: _fly_from = p.global_position
	_fly_last_k = k
	var e := k * k * (3.0 - 2.0 * k)
	var pos := _fly_from.lerp(goal, e)
	var d := goal - p.global_position
	if d.length() > 0.5:
		var dir := d.normalized()
		space.yaw = lerp_angle(space.yaw, atan2(-dir.x, -dir.z), 0.12)
		space.pitch = lerpf(space.pitch, asin(clampf(dir.y, -1, 1)), 0.12)
		p.basis = Basis.from_euler(Vector3(space.pitch, space.yaw, 0))
	p.global_position = pos
	space.vel = Vector3.ZERO

func launch() -> void:
	if state != "hub": return
	state = "launching"
	hub.visible = false
	var where: String = hub.base["name"]
	fx.fade = 1.0
	space.visible = true
	space.process_mode = Node.PROCESS_MODE_INHERIT
	space.set_player_model()
	space.place_player("planet" if docked_node_kind == "planet" else "station")
	_launch_sequence(where)

func _launch_sequence(where: String) -> void:
	fx.caption = "LAUNCHING"
	fx.sub = where.to_upper()
	fx.fade = 1.0
	hud.visible = false
	space.controls = false
	var p: Node3D = space.player
	var fwd := -p.global_basis.z
	var start := p.global_position - fwd * 60.0
	var goal := p.global_position + fwd * 30.0
	p.global_position = start
	space._update_camera(1.0, true)
	var tw := create_tween()
	tw.tween_property(fx, "fade", 0.0, 1.0)
	tw.parallel().tween_method(func(k: float): p.global_position = start.lerp(goal, k); space.vel = fwd * 40.0, 0.0, 1.0, 1.8)
	await tw.finished
	fx.caption = ""
	space.controls = true
	space.vel = fwd * 35.0
	hud.visible = true
	state = "flight"
	hud.flash_message("Launch complete. %s system." % Data.SYSTEMS[GS.system_id]["name"])
	var ctl := "vale" if GS.system_id == "solara" else "amari"
	if ctl in GS.met: hud.open_comms("%s — %s" % [Data.CHARACTERS[ctl]["name"], Data.CHARACTERS[ctl]["role"]], "[smile]You're clear, pilot. " + _comms_line().substr(_comms_line().find("]") + 1), "incoming", false,
		Data.CHARACTERS[ctl].get("face", ""), float(Data.CHARACTERS[ctl].get("voice", 1.0)), bool(Data.CHARACTERS[ctl].get("female", false)))
	else: _meet(ctl, "friendly")

# ---------------------------------------------------------------- jump gates
func jump() -> void:
	if state != "flight": return
	state = "jumping"
	space.controls = false
	space.autopilot = null
	space.drop_warp()
	hud.visible = false
	var to: String = space.sys["gate"]["to"]
	var gate: Node3D = space.gate
	var p: Node3D = space.player
	var front: Vector3 = gate.global_position + gate.global_basis.z * 110.0
	var through: Vector3 = gate.global_position - gate.global_basis.z * 60.0
	fx.caption = ""
	fx.warp_color = Data.SYSTEMS[to]["star"]
	var tw := create_tween()
	tw.tween_method(func(k: float): _fly_along(p, front, k), 0.0, 1.0, 1.2)
	tw.tween_method(func(k: float): _fly_along(p, through, k), 0.0, 1.0, 1.4)
	tw.parallel().tween_property(fx, "warp", 1.0, 1.4)
	await tw.finished
	fx.caption = "JUMP IN PROGRESS"
	fx.sub = "%s  >  %s" % [space.sys["name"].to_upper(), Data.SYSTEMS[to]["name"].to_upper()]
	await get_tree().create_timer(1.3).timeout
	_load_system(to, "gate")
	space.controls = false
	fx.caption = "ARRIVING"
	fx.sub = "%s SYSTEM  ·  %s" % [Data.SYSTEMS[to]["name"].to_upper(), space.sys["gate"]["name"]]
	var tw2 := create_tween()
	tw2.tween_property(fx, "warp", 0.0, 1.4)
	await tw2.finished
	fx.caption = ""
	space.controls = true
	hud.visible = true
	state = "flight"
	hud.flash_message("Welcome to %s." % Data.SYSTEMS[to]["name"])

# ---------------------------------------------------------------- defeat
func _on_destroyed() -> void:
	if state != "flight": return
	state = "dead"
	hud.visible = false
	fx.caption = "SHIP DISABLED"
	fx.sub = "Rescue tug inbound — towing you to %s" % space.sys["station"]["name"]
	var tw := create_tween()
	tw.tween_property(fx, "fade", 1.0, 2.0).set_delay(1.0)
	await tw.finished
	var lost := int(GS.credits * 0.1)
	GS.credits -= lost
	GS.restore_full()
	if space.surface_mode: _load_system(space.sys_id, "station")
	space.visible = false
	space.process_mode = Node.PROCESS_MODE_DISABLED
	space.controls = true
	var info: Dictionary = space.sys["station"].duplicate()
	docked_node_kind = "station"
	hub.open(info)
	hub.status.text = "Towed in. Repairs complete. Salvage fee: %d credits." % lost
	state = "hub"
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""

# ---------------------------------------------------------------- planets: atmosphere entry, tiles, fast travel
## Option A: fly into a planet. Heat glow + clouds + shake + rumble hide the load; you come out over the tile
## under the point where you hit the atmosphere, still heading the same way.
func enter_atmosphere(planet_node: Node3D) -> void:
	if state != "flight": return
	state = "atmosphere"
	var pid: String = planet_node.get_meta("info")["id"]
	var d: Vector3 = (space.player.global_position - planet_node.global_position).normalized()
	var t := Surface.tile_from_direction(pid, d)
	var yaw: float = space.yaw
	var entry_speed: float = space.speed_now
	space.controls = false
	space.autopilot = null
	space.drop_warp()
	hud.close_comms()
	hud.visible = false
	fx.caption = "ENTERING THE STAR" if Surface.is_sun(pid) else "ENTERING ATMOSPHERE"
	fx.sub = Surface.PLANETS[pid]["name"].to_upper()
	fx.cloud_tint = Surface.biome(pid, t)["horizon"].lerp(Color.WHITE, 0.6)
	Sfx.play("atmo", -2.0)
	var tw := create_tween()
	tw.tween_property(fx, "heat", 1.0, 1.0)
	tw.parallel().tween_property(fx, "clouds", 0.55, 1.2)
	tw.parallel().tween_method(func(k: float): space.hit_shake = 0.35 + 0.4 * k, 0.0, 1.0, 1.4)
	tw.tween_property(fx, "clouds", 1.0, 0.5)
	await tw.finished
	Packs.request("city")
	if not Packs.is_ready("planets"):
		fx.caption = "ENTERING ATMOSPHERE"
		fx.sub = "Receiving surface data…"
		await Packs.wait("planets", 90.0)   # clouds stay up while the planet pack arrives
	_load_surface(pid, t)            # loads while the screen is white
	space.controls = false
	var p: Node3D = space.player
	var at := Surface.local_from_direction(pid, d)   # come out over the part of the planet you flew into
	p.global_position = Vector3(at.x, maxf(1500.0, space._ground(at.x, at.y) + 900.0), at.y)
	space.yaw = yaw
	space.pitch = deg_to_rad(-18.0)
	p.basis = Basis.from_euler(Vector3(space.pitch, space.yaw, 0))
	space.vel = -p.global_basis.z * clampf(entry_speed, 40.0, 90.0)
	space._update_camera(1.0, true)
	fx.caption = "SOLAR SURFACE" if Surface.is_sun(pid) else "ATMOSPHERE"
	fx.sub = Surface.tile_name(pid, t)
	var tw2 := create_tween()
	tw2.tween_property(fx, "heat", 0.0, 0.9)
	tw2.parallel().tween_method(func(k: float): space.hit_shake = 0.5 * (1.0 - k), 0.0, 1.0, 1.2)
	tw2.parallel().tween_property(fx, "clouds", 0.0, 1.6).set_ease(Tween.EASE_IN)
	await tw2.finished
	fx.caption = ""
	space.controls = true
	hud.visible = true
	state = "flight"
	hud.flash_message("Welcome to %s." % Surface.tile_name(pid, t).capitalize())

## Crossing a tile edge. Normally seamless (SUPERSEDES the old "storm on every border"): the next sector was built
## ahead of time, so the ground just continues. Only if it isn't ready yet (very fast flight) a quick cloud pass hides
## the build.
func _on_tile_edge(dir: Vector2i) -> void:
	if state != "flight" or space.surf_busy: return
	var pid: String = space.planet_id
	var nt := Surface.neighbour(pid, space.tile, dir)
	if Surface.is_ready(pid, nt):
		space.shift_tile(dir)
		hud.flash_message(Surface.tile_name(pid, nt).capitalize())
		return
	space.surf_busy = true
	# the border is hidden inside a weather front that suits where you're going
	var front := _weather_front(Surface.PLANETS[pid]["tiles"][nt])
	fx.cloud_tint = front[1]
	fx.warp_color = front[1].lightened(0.3)
	fx.caption = front[0]
	fx.sub = Surface.tile_name(pid, nt)
	Sfx.play("whoosh", -4.0)
	var tw := create_tween()
	tw.tween_property(fx, "clouds", 1.0, 0.35)
	tw.parallel().tween_property(fx, "warp", 0.45, 0.35)
	await tw.finished
	space.shift_tile(dir)
	var tw2 := create_tween()
	tw2.tween_property(fx, "clouds", 0.0, 0.6)
	tw2.parallel().tween_property(fx, "warp", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""
	space.surf_busy = false
	hud.flash_message(Surface.tile_name(pid, space.tile).capitalize())

func _weather_front(biome_id: String) -> Array:
	match biome_id:
		"desert", "canyon", "wasteland": return ["SANDSTORM", Color(0.86, 0.66, 0.44)]
		"ice": return ["SNOW SQUALL", Color(0.9, 0.94, 1.0)]
		"volcanic": return ["ASH CLOUD", Color(0.42, 0.36, 0.34)]
		"mountains": return ["TURBULENCE", Color(0.82, 0.86, 0.92)]
		"industrial": return ["SMOG BANK", Color(0.62, 0.6, 0.55)]
	return ["RAIN SQUALL", Color(0.66, 0.72, 0.8)]

## Climbing past the ceiling: clouds, then space above the same part of the planet.
func leave_atmosphere() -> void:
	if state != "flight": return
	state = "atmosphere"
	var pid: String = space.planet_id
	var t: int = space.tile
	space.controls = false
	hud.visible = false
	fx.caption = "LEAVING ATMOSPHERE"
	fx.sub = Surface.PLANETS[pid]["name"].to_upper()
	Sfx.play("whoosh", -2.0, 0.7)
	var tw := create_tween()
	tw.tween_property(fx, "clouds", 1.0, 0.8)
	await tw.finished
	_load_system(Surface.PLANETS[pid]["system"], "sunorbit" if Surface.is_sun(pid) else "orbit:%d" % t)
	space.controls = false
	var tw2 := create_tween()
	tw2.tween_property(fx, "clouds", 0.0, 1.0)
	await tw2.finished
	fx.caption = ""
	space.controls = true
	hud.visible = true
	state = "flight"
	hud.flash_message(("Clear of %s." if Surface.is_sun(pid) else "Orbit reached above %s.") % Surface.PLANETS[pid]["name"])

## Option B: from a planet hub (orbital port or a town), pick a destination and go straight there.
func descend_to(pid: String, loc_id: String) -> void:
	if state != "hub": return
	var l := Surface.location(pid, loc_id)
	if l.is_empty(): return
	state = "launching"
	hub.visible = false
	fx.fade = 1.0
	fx.caption = "DESCENDING"
	fx.sub = "%s  ·  %s" % [l["name"].to_upper(), l["role"].to_upper()]
	Packs.request("city")
	if not Packs.is_ready("planets"):
		fx.sub = "Receiving surface data…"
		await Packs.wait("planets", 90.0)
	_load_surface(pid, int(l["tile"]))
	visited[loc_id] = true
	await get_tree().create_timer(0.6).timeout
	_launch_sequence(l["name"])
