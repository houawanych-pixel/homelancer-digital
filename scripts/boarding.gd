class_name Boarding
extends RefCounted
## v11.45 (owner: "I want to go inside the battleship, as a mech"): the inside of a fleet battleship, built as a small
## level the mech walks (the planet-surface code with a flat deck, walls and a roof). Floor plan first, Metal Gear
## style (rooms joined by passages); the walls get dressed later.
##
## Side entry (the open side hangar, once the SHIELD TOWER is down): the HANGAR BAY, a PASSAGE wide enough for two mechs
## side by side, and the REACTOR HALL: the big battle space with the core in the middle. Enemy mechs come at you three
## at a time, ten in all; then the BOSS. It drops the bounty pilot: grab it. Then the core can be hit; blow it and get
## back out through the bay before the countdown ends.
##
## Units: metres. +X starboard, -Z deeper in (you come in heading -Z). The deck is y = 0.

static var sunk := {}   # system id -> true: you blew that battleship's reactor (this session: it is gone)

const ROOMS := {   # [x0, x1, z0, z1, height]
	"bay": [-45.0, 45.0, -70.0, 0.0, 44.0],
	"passage": [-22.0, 22.0, -230.0, -70.0, 34.0],
	"hall": [-115.0, 115.0, -460.0, -230.0, 72.0],
}
const WALL := 4.0                         # wall thickness
const EXIT_AT := Vector3(0, 0, -8.0)      # back out here (the bay's open side)
const START_AT := Vector3(0, 0, -30.0)    # where you land inside
const CORE_AT := Vector3(0, 0, -360.0)    # the reactor core
const MECH_DOORS := [Vector3(-90, 0, -440), Vector3(90, 0, -440), Vector3(-100, 0, -300), Vector3(100, 0, -300)]   # where their mechs walk in
const BOSS_AT := Vector3(0, 0, -440)

## The rooms' floor rectangles joined (for keeping the mechs inside): [x0, x1, z0, z1].
static func inside(p: Vector3, pad := 0.0) -> bool:
	for k in ROOMS:
		var r: Array = ROOMS[k]
		if p.x > float(r[0]) + pad and p.x < float(r[1]) - pad and p.z > float(r[2]) + pad and p.z < float(r[3]) - pad: return true
	return false

## Clamp a point onto the nearest room floor (a mech that walks into a wall stays in).
static func keep_in(p: Vector3, pad := 10.0) -> Vector3:
	if inside(p, pad): return p
	var best := p
	var bd := INF
	for k in ROOMS:
		var r: Array = ROOMS[k]
		var q := Vector3(clampf(p.x, float(r[0]) + pad, float(r[1]) - pad), p.y, clampf(p.z, float(r[2]) + pad, float(r[3]) - pad))
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = q
	return best

## The roof over a point (the room it is in), or the lowest roof.
static func roof_at(p: Vector3) -> float:
	for k in ROOMS:
		var r: Array = ROOMS[k]
		if p.x > float(r[0]) and p.x < float(r[1]) and p.z > float(r[2]) and p.z < float(r[3]): return float(r[4])
	return float(ROOMS["passage"][4])

## Build the decks, walls, roofs, lights and the core under `root`. Returns the solid boxes [[holder, AABB], ...]
## (the walls; the floor and roof are handled as heights).
static func build(root: Node3D, tint: Color) -> Array:
	var boxes: Array = []
	var hull := ShipFactory.mat(Color(0.42, 0.43, 0.46), false, 0.55)
	var deck := ShipFactory.mat(Color(0.3, 0.31, 0.33), false, 0.7)
	var trim := ShipFactory.mat(tint.lerp(Color(1, 1, 1), 0.15), true)
	for k in ROOMS:
		var r: Array = ROOMS[k]
		var x0: float = r[0]
		var x1: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var h: float = r[4]
		_slab(root, Vector3(x0, -WALL, z0), Vector3(x1, 0, z1), deck, null)   # deck
		_slab(root, Vector3(x0, h, z0), Vector3(x1, h + WALL, z1), hull, null)  # roof
		# side walls (x0 / x1), the length of the room
		boxes.append(_slab(root, Vector3(x0 - WALL, 0, z0), Vector3(x0, h, z1), hull, root))
		boxes.append(_slab(root, Vector3(x1, 0, z0), Vector3(x1 + WALL, h, z1), hull, root))
		# end walls with a doorway where the next room joins
		for end in [z0, z1]:
			var gap := _gap(k, end)
			if gap.x >= gap.y:   # a full wall
				if not (k == "bay" and end == z1): boxes.append(_slab(root, Vector3(x0, 0, end - WALL * 0.5), Vector3(x1, h, end + WALL * 0.5), hull, root))
				continue
			if gap.x > x0: boxes.append(_slab(root, Vector3(x0, 0, end - WALL * 0.5), Vector3(gap.x, h, end + WALL * 0.5), hull, root))
			if gap.y < x1: boxes.append(_slab(root, Vector3(gap.y, 0, end - WALL * 0.5), Vector3(x1, h, end + WALL * 0.5), hull, root))
		# ribs and light strips every 20 m along the walls; a glow line down the middle of the deck
		var z := z1 - 10.0
		while z > z0 + 5.0:
			for sx in [x0 + 0.6, x1 - 0.6]:
				_slab(root, Vector3(sx - 0.6, 0, z - 1.5), Vector3(sx + 0.6, h, z + 1.5), hull, null)
				_slab(root, Vector3(sx - 0.8, h * 0.62, z - 4.0), Vector3(sx + 0.8, h * 0.62 + 1.2, z + 4.0), trim, null)
			z -= 20.0
		_slab(root, Vector3(-0.8, 0.02, z0 + 2.0), Vector3(0.8, 0.12, z1 - 2.0), trim, null)
		# ceiling lamps on a 60 m grid (a light panel and a lamp each), so every corner is lit
		var lz := z1 - 25.0
		while lz > z0:
			var lx := x0 + minf(30.0, (x1 - x0) * 0.5)
			while lx < x1:
				_slab(root, Vector3(lx - 6, h - 0.6, lz - 6), Vector3(lx + 6, h - 0.1, lz + 6), trim, null)
				var lamp := OmniLight3D.new()
				lamp.position = Vector3(lx, h - 5.0, lz)
				lamp.omni_range = 95.0
				lamp.light_energy = 2.4
				lamp.light_color = Color(1, 0.96, 0.9).lerp(tint, 0.15)
				root.add_child(lamp)
				lx += 60.0
			lz -= 60.0
	# the bay's open side: a bright frame round the opening
	var bay: Array = ROOMS["bay"]
	_slab(root, Vector3(float(bay[0]), 0, -1.0), Vector3(float(bay[0]) + 2.0, float(bay[4]), 1.0), trim, null)
	_slab(root, Vector3(float(bay[1]) - 2.0, 0, -1.0), Vector3(float(bay[1]), float(bay[4]), 1.0), trim, null)
	_slab(root, Vector3(float(bay[0]), float(bay[4]) - 2.0, -1.0), Vector3(float(bay[1]), float(bay[4]), 1.0), trim, null)
	# the core's pit ring
	for a in 12:
		var ang := TAU * float(a) / 12.0
		var c := CORE_AT + Vector3(cos(ang), 0, sin(ang)) * 34.0
		_slab(root, c + Vector3(-3, 0, -3), c + Vector3(3, 10, 3), hull, null)
	return boxes

## Where a room's end wall opens into the next room: Vector2(gap x0, gap x1); x0 >= x1 = no doorway.
static func _gap(room: String, z: float) -> Vector2:
	var p: Array = ROOMS["passage"]
	if (room == "bay" and is_equal_approx(z, float(ROOMS["bay"][2]))) or (room == "hall" and is_equal_approx(z, float(ROOMS["hall"][3]))): return Vector2(float(p[0]), float(p[1]))
	if room == "passage": return Vector2(float(p[0]), float(p[1]))
	return Vector2(1, 0)

## One block of the ship: a mesh, and a solid box when `holder` is given.
static func _slab(root: Node3D, a: Vector3, b: Vector3, m: Material, holder) -> Array:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = (b - a).abs()
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = (a + b) * 0.5
	root.add_child(mi)
	if holder == null: return []
	return [holder, AABB(Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)), (b - a).abs())]
