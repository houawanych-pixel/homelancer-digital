class_name CityTowers
extends RefCounted
## v13.302 (owner: "now this is a city: look at the shapes, look at the colours, look at the size. Build this city"; his
## concept art: white sci-fi megatowers): every city building is a walkable podium (the BlockField floors with rooms,
## doors, lifts) and, on top of it, a megatower drawn as one clean mesh:
##   - stacked tiers that step in as they rise, each a cut (chamfered) prism, white panelled armour (panel lines and
##     tints from the shader, no texture), a dark recessed spine up the main faces with cyan light strips and ribs,
##     a glowing ledge at each tier top; round towers get stacked saucer decks with glowing rims instead;
##   - buttress legs flaring out at the foot of the big ones; needle spires on top;
##   - sky bridges between the big towers of a block, and a landing pad off the big ones.
## Heights: the downtown block's big towers Data.TOWER_H_DOWNTOWN, other big ones Data.TOWER_H_MAIN, the slim ones
## Data.TOWER_H_SLIM. The mesh is in tile-local metres. `far` makes the cheap version for the far skyline.
## Also returns collision triangles (the tiers, ledges, saucers and bridges) for the solid hull.

const SPINE := 0   # (UV.y: what a face is, for the shader)
const PANEL := 1
const GLOW := 2
const GLASS := 3

## A tower for one building of a block plan: {c (tile-local m), r (m), sides, rot, base (y), h (m over base), main, seed}.
static func spec(b: Dictionary, org: Vector2, g_roof: float, downtown: bool, key: String) -> Dictionary:
	var s: float = Data.BLOCK_MIN
	var c: Vector2 = org + (b["centre"] as Vector2) * s
	var pts: Array = []
	for q in b["poly"]: pts.append(org + (q as Vector2) * s)
	var r: float = float(b["radius"]) * s
	var p0: Vector2 = pts[0]
	var rot := atan2(p0.y - c.y, p0.x - c.x)
	var seed := absi(hash("%s|%s|tower" % [key, str(b["at"])]))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var main: bool = bool(b.get("main", false))
	var hr: Vector2 = Data.TOWER_H_DOWNTOWN if downtown and main else (Data.TOWER_H_MAIN if main else Data.TOWER_H_SLIM)
	return {"c": c, "r": r * Data.TOWER_INSET, "sides": int(b.get("sides", 6)), "rot": rot, "base": g_roof, "h": rng.randf_range(hr.x, hr.y),
		"main": main, "seed": seed, "kind": str(b.get("kind", "hex"))}

## The whole block's towers (and bridges between the big ones) as one mesh: [ArrayMesh, PackedVector3Array collision].
static func build(towers: Array, bridges: Array, far: bool) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := PackedVector3Array()
	for t in towers: _tower(st, col, t, far)
	for br in bridges: _sky_bridge(st, col, br, far)
	return [st.commit(), col]

## Sky bridges between pairs of big towers: [{a: spec, b: spec, y}].
static func bridges_for(towers: Array, seed: int) -> Array:
	var mains: Array = towers.filter(func(t): return bool(t["main"]))
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in mains.size():
		for j in range(i + 1, mains.size()):
			var a: Dictionary = mains[i]
			var b: Dictionary = mains[j]
			var d: float = (a["c"] as Vector2).distance_to(b["c"])
			if d > Data.TOWER_BRIDGE_MAX or rng.randf() > Data.TOWER_BRIDGE_CHANCE: continue
			var top: float = minf(float(a["base"]) + float(a["h"]), float(b["base"]) + float(b["h"]))
			var low: float = maxf(float(a["base"]), float(b["base"]))
			for k in rng.randi_range(1, 2):
				out.append({"a": a, "b": b, "y": lerpf(low, top, rng.randf_range(0.22, 0.6))})
	return out

# ---------------------------------------------------------------------------------------------------------------- one tower
## The massing first (owner: "take its basic 3D shape first"), three shapes from his art:
##   tiered:    a wide cut octagon stepping in tier by tier (1, .78, .6, .45 ...) to a needle spire; a block giant stands
##              on buttress legs down to the street;
##   cathedral: a tall middle with two shoulder towers fused to its sides (each about 2/3 as tall, their own spires);
##   saucer:    a round core with wide saucer decks stacked up it, getting smaller toward the top.
static func _tower(st: SurfaceTool, col: PackedVector3Array, t: Dictionary, far: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t["seed"])
	var c: Vector2 = t["c"]
	var r: float = t["r"]
	var rot: float = t["rot"]
	var y: float = t["base"]
	var H: float = t["h"]
	var main: bool = t["main"]
	var style := str(t.get("style", "tiered"))
	var ground: float = float(t.get("ground", y))
	var white := Data.TOWER_WHITE
	var trim: Color = Data.CITY_TRIM
	if main and y > ground + 1.0:   # raised on its podium: the underside, and legs down to the street
		_cap(st, _chamfered(c, r, 8, rot, Data.TOWER_CHAMFER), y, Data.TOWER_SPINE * 1.6, true)
		if not far and style != "saucer": _legs(st, col, c, r, 8, rot, y, ground, white, trim)
	if main and style != "saucer":   # a landing pad off one face (the draws always, so far and near come out the same)
		var pad_roll := rng.randf()
		var pad_face := rng.randi_range(0, 3)
		var pad_h := rng.randf_range(0.18, 0.3)
		if not far and pad_roll < Data.TOWER_PAD_CHANCE:
			_pad(st, col, c, r * (0.6 if style == "cathedral" else 0.82), rot + PI / 8.0 * (1 + 2 * pad_face) + (PI / 2.0 if style == "cathedral" else 0.0), y + H * pad_h)
	match style:
		"cathedral":
			var ax := Vector2(cos(rot), sin(rot))
			var cr2 := r * 0.72
			_stack(st, col, c, cr2, 8, rot, y, H, Data.TOWER_TIERS_MAIN if main else [1.0], rng, far, true)
			for sg in [-1.0, 1.0]:
				var sc2: Vector2 = c + ax * sg * r * 0.55
				_stack(st, col, sc2, r * 0.42, 8, rot, y, H * rng.randf_range(0.55, 0.7), [0.62, 0.38], rng, far, true)
		"saucer":
			var core := r * 0.5
			_stack(st, col, c, core, 24, rot, y, H, [1.0], rng, far, false)
			var decks: int = rng.randi_range(3, 5) if main else rng.randi_range(2, 3)
			for k in decks:
				var f := (k + 1.0) / (decks + 1.0)
				var dr := r * lerpf(1.05, 0.62, f) * rng.randf_range(0.92, 1.05)
				_saucer(st, col, c, dr, y + H * f * 0.85, core, far)
			_spire(st, Vector3(c.x, y + H, c.y), core * 0.45, H * rng.randf_range(0.1, 0.18), 6 if far else 12, white, trim)
		_:
			_stack(st, col, c, r, 8 if int(t.get("sides", 8)) <= 8 else 24, rot, y, H, Data.TOWER_TIERS_MAIN if main else Data.TOWER_TIERS_SLIM, rng, far, true)

## A stack of tiers (shares of H in `parts`, each narrower than the last), a ledge on each, the roof and its spires.
static func _stack(st: SurfaceTool, col: PackedVector3Array, c: Vector2, r: float, ns: int, rot: float, y: float, H: float, parts: Array, rng: RandomNumberGenerator, far: bool, spire: bool) -> void:
	var white := Data.TOWER_WHITE
	var trim: Color = Data.CITY_TRIM
	var round_t := ns > 8
	var tot := 0.0
	for p in parts: tot += float(p)
	var spine_faces := {}
	for e in ns: spine_faces[e] = (e % 2 == 0)
	var sc := 1.0
	var rr := r
	for i in parts.size():
		var th: float = H * float(parts[i]) / tot
		rr = r * sc
		var poly := _chamfered(c, rr, ns, rot, 0.0 if round_t else Data.TOWER_CHAMFER)
		_prism(st, col, poly, c, y, y + th, white, trim, spine_faces if not round_t else {}, rr, far)
		if i < parts.size() - 1:
			if round_t: _saucer(st, col, c, rr * 1.2, y + th, rr, far)
			else: _ledge(st, col, _chamfered(c, rr * Data.TOWER_LEDGE, ns, rot, Data.TOWER_CHAMFER), c, y + th, far)
		y += th
		sc *= rng.randf_range(Data.TOWER_STEP.x, Data.TOWER_STEP.y)
	_cap(st, _chamfered(c, rr, ns, rot, 0.0 if round_t else Data.TOWER_CHAMFER), y, white * 0.92)
	var rs := RandomNumberGenerator.new()   # (the spires draw from their own: the stack's draws are the same near, far and solid)
	rs.seed = rng.randi()
	if not spire: return
	var sh: float = H * rs.randf_range(Data.TOWER_SPIRE.x, Data.TOWER_SPIRE.y)
	_spire(st, Vector3(c.x, y, c.y), rr * 0.4, sh, 6 if far else 10, white, trim)
	if not far and rr > 30.0:
		for k in 4:
			var a := rot + TAU * (k + 0.5) / 4.0
			var p2 := c + Vector2(cos(a), sin(a)) * rr * 0.65
			_spire(st, Vector3(p2.x, y, p2.y), rr * 0.1, sh * rs.randf_range(0.2, 0.4), 6, white, trim)

## v13.302: the tower as solid upright drums for flying into it: [[centre (Vector2), y0, y1, radius]] (each tier's
## inscribed circle; the saucer decks as flat drums). The same random draws as the mesh, so they line up.
static func solids(t: Dictionary) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t["seed"])
	var c: Vector2 = t["c"]
	var r: float = t["r"]
	var y: float = t["base"]
	var H: float = t["h"]
	var main: bool = t["main"]
	var style := str(t.get("style", "tiered"))
	if main and style != "saucer":   # (the pad's draws, as in _tower)
		rng.randf()
		rng.randi_range(0, 3)
		rng.randf_range(0.18, 0.3)
	match style:
		"cathedral":
			var ax := Vector2(cos(float(t["rot"])), sin(float(t["rot"])))
			_stack_solids(out, c, r * 0.72, 8, y, H, Data.TOWER_TIERS_MAIN if main else [1.0], rng)
			for sg in [-1.0, 1.0]:
				_stack_solids(out, c + ax * sg * r * 0.55, r * 0.42, 8, y, H * rng.randf_range(0.55, 0.7), [0.62, 0.38], rng)
		"saucer":
			_stack_solids(out, c, r * 0.5, 24, y, H, [1.0], rng)
			var decks: int = rng.randi_range(3, 5) if main else rng.randi_range(2, 3)
			for k in decks:
				var f := (k + 1.0) / (decks + 1.0)
				var dr := r * lerpf(1.05, 0.62, f) * rng.randf_range(0.92, 1.05)
				var yd := y + H * f * 0.85
				out.append([c, yd - Data.TOWER_SAUCER_T * 2.5, yd + Data.TOWER_SAUCER_T, dr])
		_:
			_stack_solids(out, c, r, 8 if int(t.get("sides", 8)) <= 8 else 24, y, H, Data.TOWER_TIERS_MAIN if main else Data.TOWER_TIERS_SLIM, rng)
	return out

static func _stack_solids(out: Array, c: Vector2, r: float, ns: int, y: float, H: float, parts: Array, rng: RandomNumberGenerator) -> void:
	var tot := 0.0
	for p in parts: tot += float(p)
	var sc := 1.0
	var k_in := cos(PI / ns) * (1.0 - Data.TOWER_CHAMFER * 0.5 if ns <= 8 else 1.0)
	for i in parts.size():
		var th: float = H * float(parts[i]) / tot
		out.append([c, y, y + th, r * sc * k_in])
		y += th
		sc *= rng.randf_range(Data.TOWER_STEP.x, Data.TOWER_STEP.y)
	rng.randi()   # (the spires' seed, as in _stack)

## A regular n-gon round c, its corners cut (chamfer: the share of each edge taken off each end; 0 = none).
static func _chamfered(c: Vector2, r: float, n: int, rot: float, ch: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := c + Vector2(cos(rot + TAU * i / n), sin(rot + TAU * i / n)) * r
		if ch <= 0.0:
			out.append(a)
			continue
		var prv := c + Vector2(cos(rot + TAU * (i - 1) / n), sin(rot + TAU * (i - 1) / n)) * r
		var nxt := c + Vector2(cos(rot + TAU * (i + 1) / n), sin(rot + TAU * (i + 1) / n)) * r
		out.append(a.lerp(prv, ch))
		out.append(a.lerp(nxt, ch))
	return out

## The walls of one tier (y0..y1). The long faces of a cut prism: white panels either side of a dark recessed spine
## with a cyan strip up each edge of it and cyan ribs across; the cut corners: plain white.
static func _prism(st: SurfaceTool, col: PackedVector3Array, poly: PackedVector2Array, c: Vector2, y0: float, y1: float, white: Color, trim: Color, spine: Dictionary, rr: float, far: bool) -> void:
	var np := poly.size()
	var chamfered := np > 0 and not spine.is_empty()
	for e in np:
		var a: Vector2 = poly[e]
		var b: Vector2 = poly[(e + 1) % np]
		var o2 := ((a + b) * 0.5 - c).normalized()
		var nrm := Vector3(o2.x, 0, o2.y)
		_tri_col(col, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y))
		_tri_col(col, Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y))
		var long_face := chamfered and e % 2 == 1   # (a cut prism: corner, face, corner, face ...)
		var fi := e / 2
		if far or not long_face or not bool(spine.get(fi, false)):
			_wall(st, a, b, y0, y1, nrm, white, PANEL, 0.0)
			if long_face and not far and (y1 - y0) > 40.0:   # a thin glowing seam up the middle of a plain face
				var m0 := a.lerp(b, 0.495)
				var m1 := a.lerp(b, 0.505)
				_wall(st, m0 + o2 * 0.15, m1 + o2 * 0.15, y0, y1, nrm, trim, GLOW, 1.1)
			continue
		# the spine: [panel | recess | panel]
		var w := Data.TOWER_SPINE_W
		var p1 := a.lerp(b, 0.5 - w * 0.5)
		var p2 := a.lerp(b, 0.5 + w * 0.5)
		var dep := maxf(1.5, rr * Data.TOWER_SPINE_DEPTH)
		var q1 := p1 - o2 * dep
		var q2 := p2 - o2 * dep
		_wall(st, a, p1, y0, y1, nrm, white, PANEL, 0.0)
		_wall(st, p2, b, y0, y1, nrm, white, PANEL, 0.0)
		var along := (b - a).normalized()
		_wall(st, p1, q1, y0, y1, Vector3(along.x, 0, along.y), white * 0.8, PANEL, 0.0)   # the recess's sides
		_wall(st, q2, p2, y0, y1, Vector3(-along.x, 0, -along.y), white * 0.8, PANEL, 0.0)
		_wall(st, q1, q2, y0, y1, nrm, Data.TOWER_SPINE, SPINE, 0.0)
		for p in [p1.lerp(q1, 0.15), p2.lerp(q2, 0.15)]:   # light strips up the recess edges
			var pv: Vector2 = p
			_wall(st, pv - along * 0.35 + o2 * 0.05, pv + along * 0.35 + o2 * 0.05, y0, y1, nrm, trim, GLOW, 1.6)
		var yy := y0 + Data.TOWER_RIB_EVERY * 0.5   # ribs across the spine
		while yy < y1 - 2.0:
			_wall(st, q1 + o2 * 0.2, q2 + o2 * 0.2, yy, yy + 0.8, nrm, trim, GLOW, 1.3)
			yy += Data.TOWER_RIB_EVERY

## A glowing ledge at a tier top: a thin slab a little wider than the tier, its rim lit.
static func _ledge(st: SurfaceTool, col: PackedVector3Array, poly: PackedVector2Array, c: Vector2, y: float, far: bool) -> void:
	var t := Data.TOWER_LEDGE_T
	_cap(st, poly, y + t, Data.TOWER_WHITE)
	_cap(st, poly, y, Data.TOWER_WHITE * 0.6, true)
	var np := poly.size()
	for e in np:
		var a: Vector2 = poly[e]
		var b: Vector2 = poly[(e + 1) % np]
		var o2 := ((a + b) * 0.5 - c).normalized()
		_wall(st, a, b, y, y + t, Vector3(o2.x, 0, o2.y), Data.CITY_TRIM if not far else Data.CITY_TRIM * 0.8, GLOW, 1.5)
		_tri_col(col, Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(b.x, y + t, b.y))
		_tri_col(col, Vector3(a.x, y, a.y), Vector3(b.x, y + t, b.y), Vector3(a.x, y + t, a.y))

## A round tower's saucer deck: a wide disc, its underside a shallow cone back to the tower, a glowing rim.
static func _saucer(st: SurfaceTool, col: PackedVector3Array, c: Vector2, R: float, y: float, r_in: float, far: bool) -> void:
	var n := 16 if far else 36
	var t := Data.TOWER_SAUCER_T
	var under := t * 2.5
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var o0 := c + d0 * R
		var o1 := c + d1 * R
		var i0 := c + d0 * r_in
		var i1 := c + d1 * r_in
		var top := y + t
		_tri(st, Vector3(c.x, top, c.y), Vector3(o1.x, top, o1.y), Vector3(o0.x, top, o0.y), Vector3.UP, Data.TOWER_WHITE, PANEL, 0.0)
		var nm := Vector3((d0 + d1).x, 0, (d0 + d1).y).normalized()
		_quad(st, Vector3(o0.x, y, o0.y), Vector3(o1.x, y, o1.y), Vector3(o1.x, top, o1.y), Vector3(o0.x, top, o0.y), nm, Data.CITY_TRIM, GLOW, 1.6)
		var nu := (nm - Vector3.UP * 2.0).normalized()
		_quad(st, Vector3(i0.x, y - under, i0.y), Vector3(i1.x, y - under, i1.y), Vector3(o1.x, y, o1.y), Vector3(o0.x, y, o0.y), nu, Data.TOWER_WHITE * 0.7, PANEL, 0.0)
		if not far and i % 3 == 0:   # lit windows round the deck's underside
			var w0 := i0.lerp(o0, 0.55)
			var w1 := i1.lerp(o1, 0.55)
			var yw := y - under * 0.45
			_quad(st, Vector3(w0.x, yw - 0.6, w0.y) + nu * 0.1, Vector3(w1.x, yw - 0.6, w1.y) + nu * 0.1, Vector3(w1.x, yw + 0.6, w1.y) + nu * 0.1, Vector3(w0.x, yw + 0.6, w0.y) + nu * 0.1, nu, Data.CITY_TRIM, GLOW, 1.2)
		_tri_col(col, Vector3(c.x, top, c.y), Vector3(o1.x, top, o1.y), Vector3(o0.x, top, o0.y))
		_tri_col(col, Vector3(o0.x, y, o0.y), Vector3(o1.x, y, o1.y), Vector3(o1.x, top, o1.y))
		_tri_col(col, Vector3(o0.x, y, o0.y), Vector3(o1.x, top, o1.y), Vector3(o0.x, top, o0.y))

## The buttress legs of a raised giant: from each corner of its foot a sloped fin down to the street, flaring out, white
## with a lit edge (the owner's art: the towers stand on great legs with arches between).
static func _legs(st: SurfaceTool, col: PackedVector3Array, c: Vector2, r: float, ns: int, rot: float, y: float, ground: float, white: Color, trim: Color) -> void:
	var up := (y - ground) * 1.6
	for i in ns:
		var a := rot + TAU * i / ns
		var d := Vector2(cos(a), sin(a))
		var side := Vector2(-d.y, d.x) * Data.TOWER_LEG_W * 0.5
		var foot := c + d * r * Data.TOWER_LEG_OUT
		var top := c + d * r * 0.9
		var A := Vector3(top.x, y + up, top.y)    # high on the wall
		var B := Vector3(foot.x, ground, foot.y)   # out on the street
		var Cc := Vector3(top.x, ground, top.y)    # under the foot
		for sgn in [-1.0, 1.0]:
			var o: Vector3 = Vector3(side.x, 0, side.y) * sgn
			_tri(st, Cc + o, B + o, A + o, Vector3(side.x, 0, side.y).normalized() * sgn, white, PANEL, 0.0)
			_tri_col(col, Cc + o, B + o, A + o)
		var on := Vector3(d.x, 0, d.y).lerp(Vector3.UP, 0.5).normalized()
		var sv := Vector3(side.x, 0, side.y)
		_quad(st, B - sv, B + sv, A + sv, A - sv, on, white * 0.95, PANEL, 0.0)
		_quad(st, B - sv * 0.2 + on * 0.1, B + sv * 0.2 + on * 0.1, A + sv * 0.2 + on * 0.1, A - sv * 0.2 + on * 0.1, on, trim, GLOW, 1.4)

## A landing pad off one face: a slab sticking out, its edge lit gold, a cyan ring painted on it.
static func _pad(st: SurfaceTool, col: PackedVector3Array, c: Vector2, rr: float, a: float, y: float) -> void:
	var d := Vector2(cos(a), sin(a))
	var sd := Vector2(-d.y, d.x)
	var w := Data.TOWER_PAD_W * 0.5
	var p0 := c + d * rr * 0.8
	var p1 := c + d * (rr + Data.TOWER_PAD_OUT)
	var pts := PackedVector2Array([p0 - sd * w, p1 - sd * w, p1 + sd * w, p0 + sd * w])
	_cap(st, pts, y + 2.5, Data.TOWER_WHITE * 0.85)
	_cap(st, pts, y, Data.TOWER_WHITE * 0.5, true)
	for e in 4:
		var q0: Vector2 = pts[e]
		var q1: Vector2 = pts[(e + 1) % 4]
		var o2 := ((q0 + q1) * 0.5 - (p0 + p1) * 0.5).normalized()
		_wall(st, q0, q1, y, y + 2.5, Vector3(o2.x, 0, o2.y), Data.TOWER_GOLD, GLOW, 1.2)
		_tri_col(col, Vector3(q0.x, y, q0.y), Vector3(q1.x, y, q1.y), Vector3(q1.x, y + 2.5, q1.y))
		_tri_col(col, Vector3(q0.x, y, q0.y), Vector3(q1.x, y + 2.5, q1.y), Vector3(q0.x, y + 2.5, q0.y))
	var m := (p0 + p1) * 0.5 + d * Data.TOWER_PAD_OUT * 0.1
	var rad := minf(w, Data.TOWER_PAD_OUT * 0.5) * 0.6
	for i in 24:   # the landing ring
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		var u0 := m + Vector2(cos(a0), sin(a0)) * rad
		var u1 := m + Vector2(cos(a1), sin(a1)) * rad
		var v0 := m + Vector2(cos(a0), sin(a0)) * (rad - 1.2)
		var v1 := m + Vector2(cos(a1), sin(a1)) * (rad - 1.2)
		_quad(st, Vector3(v0.x, y + 2.55, v0.y), Vector3(v1.x, y + 2.55, v1.y), Vector3(u1.x, y + 2.55, u1.y), Vector3(u0.x, y + 2.55, u0.y), Vector3.UP, Data.CITY_TRIM, GLOW, 1.0)

## A sky bridge: a white tube between two towers at height y, a lit window band down each side.
static func _sky_bridge(st: SurfaceTool, col: PackedVector3Array, br: Dictionary, far: bool) -> void:
	var a: Dictionary = br["a"]
	var b: Dictionary = br["b"]
	var ca: Vector2 = a["c"]
	var cb: Vector2 = b["c"]
	var d := (cb - ca).normalized()
	var p0 := ca + d * float(a["r"]) * 0.55
	var p1 := cb - d * float(b["r"]) * 0.55
	var y: float = br["y"]
	var sd := Vector2(-d.y, d.x) * Data.TOWER_BRIDGE_W * 0.5
	var hgt := Data.TOWER_BRIDGE_H
	var corners := [[p0 - sd, p1 - sd], [p0 + sd, p1 + sd]]
	# floor, roof, two sides
	_quad(st, Vector3((p0 - sd).x, y + hgt, (p0 - sd).y), Vector3((p1 - sd).x, y + hgt, (p1 - sd).y), Vector3((p1 + sd).x, y + hgt, (p1 + sd).y), Vector3((p0 + sd).x, y + hgt, (p0 + sd).y), Vector3.UP, Data.TOWER_WHITE, PANEL, 0.0)
	_quad(st, Vector3((p0 + sd).x, y, (p0 + sd).y), Vector3((p1 + sd).x, y, (p1 + sd).y), Vector3((p1 - sd).x, y, (p1 - sd).y), Vector3((p0 - sd).x, y, (p0 - sd).y), Vector3.DOWN, Data.TOWER_WHITE * 0.55, PANEL, 0.0)
	for sg in [-1.0, 1.0]:
		var o: Vector2 = sd * sg
		var nrm := Vector3(o.x, 0, o.y).normalized()
		var q0: Vector2 = p0 + o
		var q1: Vector2 = p1 + o
		_wall(st, q0, q1, y, y + hgt, nrm, Data.TOWER_WHITE, PANEL, 0.0)
		if not far: _wall(st, q0 + o.normalized() * 0.1, q1 + o.normalized() * 0.1, y + hgt * 0.4, y + hgt * 0.7, nrm, Data.CITY_TRIM, GLOW, 1.1)
		_tri_col(col, Vector3(q0.x, y, q0.y), Vector3(q1.x, y, q1.y), Vector3(q1.x, y + hgt, q1.y))
		_tri_col(col, Vector3(q0.x, y, q0.y), Vector3(q1.x, y + hgt, q1.y), Vector3(q0.x, y + hgt, q0.y))
	_tri_col(col, Vector3((p0 - sd).x, y + hgt, (p0 - sd).y), Vector3((p1 - sd).x, y + hgt, (p1 - sd).y), Vector3((p1 + sd).x, y + hgt, (p1 + sd).y))
	_tri_col(col, Vector3((p0 - sd).x, y + hgt, (p0 - sd).y), Vector3((p1 + sd).x, y + hgt, (p1 + sd).y), Vector3((p0 + sd).x, y + hgt, (p0 + sd).y))
	_tri_col(col, Vector3((p0 - sd).x, y, (p0 - sd).y), Vector3((p1 - sd).x, y, (p1 - sd).y), Vector3((p1 + sd).x, y, (p1 + sd).y))
	_tri_col(col, Vector3((p0 - sd).x, y, (p0 - sd).y), Vector3((p1 + sd).x, y, (p1 + sd).y), Vector3((p0 + sd).x, y, (p0 + sd).y))

## A needle spire: a tapered n-sided cone, white with a lit tip.
static func _spire(st: SurfaceTool, base: Vector3, r: float, h: float, n: int, white: Color, trim: Color) -> void:
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var b0 := base + Vector3(cos(a0), 0, sin(a0)) * r
		var b1 := base + Vector3(cos(a1), 0, sin(a1)) * r
		var m0 := base + Vector3(cos(a0), 0, sin(a0)) * r * 0.35 + Vector3(0, h * 0.55, 0)
		var m1 := base + Vector3(cos(a1), 0, sin(a1)) * r * 0.35 + Vector3(0, h * 0.55, 0)
		var tip := base + Vector3(0, h, 0)
		var nrm := Vector3(cos((a0 + a1) * 0.5), 0.3, sin((a0 + a1) * 0.5)).normalized()
		_quad(st, b0, b1, m1, m0, nrm, white, PANEL, 0.0)
		_tri(st, m0, m1, tip, nrm, white * 0.95, PANEL, 0.0)
	var t0 := base + Vector3(0, h * 0.93, 0)
	for i in 4:   # the lit tip
		var a0 := TAU * i / 4.0
		var a1 := TAU * (i + 1) / 4.0
		_tri(st, t0 + Vector3(cos(a0), 0, sin(a0)) * r * 0.06, t0 + Vector3(cos(a1), 0, sin(a1)) * r * 0.06, base + Vector3(0, h * 1.02, 0), Vector3(cos(a0), 0.5, sin(a0)).normalized(), trim, GLOW, 2.5)

# ---------------------------------------------------------------------------------------------------------------- pieces
static func _cap(st: SurfaceTool, poly: PackedVector2Array, y: float, colr: Color, down := false) -> void:
	var c := Vector2.ZERO
	for p in poly: c += p
	c /= maxf(1, poly.size())
	for e in poly.size():
		var a: Vector2 = poly[e]
		var b: Vector2 = poly[(e + 1) % poly.size()]
		if down: _tri(st, Vector3(c.x, y, c.y), Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3.DOWN, colr, PANEL, 0.0)
		else: _tri(st, Vector3(c.x, y, c.y), Vector3(b.x, y, b.y), Vector3(a.x, y, a.y), Vector3.UP, colr, PANEL, 0.0)

static func _wall(st: SurfaceTool, a: Vector2, b: Vector2, y0: float, y1: float, nrm: Vector3, colr: Color, kind: int, glow: float) -> void:
	_quad(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), nrm, colr, kind, glow)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, colr: Color, kind: int, glow: float) -> void:
	_tri(st, a, b, c, n, colr, kind, glow)
	_tri(st, a, c, d, n, colr, kind, glow)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, colr: Color, kind: int, glow: float) -> void:
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(Color(colr.r, colr.g, colr.b, 1.0))
		st.set_uv(Vector2(glow, float(kind)))
		st.add_vertex(v)

static func _tri_col(col: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	col.append(a)
	col.append(b)
	col.append(c)

# ---------------------------------------------------------------------------------------------------------------- look
static var _mat: ShaderMaterial
## The towers' material: vertex colour, UV.x glow, UV.y what it is (spine / panel / glow / glass). The white armour gets
## panel seams and a little tint per panel from the world position (no texture); the dark spine gets rows of small lit
## windows; glow faces shine.
static func material() -> ShaderMaterial:
	if _mat != null: return _mat
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	return _mat

const SHADER := """shader_type spatial;
render_mode cull_disabled;
varying float glow;
varying float kind;
varying vec3 wpos;
varying vec3 wnrm;
float h2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void vertex() {
	glow = UV.x;
	kind = UV.y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 c = COLOR.rgb;
	float rough = 0.35;
	float metal = 0.25;
	vec3 em = vec3(0.0);
	// face coordinates: along the wall and up it (a roof: the ground plan)
	vec2 f;
	if (abs(wnrm.y) > 0.7) f = wpos.xz;
	else {
		vec2 t = normalize(vec2(-wnrm.z, wnrm.x));
		f = vec2(dot(wpos.xz, t), wpos.y);
	}
	if (kind < 0.5) {   // the dark spine: rows of small windows, some lit
		vec2 g = f / vec2(2.2, 4.0);
		vec2 id = floor(g);
		vec2 q = fract(g);
		float win = step(0.25, q.x) * step(q.x, 0.75) * step(0.3, q.y) * step(q.y, 0.7);
		win *= clamp(1.5 - max(fwidth(g.x), fwidth(g.y)) * 3.0, 0.0, 1.0);   // (far off, the window grid fades to an even tone)
		float lit = step(0.62, h2(id));
		c = mix(c, vec3(0.05, 0.08, 0.12), win);
		em = vec3(0.35, 0.8, 1.0) * win * lit * 0.9;
		rough = 0.25;
		metal = 0.6;
	} else if (kind < 1.5) {   // white armour panels: staggered seams, a little tint each
		float row = floor(f.y / 7.0);
		vec2 g = vec2(f.x / 9.0 + row * 0.37, f.y / 7.0);
		vec2 id = floor(g);
		vec2 q = fract(g);
		float seam = 1.0 - step(0.03, q.x) * step(q.x, 0.97) * step(0.04, q.y) * step(q.y, 0.96);
		float tone = 0.92 + 0.1 * h2(id);
		float blue = step(0.97, h2(id + 7.1));   // the odd panel a cool grey
		c *= tone;
		c = mix(c, c * vec3(0.78, 0.84, 0.92), blue);
		seam *= clamp(1.4 - max(fwidth(g.x), fwidth(g.y)) * 8.0, 0.0, 1.0);   // (far off, the seams fade: no shimmer)
		c *= 1.0 - seam * 0.35;
		rough = 0.32 + 0.1 * h2(id + 3.3);
	} else if (kind < 2.5) {   // a light
		em = c * glow;
		rough = 0.2;
	} else {   // glass
		rough = 0.06;
		metal = 0.8;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = em;
}"""
