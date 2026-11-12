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
	hub.creator_finished.connect(finish_creator)   # v12.90
	hub.escape_requested.connect(start_escape)   # v12.30
	hub.map_requested.connect(func(): navmap.open(null))
	hub.galaxy_requested.connect(func(): galaxymap.open(GS.system_id))   # v3.1: the GALAXY MAP tile on HOME
	hub.descend_requested.connect(descend_to)
	hub.walk_requested.connect(func(id: String): open_station_interior(id, true))   # v13.02: WALK THE STATION (rebuilt stations)
	hub.interior_requested.connect(open_ship_interior)   # v12.97: a fleet ship's DECK PLAN (ShipInterior)
	navmap.closed.connect(_on_map_closed)
	navmap.wild_toggle.connect(func(): if is_instance_valid(space) and space.surface_mode: wild_test_here(not space.wild_park))
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
	if (not back or not GS.creator_done) and (not autotest or OS.get_environment("HL_CREATOR") != ""):   # v12.90 (owner): a new pilot makes their character first
		open_creator()
		return
	_launch_sequence(str(Data.SYSTEMS[GS.system_id]["station"]["name"]) if back else "Liberty Hub", false)   # v1.7n (owner): no radio call at the very start
	if back: hud.flash_message("Welcome back, %s. Your progress is loaded." % GS.pilot_name if GS.pilot_name != "" else "Welcome back. Your progress is loaded.")
	else: GS.save_game()   # v1.9j: a new pilot's slot is taken at once (the picker shows the name next time)
	await get_tree().create_timer(2.6).timeout
	if state == "flight" and GS.tutorial_seen.is_empty(): hud.flash_message(Data.TUTOR_HINT)   # v1.7r: a quiet hint, no radio noise
	if wild_test_flag() and state == "flight": start_wild_test()

## v12.90 (owner: "when you start off, you name your character and then you go into picking your character and setting
## up the clothes"): the PILOT CREATOR. The new pilot starts docked at the station, in the Pilot Gear Store in creator
## mode (who you are, then helmet, uniform, booster, gear); START FLYING launches the game as usual.
func open_creator() -> void:
	GS.creator_done = false
	GS.save_game()   # (the slot is taken at once; quit half way and the creator opens again next time)
	var n: Node3D = space.station
	var info: Dictionary = n.get_meta("info") if n != null and n.has_meta("info") else {}
	space.controls = false
	space.visible = false
	space.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	docked_node_kind = str(info.get("kind", "station"))
	space.launch_from = n if n != null and n.has_meta("dock") else null
	GS.last_base = str(info.get("id", GS.last_base))
	hub.open(info)
	state = "hub"
	hub.start_creator()

func finish_creator() -> void:
	GS.creator_done = true
	GS.save_game()
	hub.status.text = ""
	launch()

## (v12.41) the wildlife test area: ?wildtest on the web, HL_WILDTEST / --wildtest on a PC.
func wild_test_flag() -> bool:
	return _web_flag("wildtest") or OS.get_environment("HL_WILDTEST") != "" or "--wildtest" in OS.get_cmdline_user_args()

## v12.44: every species round you on this world (or back to normal): the wildlife is made again with the park on / off.
func wild_test_here(on: bool) -> void:
	if space == null or not space.surface_mode: return
	space.wild_park = on
	if space.wildlife != null and is_instance_valid(space.wildlife): space.wildlife.queue_free()
	space.wildlife = null
	hud.flash_message("WILDLIFE TEST ON - every animal is round you. Walk up, shoot near them, watch what they do." if on else "Wildlife test off.")

## Down onto Eden Prime's jungle with every species at its spot round you (Data.WILDLIFE_PARK).
func start_wild_test() -> void:
	_load_surface("eden_prime", 0)
	space.wild_park = true
	hud.flash_message("WILDLIFE TEST AREA - every animal is round you. Walk up, shoot near them, watch what they do.")
	tutor_prefetch()   # (her first clip downloads while you fly)

# ---------------------------------------------------------------- systems
func _load_system(id: String, arrival: String, staged := false) -> void:
	Sfx.keep_until = 0.0   # (a new system: its own lines may speak)
	_new_space("Space_" + id)
	if id != GS.system_id: dock_ban.clear()   # v12.30: leaving the star system lifts a docking ban
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
	space.board_request.connect(board_battleship)   # v11.45
	space.facility_request.connect(enter_facility)   # v11.96
	space.board_exit.connect(leave_boarding)
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
	if state != "hub": Music.duck(false)   # (v11.97: never left quiet after a briefing)
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
	if state != "flight" or not is_instance_valid(space): return
	if not _mission_auto:
		_auto_dock_step()
		return
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

## v12.62 (owner: "GO TO a planet ... it will dock on the planet as the autopilot; or anywhere else"): a course you
## set ends docked: at a station, a planet's landing field, a platform, or a dock down on a world.
func _auto_dock_step() -> void:
	var a: Node3D = space.last_arrived
	if a == null: return
	space.last_arrived = null
	var spot: Dictionary = space.arrived_spot
	space.arrived_spot = {}
	var want: Node3D = space.autodock_target
	if not Data.AUTOPILOT_DOCK or want == null or not is_instance_valid(want) or a != want: return
	if space.autopilot != null and is_instance_valid(space.autopilot): return
	space.autodock_target = null
	var dc: Node3D = space.dock_candidate()
	if space.surface_mode:
		if str(spot.get("id", "")) == "" or dc == null: return   # (a facility or a job point: you just arrive)
		hud.flash_message("Autopilot: docking at %s." % str(spot.get("name", dc.name)))
		dock(dc)
		return
	if dc != null and (dc == a or a.get_meta("kind", "") in ["planet", "station"]):
		hud.flash_message("Autopilot: docking at %s." % dc.name)
		dock(dc)

var _save_t := 0.0
var _escape_t := 0.0
func _process(_dt: float) -> void:
	Music.want(music_mood(_dt))
	_mission_auto_step()
	_board_job_step(_dt)
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
		_check_space_edge()
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

## v12.97 (owner brief, job 2): walk a fleet ship's main deck on foot, built from its official HoloDeck plan.
## Opened from the station's ship dealer (FACTION FLEET list, DECK PLAN). A separate 3D world over everything; the
## flight scene and the hub stay as they were and come back on LEAVE SHIP.
## PROPOSAL (not wired): boarding a friendly fleet ship in flight (a docked visitor, see SpaceSystem.fleet_visitors)
## could open this same stage: on the dock prompt, if ShipInterior.can_open(visitor id) -> open_ship_interior(id)
## instead of the station hub. Left for the owner to decide; docking to a station is unchanged.
var ship_deck: ShipInterior
var _deck_layer: CanvasLayer
var _deck_from := ""
func open_ship_interior(id: String) -> bool:
	if is_instance_valid(ship_deck): return false
	var st := ShipInterior.create(id)
	if st == null:
		hud.flash_message("No deck plan for that ship yet.")
		return false
	ship_deck = st
	_deck_from = state
	_deck_layer = CanvasLayer.new()
	_deck_layer.layer = 60
	add_child(_deck_layer)
	_deck_layer.add_child(st)
	hud.visible = false
	hub.visible = false
	state = "ship_deck"
	st.left.connect(_close_ship_interior)
	return true

func _close_ship_interior() -> void:
	state = _deck_from if _deck_from != "" else "hub"
	if state == "hub": hub.visible = true
	else: hud.visible = true
	if is_instance_valid(_deck_layer): _deck_layer.queue_free()
	ship_deck = null

## v13.02 BOARDING missions (BoardingJobs; the job itself is hub.board_job). In flight in the job's system the ship is
## out there with its fighters and a waypoint on it; reach it and you are aboard (its deck plan, with the job's deck
## mission running); finish and leave by the hangar and you are paid, leave early and it is still there.
var board_ship: Node3D
var board_escort: Array = []
var _board_cd := 0.0
func board_job() -> Dictionary: return hub.board_job if is_instance_valid(hub) else {}
func _board_job_step(dt: float) -> void:
	_board_cd = maxf(0.0, _board_cd - dt)
	var j := board_job()
	if is_instance_valid(space):   # v13.10: the job shows on the GPS and the map like any mission (gold waypoint)
		var was: bool = not space.board_mission.is_empty()
		space.board_mission = {} if j.is_empty() else {"sys": str(j["sys"]), "title": str(j["title"]), "node": board_ship if is_instance_valid(board_ship) else null, "power": board_power()}
		if not was and not j.is_empty() and state == "flight":
			space.gps_mission = true
			var mw0: Dictionary = space.mission_waypoint()
			if not mw0.is_empty(): space.set_destination(mw0["node"])
	if j.is_empty() or state != "flight" or not is_instance_valid(space) or space.surface_mode or str(j["sys"]) != str(space.sys_id) or space.sys_id != GS.system_id:
		if j.is_empty() and is_instance_valid(board_ship): board_ship.queue_free()
		return
	if is_instance_valid(ship_deck) or is_instance_valid(station_deck): return
	if not is_instance_valid(board_ship):
		_board_job_spawn(j)
		return
	# your laser shots that reach the hull take its power down (100% -> 50%: the shield fails and stays down)
	# v13.10 (owner: "I couldn't board their ship"): a shot counts anywhere on the hull (its box), not only near the
	# middle, and you board anywhere along the hull once the shield is down.
	if board_power() > 50.0:
		for b in space.bolts:
			if str(b.get("owner", "")) != "player" or float(b.get("life", 0.0)) <= 0.0 or not is_instance_valid(b["node"]): continue
			if board_hull_dist((b["node"] as Node3D).global_position) < 12.0:
				b["life"] = 0.0
				board_damage(float(b.get("dmg", 1.0)))
	var near: bool = is_instance_valid(space.player) and board_hull_dist(space.player.global_position) < BoardingJobs.BOARD_RANGE
	if near and _board_cd <= 0.0:
		if board_power() <= 50.0: _board_enter(j)
		else:
			_board_cd = 5.0
			hud.flash_message("SHIELDS UP: you can't board yet. Shoot the ship down to 50%% power (now %d%%)." % int(ceil(board_power())))
## How far a point is from the target ship's hull box (0 = on or inside it).
func board_hull_dist(p: Vector3) -> float:
	if not is_instance_valid(board_ship): return INF
	var hh: Vector3 = board_ship.get_meta("hit_half", Vector3.ONE * float(board_ship.get_meta("radius", 200.0)) * 0.6)
	var lp: Vector3 = board_ship.global_transform.affine_inverse() * p
	return Vector3(maxf(absf(lp.x) - hh.x, 0.0), maxf(absf(lp.y) - hh.y, 0.0), maxf(absf(lp.z) - hh.z, 0.0)).length()
## The target ship's power, 100 down to 50 (%).
func board_power() -> float: return float(board_ship.get_meta("power", 100.0)) if is_instance_valid(board_ship) else 100.0
## Laser damage on the target ship. At 50% the shield fails for good.
func board_damage(dmg: float) -> void:
	if not is_instance_valid(board_ship) or board_power() <= 50.0: return
	var hp: float = float(BoardingJobs.SHIELD_HP.get(str(board_job().get("class", "")), 600.0))
	var pw: float = maxf(50.0, board_power() - 50.0 * dmg / hp)
	board_ship.set_meta("power", pw)
	var lb := board_ship.get_node_or_null("PowerLabel") as Label3D
	if lb != null:
		lb.text = ("POWER %d%%  ·  SHIELD UP" % int(ceil(pw))) if pw > 50.0 else "POWER 50%  ·  SHIELD DOWN  ·  BOARD NOW"
		lb.modulate = Color(0.5, 0.85, 1.0) if pw > 50.0 else Color(0.45, 1.0, 0.55)
	if pw <= 50.0:
		_board_cd = 0.0
		hud.flash_message("SHIELD DOWN: the ship is at 50% power and can't raise it again. Fly to the hull to board.")
func _board_job_spawn(j: Dictionary) -> void:
	var e: Dictionary = FleetCatalog.get_entry(str(j["id"]))
	if e.is_empty() or not is_instance_valid(space.station): return
	var clouds: Array = []
	for nb in space.nebulae:
		if nb is Dictionary and (nb as Dictionary).has("center"): clouds.append({"center": nb["center"], "radius": float((nb as Dictionary).get("radius", 0.0))})
	var pts: Array = BoardingJobs.points(str(j["sys"]), space.station.global_position, clouds)
	var pt: Dictionary = pts[clampi(int(j.get("pt", 0)), 0, pts.size() - 1)]
	board_ship = SpaceSystem._fleet_standin(e)
	board_ship.name = str(e["name"]).validate_node_name()   # v13.10: its own name on the GPS (it is the mission)
	board_ship.set_meta("kind", "board_target")
	space.add_child(board_ship)
	board_ship.global_position = pt["pos"]
	board_ship.rotation.y = float(absi(hash(str(j["id"]))) % 628) / 100.0
	board_ship.set_meta("power", 100.0)
	var lb := Label3D.new()
	lb.name = "PowerLabel"
	lb.text = "POWER 100%  ·  SHIELD UP"
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.fixed_size = true
	lb.pixel_size = 0.0011
	lb.font_size = 40
	lb.outline_size = 10
	lb.modulate = Color(0.5, 0.85, 1.0)
	lb.position = Vector3(0, float(board_ship.get_meta("radius", 200.0)) * 0.6, 0)
	board_ship.add_child(lb)
	board_escort = []
	if Factions.has_fighters(str(j["faction"])):
		board_escort = space.spawn_mission_group((pt["pos"] as Vector3) + Vector3(0, 90, 0), str(j["faction"]), int(j["fighters"]), 2, "", 0)
	j["escort"] = board_escort.size()
	j["in_nebula"] = bool(pt["nebula"])
	space.board_mission = {"sys": str(j["sys"]), "title": str(j["title"]), "node": board_ship, "power": 100.0}
	space.gps_mission = true
	space.set_destination(board_ship)   # v13.10: the ship itself, gold on the map (was a plain waypoint)
	space.target = board_ship
	hud.flash_message("%s: target ship %s, %d fighters with it. Waypoint set: GO TO flies it. Shoot the ship down to 50%% power to break its shield, then fly to the hull to board." % [str(j["title"]), "hidden in a nebula" if bool(pt["nebula"]) else "located", board_escort.size()])
func _board_enter(j: Dictionary) -> void:
	space.controls = false
	space.autopilot = null
	if not open_ship_interior(str(j["id"])):
		space.controls = true
		_board_cd = 8.0
		return
	space.process_mode = Node.PROCESS_MODE_DISABLED    # (the fight outside waits while you are aboard)
	var sd: ShipInterior = ship_deck
	sd.start_mission(str(j["kind"]))
	sd.left.connect(func(): _board_left(sd.mission == str(j["kind"]) and sd.m_stage == 2))
func _board_left(done: bool) -> void:
	if not is_instance_valid(space): return
	space.process_mode = Node.PROCESS_MODE_INHERIT
	space.controls = true
	var j := board_job()
	if is_instance_valid(board_ship) and is_instance_valid(space.player):   # you launch clear of the hull
		var away: Vector3 = (space.player.global_position - board_ship.global_position)
		away.y = 0.0
		away = away.normalized() if away.length() > 1.0 else Vector3(0, 0, 1)
		var hh: Vector3 = board_ship.get_meta("hit_half", Vector3.ONE * float(board_ship.get_meta("radius", 200.0)))
		space.player.global_position = board_ship.global_position + away * (maxf(hh.x, hh.z) + BoardingJobs.BOARD_RANGE + 500.0)
	_board_cd = 6.0
	if done and not j.is_empty():
		GS.add_credits(int(j["pay"]))
		hud.flash_message("BOARDING MISSION COMPLETE: %s. Paid %d cr." % [str(j["title"]), int(j["pay"])])
		if is_instance_valid(board_ship): board_ship.queue_free()
		board_ship = null
		hub.board_job = {}
		GS.save_game()
	elif not j.is_empty():
		hud.flash_message("You left the ship with the job unfinished. It is still out here: reach it again to go back aboard.")

## v13.01 station rebuild (Veranthos first): the rebuilt station interior, on foot (StationInterior). Opened from the
## Station Viewer (WALK INSIDE) while it is reviewed; docking, services, missions, the alarm and the escape are NOT
## switched over to it yet and work as before.
var station_deck: StationInterior
var _stn_layer: CanvasLayer
var _stn_from := ""
func open_station_interior(id: String, docked := false) -> bool:
	if is_instance_valid(station_deck) or is_instance_valid(ship_deck): return false
	var st := StationInterior.create(id)
	if st == null:
		hud.flash_message("That station has not been rebuilt yet.")
		return false
	station_deck = st
	_stn_from = state
	_stn_layer = CanvasLayer.new()
	_stn_layer.layer = 61
	add_child(_stn_layer)
	_stn_layer.add_child(st)
	_stn_hid = [hud.visible, hub.visible]
	hud.visible = false
	hub.visible = false
	state = "station_deck"
	st.left.connect(_close_station_interior)
	# v13.02: docked here = the rooms are the station's services, and you come aboard at a docking bay
	st.services_on = docked and _stn_from == "hub"
	if st.services_on:
		st.service.connect(_stn_service)
		var at := st.arrival()
		if at != Vector3.INF: st.place(str(st.data["start"]["level"]), at)
	return true
## v13.02: a service asked for from its room: back to the station page that does the work (or out to your ship).
func _stn_service(screen: String) -> void:
	if not is_instance_valid(station_deck): return
	station_deck.close()
	if state != "hub": return
	if screen == "launch": launch()
	else: hub.show_screen(screen)
var _stn_hid: Array = [false, false]
func _close_station_interior() -> void:
	state = _stn_from if _stn_from != "" else "hub"
	hud.visible = bool(_stn_hid[0])
	hub.visible = bool(_stn_hid[1])
	if is_instance_valid(_stn_layer): _stn_layer.queue_free()
	station_deck = null

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
	if space.boarding: return space.board_line()   # v11.45
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
	var gt: String = str(space.sys["gate"].get("name", "the edge of this space"))
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
	if hud.fl_tap(id): return   # v6.7: the contact list and ship panel
	if id in ["start", "select", "pm_resume", "pm_tips"] or id.begins_with("pm_slot_"):   # v11.25 (owner): the pause menu
		_pause_input(id)
		return
	if space.cloaked and not (id in ["cloak", "kill", "engine_kill", "view", "radar", "fullscreen", "scan", "scan_close", "hangup", "side_l", "side_r", "call_pick"]):   # v10.6 (owner): cloaked, every tool is locked: you only fly and look around
		hud.flash_message("Cloaked: everything is locked. You can only fly. Tap CLOAK to drop it.")
		return
	if id == "weapons":   # v7.0: open / fold the weapons and abilities
		hud.weapons_open = not hud.weapons_open
		return
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
	if id == "build":   # v12.25 (owner): BUILD mode
		hud.flash_message(space.toggle_build())
		return
	if id.begins_with("bslot_"):
		space.build_slot = int(id.substr(6))
		var bm := space.build_mat()
		hud.flash_message(("%s: %d blocks" % [bm.to_upper(), GS.build_count(bm)]) if bm != "" else "Empty slot.")
		return
	if id == "fire" and space.build_mode:   # in BUILD, FIRE is PLACE
		var say := space.place_block()
		if say != "": hud.flash_message(say)
		return
	if id == "goto_l": id = "goto"   # v8.0: the contact window's GO TO = the console's
	match id:
		"missile": space.trigger_system("missile")
		"shield": space.trigger_system("shield")
		"repair": space.trigger_system("hull")
		"tractor":
			var tm: String = space.tractor()
			hud.flash_message(tm)
			if space.tractor_t > 0.0: Sfx.play("tractor", -6.0)
		"target", "dash_next":   # (v12.2: NEXT on the console too)
			space.cycle_target()
			hud.target_menu = false
		"dash_tgt": _on_hud("tgt_front")
		"sidestep": pass   # v12.55: the SWORD button in every form (space._update_sword acts on let-go)
		"spare_l":   # v12.15 (owner): the mech's laser shield
			match space.toggle_laser_shield():
				"on": hud.flash_message("LASER SHIELD up: it blocks shots from in front, and swings to your left while you fire.")
				"off": hud.flash_message("Laser shield down.")
				_: hud.flash_message("The laser shield is for the MECH — transform first.")
		"scan":
			hud.flash_message(hud.start_scan())   # v1.5g
			hud.target_menu = false
		"scan_close": hud.close_scan()
		"scan_view": open_scan_view()   # v11.28
		"view":
			space.set_view("cockpit" if GS.view == "chase" else "chase")
			hud.flash_message("View: %s" % (("first person: the mech's eyes" if GS.form == "mech" else "first-person cockpit") if GS.view == "cockpit" else "chase camera"))
		"zoom":   # v1.7z: the mech rifle's scope
			hud.flash_message("Scope: ON" if space.toggle_zoom() else "Scope: OFF")
		"stop":
			space.full_stop()
			hud.flash_message("Braking to a full stop.")
		"swap":   # v12.67 (owner's spec): one button cycles the weapon sets
			hud.flash_message(space.loadout_swap())
		"cruise":   # v12.61 (owner): full speed without holding the stick forward
			if GS.form == "mech" or space.on_foot: return
			var con := space.toggle_cruise()
			if con: GS.learn_tip("cruise")
			hud.flash_message("CRUISE: full speed. Pull back or tap STOP to end it." if con else "Cruise off.")
		"eject":
			if space.eject() == "loading": hud.flash_message("Pilot still downloading — try again in a moment.")
		"enter":
			space.enter_vehicle()
		"form":
			if space.on_foot:
				hud.flash_message("You're on foot: walk back to it and ENTER.")
				return
			if bool(board_from.get("escape", false)):
				hud.flash_message("On foot in here: no transforming. Get to YOUR SHIP in the launch bay.")
				return
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
			elif space.warp_state == "on" and space.toggle_engine_kill(): hud.flash_message("Engines OFF at warp: drifting at warp speed. Turn, shoot, use your abilities; THRUST swings the speed to your nose. KILL again restarts the engines.")
			elif space.warp_active(): hud.flash_message("Wait for the warp drive to finish spooling.")
			else: hud.flash_message("Engines OFF — drifting. You can still turn and shoot; THRUST restarts them." if space.toggle_engine_kill() else "Engines restarted.")
		"warp":
			if space.on_foot or space.escape_pilot:   # v12.45: on foot WARP is the speed run
				space.sprint = not space.sprint
				hud.flash_message("SPEED RUN on: keep running and you build up to a speed boost." if space.sprint else "Speed run off.")
				return
			match space.request_warp():
				"charging": hud.flash_message("Warp spooling — 5 s. Weapons locked. Keep flying!")
				"atmosphere": hud.flash_message("The warp drive can't run inside an atmosphere.")
				"mech": hud.flash_message("Mechs have no warp drive — transform to SHIP to warp.")
				"busy": hud.flash_message("Finish transforming first.")
				"cancelled": hud.flash_message("Warp charge cancelled. Weapons unlocked.")
				"cloaked": hud.flash_message("No warp while cloaked. Drop the cloak first.")
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
				"off": hud.flash_message("GROUND off: JETPACK. THRUST = boost." if (space.on_foot or space.escape_pilot) else "GROUND off: flying.")
				"space": hud.flash_message("GROUND works down on a planet.")
				"warp": hud.flash_message("Drop out of warp first.")
		"lock_a", "lock_c": hud.flash_message("Locked for now.")
		"cloak": space.set_cloak(not space.cloaked)   # v8.3 (owner)
		"board":   # v11.60 (owner): BOARD the battleship whose shield you broke
			if not space.board_now(): hud.flash_message("Get closer, with its shield broken.")
		"tgt_front":   # v8.3 (owner): TARGET = the hostile in front of you, closest
			var tf: Node3D = space.target_front()
			if tf == null: hud.flash_message("No hostiles around.")
			else:
				space.pick_target(tf)
				hud.flash_message("Target: %s" % tf.name)
		"fullscreen":   # v1.9 (owner): the browser's full screen on / off (hides the address bar where the phone allows it)
			if OS.has_feature("web"): JavaScriptBridge.eval("window.__hlFsToggle && window.__hlFsToggle()", true)
		"pmap_wild":   # v12.44 (owner: "make it a button on the planet map"): the wildlife test area right here, on / off
			hud.planet_map = false
			wild_test_here(not space.wild_park)
		"pmap_close":
			hud.planet_map = false
			hud.map_deck = ""
		"pmap_deck0", "pmap_deck1", "pmap_deck2": hud.map_deck = str(hud.deck_list()[int(id.right(1))])   # v12.19
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
		"goto_t":   # v7.3 (owner): GO TO in the target window flies to the picked target
			if space.target and is_instance_valid(space.target):
				var tg: Node3D = space.target
				_mission_auto = false
				space.set_destination(tg)
				space.autopilot = tg if tg.get_meta("kind", "") != "enemy" else space.waypoint_at(tg.global_position)
				hud.flash_message("Autopilot engaged: %s" % tg.name)
		"goto":
			if space.autopilot != null and is_instance_valid(space.autopilot):   # v1.8v: a second tap stops it, whatever it is flying to
				space.autopilot = null
				hud.flash_message("Autopilot off.")
			# v6.7 (owner: I get lost): GO TO goes to the MISSION first, then your waypoint, and only then the target you picked
			elif not space.mission_waypoint().is_empty():
				var mw: Dictionary = space.mission_waypoint()
				var mn: Node3D = mw["node"]
				space.gps_mission = true
				space.set_destination(mn)
				space.autopilot = mn if mn.get_meta("kind", "") != "enemy" else space.waypoint_at(mn.global_position)   # (a hostile is flown TO, not docked with)
				_mission_auto = true   # v1.9k: through the gates and in to dock, not just to the next stop
				hud.flash_message("Autopilot engaged: %s" % mw["title"])   # (v1.9a: on a planet too: the job's point, the freighter, or the way up)
			elif space.nav_dest != null and is_instance_valid(space.nav_dest):   # v1.7v (owner): the GPS destination picked on the map
				var nd: Node3D = space.nav_dest
				_mission_auto = false
				space.route_go()   # (v12.62: and docks at the last stop)
				if nd.get_meta("kind", "") == "enemy": space.autopilot = space.waypoint_at(nd.global_position)   # (a hostile is flown TO, not docked with)
				hud.flash_message("Autopilot engaged: %s" % nd.name)
			elif space.target and is_instance_valid(space.target):   # (v6.7: a hostile you picked too: flown to, not docked with)
				space.autopilot = space.target if space.target.get_meta("kind", "") != "enemy" else space.waypoint_at(space.target.global_position)
				hud.flash_message("Autopilot engaged: %s" % space.target.name)
			elif space.surface_mode and not space.nearest_base().is_empty():   # v1.8y: on a planet: the nearest base, wherever it is
				var nb: Dictionary = space.nearest_base()
				space.autodock_target = space.set_surface_goal(nb)
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
			if id == "pmap_job":   # v12.59 (owner): the job's point tapped on the planet map: GO TO it, the autopilot cruises there
				for jp in hud.pmap_job_points():
					if jp["current"]:
						var tile_j := int(jp["tile"])
						space.set_surface_goal({"name": str(jp["label"]), "tile": tile_j, "x": float(jp["x"]), "z": float(jp["z"]),
							"pos": space.surface_offset(tile_j) + Vector3(float(jp["x"]), Surface.pad_top(space.planet_id, tile_j) + 40.0, float(jp["z"]))})
						hud.planet_map = false
						hud.flash_message("Autopilot engaged: %s" % str(jp["label"]))
						break
				return
			if id.begins_with("pmap_f"):   # v12.0: a facility tapped on the planet map: fly there
				var fsp: Array = space.facility_spots()
				var fi := int(id.substr(6))
				if fi < fsp.size():
					space.set_surface_goal(fsp[fi])
					hud.planet_map = false
					hud.flash_message("Autopilot engaged: %s (level %d facility)" % [fsp[fi]["name"], int(fsp[fi].get("difficulty", 1))])
				return
			if id.begins_with("pmap_b"):   # v1.8y: a base tapped on the planet map: fly there
				var spots: Array = space.base_spots()
				var bi := int(id.substr(6))
				if bi < spots.size():
					space.autodock_target = space.set_surface_goal(spots[bi])
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
	if space.boarding:   # (inside a ship or a facility: the deck map)
		hud.planet_map = not hud.planet_map
		return
	# v12.61 (owner: "the planet map should be like the space map"): on a planet the same map as in space shows the planet
	hud.planet_map = false
	if space.surface_mode: GS.learn_tip("planet_map")
	state = "map"
	hud.close_comms()
	hud.visible = false   # v11.97 (owner): the map no longer pauses the game (only START does): you keep flying, warping
	navmap.open(space)    # and the autopilot keeps going while you watch yourself move on it, like a real GPS

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
	space.autodock_target = n   # v12.62: it docks there when it arrives
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
	var dinfo: Dictionary = n.get_meta("info", {}) if n.has_meta("info") else {}
	if str(dinfo.get("kind", "")) == "station" and SystemBuilder.is_enemy_space(Data.SYSTEMS.get(space.sys_id, {})):
		# v11.99 (owner: alien stations "are not dockable ... more like Armored Core facilities you have to infiltrate")
		if GS.form != "mech":
			hud.flash_message("%s won't take you: a hostile station. Transform to your MECH and dock to infiltrate it." % str(dinfo.get("name", "The station")))
			return
		infiltrate_station(n)
		return
	var dname := str(dinfo.get("name", ""))
	if dock_ban.has(dname) and str(dock_ban[dname]) == space.sys_id:   # v12.30 (owner): you broke out of there
		hud.flash_message("%s: DOCKING ACCESS DENIED. Leave the system or dock somewhere else first." % dname)
		return
	dock_ban.clear()   # (docking anywhere else lifts it)
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
	# v12.60 (owner: "when I'm dead I restart at the last place I docked; a planet dock is my new respawn point")
	record_home(info, false)
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
	if paid == "" and home_free == "":   # v12.61: Evee's tip for this dock (the home point; the atlas on a world)
		if evee_tip("dock") == "" and docked_node_kind == "planet": evee_tip("planet_dock")
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

## v12.30 (owner): the lockdown as a 3D escape. The hub hides; you break out room by room (StationEscape); boarding
## your ship launches you, with ESCAPE_CHASERS of their ships after you, and that station won't take you back until
## you leave the system or dock somewhere else.
var escape: StationEscape
var escape_rooms := false   # (tests: the older separate escape rooms, StationEscape)
var dock_ban := {}   # station name -> system id
var escape_from := ""
func start_escape(faction: String) -> void:
	if escape != null: return
	while state == "docking": await get_tree().process_frame   # (the alarm goes off as the hub opens, before docking is done)
	if state != "hub": return
	if Data.ESCAPE_IN_SPACE and not escape_rooms:
		_escape_in_space()
		return
	state = "escape"
	escape_from = str(hub.base["name"])
	hub.visible = false
	escape = StationEscape.new()
	escape.name = "StationEscape"
	add_child(escape)
	escape.escaped.connect(_escaped)
	escape.start(faction)

## v12.38 (owner: "the same controls as mech mode ... bring everything ... it's not just copy-paste?"): the breakout runs
## inside the real flight / mech game, like boarding: the station's deck plan, its guards, the whole HUD (TARGET, GO TO,
## COMMS, radar, wheels, missiles, sword, shield, sidestep, super). You're on foot (the owner's pilot, his rifle);
## TRANSFORM is out. Reach the launch bay where your ship waits: you launch with their fleet after you.
func _escape_in_space(retry := false) -> void:
	var sid := GS.system_id
	escape_from = str(hub.base["name"])
	var own := str(Factions.owner_of(hub.base, Data.SYSTEMS[sid]))
	var fac := own if Factions.has(own) else "Savagers"
	var form: String = str(board_from.get("form", GS.form)) if retry else GS.form
	state = "boarding"
	board_from = {"sys": sid, "pos": Vector3.ZERO, "name": escape_from, "faction": fac, "escape": true, "form": form}
	fx.caption = "WANTED" if not retry else "TRY AGAIN"
	fx.sub = "GET TO YOUR SHIP IN %s'S HANGAR" % escape_from.to_upper()
	Sfx.play("whoosh", -2.0, 0.7)
	var tw := create_tween()
	tw.tween_property(fx, "fade", 1.0, 0.5)
	await tw.finished
	await Packs.wait(PilotRig.PACK, 60.0)   # v12.44: on the web your pilot comes in its own pack: have him before going in
	var gpk := "crowd3d_orion" if fac.to_lower().begins_with("orion") else "crowd3d"   # v12.46: the guards are the faction's soldiers
	Packs.request(gpk)
	await Packs.wait(gpk, 30.0)
	# v12.47 (owner: "Tripo space stations give you a good shell to build on"): the station's own 3D model shapes the
	# deck plan (its silhouette) and is set round it as the shell
	var skey := breakout_shell_key(fac)
	var fp := {}
	if skey != "":
		Packs.request(skey)
		await Packs.wait(skey, 30.0)
		fp = Boarding.footprint("res://assets/stations3d/%s.glb" % skey)
	if retry: GS.restore_full()
	hub.visible = false
	GS.form = "mech"
	# v12.46 (owner: "a hub area ... not such a big maze"): the breakout's own small station
	Boarding.use(Boarding.deckplan("%s:%s:breakout" % [sid, escape_from], "hub", Data.STATION_INFIL_LEVEL, escape_from, fp.get("occ", [])))
	if not fp.is_empty():
		Boarding.INFO["shell"] = "res://assets/stations3d/%s.glb" % skey
		Boarding.INFO["shell_lo"] = fp["lo"]
		Boarding.INFO["shell_hi"] = fp["hi"]
	_new_space("Boarding")
	space.escape_pilot = true
	space.setup_boarding({"sys": sid, "faction": fac, "name": escape_from, "escape": true})
	_connect_space()
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""
	fx.sub = ""
	space.controls = true
	hud.visible = true
	state = "flight"

## The station model the breakout is built in: the docked station's own (one of the owner's Tripo 3D stations), else
## its faction's military station, else Unity's.
func breakout_shell_key(fac: String) -> String:
	var m := str(hub.base.get("model", ""))
	for k in [m, "HL_Station_%s_Military_retopo" % fac, "HL_Station_Unity_Military_retopo"]:
		if k != "" and Packs.PACKS.has(k) and str(k).begins_with("HL_Station_"): return k
	return ""

func _escaped() -> void:
	if is_instance_valid(escape): escape.queue_free()
	escape = null
	_escape_finish()

func _escape_finish(quiet := false) -> void:
	var fac: String = hub.lockdown_faction()
	var own := str(Factions.owner_of(hub.base, Data.SYSTEMS[GS.system_id]))
	hub.visible = true
	hub._end_lockdown()
	state = "hub"
	launch()
	dock_ban[escape_from] = GS.system_id
	if not is_instance_valid(space) or not is_instance_valid(space.player): return
	if quiet:   # v12.46: out without being seen: nobody's after you
		escape_chasers = 0
		hud.flash_message("You slipped out of %s unseen. They still won't let you dock there." % escape_from)
		return
	var p: Node3D = space.player
	var at: Vector3 = p.global_position + p.global_basis.z * 600.0 + Vector3(0, 60, 0)
	var fl: String = own if Factions.has(own) else fac
	var grp: Array = []
	var left := Data.ESCAPE_CHASERS
	while left > 0:
		var g: Array = space.spawn_mission_group(at + Vector3(randf_range(-200, 200), randf_range(-60, 60), randf_range(-200, 200)), fl, mini(5, left), 3, "", -8)
		if g.is_empty(): break
		grp.append_array(g)
		left -= g.size()
	for e in grp:
		e["aggro"] = true
		e["provoked"] = true
	escape_chasers = grp.size()
	hud.flash_message("You're out! %d of their ships are after you. %s won't let you dock: leave the system or dock somewhere else." % [grp.size(), escape_from])

var escape_chasers := 0
var breakout_retries := 0   # (tests)

func launch() -> void:
	if state != "hub": return
	if hub.lockdown:   # v9.2 (owner): no launching in a lockdown until you reach the hangar
		hub.status.text = "LOCKED DOWN. Fight your way to the hangar first."
		return
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
	get_tree().create_timer(9.0).timeout.connect(func(): if state == "flight": evee_tip("launch"))   # v12.61
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
	var dest: String = str(Surface.PLANETS[info["planet_to"]]["name"]) if info.has("planet_to") else str(Data.SYSTEMS[info["to"]]["name"])   # (v6.5: a planet's rift leads to a planet)
	gate_dock.open(docked_gate.name, dest, "%s gate" % str(info.get("gkind", "jump")))
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
	var hold_end := Time.get_ticks_msec() + int((Data.JUMP_TUNNEL_HOLD_MIN + (Data.RIFT_RIDE_EXTRA if look == "rift" else 0.0)) * 1000.0)   # v12.87: the ride through the living tube lasts a while
	while Time.get_ticks_msec() < hold_end:
		if not reduced: _tunnel(1.0)
		await get_tree().process_frame
	await get_tree().process_frame   # the full tunnel is on screen before the load starts
	if not reduced: _tunnel(1.0)
	var pto: String = str(gate.get_meta("info").get("planet_to", ""))
	if pto != "":   # v6.5 (owner): a planet's rift gate comes out on another planet, at its rift gate
		_load_surface(pto, 0)
		space.place_at_rift()
	else: await _load_system(to, "gate:" + from, true)   # v1.5d: built one step a frame; the warp keeps moving over it
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
## v12.60 / v12.61: this dock becomes the home point (pin = SET HOME POINT in your quarters: docking elsewhere won't
## move it). The one before is kept: if this one turns hostile, that's where the tug takes you.
func record_home(info: Dictionary, pin: bool) -> void:
	if GS.home_pinned and not pin: return
	var surf: bool = is_instance_valid(space) and space.surface_mode
	var nh := {"sys": space.sys_id if is_instance_valid(space) else GS.system_id, "id": str(info.get("id", "")), "surface": surf, "planet": space.planet_id if surf else "", "tile": space.tile if surf else -1}
	if not GS.respawn.is_empty() and str(GS.respawn.get("id", "")) != nh["id"]: GS.respawn_prev = GS.respawn.duplicate()
	GS.respawn = nh
	if pin: GS.home_pinned = true

## v12.61 (owner: "Evee gives you tips until you know them"): the first tip for this moment you haven't shown you know
## (and not too soon after the last one). Docked she says it in the station, in flight on the comms.
var _tip_t := -1000.0
func evee_tip(where: String) -> String:
	if not GS.tips_on: return ""
	var now := Time.get_ticks_msec() / 1000.0
	if now - _tip_t < Data.EVEE_TIP_GAP: return ""
	for id in Data.EVEE_TIPS:
		var tp: Dictionary = Data.EVEE_TIPS[id]
		if str(tp["where"]) != where or id in GS.tips_known: continue
		if id == "atlas" and (hub.atlas_planet() == "" or hub.atlas_planet() in GS.atlases): continue
		_tip_t = now
		if state == "hub" or where in ["dock", "planet_dock"]: hub.evee_say(str(tp["line"]))
		else: say_as("assistant", str(tp["line"]))
		return id
	return ""
## v12.60: the last dock you used, if it still takes you: {surface, sys, planet, tile, info} or {} (then the old tow rule).
func respawn_dock(r: Dictionary) -> Dictionary:
	if r.is_empty() or not Data.SYSTEMS.has(str(r.get("sys", ""))): return {}
	var sy: Dictionary = Data.SYSTEMS[str(r["sys"])]
	if bool(r.get("surface", false)):
		var pid := str(r.get("planet", ""))
		if not Surface.PLANETS.has(pid): return {}
		for l in Surface.locations_in(pid, int(r["tile"])):
			if str(l.get("id", "")) == str(r["id"]):
				if Factions.has(str(l.get("faction", ""))) and Factions.hostile(str(l.get("faction", ""))): return {}   # (they won't take you now)
				return {"surface": true, "sys": str(r["sys"]), "planet": pid, "tile": int(r["tile"]), "info": l}
		return {}
	if SystemBuilder.is_enemy_space(sy) or sy.get("open", false) or str(sy["station"].get("id", "")) != str(r["id"]): return {}
	return {"surface": false, "sys": str(r["sys"]), "info": sy["station"].duplicate()}

## v6.2: where the tug takes you from enemy or open space: the system of the last station you docked at, else Solara.
func friendly_base_system() -> String:
	for id in Data.SYSTEMS:
		var sy: Dictionary = Data.SYSTEMS[id]
		if str(sy["station"].get("id", "")) == GS.last_base and not SystemBuilder.is_enemy_space(sy) and not sy.get("open", false): return id
	return "solara" if Data.SYSTEMS.has("solara") else Data.SYSTEMS.keys()[0]

func _on_destroyed() -> void:
	if state == "map":   # v11.97: the map no longer pauses, so you can die with it open: shut it first
		navmap.visible = false
		state = "flight"
	if state != "flight": return
	if bool(board_from.get("escape", false)):   # v12.46 (owner: "if you die, it starts from before the guards find you")
		state = "boarding"
		hud.visible = false
		fx.caption = "YOU WERE TAKEN DOWN"
		fx.sub = ""
		var twb := create_tween()
		twb.tween_property(fx, "fade", 1.0, 1.2).set_delay(0.8)
		await twb.finished
		breakout_retries += 1
		_escape_in_space(true)
		return
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
	var rs: Dictionary = respawn_dock(GS.respawn)
	if rs.is_empty() and not GS.respawn_prev.is_empty(): rs = respawn_dock(GS.respawn_prev)   # v12.61: the home point turned hostile: the one before
	if not rs.is_empty():   # v12.60 (owner): back at the last dock (a planet's too)
		if bool(rs["surface"]):
			_load_surface(str(rs["planet"]), int(rs["tile"]))
			var at_l: Dictionary = rs["info"]
			space.station.set_meta("info", at_l)
			space.station.name = str(at_l["name"])
			space.station.global_position = Vector3(at_l["pos"].x, Surface.pad_top(str(rs["planet"]), int(rs["tile"])) + 20.0, at_l["pos"].y)
			docked_node_kind = "planet"
		else:
			_load_system(str(rs["sys"]), "station")
			docked_node_kind = "station"
		space.visible = false
		space.process_mode = Node.PROCESS_MODE_DISABLED
		space.controls = true
		clear_fx()
		hub.open(rs["info"])
		hub.status.text = "Towed back to %s. Repairs complete. Salvage fee: %d credits.%s" % [str(rs["info"]["name"]), lost, ("  " + failed) if failed != "" else ""]
		state = "hub"
		var tw3 := create_tween()
		tw3.tween_property(fx, "fade", 0.0, 0.6)
		await tw3.finished
		fx.caption = ""
		return
	var tow_to: String = space.sys_id
	if SystemBuilder.is_enemy_space(space.sys) or space.sys.get("open", false): tow_to = friendly_base_system()   # v6.2: never towed into an enemy station
	if space.surface_mode or failed != "" or tow_to != space.sys_id: _load_system(tow_to, "station")   # (a fresh system: the job's old wave is gone)
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
	var auto_land: bool = space.autodock_target != null and is_instance_valid(space.autodock_target) and space.autodock_target == planet_node   # v12.62
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
	# v12.52 (owner): no saved craters from last time, and a new seed for the world's rocks, caves and trees
	var visits := int(GS.planet_visits.get(pid, 0))
	GS.planet_visits[pid] = visits + 1
	BlockField.visit_salt[pid] = visits
	for bk in GS.block_deltas.keys(): if str(bk).begins_with(pid + "|"): GS.block_deltas.erase(bk)
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
	# v12.52 (owner: "things were taking so long to load ... a movie clip of the ship going through clouds, then back to
	# the chase view, to give it time to load"): the camera flies round your ship as it glides down through thinning
	# cloud while the ground under you is built; the chase view comes back when it's ready (or after 14 s at most)
	if not Surface.is_sun(pid):
		space.cine_t = 0.0
		space.vel = -p.global_basis.z * 35.0
		var twc := create_tween()
		twc.tween_property(fx, "heat", 0.25, 0.8)
		twc.parallel().tween_property(fx, "clouds", 0.55, 1.5)
		await twc.finished
		fx.caption = ""
		var waited := 0.0
		while waited < landing_film_max and (waited < landing_film_min or not space.ground_ready()):
			await get_tree().process_frame
			var fdt := get_process_delta_time()
			waited += fdt
			space.vel = -p.global_basis.z * 35.0
			fx.clouds = 0.55 + 0.2 * sin(waited * 1.3)   # (cloud banks drifting past)
		landing_film_s = waited
		space.cine_t = -1.0
		space.vel = -p.global_basis.z * clampf(entry_speed, 40.0, 90.0)   # (back to your own speed)
		space._update_camera(1.0, true)
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
	if auto_land and not space.nearest_base().is_empty():   # v12.62: GO TO the planet carries on down here: to its port, and docks
		var nb2: Dictionary = space.nearest_base()
		space.autodock_target = space.set_surface_goal(nb2)
		hud.flash_message("Autopilot: on to %s to dock." % nb2["name"])
	if not Surface.is_sun(pid):
		say_as("assistant", planet_brief(pid, t, visits))   # v12.52: Evee on what this world is
		get_tree().create_timer(14.0).timeout.connect(func(): if state == "flight" and is_instance_valid(space) and space.surface_mode: evee_tip("planet"))   # v12.61

var landing_film_s := 0.0   # (tests)
var landing_film_min: float = Data.LANDING_FILM_MIN
var landing_film_max: float = Data.LANDING_FILM_MAX
## v12.52 (owner: "Evee ... this planet is lush ... or its data is unknown until you visit; you've been here before"):
## what Evee says as you come out of the clouds
func planet_brief(pid: String, t: int, visits: int) -> String:
	var nm: String = str(Surface.PLANETS[pid]["name"])
	var key: String = str(Surface.PLANETS[pid]["tiles"][t])
	var bname: String = str(Surface.biome(pid, t)["name"]).to_lower()
	if visits <= 0:
		return "[normal]%s. We've never been here: no survey data on this world yet. I'm logging what we see. Below us: %s. Keep your eyes open." % [nm, bname]
	var hint: String = str(Data.PLANET_HINTS.get(key, "Nothing on record that'll kill you outright."))
	return "[smile]We've been to %s before (that's %d visits now). This sector's %s. %s It's shifted since last time, the ground's been reshaped." % [nm, visits + 1, bname, hint]

## Crossing a tile edge. Normally seamless (SUPERSEDES the old "storm on every border"): the next sector was built
## ahead of time, so the ground just continues. Only if it isn't ready yet (very fast flight) a quick cloud pass hides
## the build.
## v6.2 (owner): the galaxy board. Each system is one tile (Data.SPACE_EDGE each way from its centre). Flying past an
## edge crosses into the neighbouring tile in that direction (map east = +X, map south = +Z); empty board squares are
## crossed on to the next system; off the board's edge you come back in on the far side, Pac-Man style.
static func board_neighbour(from: String, dc: int, dr: int) -> String:
	var cells := {}
	var cols := 0
	var rows := 0
	for t in GalaxyData.TILES + SystemBuilder.open_rows():   # v6.2: the open squares are real space too
		if not Data.SYSTEMS.has(t[0]): continue
		cells[Vector2i(int(t[3]), int(t[4]))] = t[0]
		cols = maxi(cols, int(t[3]) + 1)
		rows = maxi(rows, int(t[4]) + 1)
	var at := Vector2i(-1, -1)
	for c in cells:
		if cells[c] == from: at = c
	if at.x < 0: return ""
	var c2 := at
	for i in maxi(cols, rows):
		c2 = Vector2i(posmod(c2.x + dc, cols), posmod(c2.y + dr, rows))
		if cells.has(c2): return cells[c2]
	return ""

var crossing := false
func _check_space_edge() -> void:
	if crossing or state != "flight" or not is_instance_valid(space) or space.surface_mode or not is_instance_valid(space.player): return
	var p: Vector3 = space.player.global_position - SystemBuilder.CENTRE
	var E := Data.SPACE_EDGE
	if absf(p.x) <= E and absf(p.z) <= E: return
	var dc := (1 if p.x > E else -1) if absf(p.x) > E else 0
	var dr := (1 if p.z > E else -1) if absf(p.z) > E else 0
	var to := board_neighbour(GS.system_id, dc, dr)
	if to == "" or to == GS.system_id:
		space.player.global_position -= Vector3(dc, 0, dr) * 2.0 * E   # (alone on the board: wrap round the same tile)
		return
	cross_edge(to, Vector3(p.x - dc * 2.0 * E, p.y, p.z - dr * 2.0 * E))

var glitch: CanvasLayer   # v12.4: the border crossing's static glitch
var border_glitches := 0   # (tests)
func cross_edge(to: String, arrive: Vector3) -> void:
	crossing = true
	state = "jumping"
	var speed: float = maxf(space.vel.length(), 40.0)
	var yw: float = space.yaw
	var pt: float = space.pitch
	space.controls = false
	space.autopilot = null
	space.drop_warp()
	hud.visible = false
	if glitch == null:
		glitch = load("res://scripts/border_glitch.gd").new()
		add_child(glitch)
	await glitch.out()   # v12.4 (owner): a static glitch, not a jump gate
	await get_tree().process_frame
	await _load_system(to, "edge:%f:%f:%f:%f:%f:%f" % [arrive.x, arrive.y, arrive.z, yw, pt, speed], true)
	space.controls = false
	await get_tree().process_frame
	await get_tree().process_frame
	await glitch.back()
	space.controls = true
	hud.visible = true
	state = "flight"
	crossing = false
	border_glitches += 1
	hud.flash_message("Entered %s space." % Data.SYSTEMS[to]["name"])

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

## v11.25 (owner: START pauses, SELECT swaps a weapon slot, e.g. the super missile for the NUKE): the flight stops while
## the menu is up (the space scene stops processing); RESUME, START again or SELECT again carries on.
## v11.28 (owner: "do it for the ship scan ... the pinch view for anything: ships, stations, buildings, mechs"):
## the scanned thing in the Station Viewer (rotate, zoom, key screens). The flight holds still while it is open.
var scan_viewer: StationViewer = null
func open_scan_view() -> StationViewer:
	var n: Node3D = hud.scan_node
	if n == null or not is_instance_valid(n) or hud.scan.is_empty(): return null
	if is_instance_valid(scan_viewer): scan_viewer.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 110   # over the HUD, under the corner FULL SCREEN button
	add_child(layer)
	var sv := StationViewer.new()
	var key: String = space.scan_model_key(n)
	sv.single = key == "" or not ResourceLoader.exists("res://assets/stations3d/%s.glb" % key) and not Packs.PACKS.has(key)
	layer.add_child(sv)
	if sv.single: sv.show_copy(n, str(hud.scan["title"]))
	else: sv.show_key(key)
	scan_viewer = sv
	space.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	controls.blocked = true
	sv.tree_exited.connect(func():
		layer.queue_free()
		if is_instance_valid(space) and not hud.pause_menu: space.process_mode = Node.PROCESS_MODE_INHERIT
		hud.visible = true
		controls.blocked = false)
	return sv

func set_paused(on: bool) -> void:
	hud.pause_menu = on
	if space != null: space.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	hud.queue_redraw()

func _pause_input(id: String) -> void:
	if id in ["start", "select"]: set_paused(not hud.pause_menu)
	elif id == "pm_resume": set_paused(false)
	elif id == "pm_tips":   # v12.61: Evee's tips on / off
		GS.tips_on = not GS.tips_on
		hud.flash_message("Evee's tips: %s" % ("ON (until you know them)" if GS.tips_on else "OFF"))
	elif id.begins_with("pm_slot_"):
		var k := int(id.substr(8))
		var order: Array = Data.SLOT_ITEMS.keys()
		var cur: String = GS.slots[k]
		var nxt := cur
		for i in order.size():   # the next weapon not already in another slot
			nxt = str(order[(order.find(nxt) + 1) % order.size()])
			if not (nxt in GS.slots) or nxt == cur: break
		GS.slots[k] = nxt
		GS.changed.emit()
		hud.flash_message("Slot %d: %s" % [k + 1, {"light_missile": "missile", "heavy_missile": "super missile", "mine": "mine", "nuke": "NUKE"}.get(nxt, nxt)])

# ---------------------------------------------------------------- v11.45 BOARDING (owner: "go inside the battleship as a mech")
## The mech reached a battleship's open side hangar (its shield tower is down): the inside is loaded as its own small
## level; coming out puts you back beside it (or where it was, if you blew its reactor).
var board_from := {}
## v11.56 (owner: "exactly 3 military-style panoramas per battleship"): boarding is the 360 alarm fight in three rooms
## (breach hangar, reactor spine, generator core; Breakout in interior mode). Clear the generator core, run back to the
## hangar and fly out: the battleship goes down and pays. Infiltrating costs standing with that faction (allies too).
var interior: Breakout
var _interior_layer: CanvasLayer
var _interior_ship: Dictionary = {}
func board_battleship(e: Dictionary) -> void:
	# v11.70 (owner: "that mini game was whack"): inside the battleship as a MECH in ground mode (Boarding / space
	# setup_boarding): corridors and doors, guard mechs, the core, then 90 s to find the other way out
	if state != "flight" or not is_instance_valid(space): return
	state = "boarding"
	_interior_ship = e
	board_from = {"sys": space.sys_id, "pos": space.player.global_position, "ship_at": (e["node"] as Node3D).global_position, "name": str(e["node"].name),
		"faction": str(e.get("faction", "")), "fleet": bool(e.get("fleet_patrol", false)), "mission": bool(e.get("invasion", false)), "form": GS.form,
		"surface": space.surface_mode, "planet": space.planet_id, "tile": space.tile, "mothership": bool(e.get("mothership", false))}   # v12.58
	if Factions.normal(str(board_from["faction"])): Factions.adjust(str(board_from["faction"]), -Data.REP_INFILTRATE)
	space.controls = false
	hud.visible = false
	fx.caption = "BOARDING"
	fx.sub = board_from["name"].to_upper()
	Sfx.play("whoosh", -2.0, 0.8)
	var tw := create_tween()
	tw.tween_property(fx, "fade", 1.0, 0.5)
	await tw.finished
	# v12.18 (owner): every enemy battleship has its own generated deck plan (Boarding.deckplan "ship")
	if Boarding.classic: Boarding.use_ship()
	elif bool(board_from["mothership"]):   # v12.58 (owner): the mothership: huge, tunnels and chambers, flown with your ship
		Boarding.use(Boarding.deckplan("%s:%s:mother" % [str(board_from["sys"]), str(board_from["name"])], "station", 4, str(board_from["name"])))
	else: Boarding.use(Boarding.deckplan("%s:%s" % [str(board_from["sys"]), str(board_from["name"])], "ship", Data.SHIP_DECK_LEVEL + (1 if bool(board_from["mission"]) else 0), str(board_from["name"])))
	GS.form = "ship" if bool(board_from["mothership"]) else "mech"   # v12.29 (owner): you dock as you are; inside you are the mech (v12.58: the mothership in your ship)
	_new_space("Boarding")
	space.setup_boarding({"sys": board_from["sys"], "faction": board_from["faction"], "name": board_from["name"]})
	_connect_space()
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""
	fx.sub = ""
	space.controls = true
	hud.visible = true
	state = "flight"

## v11.99 (owner): an alien station is infiltrated like a facility (level 3, its own maze), never docked at. Clear it
## and you come out beside it, paid.
func infiltrate_station(n: Node3D) -> void:
	if state != "flight" or not is_instance_valid(space): return
	state = "boarding"
	var info: Dictionary = n.get_meta("info", {})
	var nm := str(info.get("name", n.name))
	var fac := str(Data.SYSTEMS.get(space.sys_id, {}).get("enemy_faction", "Savagers"))
	if not Factions.has(fac): fac = "Savagers"
	board_from = {"sys": space.sys_id, "pos": space.player.global_position, "ship_at": n.global_position, "name": nm, "faction": fac, "infiltrate": true, "form": GS.form}
	space.controls = false
	hud.visible = false
	fx.caption = "INFILTRATION"
	fx.sub = nm.to_upper()
	Sfx.play("whoosh", -2.0, 0.7)
	var tw := create_tween()
	tw.tween_property(fx, "fade", 1.0, 0.5)
	await tw.finished
	Boarding.use(Boarding.deckplan("%s:%s" % [space.sys_id, nm], "station", Data.STATION_INFIL_LEVEL, nm))   # v12.18: a hub-and-ring station deck plan
	GS.form = "mech"   # v12.29 (owner): you dock as you are; inside you are the mech
	_new_space("Boarding")
	space.setup_boarding({"sys": board_from["sys"], "faction": board_from["faction"], "name": nm})
	_connect_space()
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""
	fx.sub = ""
	space.controls = true
	hud.visible = true
	state = "flight"

## v11.96 (owner: Armored Core facilities under every world's bases): go in as a mech; the facility is generated from
## its world and slot (Boarding.facility): deeper, bigger and better guarded the harder it is. Blow the reactor, get out
## of the exit shaft: you come up beside it on the surface and are paid. The base stays; you can run it again.
func enter_facility(site: Dictionary) -> void:
	if state != "flight" or not is_instance_valid(space) or not space.surface_mode: return
	state = "boarding"
	var fac := str(Data.SYSTEMS.get(space.sys_id, {}).get("faction", "Enemy"))   # (a hostile site is the rival's; a friendly one's guards are squatters)
	if Factions.rival(fac) != "": fac = Factions.rival(fac)
	if not Factions.has(fac): fac = "Savagers"
	board_from = {"sys": space.sys_id, "pos": space.player.global_position, "name": str(site["name"]), "faction": fac, "facility": true,
		"planet": str(space.planet_id), "tile": int(space.tile), "difficulty": int(site.get("difficulty", 1)), "form": GS.form}
	space.controls = false
	hud.visible = false
	fx.caption = "FACILITY"
	fx.sub = "%s  ·  LEVEL %d" % [str(site["name"]).to_upper(), int(site.get("difficulty", 1))]
	Sfx.play("whoosh", -2.0, 0.7)
	var tw := create_tween()
	tw.tween_property(fx, "fade", 1.0, 0.5)
	await tw.finished
	Boarding.use(Boarding.facility("%s:%s" % [str(site.get("planet", "")), str(site["name"])], int(site.get("difficulty", 1)), str(site["name"])))
	GS.form = "mech"   # v12.29 (owner): you dock as you are; inside you are the mech
	_new_space("Boarding")
	space.setup_boarding({"sys": board_from["sys"], "faction": board_from["faction"], "name": board_from["name"]})
	_connect_space()
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""
	fx.sub = ""
	space.controls = true
	hud.visible = true
	state = "flight"
	hud.flash_message("COMMAND: You're in %s. Find the reactor, deep inside: their boss mech guards it. Blow it and get out the exit shaft." % str(site["name"]))

func _interior_cleared() -> void:
	if state != "interior": return
	state = "boarding"
	fx.caption = "BATTLESHIP DESTROYED"
	fx.sub = str(board_from.get("name", "")).to_upper()
	var tw := create_tween()
	tw.tween_property(fx, "fade", 1.0, 0.4)
	await tw.finished
	space.process_mode = Node.PROCESS_MODE_INHERIT
	if bool(_interior_ship.get("fleet_patrol", false)): Boarding.sunk[board_from["sys"]] = true   # (v11.66: a mission battleship is not the system's own)
	GS.credits += Data.BOARD_PAY
	GS.kills += 1
	var e := _interior_ship
	if not e.is_empty() and space.enemies.has(e) and is_instance_valid(e["node"]):
		space.player.global_position = (e["node"] as Node3D).global_position + Vector3(0, 0, 900.0)
		space._destroy_unit(e)
	space.vel = Vector3.ZERO
	space._update_camera(1.0, true)
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	fx.caption = ""
	fx.sub = ""
	space.controls = true
	hud.visible = true
	state = "flight"
	hud.flash_message("Battleship destroyed: +%d cr. Your standing with %s fell for the infiltration." % [Data.BOARD_PAY, str(board_from.get("faction", ""))])
	board_from = {}
	_interior_ship = {}

## v12.58 (owner: "with enemy factions you may obtain special items, used to achieve or craft alien artifacts; yet to
## be determined"): a ship or base of a permanent-enemy faction broken from the inside leaves alien relics in the hold
## (GS.relics: faction -> count). What they make is still to come.
func _relic_drop(fac: String, big: bool) -> int:
	var enemy_fac: bool = Factions.has(fac) and str(Factions.def(fac).get("reputation_mode", "")) == "enemy"
	if not enemy_fac and not SystemBuilder.is_enemy_space(Data.SYSTEMS.get(str(board_from.get("sys", "")), {})): return 0
	var k: String = fac if fac != "" else "Unknown"
	var n: int = randi_range(int(Data.RELIC_DROP[0]), int(Data.RELIC_DROP[1])) * (Data.RELIC_BIG_K if big else 1)
	GS.relics[k] = int(GS.relics.get(k, 0)) + n
	hud.flash_message("Recovered %d %s RELIC%s from the wreck (%d held). Alien tech: what it can make is still a mystery." % [n, k.to_upper(), "" if n == 1 else "S", int(GS.relics[k])])
	return n

func leave_boarding(won: bool) -> void:
	# v11.70 (owner): out of the launch bay you fly, the battleship blows up behind you, and 20 of its fighters are
	# waiting. Command congratulates you; clear every one of them and you are paid.
	if state != "flight" or board_from.is_empty(): return
	state = "boarding"
	space.controls = false
	hud.visible = false
	fx.caption = "OUT!" if won else "OUT"
	fx.sub = board_from["name"].to_upper()
	var tw := create_tween()
	tw.tween_property(fx, "fade", 1.0, 0.4)
	await tw.finished
	GS.form = str(board_from.get("form", "ship"))   # v12.29: back to what you came in as, at once (no transforming in the open)
	if won: _relic_drop(str(board_from.get("faction", "")), bool(board_from.get("infiltrate", false)) or bool(board_from.get("mothership", false)))
	if bool(board_from.get("escape", false)):   # v12.38: out of the station you broke out of: into your ship, launch
		Boarding.use_ship()
		var sid: String = board_from["sys"]
		var quiet: bool = is_instance_valid(space) and str(space.board.get("phase", "")) == "out" and not bool(space.board.get("alerted", false))
		board_from = {}
		_load_system(sid, "station")
		space.visible = false
		space.process_mode = Node.PROCESS_MODE_DISABLED
		state = "hub"
		_escape_finish(quiet)
		return
	if bool(board_from.get("facility", false)):   # v11.96: back up on the world beside the facility
		Boarding.use_ship()
		var pay := Data.FACILITY_PAY * int(board_from.get("difficulty", 1)) if won else 0
		var job: bool = won and str(GS.mission.get("kind", "")) == "facility" and str(GS.mission.get("site", "")) == str(board_from["name"])   # v12.56: the job was this facility
		if job: pay = 0
		GS.credits += pay
		_load_surface(str(board_from["planet"]), int(board_from["tile"]))
		await get_tree().process_frame
		if job: Missions._pay(space, "%s is gutted. %s pays %d cr." % [str(board_from["name"]), Missions.giver_name(GS.mission), int(GS.mission["pay"])])
		space.player.global_position = (board_from["pos"] as Vector3) + Vector3(0, 40.0, 0)
		space.vel = Vector3.ZERO
		var twf := create_tween()
		twf.tween_property(fx, "fade", 0.0, 0.6)
		await twf.finished
		fx.caption = ""
		fx.sub = ""
		space.controls = true
		hud.visible = true
		state = "flight"
		if won: hud.flash_message("COMMAND: %s is gutted. Good work, pilot: %d credits. It'll be back in business soon." % [board_from["name"], pay])
		board_from = {}
		return
	if bool(board_from.get("surface", false)):   # v12.58: a battleship over a planet: back out into that sky
		Boarding.use_ship()
		if won and str(GS.mission.get("kind", "")) == "planet_invasion":
			GS.mission["bs_down"] = int(GS.mission.get("bs_down", 0)) + 1
			if int(GS.mission["bs_down"]) < int(GS.mission.get("left", 1)): GS.mission["spawned"] = int(GS.mission.get("stage", 0)) - 1   # (the next battleship's still up there)
		_load_surface(str(board_from["planet"]), int(board_from["tile"]))
		await get_tree().process_frame
		var sat: Vector3 = board_from.get("ship_at", board_from["pos"])
		space.player.global_position = sat + Vector3(0, 80.0, 500.0)
		space.vel = Vector3.ZERO
		space._update_camera(1.0, true)
		if won: space.start_post_wave(str(board_from["faction"]), sat, 0, true)
		var twp := create_tween()
		twp.tween_property(fx, "fade", 0.0, 0.6)
		await twp.finished
		fx.caption = ""
		fx.sub = ""
		space.controls = true
		hud.visible = true
		state = "flight"
		if won: hud.flash_message("The %s is gone! Now clear the sky: destroy the remaining fighters." % board_from["name"])
		board_from = {}
		_interior_ship = {}
		return
	if bool(board_from.get("mothership", false)) and won and str(GS.mission.get("kind", "")) == "mothership":   # v12.58: the armada's broken
		_load_system(board_from["sys"], "station")
		space.player.global_position = (board_from.get("ship_at", board_from["pos"]) as Vector3) + Vector3(0, 60.0, 1500.0)
		Missions._pay(space, "The %s MOTHERSHIP is destroyed and the armada with it! %s pays %d cr." % [board_from["faction"], Missions.giver_name(GS.mission), int(GS.mission["pay"])])
		var twm := create_tween()
		twm.tween_property(fx, "fade", 0.0, 0.6)
		await twm.finished
		fx.caption = ""
		fx.sub = ""
		space.controls = true
		hud.visible = true
		state = "flight"
		board_from = {}
		_interior_ship = {}
		return
	if bool(board_from.get("infiltrate", false)): Boarding.use_ship()   # v11.99: out of an alien station
	if won:
		if bool(board_from.get("fleet", false)): Boarding.sunk[board_from["sys"]] = true
		if bool(board_from.get("mission", false)) and not GS.mission.is_empty() and str(GS.mission.get("kind", "")) == "disturbance": GS.mission["boarded"] = true
	_load_system(board_from["sys"], "station")
	var ship_at: Vector3 = board_from.get("ship_at", board_from["pos"])
	space.player.global_position = ship_at + Vector3(0, 60.0, 1200.0 if won else 300.0)
	SpaceSystem.face(space.player, ship_at - space.player.global_position)
	space.yaw = space.player.rotation.y
	space.pitch = space.player.rotation.x
	space.vel = Vector3.ZERO
	space._update_camera(1.0, true)
	var tw2 := create_tween()
	tw2.tween_property(fx, "fade", 0.0, 0.6)
	await tw2.finished
	if won and bool(board_from.get("infiltrate", false)):
		GS.credits += Data.FACILITY_PAY * Data.STATION_INFIL_LEVEL
		hud.flash_message("COMMAND: you gutted %s from the inside. %d credits. They'll rebuild." % [board_from["name"], Data.FACILITY_PAY * Data.STATION_INFIL_LEVEL])
	elif won: space.start_post_wave(str(board_from["faction"]), ship_at, Data.BOARD_PAY, bool(board_from.get("mission", false)))   # (once you can see it go up)
	fx.caption = ""
	fx.sub = ""
	space.controls = true
	hud.visible = true
	state = "flight"
	if won: hud.flash_message("COMMAND: Outstanding, pilot! The %s is gone. %d of their fighters are on you: destroy all threats." % [board_from["name"], Data.BOARD_WAVE])
	board_from = {}
	_interior_ship = {}
