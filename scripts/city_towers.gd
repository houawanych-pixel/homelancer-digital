class_name CityTowers
extends RefCounted
## v13.303 (owner, with two photos of a modular building: "these are real basic shapes with the right colouring: boxes
## with that HyperNURBS bevel built in, the glass, you can build a whole city with this; they're easy to stack
## differently and look like a kit of components"): every tower is a stack of a few kit parts, each a simple shape
## with its edges bevelled (rounded corners, chamfered tops), and the right colour:
##   white : a smooth white concrete box (big panels, a few fine seams);
##   glass : a dark glass block, black frames on a 2.5 x 4 m grid, some rooms lit;
##   dark  : a dark metal slab (floor bands, plinths, masts);
##   pod   : a white capsule (rounded box, its foot tapering in) with a glass front, hung off a tower's side;
##   green : a planter of greenery on a roof.
## A tower is a glass core stacked from blocks that shift a little each way, white pillars clamped to its corners
## (topping out at different heights, planters on top), pods and glass bays sticking out, and a stepped crown. The same
## part list makes the close-up mesh, the far skyline (no bevels or frames) and the solid shape, so they always agree.
## Every building is a walkable podium (the BlockField floors with rooms, doors, lifts) with its tower on top.

const DARK := 0    # (UV.y: what a face is, for the shader)
const PANEL := 1
const GLOW := 2
const GLASS := 3
const GREEN := 4

## A tower for one building of a block plan: {c (tile-local m), r (m), sides, rot, base (y), h (m over base), main, seed}.
static func spec(b: Dictionary, org: Vector2, g_roof: float, downtown: bool, key: String) -> Dictionary:
	var s: float = Data.BLOCK_MIN
	var c: Vector2 = org + (b["centre"] as Vector2) * s
	var r: float = float(b["radius"]) * s
	var seed := absi(hash("%s|%s|tower" % [key, str(b["at"])]))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var main: bool = bool(b.get("main", false))
	var hr: Vector2 = Data.TOWER_H_DOWNTOWN if downtown and main else (Data.TOWER_H_MAIN if main else Data.TOWER_H_SLIM)
	return {"c": c, "r": r * Data.TOWER_INSET, "sides": int(b.get("sides", 6)), "rot": 0.0, "base": g_roof, "h": rng.randf_range(hr.x, hr.y),
		"main": main, "seed": seed, "kind": str(b.get("kind", "hex"))}

## The whole block's towers (and bridges) as one mesh: [ArrayMesh, PackedVector3Array (unused: the solids are parts)].
static func build(towers: Array, bridges: Array, far: bool) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in towers:
		for p in parts(t): _part(st, p, far)
	for br in bridges: _part(st, br, far)
	return [st.commit(), PackedVector3Array()]

## Glass sky bridges between big towers close enough: parts (kind glass).
static func bridges_for(towers: Array, seed: int) -> Array:
	var mains: Array = towers.filter(func(t): return bool(t["main"]))
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in mains.size():
		for j in range(i + 1, mains.size()):
			var a: Dictionary = mains[i]
			var b: Dictionary = mains[j]
			var d: Vector2 = (b["c"] as Vector2) - (a["c"] as Vector2)
			if d.length() > Data.TOWER_BRIDGE_MAX or rng.randf() > Data.TOWER_BRIDGE_CHANCE: continue
			var top: float = minf(float(a["base"]) + float(a["h"]), float(b["base"]) + float(b["h"]))
			var y := lerpf(maxf(float(a["base"]), float(b["base"])), top, rng.randf_range(0.2, 0.55))
			var m: Vector2 = ((a["c"] as Vector2) + (b["c"] as Vector2)) * 0.5
			var along_x := absf(d.x) >= absf(d.y)
			var ln := d.length() - float(a["r"]) - float(b["r"])
			if ln <= 4.0: continue
			var sz := Vector3(ln + 8.0, Data.TOWER_BRIDGE_H, Data.TOWER_BRIDGE_W) if along_x else Vector3(Data.TOWER_BRIDGE_W, Data.TOWER_BRIDGE_H, ln + 8.0)
			out.append({"k": "glass", "p": Vector3(m.x, y, m.y), "s": sz})
	return out

# ---------------------------------------------------------------------------------------------------------------- the kit
## The parts of one tower: [{k (white / glass / dark / pod / green), p (bottom centre), s (size x, y, z), out (pods:
## the way the glass front faces)}], tile-local. Deterministic from the tower's seed.
static func parts(t: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t["seed"])
	var c: Vector2 = t["c"]
	var R: float = t["r"]
	var y0: float = t["base"]
	var H: float = t["h"]
	var main: bool = t["main"]
	var style := str(t.get("style", "cluster"))
	var out: Array = []
	# the core: one glass column, or two (twin), or a long slab
	var cores: Array = []   # [centre, w, d]
	match style:
		"twin":
			var gap := R * 0.18
			var w := R * 0.62
			var ax := rng.randi() % 2 == 0
			for sg in [-1.0, 1.0]:
				var o := Vector2(sg * (w * 0.5 + gap * 0.5), 0.0) if ax else Vector2(0.0, sg * (w * 0.5 + gap * 0.5))
				cores.append([c + o, w, R * 1.1])
		"slab":
			var ax2 := rng.randi() % 2 == 0
			cores.append([c, R * (1.75 if ax2 else 0.75), R * (0.75 if ax2 else 1.75)])
		_:
			cores.append([c, R * rng.randf_range(1.1, 1.35), R * rng.randf_range(1.0, 1.25)])
	var tall_k := 1.0
	for ci in cores.size():
		var cc: Vector2 = cores[ci][0]
		var cw: float = cores[ci][1]
		var cd: float = cores[ci][2]
		var ch: float = H * (tall_k if ci == 0 else rng.randf_range(0.7, 0.92))
		_core(out, rng, cc, cw, cd, y0, ch, main)
		_pillars(out, rng, cc, cw, cd, y0, ch, main)
		_pods(out, rng, cc, cw, cd, y0, ch, main)
		_crown(out, rng, cc, cw, cd, y0 + ch, main)
	if style == "twin" and cores.size() == 2:   # glass links between the twins
		var a: Vector2 = cores[0][0]
		var b: Vector2 = cores[1][0]
		var m := (a + b) * 0.5
		var dx := absf(b.x - a.x) > 1.0
		for k in rng.randi_range(2, 4):
			var yb := y0 + H * rng.randf_range(0.15, 0.7)
			var span := a.distance_to(b)
			out.append({"k": "glass", "p": Vector3(m.x, yb, m.y), "s": Vector3(span, rng.randf_range(10.0, 22.0), R * 0.45) if dx else Vector3(R * 0.45, rng.randf_range(10.0, 22.0), span)})
	return out

## The glass core, stacked from blocks that each shift a little, a dark floor band between them now and then.
static func _core(out: Array, rng: RandomNumberGenerator, c: Vector2, w: float, d: float, y: float, h: float, main: bool) -> void:
	var top := y + h
	var shift := 0.06
	while y < top - 4.0:
		var bh := minf(top - y, h * rng.randf_range(0.08, 0.16) if main else h * rng.randf_range(0.18, 0.3))
		var ox := rng.randf_range(-shift, shift) * w
		var oz := rng.randf_range(-shift, shift) * d
		out.append({"k": "glass", "p": Vector3(c.x + ox, y, c.y + oz), "s": Vector3(w * rng.randf_range(0.86, 1.0), bh, d * rng.randf_range(0.86, 1.0))})
		y += bh
		if y < top - 8.0 and rng.randf() < 0.55:
			out.append({"k": "dark", "p": Vector3(c.x, y, c.y), "s": Vector3(w * 1.04, Data.KIT_BAND, d * 1.04)})
			y += Data.KIT_BAND

## White pillars clamped to the core's corners: some run the full height, some stop part way, one may start higher;
## each in a few pieces with a dark joint, a planter on top of the shorter ones.
static func _pillars(out: Array, rng: RandomNumberGenerator, c: Vector2, w: float, d: float, y0: float, h: float, main: bool) -> void:
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var n: int = rng.randi_range(2, 4) if main else rng.randi_range(1, 3)
	var start := rng.randi() % 4
	for k in n:
		var cv: Vector2 = corners[(start + k * (2 if n == 2 else 1)) % 4]
		var pw := minf(w, d) * rng.randf_range(0.32, 0.48)
		var pd := pw * rng.randf_range(0.8, 1.4)
		var pc := c + Vector2(cv.x * (w * 0.5 - pw * 0.15), cv.y * (d * 0.5 - pd * 0.15))
		var ya := y0 + (0.0 if rng.randf() < 0.75 else h * rng.randf_range(0.15, 0.4))
		var yb := y0 + h * (1.03 if k == 0 and rng.randf() < 0.5 else rng.randf_range(0.35, 0.92))
		var pieces: int = rng.randi_range(1, 3)
		var y := ya
		for j in pieces:
			var ph := (yb - ya) / pieces - (Data.KIT_JOINT if j < pieces - 1 else 0.0)
			out.append({"k": "white", "p": Vector3(pc.x, y, pc.y), "s": Vector3(pw, ph, pd)})
			y += ph
			if j < pieces - 1:
				out.append({"k": "dark", "p": Vector3(pc.x, y, pc.y), "s": Vector3(pw * 0.9, Data.KIT_JOINT, pd * 0.9)})
				y += Data.KIT_JOINT
		if yb < y0 + h * 0.95 and rng.randf() < 0.7:
			out.append({"k": "green", "p": Vector3(pc.x, y, pc.y), "s": Vector3(pw * 0.86, Data.KIT_PLANTER, pd * 0.86)})

## White capsule pods with glass fronts, hung off the core's faces up high, and dark glass bays lower down.
static func _pods(out: Array, rng: RandomNumberGenerator, c: Vector2, w: float, d: float, y0: float, h: float, main: bool) -> void:
	var faces := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
	var n: int = rng.randi_range(2, 5) if main else rng.randi_range(0, 2)
	for k in n:
		var f: Vector2 = faces[rng.randi() % 4]
		var half := w * 0.5 if f.x != 0.0 else d * 0.5
		var across := d if f.x != 0.0 else w
		var pw := minf(w, d) * rng.randf_range(0.42, 0.58)
		var pdp := pw * rng.randf_range(0.8, 1.1)
		var ph := pw * rng.randf_range(1.4, 2.0)
		var slide := rng.randf_range(-0.3, 0.3) * across
		var pc := c + f * (half + pdp * 0.3) + Vector2(-f.y, f.x) * slide
		var yp := y0 + h * rng.randf_range(0.4, 0.88)
		var sz := Vector3(pdp, ph, pw) if f.x != 0.0 else Vector3(pw, ph, pdp)
		out.append({"k": "pod", "p": Vector3(pc.x, yp, pc.y), "s": sz, "out": Vector3(f.x, 0, f.y)})
		out.append({"k": "dark", "p": Vector3(pc.x - f.x * pdp * 0.45, yp + ph * 0.3, pc.y - f.y * pdp * 0.45), "s": Vector3(maxf(2.5, sz.x * 0.4), ph * 0.4, maxf(2.5, sz.z * 0.4))})   # its clamp to the core
	var nb: int = rng.randi_range(1, 3) if main else rng.randi_range(0, 1)
	for k in nb:
		var f2: Vector2 = faces[rng.randi() % 4]
		var half2 := w * 0.5 if f2.x != 0.0 else d * 0.5
		var across2 := d if f2.x != 0.0 else w
		var bw := across2 * rng.randf_range(0.3, 0.5)
		var bd := minf(w, d) * rng.randf_range(0.15, 0.25)
		var bh := h * rng.randf_range(0.12, 0.3)
		var pc2 := c + f2 * (half2 + bd * 0.4) + Vector2(-f2.y, f2.x) * rng.randf_range(-0.2, 0.2) * across2
		out.append({"k": "glass", "p": Vector3(pc2.x, y0 + h * rng.randf_range(0.05, 0.45), pc2.y), "s": Vector3(bd, bh, bw) if f2.x != 0.0 else Vector3(bw, bh, bd)})

## The crown: a smaller glass block and a white cap stepped back on the roof, a planter, a dark mast.
static func _crown(out: Array, rng: RandomNumberGenerator, c: Vector2, w: float, d: float, y: float, main: bool) -> void:
	var gh := maxf(8.0, minf(w, d) * rng.randf_range(0.25, 0.45))
	out.append({"k": "glass", "p": Vector3(c.x, y, c.y), "s": Vector3(w * 0.7, gh, d * 0.7)})
	var wh := gh * rng.randf_range(0.5, 0.9)
	var off := Vector2(rng.randf_range(-0.12, 0.12) * w, rng.randf_range(-0.12, 0.12) * d)
	out.append({"k": "white", "p": Vector3(c.x + off.x, y + gh, c.y + off.y), "s": Vector3(w * 0.42, wh, d * 0.42)})
	out.append({"k": "green", "p": Vector3(c.x - off.x * 2.0, y + gh, c.y - off.y * 2.0), "s": Vector3(w * 0.22, Data.KIT_PLANTER, d * 0.22)})
	if main: out.append({"k": "dark", "p": Vector3(c.x + off.x, y + gh + wh, c.y + off.y), "s": Vector3(2.0, maxf(20.0, w * 0.6), 2.0)})

## The tower as solid upright drums for flying into it: [[centre (Vector2), y0, y1, radius]] (each part's footprint
## as a circle a little inside its corners).
static func solids(t: Dictionary) -> Array:
	var out: Array = []
	for p in parts(t):
		if str(p["k"]) == "green": continue
		var pp: Vector3 = p["p"]
		var s: Vector3 = p["s"]
		out.append([Vector2(pp.x, pp.z), pp.y, pp.y + s.y, (s.x + s.z) * 0.25 * 1.05])
	return out

# ---------------------------------------------------------------------------------------------------------------- drawing
static func _part(st: SurfaceTool, p: Dictionary, far: bool) -> void:
	var k := str(p["k"])
	var pp: Vector3 = p["p"]
	var s: Vector3 = p["s"]
	match k:
		"white":
			_bevel_box(st, pp, s, 0.0 if far else minf(s.x, s.z) * Data.KIT_BEVEL_WHITE, Data.TOWER_WHITE, PANEL, PANEL, far)
		"glass":
			_bevel_box(st, pp, s, 0.0 if far else minf(1.2, minf(s.x, s.z) * 0.05), Data.KIT_GLASS, GLASS, DARK, far)
		"dark":
			_bevel_box(st, pp, s, 0.0 if far else minf(0.8, minf(s.x, s.z) * 0.08), Data.TOWER_SPINE, DARK, DARK, far)
		"green":
			_bevel_box(st, pp, s, 0.0 if far else minf(s.x, s.z) * 0.12, Data.KIT_GREEN, GREEN, GREEN, far)
		"pod":
			_pod(st, pp, s, p.get("out", Vector3.RIGHT), far)

## A box (bottom centre p, size s) with its four upright edges rounded (radius b, 2 steps) and its top and bottom edges
## chamfered by b: the HyperNURBS look with a handful of faces. walls: the side faces' kind; caps: top and bottom.
static func _bevel_box(st: SurfaceTool, p: Vector3, s: Vector3, b: float, colr: Color, walls: int, caps: int, far: bool) -> void:
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	var y0 := p.y
	var y1 := p.y + s.y
	if b <= 0.01 or far:
		var ring := _rrect(hx, hz, 0.0, 0)
		_loft(st, p, ring, ring, y0, y1, colr, walls)
		_fan(st, p, ring, y1, colr, caps, false)
		_fan(st, p, ring, y0, colr * 0.6, caps, true)
		return
	b = minf(b, minf(hx, hz) * 0.45)
	b = minf(b, s.y * 0.3)
	var outer := _rrect(hx, hz, b, 2)
	var inner := _rrect(hx - b, hz - b, b * 0.5, 2)
	_loft(st, p, outer, outer, y0 + b, y1 - b, colr, walls)
	_loft(st, p, outer, inner, y1 - b, y1, colr * 1.02, caps)     # the chamfer up to the top
	_loft(st, p, inner, outer, y0, y0 + b, colr * 0.8, caps)      # and from the bottom
	_fan(st, p, inner, y1, colr, caps, false)
	_fan(st, p, inner, y0, colr * 0.6, caps, true)

## A white capsule pod (bottom centre p, size s) whose glass front faces `out`: a rounded box, its foot tapering in to a
## blunt point and its top chamfered, a glass panel across the front.
static func _pod(st: SurfaceTool, p: Vector3, s: Vector3, outv: Vector3, far: bool) -> void:
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	var r := minf(hx, hz) * (0.0 if far else 0.4)
	var steps := 0 if far else 3
	var full := _rrect(hx, hz, r, steps)
	var foot := _rrect(hx * 0.45, hz * 0.45, r * 0.45, steps)
	var top := _rrect(hx * 0.82, hz * 0.82, r * 0.82, steps)
	var ya := p.y
	var yb := p.y + s.y * 0.26
	var yc := p.y + s.y * 0.88
	var yd := p.y + s.y
	var w := Data.TOWER_WHITE
	_loft(st, p, foot, full, ya, yb, w * 0.92, PANEL)
	_loft(st, p, full, full, yb, yc, w, PANEL)
	_loft(st, p, full, top, yc, yd, w, PANEL)
	_fan(st, p, top, yd, w, PANEL, false)
	_fan(st, p, foot, ya, w * 0.7, PANEL, true)
	# the glass front: a panel just proud of the face that looks out
	var half_out := hx if absf(outv.x) > 0.5 else hz
	var half_side := hz if absf(outv.x) > 0.5 else hx
	var side := Vector3(-outv.z, 0, outv.x)
	var fc := p + outv * (half_out + 0.15)
	var a := fc - side * half_side * 0.72
	var bb := fc + side * half_side * 0.72
	var g0 := yb + s.y * 0.04
	var g1 := yc - s.y * 0.03
	_quad(st, Vector3(a.x, g0, a.z), Vector3(bb.x, g0, bb.z), Vector3(bb.x, g1, bb.z), Vector3(a.x, g1, a.z), outv, Data.KIT_GLASS, GLASS)
	if not far:   # a thin gold rim round the glass (the trim on the owner's photos)
		var t := 0.35
		for e in [[a, bb, g0, g0 + t], [a, bb, g1 - t, g1]]:
			var ea: Vector3 = e[0]
			var eb: Vector3 = e[1]
			_quad(st, Vector3(ea.x, e[2], ea.z) + outv * 0.05, Vector3(eb.x, e[2], eb.z) + outv * 0.05, Vector3(eb.x, e[3], eb.z) + outv * 0.05, Vector3(ea.x, e[3], ea.z) + outv * 0.05, outv, Data.TOWER_GOLD, GLOW, 0.25)

## The outline of a rounded rectangle (half sizes hx, hz, corner radius r in `steps` steps; 0 steps = sharp corners),
## counter-clockwise from the +x side.
static func _rrect(hx: float, hz: float, r: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if steps <= 0 or r <= 0.01:
		out.append_array([Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz), Vector2(-hx, -hz)])
		return out
	var cs := [Vector2(hx - r, -hz + r), Vector2(hx - r, hz - r), Vector2(-hx + r, hz - r), Vector2(-hx + r, -hz + r)]
	var a0 := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for i in 4:
		for k in steps + 1:
			var a: float = float(a0[i]) + PI * 0.5 * k / steps
			out.append((cs[i] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return out

## Side faces between two outlines (same number of points) at y0 and y1, round centre p.
static func _loft(st: SurfaceTool, p: Vector3, lo: PackedVector2Array, hi: PackedVector2Array, y0: float, y1: float, colr: Color, kind: int) -> void:
	var n := lo.size()
	for i in n:
		var a := lo[i]
		var b := lo[(i + 1) % n]
		var c := hi[(i + 1) % n]
		var d := hi[i]
		var e := b - a
		var nrm := Vector3(e.y, 0, -e.x).normalized()
		var lean := ((a + b) * 0.5).length() - ((c + d) * 0.5).length()   # (a chamfer leans in: its normal tips up / down)
		if absf(lean) > 0.01: nrm = (nrm + Vector3(0, lean / maxf(0.01, absf(y1 - y0)) * signf(y1 - y0), 0)).normalized()
		_quad(st, Vector3(p.x + a.x, y0, p.z + a.y), Vector3(p.x + b.x, y0, p.z + b.y), Vector3(p.x + c.x, y1, p.z + c.y), Vector3(p.x + d.x, y1, p.z + d.y), nrm, colr, kind)

## A flat cap over an outline at height y (down = facing down).
static func _fan(st: SurfaceTool, p: Vector3, ring: PackedVector2Array, y: float, colr: Color, kind: int, down: bool) -> void:
	var n := ring.size()
	var c := Vector3(p.x, y, p.z)
	for i in n:
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var va := Vector3(p.x + a.x, y, p.z + a.y)
		var vb := Vector3(p.x + b.x, y, p.z + b.y)
		if down: _tri(st, c, va, vb, Vector3.DOWN, colr, kind, 0.0)
		else: _tri(st, c, vb, va, Vector3.UP, colr, kind, 0.0)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, colr: Color, kind: int, glow := 0.0) -> void:
	_tri(st, a, b, c, n, colr, kind, glow)
	_tri(st, a, c, d, n, colr, kind, glow)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, colr: Color, kind: int, glow: float) -> void:
	for v in [a, b, c]:
		st.set_normal(n)
		st.set_color(Color(colr.r, colr.g, colr.b, 1.0))
		st.set_uv(Vector2(glow, float(kind)))
		st.add_vertex(v)

# ---------------------------------------------------------------------------------------------------------------- look
static var _mat: ShaderMaterial
## The kit's material: vertex colour, UV.x glow, UV.y what it is. White: smooth concrete in big panels with a few fine
## seams; glass: dark and glossy behind black frames, some rooms lit warm; dark: satin metal; green: leafy noise.
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
float n2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	glow = UV.x;
	kind = UV.y;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 c = COLOR.rgb;
	float rough = 0.5;
	float metal = 0.0;
	float spec = 0.5;
	vec3 em = vec3(0.0);
	vec2 f;   // face coordinates: along the wall and up it (a roof: the ground plan)
	if (abs(wnrm.y) > 0.7) f = wpos.xz;
	else {
		vec2 t = normalize(vec2(-wnrm.z, wnrm.x));
		f = vec2(dot(wpos.xz, t), wpos.y);
	}
	if (kind > 3.5) {   // greenery
		float l = n2(wpos.xz * 0.8) * 0.6 + n2(wpos.xz * 3.1) * 0.4;
		c = mix(vec3(0.16, 0.32, 0.12), vec3(0.42, 0.6, 0.25), l);
		rough = 0.9;
	} else if (kind > 2.5) {   // glass: dark, glossy, black frames on a 2.5 x 4 m grid, some rooms lit
		vec2 g = f / vec2(2.5, 4.0);
		vec2 q = fract(g);
		vec2 id = floor(g);
		float aa = clamp(1.6 - max(fwidth(g.x), fwidth(g.y)) * 4.0, 0.0, 1.0);
		float frame = (1.0 - step(0.05, q.x) * step(q.x, 0.95) * step(0.06, q.y) * step(q.y, 0.94)) * aa;
		float lit = step(0.93, h2(id + vec2(floor(wpos.y / 40.0), 3.0)));
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);   // the sky in the glass at a glancing angle
		vec3 glass = vec3(0.06, 0.08, 0.1) + vec3(0.22, 0.3, 0.4) * fres + vec3(0.02, 0.025, 0.03) * h2(id);
		c = mix(glass, vec3(0.02, 0.02, 0.025), frame);
		em = vec3(1.0, 0.85, 0.6) * lit * (1.0 - frame) * 0.12 * aa;
		rough = mix(0.05, 0.4, frame);
		metal = 0.6;
		spec = 0.9;
	} else if (kind > 1.5) {   // a light / trim
		em = c * glow;
		rough = 0.25;
		metal = 0.8;
	} else if (kind > 0.5) {   // white concrete: big panels, fine seams, a faint tone each
		vec2 g = f / vec2(7.0, 10.0);
		vec2 id = floor(g);
		vec2 q = fract(g);
		float aa = clamp(1.4 - max(fwidth(g.x), fwidth(g.y)) * 10.0, 0.0, 1.0);
		float seam = (1.0 - step(0.012, q.x) * step(0.015, q.y)) * aa * step(0.35, h2(id + 1.7));
		c *= 0.95 + 0.06 * h2(id);
		c *= 1.0 - seam * 0.45;
		rough = 0.62;
		spec = 0.35;
	} else {   // dark metal
		rough = 0.35;
		metal = 0.7;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	EMISSION = em;
}"""
