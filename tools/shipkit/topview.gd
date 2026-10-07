extends SceneTree
## Look straight down on a model with the game's FORWARD (-Z) at the TOP of the picture.
## The nose must point UP. If it points down, the yaw for the game table is 180 more.
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if a.size() < 2 or doc.append_from_file(a[0], st) != OK:
		push_error("usage: -- in.glb out.png [yaw]")
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
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(box.size.x, box.size.z) * 1.15
	cam.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(0, 0, -1)), box.get_center() + Vector3(0, box.size.length() * 2.0 + 1.0, 0))
	root.add_child(cam)
	cam.far = box.size.length() * 6.0 + 10.0
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.04, 0.06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	root.size = Vector2i(512, 512)
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(a[1])
	print("TOPVIEW saved ", a[1], "  (game forward = top of the picture)")
	quit()
