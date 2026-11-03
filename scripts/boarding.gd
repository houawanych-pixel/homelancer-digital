class_name Boarding
extends RefCounted
## v11.71 (owner's walk-through, Nov 3): the inside of a battleship, GREYBOX, big enough to fight in as a MECH on foot.
## Tunnels are wide enough for four mechs side by side, with a hexagon cross-section (the walls lean out, then back
## in); the halls are big. Every opening between two areas is a sliding DOOR that opens as you walk up.
##
##   IN:  the PORT LAUNCH BAY (one side of the ship) -> a tunnel down into the sunken MUSTER HALL -> the aft passage
##        to the CARGO HALL (heading for the back of the ship) -> the DESCENT RAMP, sloping down into the BELLY ->
##        the REACTOR ROOM: the reactor sits in a shield; their BOSS MECH fights you round it. Boss down = shield down.
##   OUT: blow the reactor and the descent ramp SEALS; the far door opens onto the BELLY RAMP, back up and forward along
##        the BELLY RUN to the FORWARD HOLD, where a door loops back round (the STARBOARD LOOP) to the STARBOARD LAUNCH
##        BAY on the other side of the ship: out. 90 seconds.
##   SIDE: from the muster hall the BRIDGE LIFT climbs to the BRIDGE: a mech guards it. On a bounty job it is your
##        bounty (it drops the pilot: tractor him in, take him back for the bounty); otherwise it holds a hostage.
##
## Units: metres. +X starboard, -Z toward the bow, +Z toward the stern. Floors are at different heights (the belly is
## lower); a ramp's floor slopes along its length.

static var sunk := {}   # system id -> true: you blew that battleship's reactor (this session: it is gone)

# name: {r: [x0, x1, z0, z1], y: [floor at the low end, floor at the high end] along `axis`, h: height, label, guards, hex}
const ROOMS := {
	"lbay": {"r": [-420.0, -300.0, -60.0, 60.0], "y": [0.0, 0.0], "axis": "x", "h": 80.0, "label": "PORT LAUNCH BAY", "guards": 0, "hex": false},
	"t1": {"r": [-300.0, -160.0, -34.0, 34.0], "y": [0.0, -10.0], "axis": "x", "h": 50.0, "label": "ENTRY TUNNEL", "guards": 0, "hex": true},
	"muster": {"r": [-160.0, 40.0, -110.0, 110.0], "y": [-10.0, -10.0], "axis": "z", "h": 70.0, "label": "MUSTER HALL", "guards": 3, "hex": false},
	"t2": {"r": [-90.0, -22.0, 110.0, 330.0], "y": [-10.0, -10.0], "axis": "z", "h": 50.0, "label": "AFT PASSAGE", "guards": 0, "hex": true},
	"cargo": {"r": [-160.0, 60.0, 330.0, 520.0], "y": [-10.0, -10.0], "axis": "z", "h": 70.0, "label": "CARGO HALL", "guards": 3, "hex": false},
	"r1": {"r": [-60.0, 8.0, 520.0, 780.0], "y": [-10.0, -100.0], "axis": "z", "h": 50.0, "label": "DESCENT RAMP", "guards": 0, "hex": true},
	"reactor": {"r": [-200.0, 200.0, 780.0, 1060.0], "y": [-100.0, -100.0], "axis": "z", "h": 120.0, "label": "REACTOR ROOM (BELLY)", "guards": 2, "hex": false},
	"r2": {"r": [80.0, 148.0, 520.0, 780.0], "y": [-40.0, -100.0], "axis": "z", "h": 50.0, "label": "BELLY RAMP", "guards": 0, "hex": true},
	"t3": {"r": [80.0, 148.0, -100.0, 520.0], "y": [-40.0, -40.0], "axis": "z", "h": 50.0, "label": "BELLY RUN", "guards": 0, "hex": true},
	"fhold": {"r": [60.0, 260.0, -260.0, -100.0], "y": [-40.0, -40.0], "axis": "z", "h": 70.0, "label": "FORWARD HOLD", "guards": 2, "hex": false},
	"t4a": {"r": [260.0, 328.0, -260.0, -100.0], "y": [-40.0, -40.0], "axis": "z", "h": 50.0, "label": "STARBOARD LOOP", "guards": 0, "hex": true},
	"t4r": {"r": [260.0, 328.0, -100.0, 60.0], "y": [-40.0, 0.0], "axis": "z", "h": 50.0, "label": "STARBOARD LOOP", "guards": 0, "hex": true},
	"t4b": {"r": [260.0, 328.0, 60.0, 180.0], "y": [0.0, 0.0], "axis": "z", "h": 50.0, "label": "STARBOARD LOOP", "guards": 0, "hex": true},
	"sbay": {"r": [328.0, 448.0, 60.0, 180.0], "y": [0.0, 0.0], "axis": "x", "h": 80.0, "label": "STARBOARD LAUNCH BAY", "guards": 0, "hex": false},
	"t5": {"r": [-90.0, -22.0, -330.0, -110.0], "y": [40.0, -10.0], "axis": "z", "h": 50.0, "label": "BRIDGE LIFT", "guards": 0, "hex": true},
	"bridge": {"r": [-160.0, 40.0, -480.0, -330.0], "y": [40.0, 40.0], "axis": "z", "h": 50.0, "label": "BRIDGE", "guards": 1, "hex": false},
}
const WALL := 4.0                         # wall thickness
const START_AT := Vector3(-380, 0, 0)     # where you land inside (the port bay), facing +X
const START_FACE := Vector3(1, 0, 0)
const CORE_AT := Vector3(0, -100, 940)    # the reactor (its foot on the belly deck)
const CORE_SHIELD_R := 60.0               # the shield bubble round it
const BOSS_AT := Vector3(0, -100, 1010)
const BRIDGE_MECH_AT := Vector3(-60, 40, -440)
const EXIT_X := 440.0                     # past this, at the starboard bay's open side: out
const ENTRY_X := -416.0                   # (the port bay's open side: you can't walk back out there)
const SEAL_DOOR := ["r1", "reactor"]      # slams shut when the reactor blows (the way you came)
const ESCAPE_DOOR := ["reactor", "r2"]    # opens when the reactor blows (the way out)
const DOOR_OPEN_AT := 110.0               # m: a door slides open when you are this close
const ROUTE_IN := ["lbay", "t1", "muster", "t2", "cargo", "r1", "reactor"]
const ROUTE_OUT := ["reactor", "r2", "t3", "fhold", "t4a", "t4r", "t4b", "sbay"]

static func rect(k: String) -> Array: return ROOMS[k]["r"]

static func room_at(p: Vector3, pad := 0.0) -> String:
	for k in ROOMS:
		var r: Array = ROOMS[k]["r"]
		if p.x > float(r[0]) + pad and p.x < float(r[1]) - pad and p.z > float(r[2]) + pad and p.z < float(r[3]) - pad: return k
	return ""

static func inside(p: Vector3, pad := 0.0) -> bool:
	return room_at(p, pad) != ""

## The deck height in a room at (x, z): flat, or sloping along a ramp.
static func floor_of(k: String, x: float, z: float) -> float:
	var R: Dictionary = ROOMS[k]
	var r: Array = R["r"]
	var ya: float = R["y"][0]
	var yb: float = R["y"][1]
	if is_equal_approx(ya, yb): return ya
	var t: float = clampf((x - float(r[0])) / (float(r[1]) - float(r[0])), 0.0, 1.0) if R["axis"] == "x" else clampf((z - float(r[2])) / (float(r[3]) - float(r[2])), 0.0, 1.0)
	return lerpf(ya, yb, t)

static func floor_at(p: Vector3) -> float:
	var k := room_at(p)
	if k == "": k = room_at(keep_in(p, 1.0))
	return floor_of(k, p.x, p.z) if k != "" else 0.0

static func roof_at(p: Vector3) -> float:
	var k := room_at(p)
	return floor_at(p) + (float(ROOMS[k]["h"]) if k != "" else 50.0)

## Clamp a point onto the nearest room floor (a mech that walks into a wall stays in).
static func keep_in(p: Vector3, pad := 10.0) -> Vector3:
	if inside(p, pad): return p
	var best := p
	var bd := INF
	for k in ROOMS:
		var r: Array = ROOMS[k]["r"]
		var cx := (float(r[0]) + float(r[1])) * 0.5
		var cz := (float(r[2]) + float(r[3])) * 0.5
		var q := Vector3(clampf(p.x, minf(float(r[0]) + pad, cx), maxf(float(r[1]) - pad, cx)), p.y, clampf(p.z, minf(float(r[2]) + pad, cz), maxf(float(r[3]) - pad, cz)))
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = q
	return best

## Where two rooms touch: {axis "x" (a wall of constant x) / "z", at, lo, hi, base (deck height there), h}, or {}.
static func joint(a: String, b: String) -> Dictionary:
	var A: Array = ROOMS[a]["r"]
	var B: Array = ROOMS[b]["r"]
	for pair in [[A[1], B[0]], [A[0], B[1]]]:
		if absf(float(pair[0]) - float(pair[1])) < 0.5:
			var lo := maxf(float(A[2]), float(B[2]))
			var hi := minf(float(A[3]), float(B[3]))
			if hi - lo > 4.0: return {"axis": "x", "at": float(pair[0]), "lo": lo, "hi": hi, "base": floor_of(a, float(pair[0]), (lo + hi) * 0.5), "h": minf(float(ROOMS[a]["h"]), float(ROOMS[b]["h"]))}
	for pair in [[A[3], B[2]], [A[2], B[3]]]:
		if absf(float(pair[0]) - float(pair[1])) < 0.5:
			var lo := maxf(float(A[0]), float(B[0]))
			var hi := minf(float(A[1]), float(B[1]))
			if hi - lo > 4.0: return {"axis": "z", "at": float(pair[0]), "lo": lo, "hi": hi, "base": floor_of(a, (lo + hi) * 0.5, float(pair[0])), "h": minf(float(ROOMS[a]["h"]), float(ROOMS[b]["h"]))}
	return {}

static func doors() -> Array:
	var out: Array = []
	var ks: Array = ROOMS.keys()
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			var jt := joint(ks[i], ks[j])
			if jt.is_empty(): continue
			jt["rooms"] = [ks[i], ks[j]]
			out.append(jt)
	return out

static func is_door(d: Dictionary, pair: Array) -> bool:
	return (d["rooms"] as Array).has(pair[0]) and (d["rooms"] as Array).has(pair[1])

# ---------------------------------------------------------------- building (greybox)
static var _grid_tex: ImageTexture
## The greybox material: flat grey with a 10 m grid laid on in world space (so every surface reads its size).
static func grey(col: Color) -> StandardMaterial3D:
	if _grid_tex == null:
		var s := 64
		var img := Image.create(s, s, true, Image.FORMAT_RGB8)
		for y in s:
			for x in s:
				var line: bool = x < 2 or y < 2 or (x >= s / 2 - 1 and x <= s / 2) or (y >= s / 2 - 1 and y <= s / 2)
				img.set_pixel(x, y, Color(0.62, 0.62, 0.64) if line else Color(1, 1, 1))
		img.generate_mipmaps()
		_grid_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.albedo_texture = _grid_tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 20.0   # (one texture = 20 m: a line every 10 m)
	m.roughness = 0.85
	return m

## Build every area, its doors, lights and the reactor pit under `root`. Returns {"boxes": the solid walls,
## "doors": [{rooms, axis, at, lo, hi, base, h, panels, box, center, open, locked, sealed}], "alarm": the lamps,
## "path": the exit lights}.
static func build(root: Node3D, tint: Color) -> Dictionary:
	var boxes: Array = []
	var wall_m := grey(Color(0.44, 0.45, 0.48))
	var deck_m := grey(Color(0.36, 0.37, 0.4))
	var roof_m := grey(Color(0.22, 0.23, 0.26))
	var trim := ShipFactory.mat(tint.lerp(Color(0.3, 0.8, 1.0), 0.5) * 0.55, true)   # (a dim coloured glow: pure white strips glared)
	var door_m := grey(Color(0.62, 0.58, 0.48))
	var lamps: Array = []
	var dl := doors()
	for k in ROOMS:
		var R: Dictionary = ROOMS[k]
		var r: Array = R["r"]
		var x0: float = r[0]
		var x1: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var h: float = R["h"]
		var ylo: float = minf(float(R["y"][0]), float(R["y"][1]))
		var yhi: float = maxf(float(R["y"][0]), float(R["y"][1]))
		_ramp(root, k, -WALL, deck_m)   # the deck (sloping on a ramp)
		_ramp(root, k, h, roof_m)       # the roof, the same height over it
		for side in [["x", x0, z0, z1, -1.0], ["x", x1, z0, z1, 1.0], ["z", z0, x0, x1, -1.0], ["z", z1, x0, x1, 1.0]]:
			if k == "lbay" and side[0] == "x" and is_equal_approx(float(side[1]), x0): continue   # the port bay's open side (in)
			if k == "sbay" and side[0] == "x" and is_equal_approx(float(side[1]), x1): continue   # the starboard bay's open side (out)
			var cuts: Array = []
			for d in dl:
				if not (d["rooms"] as Array).has(k) or d["axis"] != side[0] or absf(float(d["at"]) - float(side[1])) > 0.5: continue
				cuts.append([float(d["lo"]), float(d["hi"])])
			cuts.sort_custom(func(a, b): return a[0] < b[0])
			var at := float(side[2])
			for c in cuts + [[float(side[3]), float(side[3])]]:
				if float(c[0]) - at > 0.5: _wall(root, boxes, side, at, float(c[0]), ylo, yhi + h, h, bool(R["hex"]), wall_m)
				at = maxf(at, float(c[1]))
		# light strips along the long walls, a glow line down the deck
		var long_z: bool = (z1 - z0) >= (x1 - x0)
		if long_z:
			for sx in [x0 + 1.0, x1 - 1.0]:
				_slab(root, Vector3(sx - 0.4, ylo + h * 0.16, z0 + 6), Vector3(sx + 0.4, ylo + h * 0.16 + 0.7, z1 - 6), trim, null)
			_ramp_strip(root, k, trim)
		else:
			for sz in [z0 + 1.0, z1 - 1.0]:
				_slab(root, Vector3(x0 + 6, ylo + h * 0.16, sz - 0.4), Vector3(x1 - 6, ylo + h * 0.16 + 0.7, sz + 0.4), trim, null)
			_ramp_strip(root, k, trim)
		# lamps: one every ~100 m (tunnels: down the middle)
		var nx := maxi(1, int(round((x1 - x0) / 110.0)))
		var nz := maxi(1, int(round((z1 - z0) / 110.0)))
		for ix in nx:
			for iz in nz:
				var lx := x0 + (x1 - x0) * (ix + 0.5) / nx
				var lz := z0 + (z1 - z0) * (iz + 0.5) / nz
				var fy := floor_of(k, lx, lz)
				_slab(root, Vector3(lx - 6, fy + h - 0.8, lz - 6), Vector3(lx + 6, fy + h - 0.2, lz + 6), trim, null)
				var lamp := OmniLight3D.new()
				lamp.position = Vector3(lx, fy + h * 0.55, lz)   # (low enough not to burn the roof white)
				lamp.omni_range = 150.0
				lamp.light_energy = 1.15
				lamp.light_color = Color(1, 0.96, 0.9).lerp(tint, 0.12)
				root.add_child(lamp)
				lamps.append(lamp)
	# the doors: two panels meeting in the middle that slide apart into the wall
	var out_doors: Array = []
	for d in dl:
		var w: float = float(d["hi"]) - float(d["lo"])
		var h2: float = float(d["h"]) - 2.0
		var mid: float = (float(d["lo"]) + float(d["hi"])) * 0.5
		var base: float = d["base"]
		var panels: Array = []
		for sgn in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(WALL * 0.8, h2, w * 0.5) if d["axis"] == "x" else Vector3(w * 0.5, h2, WALL * 0.8)
			mi.mesh = bm
			mi.material_override = door_m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var stripe := MeshInstance3D.new()   # green: it will open; red: locked / sealed (the space code sets it)
			var sb := BoxMesh.new()
			sb.size = Vector3(WALL, 2.0, w * 0.5 - 2.0) if d["axis"] == "x" else Vector3(w * 0.5 - 2.0, 2.0, WALL)
			stripe.mesh = sb
			stripe.position = Vector3(0, h2 * 0.1, 0)
			stripe.material_override = ShipFactory.mat(Color(0.3, 1.0, 0.45), true)
			stripe.name = "Stripe"
			mi.add_child(stripe)
			var closed_at := Vector3(float(d["at"]), base + h2 * 0.5, mid + sgn * w * 0.25) if d["axis"] == "x" else Vector3(mid + sgn * w * 0.25, base + h2 * 0.5, float(d["at"]))
			mi.position = closed_at
			mi.set_meta("closed_at", closed_at)
			mi.set_meta("open_off", (Vector3(0, 0, sgn * w * 0.5) if d["axis"] == "x" else Vector3(sgn * w * 0.5, 0, 0)))
			root.add_child(mi)
			panels.append(mi)
		var a := Vector3(float(d["at"]) - WALL * 0.5, base, float(d["lo"])) if d["axis"] == "x" else Vector3(float(d["lo"]), base, float(d["at"]) - WALL * 0.5)
		var b := Vector3(float(d["at"]) + WALL * 0.5, base + h2, float(d["hi"])) if d["axis"] == "x" else Vector3(float(d["hi"]), base + h2, float(d["at"]) + WALL * 0.5)
		d["panels"] = panels
		d["box"] = [root, AABB(a, b - a)]
		d["center"] = Vector3(float(d["at"]), base, mid) if d["axis"] == "x" else Vector3(mid, base, float(d["at"]))
		d["open"] = 0.0
		d["locked"] = is_door(d, ESCAPE_DOOR)
		d["sealed"] = false
		out_doors.append(d)
	# the reactor's pit ring
	for a in 16:
		var ang := TAU * float(a) / 16.0
		var c := CORE_AT + Vector3(cos(ang), 0, sin(ang)) * (CORE_SHIELD_R + 14.0)
		_slab(root, c + Vector3(-4, 0, -4), c + Vector3(4, 14, 4), wall_m, null)
	# the way out, lit on the deck once the reactor blows (hidden until then)
	var path := Node3D.new()
	path.name = "ExitPath"
	path.visible = false
	root.add_child(path)
	var green := ShipFactory.mat(Color(0.3, 1.0, 0.45), true)
	var prev := CORE_AT
	for k in ROUTE_OUT.slice(1):
		var r: Array = ROOMS[k]["r"]
		var c := Vector3((float(r[0]) + float(r[1])) * 0.5, 0, (float(r[2]) + float(r[3])) * 0.5)
		var n := int(prev.distance_to(c) / 16.0)
		for i in n:
			var p := prev.lerp(c, (i + 0.5) / float(maxi(n, 1)))
			p.y = floor_at(p) + 0.3
			var bm := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(5, 0.4, 5)
			bm.mesh = bx
			bm.material_override = green
			bm.position = p
			path.add_child(bm)
		prev = c
	return {"boxes": boxes, "doors": out_doors, "alarm": lamps, "path": path}

## One wall run (from a to b along the side). Tunnels lean: a vertical foot, a panel leaning OUT to the widest point,
## then one leaning back IN to the roof (a hexagon). The solid part is the floor-width wall (mechs walk on the deck).
static func _wall(root: Node3D, boxes: Array, side: Array, a: float, b: float, ylo: float, ytop: float, h: float, hex: bool, m: Material) -> void:
	var axis: String = side[0]
	var at: float = side[1]
	var out: float = side[4]   # which way is outward
	var lo := Vector3(at - WALL * 0.5, ylo, a) if axis == "x" else Vector3(a, ylo, at - WALL * 0.5)
	var hi := Vector3(at + WALL * 0.5, ytop, b) if axis == "x" else Vector3(b, ytop, at + WALL * 0.5)
	if not hex:
		boxes.append(_slab(root, lo, hi, m, root))
		return
	# a tunnel: the solid wall stays at the deck's width (mechs walk on the deck), but you see a vertical foot, then a
	# panel leaning OUT to the widest point and one leaning back IN to the roof: a hexagon
	boxes.append([root, AABB(Vector3(minf(lo.x, hi.x), minf(lo.y, hi.y), minf(lo.z, hi.z)), (hi - lo).abs())])
	var foot := h * 0.22
	var bulge := h * 0.28
	var rise1 := h * 0.3
	var rise2 := (ytop - ylo) - foot - rise1
	_slab(root, lo, Vector3(hi.x, ylo + foot, hi.z), m, null)
	var ln := b - a
	for seg in [[foot, rise1, bulge, 0.0], [foot + rise1, rise2, -bulge, bulge]]:
		var y0: float = ylo + float(seg[0])
		var dy: float = seg[1]
		var dx: float = seg[2]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var slant := sqrt(dy * dy + dx * dx)
		bm.size = Vector3(WALL, slant, ln) if axis == "x" else Vector3(ln, slant, WALL)
		mi.mesh = bm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var off: float = float(seg[3]) + dx * 0.5
		var ang := atan2(dx * out, dy)
		if axis == "x":
			mi.position = Vector3(at + out * off, y0 + dy * 0.5, (a + b) * 0.5)
			mi.rotation = Vector3(0, 0, -ang)
		else:
			mi.position = Vector3((a + b) * 0.5, y0 + dy * 0.5, at + out * off)
			mi.rotation = Vector3(ang, 0, 0)
		root.add_child(mi)

## A room's deck (dy = -WALL) or roof (dy = h): a flat slab, or a tilted one on a ramp.
static func _ramp(root: Node3D, k: String, dy: float, m: Material) -> void:
	var R: Dictionary = ROOMS[k]
	var r: Array = R["r"]
	var ya: float = float(R["y"][0])
	var yb: float = float(R["y"][1])
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var lx: float = float(r[1]) - float(r[0])
	var lz: float = float(r[3]) - float(r[2])
	var rise: float = yb - ya
	if R["axis"] == "x":
		bm.size = Vector3(sqrt(lx * lx + rise * rise), WALL, lz)
		mi.rotation = Vector3(0, 0, atan2(rise, lx))
	else:
		bm.size = Vector3(lx, WALL, sqrt(lz * lz + rise * rise))
		mi.rotation = Vector3(-atan2(rise, lz), 0, 0)
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var roof: bool = dy > 0.0
	mi.position = Vector3((float(r[0]) + float(r[1])) * 0.5, (ya + yb) * 0.5 + (dy + WALL * 0.5 if roof else -WALL * 0.5), (float(r[2]) + float(r[3])) * 0.5)
	root.add_child(mi)

## The glow line down the middle of a room's deck (following a ramp's slope).
static func _ramp_strip(root: Node3D, k: String, m: Material) -> void:
	var R: Dictionary = ROOMS[k]
	var r: Array = R["r"]
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var lx: float = float(r[1]) - float(r[0]) - 8.0
	var lz: float = float(r[3]) - float(r[2]) - 8.0
	var rise: float = float(R["y"][1]) - float(R["y"][0])
	if R["axis"] == "x" and lx >= lz:
		bm.size = Vector3(sqrt(lx * lx + rise * rise), 0.2, 1.6)
		mi.rotation = Vector3(0, 0, atan2(rise, lx))
	elif R["axis"] == "z" and lz >= lx:
		bm.size = Vector3(1.6, 0.2, sqrt(lz * lz + rise * rise))
		mi.rotation = Vector3(-atan2(rise, lz), 0, 0)
	else:
		bm.size = Vector3(lx, 0.2, 1.6) if lx >= lz else Vector3(1.6, 0.2, lz)
	mi.mesh = bm
	mi.material_override = m
	mi.position = Vector3((float(r[0]) + float(r[1])) * 0.5, (float(R["y"][0]) + float(R["y"][1])) * 0.5 + 0.15, (float(r[2]) + float(r[3])) * 0.5)
	root.add_child(mi)

## One block of the ship: a mesh, and a solid box when `holder` is given.
static func _slab(root: Node3D, a: Vector3, b: Vector3, m: Material, holder) -> Array:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = (b - a).abs()
	mi.mesh = bm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = (a + b) * 0.5
	root.add_child(mi)
	if holder == null: return []
	return [holder, AABB(Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)), (b - a).abs())]
