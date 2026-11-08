extends Node3D
## v12.84: every Tripo mech frame built the way the game builds a mech (ShipFactory.build_mech: the pre-cut .scn on
## its skeleton), standing in rows mid-stride, far from the game world with its own camera. HL_MECHLINEUP autotest job.
var built := 0
var skeletons := 0

func _ready() -> void:
	position = Vector3(0, 70000, 0)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.12, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.64, 0.75)
	e.ambient_light_energy = 0.7
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var ids: Array = Data.MECH_ORDER.slice(12)
	for i in ids.size():
		var key := str(Data.MECHS[ids[i]]["model"])
		var m := ShipFactory.build_mech(key, key, key)
		add_child(m)
		var col := i % 9
		var row := i / 9
		m.position = Vector3((col - 4) * 12.0, 0, -row * 16.0)
		m.rotation_degrees.y = 160.0
		built += 1
		var v := Sections.setup(m, true)
		if v.get("mech", false):
			skeletons += 1
			Sections.stride(v, 22.0 if i % 2 == 0 else -22.0)
	var cam := Camera3D.new()
	cam.fov = 50
	add_child(cam)
	cam.position = Vector3(0, 22, 62)
	cam.look_at(global_position + Vector3(0, 2, -14))
	cam.current = true
