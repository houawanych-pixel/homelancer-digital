class_name CityPlan
extends RefCounted
## v13.272 (owner: "GTA-style chases on planets need actual cities, not just terrain. Start with plain cities: buildings
## are just floors, rooms and elevators; one small map per city block, not per building; run them like the regular
## terrain: one of the terrain tiles becomes a nine-block city, streamed on the same 3 x 3 grid"):
## a city tile's 3 x 3 square of 500 m ground regions next to its port become city blocks. Each block is one plan made
## from its seed (the same every visit): avenues round its edge, an alley through the middle, four lots, and on each lot
## a building with a cut outline (L, U, T, stepped corners: never a plain box), floors of rooms, a door to the street and
## a lift shaft. The ground builder (BlockField) makes it out of the 5 m blocks (solid, shootable, walkable inside);
## Surface draws a cheap skyline of the same plan for far away.
##
## Cells are 5 m (Data.BLOCK_MIN); a block is 100 x 100 cells. A floor is CITY_FLOOR_LAYERS layers: the rooms, then
## a one-layer slab. (0, 0) is the region's north-west cell.

const N := 100                     # cells per region side (500 m / 5 m)

static var _windows := {}          # "pid|tile" -> Vector2i (the 3 x 3 window's first region) or (-1, -1)
static var _ground := {}           # "pid|tile" -> street height
static var _blocks := {}           # "pid|tile|rx|rz" -> plan

## Is this tile a city tile?
static func is_city_tile(pid: String, tile: int) -> bool:
	if not Data.CITIES or not Surface.PLANETS.has(pid): return false
	var tl: Array = Surface.PLANETS[pid].get("tiles", [])
	return tile >= 0 and tile < tl.size() and str(tl[tile]) in Data.CITY_BIOMES

## The first region of the city's 3 x 3 window ((-1, -1) = no city here): as close to the tile's port as it can be
## while its pad island, other ports and the facility sites stay clear.
static func window(pid: String, tile: int) -> Vector2i:
	var key := "%s|%d" % [pid, tile]
	if _windows.has(key): return _windows[key]
	var out := Vector2i(-1, -1)
	if is_city_tile(pid, tile):
		var avoid: Array = []   # [Vector2 tile-local, radius]
		for l in Surface.locations_in(pid, tile): avoid.append([l["pos"] as Vector2, Data.PAD_ISLAND_RADIUS + Data.CITY_CLEAR])
		for f in Surface.facility_sites(pid):
			if int(f.get("tile", -1)) == tile and f.has("spot"): avoid.append([f["spot"] as Vector2, Data.CITY_CLEAR * 2.0])
		var target: Vector2 = (avoid[0][0] as Vector2) if not avoid.is_empty() else Vector2.ZERO
		var nr := int(round(Surface.TILE / Data.BLOCK_REGION))
		var bd := INF
		for sz in range(1, nr - 3):   # (never on the tile's outer ring)
			for sx in range(1, nr - 3):
				var rect := Rect2(-Surface.EDGE + sx * Data.BLOCK_REGION, -Surface.EDGE + sz * Data.BLOCK_REGION, Data.BLOCK_REGION * 3.0, Data.BLOCK_REGION * 3.0)
				var ok := true
				for a in avoid:
					var p: Vector2 = a[0]
					var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
					if q.distance_to(p) < float(a[1]): ok = false
				if not ok: continue
				var d := rect.get_center().distance_to(target)
				if d < bd:
					bd = d
					out = Vector2i(sx, sz)
	_windows[key] = out
	return out

static func is_city_region(pid: String, tile: int, r: Vector2i) -> bool:
	var w := window(pid, tile)
	return w.x >= 0 and r.x >= w.x and r.y >= w.y and r.x < w.x + 3 and r.y < w.y + 3

## The street height (a whole layer): the mean ground under the city, snapped up to a step.
static func ground(pid: String, tile: int) -> float:
	var key := "%s|%d" % [pid, tile]
	if _ground.has(key): return _ground[key]
	var w := window(pid, tile)
	var sum := 0.0
	var cnt := 0
	for jz in 13:
		for jx in 13:
			var x := -Surface.EDGE + w.x * Data.BLOCK_REGION + jx * Data.BLOCK_REGION * 3.0 / 12.0
			var z := -Surface.EDGE + w.y * Data.BLOCK_REGION + jz * Data.BLOCK_REGION * 3.0 / 12.0
			sum += maxf(Surface.height(pid, tile, x, z), 0.0)
			cnt += 1
	var g := ceilf((sum / maxf(1, cnt) + Data.BLOCK_MARGIN) / Data.BLOCK_MIN) * Data.BLOCK_MIN
	_ground[key] = g
	return g

## One block's plan: {g, cells: {Vector2i: floors}, walk: {Vector2i: true} (pavement), buildings: [{cells: {Vector2i:
## floors}, floors, door: [Vector2i], shaft: [Vector2i], walls: {Vector2i: true}}]}.
static func block(pid: String, tile: int, r: Vector2i) -> Dictionary:
	var key := "%s|%d|%d|%d" % [pid, tile, r.x, r.y]
	if _blocks.has(key): return _blocks[key]
	var plan := {"g": ground(pid, tile), "cells": {}, "walk": {}, "buildings": []}
	if not is_city_region(pid, tile, r):
		_blocks[key] = plan
		return plan
	var w := window(pid, tile)
	var downtown := (r - w) == Vector2i(1, 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key + "|city")
	var a: int = Data.CITY_AVENUE      # half an avenue on each edge of the block
	var al: int = Data.CITY_ALLEY
	var mid := N / 2
	var lots := [Rect2i(a, a, mid - al / 2 - a, mid - al / 2 - a), Rect2i(mid + al - al / 2, a, N - a - (mid + al - al / 2), mid - al / 2 - a),
		Rect2i(a, mid + al - al / 2, mid - al / 2 - a, N - a - (mid + al - al / 2)), Rect2i(mid + al - al / 2, mid + al - al / 2, N - a - (mid + al - al / 2), N - a - (mid + al - al / 2))]
	for lot in lots:
		var lr: Rect2i = lot
		for z in range(lr.position.y, lr.end.y):   # the lot's pavement
			for x in range(lr.position.x, lr.end.x): plan["walk"][Vector2i(x, z)] = true
		var b := _building(lr.grow(-Data.CITY_PAVEMENT), rng, downtown)
		if b.is_empty(): continue
		plan["buildings"].append(b)
		for c in b["cells"]: plan["cells"][c] = b["cells"][c]
	_blocks[key] = plan
	return plan

## One building on a lot: a cut outline, floors (a setback higher up on the tall ones), rooms, a door, a lift shaft.
static func _building(lot: Rect2i, rng: RandomNumberGenerator, downtown: bool) -> Dictionary:
	if lot.size.x < 10 or lot.size.y < 10: return {}
	var w := int(lot.size.x * rng.randf_range(0.65, 1.0))
	var d := int(lot.size.y * rng.randf_range(0.65, 1.0))
	var o := lot.position + Vector2i(rng.randi_range(0, lot.size.x - w), rng.randi_range(0, lot.size.y - d))
	var fl: int = rng.randi_range(Data.CITY_FLOORS_DOWNTOWN[0], Data.CITY_FLOORS_DOWNTOWN[1]) if downtown else rng.randi_range(Data.CITY_FLOORS[0], Data.CITY_FLOORS[1])
	var foot := {}
	for z in d:
		for x in w: foot[o + Vector2i(x, z)] = true
	# the outline: cut it so it's never a plain box
	var shape: String = ["L", "U", "T", "steps", "notches"][rng.randi() % 5]
	var cw := maxi(3, int(w * rng.randf_range(0.3, 0.45)))
	var cd := maxi(3, int(d * rng.randf_range(0.3, 0.45)))
	match shape:
		"L":   # one corner out
			var cx := o.x if rng.randf() < 0.5 else o.x + w - cw
			var cz := o.y if rng.randf() < 0.5 else o.y + d - cd
			_cut(foot, Rect2i(cx, cz, cw, cd))
		"U":   # a court out of the middle of one side
			var uw := maxi(3, w / 3)
			_cut(foot, Rect2i(o.x + (w - uw) / 2, o.y, uw, cd))
		"T":   # both corners of one side out
			_cut(foot, Rect2i(o.x, o.y + d - cd, cw, cd))
			_cut(foot, Rect2i(o.x + w - cw, o.y + d - cd, cw, cd))
		"steps":   # every corner stepped in twice
			for cx2 in [o.x, o.x + w - 2]:
				for cz2 in [o.y, o.y + d - 2]: _cut(foot, Rect2i(cx2, cz2, 2, 2))
			for cx3 in [o.x, o.x + w - 1]:
				for cz3 in [o.y, o.y + d - 4]: _cut(foot, Rect2i(cx3, cz3, 1, 4))
		_:   # notches along the long sides
			for k in range(o.x + 3, o.x + w - 3, 6):
				_cut(foot, Rect2i(k, o.y, 2, 1))
				_cut(foot, Rect2i(k, o.y + d - 1, 2, 1))
	if foot.size() < 60: return {}
	# floors per cell: a setback (the core keeps going) on the taller ones
	var cells := {}
	var setback: int = fl
	if fl >= Data.CITY_SETBACK_FROM:
		setback = maxi(2, int(fl * rng.randf_range(0.45, 0.7)))
	var inset: int = Data.CITY_SETBACK_IN
	for c in foot:
		var core := true
		for dz in range(-inset, inset + 1):
			for dx in range(-inset, inset + 1):
				if not foot.has(c + Vector2i(dx, dz)): core = false
		cells[c] = fl if core else setback
	# the lift shaft: 2 x 2 cells that go all the way up, as near the middle as it can
	var cen := Vector2(0, 0)
	for c in foot: cen += Vector2(c)
	cen /= float(foot.size())
	var shaft: Array = []
	var bd := INF
	for c in foot:
		var ok := true
		for e in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var q: Vector2i = c + e
			if int(cells.get(q, 0)) != fl or _edge(foot, q): ok = false
		if ok and Vector2(c).distance_to(cen) < bd:
			bd = Vector2(c).distance_to(cen)
			shaft = [c, c + Vector2i(1, 0), c + Vector2i(0, 1), c + Vector2i(1, 1)]
	# interior walls: a cross through the middle, with doorways near each end (four rooms a floor)
	var walls := {}
	var mx := int(round(cen.x))
	var mz := int(round(cen.y))
	for c in foot:
		if _edge(foot, c): continue
		if c.x == mx or c.y == mz: walls[c] = true
	for c in walls.keys():   # doorways: 2 cells open every 7 along each wall
		var along: int = c.y if c.x == mx else c.x
		if posmod(along, 7) < 2: walls.erase(c)
	for c in shaft: walls.erase(c)
	# the door: 2 cells in the middle of the side facing the lot's widest street (south or north)
	var door: Array = []
	var sides := [o.y + d - 1, o.y] if rng.randf() < 0.5 else [o.y, o.y + d - 1]
	var dx0 := o.x + w / 2 - 1
	for side_z in sides:   # slide out from the middle until both cells are on the outline, facing out
		var out_dz := 1 if side_z == o.y + d - 1 else -1
		for k in w:
			var x1: int = dx0 + (k / 2 if k % 2 == 0 else -(k + 1) / 2)
			var c1 := Vector2i(x1, side_z)
			var c2 := Vector2i(x1 + 1, side_z)
			if foot.has(c1) and foot.has(c2) and not foot.has(c1 + Vector2i(0, out_dz)) and not foot.has(c2 + Vector2i(0, out_dz)) \
					and foot.has(c1 - Vector2i(0, out_dz)) and foot.has(c2 - Vector2i(0, out_dz)):
				door = [c1, c2]
				break
		if not door.is_empty(): break
	for c in door:   # (the cell inside the door is never a wall)
		walls.erase(c - Vector2i(0, 1))
		walls.erase(c + Vector2i(0, 1))
	return {"cells": cells, "floors": fl, "shape": shape, "door": door, "shaft": shaft, "walls": walls}

static func _cut(foot: Dictionary, r: Rect2i) -> void:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x): foot.erase(Vector2i(x, z))

## On the outline (a side neighbour isn't building)?
static func _edge(foot: Dictionary, c: Vector2i) -> bool:
	for e in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not foot.has(c + e): return true
	return false

## Height of a cell's roof (m), given its floors.
static func roof(g: float, floors: int) -> float:
	return g + floors * Data.CITY_FLOOR_LAYERS * Data.BLOCK_MIN

## A cheap skyline of one block for far away: the roofs and walls of its buildings as one mesh (tile-local).
static func skyline_mesh(pid: String, tile: int, r: Vector2i) -> ArrayMesh:
	var plan := block(pid, tile, r)
	var cells: Dictionary = plan["cells"]
	if cells.is_empty(): return null
	var g: float = plan["g"]
	var s: float = Data.BLOCK_MIN
	var org := BlockField.region_centre(r) - Vector2(Data.BLOCK_REGION, Data.BLOCK_REGION) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ground_c: Color = Data.CITY_COLORS["street"]
	var wall_c: Color = Data.CITY_COLORS["concrete"]
	var glass_c: Color = Data.CITY_COLORS["glass"]
	# the street level as one flat slab, so the far skyline stands on something level
	_quad(st, Vector3(org.x, g, org.y), Vector3(org.x + Data.BLOCK_REGION, g, org.y), Vector3(org.x + Data.BLOCK_REGION, g, org.y + Data.BLOCK_REGION), Vector3(org.x, g, org.y + Data.BLOCK_REGION), Vector3.UP, ground_c)
	for c in cells:
		var cv: Vector2i = c
		var top := roof(g, int(cells[c]))
		var x0: float = org.x + cv.x * s
		var z0: float = org.y + cv.y * s
		_quad(st, Vector3(x0, top, z0), Vector3(x0 + s, top, z0), Vector3(x0 + s, top, z0 + s), Vector3(x0, top, z0 + s), Vector3.UP, wall_c)
		for e in [[Vector2i(1, 0), Vector3.RIGHT], [Vector2i(-1, 0), Vector3.LEFT], [Vector2i(0, 1), Vector3.BACK], [Vector2i(0, -1), Vector3.FORWARD]]:
			var nb: Vector2i = cv + (e[0] as Vector2i)
			var low := roof(g, int(cells.get(nb, 0))) if cells.has(nb) else g
			if low >= top: continue
			var nrm: Vector3 = e[1]
			var ax: float = x0 + (s if nrm.x > 0 else 0.0)
			var az: float = z0 + (s if nrm.z > 0 else 0.0)
			var a0: Vector3
			var a1: Vector3
			if absf(nrm.x) > 0.5:
				a0 = Vector3(ax, 0, z0)
				a1 = Vector3(ax, 0, z0 + s)
			else:
				a0 = Vector3(x0, 0, az)
				a1 = Vector3(x0 + s, 0, az)
			_quad(st, Vector3(a0.x, top, a0.z), Vector3(a1.x, top, a1.z), Vector3(a1.x, low, a1.z), Vector3(a0.x, low, a0.z), nrm, glass_c.lerp(wall_c, 0.35))
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)
