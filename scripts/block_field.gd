class_name BlockField
extends Node3D

signal mined(at: Vector3, mat: String, weapon: String)   # v1.6c: a gold / diamond layer broke (the game drops the pieces)
## EXPERIMENT (branch planet-blocks-test): the owner's destructible ground, light version (docs/PLANET_BLOCKS.md).
## One test patch of a planet tile is built from BIG blocks instead of the smooth terrain sheet:
##   - columns on a grid of Data.BLOCK_BIG metres; the top of each follows the planet's own noise shape
##     (Surface.sample), snapped to Data.BLOCK_MIN steps, so the patch keeps the planet's hills and colours;
##   - step 1b (v1.5s): drawn as ONE fused surface: same-height neighbours share a face, walls only where it steps;
##   - step 2 (v1.5t): CRATERS. Every block inside a blast's radius is hit (Data.BLOCK_BLAST by weapon). A block only
##     partly inside splits into four (20 -> 10 -> 5 m), so a corner shot takes a corner and the rest stays whole.
##     Each 5 m layer needs Data.BLOCK_HITS light-gun hits by material (sand 1, dirt 2, stone 4, obsidian 8) and shows
##     damage (it darkens) until it breaks. Obsidian never splits into four: it chips, then breaks off whole, in half.
##     Each material breaks its own way (obsidian 2 pieces, stone 3, dirt 4, sand 5); about half of it flies out as
##     rubble (bigger pieces from the edge of the blast, smaller from the middle); obsidian cleaves again on a hard landing.
## Data: the field regrows from the planet seed every visit and only the blasts ("deltas") are kept and re-applied.
## The game has no save file yet, so the notes live for the session (GS.block_deltas); they are what a save will hold.

var planet_id := ""
var tile := 0
var region := Vector2i(-1, -1)   # v1.7a: which 500 m square of the tile ((-1, -1) = the old test patch)
var _sk := ""                  # the seed key: planet|tile (test patch) or planet|tile|rx|rz (a region)
var off := Vector2.ZERO         # v1.7d: where this field's own tile sits in the frame it is used in (a neighbour tile's
                               # region near the border is built shifted by a tile; its notes are kept in its own tile's frame)
var chunk: int = Data.BLOCK_CHUNK   # v1.7q: mesh chunk side in cells (regions use smaller ones: quicker to redraw)
var feat := 1.0                # how many landmarks / caves / pockets compared with the test patch (by area)
var center := Vector2.ZERO     # tile-local centre of the patch (x east, z south)
var cols := 0                  # big columns per side
var tops := PackedFloat32Array()   # the ORIGINAL top of each big column (row-major)
var blocks: Array = []         # the original stacks of big blocks: [{pos, size, col, depth}] (step 1 data)
var deltas: Array = []         # the blasts made by the player: [[x, y, z, kind]]; this is all that gets kept
var surf_cols := PackedColorArray()   # the ground's own colour per big column
const OFFS := [Vector2.ZERO, Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5),
	Vector2(0, -0.5), Vector2(0, 0.5), Vector2(-0.5, 0), Vector2(0.5, 0)]

# step 2: the ground as 5 m cells. Every cell belongs to one block (a square of 4, 2 or 1 cells, aligned).
var R := 4                     # cells per big block side
var n := 0                     # cells per patch side
var x0 := 0.0                  # tile-local west / north edge of the patch
var z0 := 0.0
var h := PackedFloat32Array()  # the ground now, per cell
var h0 := PackedFloat32Array() # the original ground, per cell
var lsz := PackedByteArray()   # the size (in cells) of the block each cell belongs to
var dmg := {}                  # hits taken per layer: block's first cell -> {layer: hits}
var holes := {}                # v1.5y: air pockets under a cell's top: cell -> [Vector2i(lo, hi)] layers, sorted
var y0 := 0.0                  # height of layer 0 (layers are BLOCK_MIN thick; below the depth floor is bedrock)
var collapses := 0             # pieces that lost their support and fell (tests)
var mats := {}                 # v1.5z: layers whose material is not the ground's own (rubble that settled, pieces that fell): cell -> {layer: material}
var fill := {}                 # v1.5z: rubble merged into a cell but not yet a whole layer: cell -> amount (layers)
var merged := 0                # rubble pieces that merged into the ground (tests)
var fluid := {}                # v1.6b water and lava: cell -> {layer: "water" | "lava"} (they fill air layers)
var pockets: Array = []        # the sealed pockets placed from the seed: [{cells: [cell], k0, kind}]
var veins: Array = []          # v1.6c gold / diamond veins from the seed: [{mat, cells: [Vector2i(cell, layer)]}]
var caves: Array = []          # v1.6d cave pockets from the seed: [{centre: Vector3, cells: int}]
var killed := 0                # things the kill floor took (tests)
var clamped := 0               # v1.6f spires cut down to a realistic height (tests)
var canyon_cells: Array = []   # v1.6f the canyon floor's cells
var roots: Array = []          # v1.6f obsidian roots piercing the surface: [{cells: [cell], tip}]
var halls: Array = []          # v1.6h deep root halls: [{x, z, w, k0, k1, trunks: [cell], lava: int}]
var trees: Array = []          # v1.7i alien trees: [{base: cell, wood: int, leaf: int, cave_root: bool, trunk: [cells], k_top}]
var burning := {}              # v1.7i fire: Vector2i(cell, layer) -> seconds burning
var burned := 0                # layers fire took (tests)
var falls: Array = []          # v1.7l waterfalls: [{lip: [cells], lip_h, foot: [cells], foot_h, top: Vector3, bottom: Vector3, dir: Vector2, on}]
var placed: Array = []         # v1.7k molds from the library (models made into molds): [{name, centre, k0, cells}]
var links: Array = []          # v1.7j winding tunnels: [{from: cell, to: [cell, k], path: [[cell, k]]}]
var molds: Array = []          # v1.7h stamped mold shapes: [{kind, centre, k0, rooms, entrance, route}]
var slabs: Array = []          # v1.7f leaning slabs and A-frames: [{cells, lo: {cell: y}, kind, mat, geo: [pieces], whole}]
var _slab_of := {}             # cell -> index in slabs
var arches: Array = []         # v1.6e generated arches: [{legs: [[cells], [cells]], span: [cells], mid: cell, mat}]
var overhangs: Array = []      # v1.6e Pride Rock promontories: [{base: [cells], jut: [cells], tip: cell}]
var reach_bonus := {}          # v1.6e cell -> how far (cells) its rock may hang from support (arches, promontories)
var _kill_st: SurfaceTool
var _kill_any := false
var fluid_moves := 0           # (tests)
var reactions := 0             # (tests)
var _fluid_t := 0.0
var _fluid_tick := 0
var _fluid_dirty := false
var _fluid_mi := {}            # "water" / "lava" -> MeshInstance3D
var ccol := PackedColorArray() # the ground colour at each cell corner ((n + 1)^2), so the surface blends
var hmax := -INF               # the highest top in the patch (quick miss test for shots)
var base := Color.GRAY         # the planet's ground colour here: the tones are made from it
var layers_broken := 0         # 5 m layers broken since the patch was built (tests)
var splits := 0                # blocks split into four (tests)
var thrown := 0                # rubble pieces thrown (tests)
var cleaved := 0               # obsidian pieces that split in half on landing (tests)
var rubble: Array = []         # flying / landed pieces: [{node, vel, spin, rest, half}]
var _noise: FastNoiseLite
var _chunks := {}              # chunk index -> MeshInstance3D
var _dirty := {}
var _tones := {}
var _mats := {}
var _box: BoxMesh
static var _ground_mat: ShaderMaterial   # (one for every field: it compiles once)
var _rng := RandomNumberGenerator.new()

const MoldLibrary := preload("res://scripts/mold_library.gd")   # v1.7k: models made into molds
static var force := false   # tests switch it on
static var _url_on := -1

## v1.7b: block ground is ON for everyone (the whole planet, region by region). On the web, ?noblocks in the address
## turns it off (the old smooth ground) in case a phone struggles; the route test's old patch uses `force`.
static func enabled() -> bool:
	if force: return true
	if _url_on < 0:
		_url_on = 1
		if OS.has_feature("web"):
			_url_on = 0 if str(JavaScriptBridge.eval("window.location.search || ''", true)).find("noblocks") >= 0 else 1
	return _url_on == 1

static var regions_test := false   # tests: the region mode with `force`

## The old 800 m test patch: only for the route test now (with ?blocks the whole planet is blocks, region by region).
static func wanted(pid: String, t: int) -> bool:
	return force and not regions_test and Data.BLOCK_TEST.get("planet", "") == pid and int(Data.BLOCK_TEST.get("tile", -1)) == t

## v1.7a: blocks everywhere, built in 500 m regions round the player (the ?blocks link, or the region test).
static func regions_on() -> bool:
	return regions_test or (enabled() and not force)

static func region_key(pid: String, t: int, r: Vector2i) -> String:
	return "%s|%d|%d|%d" % [pid, t, r.x, r.y]

## The region a tile-local point is in (clamped to the tile).
static func region_of(x: float, z: float) -> Vector2i:
	var nr := int(round(Surface.TILE / Data.BLOCK_REGION))
	return Vector2i(clampi(int(floor((x + Surface.EDGE) / Data.BLOCK_REGION)), 0, nr - 1), clampi(int(floor((z + Surface.EDGE) / Data.BLOCK_REGION)), 0, nr - 1))

static func region_centre(r: Vector2i) -> Vector2:
	return Vector2(-Surface.EDGE + (r.x + 0.5) * Data.BLOCK_REGION, -Surface.EDGE + (r.y + 0.5) * Data.BLOCK_REGION)

## How many of something the seed places here: the test patch gets the full count, a region its share (the leftover
## fraction is a chance of one more).
func _scaled(count: int, rng: RandomNumberGenerator) -> int:
	if feat >= 0.999: return count
	var e := count * feat
	return int(e) + (1 if rng.randf() < e - int(e) else 0)

static func key_of(pid: String, t: int) -> String:
	return "%s|%d" % [pid, t]

@warning_ignore("integer_division")
var built := false   # v1.7a: a region built a little each frame is only used once this is true
var cancel := false  # ...and stops (and frees itself) if this is set while it builds

## Build from the seed. `staged` (v1.7a regions): spread over many frames so flying never stalls (each step is
## a few rows, one feature or one mesh chunk); `built` goes true at the end.
static var step_max_ms := 0.0   # v1.7q: the longest single slice of a staged build so far (tests: no long stalls)
var _step_t0 := 0
func _slice_end() -> void:
	var d := (Time.get_ticks_usec() - _step_t0) / 1000.0
	step_max_ms = maxf(step_max_ms, d)

func build(pid: String, t: int, reg := Vector2i(-1, -1), staged := false, frame := Vector2.ZERO) -> void:
	_step_t0 = Time.get_ticks_usec()
	planet_id = pid
	tile = t
	region = reg
	var big: float = Data.BLOCK_BIG
	var step: float = Data.BLOCK_MIN
	if reg.x < 0:
		name = "BlockField"
		_sk = key_of(pid, t)
		center = Data.BLOCK_TEST["center"]
		cols = int(round(float(Data.BLOCK_TEST["size"]) / big))
	else:
		name = "BlockField_%d_%d" % [reg.x, reg.y]
		_sk = region_key(pid, t, reg)
		center = region_centre(reg) + frame
		off = frame
		cols = int(round(Data.BLOCK_REGION / big))
		feat = Data.BLOCK_REGION_FEATURES
		chunk = Data.BLOCK_CHUNK_REGION
	tops.resize(cols * cols)
	var g := Surface.grid(pid)
	var ox := float(t % g) * Surface.TILE - off.x   # (planet metres of this frame's origin)
	var oz := float(t / g) * Surface.TILE - off.y
	_pox = ox
	_poz = oz
	_slant_noise = FastNoiseLite.new()
	_slant_noise.seed = hash(pid + "|slant")   # (one field for the whole planet, so patches run on across regions)
	_slant_noise.frequency = Data.BLOCK_SLANT_FREQ
	var cols_c: Array = []
	cols_c.resize(cols * cols)
	surf_cols.resize(cols * cols)
	# 1. column tops: the highest ground under the column (so the smooth sheet never pokes through), snapped up a step
	for j in cols:
		if staged and j % 4 == 3:
			_slice_end()
			await Engine.get_main_loop().process_frame
			_step_t0 = Time.get_ticks_usec()
			if cancel:
				queue_free()
				return
		for i in cols:
			var c := _col_centre(i, j)
			var hm := -1e9
			var colr := Color.GRAY
			for k in OFFS.size():
				var o: Vector2 = OFFS[k] * big
				var smp: Array = Surface.sample(pid, ox + c.x + o.x, oz + c.y + o.y)
				hm = maxf(hm, float(smp[0]))
				if k == 0: colr = smp[1]
			tops[j * cols + i] = ceilf((hm + Data.BLOCK_MARGIN) / step) * step
			surf_cols[j * cols + i] = Color(colr.r, colr.g, colr.b)
			cols_c[j * cols + i] = colr
	# 1a. (v1.7g) blocks of many sizes: neighbouring columns on even ground join into one long or big block (one top),
	#     and some big ones stand a step or two proud, so the ground is long rectangles and solid cubes, not one grid
	if reg.x >= 0: _join_columns()
	# 1b. realistic heights (v1.6f): no thin spires. A column standing more than SPIRE_MAX over every neighbour is cut
	#     down to that (the edge columns are left alone: the smooth sheet there isn't sunk)
	for pass_i in 2:
		for j in range(2, cols - 2):
			for i in range(2, cols - 2):
				var mx := -INF
				for dj in [-1, 0, 1]:
					for di in [-1, 0, 1]:
						if di != 0 or dj != 0: mx = maxf(mx, tops[(j + dj) * cols + i + di])
				if tops[j * cols + i] > mx + Data.SPIRE_MAX:
					tops[j * cols + i] = ceilf((mx + Data.SPIRE_MAX) / step) * step
					clamped += 1
	# 2. the original stacks of big blocks (each column from below its lowest neighbour up to its top)
	_rng.seed = hash(_sk + "|blocks")
	for j in cols:
		for i in cols:
			var top: float = tops[j * cols + i]
			var low := top
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				low = minf(low, tops[nj * cols + ni] if ni >= 0 and nj >= 0 and ni < cols and nj < cols else top - Data.BLOCK_SKIRT)
			var bottom := low - big
			var c2 := _col_centre(i, j)
			var y := top
			var depth := 0
			while y > bottom + 0.01:
				var hh := minf(big, y - bottom)
				blocks.append({"pos": Vector3(c2.x, y - hh * 0.5, c2.y), "size": Vector3(big, hh, big), "col": cols_c[j * cols + i], "depth": depth})
				y -= hh
				depth += 1
	# 3. the 5 m cells (step 2)
	R = maxi(1, int(round(big / step)))
	n = cols * R
	x0 = center.x - cols * big * 0.5
	z0 = center.y - cols * big * 0.5
	h.resize(n * n)
	lsz.resize(n * n)
	lsz.fill(R)
	for fz in n:
		for fx in n:
			h[fz * n + fx] = tops[(fz / R) * cols + fx / R]
	h0 = h.duplicate()
	var hmin := INF
	for v in tops:
		hmax = maxf(hmax, v)
		hmin = minf(hmin, v)
	y0 = floorf((hmin - Data.BLOCK_DEPTH_FLOOR) / step) * step - step * 2.0
	var cc := PackedColorArray()   # colours at the big columns' corners, then blended down to every cell corner
	cc.resize((cols + 1) * (cols + 1))
	var sum := Color(0, 0, 0)
	for v in surf_cols: sum += v
	base = sum / maxf(1.0, surf_cols.size())
	for cj in cols + 1:
		for ci in cols + 1:
			var acc := Color(0, 0, 0)
			var nn := 0
			for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var i2: int = ci + d.x
				var j2: int = cj + d.y
				if i2 >= 0 and j2 >= 0 and i2 < cols and j2 < cols:
					acc += surf_cols[j2 * cols + i2]
					nn += 1
			cc[cj * (cols + 1) + ci] = acc / maxf(1.0, nn)
	ccol.resize((n + 1) * (n + 1))
	for fz in n + 1:
		for fx in n + 1:
			var u := float(fx) / R
			var w := float(fz) / R
			var i0 := mini(int(u), cols - 1)
			var j0 := mini(int(w), cols - 1)
			var tu := u - i0
			var tw := w - j0
			var top_c := cc[j0 * (cols + 1) + i0].lerp(cc[j0 * (cols + 1) + i0 + 1], tu)
			var bot_c := cc[(j0 + 1) * (cols + 1) + i0].lerp(cc[(j0 + 1) * (cols + 1) + i0 + 1], tu)
			ccol[fz * (n + 1) + fx] = top_c.lerp(bot_c, tw)
	_gen = staged   # (v1.7q: in a staged region build, one support check at the end instead of one per feature)
	_gen_box = Rect2i()
	_noise = FastNoiseLite.new()
	_noise.seed = hash(_sk + "|layers")
	_noise.frequency = 0.03
	# 4. caves, sealed water and lava pockets, gold and diamond veins, from the seed (v1.6b-d)
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	_carve_canyon()
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	_carve_root_halls()
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	_carve_caves()
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	if region.x >= 0 and _carve_cave_mold():   # (v1.7h cave, v1.7j tunnels out to the caves near it)
		if staged:
			_slice_end()
			await Engine.get_main_loop().process_frame
			_step_t0 = Time.get_ticks_usec()
			if cancel:
				queue_free()
				return
		_carve_links()
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	_build_landmarks()
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	if region.x >= 0: _build_slabs()   # (v1.7f; the old test patch keeps its ground as the tests know it)
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	if region.x >= 0: _place_library()   # (v1.7k: shapes made from models, scripts/mold_library.gd)
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	if region.x >= 0: _grow_trees()   # (v1.7i: after the cave, so a root can grow into it)
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	if region.x >= 0: _place_falls()   # (v1.7l)
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	_raise_roots()
	if staged:
		_slice_end()
		await Engine.get_main_loop().process_frame
		_step_t0 = Time.get_ticks_usec()
		if cancel:
			queue_free()
			return
	if _gen:
		_gen = false
		if _gen_box.size != Vector2i.ZERO:
			_slice_end()
			await Engine.get_main_loop().process_frame
			_step_t0 = Time.get_ticks_usec()
			if cancel:
				queue_free()
				return
			_settle(_gen_box.position.x, _gen_box.end.x - 1, _gen_box.position.y, _gen_box.end.y - 1)
			collapses = 0
	_place_pockets()
	_place_veins()
	_slab_expect()
	# 5. re-apply the blasts made here before (seed + deltas), quietly
	var key := _sk
	if not GS.block_deltas.has(key): GS.block_deltas[key] = []
	deltas = GS.block_deltas[key]
	for d in deltas: _apply_note(d)
	for pk in pockets:   # a pocket that was opened before has already poured out (its effects are in the notes)
		if _pocket_open(pk):
			for c in pk["cells"]: fluid.erase(c)
	_fluid_dirty = true
	layers_broken = 0
	splits = 0
	collapses = 0
	_mat_ok = true
	var nc := _nchunks()
	for k in nc * nc: _dirty[k] = true
	if staged:
		while not _dirty.is_empty():
			_slice_end()
			await Engine.get_main_loop().process_frame
			_step_t0 = Time.get_ticks_usec()
			if cancel:
				queue_free()
				return
			flush(1)
	flush()
	built = true

var joined := 0   # columns joined into bigger blocks (tests)
@warning_ignore("integer_division")
func _join_columns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|shapes")
	var step: float = Data.BLOCK_MIN
	var used := {}
	var total_w := 0
	for sh in Data.BLOCK_SHAPES: total_w += int(sh[2])
	var order: Array = range(cols * cols)
	for k in range(order.size() - 1, 0, -1):   # (seeded shuffle)
		var r := rng.randi_range(0, k)
		var t: int = order[k]
		order[k] = order[r]
		order[r] = t
	for idx in order:
		var i: int = idx % cols
		var j: int = idx / cols
		if used.has(idx): continue
		var pick := rng.randi_range(0, total_w - 1)
		var w := 1
		var d := 1
		for sh in Data.BLOCK_SHAPES:
			pick -= int(sh[2])
			if pick < 0:
				w = int(sh[0])
				d = int(sh[1])
				break
		if i + w > cols or j + d > cols:
			w = 1
			d = 1
		var cells: Array = []
		var hmin := INF
		var hmx := -INF
		for dj in d:
			for di in w:
				var q := (j + dj) * cols + i + di
				if used.has(q):
					cells.clear()
					break
				cells.append(q)
				hmin = minf(hmin, tops[q])
				hmx = maxf(hmx, tops[q])
			if cells.is_empty(): break
		if cells.is_empty() or hmx - hmin > Data.BLOCK_SHAPE_EVEN:
			used[idx] = true
			continue
		var top := hmx
		if cells.size() >= 4 and rng.randf() < Data.BLOCK_BIG_RISE: top += step * rng.randi_range(1, 2)
		for q in cells:
			tops[q] = top
			used[q] = true
		if cells.size() > 1: joined += cells.size()

func _col_centre(i: int, j: int) -> Vector2:
	var big: float = Data.BLOCK_BIG
	return center + Vector2((i + 0.5) * big - cols * big * 0.5, (j + 0.5) * big - cols * big * 0.5)

# ---------------------------------------------------------------- materials
## What a 5 m layer is made of: its top at height y in cell (fx, fz). Layered by depth under the original ground:
## a skin of sand and dirt, dirt and stone under it, then stone with obsidian growing more common the deeper you go
## (and a few sand pockets in the rock). Fixed by the planet seed, so it is the same every visit.
var force_mat := ""   # tests only: every layer reads as this material

func mat_at(fx: int, fz: int, y: float) -> String:
	if force_mat != "": return force_mat
	var ov: Dictionary = mats.get(fz * n + fx, {})
	if not ov.is_empty():
		var kk := _k(y - Data.BLOCK_MIN * 0.5)
		if ov.has(kk): return ov[kk]
	var d: float = h0[fz * n + fx] - y
	# v1.7q: the natural material of a layer never changes once the region is built: remembered (one byte a layer)
	var slot := -1
	if _mat_ok and d >= 0.0 and d < MAT_DEPTH * Data.BLOCK_MIN:
		if _mat_mem.is_empty(): _mat_mem.resize(n * n * MAT_DEPTH)
		slot = (fz * n + fx) * MAT_DEPTH + int(d / Data.BLOCK_MIN)
		var mm: int = _mat_mem[slot]
		if mm > 0: return MAT_NAMES[mm]
	var res := _mat_natural(fx, fz, y, d)
	if slot >= 0: _mat_mem[slot] = MAT_NAMES.find(res)
	return res

const MAT_NAMES := ["", "sand", "dirt", "stone", "obsidian"]
const MAT_DEPTH := 44
var _mat_mem := PackedByteArray()
var _mat_ok := false   # (set once the region is generated: h0 no longer changes)

func _mat_natural(fx: int, fz: int, y: float, d: float) -> String:
	if Data.BLOCK_DEPTH_FLOOR - d < Data.KILL_CAP + 0.01: return "obsidian"   # v1.6d: the obsidian cap over the kill floor
	var step: float = Data.BLOCK_MIN
	var wx := x0 + (fx + 0.5) * step
	var wz := z0 + (fz + 0.5) * step
	var a := _noise.get_noise_3d(wx, y * 1.6, wz)
	if d < step * 0.5: return "sand" if a > 0.3 else "dirt"
	if d < step * 2.5: return "dirt" if a > -0.15 else "stone"
	var ob := _noise.get_noise_3d(wz + 917.0, y * 2.0, wx - 433.0)
	if ob > lerpf(0.55, 0.05, clampf((d - 15.0) / 160.0, 0.0, 1.0)): return "obsidian"
	if d < 90.0 and a > 0.62: return "sand"
	return "stone"

## The tone of a material, made from this planet's own ground colour: lighter = softer, darker = tougher.
func tone(m: String) -> Color:
	if Data.VALUABLE_COLOR.has(m): return Data.VALUABLE_COLOR[m]   # treasure keeps its own bright colour on any world
	if _tones.has(m): return _tones[m]
	var tn: Array = Data.BLOCK_TONES.get(m, [0.0, 1.0])
	var gl := (base.r + base.g + base.b) / 3.0
	var c := Color(gl, gl, gl).lerp(base, float(tn[1]))
	if m == "dirt": c = Data.DIRT_BROWN.lerp(base, Data.DIRT_PLANET)   # (v1.7g: earthy brown under the grass)
	if m == "wood": c = Data.WOOD_COLOR
	if Data.LEAF_COLORS.has(m): c = Data.LEAF_COLORS[m]
	var k := float(tn[0])
	c = c.lerp(Color.WHITE, k) if k > 0.0 else c.lerp(Color.BLACK, -k)
	_tones[m] = c
	return c

# ---------------------------------------------------------------- craters
## A blast at tile-local point p by a weapon kind (Data.BLOCK_BLAST: gun, missile, heavy, special, thrust...).
## Every 5 m layer of every block inside the sphere takes the weapon's hits; a layer breaks when its material's count
## is reached. A blast from above digs a crater; one against a wall digs INTO it (v1.5y: tunnels, overhangs). Then
## anything that lost its support falls (_settle). Returns {broken, chipped, mat}.
@warning_ignore("integer_division")
func blast(p: Vector3, kind: String, record := true, effects := true) -> Dictionary:
	var spec: Array = Data.BLOCK_BLAST.get(kind, Data.BLOCK_BLAST["gun"])
	var r: float = spec[0]
	var power: int = spec[1]
	var step: float = Data.BLOCK_MIN
	var res := {"broken": 0, "chipped": 0, "mat": ""}
	if p.x + r < x0 or p.z + r < z0 or p.x - r > x0 + n * step or p.z - r > z0 + n * step: return res
	if record:
		deltas.append([snappedf(p.x - off.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z - off.y, 0.01), kind])
		if deltas.size() > Data.BLOCK_DELTAS_MAX: deltas.remove_at(0)
	var fx0 := clampi(floori((p.x - r - x0) / step), 0, n - 1)
	var fx1 := clampi(floori((p.x + r - x0) / step), 0, n - 1)
	var fz0 := clampi(floori((p.z - r - z0) / step), 0, n - 1)
	var fz1 := clampi(floori((p.z + r - z0) / step), 0, n - 1)
	var queue: Array = []
	var seen := {}
	for fz in range(fz0, fz1 + 1):
		for fx in range(fx0, fx1 + 1):
			var s: int = lsz[fz * n + fx]
			var bx := fx - fx % s
			var bz := fz - fz % s
			if seen.has(bz * n + bx): continue
			seen[bz * n + bx] = true
			queue.append(Vector3i(bx, bz, s))
	var out: Array = []
	while not queue.is_empty():
		var q: Vector3i = queue.pop_back()
		var ox := q.x
		var oz := q.y
		var s := q.z
		var rx0 := x0 + ox * step
		var rz0 := z0 + oz * step
		var rx1 := rx0 + s * step
		var rz1 := rz0 + s * step
		var dmin := Vector2(p.x - clampf(p.x, rx0, rx1), p.z - clampf(p.z, rz0, rz1)).length()
		if dmin >= r: continue
		var dmax := Vector2(maxf(absf(p.x - rx0), absf(p.x - rx1)), maxf(absf(p.z - rz0), absf(p.z - rz1))).length()
		var i0 := oz * n + ox
		var v := sqrt(r * r - dmin * dmin)
		var kt := _ktop(i0)
		var kf := _kfloor(i0)
		var klo := maxi(_k(p.y - v + 0.01), kf)
		var khi := mini(_k(p.y + v - 0.01), kt - 1)
		if khi < klo: continue   # the sphere doesn't reach any breakable layer of this block
		var ktop_hit := -1
		for k in range(khi, klo - 1, -1):
			if _solid_k(i0, k):
				ktop_hit = k
				break
		if ktop_hit < 0: continue   # only air (a hole) in reach
		var cfx := ox + s / 2
		var cfz := oz + s / 2
		var m := mat_at(cfx, cfz, _ly(ktop_hit))
		var partial: bool = dmax > r and m != "obsidian"
		var holing: bool = khi < kt - 1   # the top isn't in reach: this digs a hole under it
		if s > 1 and (partial or holing):
			# split into four (or straight down to single cells when it digs in under the top)
			var hs := 1 if holing and not partial else s / 2
			var d0: Dictionary = dmg.get(i0, {})
			dmg.erase(i0)
			for jz in range(0, s, hs):
				for jx in range(0, s, hs):
					var sx: int = ox + jx
					var sz: int = oz + jz
					for yz in hs:
						for yx in hs: lsz[(sz + yz) * n + sx + yx] = hs
					if not d0.is_empty(): dmg[sz * n + sx] = d0.duplicate()
					queue.append(Vector3i(sx, sz, hs))
			splits += 1
			_mark(ox, oz, s)
			continue
		var dl: Dictionary = dmg.get(i0, {})
		var broke := 0
		for k in range(khi, klo - 1, -1):
			if not _solid_k(i0, k): continue
			m = mat_at(cfx, cfz, _ly(k))
			var need: int = Data.BLOCK_HITS.get(m, 1)
			var hits: int = int(dl.get(k, 0)) + power
			if hits < need:
				dl[k] = hits
				continue
			dl.erase(k)
			for jz in s:
				for jx in s: _cell_remove((oz + jz) * n + ox + jx, k)
			out.append({"pos": Vector3((rx0 + rx1) * 0.5, _ly(k) - step * 0.5, (rz0 + rz1) * 0.5), "size": s * step, "mat": m, "edge": dmin / r})
			if effects and Data.VALUABLE_COLOR.has(m): mined.emit(Vector3((rx0 + rx1) * 0.5, _ly(k) - step * 0.5, (rz0 + rz1) * 0.5), m, kind)
			broke += 1
		if broke == 0: res["chipped"] = int(res["chipped"]) + 1
		# damage on layers that are gone is dropped
		for k in dl.keys():
			if not _solid_k(i0, int(k)): dl.erase(k)
		if dl.is_empty(): dmg.erase(i0)
		else: dmg[i0] = dl
		_mark(ox, oz, s)
	layers_broken += out.size()
	res["broken"] = out.size()
	if effects and kind != "thrust" and kind != "thrust_soft":   # v1.7i: shots set wood and leaves alight (round the crater too)
		var rf := r + Data.BLOCK_MIN * 1.5
		var kl := _k(p.y - rf)
		var kh := _k(p.y + rf)
		for fz in range(maxi(0, fz0 - 2), mini(n - 1, fz1 + 2) + 1):
			for fx in range(maxi(0, fx0 - 2), mini(n - 1, fx1 + 2) + 1):
				var c := fz * n + fx
				for k in range(kl, kh + 1):
					if not _solid_k(c, k): continue
					if _layer_point(c, k).distance_to(p) > rf: continue
					var mm := mat_at(fx, fz, _ly(k))
					if mm != "wood" and not Data.LEAF_COLORS.has(mm): continue
					if kind != "gun" or _rng.randf() < Data.FIRE_GUN_CHANCE: ignite(c, k)
	if not out.is_empty():
		res["mat"] = out[0]["mat"]
		var fell := _settle(fx0 - 6, fx1 + 6, fz0 - 6, fz1 + 6)
		if effects:
			var flew := _throw(p, r, out)
			for f in fell.slice(0, clampi(Data.BLOCK_RUBBLE_PER_BLAST - flew, 0, 4)): _piece(f["pos"], minf(float(f["size"]), 8.0) * 0.6, str(f["mat"]), Vector3(_rng.randf_range(-3, 3), -4.0, _rng.randf_range(-3, 3)))
	return res

# ---------------------------------------------------------------- layers, holes and support (v1.5y)
## Layer k covers heights [y0 + k * BLOCK_MIN, y0 + (k + 1) * BLOCK_MIN); _ly(k) is its TOP.
func _k(y: float) -> int:
	return floori((y - y0) / Data.BLOCK_MIN + 0.0001)

func _ly(k: int) -> float:
	return y0 + (k + 1) * Data.BLOCK_MIN

func _ktop(i: int) -> int:   # layers [.., ktop) can be solid
	return int(round((h[i] - y0) / Data.BLOCK_MIN))

func _kfloor(i: int) -> int:   # below this is bedrock (nothing digs deeper than BLOCK_DEPTH_FLOOR)
	return int(round((h0[i] - Data.BLOCK_DEPTH_FLOOR - y0) / Data.BLOCK_MIN))

func _solid_k(i: int, k: int) -> bool:
	if k >= _ktop(i): return false
	for hv in holes.get(i, []):
		if k >= hv.x and k < hv.y: return false
	return true

## Break layer k of cell i: the top layer lowers the ground (and opens any hole right under it to the sky); a lower
## layer becomes a hole (air) under solid ground: a tunnel or a cave.
func _cell_remove(i: int, k: int) -> void:
	var kt := _ktop(i)
	if k >= kt: return
	if mats.has(i):
		(mats[i] as Dictionary).erase(k)
		if (mats[i] as Dictionary).is_empty(): mats.erase(i)
	var hl: Array = holes.get(i, [])
	if k == kt - 1:
		kt -= 1
		while not hl.is_empty() and (hl[-1] as Vector2i).y >= kt:
			kt = mini(kt, (hl[-1] as Vector2i).x)
			hl.pop_back()
		h[i] = y0 + kt * Data.BLOCK_MIN
	else:
		var lo := k
		var hi := k + 1
		var keep: Array = []
		for hv in hl:
			var e: Vector2i = hv
			if e.y < lo or e.x > hi: keep.append(e)
			else:
				lo = mini(lo, e.x)
				hi = maxi(hi, e.y)
		keep.append(Vector2i(lo, hi))
		keep.sort_custom(func(a, b): return a.x < b.x)
		hl = keep
	if hl.is_empty(): holes.erase(i)
	else: holes[i] = hl

## The solid runs of a cell, bottom up: [Vector2i(lo, hi)]; the first rests on bedrock (lo = -1000).
func spans(i: int) -> Array:
	var out: Array = []
	var start := -1000
	for hv in holes.get(i, []):
		out.append(Vector2i(start, (hv as Vector2i).x))
		start = (hv as Vector2i).y
	out.append(Vector2i(start, _ktop(i)))
	return out

func _set_spans(i: int, sp: Array) -> void:
	var hl: Array = []
	for j in range(1, sp.size()):
		hl.append(Vector2i((sp[j - 1] as Vector2i).y, (sp[j] as Vector2i).x))
	h[i] = y0 + (sp[-1] as Vector2i).y * Data.BLOCK_MIN
	if hl.is_empty(): holes.erase(i)
	else: holes[i] = hl

## Support (step 5): a piece floating over a hole stays up only if it is joined sideways to grounded ground within its
## material's reach (Data.BLOCK_REACH, in 5 m cells: sand 0, dirt 1, stone 3, obsidian 5). Otherwise it falls and lands
## on what is under it. Checked around the blast, again and again until nothing more falls. Returns what fell.
var _gen := false          # v1.7q: generating a region: the support checks wait and run once at the end
var _gen_box := Rect2i()
func _settle(cx0: int, cx1: int, cz0: int, cz1: int) -> Array:
	if _gen:
		var b := Rect2i(cx0, cz0, cx1 - cx0 + 1, cz1 - cz0 + 1)
		_gen_box = b if _gen_box.size == Vector2i.ZERO else _gen_box.merge(b)
		return []
	return _settle_body(cx0, cx1, cz0, cz1)

func _settle_body(cx0: int, cx1: int, cz0: int, cz1: int) -> Array:
	var fell: Array = []
	cx0 = clampi(cx0, 0, n - 1)
	cx1 = clampi(cx1, 0, n - 1)
	cz0 = clampi(cz0, 0, n - 1)
	cz1 = clampi(cz1, 0, n - 1)
	for pass_i in 12:
		var changed := false
		var cells: Array = holes.keys()
		cells.sort()
		var dist := _ground_dist()   # v1.7q: every hanging piece's distance to grounded rock, worked out once per pass
		for ci in cells:
			var i: int = ci
			var fx := i % n
			var fz := i / n
			if fx < cx0 or fx > cx1 or fz < cz0 or fz > cz1 or not holes.has(i): continue
			var sp: Array = spans(i)
			var j := 1
			var cut := false
			while j < sp.size():
				var spj: Vector2i = sp[j]
				var reach: int = maxi(Data.BLOCK_REACH.get(mat_at(fx, fz, _ly(spj.x)), 1), int(reach_bonus.get(i, 0)))
				if int(dist.get(Vector3i(fx, fz, spj.x), 999)) <= reach:
					j += 1
					continue
				var a: Vector2i = sp[j - 1]
				var b: Vector2i = sp[j]
				fell.append({"pos": Vector3(x0 + (fx + 0.5) * Data.BLOCK_MIN, _ly(b.x), z0 + (fz + 0.5) * Data.BLOCK_MIN), "size": Data.BLOCK_MIN, "mat": mat_at(fx, fz, _ly(b.x))})
				# v1.5z: it keeps its own material where it lands
				var moved := {}
				for k in range(b.x, b.y): moved[a.y + (k - b.x)] = mat_at(fx, fz, _ly(k))
				var ov: Dictionary = mats.get(i, {})
				for k in range(a.y, b.y): ov.erase(k)
				for k in moved: ov[k] = moved[k]
				mats[i] = ov
				sp[j - 1] = Vector2i(a.x, a.y + (b.y - b.x))   # it drops and lands on what was under the hole
				sp.remove_at(j)
				collapses += 1
				changed = true
				cut = true
			if cut:
				_set_spans(i, sp)
				dmg.erase(i)
				_mark(fx, fz, 1)
		if not changed: break
	return fell

## v1.7q: how far (in side-by-side steps) every hanging piece of rock is from rock that stands on the bottom: one sweep
## out from the grounded rock over all the pieces (the same answer _held finds one piece at a time, far cheaper).
## Key Vector3i(x, z, the piece's lowest layer) -> steps; pieces further than the longest reach are left out.
@warning_ignore("integer_division")
func _ground_dist() -> Dictionary:
	var maxd := 13
	for v in reach_bonus.values(): maxd = maxi(maxd, int(v) + 1)
	var sp_of := {}
	for c in holes: sp_of[c] = spans(int(c))
	var dist := {}
	var frontier: Array = []   # [cell, span]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for c in sp_of:
		var fx: int = int(c) % n
		var fz: int = int(c) / n
		var sp: Array = sp_of[c]
		for jj in range(1, sp.size()):
			var o: Vector2i = sp[jj]
			for d in dirs:
				var nx: int = fx + d.x
				var nz: int = fz + d.y
				if nx < 0 or nz < 0 or nx >= n or nz >= n: continue
				var nc := nz * n + nx
				var ft: int = (holes[nc][0] as Vector2i).x if holes.has(nc) else _ktop(nc)   # the top of its grounded run
				if ft > o.x:
					dist[Vector3i(fx, fz, o.x)] = 1
					frontier.append([int(c), o])
					break
	var dcur := 1
	while not frontier.is_empty() and dcur < maxd:
		var nxt: Array = []
		for it in frontier:
			var c2: int = it[0]
			var cur: Vector2i = it[1]
			var fx2: int = c2 % n
			var fz2: int = c2 / n
			for d in dirs:
				var nx2: int = fx2 + d.x
				var nz2: int = fz2 + d.y
				if nx2 < 0 or nz2 < 0 or nx2 >= n or nz2 >= n: continue
				var nc2 := nz2 * n + nx2
				if not sp_of.has(nc2): continue
				var nsp: Array = sp_of[nc2]
				for jj2 in range(1, nsp.size()):
					var o2: Vector2i = nsp[jj2]
					if o2.x >= cur.y or o2.y <= cur.x: continue
					var key := Vector3i(nx2, nz2, o2.x)
					if dist.has(key): continue
					dist[key] = dcur + 1
					nxt.append([nc2, o2])
		frontier = nxt
		dcur += 1
	return dist

func _held(fx: int, fz: int, sp: Vector2i) -> bool:
	var reach: int = maxi(Data.BLOCK_REACH.get(mat_at(fx, fz, _ly(sp.x)), 1), int(reach_bonus.get(fz * n + fx, 0)))
	var frontier: Array = [[fx, fz, sp]]
	var seen := {Vector3i(fx, fz, sp.x): true}
	for depth in reach:
		var nxt: Array = []
		for it in frontier:
			var cur: Vector2i = it[2]
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = int(it[0]) + d.x
				var nz: int = int(it[1]) + d.y
				if nx < 0 or nz < 0 or nx >= n or nz >= n: continue
				var nsp := spans(nz * n + nx)
				for jj in nsp.size():
					var o: Vector2i = nsp[jj]
					if o.x >= cur.y or o.y <= cur.x: continue   # no side contact
					if jj == 0: return true   # joined to grounded ground
					var key := Vector3i(nx, nz, o.x)
					if seen.has(key): continue
					seen[key] = true
					nxt.append([nx, nz, o])
		frontier = nxt
		if frontier.is_empty(): break
	return false

## Is a tile-local point inside the block ground? (Off the patch: no.)
@warning_ignore("integer_division")
func is_solid(x: float, y: float, z: float) -> bool:
	if not covers(x, z): return false
	var step: float = Data.BLOCK_MIN
	var i := clampi(int((z - z0) / step), 0, n - 1) * n + clampi(int((x - x0) / step), 0, n - 1)
	var k := _k(y)
	if k < _kfloor(i): return true
	return _solid_k(i, k)

## The ground for something whose feet are at height y: inside rock = the top of that rock (it pops up onto it);
## otherwise the top of the solid under it (a tunnel floor under an overhang). Off the patch: -INF.
func ground_for(x: float, y: float, z: float) -> float:
	if not covers(x, z): return -INF
	var step: float = Data.BLOCK_MIN
	var i := clampi(int((z - z0) / step), 0, n - 1) * n + clampi(int((x - x0) / step), 0, n - 1)
	if not holes.has(i): return h[i]
	var best := -INF
	for o in spans(i):
		var lo: float = y0 + (o as Vector2i).x * step
		var hi: float = y0 + (o as Vector2i).y * step
		if y >= lo and y < hi - 0.01: return hi
		if hi <= y + 0.01: best = maxf(best, hi)
	return best if best > -INF else h[i]

## The underside of the rock over a point (a tunnel / cave roof), or INF in the open.
func ceiling_above(x: float, y: float, z: float) -> float:
	if not covers(x, z): return INF
	var step: float = Data.BLOCK_MIN
	var i := clampi(int((z - z0) / step), 0, n - 1) * n + clampi(int((x - x0) / step), 0, n - 1)
	if not holes.has(i): return INF
	for o in spans(i):
		var lo: float = y0 + (o as Vector2i).x * step
		if lo > y + 0.01: return lo
	return INF

## The material of the layer at a point (or "" outside the ground).
@warning_ignore("integer_division")
func mat_point(x: float, y: float, z: float) -> String:
	if not covers(x, z): return ""
	var step: float = Data.BLOCK_MIN
	var fx := clampi(int((x - x0) / step), 0, n - 1)
	var fz := clampi(int((z - z0) / step), 0, n - 1)
	var s: int = lsz[fz * n + fx]
	return mat_at(fx - fx % s + s / 2, fz - fz % s + s / 2, _ly(_k(y)))

## Tests / tools: the whole changeable state, and putting it back.
func snapshot() -> Dictionary:
	return {"h": h.duplicate(), "lsz": lsz.duplicate(), "dmg": dmg.duplicate(true), "holes": holes.duplicate(true), "mats": mats.duplicate(true), "fill": fill.duplicate(true), "fluid": fluid.duplicate(true), "reach": reach_bonus.duplicate(), "n": deltas.size()}

func restore(sn: Dictionary) -> void:
	h = sn["h"]
	lsz = sn["lsz"]
	dmg = sn["dmg"]
	holes = sn["holes"]
	mats = sn.get("mats", {})
	fill = sn.get("fill", {})
	fluid = sn.get("fluid", {})
	reach_bonus = sn.get("reach", reach_bonus)
	_fluid_dirty = true
	deltas.resize(int(sn["n"]))
	var nc := _nchunks()
	for k in nc * nc: _dirty[k] = true

# ---------------------------------------------------------------- settling rubble (v1.5z)
## A landed (or stuck) piece becomes part of the ground: its volume, in 5 m layers, goes into the cell under it as its
## own material. Kept as a note, so the ground regrows the same: [x, y, z, "dep:<material>:<amount>"].
func _merge_piece(b: Dictionary, y: float) -> void:
	var nd := b["node"] as Node3D
	var sc: Vector3 = nd.scale
	var amount := clampf(sc.x * sc.y * sc.z / pow(Data.BLOCK_MIN, 3.0), 0.05, Data.BLOCK_DEPOSIT_MAX)
	var at: Vector3 = nd.position
	nd.queue_free()
	merged += 1
	var note := [snappedf(at.x - off.x, 0.01), snappedf(y, 0.01), snappedf(at.z - off.y, 0.01), "dep:%s:%.3f" % [str(b.get("mat", "dirt")), amount]]
	deltas.append(note)
	if deltas.size() > Data.BLOCK_DELTAS_MAX: deltas.remove_at(0)
	_apply_note(note)

## Re-apply one kept note: a blast, or a deposit of settled rubble.
func _apply_note(d: Array) -> void:
	var kind := str(d[3])
	var at := Vector3(float(d[0]) + off.x, float(d[1]), float(d[2]) + off.y)   # (notes are kept in the field's own tile frame)
	if kind.begins_with("dep:"):
		var parts := kind.split(":")
		deposit(at, parts[1], float(parts[2]))
	elif kind.begins_with("set:") or kind == "cut":
		_edit_layer(at, kind.substr(4) if kind != "cut" else "")
	else:
		blast(at, kind, false, false)

## v1.7d: the player crossed into the next tile, so the frame moved by d: everything here moves with it (no rebuild;
## meshes already drawn just slide, and sit back at zero when they are next redrawn).
func reframe(d: Vector2) -> void:
	center += d
	x0 += d.x
	z0 += d.y
	off += d
	_pox -= d.x   # (the same planet ground: the frame's origin moved the other way)
	_poz -= d.y
	for sb in slabs:   # (the slab and waterfall drawings remember where they are)
		for g in sb["geo"]:
			g[0] = (g[0] as Vector2) + d
			g[1] = (g[1] as Vector2) + d
	for f in falls:
		f["top"] = (f["top"] as Vector3) + Vector3(d.x, 0.0, d.y)
		f["bottom"] = (f["bottom"] as Vector3) + Vector3(d.x, 0.0, d.y)
	for ch in get_children():
		if ch is Node3D: (ch as Node3D).position += Vector3(d.x, 0.0, d.y)

## Add `amount` layers of material m at the air layer containing point p (its cell). Whole layers are laid as the
## amount builds up; sand then slumps into a pile; anything left hanging is checked for support.
@warning_ignore("integer_division")
func deposit(p: Vector3, m: String, amount: float) -> void:
	if not covers(p.x, p.z): return
	var step: float = Data.BLOCK_MIN
	var fx := clampi(int((p.x - x0) / step), 0, n - 1)
	var fz := clampi(int((p.z - z0) / step), 0, n - 1)
	var i := fz * n + fx
	var acc: float = float(fill.get(i, 0.0)) + amount
	var added := 0
	while acc >= 1.0:
		_split_one(i)
		var k := _k(p.y)
		if _solid_k(i, k) or k < _kfloor(i): k = _ktop(i)   # (inside rock: it goes on top)
		_cell_add(i, k, m)
		acc -= 1.0
		added += 1
		p.y += step
	if acc > 0.001: fill[i] = acc
	else: fill.erase(i)
	if added > 0:
		if m == "sand": _slump(fx, fz)
		_settle(fx - 2, fx + 2, fz - 2, fz + 2)
		_mark(fx, fz, 1)

## Lay one layer k of material m in cell i (on top, or filling part of a hole).
func _cell_add(i: int, k: int, m: String) -> void:
	var kt := _ktop(i)
	if k >= kt:
		if k > kt:   # leaves air between: that's a hole under the new layer
			var hl: Array = holes.get(i, [])
			hl.append(Vector2i(kt, k))
			holes[i] = hl
		h[i] = y0 + (k + 1) * Data.BLOCK_MIN
	else:
		var keep: Array = []
		for hv in holes.get(i, []):
			var e: Vector2i = hv
			if k >= e.x and k < e.y:
				if e.x < k: keep.append(Vector2i(e.x, k))
				if k + 1 < e.y: keep.append(Vector2i(k + 1, e.y))
			else: keep.append(e)
		if keep.is_empty(): holes.erase(i)
		else: holes[i] = keep
	var ov: Dictionary = mats.get(i, {})
	ov[k] = m
	mats[i] = ov
	hmax = maxf(hmax, h[i])

## Break the block a cell belongs to down to single cells (rubble can only settle on single cells).
@warning_ignore("integer_division")
func _split_one(i: int) -> void:
	var fx := i % n
	var fz := i / n
	var s: int = lsz[i]
	if s <= 1: return
	var ox := fx - fx % s
	var oz := fz - fz % s
	var d0: Dictionary = dmg.get(oz * n + ox, {})
	for jz in s:
		for jx in s:
			var c := (oz + jz) * n + ox + jx
			lsz[c] = 1
			if not d0.is_empty(): dmg[c] = d0.duplicate()
	splits += 1
	_mark(ox, oz, s)

## Sand piles: a sand top more than a layer above a neighbour pours its top layer onto the lowest neighbour, again and
## again, so it ends as a mound with 45-degree sides, never a tower.
func _slump(fx: int, fz: int) -> void:
	var todo: Array = [Vector2i(fx, fz)]
	var guard := 0
	while not todo.is_empty() and guard < 200:
		guard += 1
		var c: Vector2i = todo.pop_back()
		var i := c.y * n + c.x
		if holes.has(i): continue
		var kt := _ktop(i)
		if mat_at(c.x, c.y, _ly(kt - 1)) != "sand": continue
		var low := -1
		var low_k := kt - Data.BLOCK_SAND_STEP
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = c.x + d.x
			var nz: int = c.y + d.y
			if nx < 0 or nz < 0 or nx >= n or nz >= n: continue
			var nk := _ktop(nz * n + nx)
			if nk < low_k:
				low_k = nk
				low = nz * n + nx
		if low < 0: continue
		_cell_remove(i, kt - 1)
		_split_one(low)
		_cell_add(low, _ktop(low), "sand")
		_mark(c.x, c.y, 1)
		_mark(low % n, low / n, 1)
		todo.append(c)
		todo.append(Vector2i(low % n, low / n))

# ---------------------------------------------------------------- water and lava (v1.6b)
## Sealed pockets placed from the seed: water held in stone, lava held in obsidian (more and deeper toward the bottom),
## never in sand, and not right at the middle of the patch. They sleep: nothing moves until one is broken into.
@warning_ignore("integer_division")
func _place_pockets() -> void:
	pockets.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|pockets")
	for spec in [["water", Data.FLUID_POCKETS["water"], 3, Data.FLUID_DEPTH["water"]], ["lava", Data.FLUID_POCKETS["lava"], 2, Data.FLUID_DEPTH["lava"]]]:
		var kind: String = spec[0]
		var w: int = spec[2]
		var tries := 0
		var placed := 0
		var want := _scaled(int(spec[1]), rng)
		while placed < want and tries < 200:
			tries += 1
			var cx := rng.randi_range(2, n - w - 2)
			var cz := rng.randi_range(2, n - w - 2)
			if Vector2(cx - n / 2, cz - n / 2).length() < 12: continue   # keep the middle clear
			var depth: float = rng.randf_range(float(spec[3][0]), float(spec[3][1]))
			var topmin := INF
			for jz in w:
				for jx in w: topmin = minf(topmin, h0[(cz + jz) * n + cx + jx])
			var k0 := _k(topmin - depth)
			var clash := false
			for jz in range(-1, w + 1):
				for jx in range(-1, w + 1):
					var c := (cz + jz) * n + cx + jx
					if fluid.has(c) or holes.has(c) or _kfloor(c) > k0 - 2 or _ktop(c) < k0 + 4: clash = true
			if clash: continue
			var cells: Array = []
			var shell: String = "obsidian" if kind == "lava" else "stone"
			for jz in range(-1, w + 1):
				for jx in range(-1, w + 1):
					var c := (cz + jz) * n + cx + jx
					_split_one(c)
					var ov: Dictionary = mats.get(c, {})
					for k in range(k0 - 1, k0 + 3): ov[k] = shell   # the container
					mats[c] = ov
			for jz in w:
				for jx in w:
					var c := (cz + jz) * n + cx + jx
					var fd: Dictionary = {}
					for k in [k0 + 1, k0]:
						_cell_remove(c, k)
						fd[k] = kind
					fluid[c] = fd
					cells.append(c)
			pockets.append({"cells": cells, "k0": k0, "kind": kind})
			placed += 1

## Gold and diamond veins (v1.6c): deep in the rock; some diamond in the obsidian over a lava pocket; and on some worlds
## (rolled by the seed) a few right out on the surface. A vein is a few 5 m cells of one layer.
@warning_ignore("integer_division")
func _place_veins() -> void:
	veins.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|veins")
	var lay := func(cells: Array, k_of: Callable, m: String) -> void:
		var placed: Array = []
		for c in cells:
			var k: int = k_of.call(c)
			if holes.has(c) or fluid.has(c) or k < _kfloor(c) or k >= _ktop(c) or not _solid_k(c, k): continue
			_split_one(c)
			var ov: Dictionary = mats.get(c, {})
			ov[k] = m
			mats[c] = ov
			placed.append(Vector2i(c, k))
		if not placed.is_empty(): veins.append({"mat": m, "cells": placed})
	for m in ["gold", "diamond"]:
		for v in _scaled(int(Data.MINE_VEINS[m]), rng):
			var cx := rng.randi_range(3, n - 6)
			var cz := rng.randi_range(3, n - 6)
			var depth: float = rng.randf_range(float(Data.VEIN_DEPTH[m][0]), float(Data.VEIN_DEPTH[m][1]))
			var w := rng.randi_range(1, 3)
			var cells: Array = []
			for jz in w:
				for jx in rng.randi_range(1, 3): cells.append((cz + jz) * n + cx + jx)
			var k0 := _k(h0[cz * n + cx] - depth)
			lay.call(cells, func(_c): return k0, m)
	for pk in pockets:   # diamond in the obsidian over some lava pockets
		if pk["kind"] != "lava" or rng.randf() > 0.5: continue
		lay.call((pk["cells"] as Array).slice(0, 2), func(_c): return int(pk["k0"]) + 2, "diamond")
	if rng.randf() < Data.SURFACE_TREASURE_CHANCE:   # this world wears some treasure on its surface
		for v in 3:
			var c := rng.randi_range(4, n - 5) * n + rng.randi_range(4, n - 5)
			lay.call([c], func(cc): return _ktop(cc) - 1, "gold" if v < 2 else "diamond")

## Caves (v1.6d): a few self-contained pockets of winding tunnels and chambers ("little pockets of ant farm"), carved
## by 3D noise inside a rounded box so each stays a section with solid rock round it; sealed, asleep until broken into.
## Settled once here so every roof that's left stands.
@warning_ignore("integer_division")
func _carve_caves() -> void:
	caves.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|caves")
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = Data.CAVE_NOISE_FREQ
	var w: int = Data.CAVE_SIZE
	var tries := 0
	var want := _scaled(Data.CAVE_COUNT, rng)
	while caves.size() < want and tries < 60:
		tries += 1
		var cx := rng.randi_range(2, n - w - 2)
		var cz := rng.randi_range(2, n - w - 2)
		if Vector2(cx + w / 2 - n / 2, cz + w / 2 - n / 2).length() < 14: continue   # the middle stays plain
		var topmin := INF
		for jz in w:
			for jx in w: topmin = minf(topmin, h0[(cz + jz) * n + cx + jx])
		var depth := rng.randf_range(float(Data.CAVE_DEPTH[0]), float(Data.CAVE_DEPTH[1]))
		var kc := _k(topmin - depth)
		var hl: int = Data.CAVE_LAYERS
		if kc - hl / 2 < _kfloor(cz * n + cx) + Data.KILL_CAP / Data.BLOCK_MIN + 1: continue
		var count := 0
		for jz in w:
			for jx in w:
				var c := (cz + jz) * n + cx + jx
				_split_one(c)
				for kk in range(-hl / 2, hl / 2):
					var k := kc + kk
					if k >= _ktop(c) - 3: continue   # always rock over it (sealed)
					var u := Vector3(float(jx) / (w - 1) * 2.0 - 1.0, float(kk) / (hl / 2), float(jz) / (w - 1) * 2.0 - 1.0)
					var fall := 1.0 - u.length_squared()   # rounded: the edges stay solid
					if fall <= 0.0: continue
					var v := nz.get_noise_3d(cx + jx, k * 1.4, cz + jz)
					if v + fall * 0.35 > Data.CAVE_THRESHOLD:
						_cell_remove(c, k)
						count += 1
		_settle(cx - 2, cx + w + 2, cz - 2, cz + w + 2)
		caves.append({"centre": Vector3(x0 + (cx + w * 0.5) * Data.BLOCK_MIN, _ly(kc), z0 + (cz + w * 0.5) * Data.BLOCK_MIN), "cells": count})
	collapses = 0

## v1.7h: stamp a mold into the ground. A mold is a filled volume of 5 m cells, given as runs [dx, dz, klo, khi]
## (cells from (cx, cz); layers from k0, khi not included). "cut" makes those layers air (from the top down, so a cut
## that reaches the surface opens an entrance); "add" makes them solid in material m. Returns the cells touched.
func _stamp(runs: Array, cx: int, cz: int, k0: int, op: String, m := "stone") -> Array:
	var touched: Array = []
	for r in runs:
		var x: int = cx + int(r[0])
		var z: int = cz + int(r[1])
		if x < 0 or z < 0 or x >= n or z >= n: continue
		var c := z * n + x
		_split_one(c)
		var kf := _kfloor(c) + 1
		if op == "cut":
			for k in range(k0 + int(r[3]) - 1, k0 + int(r[2]) - 1, -1):
				if k > kf and _solid_k(c, k): _cell_remove(c, k)
		else:   # (layers already solid take the mould's material: a root through rock is wood; "paint" fills no air)
			for k in range(k0 + int(r[2]), k0 + int(r[3])):
				if k <= kf: continue
				if not _solid_k(c, k):
					if op != "paint": _cell_add(c, k, m)
				else:
					var ov: Dictionary = mats.get(c, {})
					ov[k] = m
					mats[c] = ov
		touched.append(c)
		_mark(x, z, 1)
	return touched

## Turn {Vector2i(dx, dz): {k: true}} into mold runs [dx, dz, klo, khi].
func _runs_of(vol: Dictionary) -> Array:
	var out: Array = []
	for key in vol:
		var ks: Array = (vol[key] as Dictionary).keys()
		ks.sort()
		var i := 0
		while i < ks.size():
			var a: int = ks[i]
			var b: int = a + 1
			while i + 1 < ks.size() and int(ks[i + 1]) == b:
				i += 1
				b += 1
			out.append([(key as Vector2i).x, (key as Vector2i).y, a, b])
			i += 1
	return out

## v1.7h, the first mold (the owner's picture 07): a big chamber, tunnels out to side rooms at other heights, and one
## tunnel climbing to a surface entrance. Placed where there is room, with at least MOLD_CEILING of rock over the
## chamber and rooms; the ceiling over the open spaces may hang further than plain rock (reach_bonus), like the halls.
@warning_ignore("integer_division")
func _carve_cave_mold(force := false) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|cavemold")
	if not force and rng.randf() >= Data.MOLD_CAVE_CHANCE: return false
	var cw := rng.randi_range(int(Data.MOLD_CHAMBER[0]), int(Data.MOLD_CHAMBER[1]))
	var ch: int = Data.MOLD_CHAMBER_TALL
	var tw: int = Data.MOLD_TUNNEL_W
	var th: int = Data.MOLD_TUNNEL_TALL
	for attempt in 30:
		var vol := {}   # Vector2i(dx, dz) from the chamber's middle -> {k (from the chamber floor): true}
		var put := func(dx: int, dz: int, k_lo: int, k_hi: int) -> void:
			var key := Vector2i(dx, dz)
			var d: Dictionary = vol.get(key, {})
			for k in range(k_lo, k_hi): d[k] = true
			vol[key] = d
		var half := cw / 2
		for dz in range(-half, half):   # the chamber: a rounded box, a little domed
			for dx in range(-half, half):
				var u := Vector2((dx + 0.5) / half, (dz + 0.5) / half)
				var e := pow(absf(u.x), 4.0) + pow(absf(u.y), 4.0)
				if e > 1.0: continue
				put.call(dx, dz, 0, ch - (1 if e > 0.6 else 0))
		var ent := rng.randi_range(0, 3)   # which side the entrance tunnel leaves from
		var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
		var rooms: Array = []
		var route: Array = []   # the way out: [Vector2i(dx, dz), floor k] samples down the middle of the entrance tunnel
		var far := half
		for side in 4:
			var d: Vector2i = dirs[side]
			var lat := Vector2i(-d.y, d.x)
			if side == ent:   # climb toward the surface (one layer up every MOLD_RAMP cells), then a shaft straight up and out
				var fl := 0
				var s := half - 1
				while fl < ch:
					for w in range(-tw / 2, tw - tw / 2):
						var p := d * s + lat * w
						put.call(p.x, p.y, fl, fl + th)
					route.append([d * s, fl])
					s += 1
					if (s - half) % int(Data.MOLD_RAMP) == 0: fl += 1
				for a2 in range(0, tw):   # the shaft: cut on up through everything, so it opens to the sky
					for w in range(-tw / 2, tw - tw / 2):
						var p := d * (s + a2) + lat * w
						put.call(p.x, p.y, fl, fl + 80)
				route.append([d * (s + tw / 2), fl])
				far = maxi(far, s + tw)
			else:
				var ln := rng.randi_range(int(Data.MOLD_TUNNEL_LEN[0]), int(Data.MOLD_TUNNEL_LEN[1]))
				var rf := rng.randi_range(-2, 2)   # the side room's floor, in layers from the chamber floor
				for s in range(half - 1, half + ln + 1):   # (one cell into the room, so it always meets it)
					var f := int(round(lerpf(0.0, float(rf), float(s - half + 1) / float(ln))))   # it steps on the way
					for w in range(-tw / 2, tw - tw / 2):
						var p := d * s + lat * w
						put.call(p.x, p.y, f, f + th)
				var rw := rng.randi_range(int(Data.MOLD_ROOM[0]), int(Data.MOLD_ROOM[1]))
				var rc := d * (half + ln + rw / 2)
				for a in range(-rw / 2, rw - rw / 2):
					for b in range(-rw / 2, rw - rw / 2):
						var p := rc + Vector2i(a, b)
						put.call(p.x, p.y, rf, rf + Data.MOLD_ROOM_TALL)
				rooms.append([rc, rf])
				far = maxi(far, half + ln + rw)
		# where it fits: inside the region, the rock thick enough over everything but the entrance climb
		var cx := rng.randi_range(far + 2, n - far - 3)
		var cz := rng.randi_range(far + 2, n - far - 3)
		if cx < far + 2 or cz < far + 2 or cx > n - far - 3 or cz > n - far - 3:
			if far * 2 + 6 > n: return false
			continue
		var topmin := INF
		var floor_ok := true
		for key in vol:
			var kk: Vector2i = key
			var x := cx + kk.x
			var z := cz + kk.y
			if x < 1 or z < 1 or x >= n - 1 or z >= n - 1:
				floor_ok = false
				break
			var on_route := false
			for rt in route:
				if (rt[0] as Vector2i) == kk or ((rt[0] as Vector2i) - kk).length_squared() <= tw * tw: on_route = true
			if not on_route: topmin = minf(topmin, h[z * n + x])
		if not floor_ok or topmin == INF: continue
		if Surface.biome(planet_id, tile)["sea"] != null and topmin < 8.0: continue   # (not under the sea: it would open on the sea floor)
		var k0 := _k(topmin) - ch - Data.MOLD_CEILING - 2 - rng.randi_range(0, 2)
		if k0 - 3 < _kfloor(cz * n + cx) + int(Data.KILL_CAP / Data.BLOCK_MIN) + 1: continue
		var runs := _runs_of(vol)
		var touched := _stamp(runs, cx, cz, k0, "cut")
		for c in touched: reach_bonus[c] = maxi(int(reach_bonus.get(c, 0)), half + 2)
		_settle(maxi(0, cx - far - 2), mini(n - 1, cx + far + 2), maxi(0, cz - far - 2), mini(n - 1, cz + far + 2))
		var rts: Array = []
		for rt in route: rts.append([(cz + (rt[0] as Vector2i).y) * n + cx + (rt[0] as Vector2i).x, k0 + int(rt[1])])
		var rms: Array = []
		for rm in rooms: rms.append([(cz + (rm[0] as Vector2i).y) * n + cx + (rm[0] as Vector2i).x, k0 + int(rm[1])])
		molds.append({"kind": "cave", "centre": cz * n + cx, "k0": k0, "tall": ch, "rooms": rms, "route": rts, "cells": touched.size()})
		collapses = 0
		return true
	return false

## v1.7k: shapes from the mold library (models turned into molds by tools/molds/voxelize.py). Each may appear in a
## region by its chance, set on fairly even, solid ground (anchor "ground": its base a layer into the ground).
func _place_library() -> void:
	placed.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|library")
	var names: Array = MoldLibrary.MOLDS.keys()
	names.sort()
	for nm in names:
		var m: Dictionary = MoldLibrary.MOLDS[nm]
		if rng.randf() >= float(m["chance"]): continue
		for t in 20:
			if not _place_mold(nm, rng.randi_range(12, n - 13), rng.randi_range(12, n - 13)).is_empty(): break

## Put mold `nm` with its middle at cell (cx, cz), if the ground there suits it. Returns what was placed ({} if not).
func _place_mold(nm: String, cx: int, cz: int) -> Dictionary:
	var m: Dictionary = MoldLibrary.MOLDS[nm]
	var foot := {}
	for r in m["runs"]: foot[Vector2i(cx + int(r[0]), cz + int(r[1]))] = true
	var lo := INF
	var hi := -INF
	for key in foot:
		var kv: Vector2i = key
		if kv.x < 2 or kv.y < 2 or kv.x >= n - 2 or kv.y >= n - 2: return {}
		var c := kv.y * n + kv.x
		if holes.has(c) or fluid.has(c) or _slab_of.has(c): return {}
		lo = minf(lo, h[c])
		hi = maxf(hi, h[c])
	if hi - lo > Data.LANDMARK_FLAT: return {}
	var k0 := _k(lo + 0.01) - 1 if str(m["anchor"]) == "ground" else _k(lo + 0.01) - int(m["size"][1]) - 3
	var touched := _stamp(m["runs"], cx, cz, k0, str(m["op"]), str(m["mat"]))
	for c in touched: reach_bonus[c] = maxi(int(reach_bonus.get(c, 0)), 12)
	_settle(maxi(0, cx - 14), mini(n - 1, cx + 14), maxi(0, cz - 14), mini(n - 1, cz + 14))
	var rec := {"name": nm, "centre": cz * n + cx, "k0": k0, "cells": touched.size()}
	placed.append(rec)
	return rec

## v1.7l: waterfalls. Where a natural column drops FALL_DROP or more to its neighbour, a pool is cut into the top set
## back behind a one-cell rock lip, a pool at the cliff's foot, both filled with real water; the falling sheet between
## them is drawn as moving water with foam where it lands.
@warning_ignore("integer_division")
func _place_falls() -> void:
	falls.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|falls")
	var kind: String = Surface.PLANETS[planet_id]["tiles"][tile] if Surface.PLANETS.has(planet_id) else ""
	var want := _scaled(int(Data.FALLS_PER_TILE.get(kind, 2)), rng)
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var step: float = Data.BLOCK_MIN
	var tries := 0
	while falls.size() < want and tries < 400:
		tries += 1
		var x := rng.randi_range(6, n - 7)
		var z := rng.randi_range(6, n - 7)
		var d: Vector2i = dirs[rng.randi_range(0, 3)]
		var lat := Vector2i(-d.y, d.x)
		var w: int = Data.FALL_WIDE
		# the lip: w cells along the edge; behind it the pool (2 deep); in front, the drop to the foot
		var lip: Array = []
		var pool: Array = []
		var foot: Array = []
		var ok := true
		var top := INF
		var top_hi := -INF
		var low := -INF
		for a in w:
			var p := Vector2i(x, z) + lat * a
			for c2 in [p, p - d, p - d * 2, p + d, p + d * 2]:
				if c2.x < 2 or c2.y < 2 or c2.x >= n - 2 or c2.y >= n - 2: ok = false
			if not ok: break
			var cl: int = p.y * n + p.x
			lip.append(cl)
			for b in [1, 2]: pool.append((p - d * b).y * n + (p - d * b).x)
			for b in [1, 2, 3]:
				var q: Vector2i = p + d * int(b)
				if q.x >= 2 and q.y >= 2 and q.x < n - 2 and q.y < n - 2: foot.append(q.y * n + q.x)
			top = minf(top, h[cl])
			top_hi = maxf(top_hi, h[cl])
		if not ok or top_hi - top > 0.01: continue
		for c2 in lip + pool + foot:
			if holes.has(c2) or fluid.has(c2) or _slab_of.has(c2) or (mats.get(c2, {}) as Dictionary).size() > 0: ok = false
		if not ok: continue
		for c2 in pool:
			if absf(h[c2] - top) > 0.01: ok = false   # the pool behind the lip is on the same top
		var fl := -INF
		for c2 in foot: fl = maxf(fl, h[c2])
		if not ok or top - fl < Data.FALL_DROP: continue
		var foot_lo := INF
		for c2 in foot: foot_lo = minf(foot_lo, h[c2])
		if fl - foot_lo > step * 1.01: continue   # (a fairly flat foot for the pool)
		# cut and fill: the top pool one layer down behind the lip, the foot pool one layer into the ground
		for c2 in pool:
			_split_one(c2)
			var kt := _ktop(c2)
			_cell_remove(c2, kt - 1)
			_set_fluid(c2, kt - 1, "water")
		for c2 in foot:
			_split_one(c2)
			var kt2 := _ktop(c2)
			if h[c2] > foot_lo + 0.01: _cell_remove(c2, kt2 - 1)
			kt2 = _ktop(c2)
			_cell_remove(c2, kt2 - 1)
			_set_fluid(c2, kt2 - 1, "water")
		for c2 in lip: _split_one(c2)
		var p0 := Vector2(x0 + (x + 0.5) * step, z0 + (z + 0.5) * step) + Vector2(d) * step * 0.5 + Vector2(lat) * (w - 1) * step * 0.5
		var foot_y := foot_lo - step + step * 0.8
		falls.append({"lip": lip, "lip_h": top, "foot": foot, "foot_h": foot_lo - step, "top": Vector3(p0.x, top - 0.6, p0.y), "bottom": Vector3(p0.x, foot_y, p0.y), "dir": Vector2(d), "lat": Vector2(lat), "on": true})
		for c2 in lip + pool + foot: _mark(c2 % n, c2 / n, 1)
	_fluid_dirty = true
	_draw_falls()

## A fall whose lip or foot has been blasted stops.
func _falls_check() -> void:
	var changed := false
	for f in falls:
		if not f["on"]: continue
		for c in f["lip"]:
			if absf(h[c] - float(f["lip_h"])) > 0.01: f["on"] = false
		if not f["on"]: changed = true
	if changed: _draw_falls()

## The falling sheets (moving water) and the foam where they land.
func _draw_falls() -> void:
	var mi := get_node_or_null("Falls") as MeshInstance3D
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foam := SurfaceTool.new()
	foam.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for f in falls:
		if not f["on"]: continue
		var t: Vector3 = f["top"]
		var b: Vector3 = f["bottom"]
		var d: Vector2 = f["dir"]
		var lat: Vector2 = f["lat"]
		var half := Data.FALL_WIDE * Data.BLOCK_MIN * 0.5 - 0.4
		var out := Vector3(d.x, 0, d.y) * 1.2   # just off the cliff face
		var sv := Vector3(lat.x, 0, lat.y) * half
		var a0 := t - sv + out
		var a1 := t + sv + out
		var b0 := Vector3(b.x, b.y, b.z) - sv + out * 2.5
		var b1 := Vector3(b.x, b.y, b.z) + sv + out * 2.5
		var hgt := t.y - b.y
		for v in [[a0, Vector2(0, 0)], [a1, Vector2(1, 0)], [b1, Vector2(1, hgt / 10.0)], [a0, Vector2(0, 0)], [b1, Vector2(1, hgt / 10.0)], [b0, Vector2(0, hgt / 10.0)]]:
			st.set_normal(Vector3(d.x, 0, d.y))
			st.set_uv(v[1])
			st.add_vertex(v[0])
		for q in 7:   # foam: little white blocks bunched where it lands
			var fc := Vector3(b.x, b.y + 0.4, b.z) + out * 3.0 + sv * _rng.randf_range(-1.1, 1.1) + Vector3(d.x, 0, d.y) * _rng.randf_range(-1.0, 4.0)
			var s := _rng.randf_range(1.2, 2.6)
			var c := Color(0.95, 0.98, 1.0)
			_quad(foam, fc + Vector3(-s, s, -s), fc + Vector3(s, s, -s), fc + Vector3(s, s, s), fc + Vector3(-s, s, s), [c, c, c, c], Vector3.UP)
			_quad(foam, fc + Vector3(-s, -s, s), fc + Vector3(s, -s, s), fc + Vector3(s, s, s), fc + Vector3(-s, s, s), [c, c, c, c], Vector3.BACK)
			_quad(foam, fc + Vector3(s, -s, -s), fc + Vector3(-s, -s, -s), fc + Vector3(-s, s, -s), fc + Vector3(s, s, -s), [c, c, c, c], Vector3.FORWARD)
			_quad(foam, fc + Vector3(s, -s, s), fc + Vector3(s, -s, -s), fc + Vector3(s, s, -s), fc + Vector3(s, s, s), [c, c, c, c], Vector3.RIGHT)
			_quad(foam, fc + Vector3(-s, -s, -s), fc + Vector3(-s, -s, s), fc + Vector3(-s, s, s), fc + Vector3(-s, s, -s), [c, c, c, c], Vector3.LEFT)
		any = true
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Falls"
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec4 col : source_color = vec4(0.62, 0.86, 1.0, 0.85);
void fragment() {
	float s = fract(UV.y * 1.5 - TIME * 1.4 + sin(UV.x * 17.0) * 0.08);
	float streak = smoothstep(0.0, 0.08, s) * (1.0 - smoothstep(0.5, 0.6, s));
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(0.0, 0.08, 1.0 - UV.x);
	ALBEDO = col.rgb + vec3(0.18) * streak;
	ALPHA = col.a * edge;
}"""
		sm.shader = sh
		sm.set_shader_parameter("col", Data.FALL_COLOR)
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var fm := MeshInstance3D.new()
		fm.name = "Foam"
		var fmat := StandardMaterial3D.new()
		fmat.vertex_color_use_as_albedo = true
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.material_override = fmat
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_child(fm)
	mi.position = Vector3.ZERO
	mi.mesh = st.commit() if any else null
	(mi.get_node("Foam") as MeshInstance3D).mesh = foam.commit() if any else null

## v1.7i: alien trees (the owner's picture 06), grown as an "add" mold of wood and leaf: a chunky trunk on root
## buttresses, branches stepping up and out, big flat leaf slabs in two colours at their ends and on top, and roots
## running down and out underground. Next to a mold cave one tree sends a root down into the chamber, where it hangs
## from the ceiling to the floor (carved first, the roots added after, so they show inside it).
@warning_ignore("integer_division")
func _grow_trees() -> void:
	trees.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|trees")
	var kind: String = Surface.PLANETS[planet_id]["tiles"][tile] if Surface.PLANETS.has(planet_id) else ""
	var want := _scaled(int(Data.TREES_PER_TILE.get(kind, 2)), rng)
	if not molds.is_empty(): _grow_cave_tree(rng)
	var tries := 0
	while trees.size() < want + (1 if not molds.is_empty() else 0) and tries < 40:
		tries += 1
		_grow_tree(rng, rng.randi_range(14, n - 15), rng.randi_range(14, n - 15), -1)
	_settle(0, n - 1, 0, n - 1)

## The tree beside a mold cave: it stands a little off the chamber, and one of its roots grows down into it.
func _grow_cave_tree(rng: RandomNumberGenerator) -> bool:
	if molds.is_empty(): return false
	var mo: Dictionary = molds[0]
	var cc: int = mo["centre"]
	for t in 20:
		var a := rng.randf() * TAU
		var dd := rng.randf_range(6.0, 12.0)
		var x := clampi(cc % n + int(round(cos(a) * dd)), 14, n - 15)
		var z := clampi(cc / n + int(round(sin(a) * dd)), 14, n - 15)
		if _grow_tree(rng, x, z, cc): return true
	return false

## One tree with its trunk's corner at cell (cx, cz); to_cave >= 0: one root grows into that mold cave's chamber.
@warning_ignore("integer_division")
func _grow_tree(rng: RandomNumberGenerator, cx: int, cz: int, to_cave: int) -> bool:
	var tw := rng.randi_range(int(Data.TREE_TRUNK[0]), int(Data.TREE_TRUNK[1]))
	var ground := -INF
	for jz in tw:
		for jx in tw:
			var c := (cz + jz) * n + cx + jx
			if holes.has(c) or fluid.has(c) or _slab_of.has(c) or (mats.get(c, {}) as Dictionary).size() > 0: return false
			ground = maxf(ground, h[c])
	for tr in trees:   # (not on top of another tree)
		if Vector2i(int(tr["base"]) % n - cx, int(tr["base"]) / n - cz).length() < 12: return false
	var kg := _k(ground + 0.01)
	var tall := rng.randi_range(int(Data.TREE_TALL[0]), int(Data.TREE_TALL[1]))
	var kt := kg + tall
	var wood := {}
	var roots := {}   # (underground wood: it only turns rock to wood, never fills a cave or tunnel)
	var leaf := {"leaf": {}, "leaf2": {}}
	var put := func(vol: Dictionary, x: int, z: int, k_lo: int, k_hi: int) -> void:
		if x < 1 or z < 1 or x >= n - 1 or z >= n - 1: return
		var key := Vector2i(x, z)
		var d: Dictionary = vol.get(key, {})
		for k in range(k_lo, k_hi): d[k] = true
		vol[key] = d
	for jz in tw:   # the trunk, from a little under the ground to the top
		for jx in tw:
			put.call(wood, cx + jx, cz + jz, kg, kt)
			put.call(roots, cx + jx, cz + jz, kg - 3, kg)
	for t in rng.randi_range(4, 7):   # root buttresses flaring at its foot
		var side := rng.randi_range(0, 3)
		var along := rng.randi_range(0, tw - 1)
		var bx: int = [cx + tw, cx + along, cx - 1, cx + along][side]
		var bz: int = [cz + along, cz + tw, cz + along, cz - 1][side]
		put.call(wood, bx, bz, _ktop(clampi(bz, 0, n - 1) * n + clampi(bx, 0, n - 1)) - 1, kg + rng.randi_range(1, 2))
	var mid := Vector2(cx + tw * 0.5, cz + tw * 0.5)
	var canopy_lo := kt
	var slab := func(x0c: int, z0c: int, k: int, colour: String) -> void:
		var w := rng.randi_range(int(Data.TREE_CANOPY[0]), int(Data.TREE_CANOPY[1]))
		var d := rng.randi_range(int(Data.TREE_CANOPY[0]), int(Data.TREE_CANOPY[1]))
		for a in w:
			for b in d: put.call(leaf[colour], x0c - w / 2 + a, z0c - d / 2 + b, k, k + 2)
	var nb := rng.randi_range(int(Data.TREE_BRANCHES[0]), int(Data.TREE_BRANCHES[1]))
	var a0 := rng.randf() * TAU
	for b in nb:   # branches stepping up and out, a leaf slab at each end
		var ang := a0 + TAU * b / nb + rng.randf_range(-0.3, 0.3)
		var dir := Vector2(cos(ang), sin(ang))
		var k := kt - rng.randi_range(1, 3)
		var ln := rng.randi_range(3, 6)
		var p := mid
		for st in ln:
			p += dir
			if st % 2 == 1: k += 1
			put.call(wood, int(floor(p.x)), int(floor(p.y)), k - 1, k + 1)
		slab.call(int(floor(p.x)), int(floor(p.y)), k + 1, "leaf" if b % 2 == 0 else "leaf2")
		canopy_lo = mini(canopy_lo, k + 1)
	slab.call(int(mid.x), int(mid.y), kt, "leaf2" if nb % 2 == 0 else "leaf")   # the crown on top
	for r in rng.randi_range(int(Data.TREE_ROOTS[0]), int(Data.TREE_ROOTS[1])):   # roots out and down underground
		var ang := rng.randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var p := mid
		var k := kg - 2
		for st in rng.randi_range(6, 12):
			p += dir
			k -= rng.randi_range(0, 2)
			put.call(roots, int(floor(p.x)), int(floor(p.y)), k - 1, k + 1)
	var cave_root := false
	if to_cave >= 0:   # down to the chamber's ceiling, in, and hanging from roof to floor
		var mo: Dictionary = molds[0]
		var k0: int = mo["k0"]
		var ktall: int = mo["tall"]
		var target := Vector2(to_cave % n + 0.5, to_cave / n + 0.5) + (mid - Vector2(to_cave % n + 0.5, to_cave / n + 0.5)).normalized() * 3.0
		var steps := int(ceil(mid.distance_to(target))) + 1
		for st in steps + 1:
			var q := mid.lerp(target, float(st) / steps)
			var kk := int(round(lerpf(float(kg - 2), float(k0 + ktall + 1), float(st) / steps)))
			put.call(roots, int(floor(q.x)), int(floor(q.y)), kk - 1, kk + 2)
		put.call(wood, int(floor(target.x)), int(floor(target.y)), k0, k0 + ktall + 2)   # the root pillar in the chamber
		cave_root = true
	var cells := {}
	var nw := 0
	var nl := 0
	for c in _stamp(_runs_of(wood), 0, 0, 0, "add", "wood"): cells[c] = true
	for c in _stamp(_runs_of(roots), 0, 0, 0, "paint", "wood"): cells[c] = true
	for v in roots.values(): nw += (v as Dictionary).size()
	for v in wood.values(): nw += (v as Dictionary).size()
	for colour in ["leaf", "leaf2"]:
		for c in _stamp(_runs_of(leaf[colour]), 0, 0, 0, "add", colour): cells[c] = true
		for v in (leaf[colour] as Dictionary).values(): nl += (v as Dictionary).size()
	for c in cells: reach_bonus[c] = maxi(int(reach_bonus.get(c, 0)), 12)   # (it holds together; take the trunk and it falls)
	var trunk: Array = []
	for jz in tw:
		for jx in tw: trunk.append((cz + jz) * n + cx + jx)
	trees.append({"base": cz * n + cx, "wood": nw, "leaf": nl, "cave_root": cave_root, "trunk": trunk, "k_ground": kg, "k_top": kt, "canopy_lo": canopy_lo})
	return true

## v1.7i fire: set a wood or leaf layer burning.
@warning_ignore("integer_division")
func ignite(c: int, k: int) -> bool:
	if burning.size() >= Data.FIRE_MAX or burning.has(Vector2i(c, k)) or not _solid_k(c, k): return false
	var m := mat_at(c % n, c / n, _ly(k))
	if m != "wood" and not Data.LEAF_COLORS.has(m): return false
	burning[Vector2i(c, k)] = 0.0
	_fire_dirty = true
	return true

var _fire_t := 0.0
var _fire_dirty := false
## Every FIRE_TICK: what burns long enough is gone (a note, like any change), it catches touching wood and leaves, and
## water beside it puts it out. Only near the player (the rest waits, like the fluids).
@warning_ignore("integer_division")
func _fire_update(dt: float, near: Vector3) -> void:
	_fire_t += dt
	if _fire_t < Data.FIRE_TICK:
		if _fire_dirty: _draw_fire()
		return
	_fire_t = 0.0
	var keys: Array = burning.keys()
	for key in keys:
		var kv: Vector2i = key
		if not burning.has(kv): continue
		var c := kv.x
		var k := kv.y
		var pt := _layer_point(c, k)
		if Vector2(pt.x - near.x, pt.z - near.z).length() > Data.FIRE_RADIUS: continue
		if not _solid_k(c, k):
			burning.erase(kv)
			continue
		var m := mat_at(c % n, c / n, _ly(k))
		var wet := false
		for nb in _nbrs6(c, k):
			if _fluid_k((nb as Vector2i).x, (nb as Vector2i).y) == "water": wet = true
		if wet:
			burning.erase(kv)
			continue
		for nb in _nbrs6(c, k):
			var nc: int = (nb as Vector2i).x
			var nk: int = (nb as Vector2i).y
			if burning.has(Vector2i(nc, nk)) or not _solid_k(nc, nk): continue
			var nm := mat_at(nc % n, nc / n, _ly(nk))
			if Data.FIRE_SPREAD.has(nm) and _rng.randf() < float(Data.FIRE_SPREAD[nm]): ignite(nc, nk)
		burning[kv] = float(burning[kv]) + Data.FIRE_TICK
		if float(burning[kv]) >= float(Data.FIRE_BURN.get(m, 2.0)):
			burning.erase(kv)
			_edit_layer(pt, "", true)   # burnt away (kept as a note)
			burned += 1
	_fire_dirty = true
	flush()
	_draw_fire()

## The flames: a glowing orange block over each burning layer, flickering.
func _draw_fire() -> void:
	_fire_dirty = false
	var mi := get_node_or_null("Fire") as MultiMeshInstance3D
	if mi == null:
		mi = MultiMeshInstance3D.new()
		mi.name = "Fire"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bx := BoxMesh.new()
		bx.size = Vector3.ONE
		mm.mesh = bx
		mi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.45, 0.08, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	mi.position = Vector3.ZERO
	var keys: Array = burning.keys()
	mi.multimesh.instance_count = keys.size()
	for i in keys.size():
		var kv: Vector2i = keys[i]
		var s := Data.BLOCK_MIN * (1.02 + 0.12 * _rng.randf())
		mi.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s * (1.0 + 0.3 * _rng.randf()), s)), _layer_point(kv.x, kv.y) + Vector3(0, 0.6, 0)))

## v1.7j: winding tunnels from a mold cave's side rooms out to the nearest sealed caves (v1.6d), wandering by noise but
## always steering home to the cave, so the system is connected on purpose; each ends in a little junction room
## that opens into the cave. They stay clear of water and lava pockets.
@warning_ignore("integer_division")
func _carve_links() -> void:
	links.clear()
	if molds.is_empty() or caves.is_empty(): return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|links")
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 0.08
	var mo: Dictionary = molds[0]
	var step: float = Data.BLOCK_MIN
	var targets: Array = []
	for cv in caves:
		var cp: Vector3 = cv["centre"]
		var tx := clampi(int((cp.x - x0) / step), 2, n - 3)
		var tz := clampi(int((cp.z - z0) / step), 2, n - 3)
		targets.append(Vector3i(tx, tz, _k(cp.y)))
	var used := {}
	for rm in mo["rooms"]:
		if links.size() >= Data.LINK_MAX: break
		var rc: int = rm[0]
		var start := Vector2(rc % n + 0.5, rc / n + 0.5)
		var best := -1
		var bd := float(Data.LINK_REACH)
		for ti in targets.size():
			if used.has(ti): continue
			var tv: Vector3i = targets[ti]
			var d := start.distance_to(Vector2(tv.x + 0.5, tv.y + 0.5))
			if d < bd:
				bd = d
				best = ti
		if best < 0: continue
		used[best] = true
		var tgt: Vector3i = targets[best]
		var goal := Vector2(tgt.x + 0.5, tgt.y + 0.5)
		var vol := {}
		var put := func(x: int, z: int, k_lo: int, k_hi: int) -> void:
			if x < 2 or z < 2 or x >= n - 2 or z >= n - 2: return
			var key := Vector2i(x, z)
			var d: Dictionary = vol.get(key, {})
			for k in range(k_lo, k_hi): d[k] = true
			vol[key] = d
		var p := start
		var k := float(int(rm[1]) + 1)
		var heading := (goal - start).normalized()
		var path: Array = []
		var r: int = Data.LINK_RADIUS
		var wet := false
		for st in 220:
			var want := (goal - p).normalized()
			var turn := nz.get_noise_2d(st * 3.0, float(links.size()) * 50.0) * Data.LINK_WANDER
			heading = (heading * 0.65 + want * 0.35).rotated(turn).normalized()
			p += heading
			k += clampf(float(tgt.z) - k, -0.5, 0.5)   # it drifts up or down toward the cave, one layer every two cells
			var ci := int(floor(p.x))
			var cj := int(floor(p.y))
			var roof := INF   # always under the ground: at least 2 layers of rock over it
			for dz in range(-r - 1, r + 2):
				for dx in range(-r - 1, r + 2):
					var x2 := clampi(ci + dx, 0, n - 1)
					var z2 := clampi(cj + dz, 0, n - 1)
					roof = minf(roof, float(_ktop(z2 * n + x2)))
			k = minf(k, roof - Data.LINK_TALL - 2)
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dz * dz > r * r + 1: continue
					var x := ci + dx
					var z := cj + dz
					if x >= 0 and z >= 0 and x < n and z < n and fluid.has(z * n + x): wet = true
					put.call(x, z, int(k), int(k) + Data.LINK_TALL)
			path.append([cj * n + ci, int(k)])
			if wet or p.distance_to(goal) < 2.5: break
		if wet: continue   # (it would have let a sealed pocket of water or lava out: no tunnel there)
		for dz in range(-3, 4):   # the junction where it meets the cave
			for dx in range(-3, 4): put.call(tgt.x + dx, tgt.y + dz, tgt.z - 1, tgt.z + 3)
		var ek := int(k)   # and a chimney from the tunnel's end up or down to it (the ground may have kept it lower)
		for dz in range(-1, 2):
			for dx in range(-1, 2): put.call(int(floor(p.x)) + dx, int(floor(p.y)) + dz, mini(ek, tgt.z - 1), maxi(ek + Data.LINK_TALL, tgt.z + 3))
		var touched := _stamp(_runs_of(vol), 0, 0, 0, "cut")
		for c in touched: reach_bonus[c] = maxi(int(reach_bonus.get(c, 0)), 12)   # (the rock over it, and over the cave it opens, holds)
		for dz in range(-9, 10):
			for dx in range(-9, 10):
				var x3 := tgt.x + dx
				var z3 := tgt.y + dz
				if x3 >= 0 and z3 >= 0 and x3 < n and z3 < n: reach_bonus[z3 * n + x3] = maxi(int(reach_bonus.get(z3 * n + x3, 0)), 12)
		links.append({"from": rc, "to": [tgt.y * n + tgt.x, tgt.z], "path": path})
	if not links.is_empty(): _settle(0, n - 1, 0, n - 1)
	collapses = 0

## Landmarks (v1.6e): flyable natural ARCHES (stone, some obsidian; some with gold or diamond in the span) on a leg at
## each end, and PRIDE ROCK promontories: a block of rock with a slab jutting out over open air. Load-bearing: each
## half of an arch hangs from its own leg (reach_bonus), a promontory's slab from its block, so blasting a leg out
## brings its half down. Realistic sizes (no thin spikes).
@warning_ignore("integer_division")
func _build_landmarks() -> void:
	arches.clear()
	overhangs.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|landmarks")
	var step: float = Data.BLOCK_MIN
	var free := func(cells: Array) -> bool:
		for c in cells:
			if c < 0 or c >= n * n or holes.has(c) or fluid.has(c): return false
		return true
	var tries := 0
	var want := _scaled(Data.ARCH_COUNT, rng)
	while arches.size() < want and tries < 80:
		tries += 1
		var length := rng.randi_range(int(Data.ARCH_SPAN[0]), int(Data.ARCH_SPAN[1]))   # cells between the legs
		var along_x := rng.randf() < 0.5
		var lx := rng.randi_range(3, n - length - 8)
		var lz := rng.randi_range(3, n - 6)
		var leg_w := 2
		var all_cells: Array = []
		var cell_at := func(a: int, b: int) -> int: return (lz + b) * n + lx + a if along_x else (lz + a) * n + lx + b
		for a in length + leg_w * 2:
			for b in 2: all_cells.append(cell_at.call(a, b))
		if not free.call(all_cells): continue
		if Vector2(lx + length / 2 - n / 2, lz - n / 2).length() < 14: continue
		var ground := -INF
		var low := INF
		for c in all_cells:
			ground = maxf(ground, h[c])
			low = minf(low, h[c])
		if ground - low > Data.LANDMARK_FLAT: continue   # only on fairly even ground
		var clear: float = rng.randf_range(float(Data.ARCH_CLEAR[0]), float(Data.ARCH_CLEAR[1]))
		var thick: float = Data.ARCH_THICK
		var m := "obsidian" if rng.randf() < 0.35 else "stone"
		var treasure := "" if rng.randf() > 0.4 else ("diamond" if rng.randf() < 0.35 else "gold")
		var legs: Array = [[], []]
		var span: Array = []
		var half := length / 2 + 1
		for a in length + leg_w * 2:
			var t := float(a - leg_w + 0.5) / float(length)   # 0..1 along the opening
			var under: float = ground if a < leg_w or a >= length + leg_w else ground + clear * sin(PI * clampf(t, 0.0, 1.0))
			under = floorf(under / step) * step
			var top: float = ceilf((ground + clear + thick) / step) * step
			for b in 2:
				var c: int = cell_at.call(a, b)
				_split_one(c)
				var k_ground := _ktop(c)
				var k_under := _k(under + 0.01)
				var k_top := _k(top - 0.01) + 1
				h[c] = y0 + k_top * step
				var is_leg: bool = a < leg_w or a >= length + leg_w
				if k_under > k_ground and not is_leg: holes[c] = [Vector2i(k_ground, k_under)]
				else: holes.erase(c)   # the legs are solid rock right down to the ground
				var ov: Dictionary = mats.get(c, {})
				for k in range(mini(k_ground, k_under), k_top): ov[k] = m
				if treasure != "" and a == (length + leg_w * 2) / 2 and b == 0: ov[k_top - 2] = treasure   # it glints in the span
				mats[c] = ov
				hmax = maxf(hmax, h[c])
				if a < leg_w: legs[0].append(c)
				elif a >= length + leg_w: legs[1].append(c)
				else:
					span.append(c)
					reach_bonus[c] = half
				_mark(c % n, c / n, 1)
		arches.append({"legs": legs, "span": span, "mid": cell_at.call((length + leg_w * 2) / 2, 0), "mat": m, "treasure": treasure})
	tries = 0
	var want_o := _scaled(Data.OVERHANG_COUNT, rng)
	while overhangs.size() < want_o and tries < 80:
		tries += 1
		var bw := 4
		var jut := rng.randi_range(int(Data.OVERHANG_JUT[0]), int(Data.OVERHANG_JUT[1]))
		var ox := rng.randi_range(3, n - bw - jut - 4)
		var oz := rng.randi_range(3, n - bw - 4)
		var cells: Array = []
		for jz in bw:
			for jx in bw + jut: cells.append((oz + jz) * n + ox + jx)
		if not free.call(cells): continue
		if Vector2(ox - n / 2, oz - n / 2).length() < 14: continue
		var ground := -INF
		var low := INF
		for c in cells:
			ground = maxf(ground, h[c])
			low = minf(low, h[c])
		if ground - low > Data.LANDMARK_FLAT: continue
		var rise: float = rng.randf_range(float(Data.OVERHANG_RISE[0]), float(Data.OVERHANG_RISE[1]))
		var top: float = ceilf((ground + rise) / step) * step
		var under: float = floorf((top - Data.OVERHANG_THICK) / step) * step
		var base: Array = []
		var slab: Array = []
		for jz in bw:
			for jx in bw + jut:
				var c: int = (oz + jz) * n + ox + jx
				_split_one(c)
				var k_ground := _ktop(c)
				var k_under := _k(under + 0.01)
				h[c] = top
				var ov: Dictionary = mats.get(c, {})
				if jx >= bw:   # the slab jutting out over open air
					if k_under > k_ground: holes[c] = [Vector2i(k_ground, k_under)]
					reach_bonus[c] = jut + 1
					slab.append(c)
				else: base.append(c)
				for k in range(k_ground - 1, _ktop(c)): ov[k] = "stone"
				mats[c] = ov
				hmax = maxf(hmax, h[c])
				_mark(c % n, c / n, 1)
		overhangs.append({"base": base, "jut": slab, "tip": (oz + 1) * n + ox + bw + jut - 1})
	_settle(0, n - 1, 0, n - 1)

## v1.7f: leaning slabs and A-frames. A lean-to is a slab rising from the ground onto a stone pillar (its prop); an
## A-frame is two slabs rising toward each other until they meet, with air under them to fly through. In blocks: each
## cell along it is solid from its slab's underside to its top, with air down to the ground under it (the low end and
## the prop are solid); its cells may hang about half its length from support, so take the prop (or one foot of an
## A-frame) away and the far part has nothing left to hold it and comes down.
@warning_ignore("integer_division")
func _build_slabs() -> void:
	slabs.clear()
	_slab_of.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|slabs")
	var step: float = Data.BLOCK_MIN
	for kind in ["lean", "aframe"]:
		var want := _scaled(Data.SLAB_COUNT if kind == "lean" else Data.AFRAME_COUNT, rng)
		var tries := 0
		var made := 0
		while made < want and tries < 60:
			tries += 1
			var L := rng.randi_range(int(Data.SLAB_LEN[0]), int(Data.SLAB_LEN[1]))
			var total := L + 2 if kind == "lean" else L * 2 + 1   # lean-to: slab + 2-cell prop; A-frame: two slabs + the apex
			var W: int = Data.SLAB_WIDE
			var along_x := rng.randf() < 0.5
			var lx := rng.randi_range(4, n - total - 5)
			var lz := rng.randi_range(4, n - W - 5)
			var flip := rng.randf() < 0.5
			var cell_at := func(a: int, b: int) -> int:
				var aa := total - 1 - a if flip else a
				return (lz + b) * n + lx + aa if along_x else (lx + aa) * n + lz + b   # (lx runs along, lz across)
			var cells: Array = []
			var ok := true
			var ground := -INF
			var low := INF
			for a in total:
				for b in W:
					var c: int = cell_at.call(a, b)
					if holes.has(c) or fluid.has(c) or _slab_of.has(c) or (mats.get(c, {}) as Dictionary).size() > 0: ok = false
					cells.append(c)
					ground = maxf(ground, h[c])
					low = minf(low, h[c])
			if not ok or ground - low > Data.LANDMARK_FLAT: continue
			var rise: float = rng.randf_range(float(Data.SLAB_RISE[0]), float(Data.SLAB_RISE[1]))
			var thick: float = Data.SLAB_THICK
			var m := "obsidian" if rng.randf() < 0.3 else "stone"
			var lo := {}
			var slab_cells: Array = []
			var hold: Array = []   # the prop (lean-to) or the first foot (A-frame): the test knocks it out
			for a in total:
				var under: float   # the slab's underside over this cell (m)
				var solid := false
				if kind == "lean":
					under = ground + rise * float(a) / float(L)
					solid = a == 0 or a >= L   # the low end and the prop pillar
					if a >= L: under = ground + rise
				else:
					under = ground + rise * (1.0 - absf(float(a) - float(L)) / float(L))
					solid = a == 0 or a == total - 1
				if not solid: under = maxf(under, ground + step)   # (v1.7q: air under every part but the feet, so only they hold it)
				var top: float = ceilf((under + thick) / step) * step
				var ku := _k(floorf(under / step) * step + 0.01)
				for b in W:
					var c: int = cell_at.call(a, b)
					_split_one(c)
					var kg := _ktop(c)
					var kt := _k(top - 0.01) + 1
					h[c] = y0 + kt * step
					if not solid and ku > kg: holes[c] = [Vector2i(kg, ku)]
					var ov: Dictionary = mats.get(c, {})
					for k in range(mini(kg, ku) if solid else ku, kt): ov[k] = m
					mats[c] = ov
					hmax = maxf(hmax, h[c])
					if (kind == "lean" and a >= L) or (kind == "aframe" and a == 0): hold.append(c)
					if not (kind == "lean" and a >= L):   # (the prop is ordinary rock: you shoot it, it isn't the slab)
						lo[c] = minf(under, ground) if solid else under
						slab_cells.append(c)
						reach_bonus[c] = L / 2 + 1
					_mark(c % n, c / n, 1)
			# the look: straight tilted slabs (corner points along the slab, across it, underside heights)
			var s0: Vector2 = _cell_corner(cell_at.call(0, 0))
			var geo: Array = []
			var lat := Vector2(0, 1) if along_x else Vector2(1, 0)   # across
			var dir := Vector2(1, 0) if along_x else Vector2(0, 1)   # along (the cell order may be flipped)
			if flip: dir = -dir
			var start := s0 + (Vector2(step, 0) if along_x else Vector2(0, step)) * (1.0 if flip else 0.0)
			if flip: start = s0 + (Vector2(step, 0) if along_x else Vector2(0, step))
			if kind == "lean":
				geo.append([start, start + dir * L * step, ground, ground + rise])
			else:
				var apex := start + dir * (L + 0.5) * step
				geo.append([start, apex, ground, ground + rise])
				geo.append([start + dir * total * step, apex, ground, ground + rise])
			slabs.append({"cells": slab_cells, "lo": lo, "kind": kind, "mat": m, "geo": geo, "lat": lat * W * step, "thick": thick, "whole": true, "expect": {}, "hold": hold, "rise": rise, "ground": ground})
			for c in slab_cells: _slab_of[c] = slabs.size() - 1
			made += 1
	_settle(0, n - 1, 0, n - 1)

## The north-west corner of a cell (tile-local x, z).
func _cell_corner(c: int) -> Vector2:
	return Vector2(x0 + (c % n) * Data.BLOCK_MIN, z0 + (c / n) * Data.BLOCK_MIN)

## Remember what each slab's cells look like when whole (after the world is generated).
func _slab_expect() -> void:
	for sb in slabs:
		var ex := {}
		for c in sb["cells"]: ex[c] = [h[c], (holes.get(c, []) as Array).duplicate()]
		sb["expect"] = ex
		sb["whole"] = true
	for sb in slabs:   # (anything later generation changed shows as blocks from the start)
		for c in sb["cells"]:
			if not _slab_cell_same(sb, c): sb["whole"] = false
	_draw_slabs()

func _slab_cell_same(sb: Dictionary, c: int) -> bool:
	var e: Array = (sb["expect"] as Dictionary).get(c, [])
	return not e.is_empty() and absf(float(e[0]) - h[c]) < 0.01 and e[1] == holes.get(c, []) and not dmg.has(c)

## Before drawing: a slab that has been hit anywhere stops being one straight piece and shows as its blocks.
func _slab_check() -> void:
	var changed := false
	for sb in slabs:
		if not sb["whole"]: continue
		for c in sb["cells"]:
			if not _slab_cell_same(sb, c):
				sb["whole"] = false
				changed = true
				for c2 in sb["cells"]: _mark(int(c2) % n, int(c2) / n, 1)
				break
	if changed: _draw_slabs()

## While its slab is whole, a cell's slab part isn't drawn as blocks (the slab is drawn instead): the y under it.
func _slab_lo(c: int) -> float:
	if not _slab_of.has(c): return INF
	var sb: Dictionary = slabs[_slab_of[c]]
	return float((sb["lo"] as Dictionary)[c]) if sb["whole"] else INF

## The straight tilted slabs (one mesh for all of them in this field).
func _draw_slabs() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for sb in slabs:
		if not sb["whole"]: continue
		var col := tone(str(sb["mat"]))
		var lat: Vector2 = sb["lat"]
		var th: float = sb["thick"]
		for g in sb["geo"]:
			var a: Vector2 = g[0]
			var b: Vector2 = g[1]
			var ya: float = g[2]
			var yb: float = g[3]
			var p := [Vector3(a.x, ya, a.y), Vector3(b.x, yb, b.y), Vector3(b.x + lat.x, yb, b.y + lat.y), Vector3(a.x + lat.x, ya, a.y + lat.y)]
			var q := []
			for v in p: q.append((v as Vector3) + Vector3(0, th, 0))
			var top_c := col.lightened(0.06)
			var side_c := col * 0.85
			var under_c := col * 0.6
			_quad(st, q[0], q[1], q[2], q[3], [top_c, top_c, top_c, top_c], ((q[1] - q[0]) as Vector3).cross(q[3] - q[0]).normalized() * -1.0 if ((q[1] - q[0]) as Vector3).cross(q[3] - q[0]).y < 0.0 else ((q[1] - q[0]) as Vector3).cross(q[3] - q[0]).normalized())
			_quad(st, p[3], p[2], p[1], p[0], [under_c, under_c, under_c, under_c], Vector3.DOWN)
			for k in 4:
				var k2 := (k + 1) % 4
				var nrm := Vector3(((p[k2] as Vector3) - (p[k] as Vector3)).z, 0, -((p[k2] as Vector3) - (p[k] as Vector3)).x).normalized()
				_quad(st, q[k], q[k2], p[k2], p[k], [side_c, side_c, side_c, side_c], nrm)
			any = true
	var mi := get_node_or_null("Slabs") as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Slabs"
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.85
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	mi.position = Vector3.ZERO
	mi.mesh = st.commit() if any else null

## A canyon (v1.6f): one deep, winding cut across the patch you can fly down into, its walls showing the layers, with a
## little gold in the walls. It wanders by noise, keeps away from the patch edge, and its floor follows the ground
## down (never deeper than CANYON_DEPTH under it, never into the obsidian cap).
@warning_ignore("integer_division")
func _carve_canyon() -> void:
	canyon_cells.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|canyon")
	if feat < 0.999 and rng.randf() > Data.BLOCK_REGION_CANYON: return   # (v1.7a) not every region has one
	var step: float = Data.BLOCK_MIN
	var m := 10
	var p := Vector2(m, rng.randf_range(m, n - m))
	var heading := rng.randf_range(-0.4, 0.4)
	if rng.randf() < 0.5:   # sometimes it runs north-south
		p = Vector2(p.y, p.x)
		heading += PI * 0.5
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 0.05
	var depth: float = rng.randf_range(float(Data.CANYON_DEPTH[0]), float(Data.CANYON_DEPTH[1]))
	var seen := {}
	var t := 0
	var gold_left := 6
	while p.x >= m and p.y >= m and p.x < n - m and p.y < n - m and t < n * 3:
		t += 1
		heading += nz.get_noise_1d(t * 3.0) * 0.35
		p += Vector2(cos(heading), sin(heading))
		var w: float = Data.CANYON_WIDTH * (0.75 + 0.5 * (nz.get_noise_1d(t * 2.0 + 500.0) * 0.5 + 0.5))
		var ci := int(p.y) * n + int(p.x)
		var floor_y: float = maxf(floorf((h0[ci] - depth) / step) * step, h0[ci] - Data.BLOCK_DEPTH_FLOOR + Data.KILL_CAP + step * 4.0)
		for dz in range(-int(w) - 1, int(w) + 2):
			for dx in range(-int(w) - 1, int(w) + 2):
				if Vector2(dx, dz).length() > w: continue
				var fx := int(p.x) + dx
				var fz := int(p.y) + dz
				if fx < m - 4 or fz < m - 4 or fx >= n - m + 4 or fz >= n - m + 4: continue
				var c := fz * n + fx
				# the walls step down a little toward the middle (no knife-thin lip)
				var fy: float = floor_y + floorf(maxf(0.0, Vector2(dx, dz).length() - w + 1.5) * 2.0) * step
				if h[c] <= fy: continue
				_split_one(c)
				h[c] = fy
				if not seen.has(c):
					seen[c] = true
					canyon_cells.append(c)
					if gold_left > 0 and Vector2(dx, dz).length() > w - 1.0 and rng.randf() < 0.04:   # gold glinting in the wall
						var ov: Dictionary = mats.get(c, {})
						ov[_k(fy + step * 2.5)] = "gold"
						mats[c] = ov
						gold_left -= 1
				_mark(fx, fz, 1)

## The deep world (v1.6h): a few great halls right over the obsidian cap, the planet's skeleton. Dark obsidian trunks
## stand from the floor to the roof and fork into branches between them; they hold the rock above up (the roof hangs
## from them, never more than a few cells away); lava pools glow on the floor between the roots. Sealed and asleep
## like everything underground until you dig down to one. In sections (not the whole planet), to stay light.
@warning_ignore("integer_division")
func _carve_root_halls() -> void:
	halls.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|roothalls")
	var w: int = Data.HALL_SIZE
	var hl: int = Data.HALL_LAYERS
	var sp: int = Data.HALL_TRUNK_SPACING
	var tries := 0
	var want := _scaled(Data.HALL_COUNT, rng)
	while halls.size() < want and tries < 40:
		tries += 1
		var hx := rng.randi_range(4, n - w - 4)
		var hz := rng.randi_range(4, n - w - 4)
		var clash := false
		for h2 in halls:
			if absi(int(h2["x"]) - hx) < w + 4 and absi(int(h2["z"]) - hz) < w + 4: clash = true
		if clash: continue
		var cap_l := int(Data.KILL_CAP / Data.BLOCK_MIN)
		var deep_ok := true   # the floor follows the top of the cap under each cell; at least 30 m of rock over it
		for jz in w:
			for jx in w:
				var cc := (hz + jz) * n + hx + jx
				if _ktop(cc) < _kfloor(cc) + cap_l + hl + 6 or holes.has(cc): deep_ok = false
		if not deep_ok: continue
		# trunks on a jittered grid, 1-2 cells thick
		var trunk := {}
		for gz in range(0, w, sp):
			for gx in range(0, w, sp):
				var tx := clampi(gx + rng.randi_range(0, sp - 2), 0, w - 1)
				var tz := clampi(gz + rng.randi_range(0, sp - 2), 0, w - 1)
				trunk[Vector2i(tx, tz)] = true
				if rng.randf() < 0.5: trunk[Vector2i(mini(tx + 1, w - 1), tz)] = true
		var branch := {}   # layer -> cells: a branch joins neighbouring trunks at some height
		var tlist: Array = trunk.keys()
		for a in tlist:
			for b in tlist:
				var va: Vector2i = a
				var vb: Vector2i = b
				if va == vb or (va - vb).length() > sp * 1.6 or rng.randf() > 0.35: continue
				var k := rng.randi_range(2, hl - 2)   # (in layers over the hall floor)
				var steps := maxi(absi(vb.x - va.x), absi(vb.y - va.y))
				for q in steps + 1:
					var c2 := Vector2i(int(round(lerpf(va.x, vb.x, float(q) / maxf(steps, 1)))), int(round(lerpf(va.y, vb.y, float(q) / maxf(steps, 1)))))
					var kk := k + int(round(float(q) / maxf(steps, 1) * rng.randi_range(-2, 2)))   # branches slant
					branch[Vector3i(c2.x, c2.y, clampi(kk, 1, hl - 1))] = true
		var lava := 0
		var trunks: Array = []
		var k0s := {}
		for jz in w:
			for jx in w:
				var c := (hz + jz) * n + hx + jx
				_split_one(c)
				var ov: Dictionary = mats.get(c, {})
				var is_trunk: bool = trunk.has(Vector2i(jx, jz))
				if is_trunk: trunks.append(c)
				var k0 := _kfloor(c) + cap_l
				k0s[c] = k0
				for k in range(k0, k0 + hl):
					if is_trunk or branch.has(Vector3i(jx, jz, k - k0)):
						ov[k] = "obsidian"
					else:
						_cell_remove(c, k)
				ov[k0 - 1] = "obsidian"
				mats[c] = ov
				reach_bonus[c] = maxi(int(reach_bonus.get(c, 0)), sp)   # the roof hangs from the trunks
				_mark(jx + hx, jz + hz, 1)
		for c in k0s:   # lava pools on the floor between the roots, only in the low spots (so they lie still)
			if trunk.has(Vector2i(int(c) % n - hx, int(c) / n - hz)) or rng.randf() >= Data.HALL_LAVA: continue
			var low := true
			for d in [1, -1, n, -n]:
				if k0s.has(int(c) + d) and int(k0s[int(c) + d]) < int(k0s[c]): low = false
			if not low: continue
			var fd: Dictionary = fluid.get(c, {})
			fd[int(k0s[c])] = "lava"
			fluid[c] = fd
			lava += 1
		_settle(hx - 2, hx + w + 2, hz - 2, hz + w + 2)
		halls.append({"x": hx, "z": hz, "w": w, "k0s": k0s, "layers": hl, "trunks": trunks, "lava": lava})
	collapses = 0

## Obsidian roots piercing the surface (v1.6f): small crowns of black glass standing out of the ground (joined, so the
## skin points them into shards), each with its root running straight down into the deep rock: they show where the
## root system, the lava and the treasure are.
@warning_ignore("integer_division")
func _raise_roots() -> void:
	roots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_sk + "|roots")
	var step: float = Data.BLOCK_MIN
	var tries := 0
	var want := _scaled(Data.ROOT_COUNT, rng)
	while roots.size() < want and tries < 60:
		tries += 1
		var cx := rng.randi_range(6, n - 9)
		var cz := rng.randi_range(6, n - 9)
		if Vector2(cx - n / 2, cz - n / 2).length() < 14: continue
		var cells: Array = []
		var shape := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)]
		var count := rng.randi_range(2, shape.size())
		var bad := false
		for q in count:
			var c: int = (cz + shape[q].y) * n + cx + shape[q].x
			if holes.has(c) or fluid.has(c): bad = true
			cells.append(c)
		if bad: continue
		var tip := -1
		var tallest := -INF
		for c in cells:
			_split_one(c)
			var rise: float = ceilf(rng.randf_range(float(Data.ROOT_RISE[0]), float(Data.ROOT_RISE[1])) / step) * step
			var k_ground := _ktop(c)
			h[c] = h[c] + rise
			var ov: Dictionary = mats.get(c, {})
			for k in range(maxi(_kfloor(c), k_ground - int(Data.ROOT_DEPTH / step)), _ktop(c)): ov[k] = "obsidian"   # the root, down into the rock
			mats[c] = ov
			hmax = maxf(hmax, h[c])
			if h[c] > tallest:
				tallest = h[c]
				tip = c
			_mark(c % n, c / n, 1)
		roots.append({"cells": cells, "tip": tip})

## The kill floor (v1.6d): the bottom of the diggable ground (BLOCK_DEPTH_FLOOR down), under a thick obsidian cap.
## Where it's been dug open it glows; anything that reaches it is gone, and the ship is destroyed.
func kill_y(x: float, z: float) -> float:
	if not covers(x, z): return -INF
	var step: float = Data.BLOCK_MIN
	var c := clampi(int((z - z0) / step), 0, n - 1) * n + clampi(int((x - x0) / step), 0, n - 1)
	return y0 + _kfloor(c) * step

func touches_kill(p: Vector3, reach := 1.0) -> bool:
	var ky := kill_y(p.x, p.z)
	return ky > -INF and p.y < ky + reach

func _pocket_open(pk: Dictionary) -> bool:
	for c in pk["cells"]:
		for k in [int(pk["k0"]), int(pk["k0"]) + 1]:
			for nb in _nbrs6(c, k):
				if _air(nb.x, nb.y): return true
	return false

## The 6 neighbours of a layer: 4 sides, below, above ([Vector2i(cell, layer)]; off the patch left out).
@warning_ignore("integer_division")
func _nbrs6(c: int, k: int) -> Array:
	var out: Array = [Vector2i(c, k - 1), Vector2i(c, k + 1)]
	var fx := c % n
	var fz := c / n
	if fx > 0: out.append(Vector2i(c - 1, k))
	if fx < n - 1: out.append(Vector2i(c + 1, k))
	if fz > 0: out.append(Vector2i(c - n, k))
	if fz < n - 1: out.append(Vector2i(c + n, k))
	return out

func _fluid_k(c: int, k: int) -> String:
	return str((fluid.get(c, {}) as Dictionary).get(k, ""))

## Open air (not rock, not water or lava) at a layer.
func _air(c: int, k: int) -> bool:
	if k < _kfloor(c): return false
	return not _solid_k(c, k) and _fluid_k(c, k) == ""

func fluid_at(x: float, y: float, z: float) -> String:
	if not covers(x, z): return ""
	var step: float = Data.BLOCK_MIN
	var c := clampi(int((z - z0) / step), 0, n - 1) * n + clampi(int((x - x0) / step), 0, n - 1)
	return _fluid_k(c, _k(y))

func _set_fluid(c: int, k: int, kind: String) -> void:
	var fd: Dictionary = fluid.get(c, {})
	if kind == "": fd.erase(k)
	else: fd[k] = kind
	if fd.is_empty(): fluid.erase(c)
	else: fluid[c] = fd
	_fluid_dirty = true

## Called by the game each frame with the player's position: water and lava only move near the player (the radius of
## exposure); everywhere else, and in every sealed pocket, they sit still and cost nothing.
func fluid_update(dt: float, near: Vector3) -> void:
	if not burning.is_empty(): _fire_update(dt, near)
	_fluid_t += dt
	if _fluid_t >= Data.FLUID_TICK:
		_fluid_t = 0.0
		_fluid_tick += 1
		fluid_step(near, Data.FLUID_RADIUS, _fluid_tick % Data.LAVA_SLOW == 0)
	if _fluid_dirty: _draw_fluids()

## One step of flow: each unit (one 5 m layer of water or lava) falls if it can; otherwise it spills sideways over a
## lip, or spreads when there is more on top of it, so a pool finds its level and fills flush. It reacts with what it
## touches: water turns sand to dirt; lava eats sand, trades one-for-one with dirt, is stopped by stone; lava meeting
## water turns to obsidian (the water is used up). Lava moves every LAVA_SLOW steps. Returns how many units moved.
@warning_ignore("integer_division")
func fluid_step(near: Vector3, radius: float, lava_too := true) -> int:
	var units: Array = []
	for c in fluid:
		var fx: int = int(c) % n
		var fz: int = int(c) / n
		if Vector2(x0 + (fx + 0.5) * Data.BLOCK_MIN - near.x, z0 + (fz + 0.5) * Data.BLOCK_MIN - near.z).length() > radius: continue
		for k in (fluid[c] as Dictionary):
			units.append(Vector3i(int(c), int(k), 0))
	units.sort_custom(func(a, b): return a.y < b.y)   # lowest first, so falls cascade
	var moved := 0
	for u in units:
		if moved >= Data.FLUID_MAX_MOVES: break
		var c: int = u.x
		var k: int = u.y
		var kind := _fluid_k(c, k)
		if kind == "" or (kind == "lava" and not lava_too): continue
		if _react(c, k, kind): continue
		if k <= _kfloor(c):   # v1.6d: it reached the kill floor: gone
			_set_fluid(c, k, "")
			killed += 1
			continue
		if _air(c, k - 1):
			_set_fluid(c, k, "")
			_set_fluid(c, k - 1, kind)
			moved += 1
			continue
		var pressed := _fluid_k(c, k + 1) != ""
		for nb in _nbrs6(c, k).slice(2):
			var nc: int = (nb as Vector2i).x
			if not _air(nc, k): continue
			if _air(nc, k - 1) or pressed:
				_set_fluid(c, k, "")
				_set_fluid(nc, k, kind)
				moved += 1
				break
	fluid_moves += moved
	return moved

@warning_ignore("integer_division")
func _react(c: int, k: int, kind: String) -> bool:
	for nb in _nbrs6(c, k):
		var nc: int = (nb as Vector2i).x
		var nk: int = (nb as Vector2i).y
		var other := _fluid_k(nc, nk)
		if kind == "lava" and other == "water":   # they meet: obsidian where the lava was, the water is used up
			_set_fluid(nc, nk, "")
			_set_fluid(c, k, "")
			_edit_layer(_layer_point(c, k), "obsidian", true)
			reactions += 1
			return true
		if not _solid_k(nc, nk) or nk < _kfloor(nc): continue
		var m := mat_at(nc % n, nc / n, _ly(nk))
		if kind == "water" and m == "sand":   # wet sand clumps into dirt
			_edit_layer(_layer_point(nc, nk), "dirt", true)
			reactions += 1
			return false
		if kind == "lava" and (m == "wood" or Data.LEAF_COLORS.has(m)):   # v1.7i: lava sets wood and leaves alight
			ignite(nc, nk)
			continue
		if kind == "lava" and m == "sand":   # eaten for free
			_edit_layer(_layer_point(nc, nk), "", true)
			reactions += 1
			return false
		if kind == "lava" and m == "dirt":   # a trade: both go
			_edit_layer(_layer_point(nc, nk), "", true)
			_set_fluid(c, k, "")
			reactions += 1
			return true
	return false

@warning_ignore("integer_division")
func _layer_point(c: int, k: int) -> Vector3:
	return Vector3(x0 + (c % n + 0.5) * Data.BLOCK_MIN, _ly(k) - Data.BLOCK_MIN * 0.5, z0 + (c / n + 0.5) * Data.BLOCK_MIN)

## Change one layer of rock at a point: m = a material (it becomes solid that), "" = it's gone. With `record` the
## change is kept as a note ("set:<m>" / "cut"), so the ground regrows the same.
@warning_ignore("integer_division")
func _edit_layer(p: Vector3, m: String, record := false) -> void:
	if not covers(p.x, p.z): return
	var step: float = Data.BLOCK_MIN
	var fx := clampi(int((p.x - x0) / step), 0, n - 1)
	var fz := clampi(int((p.z - z0) / step), 0, n - 1)
	var c := fz * n + fx
	var k := _k(p.y)
	_split_one(c)
	if m == "":
		if _solid_k(c, k) and k >= _kfloor(c): _cell_remove(c, k)
	else:
		_set_fluid(c, k, "")
		if not _solid_k(c, k): _cell_add(c, k, m)
		else:
			var ov: Dictionary = mats.get(c, {})
			ov[k] = m
			mats[c] = ov
	_mark(fx, fz, 1)
	if m == "": _settle(fx - 2, fx + 2, fz - 2, fz + 2)
	if record:
		deltas.append([snappedf(p.x - off.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z - off.y, 0.01), ("set:" + m) if m != "" else "cut"])
		if deltas.size() > Data.BLOCK_DELTAS_MAX: deltas.remove_at(0)

## Water is clear and tinted blue, lava only a little see-through and glowing (see-through = it flows).
@warning_ignore("integer_division")
func _draw_fluids() -> void:
	_fluid_dirty = false
	var step: float = Data.BLOCK_MIN
	for kind in ["water", "lava"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var any := false
		var col: Color = Data.FLUID_COLOR[kind]
		for c in fluid:
			for k in (fluid[c] as Dictionary):
				if str(fluid[c][k]) != kind: continue
				any = true
				var ax: float = x0 + (int(c) % n) * step
				var az: float = z0 + (int(c) / n) * step
				var y_lo: float = y0 + int(k) * step
				var y_hi: float = y_lo + step
				if _fluid_k(int(c), int(k) + 1) != kind and not _solid_k(int(c), int(k) + 1):
					var ty := y_hi - 0.6
					_quad(st, Vector3(ax, ty, az), Vector3(ax + step, ty, az), Vector3(ax + step, ty, az + step), Vector3(ax, ty, az + step), [col, col, col, col], Vector3.UP)
				var sides := [[-n, Vector3(ax, 0, az), Vector3(ax + step, 0, az), Vector3.FORWARD], [1, Vector3(ax + step, 0, az), Vector3(ax + step, 0, az + step), Vector3.RIGHT],
					[n, Vector3(ax + step, 0, az + step), Vector3(ax, 0, az + step), Vector3.BACK], [-1, Vector3(ax, 0, az + step), Vector3(ax, 0, az), Vector3.LEFT]]
				for sd in sides:
					var nc: int = int(c) + int(sd[0])
					if nc < 0 or nc >= n * n: continue
					if absi(int(sd[0])) == 1 and nc / n != int(c) / n: continue
					if _fluid_k(nc, int(k)) == kind or _solid_k(nc, int(k)): continue
					var p0: Vector3 = sd[1]
					var p1: Vector3 = sd[2]
					var top_y: float = y_hi - (0.6 if _fluid_k(int(c), int(k) + 1) != kind else 0.0)
					_quad(st, Vector3(p0.x, top_y, p0.z), Vector3(p1.x, top_y, p1.z), Vector3(p1.x, y_lo, p1.z), Vector3(p0.x, y_lo, p0.z), [col, col, col, col], sd[3])
		var mi: MeshInstance3D = _fluid_mi.get(kind)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.name = "Fluid_" + kind
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.15
			if kind == "lava":
				m.emission_enabled = true
				m.emission = Color(1.0, 0.35, 0.05)
				m.emission_energy_multiplier = 1.6
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_fluid_mi[kind] = mi
		mi.position = Vector3.ZERO
		mi.mesh = st.commit() if any else null

## A shot from a to b: where it first goes into the block ground (or Vector3.INF).
func ray_hit(a: Vector3, b: Vector3) -> Vector3:
	if a.y > hmax + 1.0 and b.y > hmax + 1.0: return Vector3.INF
	var steps := maxi(1, ceili(a.distance_to(b) / 2.5))
	var prev := a
	for k in range(1, steps + 1):
		var q := a.lerp(b, float(k) / steps)
		if is_solid(q.x, q.y, q.z):
			var lo := prev
			var hi := q
			for it in 6:
				var mid := (lo + hi) * 0.5
				if is_solid(mid.x, mid.y, mid.z): hi = mid
				else: lo = mid
			return hi
		prev = q
	return Vector3.INF

@warning_ignore("integer_division")
func _mark(ox: int, oz: int, s: int) -> void:
	var c: int = chunk
	var nc := _nchunks()
	for z in [oz - 1, oz + s]:
		for x in [ox - 1, ox + s]:
			var cx := clampi(x, 0, n - 1) / c
			var cz := clampi(z, 0, n - 1) / c
			_dirty[cz * nc + cx] = true

func _nchunks() -> int:
	return ceili(float(n) / chunk)

# ---------------------------------------------------------------- rubble
## What a blast breaks flies out by material (Data.BLOCK_BREAK_PIECES): obsidian in 2 big halves, stone in 3, dirt in
## 4, sand in 5 smaller pieces. About half of it flies (BLOCK_RUBBLE_FRAC; obsidian always goes whole), at most
## BLOCK_RUBBLE_PER_BLAST pieces: bigger pieces from the edge of the blast, smaller ones from the middle.
func _throw(p: Vector3, r: float, out: Array) -> int:
	var cands: Array = []
	for o in out:
		if Data.VALUABLE_COLOR.has(o["mat"]): continue   # treasure doesn't turn to rubble: the game drops it as pickups
		var cnt: int = Data.BLOCK_BREAK_PIECES.get(o["mat"], 4)
		var keep: int = cnt if o["mat"] == "obsidian" else ceili(cnt * Data.BLOCK_RUBBLE_FRAC)
		for k in keep: cands.append(o)
	for i in range(cands.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	cands.sort_custom(func(a, b): return a["mat"] == "obsidian" and b["mat"] != "obsidian")   # obsidian first: it never turns to dust
	var nfly := mini(Data.BLOCK_RUBBLE_PER_BLAST, cands.size())
	for k in nfly:
		var o: Dictionary = cands[k]
		var m: String = o["mat"]
		var cnt: int = Data.BLOCK_BREAK_PIECES.get(m, 4)
		var share := pow(1.0 / cnt, 1.0 / 3.0)   # a piece's size from its share of the block
		var edge: bool = float(o["edge"]) > 0.6 or m == "obsidian"
		var sz: float = minf(float(o["size"]), 16.0 if m == "obsidian" else 10.0) * share * (1.0 if edge else 0.55)
		sz = maxf(sz, Data.BLOCK_MIN * 0.35)
		var pos: Vector3 = o["pos"]
		var away := Vector3(pos.x - p.x, 0.0, pos.z - p.z)
		if away.length() < 0.1: away = Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1))
		var vel := away.normalized() * _rng.randf_range(6.0, 18.0) * (1.0 + r / 40.0) + Vector3.UP * _rng.randf_range(14.0, 30.0)
		if edge: vel *= 0.6
		_piece(pos + Vector3.UP * Data.BLOCK_MIN * 0.5, sz, m, vel)
	return nfly

## One rubble piece. Obsidian pieces cleave in half once more when they land hard (Data.BLOCK_CLEAVE_SPEED).
func _piece(pos: Vector3, sz: float, m: String, vel: Vector3, cleave := true) -> void:
	if rubble.size() >= Data.BLOCK_RUBBLE_LIVE:
		var old: Dictionary = rubble.pop_front()
		if is_instance_valid(old["node"]): (old["node"] as Node).queue_free()
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = _box
	mi.material_override = _piece_mat(m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(sz, sz * _rng.randf_range(0.6, 1.0), sz * _rng.randf_range(0.7, 1.1))
	mi.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	mi.name = "Rubble"
	add_child(mi)
	mi.position = pos
	rubble.append({"node": mi, "vel": vel, "spin": Vector3(_rng.randfn(0, 3), _rng.randfn(0, 3), _rng.randfn(0, 3)), "rest": -1.0, "half": sz * 0.4,
		"mat": m, "size": sz, "cleave": cleave and m == "obsidian"})
	thrown += 1

func _piece_mat(m: String) -> StandardMaterial3D:
	if _mats.has(m): return _mats[m]
	var mt := StandardMaterial3D.new()
	mt.albedo_color = tone(m)
	mt.roughness = 0.9
	_mats[m] = mt
	return mt

func _process(dt: float) -> void:
	for i in range(rubble.size() - 1, -1, -1):
		var b: Dictionary = rubble[i]
		var nd := b["node"] as MeshInstance3D
		if not is_instance_valid(nd):
			rubble.remove_at(i)
			continue
		var g := ground_for(nd.position.x, nd.position.y - float(b["half"]), nd.position.z)
		if float(b["rest"]) < 0.0:
			if b.get("mat", "") == "dirt" and g != -INF:
				var ahead: Vector3 = nd.position + (b["vel"] as Vector3) * dt + Vector3((b["vel"] as Vector3).x, 0, (b["vel"] as Vector3).z).normalized() * float(b["half"])
				if is_solid(ahead.x, nd.position.y, ahead.z) and not is_solid(nd.position.x, nd.position.y, nd.position.z):
					_merge_piece(b, nd.position.y)   # dirt sticks to the wall it hits
					rubble.remove_at(i)
					continue
			b["vel"] = (b["vel"] as Vector3) + Vector3.DOWN * 30.0 * dt
			nd.position += (b["vel"] as Vector3) * dt
			nd.rotation += (b["spin"] as Vector3) * dt
			if g == -INF and nd.position.y < hmax - 400.0:   # fell off the patch: gone
				nd.queue_free()
				rubble.remove_at(i)
			elif nd.position.y - float(b["half"]) <= g and absf(g - kill_y(nd.position.x, nd.position.z)) < 0.01:
				nd.queue_free()   # v1.6d: it fell onto the kill floor: gone
				rubble.remove_at(i)
				killed += 1
				continue
			elif nd.position.y - float(b["half"]) <= g:
				nd.position.y = g + float(b["half"])
				b["rest"] = 0.0
				if b.get("cleave", false) and -(b["vel"] as Vector3).y > Data.BLOCK_CLEAVE_SPEED:   # brittle glass: a hard landing splits it in two
					var at := nd.position
					var hsz := float(b["size"]) * 0.79
					var side := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized() * 5.0
					nd.queue_free()
					rubble.remove_at(i)
					cleaved += 1
					_piece(at + side * 0.3, hsz, "obsidian", side + Vector3.UP * 6.0, false)
					_piece(at - side * 0.3, hsz, "obsidian", -side + Vector3.UP * 6.0, false)
					continue
		else:
			b["rest"] = float(b["rest"]) + dt
			if g != -INF and g < nd.position.y - float(b["half"]) - 1.0:   # the ground under it was blown away: it falls again
				b["rest"] = -1.0
				b["vel"] = Vector3.ZERO
			elif float(b["rest"]) > Data.BLOCK_MERGE_DELAY and g != -INF:   # v1.5z: it settles into the ground, as its own material
				_merge_piece(b, g + 0.1)
				rubble.remove_at(i)
			elif float(b["rest"]) > Data.BLOCK_RUBBLE_REST:
				nd.position.y -= dt * 2.0
				if float(b["rest"]) > Data.BLOCK_RUBBLE_REST + 3.0:
					nd.queue_free()
					rubble.remove_at(i)
	if not _dirty.is_empty(): flush(2)

# ---------------------------------------------------------------- drawing
## Redraw the squares that changed (at most `limit` per call; 0 = all). The ground is one fused surface: same-height
## neighbours share one flat face with no seam; a wall appears only where the ground steps. Untouched ground keeps its
## own blended colours; dug ground shows the tone of the layer that is now on top; walls show the layers they cut.
const GROUND_SHADER := """shader_type spatial;
render_mode cull_disabled;
varying float sky;
varying float glow;
varying float gloss;
void vertex() {
	sky = COLOR.a;
	glow = UV.x;
	gloss = UV.y;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = mix(0.9, 0.3, gloss);
	AO = sky;
	AO_LIGHT_AFFECT = 0.0;
	EMISSION = COLOR.rgb * glow;
}
void light() {
	float k = LIGHT_IS_DIRECTIONAL ? sky : 1.0;
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += k * nl * ATTENUATION * LIGHT_COLOR / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += k * gloss * pow(clamp(dot(NORMAL, hv), 0.0, 1.0), 40.0) * nl * ATTENUATION * LIGHT_COLOR * 0.35;
}"""

## v1.7m: the glowing things in this field near a point (for the few real lights): [[position, kind]], at most one per
## ~15 m: lava, fire, gold and diamond with air beside them, the kill floor where it is dug open.
@warning_ignore("integer_division")
func glow_points(near: Vector3, reach: float) -> Array:
	var out: Array = []
	var taken := {}
	var add := func(pt: Vector3, kind: String) -> void:
		if Vector2(pt.x - near.x, pt.z - near.z).length() > reach or absf(pt.y - near.y) > reach: return
		var key := Vector3i(int(floor(pt.x / 15.0)), int(floor(pt.y / 15.0)), int(floor(pt.z / 15.0)))
		if taken.has(key): return
		taken[key] = true
		out.append([pt, kind])
	for kv in burning: add.call(_layer_point((kv as Vector2i).x, (kv as Vector2i).y), "fire")
	for c in fluid:
		var d: Dictionary = fluid[c]
		for k in d:
			if d[k] == "lava": add.call(_layer_point(int(c), int(k)), "lava")
	for v in veins:
		for ck in v["cells"]:
			var c2: int = (ck as Vector2i).x
			var k2: int = (ck as Vector2i).y
			if not _solid_k(c2, k2): continue
			var open := false
			for nb in _nbrs6(c2, k2):
				if not _solid_k((nb as Vector2i).x, (nb as Vector2i).y): open = true
			if open: add.call(_layer_point(c2, k2), str(v["mat"]))
	var step: float = Data.BLOCK_MIN
	var fx := int((near.x - x0) / step)
	var fz := int((near.z - z0) / step)
	var rr := int(reach / step)
	for z in range(maxi(0, fz - rr), mini(n, fz + rr + 1), 2):
		for x in range(maxi(0, fx - rr), mini(n, fx + rr + 1), 2):
			var c3 := z * n + x
			if _ktop(c3) <= _kfloor(c3) + 1: add.call(Vector3(x0 + (x + 0.5) * step, h[c3] + 2.0, z0 + (z + 0.5) * step), "kill")
	return out

## v1.7m: set how the next faces glow and shine (their material's own light and gloss).
func _look(st: SurfaceTool, m: String) -> void:
	st.set_uv(Vector2(float(Data.BLOCK_GLOW.get(m, 0.0)), float(Data.BLOCK_GLOSS.get(m, 0.0))))

func _sky(cs: Array, covered: bool) -> Array:
	var out: Array = []
	for c in cs: out.append(Color((c as Color).r, (c as Color).g, (c as Color).b, Data.CAVE_DARK if covered else 1.0))
	return out

var _slant_cache := {}
func flush(limit := 0) -> void:
	if not slabs.is_empty(): _slab_check()
	if not falls.is_empty(): _falls_check()
	var done := 0
	for k in _dirty.keys():
		_draw_chunk(int(k))
		_dirty.erase(k)
		done += 1
		if limit > 0 and done >= limit: break

@warning_ignore("integer_division")
func _draw_chunk(k: int) -> void:
	_slant_cache.clear()   # (the ground may have changed since the last chunk)
	var c: int = chunk
	var nc := _nchunks()
	var ci := k % nc
	var cj := k / nc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Vector2.ZERO)   # (v1.7m: every face carries its glow / gloss)
	_kill_st = SurfaceTool.new()
	_kill_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_kill_any = false
	var any := false
	for fz in range(cj * c, mini((cj + 1) * c, n)):
		for fx in range(ci * c, mini((ci + 1) * c, n)):
			var s: int = lsz[fz * n + fx]
			if fx % s != 0 or fz % s != 0: continue
			_draw_block(st, fx, fz, s)
			any = true
	var mi: MeshInstance3D = _chunks.get(k)
	if mi == null:
		if _ground_mat == null:   # v1.7m: vertex colour alpha = how much sun / sky reaches it; uv.x = its own glow, uv.y = gloss
			_ground_mat = ShaderMaterial.new()
			var sh := Shader.new()
			sh.code = GROUND_SHADER
			_ground_mat.shader = sh
		mi = MeshInstance3D.new()
		mi.name = "Ground%d" % k
		mi.material_override = _ground_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks[k] = mi
	mi.position = Vector3.ZERO   # (after a reframe the old mesh was slid; a fresh one is drawn in place)
	mi.mesh = st.commit() if any else null
	var km: MeshInstance3D = mi.get_node_or_null("Kill")
	if _kill_any:
		if km == null:
			km = MeshInstance3D.new()
			km.name = "Kill"
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.vertex_color_use_as_albedo = true
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			km.material_override = m
			km.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_child(km)
		km.mesh = _kill_st.commit()
	elif km != null: km.mesh = null

@warning_ignore("integer_division")
func _draw_block(st: SurfaceTool, ox: int, oz: int, s: int) -> void:
	var step: float = Data.BLOCK_MIN
	var i0 := oz * n + ox
	var top: float = h[i0]
	var ax := x0 + ox * step
	var az := z0 + oz * step
	var bx := ax + s * step
	var bz := az + s * step
	var cfx := ox + s / 2
	var cfz := oz + s / 2
	var untouched: bool = top >= h0[i0] - 0.01 and not (mats.get(i0, {}) as Dictionary).has(_ktop(i0) - 1)
	var n1 := n + 1
	var sp := spans(i0)
	var dl: Dictionary = dmg.get(i0, {})
	var jit := 0.95 + float(absi(hash(i0)) % 100) / 1000.0
	# v1.6a the skin (the owner's "hypernerve"): only the look changes, collision stays square. Where the top steps down
	# on a side, sand eases into a soft blunt mound, dirt and stone get a rounded edge; obsidian joined to obsidian
	# crisps up into a pointed shard tip. A lone obsidian block stays a block.
	var tm := mat_at(cfx, cfz, top)
	var edge := [false, false, false, false]
	var any_edge := false
	for side in 4:
		edge[side] = _side_lower(side, ox, oz, s, top)
		any_edge = any_edge or edge[side]
	var skin: Array = Data.BLOCK_SKIN.get(tm, [0.0, 0.0])
	var inset: float = minf(float(skin[0]), s * step * 0.42)
	var drop: float = float(skin[1]) if any_edge else 0.0
	var vh := _slant(ox, oz, s, top, tm, untouched, edge)   # v1.7e: the top's corner heights if it leans ([] if square)
	var slo := _slab_lo(i0)   # v1.7f: part of a whole leaning slab: above this the slab is drawn, not blocks
	if not vh.is_empty(): drop = 0.0
	var shard := Vector3.ZERO   # the shard's lean (away from the obsidian it is joined to)
	var fused := false
	if tm == "obsidian" and any_edge:
		for side in 4:
			var c := _nb_cell(side, ox, oz, s, 0)
			if c >= 0 and h[c] >= top - step - 0.01 and mat_point(x0 + (c % n + 0.5) * step, h[c] - step * 0.5, z0 + (c / n + 0.5) * step) == "obsidian":
				fused = true
				shard -= [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT][side]
	for j in sp.size():
		var o: Vector2i = sp[j]
		var ty: float = y0 + o.y * step
		var cs: Array
		if j == sp.size() - 1 and untouched:
			cs = [ccol[oz * n1 + ox], ccol[oz * n1 + ox + s], ccol[(oz + s) * n1 + ox + s], ccol[(oz + s) * n1 + ox]]
		else:
			var tc := tone(mat_at(cfx, cfz, ty)) * jit
			cs = [tc, tc, tc, tc]
		var dd: int = int(dl.get(o.y - 1, 0))
		if dd > 0:   # cracked: darker the closer it is to breaking
			var f: float = Data.BLOCK_DAMAGE_DARK * float(dd) / float(Data.BLOCK_HITS.get(mat_at(cfx, cfz, ty), 1))
			for q in 4: cs[q] = (cs[q] as Color).lerp(Color.BLACK, f)
		cs = _sky(cs, j < sp.size() - 1)   # v1.7m: a floor under a roof (a cave, a tunnel) is out of the sun
		_look(st, "" if (j == sp.size() - 1 and untouched) else mat_at(cfx, cfz, ty))
		if slo < INF and ty > slo + 0.01:
			pass   # (the slab's own top: drawn as the slab)
		elif j == 0 and o.y <= _kfloor(i0):   # the kill floor, dug open: it blazes (a warning you see from far above)
			var kc: Color = Data.KILL_COLOR
			_quad(_kill_st, Vector3(ax, ty, az), Vector3(bx, ty, az), Vector3(bx, ty, bz), Vector3(ax, ty, bz), [kc, kc, kc, kc], Vector3.UP)
			_kill_any = true
		elif j == sp.size() - 1 and not vh.is_empty():
			_slant_top(st, ax, az, bx, bz, vh, cs)
		elif j == sp.size() - 1 and (drop > 0.0 or fused):
			_skin_top(st, ax, az, bx, bz, ty, edge, inset, drop, cs, fused, shard, s * step)
		else:
			_quad(st, Vector3(ax, ty, az), Vector3(bx, ty, az), Vector3(bx, ty, bz), Vector3(ax, ty, bz), cs, Vector3.UP)
		if j > 0 and not (slo < INF and y0 + o.x * step >= slo - step - 0.01):   # the roof of a hole under it (a tunnel or cave ceiling)
			var by: float = y0 + o.x * step
			var rm := mat_at(cfx, cfz, _ly(o.x))
			var cc0 := tone(rm).lerp(Color.BLACK, 0.4)
			var cc := Color(cc0.r, cc0.g, cc0.b, Data.CAVE_DARK)   # (a roof is always out of the sun)
			_look(st, rm)
			_quad(st, Vector3(ax, by, az), Vector3(ax, by, bz), Vector3(bx, by, bz), Vector3(bx, by, az), [cc, cc, cc, cc], Vector3.DOWN)
	var surf: Color = ccol[cfz * n1 + cfx]
	var corners := [Vector3(ax, 0, az), Vector3(bx, 0, az), Vector3(bx, 0, bz), Vector3(ax, 0, bz), Vector3(ax, 0, az)]
	var normals := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for side in 4:
		var open := false   # v1.7q: a side against solid ground at least as high, with no holes, has no wall at all: skip it
		for kq in s:
			var cq := _nb_cell(side, ox, oz, s, kq)
			if cq < 0 or holes.has(cq) or h[cq] < top - 0.01:
				open = true
				break
		if not open: continue
		var k := 0
		while k < s:
			var key = _nb_key(side, ox, oz, s, k)
			var k2 := k + 1
			while k2 < s and _nb_key(side, ox, oz, s, k2) == key: k2 += 1
			var air := _air_iv(_nb_cell(side, ox, oz, s, k), top)
			var p0: Vector3 = (corners[side] as Vector3).lerp(corners[side + 1], float(k) / s)
			var p1: Vector3 = (corners[side] as Vector3).lerp(corners[side + 1], float(k2) / s)
			for o in sp:
				var lo: float = -INF if (o as Vector2i).x <= -1000 else y0 + (o as Vector2i).x * step
				var hi: float = y0 + (o as Vector2i).y * step
				if slo < INF:   # (v1.7f: the slab is drawn above this)
					if lo >= slo - step - 0.01: continue
					hi = minf(hi, slo)
				var lean := not vh.is_empty() and absf(hi - top) < 0.01
				var e0 := 0.0
				var e1 := 0.0
				if lean:   # v1.7e: this side's top edge slopes: the wall stops under it and a sliver fills up to it
					var ha: float = lerpf(vh[side], vh[(side + 1) % 4], float(k) / s)
					var hb: float = lerpf(vh[side], vh[(side + 1) % 4], float(k2) / s)
					hi = minf(ha, hb)
					e0 = ha
					e1 = hb
				if absf(hi - top) < 0.01 and edge[side]: hi -= drop   # the skin rounds the top edge off
				for A in air:
					var wl := maxf(lo, (A as Vector2).x)
					var wh := minf(hi, (A as Vector2).y)
					if wh > wl + 0.01: _wall(st, p0, p1, wh, wl, cfx, cfz, untouched and (absf(wh - top) < 0.01 or lean), surf, normals[side], (A as Vector2).y < INF)
				if lean and edge[side] and maxf(e0, e1) > hi + 0.01:
					var sc0: Color = surf * 0.92
					var sc := Color(sc0.r, sc0.g, sc0.b, 1.0)
					_look(st, "")
					_quad(st, Vector3(p0.x, e0, p0.z), Vector3(p1.x, e1, p1.z), Vector3(p1.x, hi, p1.z), Vector3(p0.x, hi, p0.z), [sc, sc, sc, sc], normals[side])
			k = k2

## Does the ground drop away along this whole side of a block?
func _side_lower(side: int, ox: int, oz: int, s: int, top: float) -> bool:
	for k in s:
		var c := _nb_cell(side, ox, oz, s, k)
		if c >= 0 and h[c] >= top - 0.01: return false
	return true

## The skinned top of a block: a plateau inset on the sides that drop away, sloping down to the edge (cs = the colours
## at the four corners NW, NE, SE, SW). A fused obsidian top becomes a faceted point instead of the flat plateau.
func _skin_top(st: SurfaceTool, ax: float, az: float, bx: float, bz: float, ty: float, edge: Array, inset: float, drop: float, cs: Array, fused: bool, lean: Vector3, size: float) -> void:
	var e0: float = inset if edge[0] else 0.0
	var e1: float = inset if edge[1] else 0.0
	var e2: float = inset if edge[2] else 0.0
	var e3: float = inset if edge[3] else 0.0
	var inner := [Vector3(ax + e3, ty, az + e0), Vector3(bx - e1, ty, az + e0), Vector3(bx - e1, ty, bz - e2), Vector3(ax + e3, ty, bz - e2)]
	var outer := [Vector3(ax, ty - (drop if edge[0] or edge[3] else 0.0), az), Vector3(bx, ty - (drop if edge[0] or edge[1] else 0.0), az),
		Vector3(bx, ty - (drop if edge[1] or edge[2] else 0.0), bz), Vector3(ax, ty - (drop if edge[2] or edge[3] else 0.0), bz)]
	if fused:
		var mid: Vector3 = (inner[0] + inner[2]) * 0.5
		if lean.length() > 0.01: mid += lean.normalized() * size * 0.3
		var apex: Vector3 = mid + Vector3.UP * minf(size * 0.8, Data.BLOCK_SHARD_HEIGHT)
		var gl := (cs[0] as Color).lightened(0.18)   # glossy black glass
		for q in 4:
			var a: Vector3 = inner[q]
			var b: Vector3 = inner[(q + 1) % 4]
			var nrm := (b - a).cross(apex - a).normalized()
			if nrm.y < 0.0: nrm = -nrm
			for v in [a, apex, b]:
				st.set_normal(nrm)
				st.set_color(gl if v == apex else cs[q])
				st.add_vertex(v)
	else:
		_quad(st, inner[0], inner[1], inner[2], inner[3], cs, Vector3.UP)
	for q in 4:
		var a2: Vector3 = inner[q]
		var b2: Vector3 = inner[(q + 1) % 4]
		var c2: Vector3 = outer[(q + 1) % 4]
		var d2: Vector3 = outer[q]
		if a2.distance_to(d2) < 0.01 and b2.distance_to(c2) < 0.01: continue
		var n2 := (b2 - a2).cross(d2 - a2)
		if n2.length() < 0.0001: n2 = (c2 - b2).cross(a2 - b2)
		n2 = n2.normalized()
		if n2.y < 0.0: n2 = -n2
		var c3: Color = (cs[q] as Color) * 0.93
		var c4: Color = (cs[(q + 1) % 4] as Color) * 0.93
		_quad(st, a2, b2, c2, d2, [cs[q], cs[(q + 1) % 4], c4, c3], n2)

## v1.7e: does this natural top lean, and how? Returns its four corner heights (NW, NE, SE, SW) or [] for a square
## top. Worked out per corner from the four cells that touch it, the same way for every block sharing that corner,
## so neighbouring slabs always meet edge to edge (no cracks): a corner drops when something round it is lower and
## nothing round it is higher, down to the highest lower one (at most BLOCK_SLANT_MAX), and only if every block at
## its height there may lean (whole untouched big blocks of sand, dirt or stone with whole big blocks round them).
func _slant(ox: int, oz: int, s: int, top: float, _tm: String, _untouched: bool, _edge: Array) -> Array:
	if not _slant_ok(oz * n + ox): return []
	var vh := []
	var any := false
	for q in 4:
		var vx: int = ox + (s if q == 1 or q == 2 else 0)
		var vz: int = oz + (s if q >= 2 else 0)
		var v := _corner_h(vx, vz, top)
		vh.append(v)
		any = any or v < top - 0.01
	return vh if any else []

var _pox := 0.0
var _poz := 0.0
var _slant_noise: FastNoiseLite
## The height a top at `top` takes at grid corner (vx, vz) (see _slant).
func _corner_h(vx: int, vz: int, top: float) -> float:
	if _slant_noise == null or _slant_noise.get_noise_2d(_pox + x0 + vx * Data.BLOCK_MIN, _poz + z0 + vz * Data.BLOCK_MIN) < Data.BLOCK_SLANT_ZONE: return top   # (v1.7g: square steps outside the slant patches)
	var lmax := -INF
	for c: Vector2i in [Vector2i(vx - 1, vz - 1), Vector2i(vx, vz - 1), Vector2i(vx - 1, vz), Vector2i(vx, vz)]:
		if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n: return top
		var i := c.y * n + c.x
		var hc: float = h[i]
		if hc > top + 0.01: return top
		if hc >= top - 0.01:
			if not _slant_ok(i): return top
		else:
			if holes.has(i): return top
			lmax = maxf(lmax, hc)
	if lmax == -INF: return top
	return maxf(top - Data.BLOCK_SLANT_MAX, lmax)

## May the block holding cell i lean? (cached per redraw)
@warning_ignore("integer_division")
func _slant_ok(i: int) -> bool:
	if _slant_cache.has(i): return _slant_cache[i]
	var ok := true
	var s: int = lsz[i]
	var fx := i % n
	var fz := i / n
	var ox := fx - fx % s
	var oz := fz - fz % s
	var i0 := oz * n + ox
	var top: float = h[i0]
	if s != R or holes.has(i0) or top < h0[i0] - 0.01 or (mats.get(i0, {}) as Dictionary).has(_ktop(i0) - 1) or not ["sand", "dirt", "stone"].has(mat_at(ox + s / 2, oz + s / 2, top)):
		ok = false
	else:
		for side in 4:
			for k in s:
				var c := _nb_cell(side, ox, oz, s, k)
				if c >= 0 and int(lsz[c]) != R:
					ok = false
					break
			if not ok: break
	_slant_cache[i] = ok
	return ok

## The cell diagonally outside corner q (NW, NE, SE, SW) of a block (-1 outside the patch).
func _corner_cell(q: int, ox: int, oz: int, s: int) -> int:
	var x: int = [ox - 1, ox + s, ox + s, ox - 1][q]
	var z: int = [oz - 1, oz - 1, oz + s, oz + s][q]
	if x < 0 or z < 0 or x >= n or z >= n: return -1
	return z * n + x

## A leaning top: two triangles creased along the steeper diagonal, so a corner dropped on its own makes a wedge.
func _slant_top(st: SurfaceTool, ax: float, az: float, bx: float, bz: float, vh: Array, cs: Array) -> void:
	var v := [Vector3(ax, vh[0], az), Vector3(bx, vh[1], az), Vector3(bx, vh[2], bz), Vector3(ax, vh[3], bz)]
	var tris := [[0, 1, 2], [0, 2, 3]] if absf(float(vh[0]) - float(vh[2])) >= absf(float(vh[1]) - float(vh[3])) else [[0, 1, 3], [1, 2, 3]]
	for t in tris:
		var a: Vector3 = v[t[0]]
		var b: Vector3 = v[t[1]]
		var c: Vector3 = v[t[2]]
		var nrm := (b - a).cross(c - a).normalized()
		if nrm.y < 0.0: nrm = -nrm
		for q in t:
			st.set_normal(nrm)
			st.set_color(cs[q])
			st.add_vertex(v[q])

## The cell next to a block's side (-1 outside the patch).
func _nb_cell(side: int, ox: int, oz: int, s: int, k: int) -> int:
	var x := 0
	var z := 0
	match side:
		0:
			x = ox + k
			z = oz - 1
		1:
			x = ox + s
			z = oz + k
		2:
			x = ox + s - 1 - k
			z = oz + s
		_:
			x = ox - 1
			z = oz + s - 1 - k
	if x < 0 or z < 0 or x >= n or z >= n: return -1
	return z * n + x

func _nb_key(side: int, ox: int, oz: int, s: int, k: int) -> float:
	var c := _nb_cell(side, ox, oz, s, k)
	if c < 0: return -1e9
	if not holes.has(c): return h[c]
	return h[c] + 100000.0 * float(1 + absi(hash(holes[c])) % 100000)   # (v1.7q: a number, not a string: same grouping, much cheaper)

## Where the neighbouring cell is open (air), as height ranges [Vector2(lo, hi)]: its holes, and above its top.
## Outside the patch: open down to the skirt (it hides the sunk smooth sheet).
func _air_iv(c: int, top: float) -> Array:
	if c < 0: return [Vector2(top - Data.BLOCK_SKIRT, INF)]
	var out: Array = []
	for hv in holes.get(c, []):
		out.append(Vector2(y0 + (hv as Vector2i).x * Data.BLOCK_MIN, y0 + (hv as Vector2i).y * Data.BLOCK_MIN))
	out.append(Vector2(h[c], INF))
	return out

## A wall from the block's top down to `low`, in bands by the layers it cuts (same-material layers merged).
func _wall(st: SurfaceTool, p0: Vector3, p1: Vector3, top: float, low: float, cfx: int, cfz: int, untouched: bool, surf: Color, nrm: Vector3, covered := false) -> void:
	var step: float = Data.BLOCK_MIN
	var ground: float = h0[cfz * n + cfx]
	var y := top
	var first := true
	while y > low + 0.01:
		var col: Color
		var y_end: float
		var first_band := first
		if first and untouched:   # the grass cap (v1.7g: a thin band, the planet's colour; the rock shows below it)
			col = surf * 0.92
			y_end = maxf(low, y - Data.BLOCK_GRASS_BAND)
		else:
			var m := mat_at(cfx, cfz, y)
			y_end = y - step
			while y_end > low + 0.01 and mat_at(cfx, cfz, y_end) == m: y_end -= step
			y_end = maxf(y_end, low)
			col = tone(m)
		first = false
		var ct := col.lerp(Color.BLACK, clampf((ground - y) / 250.0, 0.0, 0.35))
		var cb := col.lerp(Color.BLACK, clampf((ground - y_end) / 250.0, 0.0, 0.35) + 0.08)
		var a := Data.CAVE_DARK if covered else 1.0   # v1.7m: a wall facing into a hole is out of the sun
		ct.a = a
		cb.a = a
		_look(st, "" if (first_band and untouched) else mat_at(cfx, cfz, y - 0.01))
		_quad(st, Vector3(p0.x, y, p0.z), Vector3(p1.x, y, p1.z), Vector3(p1.x, y_end, p1.z), Vector3(p0.x, y_end, p0.z), [ct, ct, cb, cb], nrm)
		y = y_end

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, cs: Array, nrm: Vector3) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_color(cs[k])
		st.add_vertex([a, b, c, d][k])

## Is a tile-local point over the patch?
func covers(x: float, z: float) -> bool:
	var half := cols * Data.BLOCK_BIG * 0.5
	return absf(x - center.x) < half and absf(z - center.y) < half

## The material of the top layer of the block under a tile-local point ("" off the patch).
@warning_ignore("integer_division")
func mat_top(x: float, z: float) -> String:
	if not covers(x, z): return ""
	var step: float = Data.BLOCK_MIN
	var fx := clampi(int((x - x0) / step), 0, n - 1)
	var fz := clampi(int((z - z0) / step), 0, n - 1)
	var s: int = lsz[fz * n + fx]
	var ox := fx - fx % s
	var oz := fz - fz % s
	return mat_at(ox + s / 2, oz + s / 2, h[oz * n + ox])

## The block ground under a tile-local point (or -INF off the patch).
func top_at(x: float, z: float) -> float:
	if not covers(x, z): return -INF
	var step: float = Data.BLOCK_MIN
	var fx := clampi(int((x - x0) / step), 0, n - 1)
	var fz := clampi(int((z - z0) / step), 0, n - 1)
	return h[fz * n + fx]

## What gets kept: the seed (the planet and tile) and the changes (one small note per blast).
func save_state() -> Dictionary:
	return {"planet": planet_id, "tile": tile, "deltas": deltas.duplicate(true)}
