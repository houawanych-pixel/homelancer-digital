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

## The tower as solid boxes (every part is an upright box): [AABB]. v13.304: boxes, not drums, so the long bridges,
## skyways and tunnels are solid where they really are.
static func solids(t: Dictionary) -> Array:
	return parts_solids(parts(t))

static func parts_solids(ps: Array) -> Array:
	var out: Array = []
	for p in ps:
		if str(p["k"]) in ["green", "glow", "ribbon", "post", "pane"]: continue   # (v13.331: the ramp decks are drawn, not boxes; v13.337: nor the canopies, overhead and thin)
		var pp: Vector3 = p["p"]
		var s: Vector3 = p["s"]
		out.append(AABB(Vector3(pp.x - s.x * 0.5, pp.y, pp.z - s.z * 0.5), s))
	return out

# ---------------------------------------------------------------------------------------------------------------- the capitol
## v13.304 (owner, with his art of a giant white tower over a canal: "the docking platform becomes part of a real docking
## building: the capitol, the highest tower, recognisable; elevated high, its landing platform mid-level, black"):
## the capitol stands beside the city's port. Its parts: a wide white plinth, a black spine up the middle with lines of
## light, twin white towers either side stepping in as they rise, lower outer towers, white collars round it, dark arms
## out to the port's (now black) landing deck at mid-level, a glass tunnel along them, and a crown of masts.
## at: its middle (tile-local x, z); ground: the ground there; deck: the landing deck's top; toward: the way to the deck.
static func capitol_parts(at: Vector2, ground: float, deck: float, toward: Vector2) -> Array:
	var out: Array = []
	var W: float = Data.CAPITOL_W
	var top := deck + Data.CAPITOL_ABOVE
	var H := top - ground
	var fx := absf(toward.x) >= absf(toward.y)   # its front faces the deck along x or z
	var fw := Vector2(signf(toward.x), 0.0) if fx else Vector2(0.0, signf(toward.y))
	var sd := Vector2(-fw.y, fw.x)
	var box := func(k: String, c: Vector2, y: float, across: float, h: float, along: float) -> void:   # across = sideways, along = front-back
		out.append({"k": k, "p": Vector3(c.x, y, c.y), "s": Vector3(across, h, along) if not fx else Vector3(along, h, across), "out": Vector3(fw.x, 0, fw.y)})
	box.call("white", at, ground, W * 1.45, Data.CAPITOL_PLINTH, W * 1.05)   # the plinth
	box.call("dark", at, ground + Data.CAPITOL_PLINTH, W * 0.34, H - Data.CAPITOL_PLINTH, W * 0.32)   # the spine
	box.call("glass", at + fw * W * 0.1, ground + Data.CAPITOL_PLINTH, W * 0.2, H * 0.9, W * 0.2)
	for sg in [-0.09, 0.09]:   # lines of light up its front
		box.call("glow", at + fw * (W * 0.165) + sd * W * sg, ground + Data.CAPITOL_PLINTH, 1.6, H - Data.CAPITOL_PLINTH - 20.0, 1.0)
	for sg in [-1.0, 1.0]:   # the twin white towers, stepping in
		var y := ground + Data.CAPITOL_PLINTH
		var pw := W * 0.32
		var pd := W * 0.46
		var pieces := [0.3, 0.26, 0.2, 0.14, 0.1]
		for i in pieces.size():
			var ph: float = (H * 0.94 - Data.CAPITOL_PLINTH) * float(pieces[i])
			box.call("white", at + sd * sg * W * 0.33, y, pw, ph - Data.KIT_JOINT, pd)
			y += ph - Data.KIT_JOINT
			box.call("dark", at + sd * sg * W * 0.33, y, pw * 0.92, Data.KIT_JOINT, pd * 0.92)
			y += Data.KIT_JOINT
			pw *= 0.9
			pd *= 0.88
		box.call("dark", at + sd * sg * W * 0.33, y, 4.0, H * 0.12, 4.0)   # a mast on each
		var y2 := ground + Data.CAPITOL_PLINTH   # the lower outer towers
		var ow := W * 0.2
		for i in 3:
			var oh := H * 0.18
			box.call("white", at + sd * sg * W * 0.62, y2, ow, oh, W * 0.3)
			y2 += oh
			box.call("glass", at + sd * sg * W * 0.62, y2, ow * 0.8, 12.0, W * 0.24)
			y2 += 12.0
			ow *= 0.88
		box.call("green", at + sd * sg * W * 0.62, y2, ow * 0.7, Data.KIT_PLANTER, W * 0.2)
	for f in [0.3, 0.52, 0.72]:   # white collars round the spine
		box.call("white", at, ground + H * f, W * 0.86, 16.0, W * 0.56)
		box.call("glow", at + fw * W * 0.281, ground + H * f + 6.0, W * 0.6, 1.2, 0.6)
	box.call("dark", at, top, 6.0, H * 0.14, 6.0)   # the crown: the tallest mast, and its white needle
	box.call("white", at, top, W * 0.14, H * 0.05, W * 0.14)
	# the arms out to the landing deck, a glass tunnel along them
	var reach := Data.CAPITOL_REACH
	for sg in [-0.28, 0.28]:
		box.call("dark", at + fw * (W * 0.5 + reach * 0.5) + sd * W * sg, deck - 10.0, 22.0, 10.0, reach + 30.0)
	box.call("glass", at + fw * (W * 0.5 + reach * 0.5), deck + 2.0, 18.0, 12.0, reach + 30.0)
	return out

## v13.305 (owner, with a blueprint of a disc-topped overwatch tower: "build that disc platform, the black disc on top,
## same colour tone, an overwatch; blend the black and white, and the city's boxes underneath it"): the capitol's
## landing deck is a great black disc (centre c, top at y, radius R): a white raised rim cut into four arcs by dark
## gate blocks, white inlay rings on the deck, and under it white and black rings stepping in, down onto a tower of the
## city's kit boxes (overwatch_parts) that holds it up from the ground.
static func deck_mesh(c: Vector2, y: float, R: float, dome_at := Vector2.INF) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if dome_at != Vector2.INF: _dome(st, dome_at, y)
	var T: float = Data.DECK_T
	_ring(st, c, 0.0, R, y - T, y, Data.CAPITOL_DECK, Data.CAPITOL_DECK * 1.4, DARK)   # the deck
	for gi in 4:   # the white rim, in four arcs
		var a0 := TAU * gi / 4.0 + Data.DECK_GATE
		var a1 := TAU * (gi + 1) / 4.0 - Data.DECK_GATE
		_ring(st, c, R, R + Data.DECK_RIM, y - T - 4.0, y + 3.0, Data.TOWER_WHITE, Data.TOWER_WHITE, PANEL, a0, a1)
		var am := TAU * gi / 4.0
		var gc := c + Vector2(cos(am), sin(am)) * (R + Data.DECK_RIM * 0.5)
		_bevel_box(st, Vector3(gc.x, y - T - 6.0, gc.y), Vector3(Data.DECK_RIM * 1.6, T + 12.0, Data.DECK_RIM * 1.6), 1.5, Data.TOWER_SPINE, DARK, DARK, false)
		_bevel_box(st, Vector3(gc.x, y + 6.0, gc.y), Vector3(4.0, 1.2, 4.0), 0.0, Data.CITY_TRIM, GLOW, GLOW, true)
	for f in [0.42, 0.7, 0.93]:   # white inlay rings on the deck
		_ring(st, c, R * f - 1.2, R * f + 1.2, y, y + 0.08, Data.TOWER_WHITE, Data.TOWER_WHITE, GLOW, 0.0, TAU, 0.35)
	var yb := y - T   # under it: rings stepping in, white and black in turn
	var rr := R * 0.88
	var k := 0
	for h in [10.0, 14.0, 10.0, 16.0]:
		var colr: Color = Data.TOWER_WHITE if k % 2 == 0 else Data.TOWER_SPINE
		_ring(st, c, 0.0, rr, yb - h, yb, colr, colr * 0.85, PANEL if k % 2 == 0 else DARK)
		if k % 2 == 0: _ring(st, c, rr + 0.1, rr + 0.6, yb - h * 0.55, yb - h * 0.45, Data.CITY_TRIM, Data.CITY_TRIM, GLOW)
		yb -= h
		rr *= 0.8
		k += 1
	return st.commit()

## v13.306 (owner: "model a dome that sits on top"): the overwatch's dome, as on his blueprint: a dark ring foot with a
## lit seam, a band of glass round it, the white dome rising in ribbed steps, a dark crown ring and a light on top.
static func _dome(st: SurfaceTool, c: Vector2, y: float) -> void:
	var R: float = Data.DOME_R
	_ring(st, c, 0.0, R * 1.06, y, y + 6.0, Data.TOWER_SPINE, Data.TOWER_SPINE, DARK)
	_ring(st, c, R * 1.06, R * 1.08, y + 2.5, y + 3.5, Data.CITY_TRIM, Data.CITY_TRIM, GLOW)
	_ring(st, c, R * 0.97, R, y + 6.0, y + 20.0, Data.KIT_GLASS, Data.KIT_GLASS, GLASS)
	_ring(st, c, 0.0, R * 1.02, y + 20.0, y + 23.0, Data.TOWER_WHITE, Data.TOWER_WHITE, PANEL)
	var steps := 7
	var h: float = Data.DOME_H
	for i in steps:   # the dome: a stack of short rings, each narrower (a quarter circle), a thin dark seam between
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var r0 := R * cos(t0 * PI * 0.5)
		var r1 := R * cos(t1 * PI * 0.5)
		var y0 := y + 23.0 + h * sin(t0 * PI * 0.5)
		var y1 := y + 23.0 + h * sin(t1 * PI * 0.5)
		var n := 40
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			var lo0 := c + d0 * r0
			var lo1 := c + d1 * r0
			var hi0 := c + d0 * r1
			var hi1 := c + d1 * r1
			var mid := (t0 + t1) * 0.25 * PI
			var nrm := (Vector3((d0 + d1).x, 0, (d0 + d1).y).normalized() * cos(mid) + Vector3.UP * sin(mid)).normalized()
			var colr: Color = Data.TOWER_WHITE if i % 3 != 2 else Data.TOWER_WHITE * 0.86
			_quad(st, Vector3(lo0.x, y0, lo0.y), Vector3(lo1.x, y0, lo1.y), Vector3(hi1.x, y1, hi1.y), Vector3(hi0.x, y1, hi0.y), nrm, colr, PANEL)
		if i < steps - 1 and i % 2 == 1: _ring(st, c, r1 - 0.2, r1 + 0.5, y1 - 0.4, y1 + 0.4, Data.TOWER_SPINE, Data.TOWER_SPINE, DARK)
	var yt := y + 23.0 + h
	_ring(st, c, 0.0, R * 0.16, yt - 2.0, yt + 3.0, Data.TOWER_SPINE, Data.TOWER_SPINE, DARK)
	_ring(st, c, 0.0, R * 0.05, yt + 3.0, yt + 9.0, Data.CITY_TRIM, Data.CITY_TRIM, GLOW)

## The overwatch's tower under the deck: the city's kit boxes (a glass core, white pillars, dark bands, pods) from the
## ground up to the deck's underside.
static func overwatch_parts(c: Vector2, ground: float, deck: float, R: float) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(str(c) + "|overwatch"))
	var under := deck - Data.DECK_T - 50.0
	var h := under - ground
	if h < 20.0: return out
	var w := R * 0.42
	_core(out, rng, c, w, w, ground, h, true)
	_pillars(out, rng, c, w, w, ground, h, true)
	_pods(out, rng, c, w, w, ground, h, true)
	return out

## A round slab (ring when r0 > 0) from y0 to y1 between angles a0..a1: top, sides, underside.
static func _ring(st: SurfaceTool, c: Vector2, r0: float, r1: float, y0: float, y1: float, top: Color, side: Color, kind: int, a0 := 0.0, a1 := TAU, glow := 0.0) -> void:
	var n := maxi(6, int(48.0 * (a1 - a0) / TAU))
	for i in n:
		var t0 := a0 + (a1 - a0) * i / n
		var t1 := a0 + (a1 - a0) * (i + 1) / n
		var d0 := Vector2(cos(t0), sin(t0))
		var d1 := Vector2(cos(t1), sin(t1))
		var o0 := c + d0 * r1
		var o1 := c + d1 * r1
		var i0 := c + d0 * r0
		var i1 := c + d1 * r0
		var nm := Vector3((d0 + d1).x, 0, (d0 + d1).y).normalized()
		_quad(st, Vector3(i0.x, y1, i0.y), Vector3(i1.x, y1, i1.y), Vector3(o1.x, y1, o1.y), Vector3(o0.x, y1, o0.y), Vector3.UP, top, kind, glow)
		_quad(st, Vector3(o0.x, y0, o0.y), Vector3(o1.x, y0, o1.y), Vector3(o1.x, y1, o1.y), Vector3(o0.x, y1, o0.y), nm, side, kind, glow)
		_quad(st, Vector3(o0.x, y0, o0.y), Vector3(i0.x, y0, i0.y), Vector3(i1.x, y0, i1.y), Vector3(o1.x, y0, o1.y), Vector3.DOWN, side * 0.7, kind, glow)
		if r0 > 0.01: _quad(st, Vector3(i1.x, y0, i1.y), Vector3(i0.x, y0, i0.y), Vector3(i0.x, y1, i0.y), Vector3(i1.x, y1, i1.y), -nm, side, kind, glow)

## The skyways and glass tunnels of a city tile, and the capitol at its port: [parts, capitol {} or {at, ...}].
## Skyways: raised roads along the avenues between the blocks (a dark deck, glass barriers, lit edges, white piers);
## glass tunnels between the giants of neighbouring blocks, white rings round them; an L of glass tunnel from the
## nearest giant to the capitol's deck.
static func city_links(pid: String, tile: int) -> Array:
	var out: Array = []
	var cr := CityPlan.rect(pid, tile)
	if cr.size == Vector2i.ZERO or not Data.CITY_TOWERS: return [out, {}]
	var g := CityPlan.ground(pid, tile)
	var org := Vector2(-Surface.EDGE, -Surface.EDGE) + Vector2(cr.position) * Data.BLOCK_REGION
	var size := Vector2(cr.size) * Data.BLOCK_REGION
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash("%s|%d|links" % [pid, tile]))
	# skyways along the inner avenues (each way), level 1 everywhere, level 2 on the first
	for ax in (0 if CityPlan.is_town(pid, tile) else 2):   # (v13.319: a town has none)
		for sl in CityPlan.sky_lines(pid, tile, ax):
			var k: int = sl[0]
			var line := (org.x if ax == 0 else org.y) + k * Data.BLOCK_REGION
			var levels: Array = sl[1]
			for ly in levels:
				_skyway(out, ax == 0, line, (org.y if ax == 0 else org.x), (org.y + size.y if ax == 0 else org.x + size.x), g, g + float(ly))
	out.append_array(interchange_parts(pid, tile))   # v13.331: the spiral interchanges at the skyways' ends
	out.append_array(walk_parts(pid, tile))   # v13.337: the covered footbridges and the canopies over the pavements
	# glass tunnels between neighbouring giants
	var giants := {}
	for rz in cr.size.y:
		for rx in cr.size.x:
			var tw: Array = CityPlan.towers(pid, tile, cr.position + Vector2i(rx, rz))
			if not tw.is_empty(): giants[Vector2i(rx, rz)] = tw[0]
	for gk in giants:
		var a: Dictionary = giants[gk]
		for e in [Vector2i(1, 0), Vector2i(0, 1)]:
			if not giants.has(gk + e): continue
			if CityPlan.is_outskirt(pid, tile, cr.position + gk) and CityPlan.is_outskirt(pid, tile, cr.position + gk + e): continue   # v13.344: (outskirt to outskirt: none)
			var b: Dictionary = giants[gk + e]
			var top := minf(float(a["base"]) + float(a["h"]), float(b["base"]) + float(b["h"]))
			for n in rng.randi_range(1, 2):
				var y := lerpf(float(a["base"]) + 40.0, top, rng.randf_range(0.2, 0.6))
				_tunnel(out, a["c"], b["c"], y)
	# the capitol at the port
	var cap := {}
	var locs := Surface.locations_in(pid, tile)
	if not locs.is_empty():
		var l: Dictionary = locs[0]
		var sh := Surface.island_shape(pid, l)
		var ic: Vector2 = sh[0]
		var irad: float = sh[1]
		var away: Vector2 = (ic - (org + size * 0.5))
		away = away.normalized() if away.length() > 1.0 else Vector2(0, 1)
		var fx := absf(away.x) >= absf(away.y)
		var dir := Vector2(signf(away.x), 0.0) if fx else Vector2(0.0, signf(away.y))
		var at := ic + dir * (irad + Data.CAPITOL_REACH + Data.CAPITOL_W * 0.5 - 10.0)
		at = at.clamp(Vector2(-Surface.EDGE + 300.0, -Surface.EDGE + 300.0), Vector2(Surface.EDGE - 300.0, Surface.EDGE - 300.0))
		var deck := Surface.pad_top(pid, tile)
		var ground := Surface.height(pid, tile, at.x, at.y)
		out.append_array(capitol_parts(at, minf(ground, deck - 60.0), deck, -dir))
		cap = {"at": at, "deck": deck, "top": deck + Data.CAPITOL_ABOVE}
		out.append_array(overwatch_parts(ic, Surface.height(pid, tile, ic.x, ic.y), deck, irad))   # v13.305: the overwatch under the deck
		var dm := Surface.deck_dome(pid, l)   # v13.306: the dome on the deck is solid
		out.append({"k": "solid", "p": Vector3(dm.x, deck, dm.y), "s": Vector3(Data.DOME_R * 1.6, 23.0 + Data.DOME_H * 0.8, Data.DOME_R * 1.6)})
		if not giants.is_empty():   # an L of glass tunnel from the nearest giant to the deck's edge
			var best: Dictionary = {}
			for gk2 in giants:
				var gt: Dictionary = giants[gk2]
				if best.is_empty() or (gt["c"] as Vector2).distance_to(ic) < (best["c"] as Vector2).distance_to(ic): best = gt
			var gc: Vector2 = best["c"]
			_tunnel(out, gc, Vector2(ic.x, ic.y + signf(gc.y - ic.y) * irad), deck + 6.0)
	return [out, cap]

## A raised road along x (along_z false: along x) at height y from s0 to s1 on line `line`: a dark deck, glass
## barriers, lit edges, a lane line, white piers down to the street.
static func _skyway(out: Array, along_z: bool, line: float, s0: float, s1: float, g: float, y: float) -> void:
	var L := s1 - s0
	var mid := (s0 + s1) * 0.5
	var W: float = Data.SKYWAY_W
	var put := func(k: String, across_off: float, yy: float, w: float, h: float, len: float, along_off := 0.0) -> void:
		var c := Vector3(line + across_off, yy, mid + along_off) if along_z else Vector3(mid + along_off, yy, line + across_off)
		out.append({"k": k, "p": c, "s": Vector3(w, h, len) if along_z else Vector3(len, h, w)})
	put.call("dark", 0.0, y - 3.0, W, 3.0, L)
	put.call("white", 0.0, y - 6.0, W * 0.7, 3.0, L)
	for sg in [-1.0, 1.0]:
		put.call("glass", sg * (W * 0.5 - 0.4), y, 0.8, 2.6, L)
		put.call("glow", sg * (W * 0.5 + 0.05), y - 1.6, 0.4, 0.5, L)
	put.call("glow", 0.0, y + 0.02, 0.5, 0.05, L)   # the middle line
	for sg in [-1.0, 1.0]:   # v13.320 (owner: "bigger lanes, enough for 4 cars"): two lanes each way, the lane lines
		put.call("glow", sg * W * 0.25, y + 0.02, 0.25, 0.05, L)
	# v13.320 (owner: "there's pillars blocking roads"): the piers stand on the pavement either side of the avenue,
	# never in the road, and only along the blocks (not in a crossing street or the alley); a cross beam carries the deck
	var S: float = Data.BLOCK_REGION
	var nb := int(round(L / S))
	for b in nb:
		for f in Data.SKYWAY_PIER_AT:
			var a := -L * 0.5 + (float(b) + float(f)) * S
			for sg in [-1.0, 1.0]:
				put.call("white", sg * Data.SKYWAY_PIER_OFF, g, Data.SKYWAY_PIER_W, y - 6.0 - g, Data.SKYWAY_PIER_W, a)
			put.call("white", 0.0, y - 8.5, Data.SKYWAY_PIER_OFF * 2.0 + Data.SKYWAY_PIER_W, 3.0, Data.SKYWAY_PIER_W * 0.8, a)

## v13.331 (owner: "roads shouldn't just be linear squares: curve and swirl round, a real loop from top to bottom,
## ramps that carry it up, everything looping together like a continuous track"): at each end of a skyway a twin
## spiral interchange carries it down to the street and back up. Going out of the city: the skyway lanes spiral
## down (one helix on the right), the street lanes run on out, both meet a turning loop at the end and come back in:
## up the other helix to the skyway, or on along the street. Every lane: [path (tile-local, the car's own height)],
## its name, and which lanes it can run on to. Cached per tile.
static var _ix := {}
static func interchanges(pid: String, tile: int) -> Array:
	var key := "%s|%d" % [pid, tile]
	if _ix.has(key): return _ix[key]
	var out: Array = []   # one per skyway end: {o, w, B, line, ax, levels, stations, lanes: {name: PackedVector3Array}}
	var cr := CityPlan.rect(pid, tile)
	if cr.size == Vector2i.ZERO or not Data.CITY_TOWERS or CityPlan.is_town(pid, tile) or not Data.CITY_RAMPS:
		_ix[key] = out
		return out
	var g := CityPlan.ground(pid, tile)
	var S: float = Data.BLOCK_REGION
	var org := Vector2(-Surface.EDGE, -Surface.EDGE) + Vector2(cr.position) * S
	var size := Vector2(cr.size) * S
	var lw: float = Data.TRAFFIC_LANE_W
	var hv: float = Data.TRAFFIC_HOVER
	for ax in 2:
		for sl in CityPlan.sky_lines(pid, tile, ax):
			var kk: int = sl[0]
			var line: float = (org.x if ax == 0 else org.y) + kk * S
			var lvls: Array = sl[1]
			for sgn in [-1.0, 1.0]:
				var o := Vector2(0.0, sgn) if ax == 0 else Vector2(sgn, 0.0)   # outward
				var w := Vector2(-o.y, o.x)                                    # the outbound lanes' side
				var B := Vector2(line, org.y if sgn < 0.0 else org.y + size.y) if ax == 0 else Vector2(org.x if sgn < 0.0 else org.x + size.x, line)
				var st: Array = [0.0]   # stations along o: the city edge, each helix, the turning loop
				var d := 0.0
				var radii: Array = []
				for j in lvls.size():
					var R: float = float(Data.RAMP_R[j])
					d = (d + float(Data.RAMP_R[j - 1]) + Data.RAMP_GAP + R) if j > 0 else (R + Data.RAMP_GAP)
					st.append(d)
					radii.append(R)
				st.append(d + float(radii[-1]) + Data.RAMP_GAP)
				var U: float = st[-1]
				var lanes := {}
				var sp: float = Data.RAMP_SPLIT
				var M: float = Data.RAMP_MERGE
				var sm: Array = [0.0]   # v13.332: where the street lanes meet a spiral's foot (a little past it)
				for i in range(1, st.size() - 1): sm.append(float(st[i]) + M)
				sm.append(U)
				for k in 2:
					var off := lw * (0.5 + k)
					for j in lvls.size():
						var R2: float = radii[j]
						var Y: float = g + float(lvls[j]) + hv
						var turns: int = int(Data.RAMP_TURNS[j])
						var D: float = st[j + 1]
						# v13.332 (owner: "pillars going straight through that road"): the two spirals stand apart (sp
						# either side of the avenue) so they never cross; a short slant leads on and off each
						var pd := PackedVector3Array()
						var e0 := B + w * off
						pd.append(Vector3(e0.x, Y, e0.y))
						pd.append_array(_helix(B + o * D, o, w, R2 + Data.RAMP_MID - off, off + sp, Y, g + hv, turns, 1.0))
						var f0 := B + o * float(sm[j + 1]) + w * off
						pd.append(Vector3(f0.x, g + hv, f0.y))
						lanes["down_%d_%d" % [j, k]] = pd
						var f1 := B + o * float(sm[j + 1]) - w * off
						var pu := PackedVector3Array([Vector3(f1.x, g + hv, f1.y)])
						pu.append_array(_helix(B + o * D, o, -w, R2 + Data.RAMP_MID - off, off + sp, g + hv, Y, turns, -1.0))
						var e1 := B - w * off
						pu.append(Vector3(e1.x, Y, e1.y))
						lanes["up_%d_%d" % [j, k]] = pu
					for i in sm.size() - 1:   # the street out and back between the spirals' feet
						var a := B + o * float(sm[i]) + w * off
						var b := B + o * float(sm[i + 1]) + w * off
						lanes["out_%d_%d" % [i, k]] = PackedVector3Array([Vector3(a.x, g + hv, a.y), Vector3(b.x, g + hv, b.y)])
						var a2 := B + o * float(sm[i + 1]) - w * off
						var b2 := B + o * float(sm[i]) - w * off
						lanes["in_%d_%d" % [i, k]] = PackedVector3Array([Vector3(a2.x, g + hv, a2.y), Vector3(b2.x, g + hv, b2.y)])
					lanes["uturn_%d" % k] = _uturn(B + o * U, o, w, off, Data.RAMP_LOOP_R, g + hv)
				out.append({"o": o, "w": w, "B": B, "line": line, "ax": ax, "levels": lvls, "stations": st, "radii": radii, "lanes": lanes, "g": g})
	_ix[key] = out
	return out

## Points of a helix lane: it leaves start (station c, the lane's offset off to the side w) heading o, turns toward w
## round a centre (c + w (off + r)) at radius r, dir 1 = winding one way (out and down), -1 the other (up and in),
## from height y0 to y1 over a whole number of turns, and ends where it began, heading o again (or -o going up).
static func _helix(c: Vector2, o: Vector2, w: Vector2, r: float, off: float, y0: float, y1: float, turns: int, dir: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var ctr := c + w * (off + r)
	var n := int(turns * 360.0 / Data.RAMP_STEP_DEG)
	for i in n + 1:
		var f := float(i) / n
		var ph := -PI * 0.5 + TAU * turns * f * dir
		var q := ctr + r * (o * cos(ph) + w * sin(ph))
		pts.append(Vector3(q.x, lerpf(y0, y1, f), q.y))
	return pts

## The turning loop at the far end: out on the w side, round a circle and back on the other side.
static func _uturn(c: Vector2, o: Vector2, w: Vector2, off: float, rr: float, y: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var q := c + o * rr
	var a := asin(clampf(off / rr, -1.0, 1.0))
	var th0 := PI - a
	var th1 := -PI + a
	var n := int((th0 - th1) / deg_to_rad(Data.RAMP_STEP_DEG))
	pts.append(Vector3((c + w * off).x, y, (c + w * off).y))
	for i in n + 1:
		var th := lerpf(th0, th1, float(i) / n)
		var p := q + rr * (o * cos(th) + w * sin(th))
		pts.append(Vector3(p.x, y, p.y))
	pts.append(Vector3((c - w * off).x, y, (c - w * off).y))
	return pts

## v13.337 (owner: "crosswalks should be like escalators for people to go up and over, covered, to be protected; and
## covered walkways along the roads, room for pedestrians"): at each avenue crossing, a covered glass footbridge over
## each of the two avenues, just past the crossing: an escalator up from the pavement either side, a glass tube across
## over the traffic, walls and a glass roof all the way. And along every pavement facing an avenue, a glass canopy on
## slim posts. All of it is parts of the one city-links mesh.
static func walk_parts(pid: String, tile: int) -> Array:
	var out: Array = []
	var cr := CityPlan.rect(pid, tile)
	if cr.size == Vector2i.ZERO or not Data.CITY_TOWERS or not Data.CITY_FOOTBRIDGES: return out
	var g := CityPlan.ground(pid, tile)
	var S: float = Data.BLOCK_REGION
	var org := Vector2(-Surface.EDGE, -Surface.EDGE) + Vector2(cr.position) * S
	var size := Vector2(cr.size) * S
	var av: float = Data.CITY_AVENUE * Data.BLOCK_MIN
	var lines := func(n_blocks: int, o: float) -> Array:   # [coordinate, half the road's width]
		var l: Array = [[o + av * 0.5, av * 0.5]]
		for b in range(1, n_blocks): l.append([o + b * S, av])
		l.append([o + n_blocks * S - av * 0.5, av * 0.5])
		return l
	var lx: Array = lines.call(cr.size.x, org.x)
	var lz: Array = lines.call(cr.size.y, org.y)
	var H: float = g + Data.FOOTBRIDGE_H
	var E: float = Data.FOOTBRIDGE_ESC
	var off: float = Data.FOOTBRIDGE_FROM
	var side: float = Data.FOOTBRIDGE_W * 0.5 + 1.0
	var co := CityPlan.core(pid, tile)   # v13.344: footbridges and canopies in the core (the outskirts keep the triangle budget)
	var core_box := Rect2(Vector2(-Surface.EDGE, -Surface.EDGE) + Vector2(co.position) * S, Vector2(co.size) * S).grow(av)
	for ax in lx:
		for az in lz:
			var X: float = ax[0]
			var Z: float = az[0]
			if not core_box.has_point(Vector2(X, Z)): continue
			var hx: float = ax[1]
			var hz: float = az[1]
			# over the avenue that runs along x (spanning z), on the +x arm of the crossing
			var x0 := X + hx + off
			if x0 + E + 4.0 < org.x + size.x:
				var a1 := Vector3(x0 + E, g + 0.1, Z - hz - side)
				var b1 := Vector3(x0, H, Z - hz - side)
				var b2 := Vector3(x0, H, Z + hz + side)
				var a2 := Vector3(x0 + E, g + 0.1, Z + hz + side)
				out.append({"k": "ribbon", "pts": PackedVector3Array([a1, b1, b2, a2]), "w": Data.FOOTBRIDGE_W, "rail": true, "roof": true, "walk": true})
			# over the avenue that runs along z (spanning x), on the +z arm
			var z0 := Z + hz + off
			if z0 + E + 4.0 < org.y + size.y:
				var c1 := Vector3(X - hx - side, g + 0.1, z0 + E)
				var d1 := Vector3(X - hx - side, H, z0)
				var d2 := Vector3(X + hx + side, H, z0)
				var c2 := Vector3(X + hx + side, g + 0.1, z0 + E)
				out.append({"k": "ribbon", "pts": PackedVector3Array([c1, d1, d2, c2]), "w": Data.FOOTBRIDGE_W, "rail": true, "roof": true, "walk": true})
	# canopies over the pavements along the avenues: the lots' edges facing a road, a glass roof on posts
	var pv: float = Data.CITY_PAVEMENT * Data.BLOCK_MIN
	for rz in cr.size.y:
		for rx in cr.size.x:
			if CityPlan.is_outskirt(pid, tile, cr.position + Vector2i(rx, rz)): continue
			var plan := CityPlan.block(pid, tile, cr.position + Vector2i(rx, rz))
			var bo := org + Vector2(rx, rz) * S
			for lr in plan.get("lots", []):
				var r: Rect2i = lr
				var x0 := bo.x + r.position.x * Data.BLOCK_MIN
				var z0 := bo.y + r.position.y * Data.BLOCK_MIN
				var x1 := bo.x + r.end.x * Data.BLOCK_MIN
				var z1 := bo.y + r.end.y * Data.BLOCK_MIN
				for ed in [[Vector2(x0, z0), Vector2(x1, z0), Vector2(0, 1)], [Vector2(x0, z1), Vector2(x1, z1), Vector2(0, -1)], [Vector2(x0, z0), Vector2(x0, z1), Vector2(1, 0)], [Vector2(x1, z0), Vector2(x1, z1), Vector2(-1, 0)]]:
					var p0: Vector2 = ed[0]
					var p1: Vector2 = ed[1]
					var inn: Vector2 = ed[2]   # toward the lot
					var mid := (p0 + p1) * 0.5 + inn * pv * 0.82   # (its back half: the footbridges' escalators run along the front)
					var L := p0.distance_to(p1) - 6.0
					if L < 10.0: continue
					var along_x := absf(p1.x - p0.x) > 1.0
					out.append({"k": "pane", "p": Vector3(mid.x, g + Data.CANOPY_H, mid.y), "s": Vector3(L, 0.4, pv * 0.36) if along_x else Vector3(pv * 0.36, 0.4, L)})
					out.append({"k": "glow", "p": Vector3(mid.x - inn.x * pv * 0.18, g + Data.CANOPY_H - 0.1, mid.y - inn.y * pv * 0.18), "s": Vector3(L, 0.3, 0.3) if along_x else Vector3(0.3, 0.3, L)})
					var n_post := int(L / Data.CANOPY_POST_EVERY)
					for k in n_post + 1:
						var f := -0.5 + float(k) / maxf(1.0, n_post)
						var q := mid - inn * pv * 0.15 + (Vector2(L * f, 0) if along_x else Vector2(0, L * f))
						out.append({"k": "post", "p": Vector3(q.x, g, q.y), "s": Vector3(0.5, Data.CANOPY_H, 0.5)})
	return out

## The interchanges' roadways to draw: helix decks with rails and lit edges, their columns, the street out to the loop.
static func interchange_parts(pid: String, tile: int) -> Array:
	var out: Array = []
	var hv: float = Data.TRAFFIC_HOVER
	for e in interchanges(pid, tile):
		var g: float = e["g"]
		var o: Vector2 = e["o"]
		var w: Vector2 = e["w"]
		var B: Vector2 = e["B"]
		var st: Array = e["stations"]
		var mid: float = Data.RAMP_MID
		for j in (e["levels"] as Array).size():
			var R: float = e["radii"][j]
			var Y: float = g + float(e["levels"][j])
			var D: float = st[j + 1]
			var sp: float = Data.RAMP_SPLIT
			var foot: float = D + Data.RAMP_MERGE
			for side in [1.0, -1.0]:   # the down helix (w side) and the up helix (the other)
				var ws: Vector2 = w * side
				var deck := PackedVector3Array()
				var e0 := B + ws * mid
				deck.append(Vector3(e0.x, Y, e0.y))   # from the skyway's end, round and down, to the street at its foot
				deck.append_array(_helix(B + o * D, o, ws, R, mid + sp, Y, g, int(Data.RAMP_TURNS[j]), side))
				var f := B + o * foot + ws * mid
				deck.append(Vector3(f.x, g + 0.15, f.y))
				out.append({"k": "ribbon", "pts": deck, "w": Data.RAMP_W, "rail": true})
				var ctr := B + o * D + ws * (mid + sp + R)
				for c in Data.RAMP_COLUMNS:   # columns round the outside of the spiral, up to its top
					var a := TAU * c / Data.RAMP_COLUMNS
					var q := ctr + (R + Data.RAMP_W * 0.5 + Data.RAMP_WALL_T + 4.0) * Vector2(cos(a), sin(a))
					# v13.332 (owner: "pillars going straight through that road"): never on the street, a slant or
					# the next spiral: only the columns on the spiral's far side
					if absf((q - B).dot(w)) < mid + sp + Data.RAMP_W + 4.0: continue
					if (q - B).dot(o) > D + R + Data.RAMP_W * 0.5 + 1.0 or (q - B).dot(o) < D - R - Data.RAMP_W * 0.5 - 1.0: continue
					out.append({"k": "white", "p": Vector3(q.x, g, q.y), "s": Vector3(3.0, Y - g + 2.0, 3.0)})
				out.append({"k": "white", "p": Vector3(ctr.x, g, ctr.y), "s": Vector3(14.0, Y - g + 6.0, 14.0)})   # the core
				out.append({"k": "glow", "p": Vector3(ctr.x, Y + 6.0, ctr.y), "s": Vector3(15.0, 0.6, 15.0)})
		# the street out to the loop (both ways) and the loop
		var U: float = st[-1]
		var a0 := B
		var a1 := B + o * U
		out.append({"k": "ribbon", "pts": PackedVector3Array([Vector3(a0.x, g + 0.15, a0.y), Vector3(a1.x, g + 0.15, a1.y)]), "w": Data.TRAFFIC_LANE_W * 4.0 + 4.0, "rail": false})
		var loop := _uturn(B + o * U, o, w, Data.RAMP_MID, Data.RAMP_LOOP_R, g + 0.15)
		out.append({"k": "ribbon", "pts": loop, "w": Data.RAMP_W, "rail": false})
	return out

## A road along a line of points: a deck (dark top, white underside), with glass rails and lit edges if rail.
static func _ribbon(st: SurfaceTool, pts: PackedVector3Array, wd: float, rail: bool, far: bool, roof := false) -> void:
	var h := wd * 0.5
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dd := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if dd.length() < 0.01: continue
		var sd := Vector3(-dd.z, 0.0, dd.x).normalized() * h
		var al := a + sd
		var ar := a - sd
		var bl := b + sd
		var br := b - sd
		var up := Vector3.UP
		_quad(st, ar, al, bl, br, up, Data.TOWER_SPINE, DARK)
		if far: continue
		var t := Vector3(0, 1.6, 0)
		_quad(st, al - t, ar - t, br - t, bl - t, -up, Data.TOWER_WHITE, PANEL)   # its underside
		_quad(st, ar - t, ar, br, br - t, -sd.normalized(), Data.TOWER_WHITE, PANEL)
		_quad(st, al, al - t, bl - t, bl, sd.normalized(), Data.TOWER_WHITE, PANEL)
		var ln := Vector3(0, 0.03, 0)
		var gi := sd.normalized() * 0.3
		_quad(st, ar + gi + ln, ar + ln, br + ln, br + gi + ln, up, Data.CITY_TRIM, GLOW)   # lit edges
		_quad(st, al + ln, al - gi + ln, bl - gi + ln, bl + ln, up, Data.CITY_TRIM, GLOW)
		if rail:   # v13.332 (owner: "protective walls so cars don't fall off, like in reality"): a solid white wall each side, lit on top
			var r := Vector3(0, Data.RAMP_WALL_H, 0)
			var th := sd.normalized() * Data.RAMP_WALL_T
			for e in [[ar, br, -1.0], [al, bl, 1.0]]:
				var p0: Vector3 = e[0]
				var p1: Vector3 = e[1]
				var sg: float = e[2]
				var o0 := p0 + th * sg
				var o1 := p1 + th * sg
				var nin := -sd.normalized() * sg
				_quad(st, p0, p0 + r, p1 + r, p1, nin, Data.TOWER_WHITE, PANEL)
				_quad(st, o0 + r, o0, o1, o1 + r, -nin, Data.TOWER_WHITE, PANEL)
				_quad(st, o0 + r, p0 + r, p1 + r, o1 + r, Vector3.UP, Data.CITY_TRIM, GLOW)
		if roof:   # v13.337 (owner: "covered, to be protected"): glass sides up to a glass roof, white ribs along its edges
			var gh := Vector3(0, Data.FOOTBRIDGE_ROOF_H, 0)
			var lo := Vector3(0, Data.RAMP_WALL_H, 0)
			_quad(st, ar + lo, ar + gh, br + gh, br + lo, -sd.normalized(), Data.KIT_GLASS, GLASS)
			_quad(st, al + gh, al + lo, bl + lo, bl + gh, sd.normalized(), Data.KIT_GLASS, GLASS)
			_quad(st, ar + gh, al + gh, bl + gh, br + gh, up, Data.KIT_GLASS, GLASS)
			var rb := sd.normalized() * 0.35
			_quad(st, ar + gh, ar + gh + rb, br + gh + rb, br + gh, up, Data.TOWER_WHITE, PANEL)
			_quad(st, al + gh - rb, al + gh, bl + gh, bl + gh - rb, up, Data.TOWER_WHITE, PANEL)

## A glass tunnel between two points (tile-local x, z) at height y, axis-aligned legs: glass tube with white rings.
static func _tunnel(out: Array, a: Vector2, b: Vector2, y: float) -> void:
	var legs := [[a, Vector2(b.x, a.y)], [Vector2(b.x, a.y), b]]
	for lg in legs:
		var p0: Vector2 = lg[0]
		var p1: Vector2 = lg[1]
		var L := p0.distance_to(p1)
		if L < 2.0: continue
		var m := (p0 + p1) * 0.5
		var along_x := absf(p1.x - p0.x) > absf(p1.y - p0.y)
		var T: float = Data.TUNNEL_W
		out.append({"k": "glass", "p": Vector3(m.x, y, m.y), "s": Vector3(L, T * 0.8, T) if along_x else Vector3(T, T * 0.8, L)})
		out.append({"k": "dark", "p": Vector3(m.x, y - 1.5, m.y), "s": Vector3(L, 1.5, T * 0.7) if along_x else Vector3(T * 0.7, 1.5, L)})
		var n := int(L / Data.TUNNEL_RING_EVERY)
		for i in range(1, n):
			var q := p0.lerp(p1, float(i) / n)
			out.append({"k": "white", "p": Vector3(q.x, y - 1.0, q.y), "s": Vector3(3.0, T * 0.8 + 2.0, T + 2.0) if along_x else Vector3(T + 2.0, T * 0.8 + 2.0, 3.0)})

# ---------------------------------------------------------------------------------------------------------------- drawing
static func _part(st: SurfaceTool, p: Dictionary, far: bool) -> void:
	var k := str(p["k"])
	var pp: Vector3 = p.get("p", Vector3.ZERO)
	var s: Vector3 = p.get("s", Vector3.ZERO)
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
		"glow":   # a line of light
			_bevel_box(st, pp, s, 0.0, Data.CITY_TRIM, GLOW, GLOW, true)
		"post":   # v13.337: a plain slim box (no rounded edges: the canopies' posts)
			_bevel_box(st, pp, s, 0.0, Data.TOWER_WHITE, PANEL, PANEL, true)
		"pane":   # v13.337: a plain glass slab (the canopies' roofs)
			_bevel_box(st, pp, s, 0.0, Data.KIT_GLASS, GLASS, GLASS, true)
		"ribbon":   # v13.331: a road along points (the interchange spirals, the street out, the loop)
			_ribbon(st, p["pts"], float(p["w"]), bool(p.get("rail", false)), far, bool(p.get("roof", false)))

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
	if kind == GLOW and glow <= 0.0: glow = 1.6
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
