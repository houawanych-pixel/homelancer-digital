extends Node3D
## Every wildlife model (toon + ink) standing in a line, far away from the game world, with its own camera and light.
## Used by the HL_WILDLINEUP autotest job to check the placeholder looks.

func _ready() -> void:
	position = Vector3(0, 60000, 0)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.19, 0.29)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.75)
	e.ambient_light_energy = 0.8
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 200)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.24, 0.32, 0.27)
	fl.material_override = fm
	add_child(fl)
	var w: Node3D = load("res://scripts/wildlife.gd").new()
	add_child(w)
	var rows := [["hopper", -66, 10, 70], ["mossfleece", -59, 8, 60], ["drift_woolly", -51, 10, 60], ["grazer", -41, 6, 60],
		["strider", -28, 4, 70], ["prismhart", -15, 6, 70], ["vexmaw", 0, 4, 80], ["grumbark", 15, 4, 65], ["shale_stalker", 28, 6, 80],
		["rimeback", 44, 0, 30], ["sandmaw", 64, -6, 20]]
	for r in rows:
		var kind: String = r[0]
		var spec: Dictionary = Data.WILDLIFE[kind]
		var n := Node3D.new()
		add_child(n)
		var parts: Dictionary = w._build(str(spec.get("model", kind)), n, spec)
		n.scale = Vector3.ONE * float(spec["size"])
		n.position = Vector3(float(r[1]), 0, float(r[2]))
		n.rotation_degrees.y = float(r[3])
		if parts.get("jaw") != null and kind in ["vexmaw", "grumbark", "shale_stalker", "rimeback"]: (parts["jaw"] as Node3D).rotation.x = 0.5
		if kind == "rimeback":
			for arm in parts["arms"]: (arm as Node3D).rotation.x = -2.5
		if kind == "strider" and parts.get("tail") != null: (parts["tail"] as Node3D).rotation.x = -1.2
	var cam := Camera3D.new()
	cam.fov = 56
	add_child(cam)
	cam.position = Vector3(0, 8, 70)
	cam.look_at(global_position + Vector3(0, 6, 0))
	cam.current = true
