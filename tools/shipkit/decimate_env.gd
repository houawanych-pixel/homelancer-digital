extends SceneTree
## Polygon reduction with Godot's built-in meshoptimizer.
## godot --headless --script tools/shipkit/decimate.gd -- in.glb out.glb TARGET_TRIS
## Prints: DECIMATE <in_tris> -> <out_tris>

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		push_error("usage: -- in.glb out.glb target_tris")
		quit(1)
		return
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		push_error("cannot read " + a[0])
		quit(1)
		return
	var target := int(a[2])
	var total := 0
	for gm in st.get_meshes():
		var im: ImporterMesh = gm.mesh
		for s in im.get_surface_count():
			total += im.get_surface_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	var ratio := minf(1.0, float(target) / maxf(1.0, float(total)))
	var root := Node3D.new()
	root.name = "Ship"
	var out_tris := 0
	for gm in st.get_meshes():
		var im: ImporterMesh = gm.mesh
		if ratio < 1.0:
			im.generate_lods(float(OS.get_environment("DEC_MERGE")) if OS.get_environment("DEC_MERGE") != "" else 60.0, float(OS.get_environment("DEC_SPLIT")) if OS.get_environment("DEC_SPLIT") != "" else 25.0, [])
		var am := ArrayMesh.new()
		for s in im.get_surface_count():
			var arr: Array = im.get_surface_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var best := idx
			if ratio < 1.0:
				for l in im.get_surface_lod_count(s):
					best = im.get_surface_lod_indices(s, l)
					if best.size() <= int(idx.size() * ratio):
						break
			arr = _compact(arr, best)
			out_tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			am.surface_set_material(am.get_surface_count() - 1, im.get_surface_material(s))
		var mi := MeshInstance3D.new()
		mi.name = "Hull"
		mi.mesh = am
		root.add_child(mi)
		mi.owner = root
	var doc2 := GLTFDocument.new()
	var st2 := GLTFState.new()
	doc2.append_from_scene(root, st2)
	if doc2.write_to_filesystem(st2, a[1]) != OK:
		push_error("cannot write " + a[1])
		quit(1)
		return
	print("DECIMATE %d -> %d" % [total, out_tris])
	root.free()
	quit(0)

## Keep only the vertices the chosen index list uses.
func _compact(arr: Array, idx: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var ni := PackedInt32Array()
	ni.resize(idx.size())
	for k in idx.size():
		var v := idx[k]
		if not remap.has(v):
			remap[v] = order.size()
			order.append(v)
		ni[k] = remap[v]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for c in Mesh.ARRAY_MAX:
		var src = arr[c]
		if src == null or c == Mesh.ARRAY_INDEX:
			continue
		var n: int = src.size()
		var vcount: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if n == 0 or n % vcount != 0:
			continue
		var per := n / vcount
		var dst = src.duplicate()
		dst.resize(order.size() * per)
		for k in order.size():
			for j in per:
				dst[k * per + j] = src[order[k] * per + j]
		out[c] = dst
	out[Mesh.ARRAY_INDEX] = ni
	return out
