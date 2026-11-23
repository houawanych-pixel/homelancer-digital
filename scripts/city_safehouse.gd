class_name CitySafehouse
extends Node3D
## v13.285 (owner: "safehouses and garages", GTA style): every city has one safehouse: a street door with a green
## SAFEHOUSE sign and a beam you can see across the city. Walk up on foot and REST: if no police can see you, the heat
## is gone, you're patched up and the game is saved. Beside it, a garage gate on the pavement: drive a car you took up
## to it and STORE it (up to Data.GARAGE_MAX are kept, even between sessions); on foot by the gate, TAKE CAR drives one
## out again (yours: no crime).

var space: Node
var planet_id := ""
var tile := -1
var spot: Dictionary = {}   # CityPlan.safehouse()

func setup(sp: Node, pid: String, t: int) -> void:
	space = sp
	planet_id = pid
	tile = t
	name = "CitySafehouse"
	spot = CityPlan.safehouse(pid, t)
	if spot.is_empty(): return
	_build()

func _build() -> void:
	var g := CityPlan.ground(planet_id, tile)
	var door: Vector2 = spot["door"]
	var out: Vector2 = spot["out"]
	var green := Color(0.35, 1.0, 0.55)
	# the door: a glowing ring on the pavement, a tall beam, the sign
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 6.0
	cm.height = 0.25
	ring.mesh = cm
	ring.material_override = _glow(green, 1.6, 0.55)
	ring.position = Vector3(door.x, g + 0.15, door.y)
	ring.name = "DoorRing"
	add_child(ring)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 1.2
	bm.bottom_radius = 2.2
	bm.height = 260.0
	beam.mesh = bm
	beam.material_override = _glow(green, 1.2, 0.18)
	beam.position = Vector3(door.x, g + 130.0, door.y)
	beam.name = "Beam"
	add_child(beam)
	add_child(_sign("SAFEHOUSE", green, Vector3(door.x, g + 16.0, door.y)))
	# the garage gate: two posts and a lintel framing a roller door, on the pavement facing the street
	var gp: Vector2 = spot["garage"]
	var along := Vector2(-out.y, out.x)
	var amber := Color(1.0, 0.72, 0.2)
	var gate := Node3D.new()
	gate.name = "Garage"
	gate.position = Vector3(gp.x, g, gp.y)
	gate.rotation.y = atan2(-out.x, -out.y)
	add_child(gate)
	var w := Data.GARAGE_GATE_W
	var hgt := Data.GARAGE_GATE_H
	var metal := _plain(Color(0.25, 0.27, 0.31))
	for sx in [-1.0, 1.0]:
		_box(gate, Vector3(1.2, hgt, 1.6), Vector3(sx * (w * 0.5 + 0.6), hgt * 0.5, 0), metal)
		_box(gate, Vector3(0.3, hgt, 0.3), Vector3(sx * (w * 0.5 + 0.05), hgt * 0.5, -0.9), _glow(amber, 2.0))
	_box(gate, Vector3(w + 2.4, 1.4, 1.8), Vector3(0, hgt + 0.7, 0), metal)
	_box(gate, Vector3(w + 2.4, 0.3, 0.3), Vector3(0, hgt + 0.1, -1.0), _glow(amber, 2.0))
	_box(gate, Vector3(w, hgt, 0.4), Vector3(0, hgt * 0.5, 0.6), _plain(Color(0.42, 0.44, 0.48)))   # the roller door
	_box(gate, Vector3(w + 3.6, hgt + 2.2, 16.0), Vector3(0, (hgt + 2.2) * 0.5, 8.9), _plain(Color(0.2, 0.22, 0.26)))   # the garage itself, behind the gate
	_box(gate, Vector3(w + 3.8, 0.35, 0.35), Vector3(0, hgt + 2.2, 0.8), _glow(amber, 1.6))
	for k in 6: _box(gate, Vector3(w, 0.12, 0.1), Vector3(0, hgt * (k + 1) / 7.0, 0.38), _plain(Color(0.3, 0.32, 0.35)))
	var pad := MeshInstance3D.new()   # the bay painted on the street in front of it
	var pm := BoxMesh.new()
	pm.size = Vector3(w, 0.1, 14.0)
	pad.mesh = pm
	pad.material_override = _glow(amber, 0.7, 0.35)
	pad.position = Vector3(0, 0.08, -8.0)
	gate.add_child(pad)
	add_child(_sign("GARAGE", amber, Vector3(gp.x, g + hgt + 5.0, gp.y)))
	var _a := along

func _sign(txt: String, col: Color, at: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 96
	l.pixel_size = 0.04
	l.modulate = col
	l.outline_size = 18
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	l.position = at
	l.name = "Sign" + txt.capitalize()
	return l

func _glow(col: Color, e: float, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _plain(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = 0.6
	m.roughness = 0.4
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

func _flat(p: Vector3) -> Vector2: return Vector2(p.x, p.z)

## On foot at the safehouse door?
func near_door(p: Vector3) -> bool:
	return not spot.is_empty() and _flat(p).distance_to(spot["door"]) < Data.SAFEHOUSE_REACH

## At the garage gate (its bay in front included)?
func near_garage(p: Vector3) -> bool:
	if spot.is_empty(): return false
	var bay: Vector2 = (spot["garage"] as Vector2) + (spot["out"] as Vector2) * 8.0
	return _flat(p).distance_to(bay) < Data.GARAGE_REACH

## Where a car comes out of the garage, and which way it faces.
func exit_point() -> Array:
	var bay: Vector2 = (spot["garage"] as Vector2) + (spot["out"] as Vector2) * 14.0
	return [bay, spot["out"]]
