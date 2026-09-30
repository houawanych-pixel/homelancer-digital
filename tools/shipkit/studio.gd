extends SceneTree
## In-engine "photo studio": renders a GLB with game-like lighting from several angles.
## xvfb-run -a godot --rendering-driver opengl3 --path <any project> --script studio.gd -- in.glb out_prefix [size]
## Writes <out_prefix>_sheet.png (4 angles side by side).

func _initialize() -> void:
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var size := 520 if a.size() < 3 else int(a[2])
	root.size = Vector2i(size, size)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		push_error("cannot read " + a[0]); quit(1); return
	var model: Node3D = doc.generate_scene(st)
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(model)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.44, 0.55)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-45, -35, 0)
	world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.rotation_degrees = Vector3(-10, 150, 0)
	world.add_child(rim)
	# frame the model
	var box := _aabb(model, Transform3D.IDENTITY)
	var c := box.get_center()
	var r := box.size.length() * 0.5
	var cam := Camera3D.new()
	cam.fov = 35.0
	world.add_child(cam)
	cam.current = true
	await process_frame
	var shots: Array[Image] = []
	# front-quarter, side, top, rear-quarter  (nose is -Z)
	var dirs := [Vector3(-0.9, 0.55, -1.0), Vector3(-1, 0.05, 0), Vector3(0, 1, 0.001), Vector3(0.9, 0.45, 1.0)]
	for d in dirs:
		var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * float(OS.get_environment("STUDIO_ZOOM") if OS.get_environment("STUDIO_ZOOM") != "" else "0.8")
		cam.look_at_from_position(c + (d as Vector3).normalized() * dist, c, Vector3.UP if absf((d as Vector3).normalized().y) < 0.99 else Vector3(0, 0, -1))
		for i in 4:
			await process_frame
		RenderingServer.force_draw()
		await process_frame
		shots.append(root.get_texture().get_image())
	var sheet := Image.create(size * shots.size(), size, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		var im := shots[i]
		im.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(im, Rect2i(0, 0, size, size), Vector2i(i * size, 0))
	sheet.save_png(a[1] + "_sheet.png")
	print("STUDIO wrote ", a[1] + "_sheet.png")
	quit(0)

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var b := t * (n as MeshInstance3D).mesh.get_aabb()
		out = b; first = false
	for ch in n.get_children():
		var cb := _aabb(ch, t)
		if cb.size != Vector3.ZERO:
			out = cb if first else out.merge(cb)
			first = false
	return out
