extends SceneTree
# tools/handoff/sheets.gd -- renders front / side / back / top orthographic views of each model,
# all from the same geometry at the same scale, and exports Godot .scn mechs to .glb.
# Reads user args: <list.json> <out_dir>.  list = [[key, res_path, yaw_deg], ...]
const PX := 768

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var out: String = a[1]
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = Vector2i(PX, PX)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 1.3; vp.add_child(sun)
	sun.look_at_from_position(Vector3(3, 6, 4), Vector3.ZERO)
	var sun2 := DirectionalLight3D.new(); sun2.light_energy = 0.5; vp.add_child(sun2)
	sun2.look_at_from_position(Vector3(-4, -2, -3), Vector3.ZERO)
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; vp.add_child(cam); cam.current = true
	var meta := {}
	for it in items:
		var key: String = it[0]; var path: String = it[1]; var yaw: float = float(it[2])
		var node: Node3D = null
		if path.ends_with(".scn") or path.ends_with(".tscn"):
			var ps = load(path)
			if ps == null: continue
			node = ps.instantiate()
			var doc := GLTFDocument.new(); var st := GLTFState.new()
			if doc.append_from_scene(node, st) == OK:
				doc.write_to_filesystem(st, out + "/" + key + ".glb")
		else:
			var doc := GLTFDocument.new(); var st := GLTFState.new()
			if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK: continue
			node = doc.generate_scene(st)
		if node == null: continue
		var holder := Node3D.new(); vp.add_child(holder); holder.add_child(node)
		holder.rotation_degrees.y = yaw
		await process_frame
		var bb := AABB(); var first := true
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			if first: bb = b; first = false
			else: bb = bb.merge(b)
		if first: holder.queue_free(); continue
		var c := bb.get_center(); var ext := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		cam.size = ext * 1.15
		var d := ext * 4.0
		cam.near = 0.01 * ext; cam.far = d * 3.0
		# nose = -Z after yaw (game convention).  front: looking at the nose; side: nose to the right;
		# back: looking at the tail; top: looking down, nose to the right (lines up with side).
		var views := {"front": [Vector3(0, 0, -1), Vector3.UP], "side": [Vector3(1, 0, 0), Vector3.UP],
			"back": [Vector3(0, 0, 1), Vector3.UP], "top": [Vector3(0, 1, 0), Vector3(-1, 0, 0)]}
		for v in views:
			var dir: Vector3 = views[v][0]
			cam.look_at_from_position(c + dir * d, c, views[v][1])
			await process_frame; await process_frame; await process_frame
			vp.get_texture().get_image().save_png(out + "/" + key + "_" + v + ".png")
		meta[key] = {"center": [c.x, c.y, c.z], "size": [bb.size.x, bb.size.y, bb.size.z], "ortho_size": cam.size, "px": PX, "yaw": yaw}
		holder.queue_free()
		await process_frame
	var f := FileAccess.open(out + "/views.json", FileAccess.WRITE); f.store_string(JSON.stringify(meta, "\t")); f.close()
	quit()
