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
	var suit := Color(0.85, 0.55, 0.2)
	var dark := Color(0.18, 0.2, 0.24)
	_part(body_mesh, Vector3(0.0, 1.22, 0.0), Vector3(0.46, 0.55, 0.28), suit)          # chest
	_part(body_mesh, Vector3(0.0, 0.88, 0.0), Vector3(0.38, 0.22, 0.24), dark)          # belt
	_part(body_mesh, Vector3(0.0, 1.27, 0.17), Vector3(0.36, 0.42, 0.12), dark)         # pack
	_part(body_mesh, Vector3(0.0, 1.7, 0.0), Vector3(0.28, 0.3, 0.3), suit.lightened(0.15), true)   # helmet
	_part(body_mesh, Vector3(0.0, 1.71, -0.13), Vector3(0.22, 0.12, 0.06), Color(0.2, 0.75, 1.0))   # visor
	for s in [-1.0, 1.0]:
		_part(body_mesh, Vector3(0.12 * s, 0.45, 0.0), Vector3(0.16, 0.86, 0.18), suit.darkened(0.2))   # legs
		_part(body_mesh, Vector3(0.3 * s, 1.2, -0.12), Vector3(0.13, 0.5, 0.14), suit.darkened(0.1))     # arms
	_part(body_mesh, Vector3(0.22, 1.2, -0.42), Vector3(0.08, 0.1, 0.75), dark)          # rifle

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
	var spd := RUN if Input.is_physical_key_pressed(KEY_SHIFT) else WALK
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
		elog.append("died")
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
	var col := Color(0.35, 0.38, 0.42)
	_part(n, Vector3(0, 1.2, 0), Vector3(0.5, 0.6, 0.3), col)
	_part(n, Vector3(0, 1.72, 0), Vector3(0.3, 0.32, 0.32), Color(0.85, 0.2, 0.15), true)
	_part(n, Vector3(0, 0.45, 0), Vector3(0.42, 0.9, 0.22), col.darkened(0.3))
	_part(n, Vector3(0.2, 1.25, -0.38), Vector3(0.08, 0.1, 0.65), Color(0.1, 0.1, 0.12))
	room.add_child(n)
	n.position = at
	guards.append({"node": n, "hp": 6, "cool": randf_range(1.0, 2.5), "alive": true, "vy": 0.0})

func _hurt_guard(g: Dictionary, dmg: int) -> void:
	if not g["alive"]: return
	g["hp"] = int(g["hp"]) - dmg
	if int(g["hp"]) <= 0:
		g["alive"] = false
		elog.append("guard_down")
		var n: Node3D = g["node"]
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
		g["cool"] = float(g["cool"]) - dt
		if sees and float(g["cool"]) <= 0.0:
			g["cool"] = randf_range(1.1, 1.8)
			var miss := randf() < clampf(flat.length() / 30.0, 0.25, 0.7)
			var at := target + (Vector3(randf_range(-1.5, 1.5), randf_range(-0.6, 1.0), randf_range(-1.5, 1.5)) if miss else Vector3.ZERO)
			_tracer(eye, at, Color(1.0, 0.35, 0.2))
			if not miss: hurt(7.0)

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
			KEY_SPACE: jump()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		var w := get_viewport().get_visible_rect().size.x
		if t.pressed:
			if t.position.x < w * 0.4 and _stick_id < 0:
				_stick_id = t.index
				_stick_o = t.position
			elif _look_id < 0:
				_look_id = t.index
		else:
			if t.index == _stick_id:
				_stick_id = -1
				_move = Vector2.ZERO
			if t.index == _look_id: _look_id = -1
	elif e is InputEventScreenDrag:
		var d := e as InputEventScreenDrag
		if d.index == _stick_id: _move = ((d.position - _stick_o) / 70.0).limit_length(1.0)
		elif d.index == _look_id: _look(d.relative * (0.002 if scoped else 0.005))

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
	# touch buttons, right side
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	col.position = Vector2(-150, -380)
	col.add_theme_constant_override("separation", 8)
	hud.add_child(col)
	col.anchor_left = 1.0
	col.anchor_top = 1.0
	col.anchor_right = 1.0
	col.anchor_bottom = 1.0
	col.offset_left = -150
	col.offset_top = -390
	col.offset_right = -18
	col.offset_bottom = -18
	var fire_b := _btn(col, "FIRE")
	fire_b.button_down.connect(func(): _fire_held = true)
	fire_b.button_up.connect(func(): _fire_held = false)
	_btn(col, "SCOPE").pressed.connect(toggle_scope)
	_btn(col, "TOOL").pressed.connect(switch_tool)
	_btn(col, "CHARGE").pressed.connect(throw_charge)
	_btn(col, "JUMP").pressed.connect(jump)
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
