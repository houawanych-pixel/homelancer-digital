extends SceneTree
## flowshot.gd -- KEY out_prefix : renders a ship from ShipFactory (flow shader included) at two moments, 3/4 view.
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var vp := SubViewport.new()
	vp.size = Vector2i(420, 420)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var m: Node3D = ShipFactory.build(a[0])
	vp.add_child(m)
	var cam := Camera3D.new()
	var L: float = float(ShipFactory.GLB[a[0]][1])
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(L * 0.75, L * 0.5, L * 0.6), Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.04, 0.07)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 0.6
	vp.add_child(env)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(a[1] + "_a.png")
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(a[1] + "_b.png")
	quit()
