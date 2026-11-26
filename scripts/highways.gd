extends RefCounted
class_name Highways
## v13.345 (owner: "roads linking all the cities across the terrains"): raised highways between a world's cities.
## Each city links to its nearest neighbours (a spanning tree over the city tiles). A highway leaves a city along the
## alley through the middle block of the side facing the other city (clear of the skyways' spiral interchanges, which
## stand on the block lines), runs out straight, sweeps round in a curve, and comes in straight on the far city's
## facing side. Its deck rides high over the land on paired piers, never steeper than Data.HIGHWAY_SLOPE, and comes
## down to the street at each city's edge. Built in planet metres; drawn in whichever tile you are on.

static var _routes := {}   # pid -> [{a: tile, b: tile, pts: PackedVector3Array (planet metres), out_a, out_b}]

static func tile_centre(pid: String, tile: int) -> Vector2:
	var g := Surface.grid(pid)
	return Vector2(float(tile % g) * Surface.TILE, float(tile / g) * Surface.TILE)

## Where a city's highway leaves it toward `toward` (planet metres): [the street point at the city's edge, the way out].
static func exit_of(pid: String, tile: int, toward: Vector2) -> Array:
	var cr := CityPlan.rect(pid, tile)
	var S: float = Data.BLOCK_REGION
	var org := tile_centre(pid, tile) + Vector2(-Surface.EDGE, -Surface.EDGE) + Vector2(cr.position) * S
	var size := Vector2(cr.size) * S
	var c := org + size * 0.5
	var d := toward - c
	if absf(d.x) >= absf(d.y):   # out of the east or west side, along the alley of the middle row of blocks
		var z := org.y + (cr.size.y / 2 + 0.5) * S
		var o := Vector2(signf(d.x), 0.0)
		return [Vector2(org.x + size.x if o.x > 0.0 else org.x, z), o]
	var x := org.x + (cr.size.x / 2 + 0.5) * S
	var o2 := Vector2(0.0, signf(d.y))
	return [Vector2(x, org.y + size.y if o2.y > 0.0 else org.y), o2]

static func routes(pid: String) -> Array:
	if _routes.has(pid): return _routes[pid]
	var out: Array = []
	if not Data.HIGHWAYS or not Data.CITY_TOWERS:
		_routes[pid] = out
		return out
	var cities: Array = CityPlan.city_tiles(pid).keys().filter(func(t): return CityPlan.is_city_tile(pid, int(t)))
	var g := Surface.grid(pid)
	# a spanning tree over the cities, shortest links first, neighbouring tiles only (no wrap round the world)
	var edges: Array = []
	for i in cities.size():
		for j in range(i + 1, cities.size()):
			var a := int(cities[i])
			var b := int(cities[j])
			if absi(a % g - b % g) > 1 or absi(a / g - b / g) > 1: continue
			edges.append([tile_centre(pid, a).distance_to(tile_centre(pid, b)), a, b])
	edges.sort_custom(func(x, y): return x[0] < y[0])
	var group := {}
	for t in cities: group[int(t)] = int(t)
	var find := func(t: int) -> int:
		while group[t] != t: t = group[t]
		return t
	for e in edges:
		var ra: int = find.call(int(e[1]))
		var rb: int = find.call(int(e[2]))
		if ra == rb: continue
		group[ra] = rb
		out.append(_route(pid, int(e[1]), int(e[2])))
	_routes[pid] = out
	return out

static func _route(pid: String, a: int, b: int) -> Dictionary:
	var ca := tile_centre(pid, a) + _city_mid(pid, a)
	var cb := tile_centre(pid, b) + _city_mid(pid, b)
	var ea: Array = exit_of(pid, a, cb)
	var eb: Array = exit_of(pid, b, ca)
	var pa: Vector2 = ea[0]
	var pb: Vector2 = eb[0]
	var oa: Vector2 = ea[1]
	var ob: Vector2 = eb[1]
	var st: float = Data.HIGHWAY_STRAIGHT   # straight out past the interchanges before it turns
	var p0 := pa + oa * st
	var p3 := pb + ob * st
	var ga := CityPlan.ground(pid, a)
	var gb := CityPlan.ground(pid, b)
	var flat: Array = [pa]
	for q in _valley_path(pid, p0, p3, maxf(ga, gb)): flat.append(q)   # v13.345: along the valleys, round the peaks
	flat.append(pb)
	# heights: over the land by HIGHWAY_CLEAR, never steeper than HIGHWAY_SLOPE, down to each city's street at its ends
	var dist: Array = [0.0]
	for i in range(1, flat.size()): dist.append(float(dist[i - 1]) + (flat[i] as Vector2).distance_to(flat[i - 1]))
	var want: Array = []
	for i in flat.size():
		var p: Vector2 = flat[i]
		want.append(maxf(maxf(Surface.sample(pid, p.x, p.y)[0], 0.0) + Data.HIGHWAY_CLEAR, minf(ga, gb)))
	want[0] = ga
	want[want.size() - 1] = gb
	var y: Array = want.duplicate()
	var s: float = Data.HIGHWAY_SLOPE
	for pass_i in 2:   # the lowest smooth line over every point: each point lifts its neighbours by the slope
		for i in range(1, y.size()): y[i] = maxf(float(y[i]), float(y[i - 1]) - s * (float(dist[i]) - float(dist[i - 1])))
		for i in range(y.size() - 2, -1, -1): y[i] = maxf(float(y[i]), float(y[i + 1]) - s * (float(dist[i + 1]) - float(dist[i])))
	for i in y.size():   # ...and the ends come down to the street (the land is eased flat round a city)
		y[i] = minf(float(y[i]), minf(ga + s * float(dist[i]), gb + s * (float(dist[-1]) - float(dist[i]))))
		y[i] = maxf(float(y[i]), minf(ga, gb))
	var pts := PackedVector3Array()
	var tun: Array = []   # where it runs under the land: [first point, last point] (a tunnel, with a portal at each end)
	var in_t := -1
	for i in flat.size():
		pts.append(Vector3((flat[i] as Vector2).x, float(y[i]) + 0.15, (flat[i] as Vector2).y))
		var under: bool = float(y[i]) < float(want[i]) - Data.HIGHWAY_CLEAR + Data.HIGHWAY_TUNNEL_COVER
		if under and in_t < 0: in_t = i
		if not under and in_t >= 0:
			tun.append([in_t, i - 1])
			in_t = -1
	if in_t >= 0: tun.append([in_t, flat.size() - 1])
	return {"a": a, "b": b, "pts": pts, "out_a": oa, "out_b": ob, "len": float(dist[-1]), "tunnels": tun}

## The cheapest way over the land from p to q (planet metres) on a coarse grid: every metre climbed or dropped costs
## as much as Data.HIGHWAY_CLIMB_COST metres of road, and land high over the cities costs extra, so it keeps to the
## valleys and the passes; then smoothed into curves and cut into even steps.
static func _valley_path(pid: String, p: Vector2, q: Vector2, top: float) -> Array:
	var G: float = Data.HIGHWAY_GRID
	var box := Rect2(p, Vector2.ZERO).expand(q).grow(Data.HIGHWAY_ROAM)
	var nx := int(ceil(box.size.x / G)) + 1
	var nz := int(ceil(box.size.y / G)) + 1
	var hgt := PackedFloat32Array()
	hgt.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			hgt[iz * nx + ix] = maxf(Surface.sample(pid, box.position.x + ix * G, box.position.y + iz * G)[0], 0.0)
	var cell := func(v: Vector2) -> int:
		return clampi(int(round((v.y - box.position.y) / G)), 0, nz - 1) * nx + clampi(int(round((v.x - box.position.x) / G)), 0, nx - 1)
	var s0: int = cell.call(p)
	var s1: int = cell.call(q)
	var cost := {s0: 0.0}
	var came := {}
	var open: Array = [[0.0, s0]]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in open.size(): if float(open[i][0]) < float(open[bi][0]): bi = i
		var cur: int = open[bi][1]
		open.remove_at(bi)
		if done.has(cur): continue
		done[cur] = true
		if cur == s1: break
		var cx := cur % nx
		var cz := cur / nx
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0: continue
				var x2: int = cx + dx
				var z2: int = cz + dz
				if x2 < 0 or z2 < 0 or x2 >= nx or z2 >= nz: continue
				var nb := z2 * nx + x2
				if done.has(nb): continue
				var d := G * (1.4142 if dx != 0 and dz != 0 else 1.0)
				var c2: float = float(cost[cur]) + d + absf(hgt[nb] - hgt[cur]) * Data.HIGHWAY_CLIMB_COST + maxf(0.0, hgt[nb] - top - Data.HIGHWAY_CLEAR) * Data.HIGHWAY_HIGH_COST * d / G
				if c2 < float(cost.get(nb, INF)):
					cost[nb] = c2
					came[nb] = cur
					open.append([c2 + Vector2(x2 - s1 % nx, z2 - s1 / nx).length() * G, nb])
	var cells: Array = [s1]
	while cells[0] != s0 and came.has(cells[0]): cells.push_front(came[cells[0]])
	var raw: Array = [p]
	for i in range(1, cells.size() - 1): raw.append(box.position + Vector2(int(cells[i]) % nx, int(cells[i]) / nx) * G)
	raw.append(q)
	for it in 3:   # smoothed (Chaikin), the two ends kept
		var sm: Array = [raw[0]]
		for i in raw.size() - 1:
			var u: Vector2 = raw[i]
			var v: Vector2 = raw[i + 1]
			sm.append(u.lerp(v, 0.25))
			sm.append(u.lerp(v, 0.75))
		sm.append(raw[raw.size() - 1])
		raw = sm
	var out: Array = [raw[0]]   # even steps
	var carry := 0.0
	for i in range(1, raw.size()):
		var u: Vector2 = raw[i - 1]
		var v: Vector2 = raw[i]
		var L := u.distance_to(v)
		var k := Data.HIGHWAY_STEP - carry
		while k < L:
			out.append(u.lerp(v, k / L))
			k += Data.HIGHWAY_STEP
		carry = L - (k - Data.HIGHWAY_STEP)
	if (out[out.size() - 1] as Vector2).distance_to(q) > 1.0: out.append(q)
	return out

static func _city_mid(pid: String, tile: int) -> Vector2:
	var cr := CityPlan.rect(pid, tile)
	return Vector2(-Surface.EDGE, -Surface.EDGE) + (Vector2(cr.position) + Vector2(cr.size) * 0.5) * Data.BLOCK_REGION

## The highways near this tile, in its own frame (tile-local metres): [{a, b, pts, out_a, out_b, len}].
static func local(pid: String, tile: int) -> Array:
	var c := tile_centre(pid, tile)
	var box := Rect2(c - Vector2(Surface.EDGE, Surface.EDGE), Vector2(Surface.TILE, Surface.TILE)).grow(Data.HIGHWAY_DRAW_GROW)
	var out: Array = []
	for r in routes(pid):
		var near := false
		for p in (r["pts"] as PackedVector3Array):
			if box.has_point(Vector2(p.x, p.z)):
				near = true
				break
		if not near: continue
		var lp := PackedVector3Array()
		for p in (r["pts"] as PackedVector3Array): lp.append(p - Vector3(c.x, 0.0, c.y))
		var d: Dictionary = r.duplicate()
		d["pts"] = lp
		out.append(d)
	return out

## The parts to draw (CityTowers kit): the deck with its walls and lit edges, and paired piers with a cross beam.
static func parts(pid: String, tile: int) -> Array:
	var out: Array = []
	var c := tile_centre(pid, tile)
	for r in local(pid, tile):
		var pts: PackedVector3Array = r["pts"]
		out.append({"k": "ribbon", "pts": pts, "w": Data.HIGHWAY_W, "rail": true, "walk": true})
		for tn in r.get("tunnels", []):   # a portal where it goes into the hill and where it comes out
			for ei in [int(tn[0]), int(tn[1])]:
				var e0 := pts[clampi(ei - 1, 0, pts.size() - 1)]
				var e1 := pts[clampi(ei + 1, 0, pts.size() - 1)]
				var dv := Vector2(e1.x - e0.x, e1.z - e0.z).normalized()
				var sd := Vector2(-dv.y, dv.x)
				var pe := pts[ei]
				var PW: float = Data.HIGHWAY_W * 0.5 + 3.0
				var ax := absf(sd.x) > absf(sd.y)
				for sg in [-1.0, 1.0]:
					var q2: Vector2 = Vector2(pe.x, pe.z) + sd * PW * sg
					out.append({"k": "white", "p": Vector3(q2.x, pe.y - 4.0, q2.y), "s": Vector3(5.0, Data.HIGHWAY_PORTAL_H + 4.0, 5.0)})
				out.append({"k": "white", "p": Vector3(pe.x, pe.y + Data.HIGHWAY_PORTAL_H, pe.z), "s": Vector3(PW * 2.0 + 5.0, 6.0, 6.0) if ax else Vector3(6.0, 6.0, PW * 2.0 + 5.0)})
				out.append({"k": "glow", "p": Vector3(pe.x, pe.y + Data.HIGHWAY_PORTAL_H - 0.4, pe.z), "s": Vector3(PW * 2.0, 0.4, 6.4) if ax else Vector3(6.4, 0.4, PW * 2.0)})
		var run := 0.0
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var seg := Vector2(b.x - a.x, b.z - a.z)
			var L := seg.length()
			if L < 0.01: continue
			var dir := seg / L
			var side := Vector2(-dir.y, dir.x)
			var k := Data.HIGHWAY_PIER_EVERY - run
			while k <= L:
				var p := Vector2(a.x, a.z) + dir * k
				var y := lerpf(a.y, b.y, k / L)
				var gnd := maxf(Surface.sample(pid, p.x + c.x, p.y + c.y)[0], -2.0) - 2.0
				if y - gnd > Data.HIGHWAY_PIER_MIN:
					for sg in [-1.0, 1.0]:
						var q: Vector2 = p + side * Data.HIGHWAY_PIER_OFF * sg
						out.append({"k": "white", "p": Vector3(q.x, gnd, q.y), "s": Vector3(Data.HIGHWAY_PIER_W, y - 3.0 - gnd, Data.HIGHWAY_PIER_W)})
					var beam_l := Data.HIGHWAY_PIER_OFF * 2.0 + Data.HIGHWAY_PIER_W
					var along_x := absf(side.x) > absf(side.y)
					out.append({"k": "white", "p": Vector3(p.x, y - 4.5, p.y), "s": Vector3(beam_l, 3.0, Data.HIGHWAY_PIER_W * 0.8) if along_x else Vector3(Data.HIGHWAY_PIER_W * 0.8, 3.0, beam_l)})
				k += Data.HIGHWAY_PIER_EVERY
			run = L - (k - Data.HIGHWAY_PIER_EVERY)
	return out
