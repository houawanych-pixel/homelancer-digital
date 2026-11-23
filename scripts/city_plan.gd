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
		var rmax: int = (mini(inner.size.x, inner.size.y) - 1) / 2
		var b := _building(_pick_kind(rng, downtown), rng, downtown, mini(rmax, rng.randi_range(8, 12)))
		var bs: Vector2i = b["size"]
		var at := Vector2i(inner.end.x - bs.x if t.x > 0 else inner.position.x, inner.end.y - bs.y if t.y > 0 else inner.position.y)
		_place(plan, b, at)
		first.append(b)
		var r2 := mini(6, (mini(inner.size.x, inner.size.y) - bs.x - 3) / 2)
		if r2 >= 4 and rng.randf() < 0.8:   # a slim round or hex tower in the far corner too
			var b2 := _building(["round", "hex", "oct"][rng.randi() % 3], rng, downtown, r2)
			var s2: Vector2i = b2["size"]
			var at2 := Vector2i(inner.position.x if t.x > 0 else inner.end.x - s2.x, inner.position.y if t.y > 0 else inner.end.y - s2.y)
			_place(plan, b2, at2)
	# bridges across the alley between the main buildings: east-west pairs, then north-south
	for pr in [[0, 1, Vector2i(1, 0)], [2, 3, Vector2i(1, 0)], [0, 2, Vector2i(0, 1)], [1, 3, Vector2i(0, 1)]]:
		if rng.randf() > Data.CITY_BRIDGE_CHANCE: continue
		var br := _bridge(first[pr[0]], first[pr[1]], pr[2], rng)
		if not br.is_empty(): plan["bridges"].append(br)
	_blocks[key] = plan
	return plan

## v13.280 (owner: "futuristic buildings: hexagons, pentagons, round towers, domes, glowing trim, clean angled walls,
## not jagged voxel stairs"; references: Star Citizen's New Babbage and Area18, Cyberpunk's Night City): each building
## is one clean prism (a hexagon, pentagon, octagon or round tower) with a crown on top (a glass dome, a spire, a
## glowing halo). The blocks under it are only its body for walking, shooting and digging; the outside is drawn as
## the real shape (BlockField._draw_shells).
static func _pick_kind(rng: RandomNumberGenerator, downtown: bool) -> String:
	var kinds: Array = ["round", "hex", "oct", "pent", "hex"] if downtown else ["hex", "pent", "oct", "round", "hex", "pent"]
	return kinds[rng.randi() % kinds.size()]

const SIDES := {"hex": 6, "pent": 5, "oct": 8, "round": 24}

static func _place(plan: Dictionary, b: Dictionary, at: Vector2i) -> void:
	for k in ["cells", "rooms", "walls", "band"]:
		var moved := {}
		for c in b[k]: moved[c + at] = b[k][c]
		b[k] = moved
	b["shaft"] = (b["shaft"] as Array).map(func(c): return c + at)
	b["door"] = (b["door"] as Array).map(func(c): return c + at)
	var pv := PackedVector2Array()
	for q in b["poly"]: pv.append(q + Vector2(at))
	b["poly"] = pv
	b["centre"] = (b["centre"] as Vector2) + Vector2(at)
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

## The corners of a regular shape (n sides, circumradius rr) round centre c, turned by rot (cell units).
static func shape_poly(c: Vector2, rr: float, n: int, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n: out.append(c + Vector2(cos(rot + TAU * i / n), sin(rot + TAU * i / n)) * rr)
	return out

## Is p inside the convex polygon (either winding)?
static func in_poly(poly: PackedVector2Array, p: Vector2) -> bool:
	var sgn := 0.0
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var cr := (b - a).cross(p - a)
		if absf(cr) < 1e-6: continue
		if sgn == 0.0: sgn = signf(cr)
		elif signf(cr) != sgn: return false
	return true

## One building of a shape, at (0, 0) (box 2R+1 cells across): the cells whose middle is inside the shape; a wall band
## round the outside (every cell the drawn outline cuts through: the clean shell is drawn there); inside, rooms of
## 2 x 2 cells in 1-cell walls on a 3-cell grid, the middle room the lift shaft; a street door on each face, through
## the wall band to the first room.
static func _building(kind: String, rng: RandomNumberGenerator, downtown: bool, rad := -1) -> Dictionary:
	if not SIDES.has(kind): kind = "hex"
	var R: int = rad if rad > 0 else rng.randi_range(8, 12)
	var ns: int = SIDES[kind]
	var rot := rng.randf() * TAU / ns
	if kind == "hex" and rng.randf() < 0.5: rot = 0.0
	var C := Vector2(R + 0.5, R + 0.5)
	var outer := shape_poly(C, R + 0.5, ns, rot)                                # (whose cells are the building)
	var vis := shape_poly(C, R + 0.5 - 0.75 / cos(PI / ns), ns, rot)           # the drawn outline: inside the cells
	var fl: int = rng.randi_range(Data.CITY_FLOORS_DOWNTOWN[0], Data.CITY_FLOORS_DOWNTOWN[1]) if downtown else rng.randi_range(Data.CITY_FLOORS[0], Data.CITY_FLOORS[1])
	if R <= 6: fl += rng.randi_range(2, 6)   # (a slim tower goes higher)
	var cells := {}
	var walls := {}
	var rooms := {}
	var shaft: Array = []
	var o := posmod(R - 2, 3)   # the grid: the middle two cells (R-1, R) are a room pair
	for z in 2 * R + 1:
		for x in 2 * R + 1:
			var c := Vector2i(x, z)
			if not in_poly(outer, Vector2(x + 0.5, z + 0.5)): continue
			cells[c] = fl
			var inside := in_poly(vis, Vector2(x, z)) and in_poly(vis, Vector2(x + 1, z)) and in_poly(vis, Vector2(x, z + 1)) and in_poly(vis, Vector2(x + 1, z + 1))
			if x >= R - 1 and x <= R and z >= R - 1 and z <= R:
				shaft.append(c)
			elif not inside or posmod(x - o, 3) == 0 or posmod(z - o, 3) == 0:
				walls[c] = true
			else:
				rooms[c] = true
	var band := {}   # the outer wall band (where the shell is drawn)
	for c in walls:
		var cv: Vector2i = c
		if not (in_poly(vis, Vector2(cv.x, cv.y)) and in_poly(vis, Vector2(cv.x + 1, cv.y)) and in_poly(vis, Vector2(cv.x, cv.y + 1)) and in_poly(vis, Vector2(cv.x + 1, cv.y + 1))): band[c] = true
	# doorways: one cell in every inner wall between two rooms (into the lift room too)
	for c in walls.keys():
		if band.has(c): continue
		var l := Vector2i(c.x - 1, c.y)
		var rr := Vector2i(c.x + 1, c.y)
		var u := Vector2i(c.x, c.y - 1)
		var dn := Vector2i(c.x, c.y + 1)
		var open_x: bool = (rooms.has(l) or shaft.has(l)) and (rooms.has(rr) or shaft.has(rr)) and posmod(c.y - o, 3) == 1
		var open_z: bool = (rooms.has(u) or shaft.has(u)) and (rooms.has(dn) or shaft.has(dn)) and posmod(c.x - o, 3) == 1
		if open_x or open_z: walls.erase(c)
	# street doors: on each face, a short passage straight in through the wall band to a room
	var door: Array = []
	for i in ns if ns <= 8 else 6:
		var k := i if ns <= 8 else i * 4
		var a: Vector2 = vis[k]
		var b2: Vector2 = vis[(k + 1) % ns]
		var mid := (a + b2) * 0.5
		var nrm := (mid - C).normalized()
		var e := Vector2i(int(signf(nrm.x)), 0) if absf(nrm.x) >= absf(nrm.y) else Vector2i(0, int(signf(nrm.y)))
		var c0 := Vector2i(floori(mid.x - nrm.x * 0.6), floori(mid.y - nrm.y * 0.6))
		if not cells.has(c0): continue
		var guard := 0
		while cells.has(c0 + e) and guard < 6:
			c0 += e
			guard += 1
		var chain: Array = []
		var c1 := c0
		while walls.has(c1) and chain.size() < 5:
			chain.append(c1)
			c1 -= e
		if chain.is_empty() or not rooms.has(c1): continue
		for q in chain:
			if not door.has(q): door.append(q)
	var crowns := {"round": ["dome", "dome", "halo"], "oct": ["dome", "spire"], "hex": ["spire", "halo", "dome"], "pent": ["halo", "spire"]}
	var cr: Array = crowns[kind]
	return {"kind": kind, "cells": cells, "walls": walls, "rooms": rooms, "shaft": shaft, "door": door, "floors": fl, "size": Vector2i(2 * R + 1, 2 * R + 1),
		"shape": kind, "poly": vis, "centre": C, "radius": R + 0.5 - 0.75 / cos(PI / ns), "sides": ns, "band": band, "crown": cr[rng.randi() % cr.size()]}

## A walkway across the alley between two buildings facing each other (dir = from a to b): at a floor both have, the
## deck from a's facade to b's; it opens a passage through each one's wall band to a room.
static func _bridge(a: Dictionary, b: Dictionary, dir: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var ca: Dictionary = a["cells"]
	var cb: Dictionary = b["cells"]
	var cand: Array = []
	for c in ca:
		if ca.has(c + dir): continue   # a's facade toward b
		var into_a := _passage(a, c, -dir)
		if into_a.is_empty(): continue
		var q: Vector2i = c + dir
		var span: Array = []
		while not cb.has(q) and span.size() < 30:
			span.append(q)
			q += dir
		if not cb.has(q) or span.is_empty(): continue
		var into_b := _passage(b, q, dir)
		if into_b.is_empty(): continue
		var fmax := mini(int(ca[c]), int(cb[q])) - 1
		if fmax < 1: continue
		cand.append([into_a + into_b, span, fmax])
	if cand.is_empty(): return {}
	var pick: Array = cand[rng.randi() % cand.size()]
	return {"cells": pick[1], "f": rng.randi_range(1, mini(int(pick[2]), 4)), "ends": pick[0], "dir": dir}

## The wall cells from facade cell c straight in (step e) to the first room ([] if no room within 4).
static func _passage(b: Dictionary, c: Vector2i, e: Vector2i) -> Array:
	var out: Array = []
	var q := c
	while (b["walls"] as Dictionary).has(q) and out.size() < 4:
		out.append(q)
		q += e
	if out.is_empty() or not (b["rooms"] as Dictionary).has(q): return []
	return out

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
	# v13.280: each building its real shape: glass and panel bands each floor, a glowing rim, the roof
	var trim: Color = Data.CITY_TRIM
	for b in plan["buildings"]:
		if not b.has("poly"): continue
		var pw: Array = []
		for q in b["poly"]: pw.append(org + (q as Vector2) * s)
		var cw: Vector2 = org + (b["centre"] as Vector2) * s
		var fl: int = b["floors"]
		var np := pw.size()
		for e in np:
			var a: Vector2 = pw[e]
			var bb: Vector2 = pw[(e + 1) % np]
			var o2 := ((a + bb) * 0.5 - cw).normalized()
			var nrm := Vector3(o2.x, 0, o2.y)
			for f in fl:
				var y0f := g + f * Data.CITY_FLOOR_LAYERS * s
				_quad(st, Vector3(a.x, y0f + s, a.y), Vector3(bb.x, y0f + s, bb.y), Vector3(bb.x, y0f, bb.y), Vector3(a.x, y0f, a.y), nrm, Data.CITY_GLASS.lerp(Data.CITY_WINDOW_LIT, 0.2))
				_quad(st, Vector3(a.x, y0f + 2.0 * s - 0.5, a.y), Vector3(bb.x, y0f + 2.0 * s - 0.5, bb.y), Vector3(bb.x, y0f + s, bb.y), Vector3(a.x, y0f + s, a.y), nrm, Data.CITY_PANEL)
				_quad(st, Vector3(a.x, y0f + 2.0 * s, a.y), Vector3(bb.x, y0f + 2.0 * s, bb.y), Vector3(bb.x, y0f + 2.0 * s - 0.5, bb.y), Vector3(a.x, y0f + 2.0 * s - 0.5, a.y), nrm, trim)
		var top_b := roof(g, fl)
		for k in range(1, np - 1):
			_quad(st, Vector3((pw[0] as Vector2).x, top_b, (pw[0] as Vector2).y), Vector3((pw[k] as Vector2).x, top_b, (pw[k] as Vector2).y), Vector3((pw[k + 1] as Vector2).x, top_b, (pw[k + 1] as Vector2).y), Vector3((pw[k + 1] as Vector2).x, top_b, (pw[k + 1] as Vector2).y), Vector3.UP, wall_c)
	for c in cells:
		var cv: Vector2i = c
		var on_shape := false
		for b in plan["buildings"]:
			if b.has("poly") and (b["cells"] as Dictionary).has(cv): on_shape = true
		if on_shape: continue
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
