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
var controls: Controls     # Job J: desktop keyboard + mouse controls and rebinding (scripts/controls.gd)
var settings: Control      # Job J: Settings screen (scripts/settings.gd)
var gate_dock: Control     # Job K: jump-gate docking screen (scripts/gatedock.gd)
var docked_gate: Node3D    # Job K: the gate you are docked to
var jumps := 0             # Job K: jumps started this session (tests: a double tap must not start two)
var jump_log: Array = []   # Job K: [phase, msec, fx.warp, system, ship speed, fx.blur, fx.fade] for the last jump: build, hold, loaded, clear, done

func _ready() -> void:
	apply_render_scale()   # v1.8e
	get_viewport().size_changed.connect(apply_render_scale)
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
	hub.galaxy_requested.connect(func(): galaxymap.open(GS.system_id))   # v3.1: the GALAXY MAP tile on HOME
	hub.descend_requested.connect(descend_to)
	navmap.closed.connect(_on_map_closed)
	navmap.course_set.connect(_on_course)
	navmap.mission_go.connect(_on_map_mission_go)
	GS.changed.connect(_on_gs_changed)
	hud.controls = controls
	controls.hud = hud
	controls.space_ref = func(): return space if state == "flight" and is_instance_valid(space) else null
	controls.action.connect(_on_key_action)
	_build_title()
	settings = load("res://scripts/settings.gd").new()
	settings.controls = controls
	ui.add_child(settings)
	controls.capture_done.connect(_on_capture_done)
	gate_dock = load("res://scripts/gatedock.gd").new()
	ui.add_child(gate_dock)
	gate_dock.activate_pressed.connect(gate_activate)
	gate_dock.undock_pressed.connect(gate_undock)
	_load_system("solara", "station")
	space.controls = false
	# optional content arrives in the background after the game is up (see scripts/packs.gd)
	get_tree().create_timer(1.5).timeout.connect(func(): Packs.queue(Data.PACK_ORDER))   # v1.8t: a few at a time, what you need to play first, the big ones last
	autotest = "--autotest" in OS.get_cmdline_user_args() or _web_flag("autotest")
	if autotest:
		var runner: Node = load("res://scripts/autotest.gd").new()
		runner.main = self
		add_child(runner)

## v1.8e: how much of the screen's resolution the 3D world is drawn at (1 = every pixel).
static func render_scale_for(px: Vector2i) -> float:
	return clampf(sqrt(Data.RENDER_PIXELS_MAX / float(maxi(1, px.x * px.y))), Data.RENDER_SCALE_MIN, 1.0)

var render_scale := 1.0
func apply_render_scale() -> void:
	var vp := get_viewport()
	render_scale = render_scale_for(DisplayServer.window_get_size())
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	var touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios")
	vp.msaa_3d = Viewport.MSAA_DISABLED if touch and render_scale < 0.99 else Viewport.MSAA_2X

func _web_flag(f: String) -> bool:
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		return q is String and (q as String).find(f) >= 0
	return false

## Keyboard + mouse bindings (Job J): the defaults and the player's rebinds live in Controls (data.gd Job J block);
## it builds the InputMap actions (forward, back, strafe_*, yaw_*, pitch_*, fire, transform keep their names).
func _input_map() -> void:
	controls = Controls.new()
	controls.name = "Controls"
	add_child(controls)

# ---------------------------------------------------------------- title
func _build_title() -> void:
	title = load("res://scripts/title.gd").new()
	ui.add_child(title)
	title.start_pressed.connect(start_game)
	title.settings_pressed.connect(func(): settings.open())

func start_game() -> void:
	if state != "title": return
	if OS.has_feature("web"): JavaScriptBridge.eval("window.__hlFullscreen && window.__hlFullscreen()", true)   # v1.5a: full screen (asked from the START tap)
	title.visible = false
	title.release()
	state = "launching"
	var back := GS.load_game()   # v1.7y (owner): pick up where you left off
	if back and GS.system_id != space.sys_id:
		await _load_system(GS.system_id, "station")
		space.controls = false
	GS.restore_full()
	_launch_sequence(str(Data.SYSTEMS[GS.system_id]["station"]["name"]) if back else "Liberty Hub", false)   # v1.7n (owner): no radio call at the very start
	if back: hud.flash_message("Welcome back, %s. Your progress is loaded." % GS.pilot_name if GS.pilot_name != "" else "Welcome back. Your progress is loaded.")
	else: GS.save_game()   # v1.9j: a new pilot's slot is taken at once (the picker shows the name next time)
	await get_tree().create_timer(2.6).timeout
	if state == "flight" and GS.tutorial_seen.is_empty(): hud.flash_message(Data.TUTOR_HINT)   # v1.7r: a quiet hint, no radio noise
	tutor_prefetch()   # (her first clip downloads while you fly)

# ---------------------------------------------------------------- systems
func _load_system(id: String, arrival: String, staged := false) -> void:
	Sfx.keep_until = 0.0   # (a new system: its own lines may speak)
	_new_space("Space_" + id)
	GS.system_id = id
	if state != "title": GS.save_game()   # v1.7y: a new system saves
	if not (id in GS.discovered): GS.discovered.append(id)
	Galaxy.refresh()
	if staged: await space.setup_staged(id, arrival)   # v1.5d: one build step a frame, behind the moving warp
	else: space.setup(id, arrival)
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
	hud.space = null   # v1.5d: the old scene is gone until the new one is connected (a staged load spans several frames)
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
	space.collided.connect(_on_collided)
	space.message.connect(func(t): hud.flash_message(t))
	space.system_used.connect(func(sid, txt): hud.flash_message(txt); hud.pulse(sid))
	space.hail.connect(_on_hail)
	space.enemy_hail.connect(_on_enemy_hail)
	space.enemy_chatter.connect(_on_enemy_chatter)
	space.mission_done.connect(_on_mission_done)   # v1.8w
	hud.space = space

## v1.8w (owner): a job done: the one who pays you calls in on the friendly side to say well done (the coordinator of
## the station that gave the job, in their own face and voice; or that station's dispatch).
func _on_mission_done(said: String) -> void:
	if said == "failed" or Missions.last_paid.is_empty(): return
	var lp: Dictionary = Missions.last_paid
	Missions.last_paid = {}
	if hud.side_busy(false): return   # (you are already talking to someone on that side)
	var gsys: Dictionary = Data.SYSTEMS[str(lp["giver_sys"])]
	var line: String = str(Data.CONGRATS[randi() % Data.CONGRATS.size()]).replace("{pay}", str(int(lp["pay"])))
	var co: Dictionary = Factions.coordinator(Factions.owner_of(gsys["station"], gsys))
	if co.is_empty(): hud.open_comms("%s dispatch" % gsys["station"]["name"], line, "incoming", false)
	else: hud.open_comms("%s — %s" % [co["name"], gsys["station"]["name"]], line, "incoming", false, "gp/" + str(co["id"]), float(co.get("voice", 1.0)), str(co.get("sex", "")) == "female", str(co.get("voice_id", co["id"])))

## Job L: a damaging collision: the red hit flash, longer for harder hits (shake + sound are in space.gd).
func _on_collided(_kind: String, _dmg: float, k: float) -> void:
	hud.damage_flash = maxf(hud.damage_flash, lerpf(Data.COLLIDE_FLASH_MIN, Data.COLLIDE_FLASH_MAX, k))

func _on_gs_changed() -> void:
	if state == "flight" and is_instance_valid(space) and GS.shield < GS.max_shield() and space.shield_delay >= 2.9:
		hud.hurt()

## Which music fits right now (moods: scripts/music.gd; the owner's guide is in docs/DESIGN.md §19).
var _fight_t := 0.0     # seconds since hostiles were last on you
var _calm_t := 0.0      # "calm after a victory" time left
var _kills_seen := 0
func music_mood(dt: float) -> String:
	if state == "title": return "intro"
	Music.set_hub(state == "hub")
	if state == "hub":   # v5.9 (owner): the faction's own music under the hub, quiet (Data.HUB_MUSIC)
		return Music.faction_mood(Data.SYSTEMS.get(GS.system_id, {}).get("faction", "Neutral"), GS.system_id)
	if not is_instance_valid(space) or not is_instance_valid(space.player): return Music.mood
	if state != "flight": return Music.mood          # docking, jumping, map: keep what is playing
	var fighting: bool = space.hostiles_engaged() > 0
	if fighting:
		_fight_t = 0.0
		var bm: String = Music.battle_mood(space.engaged_tier())   # v1.9k (owner): epic music for the big fights
		if Music.mood == "epic": bm = "epic"   # (once epic, it stays epic until the fight is over)
		return bm
	_fight_t += dt
	if Music.is_battle(Music.mood) and _fight_t < 4.0: return Music.mood   # do not drop the battle music for a short gap
	# v1.4l (owner): music by faction; v1.9k: each system opens on its own track of that faction's set
	return Music.faction_mood(Data.SYSTEMS[space.sys_id].get("faction", "Neutral"), space.sys_id)

## v1.9k (owner: GO TO takes me right there): a job's GO TO carries on: at the job's gate it docks and jumps, in the
## next system it flies on, and at the job's station it docks. Steering (the autopilot dropped) ends it.
var _mission_auto := false
func _mission_auto_step() -> void:
	if not _mission_auto or state != "flight" or not is_instance_valid(space): return
	var a: Node3D = space.last_arrived
	space.last_arrived = null
	if space.autopilot != null and is_instance_valid(space.autopilot): return
	if a == null or not is_instance_valid(a):
		_mission_auto = false   # (the pilot took the stick)
		return
	var mw: Dictionary = space.mission_waypoint()
	var k: String = str(a.get_meta("kind", ""))
	if k == "gate" and not mw.is_empty() and int(mw.get("hops", 0)) > 0 and space.gate_in_range():
		if dock_gate(): gate_activate()
		return
	if not mw.is_empty() and mw["node"] == a and k != "gate" and space.dock_candidate() == a:
		_mission_auto = false
		dock(a)
		return
	_mission_auto = false

var _save_t := 0.0
var _escape_t := 0.0
func _process(_dt: float) -> void:
	Music.want(music_mood(_dt))
	_mission_auto_step()
	_escape_t += _dt
	if _escape_t >= 10.0 and state != "title":   # v1.8k: a jailed pilot whose time is up breaks out
		_escape_t = 0.0
		for eid in GS.check_escapes():
			hud.flash_message(GS.last_back_line(str(eid)))
	if state == "flight":   # v1.7y: save every so often in flight
		_save_t += _dt
		if _save_t >= Data.SAVE_EVERY:
			_save_t = 0.0
			GS.save_game()
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
			fx.clouds = pow(k, 1.3) * 0.8   # v1.9z (owner): the air goes white as you go in, not clear like space
			fx.heat = k * clampf(space.speed_now / 90.0, 0.25, 1.0) * 0.7
			if k > 0.0 and is_instance_valid(space.planet):
				var pid: String = space.planet.get_meta("info")["id"]
				fx.cloud_tint = space.atmo_color   # (the planet's own sky colour, pale)
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
		var gw: Dictionary = space.mission_waypoint()   # v1.8m: a ground job comes first down here too
		if not gw.is_empty(): return "MISSION: %s" % gw["line"]
		var has_port: bool = space.station.get_meta("kind", "") == "station"
		return "PLANET: %s  ·  climb above %d m for orbit" % [("dock at " + space.station.name) if has_port else "fly on — the planet wraps around", int(Surface.CEILING)]
	var mw: Dictionary = space.mission_waypoint()   # v1.5a: a mission you carry comes first, with where to go next
	if not mw.is_empty(): return "MISSION: %s" % mw["line"]
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
	return "OBJECTIVE: Explore %s, fight %ss, or leave by the %s" % [space.sys["name"], enemy_name.to_lower(), gt]

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
		"scan": hud.flash_message(hud.start_scan())   # v1.5g
		"scan_close": hud.close_scan()
		"view":
			space.set_view("cockpit" if GS.view == "chase" else "chase")
			hud.flash_message("View: %s" % (("first person: the mech's eyes" if GS.form == "mech" else "first-person cockpit") if GS.view == "cockpit" else "chase camera"))
		"zoom":   # v1.7z: the mech rifle's scope
			hud.flash_message("Scope: ON" if space.toggle_zoom() else "Scope: OFF")
		"stop":
			space.full_stop()
			hud.flash_message("Braking to a full stop.")
		"form":
			match space.start_transform():
				"mech": hud.flash_message("Transforming to MECH… weapons locked for 3 s.")
				"ship": hud.flash_message("Transforming to SHIP… weapons locked for 3 s.")
				"warp": hud.flash_message("Can't transform during warp.")
				"loading": hud.flash_message("Mech frame still downloading — try again in a moment.")
		"fire":   # v1.4l: guns on / off
			space.fire_lock = not space.fire_lock
			hud.flash_message("Guns firing nonstop. Tap FIRE again to stop." if space.fire_lock else "Guns holding fire.")
		"lane":   # v1.4l: dock the trade-lane ring in range, or leave the lane you are in
			if not space.lane.is_empty():
				space.lane_abort()
				hud.flash_message("Left the trade lane.")
			elif not space.lane_enter(): hud.flash_message("No trade-lane ring in range.")
		"kill":
			if GS.form == "mech": hud.flash_message("Mechs don't drift — use BOOST with the stick to dash any direction.")
			elif space.warp_state == "on" and space.toggle_engine_kill(): hud.flash_message("Engines OFF at warp — drifting at warp speed. Turn and shoot; THRUST to restart.")
			elif space.warp_active(): hud.flash_message("Wait for the warp drive to finish spooling.")
			else: hud.flash_message("Engines OFF — drifting. You can still turn and shoot; THRUST restarts them." if space.toggle_engine_kill() else "Engines restarted.")
		"warp":
			match space.request_warp():
				"charging": hud.flash_message("Warp spooling — 5 s. Weapons locked. Keep flying!")
				"atmosphere": hud.flash_message("The warp drive can't run inside an atmosphere.")
				"mech": hud.flash_message("Mechs have no warp drive — transform to SHIP to warp.")
				"busy": hud.flash_message("Finish transforming first.")
				"cancelled": hud.flash_message("Warp charge cancelled. Weapons unlocked.")
				"off": hud.flash_message("Dropped out of warp. Weapons unlocked.")
		"call":   # (v1.8q: no button of its own any more; LOG -> TARGET / CONTROL -> CALL lands here)
			_call_target()
		"met_hail": hud.pick_contact("hail", hail_info())
		"call_pick":   # v1.8q (owner): CALL under the picked face
			var pk: String = hud.pick
			if pk == "hail": _call_target()
			elif pk != "" and hud.in_range(pk): call_character(pk)
			elif pk != "": hud.flash_message("%s is in %s — out of comms range. Only people in this system can be called." % [Data.CHARACTERS[pk]["name"], Data.SYSTEMS[Data.CHARACTERS[pk]["system"]]["name"]])
			if hud.slots["l"].is_empty() and hud.slots["r"].get("mode", "") == "talk": hud.open_chat()   # v1.8s (owner): the text screen comes up on the left for the call
		"chat_close": hud.close_roster()
		"ground":   # v1.8r (owner): gravity on / off
			match space.toggle_ground():
				"on": hud.flash_message("GROUND: walking. THRUST = jump, stick + THRUST = dash." if GS.form == "mech" else "GROUND: coming down to land. THRUST = hop up, stick + THRUST = dash.")
				"off": hud.flash_message("GROUND off: flying.")
				"space": hud.flash_message("GROUND works down on a planet.")
				"warp": hud.flash_message("Drop out of warp first.")
		"lock_a", "lock_c": hud.flash_message("Locked for now.")
		"fullscreen":   # v1.9 (owner): the browser's full screen on / off (hides the address bar where the phone allows it)
			if OS.has_feature("web"): JavaScriptBridge.eval("window.__hlFsToggle && window.__hlFsToggle()", true)
		"pmap_close": hud.planet_map = false
		"log":
			if hud.comms_mode == "roster": hud.close_roster()
			else: hud.open_log()
		"voice":
			hud.flash_message(Sfx.toggle_voice())
			if hud.comms_open: Sfx.speak(hud.comms_line, hud.comms_voice, hud.comms_female, hud.comms_voice_id)
		"hangup":
			if hud.comms_open:
				hud.close_comms()
				hud.flash_message("Call ended.")
		"goto":
			if space.autopilot != null and is_instance_valid(space.autopilot):   # v1.8v: a second tap stops it, whatever it is flying to
				space.autopilot = null
				hud.flash_message("Autopilot off.")
			elif space.target and is_instance_valid(space.target) and space.target.get_meta("kind", "") != "enemy":
				space.autopilot = space.target
				hud.flash_message("Autopilot engaged: %s" % space.target.name)
			elif space.nav_dest != null and is_instance_valid(space.nav_dest):   # v1.7v (owner): the GPS destination picked on the map
				var nd: Node3D = space.nav_dest
				var mwd: Dictionary = space.mission_waypoint()
				_mission_auto = not mwd.is_empty() and mwd["node"] == nd   # v1.9k: the job's waypoint: GO TO goes all the way
				space.route_go()
				if nd.get_meta("kind", "") == "enemy": space.autopilot = space.waypoint_at(nd.global_position)   # (a hostile is flown TO, not docked with)
				hud.flash_message("Autopilot engaged: %s" % nd.name)
			elif not space.mission_waypoint().is_empty():   # v1.5a: nothing picked: fly the mission waypoint
				var mw: Dictionary = space.mission_waypoint()
				var mn: Node3D = mw["node"]
				space.autopilot = mn if mn.get_meta("kind", "") != "enemy" else space.waypoint_at(mn.global_position)   # (a hostile is flown TO, not docked with)
				_mission_auto = true   # v1.9k: through the gates and in to dock, not just to the next stop
				hud.flash_message("Autopilot engaged: %s" % mw["title"])   # (v1.9a: on a planet too: the job's point, the freighter, or the way up)
			elif space.surface_mode and not space.nearest_base().is_empty():   # v1.8y: on a planet: the nearest base, wherever it is
				var nb: Dictionary = space.nearest_base()
				space.set_surface_goal(nb)
				hud.flash_message("Autopilot engaged: %s" % nb["name"])
			else:   # v1.8v (owner: GO TO always takes you somewhere): nothing picked and no job: the station (on a planet: its base), or the way home
				var home: Node3D = space.station if is_instance_valid(space.station) and space.station.get_meta("kind", "") == "station" else null
				if home == null and not space.surface_mode and is_instance_valid(space.gate): home = space.gate
				if home != null:
					space.autopilot = home
					hud.flash_message("Autopilot engaged: %s" % home.name)
				else: hud.flash_message("Nowhere to fly to here: climb out to orbit, or pick a place on the MAP.")
		"objective":   # v1.9k (owner): tap the job line: the waypoint is set and shown; GO TO flies it all the way
			var ow: Dictionary = space.mission_waypoint()
			if not ow.is_empty():
				space.gps_mission = true
				space.set_destination(ow["node"])
				hud.radar_overview = Data.RADAR_OVERVIEW
				hud.flash_message("Waypoint set: %s. Tap GO TO." % ow["title"])
		"nav": open_map()
		"dock":
			var n: Node3D = space.dock_candidate()
			if n: dock(n)
		"jump":   # Job K: the gate prompt docks you to the gate (docking screen), it no longer jumps at once
			if space.gate_in_range(): dock_gate()
		"side_l", "side_r":   # tap a comms screen: the console (log, contacts, type) pulls up
			if hud.comms_mode != "roster": hud.open_chat()   # (v1.8s: the text screen, not the call list)
		"type": hud.start_typing()
		"radar":   # tap the radar: the map, where you can set a course or drop a waypoint; a tap on a blip opens its card
			open_map()
			if state == "map" and hud.radar_pick != Vector3.INF: navmap.select_near(hud.radar_pick)
		_:
			if id.begins_with("pmap_b"):   # v1.8y: a base tapped on the planet map: fly there
				var spots: Array = space.base_spots()
				var bi := int(id.substr(6))
				if bi < spots.size():
					space.set_surface_goal(spots[bi])
					hud.planet_map = false
					hud.flash_message("Autopilot engaged: %s" % spots[bi]["name"])
				return
			if id.begins_with("met_"):
				if id == "met_up" or id == "met_down":   # v1.8r: scroll the call list
					hud.scroll_contacts(-1 if id == "met_up" else 1)
					return
				var k := int(id.substr(4))
				var cid: String = hud.contact_at(k)   # v1.8q (owner): a tap shows the picture with CALL; CALL makes the call
				if cid != "":
					var cc: Dictionary = Data.CHARACTERS[cid]
					hud.pick_contact(cid, {"name": "%s — %s" % [cc["name"], cc["role"]], "face": str(cc.get("face", "")), "ok": hud.in_range(cid),
						"sub": str(Data.SYSTEMS[cc["system"]]["name"]).to_upper() if cc.has("system") else ""})

func _on_capture_done(_id: String, _ok: bool, _note: String) -> void:
	if settings.visible: settings.refresh()

## Job J: a keyboard / mouse action (see Data.KBM_ACTIONS). Reuses the HUD button code so both behave the same.
func _on_key_action(id: String) -> void:
	if id == "settings":
		if settings.visible: settings.close()
		else: settings.open()
		return
	if id in ["map_orient", "map_tilt"] and state in ["flight", "map"]:   # v1.4p: works on the map and in flight (the radar follows)
		if id == "map_orient": NavGrid.toggle_orient()
		else: NavGrid.toggle_tilt()
		if state == "flight": hud.flash_message("Map and radar: %s, %s." % ["heading-up" if NavGrid.orient == "heading" else "north-up", "angled" if NavGrid.tilt == "angled" else "overhead"])
		return
	if state != "flight": return
	match id:
		"mouse_flight": hud.flash_message("Mouse flight %s." % ("ON — the ship steers toward the cursor" if controls.mouse_flight else "OFF — hold left-click and drag to steer"))
		"missile": _on_hud("missile")
		"brake": _on_hud("stop")
		"engine_kill": _on_hud("kill")
		"cruise": _on_hud("warp")
		"target_closest": space.target_closest()
		"target_next": _on_hud("target")
		"dock":   # dock / activate: station or planet in range, otherwise the jump gate in range
			var pr: String = space.prompt()
			if pr == "dock" or pr == "jump": _on_hud(pr)
			elif space.dock_candidate() != null: _on_hud("dock")
			elif not space.lane_candidate().is_empty(): _on_hud("lane")
			else: hud.flash_message("Nothing in docking range.")
		"transform": _on_hud("form")
		"view": _on_hud("view")
		"map": _on_hud("nav")

## v1.8q: who LOG's first row (TARGET / CONTROL) would reach right now, for the picture: the same order _call_target uses.
func hail_info() -> Dictionary:
	var tgt: Node3D = space.target
	if tgt and is_instance_valid(tgt):
		var kind := str(tgt.get_meta("kind", ""))
		if kind in ["enemy", "patrol"] and tgt.has_meta("pilot"):
			var fp: Dictionary = tgt.get_meta("pilot")
			return {"name": str(fp.get("name", tgt.name)), "face": ("gp/" + str(fp["id"])) if fp.has("voice_id") or fp.has("slot") else str(fp.get("face", "")), "ok": true}
		if kind == "enemy": return {"name": tgt.name + " pilot", "face": "", "ok": true}
		if tgt == space.planet and GS.system_id == "solara": return _char_info("oduya")
		for tr in space.traffic:
			if tgt == tr["node"]: return _char_info("rennick")
	if tutor_next() != "": return _char_info(Data.TUTOR_ID)
	return _char_info("vale" if GS.system_id == "solara" else "amari")

func _char_info(id: String) -> Dictionary:
	var c: Dictionary = Data.CHARACTERS[id]
	return {"name": "%s — %s" % [c["name"], c["role"]], "face": str(c.get("face", "")), "ok": true}

## CALL: hail whatever you have targeted, otherwise the local station controller.
func _call_target() -> void:
	var tgt: Node3D = space.target
	if tgt and is_instance_valid(tgt) and tgt.get_meta("kind", "") == "enemy":
		var leader: String = Data.ENEMY_LEADER[space.sys["enemy"]]
		if tgt.has_meta("pilot") and (not (leader in GS.met) or randf() < 0.6): _pilot_call(tgt.get_meta("pilot"), false)
		elif leader in GS.met: call_character(leader)
		else: hud.open_comms(tgt.name + " pilot", space.TAUNTS[randi() % space.TAUNTS.size()], "talk", true)
		return
	if tgt and is_instance_valid(tgt) and tgt.get_meta("kind", "") == "patrol" and tgt.has_meta("pilot"):   # v1.4w: a faction pilot who is not hostile
		var fp: Dictionary = tgt.get_meta("pilot")
		var line: String = Data.ROSTER_HAIL[randi() % Data.ROSTER_HAIL.size()].replace("{name}", str(fp["name"])).replace("{faction}", str(fp.get("faction", "")))
		hud.open_comms(pilot_title(fp), line, "talk", false, "gp/" + str(fp["id"]), float(fp["voice"]), bool(fp["female"]), str(fp.get("voice_id", fp["id"])))
		return
	if tgt and is_instance_valid(tgt) and tgt == space.planet and GS.system_id == "solara":
		call_character("oduya")
		return
	for tr in space.traffic:
		if tgt == tr["node"]:
			call_character("rennick")
			return
	if tutor_next() != "":   # v1.7r (owner): nothing targeted and lessons left: the guide teaches the next one
		_tutor_call()
		return
	call_character("vale" if GS.system_id == "solara" else "amari")

## v1.7r: the next tutorial lesson id ("" when all are done). The intro first; then what is happening around you.
func tutor_next() -> String:
	var now := ""
	if space.hostiles_near(900.0) > 0: now = "hostiles"
	elif space.surface_mode: now = "planet"
	elif space.dock_candidate() != null: now = "dock"
	var first := ""
	for l in Data.TUTORIAL:
		if str(l["id"]) in GS.tutorial_seen: continue
		if Data.TUTOR_VIDEO and not Packs.PACKS.has("tutor_%d" % int(l.get("video", 0))): continue   # (clips: only lessons whose clip has arrived)
		if str(l["id"]) == "intro": return "intro"
		if now != "" and str(l["when"]) == now: return str(l["id"])
		if first == "": first = str(l["id"])
	return first

func _lesson(id: String) -> Dictionary:
	for l in Data.TUTORIAL:
		if str(l["id"]) == id: return l
	return {}

## The lesson's acted clip, if it is here ("" = not yet: the line is spoken instead).
func tutor_clip(l: Dictionary) -> String:
	if not Data.TUTOR_VIDEO: return ""   # v1.8a: pictures and text
	var n := int(l.get("video", 0))
	if n <= 0: return ""
	var pk := "tutor_%d" % n
	if Packs.PACKS.has(pk) and not Packs.is_ready(pk): Packs.request(pk)
	var path := Data.tutor_clip(n)
	return path if (not Packs.PACKS.has(pk) or Packs.is_ready(pk)) and ResourceLoader.exists(path) else ""

## Fetch the next lesson's clip in the background so it is ready when you CALL.
func tutor_prefetch() -> void:
	var l := _lesson(tutor_next())
	if not l.is_empty(): tutor_clip(l)

func _tutor_call() -> void:
	var id := tutor_next()
	var l := _lesson(id)
	var line := str(l["line"])
	var clip := tutor_clip(l)
	GS.tutorial_seen.append(id)
	var c: Dictionary = Data.CHARACTERS[Data.TUTOR_ID]
	if not (Data.TUTOR_ID in GS.met): GS.meet(Data.TUTOR_ID, "friendly")
	on_call = Data.TUTOR_ID
	Sfx.keep_until = 0.0   # (you asked: the lesson may speak)
	hud.open_comms("%s — Tutorial" % c["name"], line, "talk", false,
		c.get("face", ""), float(c.get("voice", 1.0)), bool(c.get("female", false)), Data.TUTOR_ID, clip)
	tutor_prefetch()

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
		c.get("face", ""), float(c.get("voice", 1.0)), bool(c.get("female", false)), id)

func call_character(id: String, incoming := false) -> void:
	var c: Dictionary = Data.CHARACTERS[id]
	if id == Data.TUTOR_ID and not incoming and tutor_next() != "":   # v1.7r: calling her from LOG gives the next lesson too
		_tutor_call()
		return
	if not incoming: on_call = id
	if not (id in GS.met): GS.meet(id, "enraged" if c["lines"].has("enraged") else "friendly")
	var m: String = GS.mood.get(id, "friendly")
	var pool: Array = c["lines"].get(m, c["lines"].values()[0])
	var line: String = pool[randi() % pool.size()]
	if (id == "vale" or id == "amari") and not incoming: line = _comms_line()
	hud.open_comms("%s — %s" % [c["name"], c["role"]], line, "incoming" if incoming else "talk", m == "enraged",
		c.get("face", ""), float(c.get("voice", 1.0)), bool(c.get("female", false)), id)

## First meetings: they join the LOG roster and usually call you.
func _meet(id: String, m: String, call := true) -> void:
	if GS.meet(id, m) and call: call_character(id, true)

func _comms_line() -> String:
	var n := space.hostiles_near(900.0)
	if n > 0: return "[serious]Pilot, %d hostile%s on your scope. Weapons free — stay sharp." % [n, "" if n == 1 else "s"]
	if space.in_nebula > 0.0: return "[serious]We're losing your signal in the nebula. Sensors will be short-ranged in there."
	if space.in_belt: return "[serious]Rocks everywhere out there. Throttle down and watch your hull."
	if GS.hull < GS.max_hull() * 0.5: return "[sad]You're leaking plasma. Dock with us for free repairs."
	var o := _objective().replace("OBJECTIVE: ", "").replace("MISSION: ", "")
	return "[normal]Traffic control here. Recommended: %s." % o.to_lower()

func open_map() -> void:
	if space.surface_mode:   # v1.8y (owner): on a planet the map is the planet: its sectors, the bases, you and the job
		hud.planet_map = not hud.planet_map
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

## v1.9p (owner): GO beside CURRENT MISSION on the map: back to flying, and the autopilot flies the whole job
## (through its gates, in to dock), like GO TO.
func _on_map_mission_go() -> void:
	_on_map_closed()
	var mw: Dictionary = space.mission_waypoint()
	if mw.is_empty(): return
	var mn: Node3D = mw["node"]
	space.gps_mission = true
	space.set_destination(mn)
	space.autopilot = mn if mn.get_meta("kind", "") != "enemy" else space.waypoint_at(mn.global_position)
	_mission_auto = true
	hud.flash_message("Autopilot engaged: %s. %s" % [mw["title"], mw["line"]])

func _on_course(n: Node3D) -> void:
	_on_map_closed()
	space.target = n
	space.autopilot = n
	space.set_destination(n)   # v1.5i: the GPS follows it even after you take the stick
	space.gps_mission = false   # (your own course: the GPS stops following the job)
	hud.flash_message("Course set: %s. Autopilot engaged — steer to cancel." % n.name)

func _unhandled_input(e: InputEvent) -> void:
	# any manual aim cancels autopilot
	if state == "flight" and space.autopilot != null and hud.aim_vec.length() > 0.35:
		space.autopilot = null
		hud.flash_message("Autopilot off.")

## An enemy pilot (face from the enemy dossiers) taunts you over the radio.
func _pilot_call(p: Dictionary, incoming := true) -> void:
	if not p.has("lines"):   # a generic wing pilot: no personal lines, they answer with squad chatter
		var ch: Array = Data.CHATTER["target_acquired"]
		hud.open_comms(pilot_title(p), ch[randi() % ch.size()],
			"incoming" if incoming else "talk", true, "gp/" + str(p["id"]), float(p["voice"]), bool(p["female"]), str(p.get("voice_id", p["id"])))
		return
	var lines: Array = p["lines"]
	hud.open_comms("%s — Unit %s" % [p["name"], p["unit"]], lines[randi() % lines.size()], "incoming" if incoming else "talk", true,
		p["face"], float(p["voice"]), bool(p["female"]), str(p["face"]))

## The name line over a pilot's face: roster people by name and rank, the old generic wing pilots as before.
static func pilot_title(p: Dictionary) -> String:
	if p.has("character_id"): return "%s — %s · %s" % [p["name"], p["type"], p.get("faction", "")]
	return "%s — %s pilot · %s's wing" % [p["unit"], p["type"], p.get("leader", "?")]

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
	hud.open_comms(pilot_title(p), line, "incoming", true,
		"gp/" + p["id"], float(p["voice"]), bool(p["female"]), str(p.get("voice_id", p["id"])))
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
	if not space.opening_rule().is_empty(): return   # v1.5k: no story leader calls in from the opening fight
	var leader: String = Data.ENEMY_LEADER[space.sys["enemy"]]
	if not (leader in GS.met): _meet.call_deferred(leader, "enraged")

# ---------------------------------------------------------------- docking / hub / launch
## v5.8 (owner): nothing from flight (atmosphere smoke, heat, tunnel streaks) carries on into the hub
func clear_fx() -> void:
	fx.clouds = 0.0
	fx.heat = 0.0
	fx.warp = 0.0
	fx.blur = 0.0
	fx.flash = 0.0
	fx.caption = ""
	fx.sub = ""
	fx.queue_redraw()

func dock(n: Node3D) -> void:
	if state != "flight": return
	state = "docking"
	space.controls = false
	space.autopilot = null
	space.drop_warp()
	hud.visible = false
	var info: Dictionary = n.get_meta("info")
	docked_node_kind = info["kind"]
	space.launch_from = n if n.has_meta("dock") else null   # v1.9d: launch again from the 3D station you docked at
	fx.caption = "DOCKING"
	fx.sub = info["name"].to_upper()
	var p: Node3D = space.player
	var approach: Vector3 = space.dock_point(n)
	var inside: Vector3 = n.global_position + Vector3(0, 0, 44) if info["kind"] == "station" else n.global_position + (approach - n.global_position).normalized() * (float(n.get_meta("radius")) + 4.0)
	var tw := create_tween()
	tw.tween_method(func(k: float): _fly_along(p, approach, k), 0.0, 1.0, 1.6)
	tw.tween_method(func(k: float): _fly_along(p, inside, k), 0.0, 1.0, 1.2)
	tw.parallel().tween_property(fx, "fade", 1.0, 1.0).set_delay(0.3)
	tw.parallel().tween_property(fx, "clouds", 0.0, 1.0)   # v5.8 (owner): the atmosphere haze clears as you dock
	tw.parallel().tween_property(fx, "heat", 0.0, 1.0)
	await tw.finished
	clear_fx()
	space.visible = false
	space.process_mode = Node.PROCESS_MODE_DISABLED
	GS.dock_service()   # v1.4n: shields and energy only; hull = REPAIR, ammo = RESTOCK at Equipment
	GS.last_base = info["id"]
	visited[info["id"]] = true
	if info["id"] == "new_terra": GS.meet("oduya", "friendly")
	if info["id"] == "frontier_exchange": GS.meet("amari", "friendly")
	if info["id"] == "liberty_hub" and GS.kills > 0: visited["liberty_hub_2"] = true
	hub.open(info)
	var wk: String = str(info.get("kind", "station"))   # v1.8k: where they are handed in sets how long they stay locked up
	var home_free: String = prisoner_home(info)   # v1.9o (owner): a prisoner brought to their own people walks free
	var was_job: Dictionary = GS.mission.duplicate()
	var was_bounty: Dictionary = GS.bounty.duplicate()
	var paid: String = Missions.claim_at(info["id"], wk) if not GS.mission.is_empty() else GS.claim_bounty(wk)   # v1.5f: a board bounty is paid where it was taken; an old-style one anywhere
	if paid != "":
		hub.status.text = paid
		hub._refresh_credits()
		if str(was_job.get("kind", "")) == "bounty" and GS.mission.is_empty(): bounty_thanks(info, was_job, was_bounty)
	if home_free != "":
		hub.show_screen("bounty")
		hub.status.text = home_free
	GS.save_game()   # v1.7y: docking saves
	state = "hub"
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""

## v1.9o (owner: "if I bring a prisoner into their home world, they're gonna be on me"): docking with a prisoner at a
## base of the prisoner's own faction: their people free them, the job is lost, that faction turns hostile (so the
## board there is locked: they don't want your business) and the freed pilot comes after you when you launch.
var chaser := ""   # the roster id of a freed prisoner who hunts you on the next launch
func prisoner_home(info: Dictionary) -> String:
	if GS.bounty.get("state", "") != "captured": return ""
	var id := str(GS.bounty.get("id", ""))
	var p: Dictionary = Data.roster_pilot(id)
	var fac := str(p.get("faction", ""))
	var own: String = Factions.owner_of(info, Data.SYSTEMS[GS.system_id])
	if fac == "" or own != fac: return ""
	Missions.release_captive()
	Missions.abandon()
	GS.bounty = {}
	if Factions.has(fac): Factions.adjust(fac, -(Factions.standing(fac) - Data.PRISONER_HOME_STANDING))   # (down to hostile)
	chaser = id
	var line := "%s's people pull %s out of your hold: this is their home. The job is lost, %s don't want your business, and %s is coming after you." % [fac, str(p.get("name", "the pilot")), fac, str(p.get("name", "the pilot"))]
	Sfx.read_aloud(line)
	return line

## v1.9k (owner): handing a captive in: the one who posted the bounty says well done, pays, and points you at the
## board for the next job (the board opens on the bounties).
var last_thanks := ""
func bounty_thanks(info: Dictionary, job: Dictionary, b: Dictionary) -> void:
	var who: String = str(Data.roster_pilot(str(job.get("id", b.get("id", "")))).get("name", "the pilot"))
	var pilot: String = str(GS.pilot_name) if str(GS.pilot_name) != "" else "pilot"
	var line: String = Data.BOUNTY_THANKS.format({"pilot": pilot, "target": who, "pay": int(job.get("pay", 0))})
	last_thanks = line
	var plain: String = line.replace("[smile]", "")
	var co: Dictionary = Factions.coordinator(Factions.owner_of(info, Data.SYSTEMS[GS.system_id]))
	if co.is_empty(): Sfx.speak(plain, 1.0, false, "")
	else: Sfx.play_character_voice(str(co.get("voice_id", co["id"])), "", line, float(co.get("voice", 1.0)), str(co.get("sex", "")) == "female")
	hub.board_tab = "bounty"
	hub.show_screen("bounty")
	hub.status.text = ("%s: " % co["name"] if not co.is_empty() else "") + plain

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
	space.spawn_bounty()   # v1.4q: a bounty just accepted for this very system
	if chaser != "":   # v1.9o: the freed prisoner and a wing come after you
		space.spawn_chaser(chaser)
		chaser = ""
	_launch_sequence(where, GS.mission.is_empty())   # v1.7n: with a job, the brief is read, not cut off by control
	var mw: Dictionary = space.mission_waypoint()
	if not mw.is_empty():
		hud.flash_message("Waypoint set: %s. GO TO flies it." % mw["title"])
		space.gps_mission = true   # v1.7o: the GPS follows the job, and the radar shows the way for a moment
		space.set_destination(mw["node"])
		hud.radar_overview = Data.RADAR_OVERVIEW
	if not GS.mission.is_empty():   # v1.5f: the dispatcher repeats the brief on the comms panel
		var gsys: Dictionary = Data.SYSTEMS[GS.mission["giver_sys"]]
		var co: Dictionary = Factions.coordinator(Factions.owner_of(gsys["station"], gsys))   # v1.5l: the coordinator gives the brief, in their own voice
		if co.is_empty(): hud.open_comms("%s dispatch" % gsys["station"]["name"], str(GS.mission["brief"]), "incoming", false)
		else: hud.open_comms("%s — %s" % [co["name"], gsys["station"]["name"]], str(GS.mission["brief"]), "incoming", false, "gp/" + str(co["id"]), float(co.get("voice", 1.0)), str(co.get("sex", "")) == "female", str(co.get("voice_id", co["id"])))
		Sfx.keep_until = Time.get_ticks_msec() / 1000.0 + clampf(str(GS.mission["brief"]).length() / 13.0, 3.0, 25.0)   # v1.7n: nothing talks over the brief

func _launch_sequence(where: String, greet := true) -> void:
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
	if not greet: return
	if ctl in GS.met: hud.open_comms("%s — %s" % [Data.CHARACTERS[ctl]["name"], Data.CHARACTERS[ctl]["role"]], "[smile]You're clear, pilot. " + _comms_line().substr(_comms_line().find("]") + 1), "incoming", false,
		Data.CHARACTERS[ctl].get("face", ""), float(Data.CHARACTERS[ctl].get("voice", 1.0)), bool(Data.CHARACTERS[ctl].get("female", false)), ctl)
	else: _meet(ctl, "friendly")

# ---------------------------------------------------------------- jump gates
## Job K: dock to the jump gate in range: the ship stops at the gate and the docking screen opens (destination,
## ACTIVATE JUMP, UNDOCK). The world waits behind the screen, like a station hub.
func dock_gate() -> bool:
	if state != "flight" or not space.gate_in_range(): return false
	state = "gate_dock"
	space.controls = false
	space.autopilot = null
	space.drop_warp()
	space.vel = Vector3.ZERO
	hud.visible = false
	docked_gate = space.near_gate()
	var info: Dictionary = docked_gate.get_meta("info")
	space.process_mode = Node.PROCESS_MODE_DISABLED
	gate_dock.open(docked_gate.name, Data.SYSTEMS[info["to"]]["name"], "%s gate" % str(info.get("gkind", "jump")))
	return true

## Job K: UNDOCK on the docking screen: back to flight at the gate, no jump.
func gate_undock() -> void:
	if state != "gate_dock": return
	gate_dock.close()
	space.process_mode = Node.PROCESS_MODE_INHERIT
	space.controls = true
	hud.visible = true
	state = "flight"
	hud.flash_message("Undocked from %s." % docked_gate.name)

## Job K: ACTIVATE JUMP. Only from the docking screen, and only once (the state changes at once).
func gate_activate() -> void:
	if state != "gate_dock": return
	gate_dock.close()
	space.process_mode = Node.PROCESS_MODE_INHERIT
	jump(docked_gate)

func _jlog(phase: String) -> void:
	var spd: float = space.vel.length() if is_instance_valid(space) else 0.0
	jump_log.append([phase, Time.get_ticks_msec(), fx.warp, GS.system_id, spd, fx.blur, fx.fade])

## Job K: the warp tunnel at strength k (0..1): streaks, blur and shake together (values in the Job K config block).
func _tunnel(k: float) -> void:
	fx.warp = k if fx.skin == "tunnel" else clampf(k * 3.0, 0.0, 1.0)   # v1.4x: the cloud and the tear fade in early, then speed up
	fx.pace = k * k if fx.skin != "tunnel" else k                       # slow booms first, then fast
	fx.blur = Data.JUMP_BLUR * k
	if is_instance_valid(space): space.hit_shake = maxf(space.hit_shake, Data.JUMP_SHAKE * k * (1.0 if fx.skin == "tunnel" else 0.5))

## Job AB: the last jump's look and what it did (tests).
var jump_look := ""
var jump_booms := 0

## Jump through a gate (Job K flow): the tunnel builds over JUMP_TUNNEL_BUILD while the ship pushes through the
## gate, holds at full while the next system loads behind it (at least JUMP_TUNNEL_HOLD_MIN, longer if the load
## takes longer), then snaps clear over JUMP_TUNNEL_CLEAR as the ship is launched out. Nothing is saved mid-jump.
func jump(gate: Node3D = null) -> void:
	if state != "gate_dock" and state != "flight": return
	state = "jumping"
	jumps += 1
	jump_log = []
	space.controls = false
	space.autopilot = null
	space.drop_warp()
	hud.visible = false
	if gate == null or not is_instance_valid(gate): gate = space.near_gate()
	var to: String = gate.get_meta("info")["to"]
	var from: String = GS.system_id
	var reduced: bool = controls.reduced_effects
	var p: Node3D = space.player
	var through: Vector3 = gate.global_position - gate.global_basis.z * Data.JUMP_PUSH     # on through the jump rings
	# v1.4x: one warp effect, three looks, chosen by the kind of gate
	var look: String = Data.WARP_SKINS.get(str(gate.get_meta("info").get("gkind", "jump")), "tunnel")
	jump_look = look
	fx.begin_warp(look)
	var here: Dictionary = space.sys
	fx.set_skies(space.sky_texture(), null, [here["star"], here["nebula"]["color"], Data.SYSTEMS[to]["star"], Data.SYSTEMS[to]["nebula"]["color"]])
	var build_t: float = Data.WARP_BUILD[look]
	var clear_t: float = Data.WARP_CLEAR[look]
	if Data.WARP_RINGS[look]: space.show_jump_rings(Data.SYSTEMS[to]["star"], 240.0, gate)
	else: through = p.global_position - p.global_basis.z * 40.0   # the rift opens where you are: no rings to fly
	fx.warp_color = Data.SYSTEMS[to]["star"]
	fx.caption = "JUMP IN PROGRESS"
	fx.sub = "%s  >  %s" % [space.sys["name"].to_upper(), Data.SYSTEMS[to]["name"].to_upper()]
	_jlog("build")
	var tw := create_tween()
	tw.tween_method(func(k: float): _fly_along(p, through, k), 0.0, 1.0, build_t)
	if reduced: tw.parallel().tween_property(fx, "fade", 1.0, Data.JUMP_REDUCED_FADE)
	else: tw.parallel().tween_method(_tunnel, 0.0, 1.0, build_t)
	await tw.finished
	_jlog("hold")
	var hold_end := Time.get_ticks_msec() + int(Data.JUMP_TUNNEL_HOLD_MIN * 1000.0)
	while Time.get_ticks_msec() < hold_end:
		if not reduced: _tunnel(1.0)
		await get_tree().process_frame
	await get_tree().process_frame   # the full tunnel is on screen before the load starts
	if not reduced: _tunnel(1.0)
	await _load_system(to, "gate:" + from, true)   # v1.5d: built one step a frame; the warp keeps moving over it
	space.controls = false
	if not reduced: _tunnel(1.0)
	fx.set_skies(null, space.sky_texture(), [here["star"], here["nebula"]["color"], Data.SYSTEMS[to]["star"], Data.SYSTEMS[to]["nebula"]["color"]])   # the far side of the tear
	await get_tree().process_frame   # the new system is built and drawn once, still behind the tunnel
	await get_tree().process_frame   # (and the long load frame's time step is used up, so the clear isn't skipped)
	_jlog("loaded")
	fx.caption = "ARRIVING"
	fx.sub = "%s SYSTEM  ·  %s" % [Data.SYSTEMS[to]["name"].to_upper(), Data.SYSTEMS[from]["name"].to_upper() + " GATE"]
	# launched out of the gate ("boom"): a burst of speed along the nose and a white flash
	space.vel = -space.player.global_basis.z * float(GS.ship()["speed"]) * Data.JUMP_LAUNCH_MULT
	fx.flash = float(Data.WARP_FLASH[look]) / maxf(Data.JUMP_FLASH_ALPHA, 0.01)   # v1.4x: the cloud and the tear arrive smoothly, no white flash
	Sfx.play("warp_go", -4.0)
	_jlog("clear")
	var tw2 := create_tween()
	if reduced: tw2.tween_property(fx, "fade", 0.0, Data.JUMP_REDUCED_FADE)
	else: tw2.tween_method(_tunnel, 1.0, 0.0, clear_t).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE if look != "tunnel" else Tween.TRANS_LINEAR)
	tw2.parallel().tween_property(fx, "flash", 0.0, Data.JUMP_LAUNCH_FLASH)
	await tw2.finished
	if not reduced: _tunnel(0.0)
	jump_booms = fx.booms
	fx.end_warp()
	fx.flash = 0.0
	fx.caption = ""
	space.controls = true
	hud.visible = true
	state = "flight"
	_jlog("done")
	hud.flash_message("Welcome to %s." % Data.SYSTEMS[to]["name"])
	if _mission_auto:   # v1.9k: the job's GO TO flies on in the new system
		var mw: Dictionary = space.mission_waypoint()
		if mw.is_empty(): _mission_auto = false
		else:
			var mn: Node3D = mw["node"]
			space.gps_mission = true
			space.set_destination(mn)
			space.autopilot = mn if mn.get_meta("kind", "") != "enemy" else space.waypoint_at(mn.global_position)
			hud.flash_message("Welcome to %s. Autopilot: %s" % [Data.SYSTEMS[to]["name"], mw["title"]])

# ---------------------------------------------------------------- defeat
func _on_destroyed() -> void:
	if state != "flight": return
	state = "dead"
	hud.visible = false
	fx.caption = "SHIP DISABLED"
	fx.sub = "Rescue tug inbound — towing you to %s" % space.sys["station"]["name"]
	if not GS.mission.is_empty(): fx.sub = "MISSION FAILED — it restarts from the beginning.   " + fx.sub   # v1.9r
	var tw := create_tween()
	tw.tween_property(fx, "fade", 1.0, 2.0).set_delay(1.0)
	await tw.finished
	var lost := int(GS.credits * 0.1)
	GS.credits -= lost
	GS.restore_full()
	var failed := Missions.restart_after_death()   # v1.9r: the job fails and starts again from the beginning
	if space.surface_mode or failed != "": _load_system(space.sys_id, "station")   # (a fresh system: the job's old wave is gone)
	space.visible = false
	space.process_mode = Node.PROCESS_MODE_DISABLED
	space.controls = true
	var info: Dictionary = space.sys["station"].duplicate()
	docked_node_kind = "station"
	clear_fx()
	hub.open(info)
	hub.status.text = "Towed in. Repairs complete. Salvage fee: %d credits.%s" % [lost, ("  " + failed) if failed != "" else ""]
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
	tw.parallel().tween_property(fx, "clouds", maxf(0.55, fx.clouds), 1.2)   # (v1.9z: never thins out again on the way in)
	tw.parallel().tween_method(func(k: float): space.hit_shake = 0.35 + 0.4 * k, 0.0, 1.0, 1.4)
	tw.tween_property(fx, "clouds", 1.0, 0.5)
	await tw.finished
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
	_load_system(Surface.PLANETS[pid]["system"], "sunorbit" if Surface.is_sun(pid) else "orbit:%d:%s" % [t, pid])
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
	if not Packs.is_ready("planets"):
		fx.sub = "Receiving surface data…"
		await Packs.wait("planets", 90.0)
	_load_surface(pid, int(l["tile"]))
	visited[loc_id] = true
	await get_tree().create_timer(0.6).timeout
	_launch_sequence(l["name"])
