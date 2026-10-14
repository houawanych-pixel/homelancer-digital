extends SceneTree
## mech_lineup.gd -- out.png "glb1,glb2,..." [mode: lineup | parts | mix]   (run with --path <repo>)
## lineup: every mech side by side, front view, all 3 m tall.  parts: each mech split into arms / core / legs,
## pulled apart and tinted.  mix: mechs built from other mechs' parts (core i, arms i+1, legs i+2).
const MP = preload("res://scripts/mech_parts.gd")

func _initialize() -> void:
	_run()

func _load(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK: return null
	return doc.generate_scene(st)

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var files: PackedStringArray = a[1].split(",")
	var mode: String = a[2] if a.size() > 2 else "lineup"
	var n := files.size()
	var TW := 320
	var TH := 520
	root.size = Vector2i(TW, TH)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.58)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-35, 20, 0)
	world.add_child(sun)
	var tint := {"arms": Color(1.0, 0.55, 0.2), "core": Color(0.35, 0.75, 1.0), "legs": Color(0.45, 1.0, 0.45)}
	for i in n:
		var m := _load(files[i])
		if m == null: continue
		var holder := Node3D.new()
		holder.position = Vector3(i * 50.0, 0, 0)
		world.add_child(holder)
		holder.add_child(m)
		if mode == "mix":
			var arms := _load(files[(i + 1) % n])
			var legs := _load(files[(i + 2) % n])
			print("LINEUP mix ", i, " ", MP.assemble(m, arms, legs))
		elif mode == "parts":
			var skel := MP.find_skeleton(m)
			for mi in MP.skinned_meshes(m):
				var parts: Dictionary = MP.split(mi, skel)
				for p in MP.PARTS:
					if parts[p] == null: continue
					var pn := MeshInstance3D.new()
					pn.mesh = parts[p]
					pn.skin = mi.skin
					skel.add_child(pn)
					pn.skeleton = pn.get_path_to(skel)
					var mat := StandardMaterial3D.new()
					mat.albedo_color = tint[p]
					pn.material_override = mat
				mi.visible = false
	await process_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.3
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	world.add_child(cam)
	cam.current = true
	var cols := 6
	var sheet := Image.create(TW * cols, TH * int(ceil(n / float(cols))), false, Image.FORMAT_RGBA8)
	for i in n:
		cam.position = Vector3(i * 50.0, 1.55, 10)
		for k in 3: await process_frame
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, TW, TH), Vector2i((i % cols) * TW, (i / cols) * TH))
	sheet.save_png(a[0])
	print("LINEUP wrote ", a[0])
	quit()
