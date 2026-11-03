class_name Boarding
extends RefCounted
## v11.70 (owner: "that mini game was whack: I want to be a mech in ground mode, moving through the inside of the ship
## like Armored Core, fighting other mechs, through doors and passageways to the core; blow the core, find ANOTHER exit
## out within 90 seconds before it blows; out I fly, big explosion, 20 ships waiting, Command congratulates me, destroy
## all threats, get paid").
##
## The inside of a battleship as a small maze of rooms and corridors (the planet-surface code with a flat deck, walls
## and roofs). Every opening between two rooms is a sliding DOOR that opens as you walk up to it. Each room has its own
## guard mechs, who come at you when you walk in. The route: the ENTRY BAY, a corridor to the GUARD ROOM, then the WEST
## or EAST way round (armory / barracks and their corridors) into the REACTOR HALL. The core's shield is up while the
## hall's guards stand. Blow the core and the way you came SEALS: the hall's far door opens onto the corridor to the AFT
## LAUNCH BAY, the only way out, 90 seconds before the ship goes up.
##
## Units: metres. +X starboard, -Z deeper in (you come in heading -Z). The deck is y = 0.

static var sunk := {}   # system id -> true: you blew that battleship's reactor (this session: it is gone)

# name: [x0, x1, z0, z1, height, label, guards]
const ROOMS := {
	"bay": [-45.0, 45.0, -70.0, 0.0, 44.0, "ENTRY BAY", 0],
	"c1": [-14.0, 14.0, -190.0, -70.0, 30.0, "ACCESS CORRIDOR", 0],
	"guard": [-60.0, 60.0, -260.0, -190.0, 40.0, "GUARD ROOM", 2],
	"c2w": [-200.0, -60.0, -240.0, -212.0, 30.0, "WEST PASSAGE", 0],
	"c2e": [60.0, 200.0, -240.0, -212.0, 30.0, "EAST PASSAGE", 0],
	"armory": [-260.0, -200.0, -300.0, -160.0, 40.0, "ARMORY", 2],
	"barracks": [200.0, 260.0, -300.0, -160.0, 40.0, "BARRACKS", 2],
	"c3w": [-244.0, -216.0, -440.0, -300.0, 30.0, "WEST SPINE", 0],
	"c3e": [216.0, 244.0, -440.0, -300.0, 30.0, "EAST SPINE", 0],
	"hall": [-260.0, 260.0, -620.0, -440.0, 72.0, "REACTOR HALL", 4],
	"c4": [-14.0, 14.0, -760.0, -620.0, 30.0, "AFT CORRIDOR", 0],
	"exit": [-50.0, 50.0, -840.0, -760.0, 44.0, "AFT LAUNCH BAY", 2],
}
const WALL := 4.0                         # wall thickness
const START_AT := Vector3(0, 0, -30.0)    # where you land inside
const CORE_AT := Vector3(0, 0, -530.0)    # the reactor core
const EXIT_Z := -834.0                    # past this, at the aft launch bay's open end: out
const SEAL_DOOR := ["c1", "guard"]        # slams shut when the core blows (the way you came)
const ESCAPE_DOOR := ["hall", "c4"]       # opens when the core blows (the way out)
const DOOR_OPEN_AT := 70.0                # m: a door slides open when you are this close
const ROUTE := ["bay", "c1", "guard", "c2w", "armory", "c3w", "hall", "c4", "exit"]   # (tests / the escape lights)

static func rect(k: String) -> Array: return ROOMS[k]

## The rooms' floor rectangles joined (for keeping the mechs inside): [x0, x1, z0, z1].
static func inside(p: Vector3, pad := 0.0) -> bool:
	return room_at(p, pad) != ""

static func room_at(p: Vector3, pad := 0.0) -> String:
	for k in ROOMS:
		var r: Array = ROOMS[k]
		if p.x > float(r[0]) + pad and p.x < float(r[1]) - pad and p.z > float(r[2]) + pad and p.z < float(r[3]) - pad: return k
	return ""

## Clamp a point onto the nearest room floor (a mech that walks into a wall stays in).
static func keep_in(p: Vector3, pad := 10.0) -> Vector3:
	if inside(p, pad): return p
	var best := p
	var bd := INF
	for k in ROOMS:
		var r: Array = ROOMS[k]
		var q := Vector3(clampf(p.x, minf(float(r[0]) + pad, (float(r[0]) + float(r[1])) * 0.5), maxf(float(r[1]) - pad, (float(r[0]) + float(r[1])) * 0.5)), p.y,
			clampf(p.z, minf(float(r[2]) + pad, (float(r[2]) + float(r[3])) * 0.5), maxf(float(r[3]) - pad, (float(r[2]) + float(r[3])) * 0.5)))
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = q
	return best

## The roof over a point (the room it is in), or the lowest roof.
static func roof_at(p: Vector3) -> float:
	var k := room_at(p)
	return float(ROOMS[k][4]) if k != "" else 30.0

## Where two rooms touch: {axis "x" (a wall of constant x) / "z", at, lo, hi} (the shared stretch), or {} if they don't.
static func joint(a: String, b: String) -> Dictionary:
	var A: Array = ROOMS[a]
	var B: Array = ROOMS[b]
	for pair in [[A[1], B[0]], [A[0], B[1]]]:   # side by side across x
		if absf(float(pair[0]) - float(pair[1])) < 0.5:
			var lo := maxf(float(A[2]), float(B[2]))
			var hi := minf(float(A[3]), float(B[3]))
			if hi - lo > 4.0: return {"axis": "x", "at": float(pair[0]), "lo": lo, "hi": hi, "h": minf(float(A[4]), float(B[4]))}
	for pair in [[A[3], B[2]], [A[2], B[3]]]:   # end to end across z
		if absf(float(pair[0]) - float(pair[1])) < 0.5:
			var lo := maxf(float(A[0]), float(B[0]))
			var hi := minf(float(A[1]), float(B[1]))
			if hi - lo > 4.0: return {"axis": "z", "at": float(pair[0]), "lo": lo, "hi": hi, "h": minf(float(A[4]), float(B[4]))}
	return {}

## Every door: one per pair of rooms that touch.
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

## Build the decks, walls, roofs, lights and the doors under `root`. Returns {"boxes": the solid walls [[holder, AABB]],
## "doors": [{rooms, axis, at, lo, hi, h, panels, box, open, locked, sealed}], "alarm": the lamps, "path": the exit lights}.
static func build(root: Node3D, tint: Color) -> Dictionary:
	var boxes: Array = []
	var hull := ShipFactory.mat(Color(0.24, 0.25, 0.28), false, 0.55)
	var deck := ShipFactory.mat(Color(0.16, 0.17, 0.19), false, 0.7)
	var trim := ShipFactory.mat(tint.lerp(Color(1, 1, 1), 0.15), true)
	var door_m := ShipFactory.mat(Color(0.55, 0.52, 0.45), false, 0.4)
	var lamps: Array = []
	var dl := doors()
	for k in ROOMS:
		var r: Array = ROOMS[k]
		var x0: float = r[0]
		var x1: float = r[1]
		var z0: float = r[2]
		var z1: float = r[3]
		var h: float = r[4]
		_slab(root, Vector3(x0, -WALL, z0), Vector3(x1, 0, z1), deck, null)   # deck
		_slab(root, Vector3(x0, h, z0), Vector3(x1, h + WALL, z1), hull, null)  # roof
		# four walls, each with the openings where another room joins (a door goes in each)
		for side in [["x", x0, z0, z1], ["x", x1, z0, z1], ["z", z0, x0, x1], ["z", z1, x0, x1]]:
			var cuts: Array = []
			for d in dl:
				if not (d["rooms"] as Array).has(k) or d["axis"] != side[0] or absf(float(d["at"]) - float(side[1])) > 0.5: continue
				cuts.append([float(d["lo"]), float(d["hi"])])
			if k == "bay" and side[0] == "z" and is_equal_approx(float(side[1]), z1): continue   # the bay's open side (you came in here)
			if k == "exit" and side[0] == "z" and is_equal_approx(float(side[1]), z0): continue  # the launch bay's open end (the way out)
			cuts.sort_custom(func(a, b): return a[0] < b[0])
			var at := float(side[2])
			for c in cuts + [[float(side[3]), float(side[3])]]:
				if float(c[0]) - at > 0.5:
					if side[0] == "x": boxes.append(_slab(root, Vector3(float(side[1]) - WALL * 0.5, 0, at), Vector3(float(side[1]) + WALL * 0.5, h, float(c[0])), hull, root))
					else: boxes.append(_slab(root, Vector3(at, 0, float(side[1]) - WALL * 0.5), Vector3(float(c[0]), h, float(side[1]) + WALL * 0.5), hull, root))
				at = maxf(at, float(c[1]))
		# ribs and light strips along the walls; a glow line down the middle of the deck
		var long_z: bool = (z1 - z0) >= (x1 - x0)
		var step := 20.0
		if long_z:
			var z := z1 - 10.0
			while z > z0 + 5.0:
				for sx in [x0 + 0.6, x1 - 0.6]:
					_slab(root, Vector3(sx - 0.6, 0, z - 1.5), Vector3(sx + 0.6, h, z + 1.5), hull, null)
					_slab(root, Vector3(sx - 0.8, h * 0.62, z - 4.0), Vector3(sx + 0.8, h * 0.62 + 1.2, z + 4.0), trim, null)
				z -= step
			_slab(root, Vector3((x0 + x1) * 0.5 - 0.8, 0.02, z0 + 2.0), Vector3((x0 + x1) * 0.5 + 0.8, 0.12, z1 - 2.0), trim, null)
		else:
			var x := x0 + 10.0
			while x < x1 - 5.0:
				for sz in [z0 + 0.6, z1 - 0.6]:
					_slab(root, Vector3(x - 1.5, 0, sz - 0.6), Vector3(x + 1.5, h, sz + 0.6), hull, null)
					_slab(root, Vector3(x - 4.0, h * 0.62, sz - 0.8), Vector3(x + 4.0, h * 0.62 + 1.2, sz + 0.8), trim, null)
				x += step
			_slab(root, Vector3(x0 + 2.0, 0.02, (z0 + z1) * 0.5 - 0.8), Vector3(x1 - 2.0, 0.12, (z0 + z1) * 0.5 + 0.8), trim, null)
		# ceiling lamps on a 60 m grid
		var lz := z1 - minf(25.0, (z1 - z0) * 0.5)
		while lz > z0:
			var lx := x0 + minf(30.0, (x1 - x0) * 0.5)
			while lx < x1:
				_slab(root, Vector3(lx - 5, h - 0.6, lz - 5), Vector3(lx + 5, h - 0.1, lz + 5), trim, null)
				var lamp := OmniLight3D.new()
				lamp.position = Vector3(lx, h - 5.0, lz)
				lamp.omni_range = 90.0
				lamp.light_energy = 1.6
				lamp.light_color = Color(1, 0.96, 0.9).lerp(tint, 0.15)
				root.add_child(lamp)
				lamps.append(lamp)
				lx += 60.0
			lz -= 60.0
	# the doors: two panels meeting in the middle that slide apart into the wall
	var out_doors: Array = []
	for d in dl:
		var w: float = float(d["hi"]) - float(d["lo"])
		var h2: float = float(d["h"]) - 2.0
		var mid: float = (float(d["lo"]) + float(d["hi"])) * 0.5
		var panels: Array = []
		for sgn in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(WALL * 0.8, h2, w * 0.5) if d["axis"] == "x" else Vector3(w * 0.5, h2, WALL * 0.8)
			mi.mesh = bm
			mi.material_override = door_m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var stripe := MeshInstance3D.new()   # a lit stripe across each panel (green open, red locked: the space code sets it)
			var sb := BoxMesh.new()
			sb.size = Vector3(WALL, 1.4, w * 0.5 - 1.0) if d["axis"] == "x" else Vector3(w * 0.5 - 1.0, 1.4, WALL)
			stripe.mesh = sb
			stripe.position = Vector3(0, h2 * 0.15, 0)
			stripe.material_override = ShipFactory.mat(Color(0.3, 1.0, 0.45), true)
			stripe.name = "Stripe"
			mi.add_child(stripe)
			var closed_at := Vector3(float(d["at"]), h2 * 0.5, mid + sgn * w * 0.25) if d["axis"] == "x" else Vector3(mid + sgn * w * 0.25, h2 * 0.5, float(d["at"]))
			mi.position = closed_at
			mi.set_meta("closed_at", closed_at)
			mi.set_meta("open_off", (Vector3(0, 0, sgn * w * 0.5) if d["axis"] == "x" else Vector3(sgn * w * 0.5, 0, 0)))
			root.add_child(mi)
			panels.append(mi)
		var a := Vector3(float(d["at"]) - WALL * 0.5, 0, float(d["lo"])) if d["axis"] == "x" else Vector3(float(d["lo"]), 0, float(d["at"]) - WALL * 0.5)
		var b := Vector3(float(d["at"]) + WALL * 0.5, h2, float(d["hi"])) if d["axis"] == "x" else Vector3(float(d["hi"]), h2, float(d["at"]) + WALL * 0.5)
		d["panels"] = panels
		d["box"] = [root, AABB(a, b - a)]
		d["center"] = Vector3(float(d["at"]), 0, mid) if d["axis"] == "x" else Vector3(mid, 0, float(d["at"]))
		d["open"] = 0.0
		d["locked"] = is_door(d, ESCAPE_DOOR)
		d["sealed"] = false
		out_doors.append(d)
	# the core's pit ring
	for a in 12:
		var ang := TAU * float(a) / 12.0
		var c := CORE_AT + Vector3(cos(ang), 0, sin(ang)) * 34.0
		_slab(root, c + Vector3(-3, 0, -3), c + Vector3(3, 10, 3), hull, null)
	# the way out, lit on the deck once the core blows (hidden until then): hall -> aft corridor -> launch bay
	var path := Node3D.new()
	path.name = "ExitPath"
	path.visible = false
	root.add_child(path)
	var green := ShipFactory.mat(Color(0.3, 1.0, 0.45), true)
	var z2 := CORE_AT.z - 40.0
	while z2 > EXIT_Z:
		_slab(path, Vector3(-3.0, 0.05, z2 - 5.0), Vector3(3.0, 0.25, z2), green, null)
		z2 -= 14.0
	return {"boxes": boxes, "doors": out_doors, "alarm": lamps, "path": path}

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
