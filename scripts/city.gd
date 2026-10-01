class_name City
extends RefCounted
## Capital city PROTOTYPE KIT, built from Godot primitives (no Blender): 8 modules on one modular grid, assembled into
## one test city block. The goal is to prove scale, connections, gameplay and performance, not final art.
## References: Drive "Faction Building Assets - Capital Prototype" (B-01 command tower, mech roads, intersection,
## merge, mega bridge, square/rectangular platforms, stair bridge).
##
## How it stays light:
##  - every part is a unit box / cylinder / cone, instanced: one MultiMesh per (shape, material, LOD group), so the
##    whole block is a dozen or so draw calls however many parts it has;
##  - ONE shared material family (assets/city/capital.gdshader): white armour, dark structure, blue glass, amber, road.
##    Panel lines, grooves, bolts and vents come from one 512 px normal map tiled in world space, not from geometry;
##  - LOD: small parts (antennas, rails, lane dashes, steps, markings) fade out beyond DETAIL_RANGE;
##  - collision is a short list of boxes (decks, pillars, tower blocks), no mesh collision.
## Code is tiny and lives in the core; the city textures + shader are the "city" content pack (assets/city).

# ---- the modular grid (metres). Every road / platform edge that connects uses the same width and height.
const CELL := 40.0          # one grid cell; module footprints are whole cells
const DECK := 20.0          # height of every elevated road / platform surface above the plaza
const DECK_T := 2.5         # deck thickness -> 17.5 m clear underneath ordinary decks
const LANE := 12.0          # one mech lane
const ROAD := 24.0          # curb to curb = 2 lanes. This is THE connection width for roads and platforms.
const RAIL := 3.0           # parapet each side -> a road module is 30 m wide inside its 40 m cell
const PED := 4.0            # pedestrian stairs / walkways (too narrow for a mech on purpose)
const DETAIL_RANGE := 1100.0
# B-01 command tower: built in Blender (art/models/B01_tower_blender.glb), baked by tools/city/bake_glb.py at x2.
const TOWER_PATH := "res://assets/city/b01_tower.glb"
const TOWER_SCALE := 2.0     # Blender metres -> game metres (already baked into the mesh; used for the boxes below)
const TOWER_OFF := -11.0     # the model sits west of the cell centre so its podium ends at the platform edge
const TOWER_TRIS := 1976
const TOWER_BOXES := [       # simple collision, in Blender metres: [stand-in material, min, max]
	[1, Vector3(-7.0, 0, -14.5), Vector3(7.0, 24.0, 7.5)],      # lower hub + buttresses + back foot
	[0, Vector3(-7.0, 24.0, -7.0), Vector3(7.0, 50.0, 5.2)],    # shaft + side slabs
	[1, Vector3(-3.4, 50.0, -5.0), Vector3(3.4, 54.0, 5.0)],    # roof machinery
	[0, Vector3(-18.4, 0, -4.2), Vector3(18.4, 6.3, 9.8)],      # wings
	[0, Vector3(-17.8, 6.3, 1.6), Vector3(17.8, 14.0, 3.4)],    # wing fins
	[0, Vector3(-11.2, 0, 0.5), Vector3(11.2, 19.5, 3.7)],      # legs
	[0, Vector3(-2.6, 0, 6.8), Vector3(2.6, 5.4, 13.5)],        # entrance porch
	[0, Vector3(-12.0, 0, -8.5), Vector3(12.0, 5.5, -4.2)],     # side annexes
]

enum { WHITE, DARK, GLASS, AMBER, ROADM }
enum { BOX, CYL, CONE }

const MODULES := ["road_straight", "intersection", "merge", "mega_bridge", "platform_square", "platform_rect", "stair_bridge", "command_tower"]
const FOOTPRINT := {"road_straight": Vector2i(1, 1), "intersection": Vector2i(1, 1), "merge": Vector2i(2, 4), "mega_bridge": Vector2i(1, 3),
	"platform_square": Vector2i(1, 1), "platform_rect": Vector2i(1, 2), "stair_bridge": Vector2i(1, 1), "command_tower": Vector2i(1, 1)}

## Part list builder. A part is [shape, material, lod (0 main, 1 detail), Transform3D of a unit shape].
class Kit:
	var parts: Array = []
	var conns: Array = []    # {kind, pos, dir, width, height}
	var solids: Array = []   # AABB, simple collision
	var alt: Array = []      # stand-in parts for a module whose real model lives in the city pack
	var tower = null         # Transform3D of the B-01 model, when this module has one
	func box(mat: int, c: Vector3, s: Vector3, lod := 0, rot := Vector3.ZERO, solid := false) -> void:
		parts.append([BOX, mat, lod, Transform3D(Basis.from_euler(rot) * Basis.from_scale(s), c)])
		if solid: solids.append(AABB(c - s * 0.5, s))
	## A deck slab: drawn as given, collides up to the deck surface (the road / floor plate on top is not solid).
	func slab(mat: int, c: Vector3, s: Vector3) -> void:
		box(mat, c, s)
		var top := maxf(c.y + s.y * 0.5, DECK)
		solids.append(AABB(c - s * 0.5, Vector3(s.x, top - (c.y - s.y * 0.5), s.z)))
	func cyl(mat: int, c: Vector3, r: float, h: float, lod := 0) -> void:
		parts.append([CYL, mat, lod, Transform3D(Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), c)])
	func cone(mat: int, foot: Vector3, r: float, h: float, lod := 1) -> void:
		parts.append([CONE, mat, lod, Transform3D(Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), foot + Vector3(0, h * 0.5, 0))])
	func conn(kind: String, pos: Vector3, dir: Vector3, width: float, height: float) -> void:
		conns.append({"kind": kind, "pos": pos, "dir": dir, "width": width, "height": height})

# ---------------------------------------------------------------- shared pieces
## Elevated road deck along Z centred on x0, from z0 to z1. Parapets can be left off on one side (merge).
static func _deck(k: Kit, x0: float, z0: float, z1: float, rails := [true, true]) -> void:
	var ln := z1 - z0
	var cz := (z0 + z1) * 0.5
	var full := ROAD + 2.0 * RAIL
	k.slab(DARK, Vector3(x0, DECK - 0.2 - (DECK_T - 0.2) * 0.5, cz), Vector3(full, DECK_T - 0.2, ln))
	k.box(ROADM, Vector3(x0, DECK - 0.1, cz), Vector3(ROAD, 0.2, ln))
	k.box(DARK, Vector3(x0, DECK - DECK_T - 0.6, cz), Vector3(ROAD * 0.55, 1.2, ln))          # spine beam underneath
	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		k.box(AMBER, Vector3(x0 + sx * (ROAD * 0.5 - 0.7), DECK + 0.02, cz), Vector3(0.4, 0.06, ln), 1)   # edge line
		if not rails[i]: continue
		var px := x0 + sx * (ROAD * 0.5 + RAIL * 0.5)
		k.box(WHITE, Vector3(px, DECK + 0.7, cz), Vector3(RAIL, 1.8, ln), 0, Vector3.ZERO, true)        # parapet
		k.box(GLASS, Vector3(x0 + sx * (ROAD * 0.5 + RAIL + 0.08), DECK - 1.1, cz), Vector3(0.16, 0.5, ln * 0.92), 1)  # light strip
		k.box(AMBER, Vector3(px + sx * RAIL * 0.3, DECK + 1.62, cz), Vector3(0.35, 0.1, ln), 1)          # thin top accent
	for d in int(ln / 10.0):                                                                           # centre dashes
		k.box(WHITE, Vector3(x0, DECK + 0.02, z0 + 5.0 + d * 10.0), Vector3(0.5, 0.06, 4.0), 1)

## Support pillar from the plaza (y 0) to the underside of a deck.
static func _pillar(k: Kit, x: float, z: float, w := 4.0, top := DECK - DECK_T) -> void:
	k.box(DARK, Vector3(x, 1.5, z), Vector3(w + 3.0, 3.0, w + 3.0), 0, Vector3.ZERO, true)
	var h := top - 4.0
	k.box(WHITE, Vector3(x, 3.0 + h * 0.5, z), Vector3(w, h, w), 0, Vector3.ZERO, true)
	k.box(DARK, Vector3(x, top - 0.5, z), Vector3(w + 1.6, 1.0, w + 1.6))
	for sz in [-1.0, 1.0]:
		k.box(GLASS, Vector3(x, 3.0 + h * 0.55, z + sz * (w * 0.5 + 0.06)), Vector3(w * 0.22, h * 0.5, 0.12), 1)

## Parapet pylon with antennas (the signature silhouette of the reference roads).
static func _pylon(k: Kit, x: float, z: float, h := 7.0, w := 3.5, base := DECK) -> void:
	k.box(WHITE, Vector3(x, base + h * 0.5, z), Vector3(w, h, w), 0, Vector3.ZERO, true)
	k.box(DARK, Vector3(x, base + h + 0.6, z), Vector3(w * 0.8, 1.2, w * 0.8))
	k.box(GLASS, Vector3(x, base + h * 0.62, z - w * 0.5 - 0.06), Vector3(w * 0.5, h * 0.35, 0.12), 1)
	k.box(GLASS, Vector3(x, base + h * 0.62, z + w * 0.5 + 0.06), Vector3(w * 0.5, h * 0.35, 0.12), 1)
	k.box(AMBER, Vector3(x, base + h * 0.25, z), Vector3(w + 0.1, 0.25, w + 0.1), 1)
	k.cone(DARK, Vector3(x - w * 0.2, base + h + 1.2, z), 0.3, h * 0.7)
	k.cone(DARK, Vector3(x + w * 0.2, base + h + 1.2, z), 0.25, h * 0.45)

## Railing (posts + amber top bar) along a straight segment at deck level, for platforms.
static func _rail(k: Kit, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.5: return
	var c := (a + b) * 0.5
	var yaw := atan2(d.x, d.z)
	k.box(WHITE, c + Vector3(0, 0.3, 0), Vector3(1.0, 0.6, ln), 0, Vector3(0, yaw, 0), true)          # curb
	k.box(AMBER, c + Vector3(0, 1.6, 0), Vector3(0.2, 0.15, ln), 1, Vector3(0, yaw, 0))               # top bar
	k.box(GLASS, c + Vector3(0, 1.0, 0), Vector3(0.08, 0.8, ln), 1, Vector3(0, yaw, 0))               # glass panel
	for i in int(ln / 4.0) + 1:
		k.box(DARK, a + d * (float(i) / maxf(1.0, floorf(ln / 4.0))) + Vector3(0, 0.85, 0), Vector3(0.45, 1.7, 0.45), 1)

## Elevated platform of w x d metres (centred), with a 24 m opening in the rail at every connector.
static func _platform(k: Kit, w: float, d: float, openings: Array) -> void:
	k.slab(DARK, Vector3(0, DECK - 0.2 - (DECK_T - 0.2) * 0.5, 0), Vector3(w, DECK_T - 0.2, d))
	k.box(ROADM, Vector3(0, DECK - 0.1, 0), Vector3(w - 0.4, 0.2, d - 0.4))
	k.box(WHITE, Vector3(0, DECK - DECK_T - 0.4, 0), Vector3(w - 6.0, 0.8, d - 6.0))               # underside frame
	for sx in [-1.0, 1.0]:
		k.box(WHITE, Vector3(sx * (w * 0.5 - 0.6), DECK - 1.4, 0), Vector3(1.2, 2.4, d), 0)          # side fascia
		k.box(GLASS, Vector3(sx * (w * 0.5 + 0.06), DECK - 1.3, 0), Vector3(0.12, 0.5, d * 0.7), 1)
	for sz in [-1.0, 1.0]:
		k.box(WHITE, Vector3(0, DECK - 1.4, sz * (d * 0.5 - 0.6)), Vector3(w, 2.4, 1.2), 0)
	# rails along each edge, broken by the openings (each opening is a connector: ROAD wide, centred on it)
	var edges := [[Vector3(-w * 0.5, DECK, -d * 0.5), Vector3(w * 0.5, DECK, -d * 0.5), Vector3(0, 0, -1)],
		[Vector3(w * 0.5, DECK, -d * 0.5), Vector3(w * 0.5, DECK, d * 0.5), Vector3(1, 0, 0)],
		[Vector3(w * 0.5, DECK, d * 0.5), Vector3(-w * 0.5, DECK, d * 0.5), Vector3(0, 0, 1)],
		[Vector3(-w * 0.5, DECK, d * 0.5), Vector3(-w * 0.5, DECK, -d * 0.5), Vector3(-1, 0, 0)]]
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var dir: Vector3 = e[2]
		var cuts: Array = []
		for o: Vector3 in openings:
			if absf((o - a).dot(dir)) < 0.01:   # opening centre lies on this edge
				var t := (o - a).dot((b - a).normalized())
				cuts.append([t - ROAD * 0.5, t + ROAD * 0.5])
				k.conn("platform", o, dir, ROAD, DECK)
				k.box(AMBER, o - dir * 1.2 + Vector3(0, 0.03, 0), Vector3(ROAD if dir.x == 0 else 0.6, 0.06, ROAD if dir.z == 0 else 0.6), 1)
		cuts.sort_custom(func(p, q): return p[0] < q[0])
		var s := 0.0
		var ln := a.distance_to(b)
		var u := (b - a).normalized()
		for c in cuts + [[ln, ln]]:
			if c[0] > s + 0.5: _rail(k, a + u * (s + 0.6) - dir * 0.6, a + u * (c[0] - 0.6) - dir * 0.6)
			s = c[1]
	# corner posts
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.box(WHITE, Vector3(sx * (w * 0.5 - 1.6), DECK + 2.5, sz * (d * 0.5 - 1.6)), Vector3(3.2, 5.0, 3.2), 0, Vector3.ZERO, true)
			k.box(GLASS, Vector3(sx * (w * 0.5 - 1.6), DECK + 2.8, sz * (d * 0.5 + 0.06 - 0.0)), Vector3(1.0, 2.6, 0.12), 1)

# ---------------------------------------------------------------- the 8 modules
## Build one module in its own space: centred on its footprint, +Z = "north", y 0 = plaza level.
static func module(id: String) -> Kit:
	var k := Kit.new()
	var hz: float = FOOTPRINT[id].y * CELL * 0.5
	match id:
		"road_straight":   # 01: straight mech road, 2 lanes
			_deck(k, 0, -hz, hz)
			_pillar(k, -10.5, 0)
			_pillar(k, 10.5, 0)
			_pylon(k, -(ROAD * 0.5 + RAIL * 0.5), 0, 6.0, 3.0)
			_pylon(k, ROAD * 0.5 + RAIL * 0.5, 0, 6.0, 3.0)
			k.conn("road", Vector3(0, DECK, hz), Vector3(0, 0, 1), ROAD, DECK)
			k.conn("road", Vector3(0, DECK, -hz), Vector3(0, 0, -1), ROAD, DECK)
		"intersection":    # 02: four-way, octagon marking, corner pylons on big pillars
			var full := CELL
			k.slab(DARK, Vector3(0, DECK - 0.2 - (DECK_T - 0.2) * 0.5, 0), Vector3(full, DECK_T - 0.2, full))
			k.box(ROADM, Vector3(0, DECK - 0.1, 0), Vector3(ROAD, 0.2, full))
			k.box(ROADM, Vector3(0, DECK - 0.1, 0), Vector3(full, 0.2, ROAD))
			var cs := (full - ROAD) * 0.5   # 8 m corner squares
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var c := Vector3(sx * (ROAD * 0.5 + cs * 0.5), DECK + 0.7, sz * (ROAD * 0.5 + cs * 0.5))
					k.box(WHITE, c, Vector3(cs, 1.8, cs), 0, Vector3.ZERO, true)
					k.box(AMBER, c + Vector3(0, 0.95, 0), Vector3(cs * 0.8, 0.1, cs * 0.8), 1)
					_pylon(k, c.x, c.z, 9.0, 5.0)
					_pillar(k, sx * 14.0, sz * 14.0, 6.0)
					for side in [Vector3(sx, 0, 0), Vector3(0, 0, sz)]:
						k.box(GLASS, Vector3(sx * (full * 0.5 + 0.08), DECK - 1.1, sz * (ROAD * 0.5 + cs * 0.5)) if side.x != 0 else Vector3(sx * (ROAD * 0.5 + cs * 0.5), DECK - 1.1, sz * (full * 0.5 + 0.08)),
							Vector3(0.16, 0.5, cs) if side.x != 0 else Vector3(cs, 0.5, 0.16), 1)
			for ring in [[9.0, 7.4], [3.4, 2.8]]:
				for i in 8:
					var a := i * TAU / 8.0
					k.box(AMBER, Vector3(cos(a) * ring[0], DECK + 0.03, sin(a) * ring[0]), Vector3(ring[1], 0.06, 0.5), 1, Vector3(0, -(a + PI * 0.5), 0))
			for d in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				k.conn("road", Vector3(d.x * full * 0.5, DECK, d.z * full * 0.5), d, ROAD, DECK)
				for s in 5:   # crosswalk-style entry bars
					var off := (s - 2) * 4.0
					var pos := Vector3(d.x * (full * 0.5 - 3.0), DECK + 0.03, d.z * (full * 0.5 - 3.0)) + Vector3(absf(d.z) * off, 0, absf(d.x) * off)
					k.box(WHITE, pos, Vector3(2.0 if d.x == 0 else 3.5, 0.06, 2.0 if d.z == 0 else 3.5), 1)
		"merge":           # 03: main road (west column) + an on-ramp from the plaza (east column) merging in
			var mx := -20.0
			_deck(k, mx, -hz, 20.0)
			_deck(k, mx, 20.0, 52.0, [true, false])
			_deck(k, mx, 52.0, hz)
			for z in [-60.0, -20.0, 20.0, 60.0]:
				_pillar(k, mx - 10.5, z)
				_pillar(k, mx + 10.5, z)
			# the ramp: one lane, plaza (y 0) at z -80 up to deck height at z +20
			var rx := 14.0
			var run := 100.0
			var ang := atan(DECK / run)
			var ln := sqrt(run * run + DECK * DECK)
			var mid := Vector3(rx, DECK * 0.5, -hz + run * 0.5)
			k.box(DARK, mid - Vector3(0, 0.85, 0), Vector3(LANE + 2 * RAIL, 1.5, ln), 0, Vector3(-ang, 0, 0))
			k.box(ROADM, mid - Vector3(0, 0.1, 0), Vector3(LANE, 0.2, ln), 0, Vector3(-ang, 0, 0))
			for sx in [-1.0, 1.0]:
				k.box(WHITE, mid + Vector3(sx * (LANE * 0.5 + RAIL * 0.5), 0.7, 0), Vector3(RAIL, 1.8, ln), 0, Vector3(-ang, 0, 0))
				k.box(AMBER, mid + Vector3(sx * (LANE * 0.5 - 0.6), 0.03, 0), Vector3(0.4, 0.06, ln), 1, Vector3(-ang, 0, 0))
			for i in 5:   # collision steps along the ramp + supports
				var z0: float = -hz + i * 20.0
				var top := DECK * (i * 20.0 + 20.0) / run
				k.solids.append(AABB(Vector3(rx - LANE * 0.5, 0, z0), Vector3(LANE, top - 0.6, 20.0)))
				if i > 0: _pillar(k, rx, z0, 3.0, DECK * (i * 20.0) / run - 1.6)
			for i in 3:   # ramp arrows
				k.box(WHITE, Vector3(rx, DECK * (25.0 + i * 25.0) / run + 0.1, -hz + 25.0 + i * 25.0), Vector3(1.0, 0.06, 5.0), 1, Vector3(-ang, 0, 0))
			# merge zone: the ramp lane joins the main road's east lane (z 20..52), then a 45-degree taper
			k.slab(DARK, Vector3((mx + 15.0 + rx + LANE * 0.5 + RAIL) * 0.5, DECK - 1.35, 36.0), Vector3(rx + LANE * 0.5 + RAIL - mx - 15.0, 2.3, 32.0))
			k.box(ROADM, Vector3((mx + 12.0 + rx + LANE * 0.5) * 0.5, DECK - 0.1, 36.0), Vector3(rx + LANE * 0.5 - mx - 12.0, 0.2, 32.0))
			k.box(WHITE, Vector3(rx + LANE * 0.5 + RAIL * 0.5, DECK + 0.7, 36.0), Vector3(RAIL, 1.8, 32.0), 0, Vector3.ZERO, true)
			for st in 4:   # taper deck in steps under the diagonal parapet
				var z0: float = 52.0 + st * 7.0
				var xr := rx + LANE * 0.5 + RAIL - (st + 1) * 7.0
				k.slab(DARK, Vector3((mx + 15.0 + xr) * 0.5, DECK - 1.35, z0 + 3.5), Vector3(xr - mx - 15.0, 2.3, 7.0))
				k.box(ROADM, Vector3((mx + 12.0 + xr) * 0.5, DECK - 0.1, z0 + 3.5), Vector3(xr - mx - 12.0, 0.2, 7.0))
			var da := Vector3(rx + LANE * 0.5 + RAIL * 0.5, DECK + 0.7, 52.0)
			var db := Vector3(mx + ROAD * 0.5 + RAIL * 0.5, DECK + 0.7, hz)
			k.box(WHITE, (da + db) * 0.5, Vector3(RAIL, 1.8, da.distance_to(db)), 0, Vector3(0, atan2(db.x - da.x, db.z - da.z), 0))
			for i in 3:   # chevrons where the lanes merge
				k.box(WHITE, Vector3(rx - 2.0 - i * 4.0, DECK + 0.03, 40.0 + i * 3.0), Vector3(0.6, 0.06, 6.0), 1, Vector3(0, -0.6, 0))
			_pylon(k, rx + LANE * 0.5 + RAIL * 0.5, 36.0, 7.0, 3.5)
			k.conn("road", Vector3(mx, DECK, hz), Vector3(0, 0, 1), ROAD, DECK)
			k.conn("road", Vector3(mx, DECK, -hz), Vector3(0, 0, -1), ROAD, DECK)
			k.conn("ramp", Vector3(rx, 0.0, -hz), Vector3(0, 0, -1), LANE, 0.0)
		"mega_bridge":     # 04: 120 m span, heavy truss, twin end pylons; open underneath for passing mechs
			_deck(k, 0, -hz, hz)
			k.box(DARK, Vector3(0, DECK - DECK_T - 1.25, 0), Vector3(ROAD + 2 * RAIL, 2.5, hz * 2.0 - 16.0), 0, Vector3.ZERO, true)  # truss box
			for sz in [-1.0, 1.0]:
				var z: float = sz * (hz - 7.0)
				for sx in [-1.0, 1.0]:
					var x: float = sx * (ROAD * 0.5 + RAIL + 3.5)
					k.box(DARK, Vector3(x, 2.0, z), Vector3(10.0, 4.0, 12.0), 0, Vector3.ZERO, true)        # foot
					k.box(WHITE, Vector3(x, 4.0 + (DECK + 14.0 - 4.0) * 0.5, z), Vector3(6.0, DECK + 14.0 - 4.0, 8.0), 0, Vector3.ZERO, true)
					k.box(GLASS, Vector3(x + sx * 3.06, 4.0 + (DECK + 10.0) * 0.5, z), Vector3(0.12, DECK * 0.8, 2.0), 1)
					k.box(GLASS, Vector3(x, DECK + 8.0, z - sz * 4.06), Vector3(2.0, 6.0, 0.12), 1)
					k.box(DARK, Vector3(x, DECK + 14.6, z), Vector3(5.0, 1.2, 7.0))
					k.box(AMBER, Vector3(x, DECK + 2.0, z), Vector3(6.1, 0.3, 8.1), 1)
					k.cone(DARK, Vector3(x - 1.2, DECK + 15.2, z), 0.45, 12.0)
					k.cone(DARK, Vector3(x + 1.2, DECK + 15.2, z), 0.35, 8.0)
					# diagonal braces from the pylon foot toward mid-span, under the truss
					var brace_a := Vector3(x * 0.55, 6.0, z)
					var brace_b := Vector3(x * 0.55, DECK - DECK_T - 2.5, z - sz * 30.0)
					k.box(DARK, (brace_a + brace_b) * 0.5, Vector3(1.6, 1.6, brace_a.distance_to(brace_b)), 1, Vector3(atan2(-(brace_b.y - brace_a.y), brace_b.z - brace_a.z), 0, 0))
				k.box(WHITE, Vector3(0, DECK - DECK_T - 3.0, z), Vector3(ROAD + 2 * RAIL + 12.0, 1.5, 6.0), 0)   # cross beam
			_pylon(k, -(ROAD * 0.5 + RAIL * 0.5), 0, 7.0, 3.0)
			_pylon(k, ROAD * 0.5 + RAIL * 0.5, 0, 7.0, 3.0)
			for i in 2:   # deck chevrons
				k.box(WHITE, Vector3(-3.0 + i * 6.0, DECK + 0.03, 0), Vector3(1.0, 0.06, 6.0), 1, Vector3(0, 0.5 - i, 0))
			k.conn("road", Vector3(0, DECK, hz), Vector3(0, 0, 1), ROAD, DECK)
			k.conn("road", Vector3(0, DECK, -hz), Vector3(0, 0, -1), ROAD, DECK)
		"platform_square": # 05
			_platform(k, CELL, CELL, [Vector3(0, DECK, CELL * 0.5), Vector3(0, DECK, -CELL * 0.5), Vector3(CELL * 0.5, DECK, 0), Vector3(-CELL * 0.5, DECK, 0)])
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]: _pillar(k, sx * 14.0, sz * 14.0, 5.0)
			for i in 4:   # landing square marking
				var a2 := i * PI * 0.5
				k.box(AMBER, Vector3(cos(a2) * 8.0, DECK + 0.03, sin(a2) * 8.0), Vector3(0.5 if i % 2 == 0 else 16.5, 0.06, 16.5 if i % 2 == 0 else 0.5), 1)
		"platform_rect":   # 06
			_platform(k, CELL, CELL * 2.0, [Vector3(0, DECK, CELL), Vector3(0, DECK, -CELL), Vector3(CELL * 0.5, DECK, -20.0), Vector3(CELL * 0.5, DECK, 20.0),
				Vector3(-CELL * 0.5, DECK, -20.0), Vector3(-CELL * 0.5, DECK, 20.0)])
			for sx in [-1.0, 1.0]:
				for z in [-34.0, 0.0, 34.0]: _pillar(k, sx * 14.0, z, 5.0)
			for i in 6:
				k.box(AMBER, Vector3(0, DECK + 0.03, -30.0 + i * 12.0), Vector3(14.0, 0.06, 0.5), 1)
		"stair_bridge":    # 07: PEDESTRIAN stairs, plaza -> deck height, 4 m wide (separate from the mech roads)
			var hw := PED * 0.5
			k.box(DARK, Vector3(0, 0.2, -hz + 3.0), Vector3(PED + 4.0, 0.4, 6.0), 0, Vector3.ZERO, true)    # bottom landing
			var flights := [[-hz + 6.0, -2.0, 0.0, DECK * 0.5], [6.0, hz - 2.0, DECK * 0.5, DECK]]
			for f in flights:
				var z0: float = f[0]
				var z1: float = f[1]
				var y0: float = f[2]
				var y1: float = f[3]
				var steps := int((y1 - y0) / 0.5)
				var run := (z1 - z0) / steps
				for s in steps:
					k.box(ROADM, Vector3(0, y0 + 0.5 * (s + 1) - 0.25, z0 + run * (s + 0.5)), Vector3(PED, 0.5, run), 1)
				var a := Vector3(0, y0, z0)
				var b := Vector3(0, y1, z1)
				var ang := atan2(y1 - y0, z1 - z0)
				var c := (a + b) * 0.5
				var ln := a.distance_to(b)
				k.box(DARK, c - Vector3(0, 0.6, 0), Vector3(PED, 0.8, ln), 0, Vector3(-ang, 0, 0))          # soffit (silhouette)
				for sx in [-1.0, 1.0]:
					k.box(WHITE, c + Vector3(sx * (hw + 0.5), 0.6, 0), Vector3(1.0, 1.8, ln), 0, Vector3(-ang, 0, 0))
					k.box(GLASS, c + Vector3(sx * (hw + 1.06), 0.4, 0), Vector3(0.12, 0.4, ln * 0.85), 1, Vector3(-ang, 0, 0))
				for i in 3:   # collision steps
					var t0 := float(i) / 3.0
					k.solids.append(AABB(Vector3(-hw, 0, z0 + (z1 - z0) * t0), Vector3(PED, y0 + (y1 - y0) * (t0 + 1.0 / 3.0) - 0.4, (z1 - z0) / 3.0)))
			k.box(DARK, Vector3(0, DECK * 0.5 - 0.3, 2.0), Vector3(PED + 4.0, 0.6, 8.0), 0, Vector3.ZERO, true)   # mid landing
			k.box(WHITE, Vector3(0, DECK * 0.25 - 0.3, 2.0), Vector3(4.0, DECK * 0.5 - 0.6, 4.0), 0, Vector3.ZERO, true)
			k.box(DARK, Vector3(0, DECK - 0.3, hz - 1.0), Vector3(PED + 4.0, 0.6, 2.0), 0, Vector3.ZERO, true)    # top landing
			k.box(WHITE, Vector3(0, DECK * 0.5 - 0.6, hz - 2.5), Vector3(3.0, DECK - 1.2, 3.0), 0, Vector3.ZERO, true)
			for sx in [-1.0, 1.0]:
				_pylon(k, sx * (hw + 1.5), 2.0, 3.0, 1.6, DECK * 0.5)
			k.conn("ped", Vector3(0, DECK, hz), Vector3(0, 0, 1), PED, DECK)
			k.conn("ped", Vector3(0, 0.0, -hz), Vector3(0, 0, -1), PED, 0.0)
		"command_tower":   # 08: B-01. The real model is the Blender build (assets/city/b01_tower.glb, city pack), ~61 x 77 m, 119 m tall.
			# Here: its collision boxes (also drawn as the plain stand-in until the pack is in) + the gangway to the platform.
			# The model's front (+Z in Blender's export) is turned to face east, at the platform.
			var txf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(TOWER_OFF, 0, 0))
			for bx: Array in TOWER_BOXES:   # [material, min, max] in Blender metres
				var box: AABB = txf * AABB((bx[1] as Vector3) * TOWER_SCALE, ((bx[2] as Vector3) - (bx[1] as Vector3)) * TOWER_SCALE)
				k.alt.append([BOX, bx[0], 0, Transform3D(Basis.from_scale(box.size), box.get_center())])
				k.solids.append(box)
			# gangway at deck height: from the light ring on the tower's front, over the entrance porch, to the cell edge
			# (the same 24 m connection as every platform)
			var gx0 := TOWER_OFF + 14.0
			var gx1 := CELL * 0.5
			k.slab(DARK, Vector3((gx0 + gx1) * 0.5, DECK - DECK_T * 0.5, 0), Vector3(gx1 - gx0, DECK_T, ROAD))
			k.box(ROADM, Vector3((gx0 + gx1) * 0.5, DECK - 0.05, 0), Vector3(gx1 - gx0, 0.12, ROAD - 2.0))
			for sz in [-1.0, 1.0]:
				k.box(WHITE, Vector3((gx0 + gx1) * 0.5, DECK + 0.7, sz * (ROAD * 0.5 + 0.4)), Vector3(gx1 - gx0, 1.4, 0.8), 0, Vector3.ZERO, true)
				k.box(AMBER, Vector3((gx0 + gx1) * 0.5, DECK + 1.45, sz * (ROAD * 0.5 + 0.4)), Vector3(gx1 - gx0, 0.12, 0.3), 1)
				_pillar(k, gx1 - 1.5, sz * (ROAD * 0.5 - 1.0), 2.4)
			k.conn("platform", Vector3(CELL * 0.5, DECK, 0), Vector3(1, 0, 0), ROAD, DECK)
			k.tower = txf
	return k

## A simplified background building (kept to big forms: body, glass strips, roof, antenna).
static func filler(k: Kit, c: Vector3, w: float, d: float, h: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	k.box(DARK, c + Vector3(0, 1.5, 0), Vector3(w + 4.0, 3.0, d + 4.0), 0, Vector3.ZERO, true)
	k.box(WHITE, c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), 0, Vector3.ZERO, true)
	k.box(GLASS, c + Vector3(0, h * 0.55, -d * 0.5 - 0.06), Vector3(w * 0.3, h * 0.7, 0.12), 0)
	k.box(GLASS, c + Vector3(w * 0.5 + 0.06, h * 0.5, 0), Vector3(0.12, h * 0.6, d * 0.25), 0)
	var top := h
	if rng.randf() < 0.6:
		k.box(WHITE, c + Vector3(-w * 0.15, h + h * 0.15, d * 0.1), Vector3(w * 0.6, h * 0.3, d * 0.6), 0, Vector3.ZERO, true)
		top = h * 1.3
	k.box(DARK, c + Vector3(0, top * 0.98, 0), Vector3(w * 0.5, 1.2, d * 0.5))
	k.box(AMBER, c + Vector3(0, h * 0.3, 0), Vector3(w + 0.1, 0.3, d + 0.1), 1)
	k.cone(DARK, c + Vector3(0, top + 0.6, 0), 0.4, rng.randf_range(8.0, 16.0))

# ---------------------------------------------------------------- assembly
## Place a module at grid cell `cell` (min corner) rotated rot * 90 degrees. Adds its parts, connectors and solids.
static func place(block: Dictionary, id: String, cell: Vector2i, rot := 0) -> void:
	var k := module(id)
	var fp: Vector2i = FOOTPRINT[id]
	var f := Vector2(fp.y, fp.x) if rot % 2 == 1 else Vector2(fp.x, fp.y)
	var origin := Vector3((cell.x + f.x * 0.5) * CELL, 0, (cell.y + f.y * 0.5) * CELL)
	var xf := Transform3D(Basis(Vector3.UP, rot * PI * 0.5), origin)
	for p in k.parts: block["parts"].append([p[0], p[1], p[2], xf * (p[3] as Transform3D)])
	for c in k.conns:
		block["conns"].append({"module": id, "cell": cell, "kind": c["kind"], "pos": xf * (c["pos"] as Vector3),
			"dir": (xf.basis * (c["dir"] as Vector3)).round(), "width": c["width"], "height": c["height"]})
	for s: AABB in k.solids: block["solids"].append(xf * s)
	for p in k.alt: block["alt"].append([p[0], p[1], p[2], xf * (p[3] as Transform3D)])
	if k.tower != null: block["tower"] = xf * (k.tower as Transform3D)
	block["modules"].append({"id": id, "cell": cell, "rot": rot, "footprint": f})

## THE test city block: command tower, square + rectangular platforms, intersection, roads, merge/on-ramp,
## mega bridge, stair bridge, and a few simplified background buildings. Returns the block description.
static func test_block() -> Dictionary:
	var b := {"parts": [], "conns": [], "solids": [], "modules": [], "alt": [], "tower": null}
	# the north-south avenue (column 3)
	place(b, "road_straight", Vector2i(3, -6))
	place(b, "merge", Vector2i(3, -10))           # cells x 3..4, z -10..-7; ramp comes up from the plaza in column 4
	place(b, "road_straight", Vector2i(3, -11))
	place(b, "intersection", Vector2i(3, -5))
	place(b, "mega_bridge", Vector2i(3, -4))      # z -4..-1: 120 m clear span over the plaza
	place(b, "road_straight", Vector2i(3, -1))
	# west: platform plaza in front of the command tower
	place(b, "platform_square", Vector2i(2, -5))
	place(b, "command_tower", Vector2i(1, -5))
	place(b, "stair_bridge", Vector2i(2, -4), 2)  # rotated 180: top lands on the square platform's north edge
	# east: road out to the long platform
	place(b, "road_straight", Vector2i(4, -5), 1)
	place(b, "platform_rect", Vector2i(5, -5), 1)
	# background structures
	var k := Kit.new()
	var fill := [[Vector3(-0.5, 0, -8.0), 24.0, 22.0, 70.0], [Vector3(0.6, 0, -1.5), 30.0, 26.0, 46.0], [Vector3(6.6, 0, -1.6), 26.0, 26.0, 84.0],
		[Vector3(7.6, 0, -7.4), 22.0, 30.0, 58.0], [Vector3(0.4, 0, -10.6), 28.0, 22.0, 38.0], [Vector3(6.2, 0, -10.2), 24.0, 24.0, 64.0]]
	for i in fill.size():
		var f: Array = fill[i]
		filler(k, (f[0] as Vector3) * CELL, f[1], f[2], f[3], 70 + i)
	for p in k.parts: b["parts"].append(p)
	for s in k.solids: b["solids"].append(s)
	# plaza: the ground level everything stands on (roads ramp down to it, stairs and mechs walk on it)
	var lo := Vector3(-2, 0, -12) * CELL
	var hi := Vector3(9, 0, 1) * CELL
	b["plaza"] = AABB(Vector3(lo.x, -1.0, lo.z), Vector3(hi.x - lo.x, 1.0, hi.z - lo.z))
	b["parts"].append([BOX, ROADM, 0, Transform3D(Basis.from_scale(b["plaza"].size), b["plaza"].get_center())])
	b["solids"].append(b["plaza"])
	for i in 12:   # walkway kerbs + mech crossing hatch on the plaza (under the bridge)
		b["parts"].append([BOX, AMBER, 1, Transform3D(Basis.from_scale(Vector3(3.0, 0.06, 0.8)), Vector3(3.5 * CELL - 9.0 + i * 1.6, 0.03, -2.5 * CELL))])
	return b

## Connector pairs: two connectors meet when they sit at the same point facing each other.
## Returns {"joined": [[a, b], ...], "bad": [...]} (bad = met but width/height/kind don't match).
static func joins(block: Dictionary) -> Dictionary:
	var joined: Array = []
	var bad: Array = []
	var cs: Array = block["conns"]
	for i in cs.size():
		for j in range(i + 1, cs.size()):
			var a: Dictionary = cs[i]
			var c: Dictionary = cs[j]
			if (a["pos"] as Vector3).distance_to(c["pos"]) > 0.05: continue
			if (a["dir"] as Vector3).dot(c["dir"]) > -0.99: continue
			if a["kind"] == "ped" or c["kind"] == "ped": continue   # stairs: see lands_on_platform()
			var ok: bool = absf(float(a["width"]) - float(c["width"])) < 0.01 and absf(float(a["height"]) - float(c["height"])) < 0.01 \
				and (a["kind"] == c["kind"] or (a["kind"] in ["road", "platform"] and c["kind"] in ["road", "platform"]))
			(joined if ok else bad).append([a, c])
	return {"joined": joined, "bad": bad}

## Does a connector land on a platform's open edge? (stairs end anywhere along an opening, not only at its centre)
static func lands_on_platform(block: Dictionary, c: Dictionary) -> bool:
	for o in block["conns"]:
		if o["kind"] != "platform" or (o["dir"] as Vector3).dot(c["dir"]) > -0.99: continue
		var d: Vector3 = (c["pos"] as Vector3) - (o["pos"] as Vector3)
		if absf(d.y) < 0.01 and absf(d.dot(o["dir"])) < 0.05 and d.length() <= float(o["width"]) * 0.5 - float(c["width"]) * 0.5 + 0.01: return true
	return false

# ---------------------------------------------------------------- rendering
static var _meshes: Array = []
static var _mats := {}

static func _unit_meshes() -> Array:
	if _meshes.is_empty():
		var bx := BoxMesh.new()
		var cy := CylinderMesh.new()
		cy.radial_segments = 8
		cy.rings = 1
		cy.top_radius = 0.5
		cy.bottom_radius = 0.5
		cy.height = 1.0
		var cn := CylinderMesh.new()
		cn.radial_segments = 6
		cn.rings = 1
		cn.top_radius = 0.0
		cn.bottom_radius = 0.5
		cn.height = 1.0
		cn.cap_top = false
		_meshes = [bx, cy, cn]
	return _meshes

## The five capital materials. With the city pack mounted: one shared shader + normal/mask maps. Without it (pack
## still downloading): flat colours, same layout, so nothing waits on the download.
static func materials(detail := 1.0) -> Array:
	var key := "d%.2f|%s" % [detail, Packs.is_ready("city")]
	if _mats.has(key): return _mats[key]
	var spec := [  # base colour, roughness, metallic, glow, window cells, seam darkening, metres per tile
		[Color(0.86, 0.87, 0.88), 0.45, 0.1, Color(0, 0, 0), 0.0, 0.3, 14.0],      # WHITE armour
		[Color(0.16, 0.17, 0.19), 0.6, 0.4, Color(0, 0, 0), 0.0, 0.25, 10.0],      # DARK structural metal
		[Color(0.08, 0.16, 0.26), 0.15, 0.3, Color(0.25, 0.6, 1.0) * 1.6, 1.0, 0.1, 6.0],  # GLASS / blue emissive
		[Color(1.0, 0.68, 0.12), 0.4, 0.1, Color(1.0, 0.6, 0.1) * 0.35, 0.0, 0.0, 8.0],    # AMBER accents
		[Color(0.2, 0.21, 0.23), 0.85, 0.05, Color(0, 0, 0), 0.0, 0.5, 12.0],      # ROAD / deck plates
	]
	var out: Array = []
	var sh: Shader = load("res://assets/city/capital.gdshader") if Packs.is_ready("city") else null
	for sp in spec:
		if sh:
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("base", sp[0])
			m.set_shader_parameter("rough", sp[1])
			m.set_shader_parameter("metal", sp[2])
			m.set_shader_parameter("glow", sp[3])
			m.set_shader_parameter("window_cells", sp[4])
			m.set_shader_parameter("seam_dark", sp[5])
			m.set_shader_parameter("tile_m", sp[6])
			m.set_shader_parameter("detail", detail)
			m.set_shader_parameter("panel_nrm", load("res://assets/city/capital_normal.png"))
			m.set_shader_parameter("panel_mask", load("res://assets/city/capital_mask.png"))
			out.append(m)
		else:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = sp[0]
			sm.roughness = sp[1]
			sm.metallic = sp[2]
			if (sp[3] as Color).r + (sp[3] as Color).b > 0.0:
				sm.emission_enabled = true
				sm.emission = sp[3]
			out.append(sm)
	_mats[key] = out
	return out

## Turn a block description into nodes: one MultiMeshInstance3D per (shape, material, LOD group).
static func instantiate(block: Dictionary, detail := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "CapitalBlock"
	var groups := {}
	for p in block["parts"]:
		var key := "%d|%d|%d" % [p[0], p[1], p[2]]
		if not groups.has(key): groups[key] = []
		groups[key].append(p[3])
	var meshes := _unit_meshes()
	var mats := materials(detail)
	for key: String in groups:
		var ks := key.split("|")
		var xfs: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[int(ks[0])]
		mm.instance_count = xfs.size()
		for i in xfs.size(): mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mats[int(ks[1])]
		mmi.name = "Kit_%s_%s_%s" % [["box", "cyl", "cone"][int(ks[0])], ["white", "dark", "glass", "amber", "road"][int(ks[1])], "detail" if ks[2] == "1" else "main"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.set_meta("mat", int(ks[1]))
		if ks[2] == "1":
			mmi.visibility_range_end = DETAIL_RANGE   # LOD: small parts drop out at range
			mmi.visibility_range_end_margin = 100.0
		root.add_child(mmi)
	root.set_meta("solids", block["solids"])
	root.set_meta("alt", block.get("alt", []))
	root.set_meta("tower", block.get("tower"))
	_tower(root, detail)
	return root

## The B-01 command tower: the Blender model once the city pack is mounted, a few plain boxes until then.
## It carries its own painted textures (colour, normal/bump, roughness+metal, glow), baked in Blender: one draw call.
static var _tower_mat: Material = null

static func tower_material() -> Material:
	if _tower_mat == null:
		var m := ORMMaterial3D.new()
		m.albedo_texture = load("res://assets/city/b01_color.jpg")
		m.orm_texture = load("res://assets/city/b01_orm.jpg")
		m.normal_enabled = true
		m.normal_texture = load("res://assets/city/b01_normal.jpg")
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_texture = load("res://assets/city/b01_emission.jpg")
		m.emission_energy_multiplier = 2.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED   # the Blender export is double-sided
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_tower_mat = m
	return _tower_mat

static var _tower_mesh: Mesh = null

static func tower_mesh() -> Mesh:
	if _tower_mesh == null and Packs.is_ready("city") and ResourceLoader.exists(TOWER_PATH):
		var sc := (load(TOWER_PATH) as PackedScene).instantiate()
		var found := sc.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty(): _tower_mesh = (found[0] as MeshInstance3D).mesh
		sc.free()
	return _tower_mesh

static func _tower(root: Node3D, detail := 1.0) -> void:
	if root.get_meta("tower") == null: return
	var mats := materials(detail)
	var mesh := tower_mesh()
	var cur := root.get_node_or_null("B01Tower")
	var alt := root.get_node_or_null("B01StandIn")
	if mesh:
		if alt:
			root.remove_child(alt)
			alt.queue_free()
		var mi := cur as MeshInstance3D
		if mi == null:
			mi = MeshInstance3D.new()
			mi.name = "B01Tower"
			mi.mesh = mesh
			mi.transform = root.get_meta("tower")
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
		mi.material_override = tower_material()
	elif alt == null and cur == null:
		var parts: Array = root.get_meta("alt")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _unit_meshes()[BOX]
		mm.instance_count = parts.size()
		for i in parts.size(): mm.set_instance_transform(i, parts[i][3])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "B01StandIn"
		mmi.multimesh = mm
		mmi.material_override = mats[WHITE]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)

## Re-apply the materials (e.g. once the city pack is mounted).
static func refresh(root: Node3D, detail := 1.0) -> void:
	var mats := materials(detail)
	for c in root.get_children():
		if c is MultiMeshInstance3D and c.has_meta("mat"): (c as MultiMeshInstance3D).material_override = mats[int(c.get_meta("mat"))]
	if root.has_meta("tower"): _tower(root, detail)

## Rough cost numbers for the report: instances, triangles, draw calls (one per MultiMesh).
static func stats(block: Dictionary) -> Dictionary:
	var tris_per := [12, 32, 6]
	var tri := 0
	var tri_main := 0
	var groups := {}
	for p in block["parts"]:
		tri += tris_per[p[0]]
		if p[2] == 0: tri_main += tris_per[p[0]]
		groups["%d|%d|%d" % [p[0], p[1], p[2]]] = true
	var tw := 0 if block.get("tower") == null else 1
	return {"parts": block["parts"].size() + tw, "triangles": tri + tw * TOWER_TRIS, "triangles_far": tri_main + tw * TOWER_TRIS,
		"draw_calls": groups.size() + tw, "solids": block["solids"].size()}
