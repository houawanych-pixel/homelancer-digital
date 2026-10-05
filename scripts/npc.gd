class_name NpcFigure
extends Node
## A person in a station room (v1.4m trial): one rigged 3D character drawn as a moving cut-out over the room picture.
## The character lives in its own small transparent viewport; rooms.gd / hub.gd draw that picture where the person
## stands. Close to you the frame is waist-up; when they walk back a little it widens to thigh-up and the figure gets
## smaller. They stroll left and right, stop, turn to you when you tap them, wave and talk.
## Model: assets/npc/<model>.glb (the "npc" pack), a humanoid rig with Idle and Walk animations.

static func path(model_id: String) -> String: return "res://assets/npc/%s.glb" % model_id

var info := {}            # {"name", "model", "u0", "u1", "lines": [...], "greet": "..."}
var vp: SubViewport
var rig: Node3D
var anim: AnimationPlayer
var skel: Skeleton3D
var cam: Camera3D
var u := 0.25             # where they stand along the room picture (same u as the room's markers)
var depth := 0.0          # 0 = close (waist-up) .. 1 = walked back (thigh-up)
var state := "idle"       # idle | walk | talk
var gesture := ""         # "" | "wave" | "nod"
var gesture_t := 0.0
var walks := true         # false = stands in one place (dealer screens)
var steps := 0            # how many strolls they have taken (tests)
var line_i := 0
var greeted := false
var _t := 0.0
var _goal_u := 0.25
var _goal_d := 0.0
var _yaw := 0.0
var _rng := RandomNumberGenerator.new()
var _height := 1.8

func setup(d: Dictionary) -> bool:
	info = d
	if not ResourceLoader.exists(path(d["model"])): return false
	vp = SubViewport.new()
	vp.size = Vector2i(Data.NPC_VIEW)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.9)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	rig = (load(path(d["model"])) as PackedScene).instantiate()
	vp.add_child(rig)
	var box := ShipFactory._aabb(rig, Transform3D.IDENTITY)
	if box.size.y > 0.01:
		var k := _height / box.size.y
		rig.scale = Vector3.ONE * k
		rig.position = Vector3(-box.get_center().x * k, -box.position.y * k, -box.get_center().z * k)
	for n in rig.find_children("*", "AnimationPlayer", true, false): anim = n
	for n in rig.find_children("*", "Skeleton3D", true, false): skel = n
	for n in rig.find_children("Weapon*", "", true, false): (n as Node3D).visible = false   # nobody carries a rifle in the lobby
	if anim != null:
		for a in ["Idle", "Walk"]:
			if anim.has_animation(a): anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		if anim.has_animation("Idle"): anim.play("Idle")
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 20.0
	vp.add_child(cam)
	cam.current = true
	_rng.seed = hash(str(d.get("name", "npc")))
	u = float(d.get("u0", 0.25))
	_goal_u = u
	walks = bool(d.get("walks", true))
	_frame()
	return true

## Frame the camera: waist-up when close, thigh-up when they have walked back.
func _frame() -> void:
	var low := lerpf(Data.NPC_FRAME_NEAR, Data.NPC_FRAME_FAR, depth) * _height
	var top := _height * 1.08
	cam.size = top - low
	cam.position = Vector3(0, (top + low) * 0.5, 5.0)
	cam.rotation = Vector3.ZERO

func update(dt: float) -> void:
	if rig == null: return
	_t -= dt
	var want_yaw := 0.0
	match state:
		"idle":
			if _t <= 0.0 and walks:
				_goal_u = _rng.randf_range(float(info.get("u0", 0.2)), float(info.get("u1", 0.3)))
				_goal_d = _rng.randf() if _rng.randf() < 0.6 else 0.0
				state = "walk"
				steps += 1
				if anim != null and anim.has_animation("Walk"): anim.play("Walk", 0.25)
		"walk":
			var du := _goal_u - u
			var step := Data.NPC_WALK * dt
			want_yaw = (PI * 0.5 if du > 0.0 else -PI * 0.5) * 0.85
			u += clampf(du, -step, step)
			depth = move_toward(depth, _goal_d, dt * 0.25)
			if absf(du) <= step and absf(depth - _goal_d) < 0.02:
				state = "idle"
				_t = _rng.randf_range(Data.NPC_PAUSE[0], Data.NPC_PAUSE[1])
				if anim != null and anim.has_animation("Idle"): anim.play("Idle", 0.3)
		"talk":
			if _t <= 0.0:
				state = "idle"
				_t = 1.5
	_yaw = lerp_angle(_yaw, want_yaw, minf(1.0, dt * 5.0))
	rig.rotation.y = _yaw
	_frame()
	if gesture != "":
		gesture_t -= dt
		_pose_gesture()
		if gesture_t <= 0.0:
			gesture = ""
			if skel != null: skel.reset_bone_poses()
			if anim != null and anim.has_animation("Idle"): anim.play("Idle", 0.2)

## Turn to the player, make a gesture and give the next line.
func talk() -> String:
	state = "talk"
	_t = Data.NPC_TALK_TIME
	if anim != null and anim.has_animation("Idle"): anim.play("Idle", 0.2)
	var lines: Array = info.get("lines", ["..."])
	var line: String = lines[line_i % lines.size()]
	line_i += 1
	do_gesture("wave" if line_i % 2 == 1 else "nod")
	return line

func do_gesture(kind: String) -> void:
	gesture = kind
	gesture_t = Data.NPC_GESTURE_TIME
	if anim != null: anim.pause()

## Gestures are posed straight on the bones, in the skeleton's own space, so they work on any humanoid rig:
## wave = the right arm comes up and the forearm swings; nod = the head dips twice.
func _pose_gesture() -> void:
	if skel == null: return
	var k := clampf(minf(Data.NPC_GESTURE_TIME - gesture_t, gesture_t) / 0.3, 0.0, 1.0)   # ease in and out
	if gesture == "wave":
		var side := -1.0 if _bone_x("RightUpperArm") < 0.0 else 1.0
		_turn("RightUpperArm", Vector3.BACK, side * deg_to_rad(125.0) * k)
		_turn("RightLowerArm", Vector3.BACK, side * deg_to_rad(125.0 + 28.0 * sin(gesture_t * 9.0)) * k)
	elif gesture == "nod":
		_turn("Head", Vector3.RIGHT, deg_to_rad(16.0) * k * (0.5 + 0.5 * sin(gesture_t * 8.0)))

func _bone_x(bone: String) -> float:
	var i := skel.find_bone(bone)
	return skel.get_bone_global_rest(i).origin.x if i >= 0 else 0.0

## Rotate a bone by `angle` about `axis` (skeleton space) from its rest direction.
func _turn(bone: String, axis: Vector3, angle: float) -> void:
	var i := skel.find_bone(bone)
	if i < 0: return
	var rest := skel.get_bone_global_rest(i).basis
	var parent := skel.get_bone_parent(i)
	var pb := skel.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var want := Basis(axis, angle) * rest
	skel.set_bone_pose_rotation(i, (pb.inverse() * want).orthonormalized().get_rotation_quaternion())

func texture() -> Texture2D:
	return vp.get_texture() if vp != null else null

## Where the figure is drawn on a screen of size S when its feet line is at x: anchored to the bottom edge.
func rect_at(x: float, S: Vector2) -> Rect2:
	var h := S.y * lerpf(Data.NPC_HEIGHT_NEAR, Data.NPC_HEIGHT_FAR, depth)
	var w := h * float(Data.NPC_VIEW.x) / float(Data.NPC_VIEW.y)
	return Rect2(x - w * 0.5, S.y - h, w, h)
