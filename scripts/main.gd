extends Node
## Homelancer Digital v1.2 — game flow: title -> launch -> flight <-> docking -> hub -> launch, jump gates, map.

const SpaceScript := preload("res://scripts/space.gd")
const HudScript := preload("res://scripts/hud.gd")
const HubScript := preload("res://scripts/hub.gd")
const MapScript := preload("res://scripts/navmap.gd")
const FxScript := preload("res://scripts/fx.gd")

var state := "title"
var space: SpaceSystem
var ui: CanvasLayer
var hud: Control
var hub: Control
var navmap: Control
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
	fx = FxScript.new()
	ui.add_child(fx)
	hud.pressed.connect(_on_hud)
	hub.launch_requested.connect(launch)
	hub.map_requested.connect(func(): navmap.open(null))
	navmap.closed.connect(_on_map_closed)
	navmap.course_set.connect(_on_course)
	GS.changed.connect(_on_gs_changed)
	_build_title()
	_load_system("solara", "station")
	space.controls = false
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
	var keys := {"forward": [KEY_W], "back": [KEY_S], "strafe_left": [KEY_A], "strafe_right": [KEY_D],
		"yaw_left": [KEY_LEFT, KEY_Q], "yaw_right": [KEY_RIGHT, KEY_E], "pitch_up": [KEY_UP], "pitch_down": [KEY_DOWN], "fire": [KEY_SPACE]}
	for a in keys:
		if not InputMap.has_action(a): InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)

# ---------------------------------------------------------------- title
func _build_title() -> void:
	title = Control.new()
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(title)
	var shade := ColorRect.new()
	shade.color = Color(0, 0.02, 0.05, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(shade)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.offset_left = -360
	box.offset_right = 360
	box.offset_top = -200
	box.offset_bottom = 200
	title.add_child(box)
	var t1 := Label.new()
	t1.text = "HOMELANCER"
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t1.add_theme_font_size_override("font_size", 76)
	t1.add_theme_color_override("font_color", Color(0.9, 0.96, 1.0))
	t1.add_theme_color_override("font_outline_color", Color(0, 0.1, 0.2))
	t1.add_theme_constant_override("outline_size", 10)
	box.add_child(t1)
	var t2 := Label.new()
	t2.text = "DIGITAL  ·  %s  ·  SOLARA — VEGA" % Data.VERSION
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.add_theme_font_size_override("font_size", 22)
	t2.add_theme_color_override("font_color", Color(0.4, 0.86, 1.0))
	box.add_child(t2)
	var b := Button.new()
	b.text = "START"
	b.name = "StartButton"
	b.custom_minimum_size = Vector2(360, 96)
	b.add_theme_font_size_override("font_size", 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.55, 0.35)
	sb.border_color = Color(0.6, 1.0, 0.75)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(16)
	for s in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(s, sb)
	var cc := CenterContainer.new()
	cc.add_child(b)
	box.add_child(cc)
	b.pressed.connect(start_game)
	var note := Label.new()
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.8, 0.86, 0.92))
	note.text = "Landscape. Left thumb: thrust and strafe. Right thumb: aim. Extra fingers: fire, missile, repair.\nPrototype build — ships marked as stand-ins are temporary original models."
	box.add_child(note)

func start_game() -> void:
	if state != "title": return
	title.visible = false
	state = "launching"
	GS.restore_full()
	_launch_sequence("Liberty Hub")

# ---------------------------------------------------------------- systems
func _load_system(id: String, arrival: String) -> void:
	if is_instance_valid(space):
		space.queue_free()
		remove_child(space)
	GS.system_id = id
	if not (id in GS.discovered): GS.discovered.append(id)
	space = SpaceScript.new()
	space.name = "Space_" + id
	add_child(space)
	move_child(space, 0)
	space.setup(id, arrival)
	space.enemy_killed.connect(_on_kill)
	space.player_destroyed.connect(_on_destroyed)
	space.message.connect(func(t): hud.flash_message(t))
	space.system_used.connect(func(sid, txt): hud.flash_message(txt); hud.pulse(sid))
	hud.space = space

func _on_gs_changed() -> void:
	if state == "flight" and is_instance_valid(space) and GS.shield < GS.max_shield() and space.shield_delay >= 2.9:
		hud.hurt()

func _process(_dt: float) -> void:
	if state == "title" and is_instance_valid(space):
		# slow attract-mode orbit around Liberty Hub
		var t := Time.get_ticks_msec() / 1000.0
		space.cam.global_position = space.station.global_position + Vector3(cos(t * 0.08) * 330, 90, sin(t * 0.08) * 330)
		space.cam.look_at(space.station.global_position, Vector3.UP)
	if state == "flight": hud.objective = _objective()
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
	var enemy_name: String = Data.ENEMIES[space.sys["enemy"]]["name"]
	var st: String = space.sys["station"]["name"]
	var pl: String = space.sys["planet"]["name"]
	var gt: String = space.sys["gate"]["name"]
	if GS.system_id == "solara":
		if GS.kills == 0: return "OBJECTIVE: Destroy a %s (tap TARGET, aim, FIRE)" % enemy_name
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
	match id:
		"missile": space.trigger_system("missile")
		"repair": space.trigger_system("hull")
		"target": space.cycle_target()
		"view":
			space.set_view("cockpit" if GS.view == "chase" else "chase")
			hud.flash_message("View: %s" % ("first-person cockpit" if GS.view == "cockpit" else "chase camera"))
		"comms":
			if hud.comms_open: hud.comms_open = false
			else: hud.open_comms(space.sys["station"]["name"] + " Control", _comms_line())
		"comms_close": hud.comms_open = false
		"cruise":
			space.set_cruise(not space.cruise)
			hud.flash_message("Cruise engines charging…" if space.cruise else "Cruise off.")
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

func _comms_line() -> String:
	var n := space.hostiles_near(900.0)
	if n > 0: return "Pilot, %d hostile%s on your scope. Weapons free — stay sharp." % [n, "" if n == 1 else "s"]
	if space.in_nebula > 0.0: return "We're losing your signal in the nebula. Sensors will be short-ranged in there."
	if space.in_belt: return "Rocks everywhere out there. Throttle down and watch your hull."
	if GS.hull < GS.max_hull() * 0.5: return "You're leaking plasma. Dock with us for free repairs."
	var o := _objective().replace("OBJECTIVE: ", "")
	return "Traffic control here. Recommended: %s." % o.to_lower()

func open_map() -> void:
	state = "map"
	hud.comms_open = false
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
	# any manual aim cancels autopilot
	if state == "flight" and space.autopilot != null and hud.aim_vec.length() > 0.35:
		space.autopilot = null
		hud.flash_message("Autopilot off.")

func _on_kill(reward: int, who: String) -> void:
	GS.kills += 1
	GS.add_credits(reward)
	hud.flash_message("%s destroyed. +%d credits." % [who, reward])

# ---------------------------------------------------------------- docking / hub / launch
func dock(n: Node3D) -> void:
	if state != "flight": return
	state = "docking"
	space.controls = false
	space.autopilot = null
	space.set_cruise(false)
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

# ---------------------------------------------------------------- jump gates
func jump() -> void:
	if state != "flight": return
	state = "jumping"
	space.controls = false
	space.autopilot = null
	space.set_cruise(false)
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
