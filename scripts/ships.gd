class_name ShipFactory
extends RefCounted
## Builds ship visuals. Real GLB models are used when present in assets/ships/; otherwise a clearly labelled,
## original low-poly stand-in is built from primitives. Every visual faces -Z and is about `length` units long.

# key -> [glb path, target length, extra yaw degrees applied after import]
const GLB := {
	"cadet": ["res://assets/ships/player/cadet_ship.glb", 9.0, 0.0],
	"ranger": ["res://assets/ships/player/ranger.glb", 10.5, 0.0],
	"lancer": ["res://assets/ships/player/lancer.glb", 12.0, 0.0],
	"enemy": ["res://assets/ships/enemy/enemy_fleet.glb", 10.0, 0.0],
	"enemy2": ["res://assets/ships/enemy/corsair.glb", 13.0, 0.0],
	"fleet": ["res://assets/ships/civilian/cargo_ship.glb", 16.0, 0.0],
	"fleet2": ["res://assets/ships/civilian/freighter.glb", 20.0, 0.0],
	"fleet3": ["res://assets/ships/civilian/tanker.glb", 24.0, 0.0],
	"tanker": ["res://assets/ships/civilian/big_tanker.glb", 110.0, 0.0],
	"carrier": ["res://assets/ships/civilian/carrier.glb", 130.0, 0.0],
	"station": ["res://assets/stations/station.glb", 150.0, 0.0],
	"missile": ["res://assets/weapons/missile.glb", 3.4, 0.0],
	"mine": ["res://assets/weapons/mine.glb", 3.2, 0.0],
	"gatling": ["res://assets/weapons/gatling.glb", 3.0, 0.0],
	"rocket_pod": ["res://assets/weapons/rocket_pod.glb", 3.0, 0.0],
	# mechs: rigged 3 m models scaled to small-ship size; yaw 180 so the mech faces -Z like the ships
	"mech_tan": ["res://assets/mechs/tan_navy_mecha.glb", 11.0, 180.0],
	"mech_player": ["res://assets/mechs/black_gold_mecha.glb", 9.5, 180.0],   # the player's ship <-> mech frame
}

static var _cache := {}
static var _mats := {}

static func has_real_model(key: String) -> bool:
	return GLB.has(key) and ResourceLoader.exists(GLB[key][0])

## keep = false: don't hold the model in memory after this copy is gone (hangar previews of ships you don't fly).
static func build(key: String, keep := true) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + key
	if has_real_model(key):
		var scene: PackedScene = _cache.get(key)
		if scene == null:
			scene = load(GLB[key][0])
			if keep: _cache[key] = scene
		var inst: Node3D = scene.instantiate()
		inst.rotation_degrees.y = GLB[key][2]
		root.add_child(inst)
		_fit(root, inst, GLB[key][1])
		root.set_meta("placeholder", false)
		return root
	root.set_meta("placeholder", true)
	match key:
		"cadet": _fighter(root, Color(0.86, 0.9, 0.95), Color(0.2, 0.75, 1.0), 1.0, 2)
		"ranger": _fighter(root, Color(0.42, 0.47, 0.55), Color(1.0, 0.72, 0.25), 1.15, 2)
		"lancer": _heavy(root, Color(0.3, 0.32, 0.36), Color(1.0, 0.35, 0.3))
		"enemy": _raider(root, Color(0.35, 0.08, 0.08), Color(1.0, 0.3, 0.15))
		"fleet": _freighter(root, Color(0.6, 0.64, 0.7), Color(0.4, 0.8, 1.0))
		"carrier": _carrier(root, Color(0.62, 0.66, 0.72), Color(0.35, 0.8, 1.0))
		_: _fighter(root, Color.WHITE, Color.CYAN, 1.0, 2)
	return root

## Scale and centre an imported model once (never re-scaled at runtime).
static func _fit(root: Node3D, inst: Node3D, length: float) -> void:
	var box := _aabb(inst, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO: return
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s := length / longest
	inst.scale = Vector3.ONE * s
	inst.position = -box.get_center() * s

static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is Node3D: xf = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var b: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
		out = b
		first = false
	for c in n.get_children():
		var cb := _aabb(c, xf)
		if cb.size == Vector3.ZERO: continue
		if first:
			out = cb
			first = false
		else:
			out = out.merge(cb)
	return out

static func mat(col: Color, emissive := false, metal := 0.4) -> StandardMaterial3D:
	var k := "%s|%s|%s" % [col.to_html(), emissive, metal]
	if _mats.has(k): return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = 0.45
	if emissive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[k] = m
	return m

static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3, col: Color, rot := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot
	mi.material_override = mat(col, emissive)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static var _box: BoxMesh
static var _prism: PrismMesh
static var _cyl: CylinderMesh
static var _sph: SphereMesh

static func _meshes() -> void:
	if _box: return
	_box = BoxMesh.new()
	_prism = PrismMesh.new()
	_cyl = CylinderMesh.new()
	_cyl.radial_segments = 10
	_cyl.rings = 1
	_sph = SphereMesh.new()
	_sph.radial_segments = 12
	_sph.rings = 6

static func _engine(root: Node3D, pos: Vector3, r: float, glow: Color) -> void:
	_part(root, _cyl, pos, Vector3(r, 0.5, r), Color(0.18, 0.2, 0.24), Vector3(90, 0, 0))
	var g := _part(root, _cyl, pos + Vector3(0, 0, 0.55), Vector3(r * 0.8, 0.06, r * 0.8), glow, Vector3(90, 0, 0), true)
	g.name = "EngineGlow"

static func _fighter(root: Node3D, body: Color, accent: Color, size: float, engines: int) -> void:
	_meshes()
	var s := size
	# fuselage: long nose prism + body block
	_part(root, _prism, Vector3(0, 0, -3.2 * s), Vector3(1.4 * s, 3.4 * s, 0.9 * s), body, Vector3(-90, 0, 0))
	_part(root, _box, Vector3(0, 0, 0.4 * s), Vector3(1.7 * s, 0.95 * s, 4.0 * s), body)
	_part(root, _sph, Vector3(0, 0.55 * s, -1.2 * s), Vector3(0.9 * s, 0.6 * s, 1.8 * s), Color(0.1, 0.22, 0.35))
	# swept wings
	for side in [-1.0, 1.0]:
		_part(root, _box, Vector3(side * 2.4 * s, -0.1 * s, 1.0 * s), Vector3(3.4 * s, 0.14 * s, 2.0 * s), body, Vector3(0, side * -24.0, side * -4.0))
		_part(root, _box, Vector3(side * 3.9 * s, 0.35 * s, 1.7 * s), Vector3(0.18 * s, 1.1 * s, 1.4 * s), accent)
		_part(root, _box, Vector3(side * 1.25 * s, 0.1 * s, -1.4 * s), Vector3(0.25 * s, 0.25 * s, 2.6 * s), Color(0.2, 0.22, 0.25))
	_part(root, _box, Vector3(0, 0.5 * s, 1.4 * s), Vector3(0.12 * s, 1.0 * s, 1.6 * s), accent)
	if engines == 2:
		for side in [-0.55, 0.55]: _engine(root, Vector3(side * s, 0, 2.6 * s), 0.55 * s, accent)
	else:
		_engine(root, Vector3(0, 0, 2.6 * s), 0.75 * s, accent)

static func _heavy(root: Node3D, body: Color, accent: Color) -> void:
	_meshes()
	_part(root, _prism, Vector3(0, 0, -3.8), Vector3(2.2, 3.2, 1.3), body, Vector3(-90, 0, 0))
	_part(root, _box, Vector3(0, 0, 0.6), Vector3(2.6, 1.4, 5.2), body)
	_part(root, _sph, Vector3(0, 0.8, -1.6), Vector3(1.1, 0.7, 2.0), Color(0.12, 0.16, 0.22))
	for side in [-1.0, 1.0]:
		_part(root, _box, Vector3(side * 2.7, -0.2, 1.2), Vector3(3.2, 0.3, 3.0), body, Vector3(0, side * -12.0, 0))
		_part(root, _box, Vector3(side * 4.2, -0.2, 0.2), Vector3(0.5, 0.5, 4.2), Color(0.22, 0.23, 0.26))
		_part(root, _box, Vector3(side * 4.2, 0.55, 1.8), Vector3(0.2, 1.0, 1.6), accent)
		_engine(root, Vector3(side * 1.0, 0, 3.4), 0.7, accent)
	_part(root, _box, Vector3(0, -0.85, -0.4), Vector3(0.45, 0.45, 3.6), Color(0.22, 0.23, 0.26))

static func _raider(root: Node3D, body: Color, accent: Color) -> void:
	_meshes()
	_part(root, _prism, Vector3(0, 0, -3.0), Vector3(1.2, 3.8, 0.7), body, Vector3(-90, 0, 0))
	_part(root, _box, Vector3(0, 0, 0.5), Vector3(1.5, 0.8, 3.4), Color(0.12, 0.1, 0.1))
	for side in [-1.0, 1.0]:
		_part(root, _prism, Vector3(side * 2.6, 0, 0.3), Vector3(1.4, 4.4, 0.25), body, Vector3(-90, 0, side * 90.0 + side * 18.0))
		_part(root, _box, Vector3(side * 4.2, 0, -1.3), Vector3(0.2, 0.2, 2.6), accent, Vector3.ZERO, true)
	_part(root, _prism, Vector3(0, 0.9, 1.2), Vector3(0.2, 1.4, 1.8), body)
	_engine(root, Vector3(0, 0, 2.3), 0.6, accent)

static func _freighter(root: Node3D, body: Color, accent: Color) -> void:
	_meshes()
	_part(root, _box, Vector3(0, 0, 0), Vector3(3.0, 2.4, 11.0), body)
	_part(root, _prism, Vector3(0, 0, -6.6), Vector3(3.0, 2.2, 2.4), body, Vector3(-90, 0, 0))
	for i in 3:
		_part(root, _box, Vector3(0, -1.9, -2.5 + i * 3.0), Vector3(3.6, 1.4, 2.4), Color(0.55, 0.42, 0.25))
	_part(root, _box, Vector3(0, 1.6, -4.2), Vector3(1.6, 0.8, 1.8), Color(0.1, 0.2, 0.3))
	for side in [-1.0, 1.0]: _engine(root, Vector3(side * 0.9, 0, 5.8), 0.8, accent)

static func _carrier(root: Node3D, body: Color, accent: Color) -> void:
	_meshes()
	var dark := Color(0.25, 0.28, 0.33)
	_part(root, _box, Vector3(0, 0, 0), Vector3(26, 12, 110), body)
	_part(root, _prism, Vector3(0, -1, -66), Vector3(26, 22, 12), body, Vector3(-90, 0, 0))
	_part(root, _box, Vector3(0, 8, 10), Vector3(34, 3, 86), dark) # flight deck
	for i in 8:
		_part(root, _box, Vector3(0, 9.7, -28 + i * 10), Vector3(1.5, 0.4, 5), accent, Vector3.ZERO, true)
	_part(root, _box, Vector3(12, 18, 22), Vector3(7, 16, 18), body) # island tower
	_part(root, _box, Vector3(12, 27, 20), Vector3(5, 3, 10), Color(0.1, 0.2, 0.3))
	for side in [-1.0, 1.0]:
		_part(root, _box, Vector3(side * 16, -2, 8), Vector3(8, 9, 70), dark)
		for j in 3:
			_engine(root, Vector3(side * (4 + j * 5.5), -1, 57), 2.4, accent)
