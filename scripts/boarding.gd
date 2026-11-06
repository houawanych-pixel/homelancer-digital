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
const SHIP_ROOMS := {
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
const SHIP_START_AT := Vector3(-380, 0, 0)     # where you land inside (the port bay), facing +X
const SHIP_START_FACE := Vector3(1, 0, 0)
const SHIP_CORE_AT := Vector3(0, -100, 940)    # the reactor (its foot on the belly deck)
const SHIP_CORE_SHIELD_R := 60.0               # the shield bubble round it
const SHIP_BOSS_AT := Vector3(0, -100, 1010)
const SHIP_BRIDGE_MECH_AT := Vector3(-60, 40, -440)
const SHIP_EXIT_X := 440.0                     # past this, at the starboard bay's open side: out
const SHIP_ENTRY_X := -416.0                   # (the port bay's open side: you can't walk back out there)
const SHIP_SEAL_DOOR := ["r1", "reactor"]      # slams shut when the reactor blows (the way you came)
const SHIP_ESCAPE_DOOR := ["reactor", "r2"]    # opens when the reactor blows (the way out)
const DOOR_OPEN_AT := 110.0               # m: a door slides open when you are this close
const SHIP_ROUTE_IN := ["lbay", "t1", "muster", "t2", "cargo", "r1", "reactor"]
const SHIP_ROUTE_OUT := ["reactor", "r2", "t3", "fhold", "t4a", "t4r", "t4b", "sbay"]

## v11.96 (owner: Armored Core facilities under every planet's bases): the layout in use. The battleship is the default;
## Boarding.use(Boarding.facility(...)) swaps in a generated facility (same room schema), use_ship() puts it back.
static var ROOMS: Dictionary = SHIP_ROOMS
static var START_AT: Vector3 = SHIP_START_AT
static var START_FACE: Vector3 = SHIP_START_FACE
static var CORE_AT: Vector3 = SHIP_CORE_AT
static var CORE_SHIELD_R: float = SHIP_CORE_SHIELD_R
static var BOSS_AT: Vector3 = SHIP_BOSS_AT
static var BRIDGE_MECH_AT: Vector3 = SHIP_BRIDGE_MECH_AT
static var EXIT_X: float = SHIP_EXIT_X
static var ENTRY_X: float = SHIP_ENTRY_X
static var SEAL_DOOR: Array = SHIP_SEAL_DOOR
static var ESCAPE_DOOR: Array = SHIP_ESCAPE_DOOR
static var ROUTE_IN: Array = SHIP_ROUTE_IN
static var ROUTE_OUT: Array = SHIP_ROUTE_OUT
static var KIND := "ship"   # "ship" | "facility"
static var INFO := {}       # a facility's name, depth, difficulty

static func use_ship() -> void:
	ROOMS = SHIP_ROOMS
	START_AT = SHIP_START_AT
	START_FACE = SHIP_START_FACE
	CORE_AT = SHIP_CORE_AT
	CORE_SHIELD_R = SHIP_CORE_SHIELD_R
	BOSS_AT = SHIP_BOSS_AT
	BRIDGE_MECH_AT = SHIP_BRIDGE_MECH_AT
	EXIT_X = SHIP_EXIT_X
	ENTRY_X = SHIP_ENTRY_X
	SEAL_DOOR = SHIP_SEAL_DOOR
	ESCAPE_DOOR = SHIP_ESCAPE_DOOR
	ROUTE_IN = SHIP_ROUTE_IN
	ROUTE_OUT = SHIP_ROUTE_OUT
	KIND = "ship"
	INFO = {}

static var classic := false   # v12.18: the route test's hand-made battleship (its walkthrough knows the coordinates)

static func use(L: Dictionary) -> void:
	ROOMS = L["rooms"]
	START_AT = L["start"]
	START_FACE = Vector3(1, 0, 0)
	CORE_AT = L["core"]
	CORE_SHIELD_R = 60.0
	BOSS_AT = L["boss"]
	BRIDGE_MECH_AT = L.get("bridge_mech", Vector3(1e6, 0, 1e6))   # (no bridge in a facility)
	EXIT_X = L["exit_x"]
	ENTRY_X = L["entry_x"]
	SEAL_DOOR = L["seal"]
	ESCAPE_DOOR = L["escape"]
	ROUTE_IN = L["route_in"]
	ROUTE_OUT = L["route_out"]
	KIND = str(L.get("kind", "facility"))
	INFO = L["info"]

## v11.96 (owner: "every planet has bases ... Armored Core tunnels and missions, 2 at the minimum, 3 or 4 at most; the
## harder they are, the deeper and bigger they are and the more enemies; basic grey-box rooms, not square hallways:
## hexagon and pentagon tunnels, rooms that aren't just squares; a maze that draws you deeper"). A facility on a grid
## of 360 m cells: you come in at the west ENTRY BAY, wind east and down level by level through halls of different
## shapes (octagon, pillar hall, crossroads, split-level, ring round a pit) joined by hex or pentagon tunnels that ramp
## down, with dead-end side wings, to the REACTOR. Blow it: the way you came seals and the escape route opens, on east
## and back up to the EXIT SHAFT. Difficulty 1-4: deeper (more rooms and levels), bigger halls, more guards.
const CELL := 360.0
const SHAPES := ["oct", "pillars", "cross", "split", "ring", "hex"]
static func facility(seed_key: String, difficulty: int, name := "Facility") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("facility:" + seed_key)
	var d := clampi(difficulty, 1, 4)
	var main_len := 3 + d * 2            # halls before the reactor: 5, 7, 9, 11
	var out_len := 2 + d                 # halls on the escape route
	var drop := 24.0 + d * 4.0           # m down per level
	var rooms := {}
	var cell_room := {}                  # Vector2i -> room key
	var level := {}                      # room key -> floor height
	var half := {}                       # room key -> [hx, hz]
	var put := func(k: String, c: Vector2i, hx: float, hz: float, y: float, label: String, guards: int, shape: String) -> void:
		var cx := float(c.x) * CELL
		var cz := float(c.y) * CELL
		rooms[k] = {"r": [cx - hx, cx + hx, cz - hz, cz + hz], "y": [y, y], "axis": "x", "h": 70.0 + d * 6.0, "label": label, "guards": guards, "hex": false, "shape": shape}
		cell_room[c] = k
		level[k] = y
		half[k] = [hx, hz]
	var tunnel := func(a: String, ca: Vector2i, b: String, cb: Vector2i, n: int) -> void:
		var tk := "t%d" % n
		var w := 34.0
		var xsec: String = ["hex", "pent"][rng.randi() % 2]
		var ra: Array = rooms[a]["r"]
		var rb: Array = rooms[b]["r"]
		if ca.y == cb.y:   # east-west
			var e := 1 if cb.x > ca.x else -1
			var x0: float = float(ra[1]) if e > 0 else float(rb[1])
			var x1: float = float(rb[0]) if e > 0 else float(ra[0])
			var cz := float(ca.y) * CELL
			var ys := [level[a], level[b]] if e > 0 else [level[b], level[a]]
			rooms[tk] = {"r": [x0, x1, cz - w, cz + w], "y": ys, "axis": "x", "h": 50.0, "label": "TUNNEL", "guards": 0, "hex": true, "xsec": xsec}
		else:              # north-south
			var e2 := 1 if cb.y > ca.y else -1
			var z0: float = float(ra[3]) if e2 > 0 else float(rb[3])
			var z1: float = float(rb[2]) if e2 > 0 else float(ra[2])
			var cx := float(ca.x) * CELL
			var ys2 := [level[a], level[b]] if e2 > 0 else [level[b], level[a]]
			rooms[tk] = {"r": [cx - w, cx + w, z0, z1], "y": ys2, "axis": "z", "h": 50.0, "label": "TUNNEL", "guards": 0, "hex": true, "xsec": xsec}
	var names := ["GATEHALL", "MUSTER", "FOUNDRY", "BARRACKS", "SUMP", "ARMORY", "DEPOT", "CONTROL", "PUMP HALL", "VAULT", "SILO", "WORKS", "GALLERY", "CISTERN"]
	# the entry bay (west, open side west)
	var c := Vector2i(0, 0)
	put.call("lbay", c, 90.0, 80.0, 0.0, "ENTRY BAY", 0, "rect")
	var route_in: Array = ["lbay"]
	var n := 0
	var y := 0.0
	var prev := "lbay"
	var pc := c
	var wander := func(from: Vector2i, east_bias: float) -> Vector2i:
		var opts: Array = []
		for dv in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0)]:
			var q: Vector2i = from + dv
			if cell_room.has(q) or q.x < 1 or absi(q.y) > 3: continue
			opts.append(q)
		if opts.is_empty(): return Vector2i(-999, 0)
		if rng.randf() < east_bias:
			for q in opts: if q.x > from.x: return q
		return opts[rng.randi() % opts.size()]
	for i in main_len:
		var q: Vector2i = wander.call(pc, 0.45)
		if q.x == -999: q = Vector2i(pc.x + 1, pc.y)
		if i % 2 == 1: y -= drop
		var hk := "h%d" % i
		var big := 1.0 + d * 0.12
		put.call(hk, q, minf(rng.randf_range(80.0, 125.0) * big, 140.0), minf(rng.randf_range(80.0, 125.0) * big, 140.0), y, names[i % names.size()], 1 + (d + i) / 3, SHAPES[rng.randi() % SHAPES.size()])
		n += 1
		tunnel.call(prev, pc, hk, q, n)
		route_in.append("t%d" % n)
		route_in.append(hk)
		# a dead-end side wing now and then (guards, and a maze to get lost in)
		if rng.randf() < 0.35 + d * 0.08:
			var sq: Vector2i = q + [Vector2i(0, 1), Vector2i(0, -1)][rng.randi() % 2]
			if not cell_room.has(sq) and absi(sq.y) <= 3:
				var sk := "s%d" % i
				put.call(sk, sq, rng.randf_range(70.0, 100.0), rng.randf_range(70.0, 100.0), y, "SIDE WING", 1 + d / 2, SHAPES[rng.randi() % SHAPES.size()])
				n += 1
				tunnel.call(hk, q, sk, sq, n)
		prev = hk
		pc = q
	# the reactor
	var rq: Vector2i = Vector2i(pc.x + 1, pc.y)
	y -= drop
	put.call("reactor", rq, 170.0, 150.0, y, "REACTOR HALL", d + 1, "ring")
	n += 1
	tunnel.call(prev, pc, "reactor", rq, n)
	var seal: Array = ["t%d" % n, "reactor"]
	route_in.append("t%d" % n)
	route_in.append("reactor")
	# the escape: on east and back up, to the exit shaft
	var route_out: Array = ["reactor"]
	prev = "reactor"
	pc = rq
	var esc: Array = []
	for i in out_len:
		var q2 := Vector2i(pc.x + 1, pc.y)   # (straight steps only: on east, or now and then a turn up or down)
		var dy: int = [-1, 0, 1][rng.randi() % 3] if i > 0 else 0
		if dy != 0 and absi(pc.y + dy) <= 3 and not cell_room.has(Vector2i(pc.x, pc.y + dy)): q2 = Vector2i(pc.x, pc.y + dy)
		y += drop * 0.7
		var ek := "fhold" if i == out_len / 2 else "e%d" % i
		put.call(ek, q2, rng.randf_range(80.0, 110.0), rng.randf_range(80.0, 110.0), y, "ESCAPE HALL" if ek != "fhold" else "COLLAPSING HALL", 2 + d / 2 if ek == "fhold" else 0, SHAPES[rng.randi() % SHAPES.size()])
		n += 1
		tunnel.call(prev, pc, ek, q2, n)
		if i == 0: esc = [prev, "t%d" % n]
		route_out.append("t%d" % n)
		route_out.append(ek)
		prev = ek
		pc = q2
	var xq := Vector2i(pc.x + 1, pc.y)
	put.call("sbay", xq, 90.0, 80.0, 0.0, "EXIT SHAFT", 0, "rect")
	n += 1
	tunnel.call(prev, pc, "sbay", xq, n)
	route_out.append("t%d" % n)
	route_out.append("sbay")
	var lb: Array = rooms["lbay"]["r"]
	var sb: Array = rooms["sbay"]["r"]
	var rr: Array = rooms["reactor"]["r"]
	var core := Vector3((float(rr[0]) + float(rr[1])) * 0.5, y + 0.0, (float(rr[2]) + float(rr[3])) * 0.5)
	core.y = level["reactor"]
	return {"rooms": rooms, "start": Vector3(float(lb[0]) + 40.0, 0.0, (float(lb[2]) + float(lb[3])) * 0.5), "core": core,
		"boss": core + Vector3(0, 0, 100.0), "exit_x": float(sb[1]) - 8.0, "entry_x": float(lb[0]) + 4.0, "seal": seal, "escape": esc,
		"route_in": route_in, "route_out": route_out,
		"info": {"name": name, "difficulty": d, "halls": main_len, "levels": int(round(-level["reactor"] / drop)), "rooms": rooms.size()}}

## v12.18 (owner: enemy battleships and stations as dungeons "like this", with deck-plan pictures for reference): a
## generated deck plan, different for every ship or station (seeded by its name), on the same 360 m grid and room schema
## as the facilities.
##  SHIP: a long hull, stern (west) to bow (east). You come in at the AFT HANGAR and work forward along the spine: big
##  halls (engineering, crew deck, mess, CIC, cargo) each with MIRRORED wings to port and starboard (barracks and
##  quarters, armory and weapons locker, med bay and cryo, gunnery and missile bay); the BRIDGE sits up a ramp off one
##  wing (its mech, bounty or hostage); the MAIN REACTOR mid-ship. Blow it and run on forward to the BOW LAUNCH BAY.
##  STATION: a hub and a ring. In at the WEST DOCK, along the west spoke to the ring, round the ring (rooms all round it,
##  pods off the outside), into the CORE at the centre: the reactor. Out the east side of the ring, along the east spoke,
##  to the EAST DOCK. Modules hang off the north and south of the ring.
##  Difficulty 1-4: longer hulls / more modules, bigger halls, more guards.
static func deckplan(seed_key: String, kind: String, difficulty: int, name := "Ship") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("deck:%s:%s" % [kind, seed_key])
	var d := clampi(difficulty, 1, 4)
	var rooms := {}
	var cell_room := {}
	var level := {}
	var nt := [0]
	var put := func(k: String, c: Vector2i, hx: float, hz: float, y: float, label: String, guards: int, shape: String, hh := 0.0) -> void:
		var cx := float(c.x) * CELL
		var cz := float(c.y) * CELL
		rooms[k] = {"r": [cx - hx, cx + hx, cz - hz, cz + hz], "y": [y, y], "axis": "x", "h": (hh if hh > 0.0 else 70.0 + d * 6.0), "label": label, "guards": guards, "hex": false, "shape": shape}
		cell_room[c] = k
		level[k] = y
	var cell_of := {}
	var link := func(a: String, b: String) -> String:   # a tunnel between two rooms in neighbouring cells; returns its key
		nt[0] += 1
		var tk := "t%d" % nt[0]
		var w := 34.0
		var xsec: String = ["hex", "pent"][rng.randi() % 2]
		var ra: Array = rooms[a]["r"]
		var rb: Array = rooms[b]["r"]
		var ca: Vector2i = cell_of[a]
		var cb: Vector2i = cell_of[b]
		if ca.y == cb.y:
			var e := 1 if cb.x > ca.x else -1
			var x0: float = float(ra[1]) if e > 0 else float(rb[1])
			var x1: float = float(rb[0]) if e > 0 else float(ra[0])
			var cz := float(ca.y) * CELL
			rooms[tk] = {"r": [x0, x1, cz - w, cz + w], "y": [level[a], level[b]] if e > 0 else [level[b], level[a]], "axis": "x", "h": 50.0, "label": "CORRIDOR", "guards": 0, "hex": true, "xsec": xsec}
		else:
			var e2 := 1 if cb.y > ca.y else -1
			var z0: float = float(ra[3]) if e2 > 0 else float(rb[3])
			var z1: float = float(rb[2]) if e2 > 0 else float(ra[2])
			var cx := float(ca.x) * CELL
			rooms[tk] = {"r": [cx - w, cx + w, z0, z1], "y": [level[a], level[b]] if e2 > 0 else [level[b], level[a]], "axis": "z", "h": 50.0, "label": "CORRIDOR", "guards": 0, "hex": true, "xsec": xsec}
		return tk
	var room := func(k: String, c: Vector2i, hx: float, hz: float, y: float, label: String, guards: int, shape: String, hh := 0.0) -> void:
		put.call(k, c, hx, hz, y, label, guards, shape, hh)
		cell_of[k] = c
	var route_in: Array = []
	var route_out: Array = []
	var seal: Array = []
	var esc: Array = []
	var bridge_at := Vector3(1e6, 0, 1e6)
	var big := 1.0 + d * 0.1
	if kind == "ship":
		var spine := ["ENGINEERING", "CREW DECK", "MESS HALL", "COMMAND CIC", "CARGO DECK", "MACHINE SHOP", "COMMS CENTRE"]
		var pairs := [["BARRACKS", "CREW QUARTERS"], ["ARMORY", "WEAPONS LOCKER"], ["MED BAY", "CRYO PODS"], ["GUNNERY", "MISSILE BAY"],
			["GALLEY", "MESS"], ["CARGO BAY 1", "CARGO BAY 2"], ["REACTOR CONTROL", "ENGINE ROOM"], ["WORKSHOP", "STORAGE"]]
		var n_spine := 2 + d                     # spine halls before the reactor: 3-6
		room.call("lbay", Vector2i(0, 0), 95.0, 85.0, 0.0, "AFT HANGAR", 0, "rect", 80.0)
		route_in.append("lbay")
		var prev := "lbay"
		var bridge_hall := 1 + rng.randi() % maxi(1, n_spine - 1)
		for i in n_spine:
			var hk := "muster" if i == 0 else "h%d" % i
			var c := Vector2i(i + 1, 0)
			room.call(hk, c, minf(rng.randf_range(100.0, 130.0) * big, 150.0), minf(rng.randf_range(110.0, 140.0) * big, 155.0), 0.0, spine[i % spine.size()], 2 + (d + i) / 3, ["oct", "cross", "pillars", "hex"][rng.randi() % 4])
			route_in.append(link.call(prev, hk))
			route_in.append(hk)
			if i == bridge_hall:   # the bridge, up a ramp off the port wing; a comms room mirrors it to starboard
				room.call("bridge", Vector2i(i + 1, -1), 110.0, 90.0, 30.0, "BRIDGE", 1, "split", 60.0)
				link.call(hk, "bridge")
				room.call("comms%d" % i, Vector2i(i + 1, 1), 110.0, 90.0, 0.0, "COMMUNICATION CENTRE", 2, "split")
				link.call(hk, "comms%d" % i)
				var br: Array = rooms["bridge"]["r"]
				bridge_at = Vector3((float(br[0]) + float(br[1])) * 0.5, 30.0, (float(br[2]) + float(br[3])) * 0.5 - 30.0)
			elif rng.randf() < 0.55 + d * 0.1:   # mirrored wings: the same shape and size both sides
				var pr: Array = pairs[rng.randi() % pairs.size()]
				var whx := rng.randf_range(70.0, 105.0)
				var whz := rng.randf_range(65.0, 95.0)
				var wsh: String = SHAPES[rng.randi() % SHAPES.size()]
				for sd in [-1, 1]:
					var wk := "w%d%s" % [i, "p" if sd < 0 else "s"]
					room.call(wk, Vector2i(i + 1, sd), whx, whz, 0.0, str(pr[0 if sd < 0 else 1]), 1 + d / 2, wsh)
					link.call(hk, wk)
			prev = hk
		var rc := Vector2i(n_spine + 1, 0)
		room.call("reactor", rc, 170.0, 150.0, -20.0, "MAIN REACTOR", d + 1, "ring", 110.0)
		var tr: String = link.call(prev, "reactor")
		seal = [tr, "reactor"]
		route_in.append(tr)
		route_in.append("reactor")
		# the escape: forward to the bow
		route_out.append("reactor")
		prev = "reactor"
		var fwd := ["FORWARD MISSILE BAY", "GUNNERY DECK", "FORWARD HOLD", "OBSERVATION"]
		var n_out := 1 + (d + 1) / 2
		for i in n_out:
			var ek := "fhold" if i == 0 else "e%d" % i
			room.call(ek, Vector2i(n_spine + 2 + i, 0), rng.randf_range(90.0, 120.0), rng.randf_range(90.0, 120.0), 0.0, fwd[i % fwd.size()], (2 + d / 2) if i == 0 else 0, ["oct", "hex", "pillars"][rng.randi() % 3])
			var te: String = link.call(prev, ek)
			if i == 0: esc = [prev, te]
			route_out.append(te)
			route_out.append(ek)
			if rng.randf() < 0.5:   # mirrored side rooms by the bow too
				for sd in [-1, 1]:
					var sk := "b%d%s" % [i, "p" if sd < 0 else "s"]
					room.call(sk, Vector2i(n_spine + 2 + i, sd), 80.0, 70.0, 0.0, ["ESCAPE PODS", "ESCAPE PODS"][0], 0, "rect")
					link.call(ek, sk)
			prev = ek
		room.call("sbay", Vector2i(n_spine + 2 + n_out, 0), 95.0, 85.0, 0.0, "BOW LAUNCH BAY", 0, "rect", 80.0)
		var tx: String = link.call(prev, "sbay")
		route_out.append(tx)
		route_out.append("sbay")
	else:
		# station: dock -> west spoke -> ring (round the north side) -> core; out: core -> east ring -> east spoke -> dock
		var cx := 3 + (1 if d >= 3 else 0)       # the hub's column (a longer west spoke on harder stations)
		room.call("lbay", Vector2i(0, 0), 95.0, 85.0, 0.0, "WEST DOCK", 0, "rect", 80.0)
		route_in.append("lbay")
		var prev := "lbay"
		for x in range(1, cx - 1):
			var sk := "muster" if x == 1 else "spw%d" % x
			room.call(sk, Vector2i(x, 0), rng.randf_range(90.0, 120.0) * big, rng.randf_range(80.0, 110.0), 0.0, ["SECURITY STATION", "CUSTOMS", "CARGO TRANSFER"][x % 3], 2 + d / 2, ["oct", "pillars", "cross"][rng.randi() % 3])
			route_in.append(link.call(prev, sk))
			route_in.append(sk)
			prev = sk
		var ring_names := {Vector2i(-1, 0): "WEST RING", Vector2i(-1, -1): "OFFICES", Vector2i(0, -1): "COMMAND RING", Vector2i(1, -1): "COMMUNICATIONS",
			Vector2i(1, 0): "EAST RING", Vector2i(1, 1): "MEDBAY", Vector2i(0, 1): "HYDROPONICS", Vector2i(-1, 1): "APARTMENTS"}
		var order := [Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1)]
		var rk := {}
		for o in order:
			var k := "ring_%d_%d" % [o.x + 1, o.y + 1]
			if o == Vector2i(1, 0): k = "fhold"
			rk[o] = k
			var corner: bool = o.x != 0 and o.y != 0
			room.call(k, Vector2i(cx + o.x, o.y), 105.0 if corner else 120.0, 105.0 if corner else 100.0, 0.0, str(ring_names[o]), (1 + d / 2) if o != Vector2i(1, 0) else (2 + d / 2), "hex" if corner else ["oct", "pillars"][rng.randi() % 2])
		var ring_t := {}
		for i in order.size():   # the ring itself
			ring_t[i] = link.call(rk[order[i]], rk[order[(i + 1) % order.size()]])
		route_in.append(link.call(prev, rk[Vector2i(-1, 0)]))
		route_in.append_array([rk[order[0]], ring_t[0], rk[order[1]], ring_t[1], rk[order[2]]])
		room.call("reactor", Vector2i(cx, 0), 150.0, 140.0, -20.0, "STATION CORE", d + 1, "ring", 110.0)
		var tr2: String = link.call(rk[Vector2i(0, -1)], "reactor")
		seal = [tr2, "reactor"]
		route_in.append(tr2)
		route_in.append("reactor")
		var te2: String = link.call("reactor", rk[Vector2i(1, 0)])
		esc = ["reactor", te2]
		route_out = ["reactor", te2, rk[Vector2i(1, 0)]]
		# modules off the north and south of the ring (and the bridge-like command deck up north)
		var mods_n := ["HIGH-END APARTMENTS", "CORPORATE ZONE", "OBSERVATORY"]
		var mods_s := ["COMMERCIAL DISTRICT", "WORKSHOPS", "POWER REGULATOR"]
		for sd in [-1, 1]:
			var depth := 1 + (1 if d >= 2 else 0) + (1 if d >= 4 else 0)
			var pk: String = rk[Vector2i(0, sd)]
			for j in depth:
				var mk := "mod%s%d" % ["n" if sd < 0 else "s", j]
				var lab: String = (mods_n if sd < 0 else mods_s)[j % 3]
				if sd < 0 and j == depth - 1:
					mk = "bridge"
					lab = "COMMAND DECK"
				room.call(mk, Vector2i(cx, sd * (2 + j)), rng.randf_range(95.0, 125.0), rng.randf_range(85.0, 110.0), 30.0 if mk == "bridge" else 0.0, lab, 1 + d / 2, SHAPES[rng.randi() % SHAPES.size()], 60.0 if mk == "bridge" else 0.0)
				link.call(pk, mk)
				pk = mk
			# pods off the ring's corners, outward
			for ox in [-1, 1]:
				if rng.randf() < 0.5 + d * 0.1:
					var pod := "pod%d%d" % [ox + 1, sd + 1]
					room.call(pod, Vector2i(cx + ox, sd * 2), 80.0, 75.0, 0.0, ["ESCAPE PODS", "DOCK " + ["A", "B", "C", "D"][rng.randi() % 4]][rng.randi() % 2], d / 2, "oct")
					link.call(rk[Vector2i(ox, sd)], pod)
		var br2: Array = rooms["bridge"]["r"]
		bridge_at = Vector3((float(br2[0]) + float(br2[1])) * 0.5, 30.0, (float(br2[2]) + float(br2[3])) * 0.5)
		prev = rk[Vector2i(1, 0)]
		for x in range(cx + 2, cx + 3 + d / 2):
			var ek2 := "spe%d" % x
			room.call(ek2, Vector2i(x, 0), rng.randf_range(85.0, 115.0), rng.randf_range(80.0, 100.0), 0.0, ["CARGO", "HANGAR DECK", "TRANSIT"][x % 3], 0, ["oct", "pillars", "cross"][rng.randi() % 3])
			var t3: String = link.call(prev, ek2)
			route_out.append(t3)
			route_out.append(ek2)
			prev = ek2
		var last_x := cx + 3 + d / 2
		room.call("sbay", Vector2i(last_x, 0), 95.0, 85.0, 0.0, "EAST DOCK", 0, "rect", 80.0)
		var t4: String = link.call(prev, "sbay")
		route_out.append(t4)
		route_out.append("sbay")
	var lb: Array = rooms["lbay"]["r"]
	var sb: Array = rooms["sbay"]["r"]
	var rr: Array = rooms["reactor"]["r"]
	var core := Vector3((float(rr[0]) + float(rr[1])) * 0.5, level["reactor"], (float(rr[2]) + float(rr[3])) * 0.5)
	return {"rooms": rooms, "start": Vector3(float(lb[0]) + 40.0, 0.0, (float(lb[2]) + float(lb[3])) * 0.5), "core": core,
		"boss": core + Vector3(0, 0, 90.0), "exit_x": float(sb[1]) - 8.0, "entry_x": float(lb[0]) + 4.0, "seal": seal, "escape": esc,
		"route_in": route_in, "route_out": route_out, "bridge_mech": bridge_at, "kind": kind,
		"info": {"name": name, "difficulty": d, "kind": kind, "rooms": rooms.size()}}

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
				if float(c[0]) - at > 0.5: _wall(root, boxes, side, at, float(c[0]), ylo, yhi + h, h, bool(R["hex"]) or str(R.get("shape", "")) == "hex", wall_m, str(R.get("xsec", "hex")), minf(x1 - x0, z1 - z0) * 0.5)
				at = maxf(at, float(c[1]))
		_shape(root, boxes, R, wall_m, trim)   # v11.96: pillars, corner blocks, a dividing ridge, a central column
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
## v11.96: what makes a facility hall more than a box (inside its rect; the solid parts are collision boxes too).
## oct: chamfered corners; pillars: four hexagonal columns; cross: four corner blocks leave a + of walkway (the doors are
## mid-wall); split: a waist-high ridge across the middle with a gap (cover); ring: a column in the middle to circle.
static func _shape(root: Node3D, boxes: Array, R: Dictionary, m: Material, trim: Material) -> void:
	var sh := str(R.get("shape", ""))
	if sh == "" or sh == "rect" or sh == "hex": return
	var r: Array = R["r"]
	var x0: float = r[0]
	var x1: float = r[1]
	var z0: float = r[2]
	var z1: float = r[3]
	var y: float = float(R["y"][0])
	var h: float = R["h"]
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var hx := (x1 - x0) * 0.5
	var hz := (z1 - z0) * 0.5
	match sh:
		"oct":
			var c := minf(hx, hz) * 0.42
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var mi := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(c * 1.42, h, WALL * 1.5)
					mi.mesh = bm
					mi.material_override = m
					mi.position = Vector3(cx + sx * (hx - c * 0.5), y + h * 0.5, cz + sz * (hz - c * 0.5))
					mi.rotation.y = PI * 0.25 * (1.0 if sx * sz > 0.0 else -1.0)
					root.add_child(mi)
					boxes.append([root, AABB(Vector3(cx + sx * hx - (c * 0.55 if sx > 0 else 0.0), y, cz + sz * hz - (c * 0.55 if sz > 0 else 0.0)), Vector3(c * 0.55, h, c * 0.55))])
		"pillars":
			for sx in [-0.5, 0.5]:
				for sz in [-0.5, 0.5]:
					var col := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.radial_segments = 6
					cm.top_radius = minf(hx, hz) * 0.12
					cm.bottom_radius = cm.top_radius * 1.25
					cm.height = h
					col.mesh = cm
					col.material_override = m
					col.position = Vector3(cx + sx * hx, y + h * 0.5, cz + sz * hz)
					root.add_child(col)
					var pr := cm.bottom_radius
					boxes.append([root, AABB(col.position - Vector3(pr * 0.85, h * 0.5, pr * 0.85), Vector3(pr * 1.7, h, pr * 1.7))])
		"cross":
			var bx := hx * 0.38
			var bz := hz * 0.38
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var a := Vector3(cx + sx * hx - (bx if sx > 0 else 0.0), y, cz + sz * hz - (bz if sz > 0 else 0.0))
					boxes.append(_slab(root, a, a + Vector3(bx, h * 0.6, bz), m, root))
		"split":
			var gap := minf(hx, hz) * 0.25
			if hx >= hz:
				boxes.append(_slab(root, Vector3(cx - 3, y, z0 + 10), Vector3(cx + 3, y + 9, cz - gap), m, root))
				boxes.append(_slab(root, Vector3(cx - 3, y, cz + gap), Vector3(cx + 3, y + 9, z1 - 10), m, root))
			else:
				boxes.append(_slab(root, Vector3(x0 + 10, y, cz - 3), Vector3(cx - gap, y + 9, cz + 3), m, root))
				boxes.append(_slab(root, Vector3(cx + gap, y, cz - 3), Vector3(x1 - 10, y + 9, cz + 3), m, root))
		"ring":
			if R.get("label", "") == "REACTOR HALL": return   # (the reactor itself is the middle)
			var cr := MeshInstance3D.new()
			var cy := CylinderMesh.new()
			cy.radial_segments = 8
			cy.top_radius = minf(hx, hz) * 0.28
			cy.bottom_radius = cy.top_radius
			cy.height = h
			cr.mesh = cy
			cr.material_override = m
			cr.position = Vector3(cx, y + h * 0.5, cz)
			root.add_child(cr)
			var rr := cy.top_radius
			boxes.append([root, AABB(Vector3(cx - rr * 0.85, y, cz - rr * 0.85), Vector3(rr * 1.7, h, rr * 1.7))])
			_slab(root, Vector3(cx - rr - 1.0, y + h * 0.4, cz - 0.5), Vector3(cx + rr + 1.0, y + h * 0.4 + 0.8, cz + 0.5), trim, null)

static func _wall(root: Node3D, boxes: Array, side: Array, a: float, b: float, ylo: float, ytop: float, h: float, hex: bool, m: Material, xsec := "hex", halfw := 34.0) -> void:
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
	var segs: Array = [[foot, rise1, bulge, 0.0], [foot + rise1, rise2, -bulge, bulge]]
	if xsec == "pent":   # v11.96: a pentagon: a tall upright foot, then the roof leans in to a ridge down the middle
		foot = h * 0.5
		segs = [[foot, (ytop - ylo) - foot, -halfw * 0.95, 0.0]]
	_slab(root, lo, Vector3(hi.x, ylo + foot, hi.z), m, null)
	var ln := b - a
	for seg in segs:
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
