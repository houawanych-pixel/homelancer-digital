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
var dmg := PackedByteArray()   # hits taken by a block's top layer (kept at the block's first cell)
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
	dmg.resize(n * n)
	dmg.fill(0)
	lsz.fill(R)
	for fz in n:
		for fx in n:
			h[fz * n + fx] = tops[(fz / R) * cols + fx / R]
	h0 = h.duplicate()
	for v in tops: hmax = maxf(hmax, v)
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
	for d in deltas: blast(Vector3(float(d[0]), float(d[1]), float(d[2])), str(d[3]), false, false)
	layers_broken = 0
	splits = 0
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
func mat_at(fx: int, fz: int, y: float) -> String:
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
## A blast at tile-local point p by a weapon kind (Data.BLOCK_BLAST: gun, missile, heavy, special).
## Returns {broken: layers broken, chipped: blocks hit but still holding, mat: what broke (or "")}.
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
		var top: float = h[i0]
		var v := sqrt(r * r - dmin * dmin)
		if top <= p.y - v: continue   # the blast does not reach down to this block
		var cfx := ox + s / 2
		var cfz := oz + s / 2
		var m := mat_at(cfx, cfz, top)
		if dmax > r and s > 1 and m != "obsidian":
			# only partly inside: split into four and hit just the parts that are in
			var hs := s / 2
			var d0: int = dmg[i0]
			for c in [Vector2i(0, 0), Vector2i(hs, 0), Vector2i(0, hs), Vector2i(hs, hs)]:
				var sx: int = ox + c.x
				var sz: int = oz + c.y
				for jz in hs:
					for jx in hs: lsz[(sz + jz) * n + sx + jx] = hs
				dmg[sz * n + sx] = d0
				queue.append(Vector3i(sx, sz, hs))
			splits += 1
			_mark(ox, oz, s)
			continue
		var remaining := power
		var maxl := maxi(1, ceili((minf(top, p.y + v) - (p.y - v)) / step - 0.01))
		var removed := 0
		var dd: int = dmg[i0]
		var floor_y: float = h0[i0] - Data.BLOCK_DEPTH_FLOOR
		while remaining > 0 and removed < maxl and top > floor_y + 0.01:
			m = mat_at(cfx, cfz, top)
			var need: int = Data.BLOCK_HITS.get(m, 1)
			var take := mini(remaining, need - dd)
			dd += take
			remaining -= take
			if dd < need: break
			dd = 0
			out.append({"pos": Vector3((rx0 + rx1) * 0.5, top - step * 0.5, (rz0 + rz1) * 0.5), "size": s * step, "mat": m, "edge": dmin / r})
			top -= step
			removed += 1
		if removed == 0: res["chipped"] = int(res["chipped"]) + 1
		dmg[i0] = dd
		for jz in s:
			for jx in s: h[(oz + jz) * n + ox + jx] = top
		_mark(ox, oz, s)
	layers_broken += out.size()
	res["broken"] = out.size()
	if not out.is_empty(): res["mat"] = out[0]["mat"]
	if effects and not out.is_empty(): _throw(p, r, out)
	return res

## A shot from a to b: where it first goes into the block ground (or Vector3.INF).
func ray_hit(a: Vector3, b: Vector3) -> Vector3:
	if a.y > hmax + 1.0 and b.y > hmax + 1.0: return Vector3.INF
	var steps := maxi(1, ceili(a.distance_to(b) / 2.5))
	var prev := a
	for k in range(1, steps + 1):
		var q := a.lerp(b, float(k) / steps)
		if q.y < top_at(q.x, q.z):
			var lo := prev
			var hi := q
			for it in 6:
				var mid := (lo + hi) * 0.5
				if mid.y < top_at(mid.x, mid.z): hi = mid
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
func _throw(p: Vector3, r: float, out: Array) -> void:
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
	for k in mini(Data.BLOCK_RUBBLE_PER_BLAST, cands.size()):
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
		var g := top_at(nd.position.x, nd.position.z)
		if float(b["rest"]) < 0.0:
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
	var a := Vector3(ax, top, az)
	var b := Vector3(bx, top, az)
	var c := Vector3(bx, top, bz)
	var d := Vector3(ax, top, bz)
	var cfx := ox + s / 2
	var cfz := oz + s / 2
	var untouched: bool = top >= h0[i0] - 0.01
	var cs: Array
	var n1 := n + 1
	if untouched:
		cs = [ccol[oz * n1 + ox], ccol[oz * n1 + ox + s], ccol[(oz + s) * n1 + ox + s], ccol[(oz + s) * n1 + ox]]
	else:
		var tc := tone(mat_at(cfx, cfz, top)) * (0.95 + float(absi(hash(i0)) % 100) / 1000.0)
		cs = [tc, tc, tc, tc]
	var dd: int = dmg[i0]
	if dd > 0:   # cracked: darker the closer it is to breaking
		var f: float = Data.BLOCK_DAMAGE_DARK * float(dd) / float(Data.BLOCK_HITS.get(mat_at(cfx, cfz, top), 1))
		for q in 4: cs[q] = (cs[q] as Color).lerp(Color.BLACK, f)
	_quad(st, a, b, c, d, cs, Vector3.UP)
	var surf: Color = ccol[cfz * n1 + cfx]
	var corners := [a, b, c, d, a]
	var normals := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for side in 4:
		var k := 0
		while k < s:
			var nh := _nb(side, ox, oz, s, k, top)
			if nh >= top - 0.01:
				k += 1
				continue
			var k2 := k + 1
			while k2 < s and absf(_nb(side, ox, oz, s, k2, top) - nh) < 0.01: k2 += 1
			var p0: Vector3 = (corners[side] as Vector3).lerp(corners[side + 1], float(k) / s)
			var p1: Vector3 = (corners[side] as Vector3).lerp(corners[side + 1], float(k2) / s)
			_wall(st, p0, p1, top, nh, cfx, cfz, untouched, surf, normals[side])
			k = k2

## The ground height next to a block's side (outside the patch: the skirt down to hide the sunk sheet).
func _nb(side: int, ox: int, oz: int, s: int, k: int, top: float) -> float:
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
	if x < 0 or z < 0 or x >= n or z >= n: return top - Data.BLOCK_SKIRT
	return h[z * n + x]

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
