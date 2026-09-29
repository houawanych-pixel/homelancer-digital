class_name SpaceSystem
extends Node3D
## One star system in flight: environment, player flight, combat, AI, docking and gate proximity.

signal enemy_killed(reward: int, name: String)
signal player_destroyed
signal message(text: String)

const DOCK_RANGE_STATION := 260.0
const DOCK_RANGE_PLANET := 300.0 # measured from the planet surface
const GATE_RANGE := 320.0

var sys: Dictionary
var sys_id := ""
var player: Node3D
var model: Node3D
var cam: Camera3D
var env: WorldEnvironment
var controls := true

# player flight state
var yaw := 0.0
var pitch := 0.0
var vel := Vector3.ZERO
var move := Vector2.ZERO # x strafe, y forward(+)/back(-)
var aim := Vector2.ZERO # stick deflection -1..1
var fire_held := false
var shield_cd := 0.0
var energy_cd := 0.0
var repair_cd := 0.0
var missile_cd := 0.0
var mine_cd := 0.0
var lock_time := 0.0
var mines_live: Array = []
signal system_used(id: String, text: String)
var cruise := false
var cruise_charge := 0.0
var gun_cd := 0.0
var shield_delay := 0.0
var hit_shake := 0.0
var autopilot: Node3D = null # fly toward this node when set
var speed_now := 0.0

# world objects
var station: Node3D
var planet: Node3D
var gate: Node3D
var gate_portal: MeshInstance3D
var nebula_center := Vector3.ZERO
var nebula_radius := 0.0
var nebula_color := Color.WHITE
var belt_center := Vector3.ZERO
var belt_radius := 0.0
var rocks: Array = [] # [Vector3 pos, float radius]
var enemies: Array = [] # Dictionaries
var traffic: Array = []
var bolts: Array = []
var missiles_live: Array = []
var effects: Array = []
var target: Node3D = null
var respawn_timer := 0.0
var in_nebula := 0.0 # 0..1 how deep inside
var in_belt := false
var time := 0.0
var _enemy_serial := 0

var _bolt_mesh: BoxMesh
var _rng := RandomNumberGenerator.new()

# ---------------------------------------------------------------- build
func setup(id: String, arrival: String) -> void:
	sys_id = id
	sys = Data.SYSTEMS[id]
	_rng.seed = hash(id)
	_bolt_mesh = BoxMesh.new()
	_bolt_mesh.size = Vector3(0.25, 0.25, 5.0)
	_build_environment()
	_build_station(sys["station"])
	_build_planet(sys["planet"])
	_build_gate(sys["gate"])
	_build_belt(sys["asteroids"])
	_build_nebula(sys["nebula"])
	_build_player()
	for p in sys["patrols"]: _spawn_group(p, 2)
	_build_traffic()
	place_player(arrival)

func place_player(arrival: String) -> void:
	var at: Vector3
	var face: Vector3
	if arrival == "gate":
		at = gate.global_position + gate.global_basis.z * 90.0
		face = gate.global_basis.z
	elif arrival == "planet":
		at = dock_point(planet) + (dock_point(planet) - planet.global_position).normalized() * 40.0
		face = (station.global_position - at).normalized()
	else:
		at = dock_point(station) + Vector3(0, 0, 30)
		face = Vector3(0, 0, 1)
	player.global_position = at
	_face(face)
	vel = -player.global_basis.z * 10.0
	_update_camera(1.0, true)

func _face(dir: Vector3) -> void:
	dir = dir.normalized()
	yaw = atan2(-dir.x, -dir.z)
	pitch = asin(clampf(dir.y, -1.0, 1.0))
	player.basis = Basis.from_euler(Vector3(pitch, yaw, 0))

func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = _star_panorama(sys["sky_tint"], sys["nebula"]["color"])
	sky.sky_material = pano
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = sys["ambient"]
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = sys["star"]
	sun.light_energy = 1.25
	var d: Vector3 = (sys["sun_dir"] as Vector3).normalized()
	sun.look_at_from_position(Vector3.ZERO, d, Vector3.UP)
	add_child(sun)
	# visible star disc + glow, far away opposite the light direction
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1400, 1400)
	glow.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _radial_texture(sys["star"], 0.18)
	m.no_depth_test = false
	glow.material_override = m
	glow.name = "Sun"
	glow.position = -d * 9000.0
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)
	cam = Camera3D.new()
	cam.far = 14000.0
	cam.near = 0.5
	cam.fov = 70.0
	cam.current = true
	add_child(cam)

func _star_panorama(tint: Color, band: Color) -> ImageTexture:
	var w := 1024
	var h := 512
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(tint * 0.35, 1.0))
	# faint galactic band of soft blobs
	var blob := Image.create(48, 24, false, Image.FORMAT_RGBA8)
	var bc: Color = (tint * 1.4).lerp(band, 0.45)
	for by in 24:
		for bx in 48:
			var dd := Vector2((bx - 23.5) / 24.0, (by - 11.5) / 12.0).length()
			blob.set_pixel(bx, by, Color(bc.r, bc.g, bc.b, clampf(1.0 - dd, 0.0, 1.0) * 0.07))
	for i in 260:
		var x := _rng.randi_range(-24, w - 24)
		var y := int(h * 0.5 + sin(float(x) / w * TAU) * h * 0.12 + _rng.randfn(0.0, h * 0.05)) - 12
		img.blend_rect(blob, Rect2i(0, 0, 48, 24), Vector2i(x, y))
	for i in 2600:
		var x := _rng.randi_range(0, w - 1)
		var y := _rng.randi_range(0, h - 1)
		var b := pow(_rng.randf(), 3.0)
		var c := Color(0.75 + b * 0.25, 0.8 + b * 0.2, 1.0).lerp(Color(1.0, 0.85, 0.7), _rng.randf() * 0.5) * (0.35 + b * 0.9)
		img.set_pixel(x, y, c)
		if b > 0.75 and x + 1 < w: img.set_pixel(x + 1, y, c * 0.6)
	return ImageTexture.create_from_image(img)

func _radial_texture(col: Color, core: float) -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0 + 0.5, y - s / 2.0 + 0.5).length() / (s / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, 2.2) + (1.0 if d < core else 0.0) * 0.8
			img.set_pixel(x, y, Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _cloud_texture(col: Color, seed_v: int) -> ImageTexture:
	var s := 96
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 0.045
	n.fractal_octaves = 3
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var v := (n.get_noise_2d(x, y) + 1.0) * 0.5
			var a := clampf((1.0 - d) * 1.4, 0.0, 1.0) * clampf(v * 1.6 - 0.35, 0.0, 1.0)
			img.set_pixel(x, y, Color(col.r * (0.7 + v * 0.5), col.g * (0.7 + v * 0.5), col.b * (0.8 + v * 0.3), a))
	return ImageTexture.create_from_image(img)

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color, scl := Vector3.ONE, rot := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot
	mi.material_override = ShipFactory.mat(col, emissive, 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _build_station(d: Dictionary) -> void:
	station = Node3D.new()
	station.name = d["name"]
	station.position = d["pos"]
	station.set_meta("kind", "station")
	station.set_meta("info", d)
	station.set_meta("radius", 70.0)
	add_child(station)
	var c: Color = d["color"]
	var cyl := CylinderMesh.new()
	cyl.radial_segments = 16
	cyl.rings = 1
	var box := BoxMesh.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 52.0
	torus.outer_radius = 60.0
	torus.rings = 40
	torus.ring_segments = 8
	var body := Node3D.new()
	station.add_child(body)
	_mesh(body, cyl, Vector3.ZERO, c, Vector3(14, 70, 14))
	_mesh(body, cyl, Vector3(0, 40, 0), c.darkened(0.3), Vector3(22, 10, 22))
	_mesh(body, cyl, Vector3(0, -40, 0), c.darkened(0.3), Vector3(22, 10, 22))
	_mesh(body, torus, Vector3.ZERO, c.darkened(0.15))
	for i in 4:
		var a := i * PI / 2.0
		_mesh(body, box, Vector3(cos(a) * 30, 0, sin(a) * 30), c.darkened(0.25), Vector3(48, 4, 4), Vector3(0, -rad_to_deg(a), 0))
	# solar wings
	for s in [-1.0, 1.0]:
		_mesh(body, box, Vector3(0, s * 62, 0), Color(0.12, 0.2, 0.42), Vector3(90, 1.5, 22))
	# docking bay facing +Z with guide lights
	_mesh(body, box, Vector3(0, 0, 44), c.darkened(0.4), Vector3(26, 16, 30))
	_mesh(body, box, Vector3(0, 0, 59.2), Color(0.02, 0.03, 0.05), Vector3(18, 10, 0.5))
	for i in 5:
		for s in [-1.0, 1.0]:
			var l := _mesh(body, BoxMesh.new(), Vector3(s * 12, -6, 64 + i * 14), Color(0.3, 1.0, 0.6), Vector3(1.2, 1.2, 1.2), Vector3.ZERO, true)
			l.set_meta("blink", i * 0.12)
	for i in 8:
		var a2 := i * TAU / 8.0
		_mesh(body, BoxMesh.new(), Vector3(cos(a2) * 60, 0, sin(a2) * 60), Color(1.0, 0.85, 0.5), Vector3(2, 2, 2), Vector3.ZERO, true)
	station.set_meta("body", body)

func _planet_texture(palette: String) -> ImageTexture:
	var w := 384
	var h := 192
	var n := FastNoiseLite.new()
	n.seed = hash(palette)
	n.frequency = 0.012
	n.fractal_octaves = 4
	var clouds := FastNoiseLite.new()
	clouds.seed = hash(palette) + 7
	clouds.frequency = 0.03
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var deep := Color(0.05, 0.16, 0.42)
	var shallow := Color(0.12, 0.42, 0.7)
	var land := Color(0.25, 0.48, 0.2)
	var high := Color(0.52, 0.45, 0.32)
	if palette == "jungle":
		deep = Color(0.03, 0.2, 0.3)
		shallow = Color(0.08, 0.45, 0.5)
		land = Color(0.12, 0.5, 0.18)
		high = Color(0.3, 0.6, 0.25)
	for y in h:
		var lat := (float(y) / h - 0.5) * PI
		for x in w:
			var lon := float(x) / w * TAU
			var p := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon)) * 180.0
			var v := n.get_noise_3dv(p)
			var c: Color
			if v < -0.05: c = deep.lerp(shallow, clampf((v + 0.5) / 0.45, 0.0, 1.0))
			else: c = land.lerp(high, clampf(v * 2.2, 0.0, 1.0))
			if absf(lat) > 1.25: c = c.lerp(Color(0.92, 0.95, 1.0), 0.8)
			var cl := clouds.get_noise_3dv(p)
			if cl > 0.15: c = c.lerp(Color(1, 1, 1), clampf((cl - 0.15) * 2.2, 0.0, 0.75))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _build_planet(d: Dictionary) -> void:
	planet = Node3D.new()
	planet.name = d["name"]
	planet.position = d["pos"]
	planet.set_meta("kind", "planet")
	planet.set_meta("info", d)
	var r: float = d["radius"]
	planet.set_meta("radius", r)
	add_child(planet)
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = _planet_texture(d["palette"])
	m.roughness = 0.9
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(mi)
	planet.set_meta("surface", mi)
	# atmosphere rim
	var atm := MeshInstance3D.new()
	var am := SphereMesh.new()
	am.radius = r * 1.06
	am.height = r * 2.12
	am.radial_segments = 48
	am.rings = 24
	atm.mesh = am
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, cull_back, depth_draw_never;\nuniform vec4 tint : source_color;\nvoid fragment(){ float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0); ALBEDO = tint.rgb * f * 1.6; ALPHA = f; }"
	var sm2 := ShaderMaterial.new()
	sm2.shader = sh
	sm2.set_shader_parameter("tint", Color(0.45, 0.7, 1.0) if d["palette"] == "terran" else Color(0.45, 1.0, 0.7))
	atm.material_override = sm2
	atm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	planet.add_child(atm)
	# landing beacon ring at the dock point
	var beacon := Node3D.new()
	beacon.name = "LandingBeacon"
	planet.add_child(beacon)
	var tor := TorusMesh.new()
	tor.inner_radius = 26.0
	tor.outer_radius = 29.0
	tor.rings = 32
	tor.ring_segments = 6
	var bm := _mesh(beacon, tor, Vector3.ZERO, Color(0.3, 1.0, 0.6), Vector3.ONE, Vector3(90, 0, 0), true)
	bm.set_meta("blink", 0.0)
	var dp := dock_point(planet)
	beacon.global_position = dp
	beacon.look_at(planet.global_position, Vector3.UP)

func dock_point(n: Node3D) -> Vector3:
	if n == planet:
		var toward: Vector3 = (station.global_position - planet.global_position).normalized()
		return planet.global_position + toward * (float(planet.get_meta("radius")) + 60.0)
	return n.global_position + Vector3(0, 0, 150)

func _build_gate(d: Dictionary) -> void:
	gate = Node3D.new()
	gate.name = d["name"]
	gate.position = d["pos"]
	gate.set_meta("kind", "gate")
	gate.set_meta("info", d)
	gate.set_meta("radius", 55.0)
	add_child(gate)
	# face the gate toward the system centre so arrivals come out facing inward
	var inward: Vector3 = (Vector3(0, 0, -1200) - gate.position)
	if inward.length() < 10.0: inward = Vector3(0, 0, -1)
	gate.look_at(gate.position - inward.normalized(), Vector3.UP)
	var ring := TorusMesh.new()
	ring.inner_radius = 44.0
	ring.outer_radius = 52.0
	ring.rings = 48
	ring.ring_segments = 8
	_mesh(gate, ring, Vector3.ZERO, Color(0.55, 0.6, 0.7), Vector3.ONE, Vector3(90, 0, 0))
	var box := BoxMesh.new()
	for i in 6:
		var a := i * TAU / 6.0
		_mesh(gate, box, Vector3(cos(a) * 56, sin(a) * 56, 0), Color(0.3, 0.33, 0.4), Vector3(10, 10, 16), Vector3(0, 0, rad_to_deg(a)))
		_mesh(gate, box, Vector3(cos(a) * 56, sin(a) * 56, 8.5), Color(0.3, 0.85, 1.0), Vector3(4, 4, 1), Vector3.ZERO, true)
	gate_portal = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 44.0
	disc.bottom_radius = 44.0
	disc.height = 0.5
	disc.radial_segments = 40
	gate_portal.mesh = disc
	gate_portal.rotation_degrees = Vector3(90, 0, 0)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_texture = _radial_texture(Color(0.35, 0.8, 1.0), 0.0)
	pm.albedo_color = Color(1, 1, 1, 0.55)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	gate_portal.material_override = pm
	gate.add_child(gate_portal)

func _rock_mesh(seed_v: int, ice: bool) -> ArrayMesh:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = 1.3
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		verts[i] = v * (1.0 + n.get_noise_3dv(v * 1.7) * 0.45) * Vector3(1.0, 0.8, 1.15)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for i in idx.size():
		st.add_vertex(verts[idx[i]])
	st.generate_normals()
	var m := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.85, 0.95) if ice else Color(0.42, 0.37, 0.33)
	mat.roughness = 0.35 if ice else 0.95
	mat.metallic = 0.1
	m.surface_set_material(0, mat)
	return m

func _build_belt(d: Dictionary) -> void:
	belt_center = d["center"]
	belt_radius = d["radius"]
	var variants := 3
	var per := int(d["count"]) / variants
	for v in variants:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rock_mesh(hash(sys_id) + v, d["ice"])
		mm.instance_count = per
		for i in per:
			var a := _rng.randf() * TAU
			var dist := sqrt(_rng.randf()) * belt_radius
			var p := belt_center + Vector3(cos(a) * dist, _rng.randfn(0.0, 30.0), sin(a) * dist * 0.8)
			var r := lerpf(3.0, 24.0, pow(_rng.randf(), 2.2))
			var b := Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)).scaled(Vector3.ONE * r)
			mm.set_instance_transform(i, Transform3D(b, p))
			rocks.append([p, r * 1.05])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "Asteroids%d" % v
		add_child(mmi)

func _build_nebula(d: Dictionary) -> void:
	nebula_center = d["center"]
	nebula_radius = d["radius"]
	nebula_color = d["color"]
	var tex := [_cloud_texture(nebula_color, hash(sys_id)), _cloud_texture(nebula_color.lightened(0.2), hash(sys_id) + 3)]
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var holder := Node3D.new()
	holder.name = "Nebula"
	add_child(holder)
	for i in 26:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = tex[i % 2]
		m.albedo_color = Color(1, 1, 1, 0.55)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mi.material_override = m
		var dir := Vector3(_rng.randfn(0, 1), _rng.randfn(0, 0.5), _rng.randfn(0, 1)).normalized()
		mi.position = nebula_center + dir * _rng.randf_range(0.0, nebula_radius * 0.85)
		var s := _rng.randf_range(260.0, 460.0)
		mi.scale = Vector3(s, s, s)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)

func _build_player() -> void:
	player = Node3D.new()
	player.name = "Player"
	add_child(player)
	set_player_model()

func set_player_model() -> void:
	if is_instance_valid(model): model.queue_free()
	model = ShipFactory.build(Data.SHIPS[GS.ship_id]["model"])
	player.add_child(model)
	model.visible = GS.view != "cockpit"

func _spawn_group(center: Vector3, count: int) -> void:
	var e: Dictionary = Data.ENEMIES[sys["enemy"]]
	for i in count:
		var n := ShipFactory.build("enemy")
		var node := Node3D.new()
		_enemy_serial += 1
		node.name = "%s %d" % [e["name"], _enemy_serial]
		node.add_child(n)
		node.position = center + Vector3(_rng.randf_range(-60, 60), _rng.randf_range(-20, 20), _rng.randf_range(-60, 60))
		node.set_meta("kind", "enemy")
		node.set_meta("radius", 7.0)
		add_child(node, true)
		enemies.append({"node": node, "hp": e["hull"], "max": e["hull"], "def": e, "vel": Vector3.ZERO, "home": center,
			"cd": _rng.randf_range(0.5, 2.0), "orbit": _rng.randf() * TAU, "aggro": false, "strafe": _rng.randf_range(-1, 1)})

func _build_traffic() -> void:
	for pair in sys["traffic"]:
		for k in 2:
			var node := Node3D.new()
			node.name = "Freighter %s-%d" % [sys["name"], k + 1]
			node.add_child(ShipFactory.build("fleet"))
			node.set_meta("kind", "traffic")
			node.set_meta("radius", 12.0)
			add_child(node)
			traffic.append({"node": node, "t": 0.5 * k, "dir": 1.0 if k == 0 else -1.0})

# ---------------------------------------------------------------- per frame
func _process(dt: float) -> void:
	time += dt
	if not is_instance_valid(player): return
	_update_player(dt)
	_update_enemies(dt)
	_update_traffic(dt)
	_update_bolts(dt)
	_update_missiles(dt)
	_update_mines(dt)
	_update_effects(dt)
	_collisions(dt)
	_update_camera(dt, false)
	_ambient_anim(dt)
	if not is_instance_valid(target): target = null
	if target == null or target.get_meta("kind", "") != "enemy": _auto_target()
	# respawn hostiles once a system is cleared
	if enemies.is_empty():
		respawn_timer += dt
		if respawn_timer > 40.0:
			respawn_timer = 0.0
			for p in sys["patrols"]:
				if p.distance_to(player.global_position) > 700.0: _spawn_group(p, 2)

func _update_player(dt: float) -> void:
	var s: Dictionary = GS.ship()
	var base_speed: float = s["speed"]
	var turn: float = s["turn"]
	gun_cd = maxf(0.0, gun_cd - dt)
	shield_delay = maxf(0.0, shield_delay - dt)
	hit_shake = maxf(0.0, hit_shake - dt * 2.5)
	GS.energy = minf(Data.ENERGY_MAX, GS.energy + Data.ENERGY_REGEN * dt)
	for k in ["shield_cd", "energy_cd", "repair_cd", "missile_cd", "mine_cd"]: set(k, maxf(0.0, float(get(k)) - dt))
	if shield_delay <= 0.0 and GS.shield < GS.max_shield():
		GS.shield = minf(GS.max_shield(), GS.shield + GS.max_shield() * 0.12 * dt)
	var steer := aim if controls else Vector2.ZERO
	var thrust := move if controls else Vector2.ZERO
	if autopilot != null and is_instance_valid(autopilot) and controls:
		var ap := _autopilot_input()
		steer = ap[0]
		thrust = ap[1]
	yaw -= steer.x * turn * dt
	pitch = clampf(pitch - steer.y * turn * 0.8 * dt, deg_to_rad(-75), deg_to_rad(75))
	player.basis = Basis.from_euler(Vector3(pitch, yaw, 0))
	# visual bank
	if is_instance_valid(model):
		model.rotation.z = lerpf(model.rotation.z, -steer.x * 0.55, minf(1.0, dt * 4.0))
		model.rotation.x = lerpf(model.rotation.x, -steer.y * 0.12, minf(1.0, dt * 4.0))
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	if cruise and controls:
		cruise_charge = minf(1.0, cruise_charge + dt / 1.6)
	else:
		cruise_charge = 0.0
	var desired: Vector3
	if cruise and cruise_charge >= 1.0 and controls:
		desired = fwd * base_speed * 5.0
	else:
		var f := thrust.y if thrust.y >= 0.0 else thrust.y * 0.5
		desired = fwd * base_speed * f + right * base_speed * 0.6 * thrust.x
	vel = vel.lerp(desired, minf(1.0, dt * (0.9 if cruise else 1.8)))
	player.global_position += vel * dt
	speed_now = vel.length()
	# weapons
	if controls:
		var want := fire_held
		if GS.is_auto("guns") and _in_fire_cone(target): want = true
		var cost := Data.ENERGY_PER_GUN * float(GS.ship()["guns"])
		if want and gun_cd <= 0.0 and GS.energy >= cost:
			GS.energy -= cost
			_fire_guns()
			if cruise: set_cruise(false)
		_auto_systems(dt)

func _autopilot_input() -> Array:
	var goal: Vector3 = autopilot.global_position
	var kind: String = autopilot.get_meta("kind", "")
	if kind == "planet" or kind == "station": goal = dock_point(autopilot)
	if kind == "gate": goal = autopilot.global_position + autopilot.global_basis.z * 120.0
	var to := goal - player.global_position
	var local := player.global_basis.inverse() * to.normalized()
	var steer := Vector2(clampf(local.x * 3.0, -1, 1), clampf(-local.y * 3.0, -1, 1))
	var dist := to.length()
	var arrive := 170.0
	if dist < arrive:
		autopilot = null
		set_cruise(false)
		message.emit("Autopilot: arrived.")
		return [Vector2.ZERO, Vector2.ZERO]
	var aligned := local.z < -0.9
	if aligned and dist > 900.0 and not cruise: set_cruise(true)
	if dist < 600.0 and cruise: set_cruise(false)
	var th := 1.0 if local.z < -0.3 else 0.2
	return [steer, Vector2(0, th)]

func set_cruise(on: bool) -> void:
	cruise = on
	if not on: cruise_charge = 0.0

func _in_fire_cone(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t) or t.get_meta("kind", "") != "enemy": return false
	var to := t.global_position - player.global_position
	var w: Dictionary = GS.weapon()
	if to.length() > float(w["range"]): return false
	return (-player.global_basis.z).dot(to.normalized()) > cos(deg_to_rad(8.0))

func _fire_guns() -> void:
	var w: Dictionary = GS.weapon()
	gun_cd = 1.0 / float(w["rate"])
	var guns: int = GS.ship()["guns"]
	var fwd := -player.global_basis.z
	var aim_dir := fwd
	# light aim assist toward the lead point of a target inside a small cone
	if target and is_instance_valid(target) and target.get_meta("kind", "") == "enemy":
		var to := target.global_position - player.global_position
		if fwd.dot(to.normalized()) > cos(deg_to_rad(10.0)):
			var tv: Vector3 = _enemy_entry(target).get("vel", Vector3.ZERO)
			var lead := target.global_position + tv * (to.length() / float(w["speed"]))
			aim_dir = (lead - player.global_position).normalized()
	for g in guns:
		var off := (g - (guns - 1) / 2.0) * 2.4
		var from := player.global_position + player.global_basis.x * off + fwd * 5.0
		_spawn_bolt(from, aim_dir * float(w["speed"]) + vel, float(w["damage"]), w["color"], "player", float(w["range"]) / float(w["speed"]))

func _spawn_bolt(from: Vector3, v: Vector3, dmg: float, col: Color, owner: String, life: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	mi.material_override = ShipFactory.mat(col, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	mi.look_at(from + v, Vector3.UP)
	bolts.append({"node": mi, "vel": v, "life": life, "dmg": dmg, "owner": owner})

func fire_missile() -> bool:
	if GS.missiles <= 0: return false
	var t := target if (target and is_instance_valid(target) and target.get_meta("kind", "") == "enemy") else null
	if t == null: t = _nearest_enemy(900.0)
	if t == null:
		message.emit("No hostile target for missile lock.")
		return false
	GS.missiles -= 1
	GS.changed.emit()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.6, 2.6)
	mi.mesh = bm
	mi.material_override = ShipFactory.mat(Color(1.0, 0.8, 0.4), true)
	add_child(mi)
	mi.global_position = player.global_position - player.global_basis.y * 1.5
	missiles_live.append({"node": mi, "vel": -player.global_basis.z * 90.0 + vel, "target": t, "life": 7.0})
	return true

func _update_bolts(dt: float) -> void:
	for i in range(bolts.size() - 1, -1, -1):
		var b: Dictionary = bolts[i]
		var n: MeshInstance3D = b["node"]
		var from := n.global_position
		var to: Vector3 = from + b["vel"] * dt
		n.global_position = to
		b["life"] -= dt
		var hit := false
		if b["owner"] == "player":
			for e in enemies:
				if _seg_hit(from, to, e["node"].global_position, 7.5):
					_damage_enemy(e, b["dmg"])
					hit = true
					break
		else:
			if _seg_hit(from, to, player.global_position, 5.0):
				_player_hit(b["dmg"])
				hit = true
		if not hit and in_belt_region(to):
			for r in rocks:
				if _seg_hit(from, to, r[0], r[1]):
					_spark(to, Color(1, 0.8, 0.5), 3.0)
					hit = true
					break
		if hit or b["life"] <= 0.0:
			n.queue_free()
			bolts.remove_at(i)

func in_belt_region(p: Vector3) -> bool:
	return p.distance_to(belt_center) < belt_radius + 60.0

func _seg_hit(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var ab := b - a
	var t := 0.0
	var l2 := ab.length_squared()
	if l2 > 0.0: t = clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(c) < r

func _update_missiles(dt: float) -> void:
	for i in range(missiles_live.size() - 1, -1, -1):
		var m: Dictionary = missiles_live[i]
		var n: MeshInstance3D = m["node"]
		var tv = m["target"]
		var t: Node3D = tv if is_instance_valid(tv) else null
		var v: Vector3 = m["vel"]
		if is_instance_valid(t):
			var want := (t.global_position - n.global_position).normalized() * 190.0
			v = v.lerp(want, minf(1.0, dt * 2.6))
		m["vel"] = v
		n.global_position += v * dt
		if v.length() > 0.1: n.look_at(n.global_position + v, Vector3.UP)
		m["life"] -= dt
		if int(time * 30.0) % 2 == 0: _spark(n.global_position, Color(1, 0.7, 0.3), 1.2, 0.35)
		var done: bool = m["life"] <= 0.0
		if is_instance_valid(t) and n.global_position.distance_to(t.global_position) < 9.0:
			var e := _enemy_entry(t)
			if not e.is_empty(): _damage_enemy(e, Data.MISSILE_DAMAGE)
			_spark(n.global_position, Color(1, 0.6, 0.2), 8.0)
			done = true
		if done:
			n.queue_free()
			missiles_live.remove_at(i)

func _enemy_entry(n: Node3D) -> Dictionary:
	for e in enemies:
		if e["node"] == n: return e
	return {}

func _damage_enemy(e: Dictionary, dmg: float) -> void:
	e["hp"] -= dmg
	e["aggro"] = true
	_spark(e["node"].global_position, Color(0.6, 0.9, 1.0), 2.5, 0.25)
	if e["hp"] <= 0.0:
		var n: Node3D = e["node"]
		_explode(n.global_position)
		enemies.erase(e)
		var reward: int = e["def"]["reward"]
		enemy_killed.emit(reward, n.name)
		if target == n: target = null
		n.queue_free()

func _player_hit(dmg: float) -> void:
	shield_delay = 3.0
	hit_shake = 1.0
	GS.damage(dmg)
	if cruise: set_cruise(false)
	if GS.hull <= 0.0 and controls:
		_explode(player.global_position)
		controls = false
		player_destroyed.emit()

func _update_enemies(dt: float) -> void:
	var ppos := player.global_position
	for e in enemies:
		var n: Node3D = e["node"]
		var d: Dictionary = e["def"]
		var to := ppos - n.global_position
		var dist := to.length()
		if dist < 650.0 or e["aggro"]: e["aggro"] = dist < 1400.0
		var goal: Vector3
		if e["aggro"] and controls:
			# attack run: approach, then peel off to the side and come back around
			var side: Vector3 = player.global_basis.x * float(e["strafe"]) * 90.0
			goal = ppos + side if dist > 140.0 else n.global_position - to.normalized() * 200.0 + side
		else:
			e["orbit"] += dt * 0.25
			goal = e["home"] + Vector3(cos(e["orbit"]) * 120.0, sin(e["orbit"] * 0.7) * 25.0, sin(e["orbit"]) * 120.0)
		var fwd := -n.global_basis.z
		var want := (goal - n.global_position).normalized()
		var new_fwd := fwd.slerp(want, minf(1.0, dt * float(d["turn"])))
		if new_fwd.length() > 0.01:
			n.look_at(n.global_position + new_fwd, Vector3.UP)
		var sp: float = d["speed"] * (1.0 if e["aggro"] else 0.5)
		e["vel"] = (e["vel"] as Vector3).lerp(-n.global_basis.z * sp, minf(1.0, dt * 1.5))
		n.global_position += e["vel"] * dt
		# shooting
		e["cd"] -= dt
		if e["aggro"] and controls and dist < 420.0 and e["cd"] <= 0.0:
			if (-n.global_basis.z).dot(to.normalized()) > cos(deg_to_rad(12.0)):
				e["cd"] = 1.0 / float(d["rate"])
				var lead := ppos + vel * (dist / 300.0)
				var jitter := Vector3(_rng.randfn(0, 4), _rng.randfn(0, 4), _rng.randfn(0, 4))
				_spawn_bolt(n.global_position - n.global_basis.z * 5.0, (lead + jitter - n.global_position).normalized() * 300.0, d["damage"], Color(1.0, 0.35, 0.25), "enemy", 1.6)

func _update_traffic(dt: float) -> void:
	var a := dock_point(station)
	var b := dock_point(planet)
	for t in traffic:
		t["t"] += dt * 0.012 * t["dir"]
		if t["t"] > 1.0 or t["t"] < 0.0:
			t["dir"] *= -1.0
			t["t"] = clampf(t["t"], 0.0, 1.0)
		var n: Node3D = t["node"]
		var p := a.lerp(b, t["t"]) + Vector3(0, 40.0 + 30.0 * t["dir"], 0)
		var dir: Vector3 = (b - a).normalized() * float(t["dir"])
		n.global_position = p
		n.look_at(p + dir, Vector3.UP)

func _collisions(dt: float) -> void:
	var p := player.global_position
	in_belt = in_belt_region(p)
	if in_belt:
		for r in rocks:
			var d: float = p.distance_to(r[0])
			var rr: float = r[1] + 3.5
			if d < rr:
				var n: Vector3 = (p - r[0]).normalized()
				player.global_position = r[0] + n * rr
				var impact := vel.dot(-n)
				if impact > 8.0:
					_player_hit(impact * 0.35)
					_spark(player.global_position, Color(1, 0.8, 0.5), 4.0)
					message.emit("Collision alert: asteroid impact.")
				vel = vel - n * vel.dot(n) * 1.6
	for body: Node3D in [station, planet]:
		var rad: float = body.get_meta("radius")
		var hitr := rad + (6.0 if body == planet else 10.0)
		var d2 := player.global_position.distance_to(body.global_position)
		if d2 < hitr:
			var n2 := (player.global_position - body.global_position).normalized()
			player.global_position = body.global_position + n2 * hitr
			vel = vel - n2 * vel.dot(n2) * 1.5
	var nd := p.distance_to(nebula_center)
	in_nebula = clampf((nebula_radius - nd) / (nebula_radius * 0.35), 0.0, 1.0)

func _update_camera(dt: float, snap: bool) -> void:
	if GS.view == "cockpit":
		# pilot's eye: fixed to the hull, tiny lag-free shake on hits
		cam.global_position = player.global_position + player.global_basis * Vector3(0, 0.9, -1.2)
		var ahead := player.global_position - player.global_basis.z * 60.0
		if hit_shake > 0.0: ahead += Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), 0) * hit_shake * 1.2
		cam.look_at(ahead, player.global_basis.y)
		cam.fov = lerpf(cam.fov, 88.0 if (cruise and cruise_charge >= 1.0) else 76.0, minf(1.0, dt * 2.0))
		return
	var back := 15.0 + (4.0 if cruise and cruise_charge >= 1.0 else 0.0)
	var want := player.global_position + player.global_basis * Vector3(0, 2.2, back)
	if snap: cam.global_position = want
	else: cam.global_position = cam.global_position.lerp(want, minf(1.0, dt * 6.0))
	var look := player.global_position - player.global_basis.z * 30.0 + player.global_basis.y * 2.6
	if hit_shake > 0.0: look += Vector3(_rng.randfn(0, 1), _rng.randfn(0, 1), 0) * hit_shake * 0.8
	cam.look_at(look, player.global_basis.y)
	cam.fov = lerpf(cam.fov, 84.0 if (cruise and cruise_charge >= 1.0) else 70.0, minf(1.0, dt * 2.0))

func _ambient_anim(dt: float) -> void:
	if is_instance_valid(gate_portal):
		gate_portal.rotate_object_local(Vector3.UP, dt * 0.8)
		var pm := gate_portal.material_override as StandardMaterial3D
		pm.albedo_color.a = 0.4 + 0.15 * sin(time * 2.0)

# ---------------------------------------------------------------- effects
func _spark(at: Vector3, col: Color, size: float, life := 0.3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _spark_tex()
	m.albedo_color = col
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	effects.append({"node": mi, "life": life, "max": life, "grow": size * 0.5})

static var _spark_texture: ImageTexture
func _spark_tex() -> ImageTexture:
	if _spark_texture == null: _spark_texture = _radial_texture(Color.WHITE, 0.08)
	return _spark_texture

func _explode(at: Vector3) -> void:
	_spark(at, Color(1.0, 0.75, 0.35), 26.0, 0.9)
	_spark(at, Color(1.0, 0.4, 0.15), 14.0, 1.3)
	for i in 6:
		_spark(at + Vector3(_rng.randfn(0, 5), _rng.randfn(0, 5), _rng.randfn(0, 5)), Color(1, 0.6, 0.3), 7.0, 0.7)

func _update_effects(dt: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var f: Dictionary = effects[i]
		f["life"] -= dt
		var n: MeshInstance3D = f["node"]
		var k: float = clampf(f["life"] / f["max"], 0.0, 1.0)
		n.scale = Vector3.ONE * (1.0 + (1.0 - k) * 1.5)
		(n.material_override as StandardMaterial3D).albedo_color.a = k
		if f["life"] <= 0.0:
			n.queue_free()
			effects.remove_at(i)

# ---------------------------------------------------------------- cockpit systems (AUTO / MANUAL)
## Manually trigger one of the six systems. Returns false when it could not run.
func trigger_system(id: String) -> bool:
	match id:
		"shield":
			if shield_cd > 0.0: return _say(id, "Shield capacitor recharging (%ds)." % ceili(shield_cd))
			if GS.shield >= GS.max_shield() - 0.5: return _say(id, "Shields already full.")
			GS.shield = minf(GS.max_shield(), GS.shield + GS.max_shield() * 0.5)
			shield_cd = Data.SHIELD_BOOST_COOLDOWN
			GS.changed.emit()
			system_used.emit(id, "Shield recharge: +50%.")
			return true
		"hull":
			if repair_cd > 0.0: return false
			if GS.repairs <= 0: return _say(id, "No repair kits left — dock to restock.")
			if not GS.use_repair(): return _say(id, "Hull is intact.")
			repair_cd = 1.5
			system_used.emit(id, "Hull repair: +40%%. %d kit%s left." % [GS.repairs, "" if GS.repairs == 1 else "s"])
			return true
		"energy":
			if energy_cd > 0.0: return _say(id, "Energy capacitor recharging (%ds)." % ceili(energy_cd))
			GS.energy = Data.ENERGY_MAX
			energy_cd = Data.ENERGY_BOOST_COOLDOWN
			GS.changed.emit()
			system_used.emit(id, "Energy recharged.")
			return true
		"missile":
			if missile_cd > 0.0: return false
			if fire_missile():
				missile_cd = 1.2
				system_used.emit(id, "Missile away.")
				return true
			return false
		"mine":
			return deploy_mine()
	return false

func _say(id: String, t: String) -> bool:
	system_used.emit(id, t)
	return false

func _auto_systems(_dt: float) -> void:
	if GS.is_auto("shield") and GS.shield <= 0.5 and shield_cd <= 0.0 and shield_delay > 0.0: trigger_system("shield")
	if GS.is_auto("hull") and GS.hull < GS.max_hull() * 0.35 and GS.repairs > 0 and repair_cd <= 0.0: trigger_system("hull")
	if GS.is_auto("energy") and GS.energy < Data.ENERGY_MAX * 0.15 and energy_cd <= 0.0: trigger_system("energy")
	# missiles: after holding a hostile in the reticle for 1.5 s
	if _in_fire_cone(target) or (target and target.get_meta("kind", "") == "enemy" and _cone(target, 15.0, 800.0)):
		lock_time += _dt
	else:
		lock_time = 0.0
	if GS.is_auto("missile") and lock_time > 1.5 and GS.missiles > 0 and missile_cd <= 0.0:
		if trigger_system("missile"): missile_cd = 5.0
	# mines: drop one when a hostile is chasing close behind
	if GS.is_auto("mine") and GS.mines > 0 and mine_cd <= 0.0:
		for e in enemies:
			var to: Vector3 = e["node"].global_position - player.global_position
			if to.length() < 160.0 and (-player.global_basis.z).dot(to.normalized()) < -0.5:
				deploy_mine()
				break

func _cone(t: Node3D, deg: float, rng: float) -> bool:
	if t == null or not is_instance_valid(t): return false
	var to := t.global_position - player.global_position
	return to.length() < rng and (-player.global_basis.z).dot(to.normalized()) > cos(deg_to_rad(deg))

func deploy_mine() -> bool:
	if mine_cd > 0.0: return false
	if GS.mines <= 0: return _say("mine", "No mines left — buy more at a dealer.")
	GS.mines -= 1
	GS.changed.emit()
	mine_cd = 2.5
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.4
	sm.height = 2.8
	sm.radial_segments = 10
	sm.rings = 5
	mi.mesh = sm
	mi.material_override = ShipFactory.mat(Color(0.25, 0.27, 0.3), false, 0.7)
	var light := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.7, 0.7, 0.7)
	light.mesh = lb
	light.position = Vector3(0, 1.3, 0)
	light.material_override = ShipFactory.mat(Color(1.0, 0.3, 0.2), true)
	mi.add_child(light)
	add_child(mi)
	mi.global_position = player.global_position + player.global_basis.z * 10.0
	mines_live.append({"node": mi, "arm": 1.0, "life": 60.0, "vel": vel * 0.2})
	system_used.emit("mine", "Mine deployed. %d left." % GS.mines)
	return true

func _update_mines(dt: float) -> void:
	for i in range(mines_live.size() - 1, -1, -1):
		var m: Dictionary = mines_live[i]
		var n: MeshInstance3D = m["node"]
		m["arm"] -= dt
		m["life"] -= dt
		m["vel"] = (m["vel"] as Vector3) * (1.0 - minf(1.0, dt * 0.8))
		n.global_position += m["vel"] * dt
		n.rotate_y(dt * 1.5)
		var boom: bool = m["life"] <= 0.0
		if m["arm"] <= 0.0:
			for e in enemies:
				if e["node"].global_position.distance_to(n.global_position) < 22.0:
					boom = true
					break
		if boom:
			_explode(n.global_position)
			for e in enemies.duplicate():
				var d: float = e["node"].global_position.distance_to(n.global_position)
				if d < Data.MINE_RADIUS: _damage_enemy(e, Data.MINE_DAMAGE * (1.0 - d / Data.MINE_RADIUS * 0.5))
			n.queue_free()
			mines_live.remove_at(i)

## Chase camera or first-person cockpit.
func set_view(v: String) -> void:
	GS.view = v
	if is_instance_valid(model): model.visible = v != "cockpit"
	_update_camera(1.0, true)

# ---------------------------------------------------------------- targeting / queries
func _nearest_enemy(max_d: float) -> Node3D:
	var best: Node3D = null
	var bd := max_d
	for e in enemies:
		var d: float = e["node"].global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = e["node"]
	return best

func _auto_target() -> void:
	# keep a manually chosen non-enemy target; otherwise pick the nearest hostile ahead
	if target != null and target.get_meta("kind", "") != "enemy": return
	var best: Node3D = null
	var score := -1.0
	for e in enemies:
		var n: Node3D = e["node"]
		var to := n.global_position - player.global_position
		var d := to.length()
		if d > 1100.0: continue
		var s := (-player.global_basis.z).dot(to.normalized()) + 600.0 / maxf(d, 1.0)
		if s > score:
			score = s
			best = n
	target = best

func targetables() -> Array:
	var out: Array = []
	var list := enemies.duplicate()
	list.sort_custom(func(a, b): return a["node"].global_position.distance_to(player.global_position) < b["node"].global_position.distance_to(player.global_position))
	for e in list: out.append(e["node"])
	out.append(station)
	out.append(planet)
	out.append(gate)
	return out

func cycle_target() -> void:
	var list := targetables()
	var i := list.find(target)
	target = list[(i + 1) % list.size()]
	message.emit("Target: %s" % target.name)

func dock_candidate() -> Node3D:
	var p := player.global_position
	if p.distance_to(station.global_position) < DOCK_RANGE_STATION: return station
	if p.distance_to(dock_point(station)) < DOCK_RANGE_STATION: return station
	var surf := p.distance_to(planet.global_position) - float(planet.get_meta("radius"))
	if surf < DOCK_RANGE_PLANET: return planet
	return null

func gate_in_range() -> bool:
	return player.global_position.distance_to(gate.global_position) < GATE_RANGE

func distance_to(n: Node3D) -> float:
	if n == planet: return maxf(0.0, player.global_position.distance_to(planet.global_position) - float(planet.get_meta("radius")))
	return player.global_position.distance_to(n.global_position)

func target_health() -> float:
	if target == null: return -1.0
	var e := _enemy_entry(target)
	if e.is_empty(): return -1.0
	return float(e["hp"]) / float(e["max"])

func hostiles_near(r: float) -> int:
	var c := 0
	for e in enemies:
		if e["node"].global_position.distance_to(player.global_position) < r: c += 1
	return c

func pulse_lights(t: float) -> void:
	pass
