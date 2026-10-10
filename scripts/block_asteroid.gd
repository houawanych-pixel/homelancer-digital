extends MeshInstance3D
## v1.7x (owner): an asteroid made of blocks, like the planet ground but floating in zero gravity. Rock outside, dark
## obsidian streaks, and sometimes gold or diamond in the middle to mine. Shots break blocks; broken blocks drift
## away (space.gd keeps them inside the field's invisible sphere); gold and diamond drop pickups for the tractor beam.
## The blocks live in a small 3D grid in the asteroid's own space, so it can tumble slowly and hits still line up.

const EMPTY := 0
const ROCK := 1
const OBSIDIAN := 2
const GOLD := 3
const DIAMOND := 4
const NAMES := ["", "rock", "obsidian", "gold", "diamond"]

var n := 8                      # cells per side
var cell := 3.0                 # m
var cells := PackedByteArray()  # n^3 materials
var hp := PackedByteArray()     # hits taken per cell
var radius := 12.0              # bounding sphere (m)
var spin := Vector3.ZERO        # rad/s tumble
var ice := false
var solid_count := 0
var _mat: StandardMaterial3D = null

func setup(seed_v: int, size_cells: int, cell_m: float, is_ice: bool, treasure: Dictionary) -> void:
	n = size_cells
	cell = cell_m
	ice = is_ice
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 0.22
	var streak := FastNoiseLite.new()
	streak.seed = seed_v + 7
	streak.frequency = 0.35
	var axes := Vector3(rng.randf_range(0.75, 1.0), rng.randf_range(0.6, 0.95), rng.randf_range(0.75, 1.0))
	cells.resize(n * n * n)
	hp.resize(n * n * n)
	cells.fill(EMPTY)
	hp.fill(0)
	var half := (n - 1) * 0.5
	var core: Array = []
	for x in n:
		for y in n:
			for z in n:
				var q := Vector3((x - half) / (half + 0.5) / axes.x, (y - half) / (half + 0.5) / axes.y, (z - half) / (half + 0.5) / axes.z)
				var d := q.length() + noise.get_noise_3d(x, y, z) * 0.32
				if d >= 1.0: continue
				var m := ROCK
				if streak.get_noise_3d(x, y, z) > 0.32: m = OBSIDIAN
				cells[_i(x, y, z)] = m
				if d < 0.42: core.append(Vector3i(x, y, z))
	# treasure: a little cluster in the middle (never on the surface)
	for kind in [GOLD, DIAMOND]:
		var chance: float = float(treasure.get(NAMES[kind], 0.0))
		if core.is_empty() or rng.randf() >= chance: continue
		var c0: Vector3i = core[rng.randi() % core.size()]
		var want := rng.randi_range(2, 4) if kind == GOLD else rng.randi_range(1, 2)
		for c in core:
			if want <= 0: break
			if (c - c0).length() <= 1.8:
				cells[_i(c.x, c.y, c.z)] = kind
				want -= 1
	radius = half * cell * 1.8 + cell
	spin = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.02, 0.08)
	rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	remesh()

func _i(x: int, y: int, z: int) -> int: return (x * n + y) * n + z
func _in(x: int, y: int, z: int) -> bool: return x >= 0 and y >= 0 and z >= 0 and x < n and y < n and z < n
func at(c: Vector3i) -> int: return cells[_i(c.x, c.y, c.z)] if _in(c.x, c.y, c.z) else EMPTY

## Grid cell of a point in the asteroid's own space.
func cell_of_local(p: Vector3) -> Vector3i:
	var o := p / cell + Vector3.ONE * (n * 0.5)
	return Vector3i(floori(o.x), floori(o.y), floori(o.z))

## Centre of a cell, in the asteroid's own space.
func local_centre(c: Vector3i) -> Vector3:
	return (Vector3(c) + Vector3.ONE * 0.5 - Vector3.ONE * (n * 0.5)) * cell

func world_centre(c: Vector3i) -> Vector3: return global_transform * local_centre(c)

func color_of(m: int) -> Color:
	match m:
		ROCK: return Color(0.72, 0.8, 0.9) if ice else Color(0.46, 0.42, 0.4)
		OBSIDIAN: return Color(0.12, 0.08, 0.16)
		GOLD: return Data.VALUABLE_COLOR["gold"]
		DIAMOND: return Data.VALUABLE_COLOR["diamond"]
	return Color.WHITE

const _FACES := [
	[Vector3i(1, 0, 0), [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)]],
	[Vector3i(-1, 0, 0), [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)]],
	[Vector3i(0, 1, 0), [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)]],
	[Vector3i(0, -1, 0), [Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]],
	[Vector3i(0, 0, 1), [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)]],
	[Vector3i(0, 0, -1), [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)]],
]

## Rebuild the mesh: one quad per block side that faces open space, coloured by material (a little variation per
## block, darker edges so the blocks read).
func remesh() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var off := Vector3.ONE * (n * 0.5)
	solid_count = 0
	for x in n:
		for y in n:
			for z in n:
				var m := cells[_i(x, y, z)]
				if m == EMPTY: continue
				solid_count += 1
				var base := color_of(m)
				var h := absi(hash(Vector3i(x, y, z))) % 1000 / 1000.0
				base = base.darkened(h * 0.12) if m != GOLD and m != DIAMOND else base
				for f in _FACES:
					var dv: Vector3i = f[0]
					if at(Vector3i(x, y, z) + dv) != EMPTY: continue
					var k := verts.size()
					var nv := Vector3(dv)
					var shade := 1.0 if dv.y >= 0 else 0.82
					for corner: Vector3 in f[1]:
						verts.append((Vector3(x, y, z) + corner - off) * cell)
						norms.append(nv)
						cols.append(Color(base.r * shade, base.g * shade, base.b * shade))
					idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
	if verts.is_empty():
		mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.85
		_mat.metallic_specular = 0.35
	am.surface_set_material(0, _mat)
	mesh = am

func tick(dt: float) -> void:
	rotate_object_local(spin.normalized() if spin.length() > 0.0 else Vector3.UP, spin.length() * dt)

## First solid block on the segment a -> b (world): [cell, world point] or [] for none. Steps through the grid.
func ray(a: Vector3, b: Vector3) -> Array:
	var inv := global_transform.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var d := lb - la
	var length := d.length()
	if length < 0.001: return []
	var steps := int(ceil(length / (cell * 0.3))) + 1
	var last := Vector3i(-999, -999, -999)
	for s in steps + 1:
		var p := la + d * (float(s) / float(steps))
		var c := cell_of_local(p)
		if c == last: continue
		last = c
		if at(c) != EMPTY: return [c, global_transform * p]
	return []

## A point in the world is inside (or within pad metres of) a solid block: the push-out direction, else ZERO.
func push_out(p: Vector3, pad: float) -> Vector3:
	var lp := global_transform.affine_inverse() * p
	var c0 := cell_of_local(lp)
	var reach := int(ceil(pad / cell)) + 1
	var best := INF
	var bc := Vector3.ZERO
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			for z in range(-reach, reach + 1):
				var c := c0 + Vector3i(x, y, z)
				if at(c) == EMPTY: continue
				var lc := local_centre(c)
				var q := (lp - lc).clamp(-Vector3.ONE * cell * 0.5, Vector3.ONE * cell * 0.5) + lc   # nearest point on the block
				var dd := lp.distance_to(q)
				if dd < pad and dd < best:
					best = dd
					bc = lc if dd < 0.01 else q
	if best == INF: return Vector3.ZERO
	var away := lp - bc
	if away.length() < 0.01: away = lp.normalized() if lp.length() > 0.01 else Vector3.UP
	return (global_transform.basis * away).normalized() * (pad - best + 0.1)

## Break one block: returns its material name ("" = nothing there).
func break_cell(c: Vector3i) -> String:
	var m := at(c)
	if m == EMPTY: return ""
	cells[_i(c.x, c.y, c.z)] = EMPTY
	return NAMES[m]

## A hit on a block: it cracks and breaks after enough hits. Returns the broken material or "".
func hit_cell(c: Vector3i, power: int) -> String:
	var m := at(c)
	if m == EMPTY: return ""
	var i := _i(c.x, c.y, c.z)
	var need: int = int(Data.ASTEROID_HITS.get(NAMES[m], 2))
	var got := mini(255, int(hp[i]) + power)
	hp[i] = got
	if got < need: return ""
	hp[i] = 0
	return break_cell(c)

## Every solid block within r metres of a world point: [[cell, material]].
func cells_near(p: Vector3, r: float) -> Array:
	var lp := global_transform.affine_inverse() * p
	var c0 := cell_of_local(lp)
	var reach := int(ceil(r / cell))
	var out: Array = []
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			for z in range(-reach, reach + 1):
				var c := c0 + Vector3i(x, y, z)
				if at(c) == EMPTY: continue
				if local_centre(c).distance_to(lp) <= r: out.append([c, NAMES[at(c)]])
	return out

## A point just outside the surface, from the middle out along a world direction (tests and ramming).
func surface_point(dir: Vector3) -> Vector3:
	var o := global_position
	var hit := ray(o + dir.normalized() * radius * 1.2, o)
	return (hit[1] as Vector3) + dir.normalized() * 0.5 if not hit.is_empty() else o + dir.normalized() * radius

func count(m: int) -> int:
	var k := 0
	for v in cells:
		if v == m: k += 1
	return k
