class_name MechParts
extends RefCounted
## v1.9i (owner: "mechs have arms, the core, which is the upper body, and the legs, which is the lower part"):
## every rigged mech shares the same 22-bone humanoid skeleton, so one mech can wear another's arms or legs.
## Each skinned mesh is CUT once per mech type (cached) into three meshes, with clean straight cuts (owner: "the whole
## arm cut off from the body as a vertical cut; the bottom torso cut off by the waist like a belt, horizontally"):
##   arms = everything outside a VERTICAL plane at each shoulder (between the Shoulder and UpperArm joints), above the
##          waist, plus the hands / forearms that hang below it. Both sides: always a matched pair.
##   legs = everything under a HORIZONTAL plane at the waist (between the Hips and Spine joints), but the hands.
##   core = the rest: the upper body with its head and anything locked to it.
## Triangles crossing a cut are sliced on the plane, so the edge is straight. A built mech keeps its own skeleton (the
## core's); the borrowed parts are skinned to it by bone NAME, so they sit on its shoulders and hips and follow its poses.

const PARTS := ["arms", "core", "legs"]
const ARM_CUT := 0.4     # the shoulder plane sits this far from the Shoulder joint towards the UpperArm joint
const WAIST_CUT := 0.5   # the belt sits this far from the Hips joint towards the Spine joint

static var _split_cache := {}   # mesh instance id -> {"arms": ArrayMesh or null, "core": ..., "legs": ...}

static func part_of_bone(n: String) -> String:
	if n.contains("Shoulder") or n.contains("Arm") or n.contains("Hand"): return "arms"
	if n == "Hips" or n.contains("Leg") or n.contains("Foot") or n.contains("Toes"): return "legs"
	return "core"

static func find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var s := find_skeleton(c)
		if s: return s
	return null

static func skinned_meshes(n: Node, out: Array = []) -> Array:
	if n is MeshInstance3D and (n as MeshInstance3D).skin != null and (n as MeshInstance3D).mesh != null: out.append(n)
	for c in n.get_children(): skinned_meshes(c, out)
	return out

# A joint's position in the mesh's own space (the inverse of its bind pose).
static func _joint(skin: Skin, names: Array, nm: String, fallback: Vector3) -> Vector3:
	var b := names.find(nm)
	return skin.get_bind_pose(b).affine_inverse().origin if b >= 0 else fallback

## Cut one skinned mesh into its three part meshes (cached by the mesh resource).
static func split(mi: MeshInstance3D, skel: Skeleton3D) -> Dictionary:
	var key := mi.mesh.get_instance_id()
	if _split_cache.has(key): return _split_cache[key]
	var skin := mi.skin
	var names: Array = []
	var bind_arm := PackedByteArray()
	for b in skin.get_bind_count():
		var nm := str(skin.get_bind_name(b))
		if nm == "" and skel != null and skin.get_bind_bone(b) >= 0: nm = skel.get_bone_name(skin.get_bind_bone(b))
		names.append(nm)
		bind_arm.append(1 if part_of_bone(nm) == "arms" else 0)
	# the cut planes, from the joints
	var hips := _joint(skin, names, "Hips", Vector3.ZERO)
	var spine := _joint(skin, names, "Spine", hips + Vector3.UP)
	var waist: float = lerpf(hips.y, spine.y, WAIST_CUT)
	var cut_l: float = lerpf(_joint(skin, names, "LeftShoulder", hips).x, _joint(skin, names, "LeftUpperArm", hips + Vector3.RIGHT).x, ARM_CUT)
	var cut_r: float = lerpf(_joint(skin, names, "RightShoulder", hips).x, _joint(skin, names, "RightUpperArm", hips + Vector3.LEFT).x, ARM_CUT)
	var lo_x := minf(cut_l, cut_r)
	var hi_x := maxf(cut_l, cut_r)
	var out := {"arms": ArrayMesh.new(), "core": ArrayMesh.new(), "legs": ArrayMesh.new()}
	var used := {"arms": false, "core": false, "legs": false}
	var src: Mesh = mi.mesh
	for s in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nv := verts.size()
		if nv == 0 or bones.size() == 0: continue
		var nb := bones.size() / nv
		# is each corner moved mostly by an arm bone? (hands hanging below the belt stay arms)
		var varm := PackedByteArray()
		varm.resize(nv)
		for v in nv:
			var best := 0
			var bw := -1.0
			for j in nb:
				var w := wts[v * nb + j]
				if w > bw:
					bw = w
					best = bones[v * nb + j]
			varm[v] = bind_arm[best] if best < bind_arm.size() else 0
		if idx.size() == 0:
			idx.resize(nv)
			for v in nv: idx[v] = v
		var ed := _Edit.new(arr, nb)
		var lists := [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
		for t in idx.size() / 3:
			var tri := [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
			var parts := []
			var below := 0
			for v in tri:
				var pv: Vector3 = verts[v]
				if pv.y < waist: below += 1
				parts.append(_region(pv, varm[v], waist, lo_x, hi_x))
			if parts[0] == parts[1] and parts[1] == parts[2]:
				lists[parts[0]].append_array(tri)
				continue
			# a triangle across a cut: slice it on the plane between its corners' parts
			var set := {}
			for q in parts: set[q] = true
			var plane := Plane()
			if set.has(2) and below > 0 and below < 3: plane = Plane(Vector3.UP, waist)          # the belt
			elif set.has(0) and set.has(1) and below == 0:                                           # a shoulder
				var tx: float = (verts[tri[0]].x + verts[tri[1]].x + verts[tri[2]].x) / 3.0
				plane = Plane(Vector3.RIGHT, cut_l if absf(tx - cut_l) < absf(tx - cut_r) else cut_r)
			else:   # (an arm / leg corner pair: no plane between them; the majority takes it)
				var maj: int = parts[0] if (parts[0] == parts[1] or parts[0] == parts[2]) else parts[1]
				lists[maj].append_array(tri)
				continue
			var tarm: int = 1 if varm[tri[0]] + varm[tri[1]] + varm[tri[2]] >= 2 else 0
			for piece in ed.clip(tri, plane):
				var c := (ed.pos(piece[0]) + ed.pos(piece[1]) + ed.pos(piece[2])) / 3.0
				lists[_region(c, tarm, waist, lo_x, hi_x)].append_array(piece)
		var a_all: Array = ed.arrays()
		var flags: int = (src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) if src is ArrayMesh else 0
		var mat := mi.get_surface_override_material(s)
		if mat == null: mat = src.surface_get_material(s)
		for k in 3:
			if lists[k].is_empty(): continue
			var a2 := a_all.duplicate()
			a2[Mesh.ARRAY_INDEX] = lists[k]
			var m: ArrayMesh = out[PARTS[k]]
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2, [], {}, flags)
			m.surface_set_material(m.get_surface_count() - 1, mat)
			used[PARTS[k]] = true
	for p in PARTS:
		if not used[p]: out[p] = null
	_split_cache[key] = out
	return out

# 0 arms, 1 core, 2 legs
static func _region(p: Vector3, arm_bone: int, waist: float, lo_x: float, hi_x: float) -> int:
	if p.y >= waist: return 0 if (p.x > hi_x or p.x < lo_x) else 1
	return 0 if arm_bone == 1 else 2

## Vertex arrays that can grow: a triangle sliced on a plane gets new corners with blended attributes.
class _Edit:
	var a: Array
	var nb: int
	var v: PackedVector3Array
	var n: PackedVector3Array
	var tg: PackedFloat32Array
	var uv: PackedVector2Array
	var uv2: PackedVector2Array
	var col: PackedColorArray
	var bo: PackedInt32Array
	var we: PackedFloat32Array
	func _init(arr: Array, bones_per: int) -> void:
		a = arr
		nb = bones_per
		v = arr[Mesh.ARRAY_VERTEX]
		n = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		tg = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		uv = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		uv2 = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		col = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		bo = arr[Mesh.ARRAY_BONES]
		we = arr[Mesh.ARRAY_WEIGHTS]
	func pos(i: int) -> Vector3: return v[i]
	# a new corner between i and j at t (skin weights from the nearer one)
	func mid(i: int, j: int, t: float) -> int:
		var k := v.size()
		v.append(v[i].lerp(v[j], t))
		if n.size() > 0: n.append(n[i].lerp(n[j], t).normalized())
		if tg.size() > 0:
			for c in 4: tg.append(lerpf(tg[i * 4 + c], tg[j * 4 + c], t))
		if uv.size() > 0: uv.append(uv[i].lerp(uv[j], t))
		if uv2.size() > 0: uv2.append(uv2[i].lerp(uv2[j], t))
		if col.size() > 0: col.append(col[i].lerp(col[j], t))
		var src := i if t < 0.5 else j
		for c in nb:
			bo.append(bo[src * nb + c])
			we.append(we[src * nb + c])
		return k
	# slice a triangle on a plane: the pieces on both sides, as corner triples
	func clip(tri: Array, pl: Plane) -> Array:
		var pieces: Array = []
		for side in [1.0, -1.0]:
			var poly: Array = []
			for e in 3:
				var i: int = tri[e]
				var j: int = tri[(e + 1) % 3]
				var di: float = pl.distance_to(v[i]) * side
				var dj: float = pl.distance_to(v[j]) * side
				if di >= 0.0: poly.append(i)
				if (di >= 0.0) != (dj >= 0.0):
					var t := di / (di - dj)
					poly.append(mid(i, j, clampf(t, 0.0, 1.0)))
			for f in range(1, poly.size() - 1): pieces.append([poly[0], poly[f], poly[f + 1]])
		return pieces
	func arrays() -> Array:
		var out := a.duplicate()
		out[Mesh.ARRAY_VERTEX] = v
		if n.size() > 0: out[Mesh.ARRAY_NORMAL] = n
		if tg.size() > 0: out[Mesh.ARRAY_TANGENT] = tg
		if uv.size() > 0: out[Mesh.ARRAY_TEX_UV] = uv
		if uv2.size() > 0: out[Mesh.ARRAY_TEX_UV2] = uv2
		if col.size() > 0: out[Mesh.ARRAY_COLOR] = col
		out[Mesh.ARRAY_BONES] = bo
		out[Mesh.ARRAY_WEIGHTS] = we
		return out

## Turn a built mech model (ShipFactory.build of the core's key) into a mech wearing `arms_src`' arms and
## `legs_src`' legs (each an unfitted instance of that mech's scene, or null to keep its own). The mech scenes come
## PRE-CUT (tools/shipkit/mech_bake.gd: Part_arms / Part_core / Part_legs), so this only swaps nodes: no mesh work
## while you play. An uncut model falls back to cutting here (once per mech type, cached).
static func assemble(model: Node3D, arms_src: Node3D, legs_src: Node3D) -> Dictionary:
	var skel := find_skeleton(model)
	var info := {"arms": 0, "core": 0, "legs": 0}
	if skel == null: return info
	var give := {"arms": arms_src, "legs": legs_src}
	for p in ["arms", "legs"]:
		var src: Node3D = give[p]
		if src == null: continue
		var src_skel := find_skeleton(src)
		var mine: Array = part_nodes(model, p)
		if mine.is_empty() and part_nodes(model, "core").is_empty():   # (an uncut model: cut its meshes now)
			for mi in skinned_meshes(model): _set_part(mi, skel, p, false)
		for n: Node in mine:
			n.get_parent().remove_child(n)
			n.free()
		var theirs: Array = part_nodes(src, p)
		if theirs.is_empty():
			for omi in skinned_meshes(src):
				var cut := split(omi, src_skel)
				if cut[p] != null: theirs.append([cut[p], omi.skin])
		else:
			theirs = theirs.map(func(m): return [m.mesh, m.skin])
		for pair in theirs:
			var n := MeshInstance3D.new()
			n.name = "Part_" + p
			n.mesh = pair[0]
			n.skin = _named_skin(pair[1], src_skel)
			skel.add_child(n)
			n.skeleton = n.get_path_to(skel)
			info[p] += 1
	info["core"] = maxi(1, part_nodes(model, "core").size())
	model.set_meta("mech_parts", info)
	return info

## The pre-cut part nodes of one part in a mech model.
static func part_nodes(n: Node, part: String, out: Array = []) -> Array:
	if n is MeshInstance3D and str(n.name).begins_with("Part_" + part): out.append(n)
	for c in n.get_children(): part_nodes(c, part, out)
	return out

# Hide one part of the core's own meshes by swapping in the mesh without it.
static func _set_part(mi: MeshInstance3D, skel: Skeleton3D, part: String, keep: bool) -> void:
	if keep: return
	if not mi.has_meta("orig_parts"): mi.set_meta("orig_parts", split(mi, skel))   # (split the ORIGINAL mesh once)
	var parts: Dictionary = mi.get_meta("orig_parts")
	var drop: Array = mi.get_meta("dropped", [])
	if part in drop: return
	drop.append(part)
	mi.set_meta("dropped", drop)
	var keep_parts: Array = PARTS.filter(func(x): return not (x in drop))
	var m := ArrayMesh.new()
	for p in keep_parts:
		var pm: ArrayMesh = parts[p]
		if pm == null: continue
		for s in pm.get_surface_count():
			var flags: int = pm.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pm.surface_get_arrays(s), [], {}, flags)
			m.surface_set_material(m.get_surface_count() - 1, pm.surface_get_material(s))
	mi.mesh = m
	for s in m.get_surface_count(): mi.set_surface_override_material(s, null)

# A copy of a skin whose binds all carry bone names (so they find the same bones on another mech's skeleton).
static var _named := {}   # skin id -> its copy with bone names
static func _named_skin(skin: Skin, skel: Skeleton3D) -> Skin:
	if _named.has(skin.get_instance_id()): return _named[skin.get_instance_id()]
	var s2 := Skin.new()
	_named[skin.get_instance_id()] = s2
	for b in skin.get_bind_count():
		var nm := str(skin.get_bind_name(b))
		if nm == "" and skel != null and skin.get_bind_bone(b) >= 0: nm = skel.get_bone_name(skin.get_bind_bone(b))
		s2.add_named_bind(nm, skin.get_bind_pose(b))
	return s2
