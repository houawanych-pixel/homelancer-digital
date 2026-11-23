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

static var _rects := {}            # "pid|tile" -> Rect2i of the city's regions (size 0: no city)
static var _tiles := {}            # pid -> {tile: blocks across (1 or 2)}
static var _ground := {}           # "pid|tile" -> street height
static var _blocks := {}           # "pid|tile|rx|rz" -> plan

## v13.274 (owner: "a planet's terrain tiles are a 3 x 3; split each green tile into its own 3 x 3, and its centre square
## always gets a city: one block, or a 2 x 2 on good green land with water; snow, desert and harsh land get none (a
## facility base can sit there); a Mars-like world gets a single block; a big 3 x 3 world has cities in maybe two
## tiles; bases go anywhere except on a city square, right next to one is fine"):
## which tiles of a world have a city, and how many blocks across (1 or 2).
static func city_tiles(pid: String) -> Dictionary:
	if _tiles.has(pid): return _tiles[pid]
	var out := {}
	if Data.CITIES and Surface.PLANETS.has(pid) and Surface.has_surface(pid) and not Surface.is_sun(pid):
		var tl: Array = Surface.PLANETS[pid].get("tiles", [])
		var g := Surface.grid(pid)
		var cands: Array = []   # [size, has a port, tile]
		for t in mini(tl.size(), g * g):
			var sz := int(Data.CITY_LAND.get(str(tl[t]), 0))
			if sz > 0: cands.append([sz, 1 if not Surface.locations_in(pid, t).is_empty() else 0, t])
		cands.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and (x[1] > y[1] or (x[1] == y[1] and x[2] < y[2]))))
		var most: int = Data.CITY_TILES_BIG if g >= 3 else 1
		for c in cands.slice(0, most): out[int(c[2])] = int(c[0])
		if out.is_empty():   # a harsh world (Mars-like): one block on its first dry tile
			for t in mini(tl.size(), g * g):
				if not (str(tl[t]) in Data.CITY_NO_OUTPOST):
					out[t] = 1
					break
	_tiles[pid] = out
	return out

## Is there a city on this tile?
static func is_city_tile(pid: String, tile: int) -> bool:
	return rect(pid, tile).size.x > 0

## The city's regions on a tile (Rect2i of 500 m regions; size 0 = none): a 1 x 1 or 2 x 2 square at the tile's dead
## centre, slid as little as it takes to keep clear of a port's pad island.
static func rect(pid: String, tile: int) -> Rect2i:
	var key := "%s|%d" % [pid, tile]
	if _rects.has(key): return _rects[key]
	var out := Rect2i()
	var want := int(city_tiles(pid).get(tile, 0))
	if want > 0:
		var avoid: Array = []
		for l in Surface.locations_in(pid, tile): avoid.append([l["pos"] as Vector2, Data.PAD_ISLAND_RADIUS + Data.CITY_CLEAR])
		var nr := int(round(Surface.TILE / Data.BLOCK_REGION))
		for sz2 in [want, 1]:
			var bd := INF
			for zz in range(1, nr - sz2):
				for xx in range(1, nr - sz2):
					var rr := Rect2(-Surface.EDGE + xx * Data.BLOCK_REGION, -Surface.EDGE + zz * Data.BLOCK_REGION, Data.BLOCK_REGION * sz2, Data.BLOCK_REGION * sz2)
					var ok := true
					for a in avoid:
						var p: Vector2 = a[0]
						var q := Vector2(clampf(p.x, rr.position.x, rr.end.x), clampf(p.y, rr.position.y, rr.end.y))
						if q.distance_to(p) < float(a[1]): ok = false
					var d := rr.get_center().length()
					if ok and d < bd - 0.01:
						bd = d
						out = Rect2i(xx, zz, sz2, sz2)
			if out.size.x > 0 and bd <= Data.BLOCK_REGION * 1.5: break   # (else try a single block nearer the middle)
	_rects[key] = out
	return out

## (older name) the first region of the city.
static func window(pid: String, tile: int) -> Vector2i:
	var r := rect(pid, tile)
	return r.position if r.size.x > 0 else Vector2i(-1, -1)

static func is_city_region(pid: String, tile: int, r: Vector2i) -> bool:
	return rect(pid, tile).has_point(r)

## Is a tile-local point on (or within `margin` m of) a city square? (bases and mission points keep off them)
static func in_city(pid: String, tile: int, p: Vector2, margin := 0.0) -> bool:
	var r := rect(pid, tile)
	if r.size.x <= 0: return false
	var rr := Rect2(-Surface.EDGE + r.position.x * Data.BLOCK_REGION, -Surface.EDGE + r.position.y * Data.BLOCK_REGION, r.size.x * Data.BLOCK_REGION, r.size.y * Data.BLOCK_REGION).grow(margin)
	return rr.has_point(p)

## The street height (a whole layer): the mean ground under the city, snapped up to a step.
static func ground(pid: String, tile: int) -> float:
	var key := "%s|%d" % [pid, tile]
	if _ground.has(key): return _ground[key]
	var r := rect(pid, tile)
	var sum := 0.0
	var cnt := 0
	Surface._no_city = true   # (the bare land, not the land already eased to the city)
	for jz in 13:
		for jx in 13:
			var x := -Surface.EDGE + r.position.x * Data.BLOCK_REGION + jx * Data.BLOCK_REGION * r.size.x / 12.0
			var z := -Surface.EDGE + r.position.y * Data.BLOCK_REGION + jz * Data.BLOCK_REGION * r.size.y / 12.0
			sum += maxf(Surface.height(pid, tile, x, z), 0.0)
			cnt += 1
	Surface._no_city = false
	var g := ceilf((sum / maxf(1, cnt) + Data.BLOCK_MARGIN) / Data.BLOCK_MIN) * Data.BLOCK_MIN
	_ground[key] = g
	return g

## One block's plan: {g, cells: {Vector2i: floors}, rooms: {Vector2i: true}, walk: {Vector2i: true} (pavement),
## buildings: [{kind, cells: {Vector2i: floors}, floors, rooms, walls, shaft, door: [Vector2i]}],
## bridges: [{cells: [Vector2i], f (the floor it joins), ends: [Vector2i, Vector2i] (the facade cells it opens)}]}.
## v13.273 (owner: "pretty basic building structures because of memory: floors, elevators, ways in and out, maybe 9
## tiles of rooms, big enough for people (not mechs); some bridges across, walkway with side rails"): a few kinds of
## building made of the same module, a 3 x 3 grid of person-sized rooms round a lift.
static func block(pid: String, tile: int, r: Vector2i) -> Dictionary:
	var key := "%s|%d|%d|%d" % [pid, tile, r.x, r.y]
	if _blocks.has(key): return _blocks[key]
	var plan := {"g": ground(pid, tile), "cells": {}, "rooms": {}, "walk": {}, "buildings": [], "bridges": [], "lots": []}
	if not is_city_region(pid, tile, r):
		_blocks[key] = plan
		return plan
	var cr := rect(pid, tile)
	var downtown := (r - cr.position) == Vector2i(cr.size.x / 2, cr.size.y / 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key + "|city")
	var a: int = Data.CITY_AVENUE      # half an avenue on each edge of the block
	var al: int = Data.CITY_ALLEY
	var lo := N / 2 - al / 2           # the alley: [lo, lo + al)
	var hi := lo + al
	var lots := [Rect2i(a, a, lo - a, lo - a), Rect2i(hi, a, N - a - hi, lo - a), Rect2i(a, hi, lo - a, N - a - hi), Rect2i(hi, hi, N - a - hi, N - a - hi)]
	# each lot's corner at the alley crossing (its buildings stand there, so bridges across the alley are short)
	var toward := [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	var first: Array = []   # the main building on each lot (bridges join these)
	for li in 4:
		var lr: Rect2i = lots[li]
		plan["lots"].append(lr)
		for z in range(lr.position.y, lr.end.y):   # the lot's pavement
			for x in range(lr.position.x, lr.end.x): plan["walk"][Vector2i(x, z)] = true
		var inner := lr.grow(-Data.CITY_PAVEMENT)
		var t: Vector2i = toward[li]
		var b := _building(_pick_kind(rng, downtown), rng, downtown)
		var bs: Vector2i = b["size"]
		var at := Vector2i(inner.end.x - bs.x if t.x > 0 else inner.position.x, inner.end.y - bs.y if t.y > 0 else inner.position.y)
		_place(plan, b, at)
		first.append(b)
		if bs.x <= inner.size.x - Data.MODULE - 2 and bs.y <= inner.size.y - Data.MODULE - 2 and rng.randf() < 0.7:   # a tower in the far corner too
			var b2 := _building("tower", rng, downtown)
			var at2 := Vector2i(inner.position.x if t.x > 0 else inner.end.x - Data.MODULE, inner.position.y if t.y > 0 else inner.end.y - Data.MODULE)
			_place(plan, b2, at2)
	# bridges across the alley between the main buildings: east-west pairs, then north-south
	for pr in [[0, 1, Vector2i(1, 0)], [2, 3, Vector2i(1, 0)], [0, 2, Vector2i(0, 1)], [1, 3, Vector2i(0, 1)]]:
		if rng.randf() > Data.CITY_BRIDGE_CHANCE: continue
		var br := _bridge(first[pr[0]], first[pr[1]], pr[2], rng)
		if not br.is_empty(): plan["bridges"].append(br)
	_blocks[key] = plan
	return plan

static func _pick_kind(rng: RandomNumberGenerator, downtown: bool) -> String:
	var kinds: Array = ["tower", "tower", "podium", "L"] if downtown else ["tower", "wide", "L", "podium", "wide"]
	return kinds[rng.randi() % kinds.size()]

static func _place(plan: Dictionary, b: Dictionary, at: Vector2i) -> void:
	for k in ["cells", "rooms", "walls"]:
		var moved := {}
		for c in b[k]: moved[c + at] = b[k][c]
		b[k] = moved
	b["shaft"] = (b["shaft"] as Array).map(func(c): return c + at)
	b["door"] = (b["door"] as Array).map(func(c): return c + at)
	b["at"] = at
	var outs: Array = []   # v13.276: which way each street door faces (out of the building)
	for c in b["door"]:
		var o := Vector2i.ZERO
		for e in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not (b["cells"] as Dictionary).has(c + e): o = e
		outs.append(o)
	b["door_out"] = outs
	plan["buildings"].append(b)
	for c in b["cells"]: plan["cells"][c] = b["cells"][c]
	for c in b["rooms"]: plan["rooms"][c] = true

## One building of a kind, at (0, 0): modules (10 x 10 cells: walls on the 0 / 3 / 6 / 9 lines, rooms of 2 x 2 cells
## between, the middle room the lift shaft) side by side sharing walls, the outer corners notched, a door from each
## module's rooms to the street on the ground floor.
static func _building(kind: String, rng: RandomNumberGenerator, downtown: bool) -> Dictionary:
	var M: int = Data.MODULE
	var S := M - 1   # modules overlap by their shared wall
	var mods: Array = []   # [offset, floors]
	var tall := func(lo2: int, hi2: int) -> int: return rng.randi_range(lo2 + (4 if downtown else 0), hi2 + (6 if downtown else 0))
	match kind:
		"tower": mods = [[Vector2i(0, 0), tall.call(6, 12)]]
		"wide":
			var f := rng.randi_range(3, 6)
			mods = [[Vector2i(0, 0), f], [Vector2i(S, 0) if rng.randf() < 0.5 else Vector2i(0, S), f]]
		"L":
			var f2 := rng.randi_range(4, 8)
			var corner := rng.randi() % 4   # the missing one of the four
			var all := [Vector2i(0, 0), Vector2i(S, 0), Vector2i(0, S), Vector2i(S, S)]
			for q in 4:
				if q != corner: mods.append([all[q], f2 + (2 if q == (corner + 3) % 4 else 0)])
		_:   # podium: four low modules, one goes on up as a tower
			var base := rng.randi_range(2, 4)
			var up := rng.randi() % 4
			var all2 := [Vector2i(0, 0), Vector2i(S, 0), Vector2i(0, S), Vector2i(S, S)]
			for q in 4: mods.append([all2[q], tall.call(8, 14) if q == up else base])
	var cells := {}
	var walls := {}
	var rooms := {}
	var shaft: Array = []
	var size := Vector2i.ZERO
	for md in mods:
		var o: Vector2i = md[0]
		var fl: int = md[1]
		size = Vector2i(maxi(size.x, o.x + M), maxi(size.y, o.y + M))
		for z in M:
			for x in M:
				var c := o + Vector2i(x, z)
				cells[c] = maxi(int(cells.get(c, 0)), fl)
				var wx := x % 3 == 0
				var wz := z % 3 == 0
				if x >= 4 and x <= 5 and z >= 4 and z <= 5:
					shaft.append(c)
				elif wx or wz:
					walls[c] = true
				else:
					rooms[c] = true
	# doorways: one cell in every inner wall between two rooms (into the lift room too)
	for c in walls.keys():
		var l := Vector2i(c.x - 1, c.y)
		var rr := Vector2i(c.x + 1, c.y)
		var u := Vector2i(c.x, c.y - 1)
		var dn := Vector2i(c.x, c.y + 1)
		var open_x: bool = (rooms.has(l) or shaft.has(l)) and (rooms.has(rr) or shaft.has(rr)) and posmod(c.y, 3) == 1
		var open_z: bool = (rooms.has(u) or shaft.has(u)) and (rooms.has(dn) or shaft.has(dn)) and posmod(c.x, 3) == 1
		if open_x or open_z: walls.erase(c)
	# notch the outer corners (a cell with two open sides)
	var corners: Array = []   # (found first, then taken: taking one must not make its neighbours corners)
	for c in cells:
		var open := 0
		for e in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not cells.has(c + e): open += 1
		if open >= 2: corners.append(c)
	for c in corners:
		cells.erase(c)
		walls.erase(c)
	# street doors: on the ground floor, the outline cell in front of each module's first room on its outward sides
	var door: Array = []
	for c in walls:
		if not _edge(cells, c): continue
		var inward := Vector2i.ZERO
		for e in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not cells.has(c - e) and rooms.has(c + e): inward = e
		if inward == Vector2i.ZERO: continue
		var along: int = c.y if inward.x != 0 else c.x
		if posmod(along, 9) == 1: door.append(c)   # (the first room cell of a module's middle band)
	var fl_max := 0
	for c in cells: fl_max = maxi(fl_max, int(cells[c]))
	return {"kind": kind, "cells": cells, "walls": walls, "rooms": rooms, "shaft": shaft, "door": door, "floors": fl_max, "size": size, "shape": kind}

## A walkway across the alley between two buildings facing each other (dir = from a to b): at a floor both have, on a
## row of rooms both have, the deck from a's facade to b's; it opens a door in each facade.
static func _bridge(a: Dictionary, b: Dictionary, dir: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var ca: Dictionary = a["cells"]
	var cb: Dictionary = b["cells"]
	var cand: Array = []
	for c in ca:
		if not ca.has(c) or ca.has(c + dir): continue   # a's facade toward b
		if not (a["rooms"] as Dictionary).has(c - dir): continue
		var q: Vector2i = c + dir
		var span: Array = []
		while not cb.has(q) and span.size() < 30:
			span.append(q)
			q += dir
		if not cb.has(q) or not (b["rooms"] as Dictionary).has(q + dir) or span.is_empty(): continue
		var fmax := mini(int(ca[c]), int(cb[q])) - 1
		if fmax < 1: continue
		cand.append([c, q, span, fmax])
	if cand.is_empty(): return {}
	var pick: Array = cand[rng.randi() % cand.size()]
	return {"cells": pick[2], "f": rng.randi_range(1, mini(int(pick[3]), 4)), "ends": [pick[0], pick[1]], "dir": dir}

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
	var rooms: Dictionary = plan["rooms"]
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
			var win := rooms.has(cv - (e[0] as Vector2i))   # a facade cell in front of a room: a window strip
			_quad(st, Vector3(a0.x, top, a0.z), Vector3(a1.x, top, a1.z), Vector3(a1.x, low, a1.z), Vector3(a0.x, low, a0.z), nrm, glass_c if win else wall_c)
	return st.commit()

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)

## v13.276: a cell's centre in tile-local metres (x, z).
static func cell_pos(r: Vector2i, c: Vector2) -> Vector2:
	return BlockField.region_centre(r) - Vector2(Data.BLOCK_REGION, Data.BLOCK_REGION) * 0.5 + (c + Vector2(0.5, 0.5)) * Data.BLOCK_MIN
