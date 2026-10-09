class_name BlockField
extends Node3D
## EXPERIMENT (branch planet-blocks-test): the owner's "Minecraft-style" destructible ground, light version, step 1.
## One test patch of a planet tile is built from BIG blocks instead of the smooth terrain sheet:
##   - columns on a grid of Data.BLOCK_BIG metres, each a stack of big blocks from deep rock up to the ground;
##   - the top of each column follows the planet's own noise shape (Surface.sample), snapped to Data.BLOCK_MIN steps,
##     so the patch keeps the planet's hills and colours, just chunky;
##   - a block can be any box (the top one is a slab when the ground falls between steps).
## Data: the field is regrown from the planet seed every visit; only changes ("deltas") will ever be saved (step 2:
## a hit splits a block into four smaller ones, down to Data.BLOCK_MIN, half a mech). Nothing is saved yet.
## Drawn as one MultiMesh of boxes with plain colours (the owner's Bible: solid colours, low memory).

var planet_id := ""
var tile := 0
var center := Vector2.ZERO     # tile-local centre of the patch (x east, z south)
var cols := 0                  # columns per side
var tops := PackedFloat32Array()   # top height of each column (row-major), the ground the ship lands on
var blocks: Array = []         # [{pos: Vector3 (centre), size: Vector3, col: Color, depth: int}]
var deltas: Array = []         # changes made by the player (empty until step 2); this is all that gets saved
var _mmi: MeshInstance3D
var surf_cols := PackedColorArray()   # the ground's own colour per column (for the fused surface)
const OFFS := [Vector2.ZERO, Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5),
	Vector2(0, -0.5), Vector2(0, 0.5), Vector2(-0.5, 0), Vector2(0.5, 0)]

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
			var hmax := -1e9
			var colr := Color.GRAY
			for k in OFFS.size():
				var o: Vector2 = OFFS[k] * big
				var smp: Array = Surface.sample(pid, ox + c.x + o.x, oz + c.y + o.y)
				hmax = maxf(hmax, float(smp[0]))
				if k == 0: colr = smp[1]
			tops[j * cols + i] = ceilf((hmax + Data.BLOCK_MARGIN) / step) * step
			surf_cols[j * cols + i] = Color(colr.r, colr.g, colr.b)   # a little over the highest sample: ridges between samples stay under
			cols_c[j * cols + i] = colr
	# 2. blocks: each column from below its lowest neighbour up to its top, in big blocks (the top one a slab)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|blocks" % [pid, t])
	for j in cols:
		for i in cols:
			var top: float = tops[j * cols + i]
			var low := top
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				low = minf(low, tops[nj * cols + ni] if ni >= 0 and nj >= 0 and ni < cols and nj < cols else top - Data.BLOCK_SKIRT)
			var base := low - big   # one block deeper than the lowest neighbour, so every visible face is a block face
			var c2 := _col_centre(i, j)
			var surf: Color = cols_c[j * cols + i]
			var y := top
			var depth := 0
			while y > base + 0.01:
				var h := minf(big, y - base)
				var bc := _shade(surf, depth, rng)
				blocks.append({"pos": Vector3(c2.x, y - h * 0.5, c2.y), "size": Vector3(big, h, big), "col": bc, "depth": depth})
				y -= h
				depth += 1
	_draw()

func _col_centre(i: int, j: int) -> Vector2:
	var big: float = Data.BLOCK_BIG
	return center + Vector2((i + 0.5) * big - cols * big * 0.5, (j + 0.5) * big - cols * big * 0.5)

## Plain colours: the ground's own colour on the top block, grading to rock below; a little variation per block.
func _shade(surf: Color, depth: int, rng: RandomNumberGenerator) -> Color:
	var rock: Color = Data.BLOCK_ROCK
	var c := Color(surf.r, surf.g, surf.b).lerp(rock, clampf(depth * 0.45, 0.0, 1.0))
	return c * rng.randf_range(0.88, 1.06)

## v2 (owner: "they're not fused, they look like Minecraft cubes"): the patch is drawn as ONE solid surface, not a box
## per block. Same-height neighbours share one flat face with no seam; a wall appears only where the ground actually
## steps (or at the patch edge). Colours blend across the ground (shared corners), so no grid shows; walls darken with
## depth from the ground colour to rock. The block data underneath (`blocks`) is unchanged: that is what will split.
func _draw() -> void:
	if is_instance_valid(_mmi): _mmi.queue_free()
	var big: float = Data.BLOCK_BIG
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := cols * big * 0.5
	var corner := func(ci: int, cj: int) -> Color:   # the average colour of the columns round a grid corner
		var c := Color(0, 0, 0)
		var n := 0
		for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
			var i: int = ci + d.x
			var j: int = cj + d.y
			if i >= 0 and j >= 0 and i < cols and j < cols:
				c += surf_cols[j * cols + i]
				n += 1
		return c / maxf(1.0, n)
	for j in cols:
		for i in cols:
			var top: float = tops[j * cols + i]
			var x0 := center.x - half + i * big
			var z0 := center.y - half + j * big
			# the top face (shared-corner colours: the ground blends, no grid)
			var a := Vector3(x0, top, z0)
			var b := Vector3(x0 + big, top, z0)
			var c := Vector3(x0 + big, top, z0 + big)
			var d := Vector3(x0, top, z0 + big)
			_quad(st, a, b, c, d, [corner.call(i, j), corner.call(i + 1, j), corner.call(i + 1, j + 1), corner.call(i, j + 1)], Vector3.UP)
			# walls only where this column stands higher than its neighbour (or at the patch edge)
			for side in [[Vector2i(0, -1), a, b, Vector3.FORWARD], [Vector2i(1, 0), b, c, Vector3.RIGHT], [Vector2i(0, 1), c, d, Vector3.BACK], [Vector2i(-1, 0), d, a, Vector3.LEFT]]:
				var ni: int = i + (side[0] as Vector2i).x
				var nj: int = j + (side[0] as Vector2i).y
				var low: float = tops[nj * cols + ni] if ni >= 0 and nj >= 0 and ni < cols and nj < cols else top - Data.BLOCK_SKIRT
				if low >= top - 0.01: continue
				var p0: Vector3 = side[1]
				var p1: Vector3 = side[2]
				var surf: Color = surf_cols[j * cols + i]
				var h := top - low
				var cut := minf(h, Data.BLOCK_MIN)   # the top band keeps the ground colour, then rock
				var rock: Color = Data.BLOCK_ROCK
				var dark := surf.lerp(rock, 0.55)
				_quad(st, p0, p1, Vector3(p1.x, top - cut, p1.z), Vector3(p0.x, top - cut, p0.z), [surf * 0.92, surf * 0.92, dark, dark], side[3])
				if h > cut + 0.01:
					var deep := surf.lerp(rock, clampf(h / 40.0, 0.6, 1.0))
					_quad(st, Vector3(p0.x, top - cut, p0.z), Vector3(p1.x, top - cut, p1.z), Vector3(p1.x, low, p1.z), Vector3(p0.x, low, p0.z), [dark, dark, deep, deep], side[3])
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mmi = MeshInstance3D.new()
	_mmi.name = "Ground"
	_mmi.mesh = st.commit()
	_mmi.material_override = m
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, cs: Array, n: Vector3) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_color(cs[k])
		st.add_vertex([a, b, c, d][k])

## Is a tile-local point over the patch?
func covers(x: float, z: float) -> bool:
	var half := cols * Data.BLOCK_BIG * 0.5
	return absf(x - center.x) < half and absf(z - center.y) < half

## The block ground under a tile-local point (or -INF off the patch).
func top_at(x: float, z: float) -> float:
	if not covers(x, z): return -INF
	var big: float = Data.BLOCK_BIG
	var half := cols * big * 0.5
	var i := clampi(int((x - center.x + half) / big), 0, cols - 1)
	var j := clampi(int((z - center.y + half) / big), 0, cols - 1)
	return tops[j * cols + i]

## What gets saved: the seed (the planet and tile) and the changes. Step 1 has no changes.
func save_state() -> Dictionary:
	return {"planet": planet_id, "tile": tile, "deltas": deltas.duplicate(true)}
