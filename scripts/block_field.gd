class_name BlockField
extends Node3D
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
var _ground_mat: StandardMaterial3D
var _rng := RandomNumberGenerator.new()

static var force := false   # tests switch it on
static var _url_on := -1

## The experiment is OFF in normal play. On the web it switches on when the game's address ends in ?blocks
## (the owner's link to look at it); the route test switches it on with `force`.
static func enabled() -> bool:
	if force: return true
	if _url_on < 0:
		_url_on = 0
		if OS.has_feature("web"):
			_url_on = 1 if str(JavaScriptBridge.eval("window.location.search || ''", true)).find("blocks") >= 0 else 0
	return _url_on == 1

static func wanted(pid: String, t: int) -> bool:
	return enabled() and Data.BLOCK_TEST.get("planet", "") == pid and int(Data.BLOCK_TEST.get("tile", -1)) == t

static func key_of(pid: String, t: int) -> String:
	return "%s|%d" % [pid, t]

@warning_ignore("integer_division")
func build(pid: String, t: int) -> void:
	planet_id = pid
	tile = t
	name = "BlockField"
	center = Data.BLOCK_TEST["center"]
	var big: float = Data.BLOCK_BIG
	var step: float = Data.BLOCK_MIN
	cols = int(round(float(Data.BLOCK_TEST["size"]) / big))
	tops.resize(cols * cols)
	var g := Surface.grid(pid)
	var ox := float(t % g) * Surface.TILE
	var oz := float(t / g) * Surface.TILE
	var cols_c: Array = []
	cols_c.resize(cols * cols)
	surf_cols.resize(cols * cols)
	# 1. column tops: the highest ground under the column (so the smooth sheet never pokes through), snapped up a step
	for j in cols:
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
	# 2. the original stacks of big blocks (each column from below its lowest neighbour up to its top)
	_rng.seed = hash("%s|%d|blocks" % [pid, t])
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
	_noise = FastNoiseLite.new()
	_noise.seed = hash("%s|%d|layers" % [pid, t])
	_noise.frequency = 0.03
	# 4. re-apply the blasts made here before (seed + deltas), quietly
	var key := key_of(pid, t)
	if not GS.block_deltas.has(key): GS.block_deltas[key] = []
	deltas = GS.block_deltas[key]
	for d in deltas: _apply_note(d)
	layers_broken = 0
	splits = 0
	collapses = 0
	var nc := _nchunks()
	for k in nc * nc: _dirty[k] = true
	flush()

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
	if _tones.has(m): return _tones[m]
	var tn: Array = Data.BLOCK_TONES.get(m, [0.0, 1.0])
	var gl := (base.r + base.g + base.b) / 3.0
	var c := Color(gl, gl, gl).lerp(base, float(tn[1]))
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
		deltas.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), kind])
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
func _settle(cx0: int, cx1: int, cz0: int, cz1: int) -> Array:
	var fell: Array = []
	cx0 = clampi(cx0, 0, n - 1)
	cx1 = clampi(cx1, 0, n - 1)
	cz0 = clampi(cz0, 0, n - 1)
	cz1 = clampi(cz1, 0, n - 1)
	for pass_i in 12:
		var changed := false
		var cells: Array = holes.keys()
		cells.sort()
		for ci in cells:
			var i: int = ci
			var fx := i % n
			var fz := i / n
			if fx < cx0 or fx > cx1 or fz < cz0 or fz > cz1 or not holes.has(i): continue
			var sp: Array = spans(i)
			var j := 1
			while j < sp.size():
				if _held(fx, fz, sp[j]):
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
			_set_spans(i, sp)
			dmg.erase(i)
			_mark(fx, fz, 1)
		if not changed: break
	return fell

func _held(fx: int, fz: int, sp: Vector2i) -> bool:
	var reach: int = Data.BLOCK_REACH.get(mat_at(fx, fz, _ly(sp.x)), 1)
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
	return {"h": h.duplicate(), "lsz": lsz.duplicate(), "dmg": dmg.duplicate(true), "holes": holes.duplicate(true), "mats": mats.duplicate(true), "fill": fill.duplicate(true), "n": deltas.size()}

func restore(sn: Dictionary) -> void:
	h = sn["h"]
	lsz = sn["lsz"]
	dmg = sn["dmg"]
	holes = sn["holes"]
	mats = sn.get("mats", {})
	fill = sn.get("fill", {})
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
	var note := [snappedf(at.x, 0.01), snappedf(y, 0.01), snappedf(at.z, 0.01), "dep:%s:%.3f" % [str(b.get("mat", "dirt")), amount]]
	deltas.append(note)
	if deltas.size() > Data.BLOCK_DELTAS_MAX: deltas.remove_at(0)
	_apply_note(note)

## Re-apply one kept note: a blast, or a deposit of settled rubble.
func _apply_note(d: Array) -> void:
	var kind := str(d[3])
	if kind.begins_with("dep:"):
		var parts := kind.split(":")
		deposit(Vector3(float(d[0]), float(d[1]), float(d[2])), parts[1], float(parts[2]))
	else:
		blast(Vector3(float(d[0]), float(d[1]), float(d[2])), kind, false, false)

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
	var c: int = Data.BLOCK_CHUNK
	var nc := _nchunks()
	for z in [oz - 1, oz + s]:
		for x in [ox - 1, ox + s]:
			var cx := clampi(x, 0, n - 1) / c
			var cz := clampi(z, 0, n - 1) / c
			_dirty[cz * nc + cx] = true

func _nchunks() -> int:
	return ceili(float(n) / Data.BLOCK_CHUNK)

# ---------------------------------------------------------------- rubble
## What a blast breaks flies out by material (Data.BLOCK_BREAK_PIECES): obsidian in 2 big halves, stone in 3, dirt in
## 4, sand in 5 smaller pieces. About half of it flies (BLOCK_RUBBLE_FRAC; obsidian always goes whole), at most
## BLOCK_RUBBLE_PER_BLAST pieces: bigger pieces from the edge of the blast, smaller ones from the middle.
func _throw(p: Vector3, r: float, out: Array) -> int:
	var cands: Array = []
	for o in out:
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
func flush(limit := 0) -> void:
	var done := 0
	for k in _dirty.keys():
		_draw_chunk(int(k))
		_dirty.erase(k)
		done += 1
		if limit > 0 and done >= limit: break

@warning_ignore("integer_division")
func _draw_chunk(k: int) -> void:
	var c: int = Data.BLOCK_CHUNK
	var nc := _nchunks()
	var ci := k % nc
	var cj := k / nc
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for fz in range(cj * c, mini((cj + 1) * c, n)):
		for fx in range(ci * c, mini((ci + 1) * c, n)):
			var s: int = lsz[fz * n + fx]
			if fx % s != 0 or fz % s != 0: continue
			_draw_block(st, fx, fz, s)
			any = true
	var mi: MeshInstance3D = _chunks.get(k)
	if mi == null:
		if _ground_mat == null:
			_ground_mat = StandardMaterial3D.new()
			_ground_mat.vertex_color_use_as_albedo = true
			_ground_mat.roughness = 0.9
			_ground_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi = MeshInstance3D.new()
		mi.name = "Ground%d" % k
		mi.material_override = _ground_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_chunks[k] = mi
	mi.mesh = st.commit() if any else null

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
	var untouched: bool = top >= h0[i0] - 0.01
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
		if j == sp.size() - 1 and (drop > 0.0 or fused):
			_skin_top(st, ax, az, bx, bz, ty, edge, inset, drop, cs, fused, shard, s * step)
		else:
			_quad(st, Vector3(ax, ty, az), Vector3(bx, ty, az), Vector3(bx, ty, bz), Vector3(ax, ty, bz), cs, Vector3.UP)
		if j > 0:   # the roof of a hole under it (a tunnel or cave ceiling)
			var by: float = y0 + o.x * step
			var cc := tone(mat_at(cfx, cfz, _ly(o.x))).lerp(Color.BLACK, 0.4)
			_quad(st, Vector3(ax, by, az), Vector3(ax, by, bz), Vector3(bx, by, bz), Vector3(bx, by, az), [cc, cc, cc, cc], Vector3.DOWN)
	var surf: Color = ccol[cfz * n1 + cfx]
	var corners := [Vector3(ax, 0, az), Vector3(bx, 0, az), Vector3(bx, 0, bz), Vector3(ax, 0, bz), Vector3(ax, 0, az)]
	var normals := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for side in 4:
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
				if absf(hi - top) < 0.01 and edge[side]: hi -= drop   # the skin rounds the top edge off
				for A in air:
					var wl := maxf(lo, (A as Vector2).x)
					var wh := minf(hi, (A as Vector2).y)
					if wh > wl + 0.01: _wall(st, p0, p1, wh, wl, cfx, cfz, untouched and absf(wh - top) < 0.01, surf, normals[side])
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

func _nb_key(side: int, ox: int, oz: int, s: int, k: int):
	var c := _nb_cell(side, ox, oz, s, k)
	if c < 0: return "out"
	if not holes.has(c): return str(h[c])
	return str(h[c], holes[c])

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
func _wall(st: SurfaceTool, p0: Vector3, p1: Vector3, top: float, low: float, cfx: int, cfz: int, untouched: bool, surf: Color, nrm: Vector3) -> void:
	var step: float = Data.BLOCK_MIN
	var ground: float = h0[cfz * n + cfx]
	var y := top
	var first := true
	while y > low + 0.01:
		var col: Color
		var y_end: float
		if first and untouched:
			col = surf * 0.92
			y_end = maxf(low, y - step)
		else:
			var m := mat_at(cfx, cfz, y)
			y_end = y - step
			while y_end > low + 0.01 and mat_at(cfx, cfz, y_end) == m: y_end -= step
			y_end = maxf(y_end, low)
			col = tone(m)
		first = false
		var ct := col.lerp(Color.BLACK, clampf((ground - y) / 250.0, 0.0, 0.35))
		var cb := col.lerp(Color.BLACK, clampf((ground - y_end) / 250.0, 0.0, 0.35) + 0.08)
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
