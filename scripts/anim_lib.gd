class_name AnimLib
extends RefCounted
## v13.157 (owner: "we need real animation, real rigging ... a library of rigging so we can plug it all in"):
## the shared animation library, the same one Chronicle Clash uses. Real animator-made clips (Quaternius
## Universal Animation Library 1 & 2, CC0; walk/run/idle from Mixamo) baked into assets/anim/clips.json as
## rig-independent pose tracks: per frame, each limb's direction in the character's own frame (+X forward,
## +Y up, +Z right), torso/head turns and the hip rise. Because they are directions, not bone rotations, one
## clip plays on any humanoid skeleton: the Tripo 78-bone rigs (L_Thigh ...), the newer Tripo/"_Rigged" crews
## (LeftUpperLeg ...), Mixamo (LeftUpLeg ...) and UE-style (thigh_l ...).
## Bake more clips with tools/anim/bake.gd in the chronicle-clash-mg3d repo (docs/ANIMATION.md there).

const PATH := "res://assets/anim/clips.json"
static var _clips: Dictionary = {}
static var _loaded := false

static func clips() -> Dictionary:
	if not _loaded:
		_loaded = true
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		if d is Dictionary: _clips = d
	return _clips

static func has(name: String) -> bool: return clips().has(name)
static func length(name: String) -> float: return float(clips()[name]["length"]) if has(name) else 1.0
static func move_rate(name: String) -> float: return float(clips()[name].get("move", 0.0)) if has(name) else 0.0

## The pose at time t (loops wrap; one-shots hold their last frame).
static func sample(name: String, t: float) -> Dictionary:
	if not has(name): return {}
	var c: Dictionary = clips()[name]
	var frames: Array = c["frames"]
	var n := frames.size()
	var L := float(c["length"])
	var u: float
	if bool(c["loop"]): u = fposmod(t, L) / L * n
	else: u = clampf(t / L, 0.0, 0.9999) * (n - 1)
	var i0 := int(floorf(u)) % n
	var i1 := (i0 + 1) % n if bool(c["loop"]) else mini(i0 + 1, n - 1)
	var k := u - floorf(u)
	var a: Dictionary = frames[i0]
	var b: Dictionary = frames[i1]
	var p := {}
	for key in a["d"]:
		var va: Array = a["d"][key]
		var vb: Array = b["d"][key]
		p[key] = Vector3(va[0], va[1], va[2]).slerp(Vector3(vb[0], vb[1], vb[2]), k).normalized()
	for key in a["t"]:
		var qa: Array = a["t"][key]
		var qb: Array = b["t"][key]
		p[key] = Quaternion(qa[0], qa[1], qa[2], qa[3]).normalized().slerp(Quaternion(qb[0], qb[1], qb[2], qb[3]).normalized(), k)
	p["lift"] = lerpf(float(a["lift"]), float(b["lift"]), k)
	return p

## Blend two poses (k = 0 -> a, 1 -> b).
static func mix(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	if a.is_empty(): return b
	if b.is_empty(): return a
	var out := a.duplicate()
	for key in b:
		if not a.has(key): out[key] = b[key]
		elif a[key] is Vector3: out[key] = (a[key] as Vector3).slerp(b[key], k).normalized()
		elif a[key] is Quaternion: out[key] = (a[key] as Quaternion).slerp(b[key], k)
		elif a[key] is float: out[key] = lerpf(a[key], b[key], k)
	return out

## Walk / run / idle blended by ground speed (m/s), the phase advancing with distance so the feet don't slide.
## `state` is a Dictionary the caller keeps per character ({} to start).
static func locomotion(state: Dictionary, dt: float, speed: float, hip_h: float, walk := "mx_walk", run := "mx_run", idle := "mx_idle") -> Dictionary:
	var w := clampf((speed - 1.6) / 2.4, 0.0, 1.0)
	var ws := move_rate(walk) * hip_h * length(walk)
	var rs := move_rate(run) * hip_h * length(run)
	var stride := lerpf(ws, rs, w)
	var ph := fposmod(float(state.get("ph", 0.0)) + dt * minf(speed / maxf(stride, 0.1), 2.3), 1.0)
	state["ph"] = ph
	state["t"] = float(state.get("t", 0.0)) + dt
	var moving := mix(sample(walk, ph * length(walk)), sample(run, ph * length(run)), w)
	return mix(sample(idle, float(state["t"])), moving, clampf(speed / 1.0, 0.0, 1.0))

## Bone names on the different humanoid rigs, ours first.
const ALIASES := {
	"Hip": ["Hip", "Hips", "hips", "pelvis", "Pelvis"],
	"Waist": ["Waist", "Spine", "spine", "spine_01"],
	"Spine01": ["Spine01", "Spine1", "Chest", "chest", "spine_02"],
	"Spine02": ["Spine02", "Spine2", "UpperChest", "upper_chest", "spine_03"],
	"Head": ["Head", "head"],
	"L_Upperarm": ["L_Upperarm", "LeftUpperArm", "LeftArm", "upperarm_l"],
	"L_Forearm": ["L_Forearm", "LeftLowerArm", "LeftForeArm", "lowerarm_l"],
	"L_Hand": ["L_Hand", "LeftHand", "hand_l"],
	"R_Upperarm": ["R_Upperarm", "RightUpperArm", "RightArm", "upperarm_r"],
	"R_Forearm": ["R_Forearm", "RightLowerArm", "RightForeArm", "lowerarm_r"],
	"R_Hand": ["R_Hand", "RightHand", "hand_r"],
	"L_Thigh": ["L_Thigh", "LeftUpperLeg", "LeftUpLeg", "thigh_l"],
	"L_Calf": ["L_Calf", "LeftLowerLeg", "LeftLeg", "calf_l"],
	"L_Foot": ["L_Foot", "LeftFoot", "foot_l"],
	"R_Thigh": ["R_Thigh", "RightUpperLeg", "RightUpLeg", "thigh_r"],
	"R_Calf": ["R_Calf", "RightLowerLeg", "RightLeg", "calf_r"],
	"R_Foot": ["R_Foot", "RightFoot", "foot_r"],
}
const AIM := {"L_Upperarm": "L_Forearm", "L_Forearm": "L_Hand", "R_Upperarm": "R_Forearm", "R_Forearm": "R_Hand",
	"L_Thigh": "L_Calf", "L_Calf": "L_Foot", "R_Thigh": "R_Calf", "R_Calf": "R_Foot"}
const TURN := ["Hip", "Waist", "Spine01", "Spine02", "Head"]
const ORDER := ["Hip", "Waist", "Spine01", "Spine02", "Head", "L_Upperarm", "L_Forearm", "R_Upperarm", "R_Forearm",
	"L_Thigh", "L_Calf", "R_Thigh", "R_Calf"]

## Plays clip poses on one skeleton. new() then setup(skel); apply(pose, dt) each frame.
class Driver:
	var sk: Skeleton3D
	var idx := {}
	var M := Basis()          # character axes (forward, up, right) -> skeleton space
	var Mi := Basis()
	var rest_q := {}
	var parent_q := {}
	var rest_dir := {}
	var cur := {}
	var turn := {}
	var hip_h := 1.0          # hip height in skeleton units (for "lift")
	var foot_rest := 0.0

	static func _strip(n: String) -> String:
		var i := n.rfind(":")
		return n.substr(i + 1) if i >= 0 else n

	func setup(skel: Skeleton3D) -> bool:
		sk = skel
		if sk == null: return false
		var names := {}
		for i in sk.get_bone_count(): names[_strip(sk.get_bone_name(i))] = i
		for ours in ALIASES:
			for alt in ALIASES[ours]:
				if names.has(alt):
					idx[ours] = names[alt]
					break
		for need in ["Hip", "L_Thigh", "R_Thigh", "L_Calf", "R_Calf", "L_Upperarm", "R_Upperarm"]:
			if not idx.has(need): return false
		# the character's own frame from the rest pose: left = left hip - right hip, up = +Y
		var l: Vector3 = sk.get_bone_global_rest(idx["L_Thigh"]).origin
		var r: Vector3 = sk.get_bone_global_rest(idx["R_Thigh"]).origin
		var left := Vector3(l.x - r.x, 0, l.z - r.z).normalized()
		var up := Vector3.UP
		var fwd := left.cross(up).normalized()
		M = Basis(fwd, up, -left)
		Mi = M.inverse()
		for i in sk.get_bone_count():
			rest_q[i] = sk.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
			var p := sk.get_bone_parent(i)
			parent_q[i] = sk.get_bone_global_rest(p).basis.orthonormalized().get_rotation_quaternion() if p >= 0 else Quaternion()
		for a in AIM:
			if idx.has(a) and idx.has(AIM[a]):
				var d: Vector3 = sk.get_bone_global_rest(idx[AIM[a]]).origin - sk.get_bone_global_rest(idx[a]).origin
				rest_dir[a] = d.normalized()
				cur[a] = Mi * d.normalized()
		for t in TURN: turn[t] = Quaternion()
		hip_h = maxf(0.05, sk.get_bone_global_rest(idx["Hip"]).origin.y - minf(_rest_y("L_Foot"), _rest_y("R_Foot")))
		foot_rest = minf(_rest_y("L_Foot"), _rest_y("R_Foot"))
		return true

	func _rest_y(n: String) -> float:
		return sk.get_bone_global_rest(idx[n]).origin.y if idx.has(n) else 0.0

	func _acc(acc: Dictionary, i: int) -> Quaternion:
		var j := i
		while j >= 0 and not acc.has(j): j = sk.get_bone_parent(j)
		return acc.get(j, Quaternion())

	## Pose the skeleton (smoothed toward the target at `rate` per second).
	func apply(pose: Dictionary, dt: float, rate := 14.0) -> void:
		if sk == null or not is_instance_valid(sk) or pose.is_empty(): return
		var k := 1.0 - exp(-rate * dt) if dt > 0.0 else 1.0
		for a in AIM:
			if pose.has(a) and cur.has(a): cur[a] = (cur[a] as Vector3).slerp(pose[a], k).normalized()
		var Mq := M.get_rotation_quaternion()
		for t in TURN:
			var q: Quaternion = pose.get(t, Quaternion())
			turn[t] = (turn[t] as Quaternion).slerp(q, k)
		var acc := {}
		for name in ORDER:
			if not idx.has(name): continue
			var i: int = idx[name]
			var accp := _acc(acc, sk.get_bone_parent(i))
			var r: Quaternion
			if rest_dir.has(name):
				var want: Vector3 = accp.inverse() * (M * (cur[name] as Vector3))
				r = Quaternion(rest_dir[name], want.normalized())
			else:
				r = Mq * (turn[name] as Quaternion) * Mq.inverse()   # turns are in character axes
			acc[i] = accp * r
			var pq: Quaternion = parent_q[i]
			sk.set_bone_pose_rotation(i, (pq.inverse() * r * pq * (rest_q[i] as Quaternion)).normalized())

	## How far (skeleton units) to raise the body so the lowest foot is back at its standing height.
	func plant_offset() -> float:
		var low := INF
		for n in ["L_Foot", "R_Foot"]:
			if idx.has(n): low = minf(low, sk.get_bone_global_pose(idx[n]).origin.y)
		return 0.0 if low == INF else foot_rest - low
