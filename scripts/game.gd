extends Node3D

var ship: Node3D
var camera: Camera3D
var world: Node3D
var beacon: Node3D
var station: Node3D
var enemy: Node3D
var hud: Label
var system := 0
var credits := 0
var hull := 100
var weapon := 1
var enemy_hull := 5
var docked := false
var charge := 0.0
var cooldown := 0.0
var message := "Fly to the blue beacon and hold T to warp."

func _ready() -> void:
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "fire": KEY_SPACE, "dock": KEY_F, "launch": KEY_R, "upgrade": KEY_U, "warp": KEY_T, "boost": KEY_SHIFT}
	for action in keys:
		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.01, 0.02, 0.05)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.7)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -40, 0)
	add_child(sun)
	ship = shape("Player", false, 2.0, Color.CYAN)
	add_child(ship)
	camera = Camera3D.new()
	camera.current = true
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(20, 20)
	hud.add_theme_font_size_override("font_size", 20)
	canvas.add_child(hud)
	load_system(0)

func shape(title: String, sphere: bool, size: float, tint: Color) -> Node3D:
	var node := Node3D.new()
	node.name = title
	var visible_mesh := MeshInstance3D.new()
	if sphere:
		visible_mesh.mesh = SphereMesh.new()
	else:
		visible_mesh.mesh = BoxMesh.new()
	visible_mesh.scale = Vector3.ONE * size
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	visible_mesh.material_override = material
	node.add_child(visible_mesh)
	return node

func load_system(next: int) -> void:
	if is_instance_valid(world):
		world.queue_free()
	world = Node3D.new()
	add_child(world)
	system = next
	ship.position = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	charge = 0.0
	docked = false
	var palette := [Color.RED, Color.GREEN] if next == 0 else [Color.BLUE, Color.YELLOW]
	for i in 2:
		var planet := shape("Planet %d" % i, true, 6.0 if i == 0 else 4.0, palette[i])
		planet.position = Vector3(-65.0 + i * 130.0, 8.0, -110.0 - i * 40.0)
		world.add_child(planet)
	for i in 14:
		var rock := shape("Asteroid %d" % i, true, 0.8 + float(i % 4) * 0.35, Color(0.45, 0.4, 0.36))
		rock.position = Vector3(sin(float(i) * 11.3) * 43.0, cos(float(i) * 5.2) * 12.0, -15.0 - i * 7.0)
		world.add_child(rock)
	beacon = shape("Warp beacon", true, 3.0, Color(0.1, 0.7, 1.0))
	beacon.position = Vector3(0, 0, -95)
	world.add_child(beacon)
	station = null
	enemy = null
	if next == 0:
		station = shape("Hub station", false, 9.0, Color(0.75, 0.75, 0.8))
		station.position = Vector3(-25, 0, -35)
		world.add_child(station)
		enemy = shape("Enemy drone", false, 2.0, Color(1.0, 0.25, 0.12))
		enemy.position = Vector3(17, 0, -50)
		world.add_child(enemy)
		enemy_hull = 5
	message = "System A: dock at the hub with F; fight the drone."
	else:
		message = "System B: return through the blue beacon."

func _process(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)
	if not docked:
		ship.rotate_y((Input.get_action_strength("left") - Input.get_action_strength("right")) * delta * 1.7)
		var thrust := Input.get_action_strength("forward") - Input.get_action_strength("back") * 0.5
		var speed := 70.0 if Input.is_action_pressed("boost") else 32.0
		ship.position -= ship.global_basis.z * thrust * speed * delta
		if Input.is_action_pressed("fire") and cooldown <= 0:
			shoot()
		if is_instance_valid(station) and ship.position.distance_to(station.position) < 16 and Input.is_action_just_pressed("dock"):
			docked = true
			hull = 100
			message = "Docked; hull repaired. U upgrades weapon for 10 credits. R launches."
		if ship.position.distance_to(beacon.position) < 19 and Input.is_action_pressed("warp"):
			charge += delta
			if charge > 1.5:
				load_system(1 - system)
		else:
			charge = 0.0
	else:
		if Input.is_action_just_pressed("upgrade"):
			if credits >= 10:
				credits -= 10
				weapon += 1
				message = "Weapon upgraded to level %d." % weapon
			else:
				message = "Need 10 credits. Destroy the drone first."
		if Input.is_action_just_pressed("launch"):
			docked = false
			message = "Launched."
	var behind := ship.position + ship.global_basis.z * 14 + Vector3(0, 6, 0)
	camera.position = camera.position.lerp(behind, minf(1, delta * 5))
	camera.look_at(ship.position - ship.global_basis.z * 15, Vector3.UP)
	hud.text = "SYSTEM %s  |  Hull %d  Credits %d  Weapon %d\nBeacon %.0f units | Hold T nearby to warp (%.0f%%)\nW/S move  A/D turn  Shift boost  Space fire  F dock  U upgrade  R launch\n%s" % ["A" if system == 0 else "B", hull, credits, weapon, ship.position.distance_to(beacon.position), charge / 1.5 * 100, message]

func shoot() -> void:
	cooldown = 0.25
	if not is_instance_valid(enemy):
		return
	var direction := enemy.position - ship.position
	if direction.length() < 75 and (-ship.global_basis.z).dot(direction.normalized()) > 0.94:
		enemy_hull -= weapon
		message = "Drone hit. Remaining hull: %d" % maxi(0, enemy_hull)
		if enemy_hull <= 0:
			enemy.queue_free()
			credits += 10
			message = "Drone destroyed: +10 credits. Dock for an upgrade."
