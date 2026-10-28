extends Node
## tools/handoff: render ships as the game builds them (ShipFactory), with their wing guns placed by the game's mount rule.
## env HL_TOOL=res://tools/handoff/ship_preview.gd  HL_PREVIEW="key1,key2"  HL_PREVIEW_OUT=/abs/dir
func _ready() -> void:
	var out := OS.get_environment("HL_PREVIEW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X; vp.own_world_3d = true
	add_child(vp)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.03, 0.04, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.5, 0.55, 0.65); env.ambient_light_energy = 0.6
	env.glow_enabled = true; env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; vp.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 1.4; vp.add_child(sun); sun.look_at_from_position(Vector3(6, 8, 4), Vector3.ZERO)
	var rim := DirectionalLight3D.new(); rim.light_energy = 0.6; rim.light_color = Color(0.6, 0.75, 1.0); vp.add_child(rim); rim.look_at_from_position(Vector3(-5, 2, -6), Vector3.ZERO)
	var cam := Camera3D.new(); cam.fov = 35.0; vp.add_child(cam); cam.current = true
	for key in OS.get_environment("HL_PREVIEW").split(","):
		var ship: Node3D = ShipFactory.build(key)
		vp.add_child(ship)
		await get_tree().process_frame
		var shots := {"three_quarter": Vector3(11, 6, -13), "rear": Vector3(-9, 5, 14), "side": Vector3(20, 1.5, 0)}
		for nm in shots:
			cam.look_at_from_position(shots[nm], Vector3.ZERO, Vector3.UP)
			for i in 6: await get_tree().process_frame
			vp.get_texture().get_image().save_png("%s/%s_%s.png" % [out, key, nm])
		ship.queue_free()
		await get_tree().process_frame
	get_tree().quit()
