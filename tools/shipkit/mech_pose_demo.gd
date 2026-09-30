extends SceneTree
## Renders a mech in its flight poses and with a destroyed arm, for checking the section system by eye.
##   xvfb-run -a $GODOT --rendering-driver opengl3 --path . --script tools/shipkit/mech_pose_demo.gd -- mech_tan out.png
## Panels: neutral · cruise (arms back 35°, lean 22°) · boost/warp (arms back 70°, lean 35°) · left arm destroyed.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var key: String = args[0] if args.size() > 0 else "mech_tan"
	var out: String = args[1] if args.size() > 1 else "/tmp/mech_poses.png"
	var vp := SubViewport.new()
	vp.size = Vector2i(560, 640)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.04, 0.08)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.6
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	# the mech flies toward -Z; view it from front-left, a little above
	var holder := Node3D.new()
	vp.add_child(holder)
	var model := ShipFactory.build(key)
	holder.add_child(model)
	await process_frame
	cam.look_at_from_position(Vector3(-14, 4, -22), Vector3.ZERO)
	var v := Sections.setup(model, true)
	var panels := [["neutral", 0.0, 0.0, false], ["cruise", 35.0, 22.0, false], ["boost / warp", 70.0, 35.0, false], ["left arm destroyed", 35.0, 22.0, true]]
	var imgs: Array = []
	# top row: front-left three-quarter view; bottom row: from the mech's right side (nose/front to the left)
	for eye in [Vector3(-14, 4, -22), Vector3(26, 2, 0)]:
		cam.look_at_from_position(eye, Vector3.ZERO)
		for p in panels:
			model.rotation.x = -deg_to_rad(p[2])
			for i in 90: Sections.pose_mech(v, p[1], 0.1)
			Sections.set_side_visible(v, "l", not p[3])
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			imgs.append(vp.get_texture().get_image())
	var sheet := Image.create(560 * 4, 1280, false, imgs[0].get_format())
	for i in 8: sheet.blit_rect(imgs[i], Rect2i(0, 0, 560, 640), Vector2i(560 * (i % 4), 640 * (i / 4)))
	sheet.save_png(out)
	print("wrote ", out)
	quit()
