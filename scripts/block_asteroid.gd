extends MeshInstance3D
## v1.8d (owner): asteroids break like the arcade game: a whole asteroid splits into 2 big pieces, each of those into 4,
## each of those into 4 more, and the smallest pieces are destroyed. Every piece can be shot; no loose bits are left.
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
var tier := 0                   # v1.8d: 0 = whole asteroid, 1 = half, 2 = quarter of that, 3 = smallest (destroyed next)
var health := 1.0               # damage left before it splits
var vel := Vector3.ZERO         # m/s drift (pieces fly apart; whole asteroids stay put)
var _mat: StandardMaterial3D = null
var seed_n := 0   # v13.260: its lumps (pieces keep their parent's)

func setup(seed_v: int, size_cells: int, cell_m: float, is_ice: bool, treasure: Dictionary) -> void:
	n = size_cells
	cell = cell_m
	ice = is_ice
	seed_n = seed_v
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

## v1.8d: a piece made from some of another piece's blocks ([[cell, material id]], in the parent's grid).
## Returns the centre of the new grid in the PARENT's own space (place the piece there).
func setup_from(list: Array, parent_n: int, cell_m: float, is_ice: bool, new_tier: int) -> Vector3:
	cell = cell_m
	ice = is_ice
	tier = new_tier
	var mn := Vector3i(9999, 9999, 9999)
	var mx := Vector3i(-9999, -9999, -9999)
	for e in list:
		var c: Vector3i = e[0]
		mn = Vector3i(mini(mn.x, c.x), mini(mn.y, c.y), mini(mn.z, c.z))
		mx = Vector3i(maxi(mx.x, c.x), maxi(mx.y, c.y), maxi(mx.z, c.z))
	var size := mx - mn + Vector3i.ONE
	n = maxi(1, maxi(size.x, maxi(size.y, size.z)))
	cells.resize(n * n * n)
	hp_cells_reset()
	cells.fill(EMPTY)
	for e in list:
		var c: Vector3i = (e[0] as Vector3i) - mn
		cells[_i(c.x, c.y, c.z)] = int(e[1])
	var half := (n - 1) * 0.5
	radius = maxf(cell, half * cell * 1.8 + cell)
	remesh()
	# where this grid's middle sits in the parent's space
	return (Vector3(mn) + Vector3.ONE * (n * 0.5) - Vector3.ONE * (parent_n * 0.5)) * cell

func hp_cells_reset() -> void:
	hp.resize(n * n * n)
	hp.fill(0)

## v1.8d: split the solid blocks into k groups (2 = halves across the longest side; 4 = quarters across the two longest).
func split_groups(k: int) -> Array:
	var list: Array = []
	for x in n:
		for y in n:
			for z in n:
				var m := cells[_i(x, y, z)]
				if m != EMPTY: list.append([Vector3i(x, y, z), m])
	if list.size() <= 1: return [list]
	var mn := Vector3(9999, 9999, 9999)
	var mx := Vector3(-9999, -9999, -9999)
	for e in list:
		var c := Vector3(e[0])
		mn = mn.min(c)
		mx = mx.max(c)
	var ext := mx - mn
	var axes := [0, 1, 2]
	axes.sort_custom(func(a, b): return ext[a] > ext[b])
	var mid := (mn + mx) * 0.5
	var groups: Array = []
	var count := 2 if k <= 2 else 4
	for g in count: groups.append([])
	for e in list:
		var c := Vector3(e[0])
		var gi := 1 if c[axes[0]] > mid[axes[0]] else 0
		if count == 4 and c[axes[1]] > mid[axes[1]]: gi += 2
		groups[gi].append(e)
	return groups.filter(func(gr): return not gr.is_empty())

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

## Rebuild the mesh: one quad per block side that faces open space, coloured by material.
## v13.260 (owner: "the asteroids need to not look so blocky, more like real asteroids, without adding topology"): the
## same quads, but their corners are shared and pulled toward their neighbours (rounded off like a subdivision cage),
## nudged in and out by noise, and shaded smooth with a rocky bump texture. The blocks underneath stay (shooting and
## mining hit them as before); only the look is a lumpy rock.
func remesh() -> void:
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var off := Vector3.ONE * (n * 0.5)
	var corner_id := {}   # grid corner -> vertex
	var pos: Array = []   # Vector3 (grid units)
	var col_sum: Array = []
	var nb: Array = []    # neighbour vertex ids
	var smooth := Data.ASTEROID_SMOOTH > 0
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
					var q: Array = []
					for corner: Vector3 in f[1]:
						var g := Vector3i(x, y, z) + Vector3i(corner)
						var key: Variant = g if smooth else Vector3i(pos.size(), 0, -1)   # (not smoothed: every quad its own corners)
						if not corner_id.has(key):
							corner_id[key] = pos.size()
							pos.append(Vector3(g) - off)
							col_sum.append(Color(0, 0, 0, 0))
							nb.append({})
						var vi: int = corner_id[key]
						q.append(vi)
						col_sum[vi] = (col_sum[vi] as Color) + Color(base.r, base.g, base.b, 1.0)
					for a in 4:
						(nb[q[a]] as Dictionary)[q[(a + 1) % 4]] = true
						(nb[q[a]] as Dictionary)[q[(a + 3) % 4]] = true
					idx.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
	if pos.is_empty():
		mesh = null
		return
	if smooth:
		for it in Data.ASTEROID_SMOOTH:   # rounded off: each corner moves part way to its neighbours' middle
			var nxt: Array = pos.duplicate()
			for vi in pos.size():
				var ks: Array = (nb[vi] as Dictionary).keys()
				if ks.is_empty(): continue
				var c := Vector3.ZERO
				for k in ks: c += pos[k]
				nxt[vi] = (pos[vi] as Vector3).lerp(c / ks.size(), Data.ASTEROID_SMOOTH_K)
			pos = nxt
	var verts := PackedVector3Array()
	verts.resize(pos.size())
	var nz := FastNoiseLite.new()
	nz.seed = int(seed_n)
	nz.frequency = 0.35
	var norms := PackedVector3Array()
	norms.resize(pos.size())
	for t in range(0, idx.size(), 3):   # smooth normals: each corner's faces averaged
		var a: Vector3 = pos[idx[t]]
		var fn := ((pos[idx[t + 1]] as Vector3) - a).cross((pos[idx[t + 2]] as Vector3) - a)
		for k in 3: norms[idx[t + k]] += fn
	for vi in pos.size():
		var nv := norms[vi].normalized() if norms[vi].length() > 0.0 else Vector3.UP
		norms[vi] = nv
		var p: Vector3 = pos[vi]
		if smooth: p += nv * nz.get_noise_3dv(p) * Data.ASTEROID_LUMPS   # lumps and dents (in blocks)
		verts[vi] = p * cell
		var cs: Color = col_sum[vi]
		cols.append(Color(cs.r / cs.a, cs.g / cs.a, cs.b / cs.a) if cs.a > 0.0 else Color.GRAY)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if _mat == null: _mat = rock_material(ice, cell)
	am.surface_set_material(0, _mat)
	mesh = am

## v13.260: a rock's skin: its colour (from the vertices) under a grainy rock pattern, and a bump texture for craters,
## cracks and grit, laid on from all three sides (no stretched seams). Shared by every rock of a size.
static var _rock_mats := {}
static func rock_material(is_ice: bool, scale_m: float) -> StandardMaterial3D:
	var key := "%s|%d" % [is_ice, int(scale_m)]
	if _rock_mats.has(key): return _rock_mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.4 if is_ice else 0.92
	m.metallic_specular = 0.3
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR   # pits and ridges, like craters
	fn.frequency = 0.03
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 14.0
	nt.noise = fn
	m.normal_enabled = true
	m.normal_texture = nt
	m.normal_scale = Data.ROCK_BUMP
	var fa := FastNoiseLite.new()
	fa.frequency = 0.035
	fa.fractal_octaves = 5
	var at := NoiseTexture2D.new()
	at.width = 256
	at.height = 256
	at.seamless = true
	at.noise = fa
	var gr := Gradient.new()   # grey grain, never black: the vertex colour still shows
	gr.set_color(0, Color(0.32, 0.3, 0.29))   # dark pits and seams ...
	gr.set_color(1, Color(1.12, 1.08, 1.02))   # ... to sunlit grit
	gr.add_point(0.55, Color(0.82, 0.79, 0.76))
	at.color_ramp = gr
	m.albedo_texture = at
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3.ONE / maxf(scale_m * Data.ROCK_PATTERN_M, 0.01)
	m.uv1_triplanar_sharpness = 2.0
	_rock_mats[key] = m
	return m

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
