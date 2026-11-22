class_name ShipParts
extends RefCounted
## v13.266 (owner: "switch out the ship's cockpit, body, wings and tail, different styles, like the mech's arms, legs,
## core and head"): a ship model is cut once (cached per model) into four parts by where its triangles sit, in the
## model's own space (the nose to -Z): WINGS = everything out past the hull band at the sides; COCKPIT = the front of
## the hull band; TAIL = its back; BODY = the rest. A fitted ship is the body of one ship with the cockpit, wings and
## tail of others, each scaled to the body's own part and set where that part was. Nothing is cut while you fly: the
## parts are made once and the model is built from them like any ship. Stats stay the ship's (the look is yours).

const PARTS := ["cockpit", "body", "wings", "tail"]
const BAND := 0.3       # the hull band: this share of the half-width each side of the middle (Sections.WING_CUT)
const NOSE := 0.3       # the cockpit: the front this share of the length
const TAIL := 0.22      # the tail: the back this share

static var _cache := {}   # model key -> {part: [[ArrayMesh, Transform3D], ...], "box": {part: AABB}, "all": AABB}

static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var x := xf
	if n is Node3D: x = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible: out.append([n, x])
	for c in n.get_children(): _collect(c, x, out)

static func part_of(p: Vector3, box: AABB) -> String:
	var c := box.get_center()
	if absf(p.x - c.x) > box.size.x * 0.5 * BAND: return "wings"
	var t := (p.z - box.position.z) / maxf(box.size.z, 0.001)   # 0 at the nose, 1 at the back
	if t < NOSE: return "cockpit"
	if t > 1.0 - TAIL: return "tail"
	return "body"

## The four parts of one ship model (in the model's own space).
static func cut(key: String) -> Dictionary:
	if _cache.has(key): return _cache[key]
	var src := ShipFactory.build(key)
	var mis: Array = []
	for c in src.get_children(): _collect(c, Transform3D.IDENTITY, mis)
	var all := ShipFactory._aabb(src, Transform3D.IDENTITY)
	var out := {"box": {}, "all": all}
	for p in PARTS: out[p] = []
	for pair in mis:
		var mi: MeshInstance3D = pair[0]
		var xf: Transform3D = pair[1]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm = arr[Mesh.ARRAY_NORMAL]
			var uv = arr[Mesh.ARRAY_TEX_UV]
			var col = arr[Mesh.ARRAY_COLOR]
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx == null:
				idx = PackedInt32Array()
				for i in v.size(): idx.append(i)
			var mat: Material = mi.get_active_material(s)
			var st := {}
			for p in PARTS:
				var t := SurfaceTool.new()
				t.begin(Mesh.PRIMITIVE_TRIANGLES)
				st[p] = [t, 0]
			for i in range(0, idx.size() - 2, 3):
				var a: Vector3 = xf * v[idx[i]]
				var b: Vector3 = xf * v[idx[i + 1]]
				var c: Vector3 = xf * v[idx[i + 2]]
				var p := part_of((a + b + c) / 3.0, all)
				var t: SurfaceTool = st[p][0]
				for k in 3:
					var vi: int = idx[i + k]
					if nrm != null and (nrm as PackedVector3Array).size() > vi: t.set_normal((xf.basis * (nrm as PackedVector3Array)[vi]).normalized())
					if uv != null and (uv as PackedVector2Array).size() > vi: t.set_uv((uv as PackedVector2Array)[vi])
					if col != null and (col as PackedColorArray).size() > vi: t.set_color((col as PackedColorArray)[vi])
					t.add_vertex(xf * v[vi])
				st[p][1] = int(st[p][1]) + 1
			for p in PARTS:
				if int(st[p][1]) == 0: continue
				var m: ArrayMesh = (st[p][0] as SurfaceTool).commit()
				if mat != null: m.surface_set_material(0, mat)
				(out[p] as Array).append(m)
				var bb := m.get_aabb()
				out["box"][p] = bb if not (out["box"] as Dictionary).has(p) else (out["box"][p] as AABB).merge(bb)
	src.free()
	_cache[key] = out
	return out

## A ship wearing these parts: {"cockpit": model key, "body": ..., "wings": ..., "tail": ...} ("" = the body's own).
static func build(keys: Dictionary) -> Node3D:
	var body_key := str(keys.get("body", ""))
	var root := Node3D.new()
	root.name = "Model_parts_" + body_key
	root.set_meta("placeholder", false)
	var B := cut(body_key)
	for p in PARTS:
		var k := str(keys.get(p, ""))
		if k == "": k = body_key
		var S := cut(k) if k != body_key else B
		var xf := Transform3D.IDENTITY
		if k != body_key and (S["box"] as Dictionary).has(p) and (B["box"] as Dictionary).has(p):
			xf = fit(p, S["box"][p], B["box"][p])
		for m: ArrayMesh in S.get(p, []):
			var mi := MeshInstance3D.new()
			mi.name = "Part_" + p
			mi.mesh = m
			mi.transform = xf
			root.add_child(mi)
	return root

## Where another ship's part goes on this body: scaled to the body's own part and set at its joint (the cockpit's
## back on the body's front, the tail's front on its back, the wings centred on the body's own wings).
static func fit(p: String, src: AABB, slot: AABB) -> Transform3D:
	var k := 1.0
	match p:
		"cockpit", "tail": k = slot.size.z / maxf(src.size.z, 0.001)
		"wings": k = slot.size.x / maxf(src.size.x, 0.001)
	k = clampf(k, 0.4, 2.5)
	var sc := src.get_center() * k
	var tc := slot.get_center()
	var off := tc - sc
	match p:
		"cockpit": off.z = (slot.end.z) - (src.end.z * k)            # its back on the body's front
		"tail": off.z = slot.position.z - src.position.z * k         # its front on the body's back
	return Transform3D(Basis().scaled(Vector3.ONE * k), off)
