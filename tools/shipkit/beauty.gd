extends SceneTree
## beauty.gd -- in.glb out.png [WxH] [sky.jpg] : a website / poster shot of a model: three-quarter view in front of a
## space sky, game-like lights. (run with --rendering-driver opengl3 and --resolution WxH)
func _initialize() -> void:
	_run()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var wh: PackedStringArray = (a[2] if a.size() > 2 else "1600x900").split("x")
	root.size = Vector2i(int(wh[0]), int(wh[1]))
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		quit(1)
		return
	var model: Node3D = doc.generate_scene(st)
	var world := Node3D.new()
	root.add_child(world)
	world.add_child(model)
	var e := Environment.new()
	var sky_path: String = a[3] if a.size() > 3 else ""
	if sky_path != "":
		var img := Image.load_from_file(sky_path)
		var mat := PanoramaSkyMaterial.new()
		mat.panorama = ImageTexture.create_from_image(img)
		mat.energy_multiplier = 0.55
		var sky := Sky.new()
		sky.sky_material = mat
		e.sky = sky
		e.background_mode = Environment.BG_SKY
	elif OS.get_environment("BEAUTY_ALPHA") != "":   # a cut-out (transparent background) to lay over another picture
		root.transparent_bg = true
		RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))
		e.background_mode = Environment.BG_CLEAR_COLOR
		e.glow_enabled = false
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.03, 0.04, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.43, 0.55)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if OS.get_environment("BEAUTY_ALPHA") == "": e.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = e
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.rotation_degrees = Vector3(-38, -40, 0)
	world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.9
	rim.light_color = Color(0.5, 0.75, 1.0)
	rim.rotation_degrees = Vector3(-15, 150, 0)
	world.add_child(rim)
	var box := _aabb(model, Transform3D.IDENTITY)
	var c := box.get_center()
	var r := box.size.length() * 0.5
	var cam := Camera3D.new()
	cam.fov = 38.0
	world.add_child(cam)
	var dir := Vector3(-0.85, 0.42, 1.0).normalized()
	if OS.get_environment("BEAUTY_DIR") != "":   # e.g. "-0.9,0.4,-1" (ships fly nose -Z: look from the front)
		var f := OS.get_environment("BEAUTY_DIR").split(",")
		dir = Vector3(float(f[0]), float(f[1]), float(f[2])).normalized()
	var shift := float(OS.get_environment("BEAUTY_SHIFT")) if OS.get_environment("BEAUTY_SHIFT") != "" else 0.0   # moves the model right in the frame
	var k := float(OS.get_environment("BEAUTY_ZOOM")) if OS.get_environment("BEAUTY_ZOOM") != "" else 0.78
	cam.far = r * 50.0
	cam.near = r * 0.01
	cam.current = true
	await process_frame
	var eye := c + dir * r / sin(deg_to_rad(cam.fov * 0.5)) * k
	var side := dir.cross(Vector3.UP).normalized()
	cam.look_at_from_position(eye + side * r * shift, c + side * r * shift, Vector3.UP)
	print("BEAUTY box ", c, " r ", r, " cam ", cam.position)
	for i in 6: await process_frame
	root.get_texture().get_image().save_png(a[1])
	print("BEAUTY ", a[1])
	quit()

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is Node3D: xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out = xf * (n as MeshInstance3D).get_aabb()
		first = false
	for ch in n.get_children():
		var b := _aabb(ch, xf)
		if b.size == Vector3.ZERO: continue
		out = b if first else out.merge(b)
		first = false
	return out
