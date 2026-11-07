class_name StationEscape
extends Node3D
## v12.30 (owner): the station lockdown as a 3D on-foot escape instead of the panorama fight.
## "You're gonna be a pilot ... over the shoulder ... the pilot is on the left side ... target in the middle. Only when
## you have a sniper weapon does it go into first person." Graybox rooms built from breakable blocks (VoxRoom):
##   1 HOLDING CELL - shoot out the cell front, cut through the door
##   2 SECURITY HALL - a catwalk on pillars (shoot the pillars, it comes down), fuel tanks
##   3 HANGAR - run to your own ship and board it: you launch, with their fleet after you
## A fade and a short camera move between rooms. Die and the room starts again.
## Keyboard: WASD move, mouse look (click to grab the mouse), left button fire, right button scope, Q tool,
## G breach charge, Space jump, Shift run, E board. Touch: left of the screen moves, right looks, and buttons.

signal escaped

const ROOMS := [
	{"id": "cell", "title": "HOLDING CELL", "goal": "Break out of the cell, take down the guards, cut through the door."},
	{"id": "hall", "title": "SECURITY HALL", "goal": "Clear the hall. Shoot the pillars to bring the catwalk down. Cut through the far door."},
	{"id": "hangar", "title": "HANGAR", "goal": "Get to your ship and BOARD it."},
]
const WALK := 4.6
const RUN := 7.2
const GRAV := 18.0
const SHOULDER := Vector3(0.72, 0.15, 2.15)   # camera from the shoulder pivot: right, up, back (the pilot sits left of centre)
const FOV := 68.0
const SCOPE_FOV := 22.0
const RIFLE_DMG := 2
const RIFLE_RATE := 0.16
const CUT_RANGE := 7.0
const CUT_DMG := 3
const CUT_RATE := 0.06
const CHARGES := 3
const HP_MAX := 100.0

var faction := ""
var room_i := 0
var room: VoxRoom
var pilot: CharacterBody3D
var body_mesh: Node3D
var cam: Camera3D
var yaw := 0.0
var pitch := -0.08
var scoped := false
var tool := "rifle"            # rifle | cutter
var hp := HP_MAX
var charges := CHARGES
var guards: Array = []         # [{node, hp, cool, alive, vy}]
var door: Array = []           # cells of the way out (cut them to leave)
var ship: Node3D
var busy := true               # (a fade / camera move: no control)
var done := false
var _fire_held := false
var _cool := 0.0
var _move := Vector2.ZERO      # touch stick
var _stick_id := -1
var _stick_o := Vector2.ZERO
var _look_id := -1
var _beam: MeshInstance3D
var _alarm: OmniLight3D
var _t := 0.0
var elog: Array = []            # (tests)
# HUD
var hud: CanvasLayer
var fade: ColorRect
var title_l: Label
var goal_l: Label
var info_l: Label
var hp_bar: ProgressBar
var cross: Control
var scope_ov: Control
var board_btn: Button

func start(fac: String) -> void:
	faction = fac
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.05
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	cam.environment = env
	add_child(cam)
	cam.current = true
	_make_hud()
	_make_pilot()
	pilot_who = {"holder": body_mesh}
	Packs.request(PILOT_PACK)
	Packs.request(guard_glb()[1])
	Packs.request(FLAT_PACK)
	_beam = MeshInstance3D.new()
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.4, 0.9, 1.0)
	_beam.material_override = bm
	_beam.mesh = ImmediateMesh.new()
	add_child(_beam)
	load_room(0)

# ---------------------------------------------------------------- rooms
func load_room(i: int) -> void:
	busy = true
	room_i = i
	fade.color.a = 1.0
	if room != null:
		room.queue_free()
	for g in guards:
		if is_instance_valid(g["node"]): (g["node"] as Node).queue_free()
	guards.clear()
	door.clear()
	if ship != null and is_instance_valid(ship): ship.queue_free()
	ship = null
	for n in get_children():
		if n.is_in_group("esc_light"): n.queue_free()
	room = VoxRoom.new()
	room.name = "Room_" + str(ROOMS[i]["id"])
	add_child(room)
	room.blast.connect(_on_blast)
	var start: Vector3 = call("_build_" + str(ROOMS[i]["id"]))
	room.rebuild_all()
	_reshow(room)   # (the same web fix as the boarding levels)
	hp = HP_MAX
	charges = CHARGES
	scoped = false
	pilot.global_position = start
	pilot.velocity = Vector3.ZERO
	yaw = PI   # (rooms run along +z)
	pitch = -0.08
	body_mesh.rotation.y = PI
	title_l.text = "ROOM %d  ·  %s" % [i + 1, ROOMS[i]["title"]]
	goal_l.text = str(ROOMS[i]["goal"])
	board_btn.visible = false
	elog.append("room:" + str(ROOMS[i]["id"]))
	_intro()

## The cut-scene: from a wide shot of the room down to the shoulder, while the black lifts.
func _intro() -> void:
	var wide := Vector3(room.sx * 0.5, room.sy - 1.6, 1.6)
	var look := Vector3(room.sx * 0.5, 1.0, room.sz * 0.6)
	cam.global_position = wide
	cam.look_at(look)
	var from_t := cam.global_transform
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, 0.6)
	tw.parallel().tween_method(func(k: float):
		var to := _shoulder_xform()
		cam.global_transform = from_t.interpolate_with(to, smoothstep(0.0, 1.0, k)), 0.0, 1.0, 1.6)
	tw.tween_callback(func(): busy = false)

func _reshow(root: Node3D) -> void:
	await get_tree().process_frame
	if not is_instance_valid(root): return
	var ms: Array = root.find_children("*", "VisualInstance3D", true, false)
	for m in ms: (m as VisualInstance3D).visible = false
	await get_tree().process_frame
	for m in ms: if is_instance_valid(m): (m as VisualInstance3D).visible = true

func _shell(w: int, h: int, d: int) -> void:
	room.setup(w, h, d)
	room.box(Vector3i(0, 0, 0), Vector3i(w - 1, 0, d - 1), VoxRoom.M.FLOOR)
	room.box(Vector3i(0, 1, 0), Vector3i(0, h - 1, d - 1), VoxRoom.M.FRAME)
	room.box(Vector3i(w - 1, 1, 0), Vector3i(w - 1, h - 1, d - 1), VoxRoom.M.FRAME)
	room.box(Vector3i(0, 1, 0), Vector3i(w - 1, h - 1, 0), VoxRoom.M.FRAME)
	room.box(Vector3i(0, 1, d - 1), Vector3i(w - 1, h - 1, d - 1), VoxRoom.M.FRAME)
	room.box(Vector3i(0, h - 1, 0), Vector3i(w - 1, h - 1, d - 1), VoxRoom.M.FRAME)
	# inner wall plating (breakable, so shots leave holes) on the side walls
	room.box(Vector3i(1, 1, 1), Vector3i(1, h - 2, d - 2), VoxRoom.M.WALL)
	room.box(Vector3i(w - 2, 1, 1), Vector3i(w - 2, h - 2, d - 2), VoxRoom.M.WALL)
	_lights(w, h, d)

func _door(cx: int, d: int) -> void:   # a blast door in the far wall: cut it to get out
	for y in range(1, 5):
		for x in range(cx - 1, cx + 2):
			room.set_m(x, y, d - 1, VoxRoom.M.WALL)
			door.append(Vector3i(x, y, d - 1))
	var tag := Label3D.new()
	tag.text = "EXIT"
	tag.font_size = 96
	tag.modulate = Color(1.0, 0.35, 0.25)
	tag.position = Vector3(cx + 0.5, 5.6, d - 1.05)
	tag.rotation.y = PI
	room.add_child(tag)

func _lights(w: int, h: int, d: int) -> void:
	for k in range(0, 3):
		var l := OmniLight3D.new()
		l.light_color = Color(0.85, 0.9, 1.0)
		l.light_energy = 1.6
		l.omni_range = maxf(w, d) * 0.7
		l.position = Vector3(w * 0.5, h - 2.0, d * (0.2 + 0.3 * k))
		l.add_to_group("esc_light")
		add_child(l)
	_alarm = OmniLight3D.new()
	_alarm.light_color = Color(1.0, 0.15, 0.1)
	_alarm.omni_range = maxf(w, d)
	_alarm.position = Vector3(w * 0.5, h - 1.5, d * 0.5)
	_alarm.add_to_group("esc_light")
	add_child(_alarm)

func _build_cell() -> Vector3:
	var w := 16
	var d := 15
	_shell(w, 7, d)
	# the cell at the back: bars (pipes) with glass between, up to the ceiling
	for x in range(4, 12):
		room.box(Vector3i(x, 1, 6), Vector3i(x, 5, 6), VoxRoom.M.PIPE if x % 2 == 0 else VoxRoom.M.GLASS)
	room.box(Vector3i(3, 1, 1), Vector3i(3, 5, 6), VoxRoom.M.WALL)
	room.box(Vector3i(12, 1, 1), Vector3i(12, 5, 6), VoxRoom.M.WALL)
	room.box(Vector3i(4, 1, 2), Vector3i(6, 1, 2), VoxRoom.M.CRATE)   # (a bunk)
	# the guard room: desk and console, crates
	room.box(Vector3i(6, 1, 10), Vector3i(9, 1, 10), VoxRoom.M.CONSOLE)
	room.box(Vector3i(7, 2, 10), Vector3i(8, 2, 10), VoxRoom.M.CONSOLE)
	room.box(Vector3i(2, 1, 11), Vector3i(3, 2, 12), VoxRoom.M.CRATE)
	room.box(Vector3i(12, 1, 9), Vector3i(13, 1, 10), VoxRoom.M.CRATE)
	room.box(Vector3i(2, 1, 8), Vector3i(2, 4, 8), VoxRoom.M.PIPE)
	_door(8, d)
	_guard(Vector3(5.5, 1.0, 12.0))
	_guard(Vector3(11.5, 1.0, 12.5))
	return Vector3(8.0, 1.05, 3.5)

func _build_hall() -> Vector3:
	var w := 30
	var d := 27
	_shell(w, 11, d)
	# the catwalk across the hall, on pillars that don't touch the walls: shoot them and it comes down
	room.box(Vector3i(4, 5, 13), Vector3i(25, 5, 18), VoxRoom.M.WALL)
	room.box(Vector3i(4, 6, 13), Vector3i(25, 6, 13), VoxRoom.M.PIPE)   # (rail)
	for px in [5, 14, 23]:
		room.box(Vector3i(px, 1, 15), Vector3i(px + 1, 4, 16), VoxRoom.M.PILLAR)
	# fuel tanks by two of the pillars (a chain)
	room.box(Vector3i(8, 1, 15), Vector3i(9, 3, 16), VoxRoom.M.TANK)
	room.box(Vector3i(20, 1, 15), Vector3i(21, 3, 16), VoxRoom.M.TANK)
	# cover
	for c in [Vector3i(6, 1, 7), Vector3i(13, 1, 9), Vector3i(21, 1, 6), Vector3i(10, 1, 21), Vector3i(18, 1, 22)]:
		room.box(c, c + Vector3i(2, 1, 1), VoxRoom.M.CRATE)
	room.box(Vector3i(2, 1, 20), Vector3i(3, 2, 24), VoxRoom.M.CONSOLE)
	room.box(Vector3i(26, 1, 3), Vector3i(27, 3, 3), VoxRoom.M.CONSOLE)
	_door(15, d)
	_guard(Vector3(9.5, 6.0, 14.5))
	_guard(Vector3(19.5, 6.0, 17.5))
	_guard(Vector3(12.0, 1.0, 20.0))
	_guard(Vector3(22.0, 1.0, 11.0))
	return Vector3(15.0, 1.05, 2.5)

func _build_hangar() -> Vector3:
	var w := 40
	var d := 38
	_shell(w, 16, d)
	# a gantry over the pad and stacks of crates; fuel tanks
	room.box(Vector3i(8, 9, 24), Vector3i(31, 9, 25), VoxRoom.M.WALL)
	for px in [8, 30]:
		room.box(Vector3i(px, 1, 24), Vector3i(px + 1, 8, 25), VoxRoom.M.PILLAR)
	for c in [Vector3i(5, 1, 8), Vector3i(30, 1, 10), Vector3i(12, 1, 15), Vector3i(25, 1, 17), Vector3i(4, 1, 20)]:
		room.box(c, c + Vector3i(2, 2, 2), VoxRoom.M.CRATE)
	room.box(Vector3i(17, 1, 12), Vector3i(18, 3, 13), VoxRoom.M.TANK)
	room.box(Vector3i(33, 1, 22), Vector3i(34, 3, 23), VoxRoom.M.TANK)
	room.box(Vector3i(14, 1, 26), Vector3i(25, 1, 35), VoxRoom.M.FLOOR)   # (the landing pad, raised a block)
	_ship()
	_guard(Vector3(10.0, 1.0, 16.0))
	_guard(Vector3(28.0, 1.0, 14.0))
	_guard(Vector3(20.0, 10.0, 24.5))
	_guard(Vector3(6.0, 1.0, 28.0))
	_guard(Vector3(33.0, 1.0, 30.0))
	return Vector3(20.0, 1.05, 2.5)

func _ship() -> void:
	var m: Node3D = ShipFactory.build(GS.ship_id)
	if m == null:
		m = Node3D.new()
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(6, 2, 10)
		mi.mesh = pm
		mi.rotation.x = -PI / 2
		m.add_child(mi)
	ship = Node3D.new()
	ship.name = "YourShip"
	ship.add_child(m)
	add_child(ship)
	var bb := _aabb(m)
	var size := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	var k := 11.0 / maxf(size, 0.01)
	m.scale = Vector3.ONE * k
	m.position = -bb.get_center() * k
	ship.position = Vector3(20.0, 2.0 + bb.size.y * k * 0.5, 31.0)
	ship.rotation.y = PI

func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null: continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D: xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-3, -1, -5), Vector3(6, 2, 10))

# ---------------------------------------------------------------- the pilot
func _make_pilot() -> void:
	pilot = CharacterBody3D.new()
	pilot.name = "Pilot"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	pilot.add_child(cs)
	add_child(pilot)
	body_mesh = Node3D.new()
	pilot.add_child(body_mesh)
	var gray := Node3D.new()
	gray.name = "Gray"
	body_mesh.add_child(gray)
	var suit := Color(0.85, 0.55, 0.2)
	var dark := Color(0.18, 0.2, 0.24)
	_part(gray, Vector3(0.0, 1.22, 0.0), Vector3(0.46, 0.55, 0.28), suit)          # chest
	_part(gray, Vector3(0.0, 0.88, 0.0), Vector3(0.38, 0.22, 0.24), dark)          # belt
	_part(gray, Vector3(0.0, 1.27, 0.17), Vector3(0.36, 0.42, 0.12), dark)         # pack
	_part(gray, Vector3(0.0, 1.7, 0.0), Vector3(0.28, 0.3, 0.3), suit.lightened(0.15), true)   # helmet
	_part(gray, Vector3(0.0, 1.71, -0.13), Vector3(0.22, 0.12, 0.06), Color(0.2, 0.75, 1.0))   # visor
	for s in [-1.0, 1.0]:
		_part(gray, Vector3(0.12 * s, 0.45, 0.0), Vector3(0.16, 0.86, 0.18), suit.darkened(0.2))   # legs
		_part(gray, Vector3(0.3 * s, 1.2, -0.12), Vector3(0.13, 0.5, 0.14), suit.darkened(0.1))     # arms
	_part(body_mesh, Vector3(0.22, 1.2, -0.42), Vector3(0.08, 0.1, 0.75), dark).name = "GrayRifle"   # rifle (until the real one loads)

func _part(parent: Node3D, at: Vector3, size: Vector3, col: Color, round := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if round:
		var sm := SphereMesh.new()
		sm.radius = size.x * 0.5
		sm.height = size.y
		mi.mesh = sm
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	mi.material_override = m
	mi.position = at
	parent.add_child(mi)
	return mi

func _aim_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))

func _pivot() -> Vector3:
	return pilot.global_position + Vector3(0, 1.55, 0)

func _shoulder_xform() -> Transform3D:
	var b := _aim_basis()
	if scoped:
		return Transform3D(b, pilot.global_position + Vector3(0, 1.68, 0) + b * Vector3(0, 0, -0.25))
	var want := _pivot() + b * SHOULDER
	var r := room.ray(_pivot(), want - _pivot(), (want - _pivot()).length()) if room != null else {}
	if not r.is_empty():
		want = _pivot() + (want - _pivot()).normalized() * maxf(0.3, float(r["dist"]) - 0.25)
	return Transform3D(b, want)

## Where the crosshair points: {point, cell, normal, guard}
func aim() -> Dictionary:
	var o := cam.global_position
	var dir := -cam.global_basis.z
	var r := room.ray(o, dir, 120.0)
	var far: float = float(r["dist"]) if not r.is_empty() else 120.0
	var hit := {"point": o + dir * far, "cell": r.get("cell", null), "normal": r.get("normal", Vector3.ZERO), "guard": null, "dist": far}
	for g in guards:
		if not g["alive"]: continue
		var gp: Vector3 = (g["node"] as Node3D).global_position + Vector3(0, 0.95, 0)
		var t := (gp - o).dot(dir)
		if t < 0.0 or t > far: continue
		if (o + dir * t).distance_to(gp) < 0.55:
			far = t
			hit = {"point": o + dir * t, "cell": null, "normal": -dir, "guard": g, "dist": t}
	return hit

# ---------------------------------------------------------------- play
func _physics_process(dt: float) -> void:
	if room == null: return
	_t += dt
	room.tick(dt)
	if _alarm != null: _alarm.light_energy = 1.5 + 1.5 * sin(_t * 6.0)
	_guards(dt)
	_dress_all(dt)
	if pilot != null and body_mesh != null: _update_gear(dt)
	if busy or done:
		return
	var mv := _move
	if mv == Vector2.ZERO:
		mv = Vector2(Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"), Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up"))
		if Input.is_physical_key_pressed(KEY_D): mv.x += 1.0
		if Input.is_physical_key_pressed(KEY_A): mv.x -= 1.0
		if Input.is_physical_key_pressed(KEY_S): mv.y += 1.0
		if Input.is_physical_key_pressed(KEY_W): mv.y -= 1.0
	mv = mv.limit_length(1.0)
	var flat := Basis(Vector3.UP, yaw)
	var wish := flat * Vector3(mv.x, 0, mv.y)
	var spd := RUN if (Input.is_physical_key_pressed(KEY_SHIFT) or run_on) else WALK
	if scoped: spd *= 0.45
	var v := pilot.velocity
	v.x = move_toward(v.x, wish.x * spd, 30.0 * dt)
	v.z = move_toward(v.z, wish.z * spd, 30.0 * dt)
	v.y -= GRAV * dt
	pilot.velocity = v
	pilot.move_and_slide()
	# the pilot turns to where they walk; while firing or aiming they face the crosshair (no sidestep shuffle)
	var face := yaw
	if not (_fire_held or scoped) and wish.length() > 0.1: face = atan2(-wish.x, -wish.z)
	body_mesh.rotation.y = lerp_angle(body_mesh.rotation.y, face, minf(1.0, 12.0 * dt))
	_anim(pilot_who, "Walk" if Vector2(v.x, v.z).length() > 0.6 else "Idle")
	_pilot_pose(dt, Vector2(v.x, v.z).length())
	body_mesh.visible = not scoped
	cam.fov = lerpf(cam.fov, SCOPE_FOV if scoped else FOV, minf(1.0, 14.0 * dt))
	cam.global_transform = _shoulder_xform()
	scope_ov.visible = scoped
	_cool -= dt
	_draw_beam(false)
	if _fire_held: fire(dt)
	if pilot.global_position.y < -6.0: hurt(999.0)
	_check_exit()
	info_l.text = "%s   ·   CHARGES %d   ·   GUARDS %d" % ["CUTTER" if tool == "cutter" else ("RIFLE (SCOPED)" if scoped else "RIFLE"), charges, _alive()]
	hp_bar.value = hp

func fire(_dt := 0.0) -> void:
	if busy or done or _cool > 0.0: return
	var a := aim()
	if tool == "cutter":
		_cool = CUT_RATE
		var reach: float = float(a["dist"])
		if reach > CUT_RANGE: return
		_draw_beam(true, a["point"])
		if a["guard"] != null: _hurt_guard(a["guard"], 1)
		elif a["cell"] != null:
			if room.hit_cell(a["cell"], CUT_DMG): room.cut_cells += 1
			if randf() < 0.25: room.mark(a["point"], a["normal"], 0.35)
		return
	_cool = RIFLE_RATE * (2.2 if scoped else 1.0)
	var dmg := RIFLE_DMG * (3 if scoped else 1)
	if a["guard"] != null: _hurt_guard(a["guard"], dmg)
	elif a["cell"] != null:
		room.hit_cell(a["cell"], dmg)
		room.mark(a["point"], a["normal"], 0.9)
	_tracer(pilot.global_position + Vector3(0, 1.3, 0) + _aim_basis() * Vector3(0.22, 0, -0.8), a["point"])

func throw_charge() -> void:
	if busy or done or charges <= 0: return
	var a := aim()
	if float(a["dist"]) > 30.0: return
	charges -= 1
	var at: Vector3 = a["point"] + (a["normal"] as Vector3) * 0.2
	var puck := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 0.1
	puck.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(1.0, 0.2, 0.1)
	pm.emission_enabled = true
	pm.emission = Color(1.0, 0.2, 0.1)
	puck.material_override = pm
	add_child(puck)
	puck.global_position = at
	elog.append("charge")
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(puck): puck.queue_free()
		if room != null and is_instance_valid(room):
			room.explode(at, 2.8, 24)
			room.mark(at, a["normal"], 4.5))

func _on_blast(at: Vector3, radius: float) -> void:
	for g in guards:
		if g["alive"] and (g["node"] as Node3D).global_position.distance_to(at) < radius + 1.5: _hurt_guard(g, 12)
	var d := pilot.global_position.distance_to(at)
	if d < radius + 1.0: hurt(45.0 * (1.0 - d / (radius + 1.0)) + 10.0)
	room.mark(at, Vector3.UP, radius * 1.6)

func hurt(n: float) -> void:
	if done or busy: return
	hp -= n
	if hp <= 0.0:
		hp = 0.0
		busy = true
		elog.append("died:%s y%.1f" % ["fall" if n >= 999.0 else "hit", pilot.global_position.y])
		goal_l.text = "YOU WERE TAKEN DOWN. Again..."
		var tw := create_tween()
		tw.tween_property(fade, "color:a", 1.0, 0.8)
		tw.tween_callback(func(): load_room(room_i))

func _alive() -> int:
	var n := 0
	for g in guards: if g["alive"]: n += 1
	return n

func door_open() -> bool:
	for c in door:
		if room.get_m(c.x, c.y, c.z) != VoxRoom.M.AIR: return false
	return true

func _check_exit() -> void:
	if str(ROOMS[room_i]["id"]) == "hangar":
		var near := ship != null and pilot.global_position.distance_to(ship.global_position) < 9.0
		board_btn.visible = near
		if near and Input.is_physical_key_pressed(KEY_E): board()
		return
	if pilot.global_position.z > room.sz - 2.4 and door_open():
		if _alive() > 0:
			goal_l.text = "Guards still standing: %d. Clear the room first." % _alive()
			return
		next_room()

func next_room() -> void:
	busy = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.5)
	tw.tween_callback(func(): load_room(room_i + 1))

func board() -> void:
	if done: return
	done = true
	busy = true
	elog.append("boarded")
	goal_l.text = "ABOARD. Launching..."
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.8)
	tw.tween_callback(func(): escaped.emit())

# ---------------------------------------------------------------- guards
func _guard(at: Vector3) -> void:
	var n := Node3D.new()
	n.name = "Guard"
	var gray := Node3D.new()
	gray.name = "Gray"
	n.add_child(gray)
	var col := Color(0.35, 0.38, 0.42)
	_part(gray, Vector3(0, 1.2, 0), Vector3(0.5, 0.6, 0.3), col)
	_part(gray, Vector3(0, 1.72, 0), Vector3(0.3, 0.32, 0.32), Color(0.85, 0.2, 0.15), true)
	_part(gray, Vector3(0, 0.45, 0), Vector3(0.42, 0.9, 0.22), col.darkened(0.3))
	_part(n, Vector3(0.2, 1.25, -0.38), Vector3(0.08, 0.1, 0.65), Color(0.1, 0.1, 0.12))
	room.add_child(n)
	n.position = at
	var g := {"node": n, "hp": 6, "cool": randf_range(1.0, 2.5), "alive": true, "vy": 0.0, "flat": guards.size() % 2 == 1}
	guards.append(g)
	if g["flat"]: _dress_flat(g)
	else: _dress(g, guard_glb()[0], guard_glb()[1], 1.85)

## v12.34 (owner: "use glb HL character"): the real rigged HL characters instead of the grey blocks: the pilot is Orion's
## blond armored pilot (#10), the guards the armoured future soldier. Their packs are fetched on the web; until they
## arrive (or if they can't), the grey stand-ins stay. Walk / Idle from the model's own clips.
## v12.34 (owner: "the guy on the left" in his Tripo sheet, "hl hova.glb"; "we got weapon same as mech"): you are his
## white-suited pilot with the mech's rifle. The guards are the rigged GLB soldiers (owner: "use glb soldiers for alarm
## room battles"): Orion's white dragon soldier in an Orion lockdown, the armoured future soldier elsewhere.
const PILOT_GLB := "res://assets/pilot/hl_hova.glb"
const PILOT_PACK := "pilot"
const RIFLE_GLB := "res://assets/pilot/pilot_rifle.glb"
const GUARD_GLB := "res://assets/crowd3d/future_soldier.glb"
const GUARD_PACK := "crowd3d"
const GUARD_GLB_ORION := "res://assets/crowd3d_orion/HL_Orion_02_WhiteDragonSoldier_Rigged.glb"
const GUARD_PACK_ORION := "crowd3d_orion"
func guard_glb() -> Array:
	return [GUARD_GLB_ORION, GUARD_PACK_ORION] if faction == "orion" else [GUARD_GLB, GUARD_PACK]
var pilot_who := {}   # {holder, anim, dressed}

func _dress(who: Dictionary, path: String, pack: String, height: float) -> void:
	if bool(who.get("dressed", false)): return
	if not Packs.is_ready(pack):
		Packs.request(pack)
		return
	if not ResourceLoader.exists(path): return
	var holder: Node3D = who["node"] if who.has("node") else who["holder"]
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	var bb := _aabb(inst)
	var k := height / maxf(0.01, bb.size.y)
	inst.scale = Vector3.ONE * k
	inst.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
	# the models face +Z (arms across X); one whose arms lie across Z faces along X: turn it to look down -Z like ours
	var side_on := bb.size.z > bb.size.x * 1.3
	inst.rotation.y = -PI / 2 if side_on else PI
	who["lateral"] = Vector3(0, 0, 1) if side_on else Vector3(1, 0, 0)
	holder.add_child(inst)
	var gray := holder.get_node_or_null("Gray")
	if gray: (gray as Node3D).visible = false
	who["dressed"] = true
	who["anim"] = null
	for ap in inst.find_children("*", "AnimationPlayer", true, false):
		who["anim"] = ap
		for a in (ap as AnimationPlayer).get_animation_list():
			(ap as AnimationPlayer).get_animation(a).loop_mode = Animation.LOOP_LINEAR
		break
	_anim(who, "Idle")
	if who == pilot_who: _pilot_rig(inst)
	elog.append("dressed:" + path.get_file())

## His model has a skeleton but no clips: a simple walk is made here (legs swing, knees bend, a little bob), arms
## brought forward to hold the rifle, which is the mech's own gun.
var _skel: Skeleton3D
var _bones := {}
var _walk_ph := 0.0
var _walk_k := 0.0
var rifle_model: Node3D
var arm_up := 1.0     # (tuned by eye: arms forward to the rifle)
var elbow := 0.9
func _pilot_rig(inst: Node3D) -> void:
	for sk in inst.find_children("*", "Skeleton3D", true, false):
		_skel = sk
		break
	if _skel != null:
		for nm in ["L_Thigh", "R_Thigh", "L_Calf", "R_Calf", "L_Upperarm", "R_Upperarm", "L_Forearm", "R_Forearm", "Spine01"]:
			var i := _skel.find_bone(nm)
			if i >= 0: _bones[nm] = i
	var gray_rifle: Node = body_mesh.get_node_or_null("GrayRifle")
	if ResourceLoader.exists(RIFLE_GLB):
		rifle_model = (load(RIFLE_GLB) as PackedScene).instantiate()
		var bb := _aabb(rifle_model)
		var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		var k := 0.95 / maxf(0.01, longest)
		var holder := Node3D.new()
		holder.name = "Rifle"
		body_mesh.add_child(holder)
		holder.position = Vector3(0.2, 1.18, -0.35)
		holder.add_child(rifle_model)
		rifle_model.scale = Vector3.ONE * k
		rifle_model.position = -bb.get_center() * k
		if bb.size.x >= bb.size.z: rifle_model.rotation.y = PI / 2   # (lay it along the aim)
		if gray_rifle is MeshInstance3D: (gray_rifle as Node3D).visible = false

## turn bone b about a body axis (in the skeleton's space) by angle a, from its rest
func _bone_turn(name: String, axis: Vector3, a: float) -> void:
	if not _bones.has(name): return
	var b: int = _bones[name]
	var rest := _skel.get_bone_rest(b)
	var par := _skel.get_bone_parent(b)
	var pg: Transform3D = _skel.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
	var gr: Transform3D = (_skel.get_bone_global_rest(par) if par >= 0 else Transform3D.IDENTITY) * rest
	var want := Basis(axis.normalized(), a) * gr.basis
	_skel.set_bone_pose_rotation(b, (pg.basis.inverse() * want).get_rotation_quaternion())

func _pilot_pose(dt: float, speed: float) -> void:
	if _skel == null: return
	_walk_k = move_toward(_walk_k, clampf(speed / RUN, 0.0, 1.0), dt * 4.0)
	_walk_ph += dt * (6.0 + speed * 1.1)
	var sw := sin(_walk_ph) * 0.55 * _walk_k
	var ax: Vector3 = pilot_who.get("lateral", Vector3.RIGHT)
	for nm in _bones: _skel.reset_bone_pose(_bones[nm])
	_bone_turn("L_Thigh", ax, sw)
	_bone_turn("R_Thigh", ax, -sw)
	_bone_turn("L_Calf", ax, -maxf(0.0, -cos(_walk_ph)) * 0.8 * _walk_k)
	_bone_turn("R_Calf", ax, -maxf(0.0, cos(_walk_ph)) * 0.8 * _walk_k)
	# arms up to the rifle (forward, elbows bent), a little sway
	_bone_turn("R_Upperarm", ax, arm_up + sw * 0.1)
	_bone_turn("L_Upperarm", ax, arm_up + 0.15 + sw * 0.1)
	_bone_turn("R_Forearm", ax, elbow)
	_bone_turn("L_Forearm", ax, elbow * 0.8)
	body_mesh.position.y = absf(sin(_walk_ph)) * 0.04 * _walk_k

func _anim(who: Dictionary, clip: String) -> void:
	var ap: AnimationPlayer = who.get("anim")
	if ap == null or not is_instance_valid(ap): return
	for a in ap.get_animation_list():
		if str(a).to_lower().ends_with(clip.to_lower()):
			if ap.current_animation != a: ap.play(a, 0.2)
			return

## v12.34 (owner: "try the 2D animation enemy as well as GLB enemies to test in the alarm"): every other guard is the
## owner's 2D animated soldier (his clips as sprite sheets: idle, run, shoot, fall), standing in the 3D room as a
## picture that always faces you; the rest are GLB soldiers.
const FLAT_PACK := "anim_orion"
const FLAT_DIR := "res://assets/characters/orion/anim/"
var _sheets := {}
func _sheet(name: String) -> Dictionary:
	if _sheets.has(name): return _sheets[name]
	var base := FLAT_DIR + name
	if not (ResourceLoader.exists(base + ".webp") and FileAccess.file_exists(base + ".json")): return {}
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	if not (j is Dictionary): return {}
	var d: Dictionary = j
	d["tex"] = load(base + ".webp")
	_sheets[name] = d
	return d

func _dress_flat(g: Dictionary) -> void:
	if not Packs.is_ready(FLAT_PACK):
		Packs.request(FLAT_PACK)
		return
	var d := _sheet("guard_idle")
	if d.is_empty(): return
	var sp := Sprite3D.new()
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.shaded = false
	sp.region_enabled = true
	(g["node"] as Node3D).add_child(sp)
	var gray := (g["node"] as Node3D).get_node_or_null("Gray")
	if gray: (gray as Node3D).visible = false
	for c in (g["node"] as Node3D).get_children():
		if c is MeshInstance3D: (c as Node3D).visible = false   # (its block rifle too: the picture has its own)
	g["sprite"] = sp
	g["clip"] = ""
	g["ct"] = 0.0
	g["dressed"] = true
	elog.append("dressed:2d")
	_flat_clip(g, "guard_idle")

func _flat_clip(g: Dictionary, name: String) -> void:
	if str(g.get("clip", "")) == name: return
	var d := _sheet(name)
	if d.is_empty(): return
	g["clip"] = name
	g["ct"] = 0.0
	var sp: Sprite3D = g["sprite"]
	sp.texture = d["tex"]
	var px: float = 1.85 / float(d.get("stand", d["fh"]))
	sp.pixel_size = px
	var foot: Array = d.get("foot", [float(d["fw"]) * 0.5, float(d["fh"])])
	# the feet (foot px, from the top-left) on the ground at the guard's spot
	sp.offset = Vector2(-(float(foot[0]) - float(d["fw"]) * 0.5), 0.0)   # (sideways: turns with the picture)
	sp.position = Vector3(0, (float(foot[1]) - float(d["fh"]) * 0.5) * px, 0)

func _flat_tick(g: Dictionary, dt: float) -> void:
	if not g.has("sprite"): return
	var want := "guard_idle"
	if not g["alive"]: want = "guard_fall"
	elif float(g.get("shot_t", 0.0)) > 0.0: want = "guard_shoot"
	elif bool(g.get("moving", false)): want = "guard_run"
	_flat_clip(g, want)
	var d := _sheet(str(g["clip"]))
	if d.is_empty(): return
	g["ct"] = float(g["ct"]) + dt
	var n := int(d["frames"])
	var f := int(float(g["ct"]) * float(d["fps"]))
	f = mini(f, n - 1) if want == "guard_fall" else f % n
	var cols := int(d["cols"])
	(g["sprite"] as Sprite3D).region_rect = Rect2((f % cols) * float(d["fw"]), (f / cols) * float(d["fh"]), float(d["fw"]), float(d["fh"]))
	g["shot_t"] = maxf(0.0, float(g.get("shot_t", 0.0)) - dt)

var _dress_t := 0.0
func _dress_all(dt: float) -> void:
	_dress_t -= dt
	if _dress_t > 0.0: return
	_dress_t = 0.5
	if not bool(pilot_who.get("dressed", false)): _dress(pilot_who, PILOT_GLB, PILOT_PACK, 1.8)
	for g in guards:
		if bool(g.get("dressed", false)) or not g["alive"]: continue
		if g["flat"]: _dress_flat(g)
		else: _dress(g, guard_glb()[0], guard_glb()[1], 1.85)

func _hurt_guard(g: Dictionary, dmg: int) -> void:
	if not g["alive"]: return
	g["hp"] = int(g["hp"]) - dmg
	if int(g["hp"]) <= 0:
		g["alive"] = false
		elog.append("guard_down")
		var n: Node3D = g["node"]
		var ap: AnimationPlayer = g.get("anim")
		if ap != null and is_instance_valid(ap): ap.pause()
		if g.has("sprite"): return   # (the 2D soldier plays its own fall)
		var tw := create_tween()
		tw.tween_property(n, "rotation:x", -PI / 2, 0.4)

func _guards(dt: float) -> void:
	for g in guards:
		var n: Node3D = g["node"]
		if not is_instance_valid(n): continue
		# standing on something? (shoot the catwalk out from under them and they fall)
		var feet := n.position + Vector3(0, -0.05, 0)
		if room.solid_at(feet):
			g["vy"] = 0.0
		else:
			g["vy"] = float(g["vy"]) - GRAV * dt
			n.position.y += float(g["vy"]) * dt
			if room.solid_at(n.position + Vector3(0, -0.05, 0)):
				n.position.y = ceilf(n.position.y)
				if float(g["vy"]) < -9.0: _hurt_guard(g, 99)
				g["vy"] = 0.0
			if n.position.y < -6.0: _hurt_guard(g, 99)
		_flat_tick(g, dt)
		if not g["alive"] or busy or done: continue
		var to := pilot.global_position - n.global_position
		var flat := Vector3(to.x, 0, to.z)
		n.rotation.y = lerp_angle(n.rotation.y, atan2(-flat.x, -flat.z), minf(1.0, 5.0 * dt))
		var eye := n.global_position + Vector3(0, 1.6, 0)
		var target := pilot.global_position + Vector3(0, 1.3, 0)
		var r := room.ray(eye, target - eye, eye.distance_to(target))
		var sees := r.is_empty()
		if sees and flat.length() > 9.0:   # close in, a step at a time, if the way is clear
			var step := flat.normalized() * 2.2 * dt
			var np := n.position + step
			if not room.solid_at(np + Vector3(0, 0.5, 0)) and not room.solid_at(np + Vector3(0, 1.5, 0)) and room.solid_at(np + Vector3(0, -0.05, 0)):
				n.position = np
				_anim(g, "Walk")
				g["moving"] = true
		else:
			_anim(g, "Idle")
			g["moving"] = false
		g["cool"] = float(g["cool"]) - dt
		if sees and float(g["cool"]) <= 0.0:
			g["cool"] = randf_range(1.1, 1.8)
			g["shot_t"] = 0.6
			var miss := randf() < clampf(flat.length() / 30.0, 0.25, 0.7)
			var at := target + (Vector3(randf_range(-1.5, 1.5), randf_range(-0.6, 1.0), randf_range(-1.5, 1.5)) if miss else Vector3.ZERO)
			_tracer(eye, at, Color(1.0, 0.35, 0.2))
			if not miss:
				var facing := Basis(Vector3.UP, yaw) * Vector3.FORWARD
				if shield_on and facing.dot((n.global_position - pilot.global_position).normalized()) > 0.3:
					energy = maxf(0.0, energy - 6.0)   # (it stopped on the shield)
					elog.append("blocked")
				else: hurt(7.0)

# ---------------------------------------------------------------- effects
func _tracer(a: Vector3, b: Vector3, col := Color(1.0, 0.9, 0.5)) -> void:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	mi.mesh = im
	add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)

func _draw_beam(on: bool, to := Vector3.ZERO) -> void:
	var im := _beam.mesh as ImmediateMesh
	if not on:
		if not _fire_held or tool != "cutter": im.clear_surfaces()
		return
	im.clear_surfaces()
	var a := pilot.global_position + Vector3(0, 1.25, 0) + _aim_basis() * Vector3(0.22, 0, -0.8)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in 3:
		var j := Vector3(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03), randf_range(-0.03, 0.03))
		im.surface_add_vertex(a + j)
		im.surface_add_vertex(to + j)
	im.surface_end()

# ---------------------------------------------------------------- input
func _unhandled_input(e: InputEvent) -> void:
	if room == null or done: return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not DisplayServer.is_touchscreen_available():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_fire_held = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			toggle_scope()
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look((e as InputEventMouseMotion).relative * 0.0035)
	elif e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		match (e as InputEventKey).physical_keycode:
			KEY_Q: switch_tool()
			KEY_G: throw_charge()
			KEY_F: toggle_shield()
			KEY_V: swing()
			KEY_SPACE: jump()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ---------------------------------------------------------------- v12.35 the mech-style pad
const PAD_BTNS := [["fire", "FIRE", 0, 0], ["shield", "SHIELD", 1, 0], ["sword", "SWORD", 0, 1], ["jump", "JUMP", 1, 1],
	["scope", "SCOPE", 2, 0], ["cutter", "CUTTER", 3, 0], ["charge", "CHARGE", 2, 1], ["run", "RUN", 3, 1]]
const PAD_COL := {"fire": Color(1.0, 0.35, 0.3), "shield": Color(0.3, 0.75, 1.0), "sword": Color(0.45, 0.95, 1.0), "jump": Color(1.0, 0.6, 0.2),
	"scope": Color(1.0, 0.85, 0.3), "cutter": Color(0.4, 1.0, 0.85), "charge": Color(1.0, 0.45, 0.2), "run": Color(0.5, 1.0, 0.5)}
var pad: Control
var _touch := {}     # finger -> "move" | "aim" | "look" | button id
var _aim := Vector2.ZERO
var _held := {}
var run_on := false
var energy := 100.0
var shield_on := false
var _shield_mesh: MeshInstance3D
var _shield_light: OmniLight3D
var _blade: MeshInstance3D
var _swing := 0.0

func _pad_geo() -> Dictionary:
	var S := get_viewport().get_visible_rect().size
	var R := S.y * 0.12
	var h := S.y * 0.062
	var out := {"S": S, "R": R, "move": Vector2(R * 1.35, S.y - R * 1.35), "aim": Vector2(S.x - R * 1.35, S.y - R * 1.35), "h": h, "btn": {}}
	var mid := S.x * 0.5
	for b in PAD_BTNS:
		var col: int = b[2]
		var x: float = mid + (col - 1.5) * h * 2.15 + (h * 1.6 if col >= 2 else -h * 1.6)
		var y: float = S.y - h * 1.25 - (1 - int(b[3])) * h * 2.0
		out["btn"][b[0]] = Vector2(x, y)
	return out

func _pad_hit(p: Vector2) -> String:
	var g := _pad_geo()
	for id in g["btn"]:
		if p.distance_to(g["btn"][id]) < float(g["h"]) * 1.05: return id
	if p.distance_to(g["move"]) < float(g["R"]) * 1.5: return "move"
	if p.distance_to(g["aim"]) < float(g["R"]) * 1.5: return "aim"
	if p.y < float(g["S"].y) * 0.82 and p.y > float(g["S"].y) * 0.14: return "look"
	return ""

func _input(e: InputEvent) -> void:
	if room == null or done: return
	if e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			var w := _pad_hit(t.position)
			if w == "": return
			_touch[t.index] = w
			_pad_press(w, true)
			if w == "move" or w == "aim": _pad_stick(w, t.position)
			get_viewport().set_input_as_handled()
		elif _touch.has(t.index):
			var w2: String = _touch[t.index]
			_touch.erase(t.index)
			_pad_press(w2, false)
			if w2 == "move": _move = Vector2.ZERO
			if w2 == "aim": _aim = Vector2.ZERO
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if not _touch.has(d.index): return
		var w3: String = _touch[d.index]
		if w3 == "move" or w3 == "aim": _pad_stick(w3, d.position)
		elif w3 == "look": _look(d.relative * (0.002 if scoped else 0.005))
		get_viewport().set_input_as_handled()

func _pad_stick(which: String, p: Vector2) -> void:
	var g := _pad_geo()
	var v: Vector2 = ((p - (g[which] as Vector2)) / float(g["R"])).limit_length(1.0)
	if which == "move": _move = v
	else: _aim = v

func _pad_press(id: String, down: bool) -> void:
	if down: _held[id] = true
	else: _held.erase(id)
	match id:
		"fire": _fire_held = down
		"shield": if down: toggle_shield()
		"sword": if down: swing()
		"jump": if down: jump()
		"scope": if down: toggle_scope()
		"cutter": if down: switch_tool()
		"charge": if down: throw_charge()
		"run": if down: run_on = not run_on

func _draw_pad() -> void:
	var g := _pad_geo()
	var HS := preload("res://scripts/hud.gd")
	HS.draw_stick(pad, g["move"], g["R"], _move, _move != Vector2.ZERO)
	HS.draw_stick(pad, g["aim"], g["R"], _aim, _aim != Vector2.ZERO)
	var h: float = g["h"]
	var font := ThemeDB.fallback_font
	for b in PAD_BTNS:
		var id: String = b[0]
		var c: Vector2 = g["btn"][id]
		var col: Color = PAD_COL[id]
		var on: bool = _held.has(id) or (id == "shield" and shield_on) or (id == "scope" and scoped) or (id == "cutter" and tool == "cutter") or (id == "run" and run_on)
		var hexp := PackedVector2Array()
		for k in 7: hexp.append(c + Vector2.from_angle(TAU * k / 6.0 + PI / 6.0) * h)
		pad.draw_colored_polygon(hexp.slice(0, 6), Color(col.darkened(0.5), 0.95) if on else Color(0.02, 0.08, 0.15, 0.9))
		pad.draw_polyline(hexp, col, 2.5, true)
		var label: String = b[1]
		if id == "charge": label = "CHARGE %d" % charges
		var fs := int(h * 0.3)
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		pad.draw_string_outline(font, c + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		pad.draw_string(font, c + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if on else col.lightened(0.3))
	# the gauge between the two groups: HEALTH (green) and ENERGY (blue) rings
	var gc := Vector2(float(g["S"].x) * 0.5, float(g["S"].y) - h * 2.25)
	var gr := h * 1.25
	pad.draw_circle(gc, gr + 6.0, Color(0.01, 0.04, 0.09, 0.85))
	pad.draw_arc(gc, gr, PI * 0.75, PI * 0.75 + PI * 1.5 * clampf(hp / HP_MAX, 0.0, 1.0), 40, Color(0.3, 0.95, 0.5), 8.0, true)
	pad.draw_arc(gc, gr - 11.0, PI * 0.75, PI * 0.75 + PI * 1.5 * clampf(energy / 100.0, 0.0, 1.0), 40, Color(0.3, 0.75, 1.0), 6.0, true)
	var ft := "HEALTH"
	pad.draw_string(font, gc + Vector2(-font.get_string_size(ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x * 0.5, 5), ft, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))

## ENERGY SHIELD: a blue barrier in front of you; guard shots from the front stop on it; lights the room round you;
## drains energy (it drops when it runs out).
func toggle_shield() -> void:
	if not shield_on and energy < 15.0: return
	shield_on = not shield_on
	elog.append("shield:" + str(shield_on))

## SWORD: a lightsaber swing: cuts down guards in front of you and slices the blocks it passes through; a flash of light.
func swing() -> void:
	if busy or done or _swing > 0.0: return
	_swing = 0.35
	elog.append("swing")
	var fwd := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var at := pilot.global_position + Vector3(0, 1.2, 0)
	for g in guards:
		if not g["alive"]: continue
		var to: Vector3 = (g["node"] as Node3D).global_position + Vector3(0, 1.0, 0) - at
		if to.length() < 3.2 and fwd.dot(to.normalized()) > 0.3: _hurt_guard(g, 99)
	for k in 7:
		var a := (k / 6.0 - 0.5) * 1.6
		var dir := Basis(Vector3.UP, a) * fwd
		for dist in [1.2, 2.0, 2.8]:
			for dy in [-0.4, 0.3, 1.0]:
				var c := room.cell_of(at + dir * dist + Vector3(0, dy, 0))
				if room.hit_cell(c, 20): room.cut_cells += 1
	_sword_flash()

func _sword_flash() -> void:
	if _shield_light != null: _shield_light.light_energy = 6.0

func _update_gear(dt: float) -> void:
	# shield
	if shield_on:
		energy -= 14.0 * dt
		if energy <= 0.0:
			energy = 0.0
			shield_on = false
	else: energy = minf(100.0, energy + 9.0 * dt)
	if _shield_mesh == null:
		_shield_mesh = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.1
		sm.height = 2.2
		sm.is_hemisphere = false
		_shield_mesh.mesh = sm
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.3, 0.7, 1.0, 0.22)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shield_mesh.material_override = m
		_shield_mesh.scale = Vector3(1.0, 1.0, 0.25)
		body_mesh.add_child(_shield_mesh)
		_shield_mesh.position = Vector3(0, 1.1, -0.9)
		_shield_light = OmniLight3D.new()
		_shield_light.light_color = Color(0.45, 0.8, 1.0)
		_shield_light.omni_range = 9.0
		pilot.add_child(_shield_light)
		_shield_light.position = Vector3(0, 1.6, 0)
		_blade = MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.035
		cm.height = 1.3
		_blade.mesh = cm
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(0.6, 1.0, 1.0)
		_blade.material_override = bm
		body_mesh.add_child(_blade)
	_shield_mesh.visible = shield_on and not scoped
	var want := 0.8 + (2.8 if shield_on else 0.0)
	_shield_light.light_energy = move_toward(_shield_light.light_energy, want, dt * 12.0)
	_shield_light.light_color = Color(0.45, 0.8, 1.0) if shield_on or _swing > 0.0 else Color(1.0, 0.95, 0.85)
	# the blade sweeps across in front during a swing
	_swing = maxf(0.0, _swing - dt)
	_blade.visible = _swing > 0.0
	if _blade.visible:
		var k := 1.0 - _swing / 0.35
		var a := lerpf(1.1, -1.1, k)
		_blade.transform = Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 1.2, 0) + Basis(Vector3.UP, a) * Vector3(0, 0, -1.0))
	if pad != null: pad.queue_redraw()
	# the aim stick turns you
	if _aim != Vector2.ZERO:
		var rate := 0.9 if scoped else 2.6
		yaw -= _aim.x * rate * dt
		pitch = clampf(pitch - _aim.y * rate * 0.6 * dt, -1.2, 1.1)

func _look(r: Vector2) -> void:
	yaw -= r.x * (0.35 if scoped else 1.0)
	pitch = clampf(pitch - r.y * (0.35 if scoped else 1.0), -1.2, 1.1)

func toggle_scope() -> void:
	if tool != "rifle": return
	scoped = not scoped

func switch_tool() -> void:
	tool = "cutter" if tool == "rifle" else "rifle"
	scoped = false
	(_beam.mesh as ImmediateMesh).clear_surfaces()

func jump() -> void:
	if pilot.is_on_floor(): pilot.velocity.y = 6.5

# ---------------------------------------------------------------- HUD
func _make_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 30
	add_child(hud)
	cross = Control.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(func():
		var c := cross.size * 0.5
		var col := Color(0.6, 1.0, 1.0, 0.9) if tool == "cutter" else Color(1, 1, 1, 0.9)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			cross.draw_line(c + d * 5.0, c + d * 13.0, col, 2.0)
		cross.draw_circle(c, 1.5, col))
	hud.add_child(cross)
	scope_ov = Control.new()
	scope_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope_ov.visible = false
	scope_ov.draw.connect(func():
		var s := scope_ov.size
		var r := minf(s.x, s.y) * 0.44
		var c := s * 0.5
		for k in 48:   # dark outside a round sight
			scope_ov.draw_arc(c, r + 30.0 + k * 22.0, 0, TAU, 96, Color(0, 0, 0, 0.92), 24.0)
		scope_ov.draw_arc(c, r, 0, TAU, 96, Color(0, 0, 0, 1), 4.0)
		scope_ov.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0, 0, 0, 0.8), 1.0)
		scope_ov.draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0, 0, 0, 0.8), 1.0))
	hud.add_child(scope_ov)
	title_l = _label(Vector2(20, 14), 26, Color(1, 0.85, 0.5))
	goal_l = _label(Vector2(20, 50), 17, Color(0.9, 0.95, 1.0))
	info_l = _label(Vector2(20, 76), 15, Color(0.7, 0.9, 1.0))
	hp_bar = ProgressBar.new()
	hp_bar.max_value = HP_MAX
	hp_bar.show_percentage = false
	hp_bar.position = Vector2(20, 102)
	hp_bar.size = Vector2(220, 12)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.3, 0.9, 0.5)
	hp_bar.add_theme_stylebox_override("fill", fg)
	hud.add_child(hp_bar)
	# v12.35 (owner: "the same controls as mech mode ... both analog sticks that look the same ... a shield, an energy
	# shield, a lightsaber sword, you can use your rifle"): the mech's sticks and hex buttons, drawn by the pad
	pad = Control.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad)
	hud.add_child(pad)
	board_btn = Button.new()
	board_btn.text = "BOARD YOUR SHIP"
	board_btn.add_theme_font_size_override("font_size", 26)
	board_btn.anchor_left = 0.5
	board_btn.anchor_right = 0.5
	board_btn.anchor_top = 1.0
	board_btn.anchor_bottom = 1.0
	board_btn.offset_left = -170
	board_btn.offset_right = 170
	board_btn.offset_top = -120
	board_btn.offset_bottom = -50
	board_btn.visible = false
	board_btn.pressed.connect(board)
	hud.add_child(board_btn)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(fade)

func _label(at: Vector2, size: int, col: Color) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(l)
	return l

func _btn(parent: Control, t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(132, 62)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	parent.add_child(b)
	return b

func _process(_dt: float) -> void:
	if cross != null: cross.queue_redraw()
	if scope_ov != null and scope_ov.visible: scope_ov.queue_redraw()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
