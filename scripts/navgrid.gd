class_name NavGrid
extends RefCounted
## Job S (v1.4p): the GPS-style view shared by the navigation map and the HUD radar.
##  - one projection: north-up or heading-up, flat overhead or angled (a slight tilt with a little depth)
##  - a layered holographic grid that keeps revealing finer lines as you zoom in
##  - low-poly faceted shapes (polygon circles with straight edges, lit side / shadow side / rim light)
##  - the info-card pictures, with a per-type fallback so a card never shows a broken image
## All numbers are in the "Job S" block of scripts/data.gd.

const CYAN := Color(0.4, 0.86, 1.0)
const LIGHT := Vector2(-0.64, -0.77)   # where the light comes from on screen (upper left)

# ---------------------------------------------------------------- the player's choice (saved with the settings)
static var orient := "north"    # "north" = north-up, never rotates | "heading" = the map turns round the ship
static var tilt := "angled"     # "angled" = GPS-style tilt | "flat" = straight down
static var _loaded := false
static var path: String = Data.SETTINGS_PATH   # where the choice is kept (the route test points this at its own file)

static func load_prefs() -> void:
	_loaded = true
	orient = Data.NAV_ORIENT_DEFAULT
	tilt = Data.NAV_TILT_DEFAULT
	var cf := ConfigFile.new()
	if cf.load(path) != OK: return
	var o = cf.get_value("nav", "orient", Data.NAV_ORIENT_DEFAULT)
	var t = cf.get_value("nav", "tilt", Data.NAV_TILT_DEFAULT)
	if o is String and o in ["north", "heading"]: orient = o
	if t is String and t in ["angled", "flat"]: tilt = t

## Writes only the "nav" section; everything else in the settings file is kept as it is.
static func save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value("nav", "orient", orient)
	cf.set_value("nav", "tilt", tilt)
	cf.save(path)

static func toggle_orient() -> String:
	orient = "heading" if orient == "north" else "north"
	save_prefs()
	return orient

static func toggle_tilt() -> String:
	tilt = "flat" if tilt == "angled" else "angled"
	save_prefs()
	return tilt

# ---------------------------------------------------------------- one view (projection)
var anchor := Vector2.ZERO       # screen point the centre of the view maps to
var center := Vector3.ZERO       # world point at the anchor
var k := 1.0                     # pixels per metre at the anchor
var rot := 0.0                   # radians the map is turned (0 = north up)
var angled := false
var depth := 900.0               # camera distance in pixels for the angled view (bigger = flatter)
var major_px: float = Data.NAV_GRID_MAJOR_PX   # bold lines are this to 5x this apart (the small radar uses less)

## Set the view up. heading_fwd = the ship's forward (world) for heading-up, Vector3.ZERO for north-up.
func setup(p_anchor: Vector2, p_center: Vector3, p_k: float, heading_fwd: Vector3, p_angled: bool, p_depth: float) -> void:
	anchor = p_anchor
	center = p_center
	k = p_k
	angled = p_angled
	depth = maxf(p_depth, 50.0)
	rot = heading_rot(heading_fwd)

## How far the map must turn so this forward direction points straight up the screen. North is -Z.
static func heading_rot(fwd: Vector3) -> float:
	var f := Vector2(fwd.x, fwd.z)
	if f.length() < 0.001: return 0.0
	return -PI * 0.5 - f.angle()

## Screen angle of true north, measured clockwise from "up" (0 = north is up).
func north_angle() -> float:
	return wrapf(rot, -PI, PI)

func _flat(p: Vector3) -> Vector2:
	return (Vector2(p.x - center.x, p.z - center.z) * k).rotated(rot)

func persp_at_flat(f: Vector2) -> float:
	if not angled: return 1.0
	return depth / maxf(depth - f.y * sin(Data.NAV_TILT), depth * 0.2)

func persp(p: Vector3) -> float:
	return persp_at_flat(_flat(p))

func to_screen(p: Vector3) -> Vector2:
	var f := _flat(p)
	if not angled: return anchor + f
	var s := persp_at_flat(f)
	return anchor + Vector2(f.x * s, f.y * cos(Data.NAV_TILT) * s)

## Screen point back to the world (on the map plane). The exact inverse of to_screen.
func to_world(sp: Vector2) -> Vector3:
	var f := sp - anchor
	if angled:
		var ct := cos(Data.NAV_TILT)
		var st := sin(Data.NAV_TILT)
		var fy := f.y * depth / maxf(depth * ct + f.y * st, 1.0)
		var s := depth / maxf(depth - fy * st, depth * 0.2)
		f = Vector2(f.x / s, fy)
	f = f.rotated(-rot) / k
	return Vector3(center.x + f.x, 0.0, center.z + f.y)

# ---------------------------------------------------------------- the grid
## The three grid layers for a zoom level: major lines, minor lines, micro-ticks. Each is [spacing in metres,
## spacing in pixels, alpha]. Major lines are always between NAV_GRID_MAJOR_PX and 5x that apart, so zooming in
## turns minors into majors and ticks into minors without a jump.
static func levels(scale_k: float, base_px: float = Data.NAV_GRID_MAJOR_PX) -> Array:
	var major: float = 1.0
	var want: float = base_px / maxf(scale_k, 0.000001)
	major = pow(5.0, ceilf(log(want) / log(5.0)))
	var mpx := major * scale_k
	var t := clampf((mpx / 5.0 - base_px / 5.0) / (base_px * 0.8), 0.0, 1.0)
	return [
		[major, mpx, Data.NAV_GRID_ALPHA[0]],
		[major / 5.0, mpx / 5.0, lerpf(Data.NAV_GRID_ALPHA[1], Data.NAV_GRID_ALPHA[0], t)],
		[major / 25.0, mpx / 25.0, lerpf(0.0, Data.NAV_GRID_ALPHA[2], clampf((mpx / 25.0 - 7.0) / 10.0, 0.0, 1.0))],
	]

## Clip a segment to a rectangle (Liang-Barsky). Returns [] when it misses.
static func clip_rect(a: Vector2, b: Vector2, r: Rect2) -> Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for e in [[-d.x, a.x - r.position.x], [d.x, r.end.x - a.x], [-d.y, a.y - r.position.y], [d.y, r.end.y - a.y]]:
		var p: float = e[0]
		var q: float = e[1]
		if absf(p) < 0.000001:
			if q < 0.0: return []
			continue
		var tt := q / p
		if p < 0.0: t0 = maxf(t0, tt)
		else: t1 = minf(t1, tt)
		if t0 > t1: return []
	return [a + d * t0, a + d * t1]

## Clip a segment to a circle. Returns [] when it misses.
static func clip_circle(a: Vector2, b: Vector2, c: Vector2, r: float) -> Array:
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	if qa < 0.000001: return [a, b] if f.length() <= r else []
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc <= 0.0: return []
	var sq := sqrt(disc)
	var t0 := maxf(0.0, (-qb - sq) / (2.0 * qa))
	var t1 := minf(1.0, (-qb + sq) / (2.0 * qa))
	if t0 >= t1: return []
	return [a + d * t0, a + d * t1]

func _clip(a: Vector2, b: Vector2, rect: Rect2, circle_r: float) -> Array:
	return clip_circle(a, b, rect.get_center(), circle_r) if circle_r > 0.0 else clip_rect(a, b, rect)

## Draw the grid into `rect` (or into the circle of radius circle_r round its centre). `through` = world points
## that must sit on a grid crossing: a pair of lines is drawn through each. Returns what was drawn, for the tests:
## {"major": n, "minor": n, "ticks": n, "through": n, "spacing": metres between major lines, "labels": [...]}
func draw_grid(ci: CanvasItem, rect: Rect2, circle_r := 0.0, through: Array = [], labels := false, font: Font = null) -> Dictionary:
	var lv := levels(k, major_px)
	# the part of the world this window can see
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var w := to_world(corner)
		mn = Vector2(minf(mn.x, w.x), minf(mn.y, w.z))
		mx = Vector2(maxf(mx.x, w.x), maxf(mx.y, w.z))
	var out := {"major": 0, "minor": 0, "ticks": 0, "through": 0, "spacing": lv[0][0], "labels": []}
	var major_step: float = lv[0][0]
	for li in [1, 0]:   # minor first, major on top
		var step: float = lv[li][0]
		var pts := PackedVector2Array()
		for axis in 2:
			var lo: float = mn.x if axis == 0 else mn.y
			var hi: float = mx.x if axis == 0 else mx.y
			var n0 := int(floor(lo / step))
			var n1 := int(ceil(hi / step))
			if n1 - n0 > Data.NAV_GRID_MAX_LINES: continue
			for n in range(n0, n1 + 1):
				if li == 1 and n % 5 == 0: continue   # that one is a major line
				var v := n * step
				var a := to_screen(Vector3(v, 0, mn.y) if axis == 0 else Vector3(mn.x, 0, v))
				var b := to_screen(Vector3(v, 0, mx.y) if axis == 0 else Vector3(mx.x, 0, v))
				var seg := _clip(a, b, rect, circle_r)
				if seg.is_empty(): continue
				pts.append(seg[0])
				pts.append(seg[1])
				if li == 0 and labels: out["labels"].append([seg[0], seg[1], ("X " if axis == 0 else "Z ") + _km(v)])
		if pts.size() >= 2:
			if li == 0:
				ci.draw_multiline(pts, Color(CYAN, lv[0][2] * 0.35), Data.NAV_GRID_WIDTH[0] + 4.0)   # glow under the bold lines
				ci.draw_multiline(pts, Color(CYAN.lightened(0.25), lv[0][2]), Data.NAV_GRID_WIDTH[0])
				out["major"] = pts.size() / 2
			else:
				ci.draw_multiline(pts, Color(CYAN, lv[1][2]), Data.NAV_GRID_WIDTH[1])
				out["minor"] = pts.size() / 2
	# micro-ticks: ruler marks along the major lines
	if lv[2][2] > 0.02:
		var tick: float = lv[2][0]
		var tp := PackedVector2Array()
		var half := tick * 0.28
		for axis in 2:
			var lo2: float = mn.x if axis == 0 else mn.y
			var hi2: float = mx.x if axis == 0 else mx.y
			var lo3: float = mn.y if axis == 0 else mn.x
			var hi3: float = mx.y if axis == 0 else mx.x
			var m0 := int(floor(lo2 / major_step))
			var m1 := int(ceil(hi2 / major_step))
			var t0 := int(floor(lo3 / tick))
			var t1 := int(ceil(hi3 / tick))
			if (m1 - m0 + 1) * (t1 - t0 + 1) > Data.NAV_GRID_MAX_TICKS: continue
			for m in range(m0, m1 + 1):
				var mv := m * major_step
				for tn in range(t0, t1 + 1):
					if tn % 5 == 0: continue
					var tv := tn * tick
					var a2 := to_screen(Vector3(mv - half, 0, tv) if axis == 0 else Vector3(tv, 0, mv - half))
					var b2 := to_screen(Vector3(mv + half, 0, tv) if axis == 0 else Vector3(tv, 0, mv + half))
					var seg2 := _clip(a2, b2, rect, circle_r)
					if seg2.is_empty(): continue
					tp.append(seg2[0])
					tp.append(seg2[1])
		if tp.size() >= 2:
			ci.draw_multiline(tp, Color(CYAN.lightened(0.3), lv[2][2]), 1.0)
			out["ticks"] = tp.size() / 2
	# a grid crossing under every object
	var op := PackedVector2Array()
	for w3: Vector3 in through:
		for axis in 2:
			var a3 := to_screen(Vector3(w3.x, 0, mn.y) if axis == 0 else Vector3(mn.x, 0, w3.z))
			var b3 := to_screen(Vector3(w3.x, 0, mx.y) if axis == 0 else Vector3(mx.x, 0, w3.z))
			var seg3 := _clip(a3, b3, rect, circle_r)
			if seg3.is_empty(): continue
			op.append(seg3[0])
			op.append(seg3[1])
	if op.size() >= 2:
		ci.draw_multiline(op, Color(CYAN, Data.NAV_GRID_ALPHA[1] * 1.6), 1.0)
		out["through"] = op.size() / 2
	if labels and font != null:
		for lb in out["labels"]:
			var at: Vector2 = lb[0] if (lb[0] as Vector2).y < (lb[1] as Vector2).y or (lb[0] as Vector2).x < (lb[1] as Vector2).x else lb[1]
			at = at.clamp(rect.position + Vector2(4, 14), rect.end - Vector2(64, 4))
			ci.draw_string(font, at + Vector2(3, 0), lb[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(CYAN.lightened(0.3), 0.75))
	return out

static func _km(v: float) -> String:
	return "%.1fk" % (v / 1000.0) if absf(v) >= 1000.0 else "%d" % int(v)

# ---------------------------------------------------------------- faceted shapes (straight edges only)
## Fill a polygon, skipping any that has collapsed to a line (tiny or edge-on shapes), which the renderer rejects.
static func fill(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	var n := pts.size()
	if n < 3: return
	var area := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		if is_nan(a.x) or is_nan(a.y) or absf(a.x) > 20000.0 or absf(a.y) > 20000.0: return   # far off screen: nothing to see, and too big for the renderer
		area += a.x * b.y - b.x * a.y
	if absf(area) < 1.0: return
	ci.draw_colored_polygon(pts, col)

static func poly(c: Vector2, r: float, sides: int, turn := 0.0, squash := 1.0) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in sides:
		var a := turn + TAU * float(i) / float(sides)
		p.append(c + Vector2(cos(a) * r, sin(a) * r * squash))
	return p

static func _lit(dir: Vector2, amount := 1.0) -> float:
	return clampf(0.32 + 0.68 * maxf(0.0, dir.normalized().dot(LIGHT) * amount + (1.0 - amount)), 0.0, 1.0)

static func _shade(col: Color, l: float) -> Color:
	return Color(col.r * l, col.g * l, col.b * l, col.a)

## The soft shadow / glow a body casts onto the grid under it.
static func cast(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	fill(ci, poly(c + Vector2(r * 0.3, r * 0.55), r * 1.15, 14, 0.0, 0.36), Color(0, 0, 0, 0.42))
	fill(ci, poly(c, r * 1.32, 16), Color(col, 0.1))

## A planet / moon / star body: a polygon circle built from two rings of flat facets, lit from the upper left.
static func sphere(ci: CanvasItem, c: Vector2, r: float, col: Color, sides := 16, glow := true) -> void:
	sides = clampi(sides, 12, 20)
	if glow: cast(ci, c, r, col)
	var outer := poly(c, r, sides)
	var inner := poly(c + LIGHT * r * 0.14, r * 0.58, sides)
	for i in sides:
		var j := (i + 1) % sides
		var mid := (outer[i] + outer[j]) * 0.5 - c
		fill(ci, PackedVector2Array([outer[i], outer[j], inner[j], inner[i]]), _shade(col, _lit(mid, 1.0)))
		fill(ci, PackedVector2Array([inner[i], inner[j], c + LIGHT * r * 0.2]), _shade(col.lightened(0.12), _lit(mid, 0.45)))
	# thin glowing grid lines across the facets
	var gl := Color(col.lightened(0.55), 0.55)
	ci.draw_polyline(inner + PackedVector2Array([inner[0]]), gl, 1.0)
	ci.draw_polyline(PackedVector2Array([c + Vector2(-r, 0), c + Vector2(-r * 0.5, r * 0.16), c + Vector2(r * 0.5, r * 0.16), c + Vector2(r, 0)]), gl, 1.0)
	ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.18, -r * 0.5), c + Vector2(r * 0.18, r * 0.5), c + Vector2(0, r)]), gl, 1.0)
	# rim light on the lit edge, a dark rim on the shadow edge
	for i in sides:
		var j2 := (i + 1) % sides
		var d := ((outer[i] + outer[j2]) * 0.5 - c).normalized().dot(LIGHT)
		if d > 0.25: ci.draw_line(outer[i], outer[j2], Color(col.lightened(0.7), 0.95), 2.0)
		elif d < -0.25: ci.draw_line(outer[i], outer[j2], Color(0, 0, 0, 0.55), 1.5)

## A star: a faceted bright body with straight spikes.
static func star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	fill(ci, poly(c, r * 2.0, 12), Color(col, 0.12))
	for i in 8:
		var a := TAU * i / 8.0
		var n := Vector2(cos(a), sin(a))
		var side := Vector2(-n.y, n.x) * r * 0.22
		fill(ci, PackedVector2Array([c + n * r * (1.9 if i % 2 == 0 else 1.45), c + side, c - side]), Color(col.lightened(0.3), 0.85))
	sphere(ci, c, r, col.lightened(0.15), 12, false)

## A ring with thickness (stations, gates): the top face in lit facets, the wall below it darker.
static func ring(ci: CanvasItem, c: Vector2, r: float, col: Color, sides: int, width := 0.3, lift := 0.18, squash := 0.62) -> void:
	sides = clampi(sides, 6, 20)
	var h := r * lift
	var o := poly(c, r, sides, PI / sides, squash)
	var inn := poly(c, r * (1.0 - width), sides, PI / sides, squash)
	fill(ci, poly(c + Vector2(r * 0.25, h + r * 0.4), r * 1.1, 14, 0.0, squash * 0.6), Color(0, 0, 0, 0.4))
	for i in sides:   # the wall (thickness)
		var j := (i + 1) % sides
		if (o[i].y + o[j].y) * 0.5 >= c.y - 0.5:
			fill(ci, PackedVector2Array([o[i], o[j], o[j] + Vector2(0, h), o[i] + Vector2(0, h)]), _shade(col, 0.3 + 0.25 * _lit((o[i] + o[j]) * 0.5 - c)))
		else:
			fill(ci, PackedVector2Array([inn[i], inn[j], inn[j] + Vector2(0, h), inn[i] + Vector2(0, h)]), _shade(col, 0.22))
	for i in sides:   # the top face
		var j2 := (i + 1) % sides
		var mid := (o[i] + o[j2]) * 0.5 - c
		fill(ci, PackedVector2Array([o[i], o[j2], inn[j2], inn[i]]), _shade(col, _lit(mid, 0.8)))
		ci.draw_line(inn[i], o[i], Color(col.lightened(0.6), 0.5), 1.0)   # grid lines across the facets
		if mid.normalized().dot(LIGHT) > 0.2: ci.draw_line(o[i], o[j2], Color(col.lightened(0.75), 0.95), 2.0)

static func station(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	fill(ci, poly(c, r * 1.5, 12), Color(col, 0.1))
	ring(ci, c, r, col, 8, 0.3, 0.2)
	var hub := poly(c - Vector2(0, r * 0.12), r * 0.34, 6, PI / 6.0, 0.7)
	for i in 6:
		var j := (i + 1) % 6
		fill(ci, PackedVector2Array([hub[i], hub[j], c - Vector2(0, r * 0.3)]), _shade(col.lightened(0.2), _lit((hub[i] + hub[j]) * 0.5 - c, 0.8)))
	for i in 4:
		var a := PI / 4.0 + TAU * i / 4.0
		ci.draw_line(c - Vector2(0, r * 0.12), c + Vector2(cos(a) * r * 0.72, sin(a) * r * 0.72 * 0.62), Color(col.lightened(0.4), 0.8), 1.5)

static func gate(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	fill(ci, poly(c, r * 1.5, 12), Color(col, 0.12))
	ring(ci, c, r, col, 12, 0.24, 0.16, 0.8)
	fill(ci, poly(c, r * 0.7, 12, PI / 12.0, 0.8), Color(0.5, 0.85, 1.0, 0.22))
	ci.draw_polyline(poly(c, r * 0.42, 12, 0.0, 0.8) + PackedVector2Array([c + Vector2(r * 0.42, 0)]), Color(0.7, 0.92, 1.0, 0.6), 1.0)

## One low-poly rock. seed picks its outline.
static func rock(ci: CanvasItem, c: Vector2, r: float, col: Color, seed_i: int) -> void:
	var n := 5 + seed_i % 3
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n + seed_i * 0.7
		var rr := r * (0.7 + 0.3 * absf(sin(seed_i * 12.9898 + i * 4.1)))
		pts.append(c + Vector2(cos(a), sin(a) * 0.82) * rr)
	for i in n:
		var j := (i + 1) % n
		fill(ci, PackedVector2Array([c, pts[i], pts[j]]), _shade(col, _lit((pts[i] + pts[j]) * 0.5 - c)))

## A nebula: a translucent faceted cloud lying on the grid.
static func cloud(ci: CanvasItem, pts: PackedVector2Array, c: Vector2, col: Color) -> void:
	if pts.size() < 3: return
	for i in pts.size():
		var j := (i + 1) % pts.size()
		fill(ci, PackedVector2Array([c, pts[i], pts[j]]), Color(_shade(col, 0.55 + 0.45 * _lit((pts[i] + pts[j]) * 0.5 - c)), 0.3))
		if i % 2 == 0: ci.draw_line(c, pts[i], Color(col.lightened(0.5), 0.3), 1.0)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col.lightened(0.5), 0.75), 1.5)

## A ship / contact: a two-tone faceted dart pointing along `dir`.
static func dart(ci: CanvasItem, c: Vector2, size: float, dir: Vector2, col: Color, outline := false) -> void:
	if dir.length() < 0.001: dir = Vector2(0, -1)
	dir = dir.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var nose := c + dir * size
	var tail := c - dir * size * 0.35
	var l := c - dir * size * 0.75 - perp * size * 0.7
	var r := c - dir * size * 0.75 + perp * size * 0.7
	fill(ci, PackedVector2Array([nose, tail, l]), _shade(col, 1.0 if perp.dot(LIGHT) < 0.0 else 0.55))
	fill(ci, PackedVector2Array([nose, r, tail]), _shade(col, 1.0 if perp.dot(LIGHT) >= 0.0 else 0.55))
	if outline: ci.draw_polyline(PackedVector2Array([nose, r, tail, l, nose]), Color(1, 1, 1, 0.9), 1.5)

## Glowing selection brackets round a point.
static func brackets(ci: CanvasItem, c: Vector2, half: float, col: Color, pulse := 0.0) -> void:
	var s := half + 3.0 * pulse
	var arm := maxf(7.0, s * 0.45)
	for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner: Vector2 = c + q * s
		for w in [[7.0, 0.25], [3.0, 1.0]]:
			ci.draw_line(corner, corner - Vector2(q.x * arm, 0), Color(col, w[1]), w[0])
			ci.draw_line(corner, corner - Vector2(0, q.y * arm), Color(col, w[1]), w[0])

## A circle lying on the map plane (orbit path, range ring, belt): a closed polygon through the projection.
func plane_ring(world_c: Vector3, radius: float, sides := 16) -> PackedVector2Array:
	var p := PackedVector2Array()
	sides = clampi(sides, 12, 20)
	for i in sides + 1:
		var a := TAU * float(i % sides) / float(sides)
		p.append(to_screen(world_c + Vector3(cos(a) * radius, 0, sin(a) * radius)))
	return p

## The compass: a faceted needle that always points at true north, with an N on its tip.
static func compass(ci: CanvasItem, c: Vector2, r: float, north: float, font: Font, font_size := 15) -> void:
	fill(ci, poly(c, r, 12), Color(0.02, 0.08, 0.14, 0.85))
	ci.draw_polyline(poly(c, r, 12) + PackedVector2Array([c + Vector2(r, 0)]), Color(CYAN, 0.8), 1.5)
	var n := Vector2(0, -1).rotated(north)
	var perp := Vector2(-n.y, n.x)
	fill(ci, PackedVector2Array([c + n * r * 0.78, c + perp * r * 0.26, c]), Color(1.0, 0.45, 0.4))
	fill(ci, PackedVector2Array([c + n * r * 0.78, c, c - perp * r * 0.26]), Color(0.75, 0.25, 0.25))
	fill(ci, PackedVector2Array([c - n * r * 0.6, c - perp * r * 0.22, c + perp * r * 0.22]), Color(0.75, 0.85, 0.95, 0.75))
	if font: ci.draw_string(font, c + n * (r + font_size * 0.75) + Vector2(-font_size * 0.36, font_size * 0.36), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1))

## A thick glowing route line with a pulsing destination pin.
static func route(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, t: float, pin := true, scale := 1.0) -> void:
	for w in [[Data.NAV_ROUTE_WIDTH * 2.6, 0.14], [Data.NAV_ROUTE_WIDTH * 1.6, 0.3], [Data.NAV_ROUTE_WIDTH, 0.95]]:
		ci.draw_line(a, b, Color(col, w[1]), w[0] * scale, true)
	ci.draw_line(a, b, Color(1, 1, 1, 0.85), maxf(1.0, Data.NAV_ROUTE_WIDTH * 0.25 * scale), true)
	var len := a.distance_to(b)
	if len > 30.0:   # chevrons running toward the destination
		var d := (b - a) / len
		var perp := Vector2(-d.y, d.x)
		var gap := 34.0 * scale
		var off := fmod(t * 40.0, gap)
		var x := off
		while x < len - 10.0:
			var p := a + d * x
			ci.draw_polyline(PackedVector2Array([p - d * 5.0 * scale + perp * 5.0 * scale, p + d * 2.0 * scale, p - d * 5.0 * scale - perp * 5.0 * scale]), Color(1, 1, 1, 0.8), 1.5)
			x += gap
	if pin:
		var pulse := 1.0 + Data.NAV_PIN_PULSE * sin(t * 5.0)
		var pr := 9.0 * scale * pulse
		fill(ci, poly(b, pr * 2.2, 12), Color(col, 0.18 + 0.12 * sin(t * 5.0)))
		var head := b + Vector2(0, -pr * 2.1)
		fill(ci, PackedVector2Array([b, head + Vector2(-pr * 0.8, pr * 0.35), head + Vector2(pr * 0.8, pr * 0.35)]), col)
		fill(ci, poly(head, pr, 12), col)
		fill(ci, poly(head, pr * 0.42, 8), Color(1, 1, 1))

# ---------------------------------------------------------------- info-card pictures
static var _tex := {}

static func _load(path: String) -> Texture2D:
	if not _tex.has(path): _tex[path] = load(path) if path != "" and ResourceLoader.exists(path) else null
	return _tex[path]

## The picture for an info card: the object's own image when the game has one, else its type's picture.
## Returns [texture or null, used_fallback]. null only when even the type picture is missing (the card then draws
## a code-made icon), so a card never shows a broken image.
static func picture(own_path: String, type: String) -> Array:
	var own := _load(own_path)
	if own != null: return [own, false]
	return [_load(Data.NAV_TYPE_PICTURES.get(type, "")), true]

## Which world map a planet wears (same rule as the 3D planet in flight), "" when the worlds pack is not in yet.
static func planet_picture(d: Dictionary) -> String:
	if not Packs.is_ready("worlds"): return ""
	var v: Array = SpaceSystem.PLANET_MAPS.get(d.get("palette", "terran"), SpaceSystem.PLANET_MAPS["terran"])
	return "res://assets/worlds/%s.jpg" % v[absi(hash(d["id"])) % v.size()][0]
