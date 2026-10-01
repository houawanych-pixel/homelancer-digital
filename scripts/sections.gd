class_name Sections
extends RefCounted
## Three-part units: LEFT · CORE · RIGHT.
## Ships: each mesh is split ONCE per model type (cached) into three index sets by which side of the hull a triangle
## sits on, so a destroyed wing is simply hidden (visible = false). Nothing is cut or rebuilt at runtime.
## Mechs: the skinned model is untouched; a destroyed arm is hidden by scaling its UpperArm bone to zero
## (the whole arm and anything in its hand collapse into the shoulder). Arms also swing back with thrust.

const WING_CUT := 0.3 # fraction of the half-width: outside this band a triangle belongs to a wing

static var _split_cache := {} # mesh instance id -> [core, left, right] ArrayMesh

## Prepare a unit's visuals. Returns the handle used by hide/show/point/pose.
static func setup(model: Node3D, is_mech: bool) -> Dictionary:
	if is_mech:
		var sk := _find_skeleton(model)
		if sk:
			var v := {"mech": true, "skel": sk}
			for n in ["LeftUpperArm", "RightUpperArm", "LeftShoulder", "RightShoulder", "UpperChest", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "Spine"]:
				v[n] = sk.find_bone(n)
			if v["LeftUpperArm"] >= 0 and v["RightUpperArm"] >= 0:
				v["arm_l"] = 0.0
				v["arm_r"] = 0.0
				return v
	return _split_ship(model)

static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s: return s
	return null

# ---------------------------------------------------------------- ships
static func _split_ship(root: Node3D) -> Dictionary:
	var mis: Array = []
	_collect(root, Transform3D.IDENTITY, mis)
	var box := ShipFactory._aabb(root, Transform3D.IDENTITY)
	var cx := box.get_center().x
	var cut := box.size.x * 0.5 * WING_CUT
	var v := {"mech": false, "l": [], "r": [], "lp": Vector3(cx - box.size.x * 0.36, box.get_center().y, box.get_center().z),
		"rp": Vector3(cx + box.size.x * 0.36, box.get_center().y, box.get_center().z), "half": box.size.x * 0.5}
	for pair in mis:
		var mi: MeshInstance3D = pair[0]
		var xf: Transform3D = pair[1]
		if mi.skin != null: continue
		var key := "%d|%.3f|%.3f" % [mi.mesh.get_instance_id(), cx, cut]
		var parts: Array = _split_cache.get(key, [])
		if parts.is_empty():
			parts = _split_mesh(mi.mesh, xf, cx, cut)
			_split_cache[key] = parts
		if parts[1] == null and parts[2] == null: continue
		mi.mesh = parts[0]
		for k in [1, 2]:
			if parts[k] == null: continue
			var w := MeshInstance3D.new()
			w.mesh = parts[k]
			w.transform = mi.transform
			w.material_override = mi.material_override
			w.cast_shadow = mi.cast_shadow
			w.name = "Wing" + ("L" if k == 1 else "R")
			mi.get_parent().add_child(w)
			(v["l"] if k == 1 else v["r"]).append(w)
	return v

static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is Node3D: xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh: out.append([n, xf])
	for c in n.get_children(): _collect(c, xf, out)

## One-time split of a mesh into [core, left, right] by triangle centre (in model space). Vertex arrays are shared
## per section mesh; only the index lists differ.
static func _split_mesh(mesh: ArrayMesh, xf: Transform3D, cx: float, cut: float) -> Array:
	var out := [ArrayMesh.new(), ArrayMesh.new(), ArrayMesh.new()]
	var used := [false, false, false]
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size(): idx[i] = i
		var sets := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
		for t in range(0, idx.size() - 2, 3):
			var c: Vector3 = xf * ((verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0)
			var k := 0
			if c.x < cx - cut: k = 1
			elif c.x > cx + cut: k = 2
			sets[k].append(idx[t])
			sets[k].append(idx[t + 1])
			sets[k].append(idx[t + 2])
		for k in 3:
			if sets[k].is_empty(): continue
			var a2 := arr.duplicate()
			a2[Mesh.ARRAY_INDEX] = sets[k]
			(out[k] as ArrayMesh).add_surface_from_arrays(mesh.surface_get_primitive_type(s), a2)
			(out[k] as ArrayMesh).surface_set_material((out[k] as ArrayMesh).get_surface_count() - 1, mesh.surface_get_material(s))
			used[k] = true
	for k in 3:
		if not used[k]: out[k] = null
	if out[0] == null: out[0] = ArrayMesh.new()
	return out

# ---------------------------------------------------------------- shared
## Hide (destroyed) or show (repaired) one side: "l" or "r".
static func set_side_visible(v: Dictionary, side: String, on: bool) -> void:
	if v.is_empty(): return
	if v["mech"]:
		var sk: Skeleton3D = v["skel"]
		var b: int = v["LeftUpperArm" if side == "l" else "RightUpperArm"]
		if is_instance_valid(sk) and b >= 0: sk.set_bone_pose_scale(b, Vector3.ONE if on else Vector3.ONE * 0.0001)
		v["gone_" + side] = not on
		return
	for w in v[side]:
		if is_instance_valid(w): (w as Node3D).visible = on

## World position of a side (arm/shoulder or wing middle), for explosions and sparks.
static func side_point(v: Dictionary, side: String, model: Node3D) -> Vector3:
	if v.is_empty(): return model.global_position
	if v["mech"]:
		var sk: Skeleton3D = v["skel"]
		var b: int = v["LeftShoulder" if side == "l" else "RightShoulder"]
		if b < 0: b = v["LeftUpperArm" if side == "l" else "RightUpperArm"]
		return sk.global_transform * sk.get_bone_global_pose(b).origin
	return model.global_transform * (v["lp"] if side == "l" else v["rp"])

## Which section a hit lands on, from the hit point: "l", "r" or "core".
static func side_of_hit(v: Dictionary, unit: Node3D, hit: Vector3, radius: float) -> String:
	var lx := unit.to_local(hit).x
	var band := radius * 0.22
	if lx < -band: return "l"
	if lx > band: return "r"
	return "core"

## Mech flight posture: arms swing back with speed/boost/warp (degrees), returning smoothly to neutral.
## tuck 0..1 folds the mech into a compact block (arms forward over the chest, knees up) for the transformation.
static func pose_mech(v: Dictionary, back_deg: float, dt: float, tuck := 0.0) -> void:
	if v.is_empty() or not v["mech"]: return
	var sk: Skeleton3D = v["skel"]
	if not is_instance_valid(sk): return
	for side in ["l", "r"]:
		var cur: float = v["arm_" + side]
		cur = lerpf(cur, back_deg, minf(1.0, dt * 2.2))   # heavy: eases in and out
		v["arm_" + side] = cur
		var pre := "Left" if side == "l" else "Right"
		_bend(sk, v[pre + "UpperArm"], cur - tuck * 95.0)                 # tuck: arms fold forward over the chest
		_bend(sk, v.get(pre + "UpperLeg", -1), -tuck * 85.0)             # knees up
		_bend(sk, v.get(pre + "LowerLeg", -1), tuck * 110.0)             # shins fold back
	_bend(sk, v.get("Spine", -1), -tuck * 25.0)                          # hunch

## Rotate a bone about the skeleton's sideways axis (positive = toward the back), relative to its rest pose.
static func _bend(sk: Skeleton3D, b: int, deg: float) -> void:
	if b < 0: return
	var rest := sk.get_bone_rest(b)
	var grest := sk.get_bone_global_rest(b)
	var axis := (grest.basis.inverse() * Vector3.RIGHT).normalized()
	sk.set_bone_pose_rotation(b, rest.basis.get_rotation_quaternion() * Quaternion(axis, deg_to_rad(deg)))
