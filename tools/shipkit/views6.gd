extends SceneTree
## views6.gd -- in.glb out_prefix [yaw] : like views3 plus straight +Z / -Z / -X views (fz, bz, lx) for structures. Saves <prefix>_top.png (game forward -Z at the top), _side.png (seen from +X,
## forward to the left) and _q.png (three-quarter view from behind-above). Work tool for looking at models.
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if a.size() < 2 or doc.append_from_file(a[0], st) != OK:
		push_error("usage: -- in.glb out_prefix [yaw]")
		quit(1)
		return
	var model: Node3D = doc.generate_scene(st)
	var holder := Node3D.new()
	holder.add_child(model)
	holder.rotation_degrees.y = float(a[2]) if a.size() > 2 else 0.0
	root.add_child(holder)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var c := box.get_center()
	var r := box.size.length()
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	cam.far = r * 8.0 + 10.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.06, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 1.3
	root.add_child(env)
	root.size = Vector2i(int(OS.get_environment("VPX")) if OS.get_environment("VPX") != "" else 640, int(OS.get_environment("VPX")) if OS.get_environment("VPX") != "" else 640)
	var shots := [
		["top", Vector3(0, 1, 0), Vector3(0, 0, -1), maxf(box.size.x, box.size.z)],
		["side", Vector3(1, 0, 0), Vector3(0, 1, 0), maxf(box.size.z, box.size.y)],
		["lx", Vector3(-1, 0, 0), Vector3(0, 1, 0), maxf(box.size.z, box.size.y)],
		["fz", Vector3(0, 0, 1), Vector3(0, 1, 0), maxf(box.size.x, box.size.y)],
		["bz", Vector3(0, 0, -1), Vector3(0, 1, 0), maxf(box.size.x, box.size.y)],
		["q", Vector3(0.55, 0.5, 0.75).normalized(), Vector3(0, 1, 0), r],
	]
	for s in shots:
		var dir: Vector3 = s[1]
		cam.size = float(s[3]) * 1.06
		cam.transform = Transform3D(Basis.looking_at(-dir, s[2]), c + dir * (r * 2.0 + 1.0))
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(a[1] + "_" + String(s[0]) + ".png")
	quit()
