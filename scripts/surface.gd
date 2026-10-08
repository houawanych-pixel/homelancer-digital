class_name Surface
extends RefCounted
## Planet surfaces as flat free-flight tiles (Star Fox all-range style), not spheres.
## A planet is a grid of square tiles (1 = moon, 2x2 = medium, 3x3 = large). Only ONE tile is ever loaded.
## Edges wrap like Pac-Man on a torus: east of the last column is column 0, north of row 0 is the last row.
## Terrain height comes from one noise field in planet coordinates, so neighbouring tiles line up; each tile's mesh
## reaches MARGIN past its edge and fog hides the end, so you never see the world stop.

const TILE := 5000.0        # playable width of a tile (m)
const MARGIN := 1600.0      # extra terrain drawn past each edge, hidden by fog
const CEILING := 2600.0     # climb above this to leave the atmosphere
const GRID_N := 128         # terrain quads per side
const EDGE := TILE * 0.5

# Biomes: height shape, colours by height, sky and fog. "sea" = water level (null = no water).
const BIOMES := {
	"ocean": {"name": "Open ocean", "amp": 260.0, "base": -140.0, "sea": 0.0, "low": Color(0.76, 0.7, 0.52), "mid": Color(0.3, 0.5, 0.28), "high": Color(0.45, 0.45, 0.42),
		"sky": Color(0.32, 0.55, 0.9), "horizon": Color(0.72, 0.82, 0.92), "fog": Color(0.7, 0.8, 0.9), "water": Color(0.08, 0.3, 0.5)},
	"coast": {"name": "Coastal city", "amp": 380.0, "base": 20.0, "sea": 0.0, "low": Color(0.8, 0.74, 0.55), "mid": Color(0.34, 0.55, 0.3), "high": Color(0.5, 0.5, 0.46),
		"sky": Color(0.3, 0.55, 0.92), "horizon": Color(0.78, 0.85, 0.92), "fog": Color(0.74, 0.82, 0.9), "water": Color(0.1, 0.34, 0.52)},
	"canyon": {"name": "Red canyon", "amp": 560.0, "base": 40.0, "sea": 0.0, "terrace": true, "detail": 1.0, "strata": 1.0,
		"low": Color(0.62, 0.36, 0.22), "mid": Color(0.74, 0.44, 0.26), "high": Color(0.8, 0.56, 0.36),
		"sky": Color(0.42, 0.6, 0.88), "horizon": Color(0.95, 0.8, 0.62), "fog": Color(0.9, 0.74, 0.58), "water": Color(0.14, 0.34, 0.36)},
	"desert": {"name": "Desert", "detail": 1.0, "strata": 1.0, "amp": 420.0, "base": 40.0, "sea": null, "low": Color(0.86, 0.7, 0.45), "mid": Color(0.8, 0.58, 0.36), "high": Color(0.62, 0.42, 0.3),
		"sky": Color(0.45, 0.62, 0.9), "horizon": Color(0.95, 0.85, 0.7), "fog": Color(0.92, 0.82, 0.66)},
	"mountains": {"name": "Mountains", "strata": 0.15, "amp": 760.0, "base": 80.0, "sea": null, "low": Color(0.35, 0.48, 0.3), "mid": Color(0.45, 0.42, 0.38), "high": Color(0.95, 0.96, 1.0),
		"sky": Color(0.3, 0.5, 0.88), "horizon": Color(0.75, 0.82, 0.92), "fog": Color(0.72, 0.78, 0.88)},
	"city": {"name": "Capital city", "amp": 300.0, "base": 30.0, "sea": 0.0, "low": Color(0.55, 0.55, 0.5), "mid": Color(0.4, 0.52, 0.34), "high": Color(0.55, 0.52, 0.48),
		"sky": Color(0.34, 0.55, 0.88), "horizon": Color(0.8, 0.84, 0.9), "fog": Color(0.76, 0.8, 0.86), "water": Color(0.12, 0.32, 0.46)},
	"forest": {"name": "Forest", "amp": 520.0, "base": 60.0, "sea": 0.0, "low": Color(0.2, 0.4, 0.2), "mid": Color(0.14, 0.34, 0.16), "high": Color(0.36, 0.4, 0.3),
		"sky": Color(0.32, 0.52, 0.85), "horizon": Color(0.7, 0.8, 0.82), "fog": Color(0.62, 0.72, 0.7), "water": Color(0.1, 0.28, 0.3)},
	"ice": {"name": "Ice sheet", "amp": 600.0, "base": 60.0, "sea": 0.0, "low": Color(0.78, 0.86, 0.94), "mid": Color(0.9, 0.94, 1.0), "high": Color(1, 1, 1),
		"sky": Color(0.5, 0.65, 0.9), "horizon": Color(0.88, 0.92, 0.98), "fog": Color(0.86, 0.9, 0.96), "water": Color(0.2, 0.4, 0.55)},
	"industrial": {"name": "Industrial zone", "amp": 320.0, "base": 30.0, "sea": null, "low": Color(0.42, 0.4, 0.38), "mid": Color(0.36, 0.34, 0.3), "high": Color(0.5, 0.46, 0.4),
		"sky": Color(0.5, 0.5, 0.52), "horizon": Color(0.7, 0.64, 0.56), "fog": Color(0.62, 0.58, 0.52)},
	"wasteland": {"name": "Wasteland", "detail": 0.6, "strata": 0.7, "amp": 480.0, "base": 30.0, "sea": null, "low": Color(0.5, 0.42, 0.32), "mid": Color(0.42, 0.36, 0.3), "high": Color(0.3, 0.26, 0.24),
		"sky": Color(0.55, 0.5, 0.48), "horizon": Color(0.8, 0.66, 0.52), "fog": Color(0.72, 0.6, 0.5)},
	"jungle": {"name": "Alien jungle", "amp": 560.0, "base": 40.0, "sea": 0.0, "low": Color(0.16, 0.42, 0.28), "mid": Color(0.2, 0.5, 0.2), "high": Color(0.3, 0.36, 0.22),
		"sky": Color(0.36, 0.6, 0.68), "horizon": Color(0.7, 0.86, 0.72), "fog": Color(0.56, 0.74, 0.6), "water": Color(0.08, 0.3, 0.26)},
	"volcanic": {"name": "Volcanic", "amp": 640.0, "base": 40.0, "sea": null, "low": Color(0.14, 0.12, 0.12), "mid": Color(0.24, 0.18, 0.16), "high": Color(0.9, 0.35, 0.12),
		"sky": Color(0.35, 0.2, 0.18), "horizon": Color(0.8, 0.42, 0.25), "fog": Color(0.45, 0.3, 0.26)},
	# v1.4l: one-tile surfaces for the planet types that had none. Colours follow the planet seen from space.
	"barren": {"name": "Barren plain", "detail": 0.7, "strata": 0.5, "amp": 520.0, "base": 40.0, "sea": null, "low": Color(0.36, 0.35, 0.37), "mid": Color(0.46, 0.45, 0.46), "high": Color(0.62, 0.6, 0.58),
		"sky": Color(0.05, 0.06, 0.1), "horizon": Color(0.3, 0.32, 0.38), "fog": Color(0.26, 0.27, 0.31)},
	"clouds": {"name": "Cloud deck", "amp": 260.0, "base": -90.0, "sea": 0.0, "detail": 0.3,
		"low": Color(0.95, 0.85, 0.66), "mid": Color(0.86, 0.68, 0.45), "high": Color(0.7, 0.5, 0.34),
		"sky": Color(0.86, 0.68, 0.42), "horizon": Color(0.98, 0.88, 0.68), "fog": Color(0.93, 0.78, 0.55), "water": Color(0.9, 0.74, 0.5)},
	"crystal": {"name": "Crystal fields", "amp": 760.0, "base": 40.0, "sea": null, "terrace": true, "detail": 0.8,
		"low": Color(0.34, 0.2, 0.55), "mid": Color(0.5, 0.4, 0.82), "high": Color(0.82, 0.9, 1.0),
		"sky": Color(0.24, 0.14, 0.42), "horizon": Color(0.7, 0.55, 0.95), "fog": Color(0.55, 0.42, 0.8)},
	"toxic": {"name": "Toxic marsh", "amp": 380.0, "base": 20.0, "sea": 0.0, "low": Color(0.42, 0.5, 0.12), "mid": Color(0.28, 0.34, 0.12), "high": Color(0.55, 0.6, 0.2),
		"sky": Color(0.4, 0.5, 0.14), "horizon": Color(0.72, 0.82, 0.3), "fog": Color(0.55, 0.66, 0.22), "water": Color(0.42, 0.6, 0.08)},
	"machine": {"name": "Machine plates", "amp": 240.0, "base": 30.0, "sea": null, "terrace": true, "detail": 0.3,
		"low": Color(0.12, 0.14, 0.2), "mid": Color(0.26, 0.28, 0.34), "high": Color(0.2, 0.7, 0.8),
		"sky": Color(0.05, 0.07, 0.11), "horizon": Color(0.16, 0.4, 0.48), "fog": Color(0.1, 0.2, 0.26)},
	# the surface of a star: a glowing magma sea with dark crust islands, under a yellow sky ("glow" = the sea shines)
	"sun": {"name": "Solar surface", "amp": 300.0, "base": -70.0, "sea": 0.0, "glow": true, "detail": 0.6,
		"low": Color(1.0, 0.72, 0.2), "mid": Color(0.75, 0.28, 0.06), "high": Color(0.22, 0.08, 0.05),
		"sky": Color(1.0, 0.72, 0.22), "horizon": Color(1.0, 0.9, 0.55), "fog": Color(1.0, 0.72, 0.28), "water": Color(1.0, 0.5, 0.08)},
}

# Planets with surfaces. tiles: row-major biome list (row 0 = north). locations: named places you can land at /
# fast-travel to (pos = metres from the tile centre, x east, y south).
static var PLANETS: Dictionary = _all_planets()
static func _all_planets() -> Dictionary:
	var out: Dictionary = CORE_PLANETS.duplicate(true)
	out.merge(SystemBuilder.suns(out))
	out.merge(SystemBuilder.planets(out))   # v1.4l: every planet has at least one tile
	return out
const CORE_PLANETS := {
	"new_terra": {"name": "New Terra", "system": "solara", "grid": 3,
		"tiles": ["ocean", "coast", "desert", "mountains", "city", "forest", "ice", "industrial", "canyon"],
		"locations": [
			{"id": "port_meridian", "name": "Port Meridian", "kind": "planet", "role": "Capital city", "tile": 4, "pos": Vector2(0, 600),
				"desc": "New Terra's capital. Shipyards, traders and the colonial government."},
			{"id": "saltmarsh", "name": "Saltmarsh Docks", "kind": "planet", "role": "Coastal trade city", "tile": 1, "pos": Vector2(-700, 300),
				"desc": "Fishing fleets and cargo haulers on the northern coast."},
			{"id": "dust_flats", "name": "Dust Flats Colony", "kind": "planet", "role": "Mining colony", "tile": 2, "pos": Vector2(400, -500),
				"desc": "Ore diggers in the red desert. Raiders like their payroll."},
			{"id": "ridgeback", "name": "Ridgeback Base", "kind": "planet", "role": "Military base", "tile": 3, "pos": Vector2(-300, 0),
				"desc": "Unity garrison high in the western range."},
			{"id": "iron_foundry", "name": "Iron Foundry", "kind": "planet", "role": "Mission zone", "tile": 7, "pos": Vector2(500, 400),
				"desc": "Abandoned smelters. Pirates hide gunships in the stacks."},
		],
		# capital city prototype (scripts/city.gd): one test block on flattened ground in the city sector, ~1 km
		# north-west of Port Meridian. The rest of the planet keeps its own biomes.
		"city_blocks": [{"id": "capital_block", "name": "Capital Test Block", "tile": 4, "pos": Vector2(-700, -250)}]},
	# Stars you can fly into (the sun sphere in space is the way in). One small tile that wraps onto itself, nothing on
	# it yet. "sun": the heat drains shield then hull unless the ship has a heat shield (see space.gd).
	"solara_sun": {"name": "Solara's Star", "system": "solara", "grid": 1, "tiles": ["sun"], "locations": [], "sun": true},
	"vega_sun": {"name": "Vega's Star", "system": "vega", "grid": 1, "tiles": ["sun"], "locations": [], "sun": true},
	"eden_prime": {"name": "Eden Prime", "system": "vega", "grid": 2,
		"tiles": ["jungle", "coast", "volcanic", "jungle"],
		"locations": [
			{"id": "verdant_terrace", "name": "Verdant Terrace", "kind": "planet", "role": "Spaceport city", "tile": 1, "pos": Vector2(0, 300),
				"desc": "Terraced landing pads above the jungle canopy."},
			{"id": "ashfall", "name": "Ashfall Outpost", "kind": "planet", "role": "Mission zone", "tile": 2, "pos": Vector2(-400, -300),
				"desc": "Research station on the lava plains. Corsairs raid it."},
		]},
}

static var _noise := {}   # planet id -> FastNoiseLite
static var _ridge := {}
static var _mesh_cache := {} # "planet|tile" -> ArrayMesh

static func is_sun(planet_id: String) -> bool:
	return bool(PLANETS.get(planet_id, {}).get("sun", false))

static func has_surface(planet_id: String) -> bool:
	return PLANETS.has(planet_id)

static func grid(planet_id: String) -> int:
	return int(PLANETS[planet_id]["grid"])

static func biome(planet_id: String, tile: int) -> Dictionary:
	return BIOMES[PLANETS[planet_id]["tiles"][tile]]

static func tile_name(planet_id: String, tile: int) -> String:
	var g := grid(planet_id)
	return "%s · SECTOR %s%d · %s" % [PLANETS[planet_id]["name"].to_upper(), "ABCDEFG"[tile / g], tile % g + 1, biome(planet_id, tile)["name"].to_upper()]

## Neighbour across an edge, wrapping around (dir: Vector2i(±1,0) east/west, (0,±1) south/north).
static func neighbour(planet_id: String, tile: int, dir: Vector2i) -> int:
	var g := grid(planet_id)
	var c := posmod(tile % g + dir.x, g)
	var r := posmod(tile / g + dir.y, g)
	return r * g + c

## Which tile you fall into when entering from space at `d` (unit vector from the planet centre).
static func tile_from_direction(planet_id: String, d: Vector3) -> int:
	var g := grid(planet_id)
	var lon := atan2(d.x, d.z)
	var lat := asin(clampf(d.y, -1.0, 1.0))
	var c := clampi(int(floor((lon + PI) / TAU * g)), 0, g - 1)
	var r := clampi(int(floor((0.5 - lat / PI) * g)), 0, g - 1)
	return r * g + c

## Where inside that tile (local x east, z south, metres) the entry point lies, so you come out over the same spot.
static func local_from_direction(planet_id: String, d: Vector3) -> Vector2:
	var g := grid(planet_id)
	var lon := atan2(d.x, d.z)
	var lat := asin(clampf(d.y, -1.0, 1.0))
	var fx := clampf((lon + PI) / TAU * g, 0.0, g - 0.001)
	var fz := clampf((0.5 - lat / PI) * g, 0.0, g - 0.001)
	return Vector2((fx - floorf(fx) - 0.5) * TILE * 0.9, (fz - floorf(fz) - 0.5) * TILE * 0.9)

## The reverse: which way out of the planet a tile faces (for climbing back to orbit).
static func direction_from_tile(planet_id: String, tile: int) -> Vector3:
	var g := grid(planet_id)
	var lon := (float(tile % g) + 0.5) / g * TAU - PI
	var lat := (0.5 - (float(tile / g) + 0.5) / g) * PI * 0.8
	return Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat)).normalized()

static func locations_in(planet_id: String, tile: int) -> Array:
	return PLANETS[planet_id]["locations"].filter(func(l): return int(l["tile"]) == tile)

static func location(planet_id: String, loc_id: String) -> Dictionary:
	for l in PLANETS[planet_id]["locations"]:
		if l["id"] == loc_id: return l
	return {}

static func _n(planet_id: String) -> FastNoiseLite:
	if not _noise.has(planet_id):
		var n := FastNoiseLite.new()
		n.seed = hash(planet_id)
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.00042
		n.fractal_octaves = 5
		_noise[planet_id] = n
		var r := FastNoiseLite.new()
		r.seed = hash(planet_id) + 7
		r.frequency = 0.0006
		r.fractal_type = FastNoiseLite.FRACTAL_RIDGED
		r.fractal_octaves = 4
		_ridge[planet_id] = r
	return _noise[planet_id]

## Ground height at local tile coordinates (x east, z south of the tile centre).
static func height(planet_id: String, tile: int, x: float, z: float) -> float:
	var g := grid(planet_id)
	return sample(planet_id, float(tile % g) * TILE + x, float(tile / g) * TILE + z)[0]

## Height and colour anywhere on the planet (planet metres; tile c's centre is at c * TILE).
## Seamless everywhere by construction:
##  - one noise field for the whole planet, and across the wrap line (east of the last column = column 0) the noise
##    is cross-faded with its copy one planet-width away, so the heights meet exactly;
##  - each biome is pure in the middle 60 % of its tile and blends into its neighbour's shape and colour over the
##    outer 20 % on each side, so crossing a border never shows a cliff or colour line.
## Returns [height, Color (alpha = how much of the ground texture's own colour to show)].
static func sample(planet_id: String, gx: float, gz: float) -> Array:
	var g := grid(planet_id)
	var wp := float(g) * TILE
	var u := fposmod(gx + EDGE, wp)
	var w := fposmod(gz + EDGE, wp)
	var bz := TILE * 0.5
	var su := _smooth((u - (wp - bz)) / bz)
	var sw := _smooth((w - (wp - bz)) / bz)
	var nr := _nr(planet_id, u, w) * (1.0 - su) * (1.0 - sw)
	if su > 0.0: nr += _nr(planet_id, u - wp, w) * su * (1.0 - sw)
	if sw > 0.0: nr += _nr(planet_id, u, w - wp) * (1.0 - su) * sw
	if su > 0.0 and sw > 0.0: nr += _nr(planet_id, u - wp, w - wp) * su * sw
	# biome weights from the four nearest tile centres
	var cx := u / TILE - 0.5
	var cz := w / TILE - 0.5
	var c0 := floori(cx)
	var r0 := floori(cz)
	var tx := _smooth((cx - c0 - 0.3) / 0.4)
	var tz := _smooth((cz - r0 - 0.3) / 0.4)
	var h := 0.0
	var col := Color(0, 0, 0, 0)
	for k in 4:
		var wx := tx if k % 2 == 1 else 1.0 - tx
		var wz := tz if k >= 2 else 1.0 - tz
		var wt := wx * wz
		if wt <= 0.0001: continue
		var t := posmod(r0 + (1 if k >= 2 else 0), g) * g + posmod(c0 + (k % 2), g)
		var hb: Array = _biome_height(biome(planet_id, t), nr.x, nr.y)
		h += hb[0] * wt
		col += (hb[1] as Color) * wt
	# flatten the ground under settlements (looked up in the tile that contains this point)
	var tc := (floori(w / TILE) % g) * g + floori(u / TILE) % g
	var lx := u - floorf(u / TILE) * TILE - EDGE
	var lz := w - floorf(w / TILE) * TILE - EDGE
	for l in locations_in(planet_id, tc):
		var d := Vector2(lx, lz).distance_to(l["pos"])
		if d < 900.0:
			var kk := clampf((d - 450.0) / 450.0, 0.0, 1.0)
			h = lerpf(pad_height(planet_id, tc), h, kk * kk)
	for cb in city_blocks_in(planet_id, tc):
		var d2 := Vector2(lx, lz).distance_to(cb["pos"])
		if d2 < CITY_FLAT + 300.0:
			var k2 := clampf((d2 - CITY_FLAT) / 300.0, 0.0, 1.0)
			h = lerpf(pad_height(planet_id, tc), h, k2 * k2)
	return [h, col]

const CITY_FLAT := 380.0   # fully flat radius under a city block (the test block's plaza is 440 x 520 m)

static func city_blocks_in(planet_id: String, tile: int) -> Array:
	return PLANETS[planet_id].get("city_blocks", []).filter(func(c): return int(c["tile"]) == tile)

static var _block_cache := {}
## The capital test block standing on its flattened ground (plaza top just above the terrain).
static func capital_block(planet_id: String, tile: int, cb: Dictionary) -> Node3D:
	if not _block_cache.has(cb["id"]): _block_cache[cb["id"]] = City.test_block()
	var block: Dictionary = _block_cache[cb["id"]]
	var n := City.instantiate(block)
	var pc: Vector3 = (block["plaza"] as AABB).get_center()
	n.position = Vector3(cb["pos"].x - pc.x, pad_height(planet_id, tile) + 0.3, cb["pos"].y - pc.z)
	n.name = "CapitalBlock"
	n.set_meta("block", block)
	return n

static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _nr(planet_id: String, x: float, z: float) -> Vector2:
	return Vector2(_n(planet_id).get_noise_2d(x, z), (_ridge[planet_id] as FastNoiseLite).get_noise_2d(x, z))

## One biome's height and colour from the shared noise (n: rolling, r: ridged).
static func _biome_height(b: Dictionary, n: float, r: float) -> Array:
	var amp: float = b["amp"]
	var base: float = b["base"]
	var h: float
	if b.get("terrace", false):
		# canyon country: flat-topped mesas in steps with sheer walls, winding river channels on the floor
		var v := clampf(n * 0.62 + 0.5 + maxf(0.0, r) * 0.25, 0.0, 1.0)
		var t := clampf((v - 0.4) / 0.6, 0.0, 1.0) * 3.0
		var stepped := floorf(t) + _smooth((t - floorf(t) - 0.6) / 0.4)
		h = base + stepped / 3.0 * amp
		if v < 0.4: h = base - 70.0 * _smooth((0.4 - v) / 0.12)
	else:
		# v1.5h: ridges squared (rounded crests instead of needles), a bigger share for mountain country, and the
		# highest ground eased off so peaks broaden instead of spiking
		var rr := maxf(0.0, r)
		var ridge: float = Data.TERRAIN_RIDGE_HIGH if amp >= Data.TERRAIN_RIDGE_AMP else Data.TERRAIN_RIDGE_LOW
		var lift := n * amp + rr * rr * amp * ridge * 2.0
		var cap: float = amp * Data.TERRAIN_PEAK_EASE
		if lift > cap: lift = cap + (lift - cap) * 0.45
		h = base + lift
	var lo := base - amp * (0.2 if b.get("terrace", false) else 0.6)
	var hi := base + amp * 1.1
	var k := clampf((h - lo) / maxf(1.0, hi - lo), 0.0, 1.0)
	var c: Color = (b["low"] as Color).lerp(b["mid"], clampf(k * 2.0, 0.0, 1.0)) if k < 0.5 else (b["mid"] as Color).lerp(b["high"], clampf(k * 2.0 - 1.0, 0.0, 1.0))
	c.a = float(b.get("detail", 0.0))
	return [h, c]

static func pad_height(planet_id: String, tile: int) -> float:
	var b := biome(planet_id, tile)
	return maxf(float(b["base"]) + 25.0, 30.0 if b["sea"] != null else -INF)

## Water shows in a tile if it or a neighbour has sea (so blended shorelines near borders stay wet). Sea level is 0.
static func has_water(planet_id: String, tile: int) -> bool:
	if biome(planet_id, tile)["sea"] != null: return true
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if biome(planet_id, neighbour(planet_id, tile, d))["sea"] != null: return true
	return false

# ---------------------------------------------------------------- v1.5h water
## The sea: rolling waves (sums of moving sines, no textures), deep water darker than the shallows, a turquoise rim
## and white foam where it meets the land (the depth below each vertex is baked into the mesh's colour), the sky in it
## at low angles (fresnel) and a sun glint. Works in the gl_compatibility renderer (no depth or screen texture).
const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;
uniform vec3 deep_col : source_color = vec3(0.03, 0.16, 0.3);
uniform vec3 shallow_col : source_color = vec3(0.12, 0.5, 0.55);
uniform vec3 sky_col : source_color = vec3(0.6, 0.75, 0.9);
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.3);
uniform float wave_h = 1.6;
uniform float wave_speed = 1.0;
uniform float foam_depth = 7.0;
uniform float shallow_depth = 45.0;
varying float depth;
varying vec3 wpos;
float wave(vec2 p, vec2 d, float f, float sp, float t) { return sin(dot(p, d) * f + t * sp); }
float waves(vec2 p, float t) {
	return wave(p, normalize(vec2(1.0, 0.3)), 0.021, 1.1, t) * 0.5 + wave(p, normalize(vec2(-0.4, 1.0)), 0.034, 1.5, t) * 0.3
		+ wave(p, normalize(vec2(0.7, -0.8)), 0.061, 2.2, t) * 0.15 + wave(p, normalize(vec2(-1.0, -0.2)), 0.13, 3.1, t) * 0.06;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = COLOR.r * 255.0;
	float t = TIME * wave_speed;
	VERTEX.y += waves(wpos.xz, t) * wave_h * clamp(depth / 12.0, 0.15, 1.0);
}
void fragment() {
	float t = TIME * wave_speed;
	vec2 p = wpos.xz;
	float e = 1.5;
	float hx = waves(p + vec2(e, 0.0), t) - waves(p - vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t) - waves(p - vec2(0.0, e), t);
	// fine ripples on top of the swell
	float r1 = sin(p.x * 0.37 + p.y * 0.21 + t * 4.0) + sin(p.x * -0.29 + p.y * 0.41 + t * 3.3);
	vec3 n = normalize(vec3(-hx * wave_h * 0.6 - r1 * 0.03, 2.0 * e, -hz * wave_h * 0.6 - r1 * 0.03));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float sh = 1.0 - smoothstep(0.0, shallow_depth, depth);
	vec3 col = mix(deep_col, shallow_col, sh * sh);
	vec3 v = normalize(-VERTEX);
	float fres = pow(1.0 - clamp(dot(NORMAL, v), 0.0, 1.0), 4.0);
	col = mix(col, sky_col, fres * 0.75);
	// shore foam: a band at the waterline that breathes with the waves
	float fb = 1.0 - smoothstep(0.0, foam_depth, depth + sin(t * 1.3 + p.x * 0.05 + p.y * 0.04) * 1.5);
	float fn = 0.5 + 0.5 * sin(p.x * 0.9 + t * 2.0) * sin(p.y * 0.8 - t * 1.7);
	float foam = clamp(fb * (0.55 + 0.6 * fn), 0.0, 1.0);
	ALBEDO = mix(col, vec3(0.95, 0.97, 1.0), foam);
	ROUGHNESS = mix(0.08, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.78, 0.97, clamp(depth / shallow_depth, 0.0, 1.0)) + foam * 0.2;
	ALPHA = clamp(ALPHA, 0.0, 1.0);
}
"""
static var _water_shader: Shader
static func water_material(b: Dictionary) -> ShaderMaterial:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = _water_shader
	var wc: Color = b.get("water", Color(0.1, 0.3, 0.45))
	m.set_shader_parameter("deep_col", wc.darkened(0.45))
	m.set_shader_parameter("shallow_col", wc.lightened(0.25).lerp(Color(0.2, 0.7, 0.68), 0.35))
	m.set_shader_parameter("sky_col", (b.get("horizon", Color(0.7, 0.8, 0.9)) as Color))
	m.set_shader_parameter("wave_h", Data.WATER_WAVE_H)
	m.set_shader_parameter("wave_speed", Data.WATER_WAVE_SPEED)
	m.set_shader_parameter("foam_depth", Data.WATER_FOAM_DEPTH)
	m.set_shader_parameter("shallow_depth", Data.WATER_SHALLOW_DEPTH)
	return m

static var _water_cache := {}
## The sea's grid for one tile: WATER_GRID x WATER_GRID quads; each vertex's colour holds the sea depth below it
## (0..255 m in red), taken from the same height field as the terrain, so the foam sits exactly on the shoreline.
static func _water_mesh(planet_id: String, tile: int) -> ArrayMesh:
	var key := "%s|%d" % [planet_id, tile]
	if _water_cache.has(key): return _water_cache[key]
	var n: int = Data.WATER_GRID
	var size := TILE + MARGIN * 2.0
	var g := grid(planet_id)
	var ox := float(tile % g) * TILE
	var oz := float(tile / g) * TILE
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in n + 1:
		for i in n + 1:
			var x := -size * 0.5 + size * float(i) / float(n)
			var z := -size * 0.5 + size * float(j) / float(n)
			var gh: float = sample(planet_id, ox + x, oz + z)[0]
			verts.append(Vector3(x, 0.0, z))
			norms.append(Vector3.UP)
			cols.append(Color(clampf(-gh, 0.0, 255.0) / 255.0, 0, 0, 1))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_water_cache[key] = am
	return am

static var _terrain_mat: ShaderMaterial
static func terrain_material(strata: float) -> Material:
	if not ResourceLoader.exists("res://assets/terrain/ground_albedo.jpg"):
		# planet pack not mounted (download failed): plain vertex colours still fly fine
		var plain := StandardMaterial3D.new()
		plain.vertex_color_use_as_albedo = true
		plain.roughness = 0.95
		return plain
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = load("res://assets/terrain/terrain.gdshader")
		_terrain_mat.set_shader_parameter("detail_tex", load("res://assets/terrain/ground_albedo.jpg"))
		_terrain_mat.set_shader_parameter("detail_nrm", load("res://assets/terrain/ground_normal.png"))
		# big soft bumps: 'render clouds' noise baked into a tiling normal map at load time
		var nt := NoiseTexture2D.new()
		nt.width = 512
		nt.height = 512
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		var fn := FastNoiseLite.new()
		fn.frequency = 0.012
		fn.fractal_octaves = 5
		nt.noise = fn
		_terrain_mat.set_shader_parameter("cloud_nrm", nt)
	var m := _terrain_mat.duplicate() as ShaderMaterial
	m.set_shader_parameter("strata", strata if strata >= 0.0 else 0.1)
	return m

## Build everything visible in one tile under a new root node (terrain, water, settlements, landmarks).
static func build_tile(planet_id: String, tile: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Tile_%d" % tile
	var b := biome(planet_id, tile)
	var key := "%s|%d" % [planet_id, tile]
	if not _mesh_cache.has(key): _terrain_mesh(planet_id, tile)
	var terrain := MeshInstance3D.new()
	terrain.mesh = _mesh_cache[key]
	terrain.name = "Terrain"
	terrain.material_override = terrain_material(float(b.get("strata", 0.1)))
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(terrain)
	if has_water(planet_id, tile):
		var w := MeshInstance3D.new()
		if b.get("glow", false):   # magma: it gives off its own light (a flat glowing sea, as before)
			var pm := PlaneMesh.new()
			pm.size = Vector2(TILE + MARGIN * 2.0, TILE + MARGIN * 2.0)
			w.mesh = pm
			var wm := StandardMaterial3D.new()
			wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wm.albedo_color = Color(b["water"], 0.93)
			wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			w.material_override = wm
		else:
			w.mesh = _water_mesh(planet_id, tile)   # v1.5h: a grid that knows how deep the sea is at each point (shore foam, shallows)
			w.material_override = water_material(b)
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.position.y = 0.0
		w.name = "Water"
		root.add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for l in locations_in(planet_id, tile): _settlement(root, planet_id, tile, l, rng)
	for cb in city_blocks_in(planet_id, tile): root.add_child(capital_block(planet_id, tile, cb))
	for c in wrap_corners(planet_id, tile): _corner_cloud(root, planet_id, tile, c, rng)
	if PLANETS[planet_id]["tiles"][tile] in ["desert", "mountains", "wasteland", "volcanic", "industrial", "ice"]:
		_landmarks(root, planet_id, tile, rng)
	return root

static func _terrain_mesh(planet_id: String, tile: int) -> ArrayMesh:
	while not prepare(planet_id, tile, GRID_N + 1): pass
	return _mesh_cache["%s|%d" % [planet_id, tile]]

static var _jobs := {}   # "planet|tile" -> {row, hs: PackedFloat32Array, cols: PackedColorArray}

static func is_ready(planet_id: String, tile: int) -> bool:
	return _mesh_cache.has("%s|%d" % [planet_id, tile])

## Build a tile's terrain a few rows at a time (call every frame) so the next sector is ready before you reach it,
## without a hitch. Returns true when the mesh is in the cache.
static func prepare(planet_id: String, tile: int, rows: int) -> bool:
	var key := "%s|%d" % [planet_id, tile]
	if _mesh_cache.has(key): return true
	var n := GRID_N
	var size := TILE + MARGIN * 2.0
	var step := size / n
	var g := grid(planet_id)
	var ox := float(tile % g) * TILE
	var oz := float(tile / g) * TILE
	if not _jobs.has(key):
		var hs := PackedFloat32Array()
		hs.resize((n + 1) * (n + 1))
		var cols := PackedColorArray()
		cols.resize((n + 1) * (n + 1))
		_jobs[key] = {"row": 0, "hs": hs, "cols": cols}
	var job: Dictionary = _jobs[key]
	var hs2: PackedFloat32Array = job["hs"]
	var cols2: PackedColorArray = job["cols"]
	var j0: int = job["row"]
	for j in range(j0, mini(j0 + rows, n + 1)):
		for i in n + 1:
			var hc := sample(planet_id, ox - size * 0.5 + i * step, oz - size * 0.5 + j * step)
			var c: Color = hc[1]
			var jitter := 0.94 + 0.12 * fposmod(sin(i * 12.9898 + j * 78.233) * 43758.5453, 1.0)
			hs2[j * (n + 1) + i] = hc[0]
			cols2[j * (n + 1) + i] = Color(c.r * jitter, c.g * jitter, c.b * jitter, c.a)
	job["row"] = mini(j0 + rows, n + 1)
	job["hs"] = hs2
	job["cols"] = cols2
	if job["row"] <= n: return false
	_jobs.erase(key)
	_mesh_cache[key] = _assemble(hs2, cols2, n, size, step)
	if _mesh_cache.size() > 6: _mesh_cache.erase(_mesh_cache.keys()[0])   # keep only recent sectors in memory
	return true

## Height grid -> mesh, with normals and tangents worked out from the grid directly (fast, no SurfaceTool).
static func _assemble(hs: PackedFloat32Array, cols: PackedColorArray, n: int, size: float, step: float) -> ArrayMesh:
	var w := n + 1
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uvs := PackedVector2Array()
	verts.resize(w * w)
	nrm.resize(w * w)
	tan.resize(w * w * 4)
	uvs.resize(w * w)
	for j in w:
		for i in w:
			var k := j * w + i
			var x := -size * 0.5 + i * step
			var z := -size * 0.5 + j * step
			verts[k] = Vector3(x, hs[k], z)
			var hl := hs[j * w + maxi(i - 1, 0)]
			var hr := hs[j * w + mini(i + 1, n)]
			var hu := hs[maxi(j - 1, 0) * w + i]
			var hd := hs[mini(j + 1, n) * w + i]
			nrm[k] = Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			var tg := Vector3(2.0 * step, hr - hl, 0.0).normalized()
			tan[k * 4] = tg.x
			tan[k * 4 + 1] = tg.y
			tan[k * 4 + 2] = tg.z
			tan[k * 4 + 3] = -1.0
			uvs[k] = Vector2(x, z) * 0.014
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = _indices(n)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

static var _idx_cache: PackedInt32Array
static func _indices(n: int) -> PackedInt32Array:
	if _idx_cache.size() == n * n * 6: return _idx_cache
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var c := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			idx[c] = a
			idx[c + 1] = a + 1
			idx[c + 2] = a + n + 1
			idx[c + 3] = a + 1
			idx[c + 4] = a + n + 2
			idx[c + 5] = a + n + 1
			c += 6
	_idx_cache = idx
	return idx

## Corners of this tile that are the planet's wrap corner (where east/west and north/south wrapping meet).
## That one logical spot shows up in up to four tiles' corners; a cloud bank sits on it to cover the awkward corner.
static func wrap_corners(planet_id: String, tile: int) -> Array:
	var g := grid(planet_id)
	var c := tile % g
	var r := tile / g
	var out: Array = []
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			if ((sx < 0 and c == 0) or (sx > 0 and c == g - 1)) and ((sz < 0 and r == 0) or (sz > 0 and r == g - 1)):
				out.append(Vector2(sx * EDGE, sz * EDGE))
	return out

static var _cloud_tex: ImageTexture
## Cheap cloud bank: a few dozen soft billboards around a corner point (local coords), tinted by the biome.
static func _corner_cloud(root: Node3D, planet_id: String, tile: int, at: Vector2, rng: RandomNumberGenerator) -> void:
	if _cloud_tex == null:
		var nz := FastNoiseLite.new()
		nz.seed = 5
		nz.frequency = 0.05
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var d := Vector2(x - 63.5, y - 63.5).length() / 64.0
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = a * a * clampf(0.5 + nz.get_noise_2d(x, y), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_cloud_tex = ImageTexture.create_from_image(img)
	var b := biome(planet_id, tile)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = _cloud_tex
	m.albedo_color = Color((b["fog"] as Color).lerp(Color.WHITE, 0.45), 0.85)
	m.disable_fog = true   # bright cloud bank stays visible through the distance fog
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = 70
	var gy := maxf(height(planet_id, tile, clampf(at.x, -EDGE, EDGE), clampf(at.y, -EDGE, EDGE)), 0.0)
	for i in 70:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 1100.0
		var sz := rng.randf_range(380.0, 760.0)
		var p := Vector3(at.x + cos(ang) * r, gy + rng.randf_range(60.0, 750.0), at.y + sin(ang) * r)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sz, sz * 0.6, sz)), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "CornerCloud"
	root.add_child(mmi)

static var _box: BoxMesh
static var _cyl: CylinderMesh
static func _prims() -> void:
	if _box: return
	_box = BoxMesh.new()
	_cyl = CylinderMesh.new()
	_cyl.radial_segments = 12
	_cyl.rings = 1

## A settlement: landing pad (the dockable port) plus a cluster of buildings drawn with one MultiMesh.
static func _settlement(root: Node3D, planet_id: String, tile: int, l: Dictionary, rng: RandomNumberGenerator) -> void:
	_prims()
	var p2: Vector2 = l["pos"]
	var gy := pad_height(planet_id, tile)
	var role: String = l["role"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _box
	var count := 90 if role.contains("city") or role.contains("Capital") else 28
	mm.instance_count = count
	var solids: Array = root.get_meta("solids", [])
	var bm := StandardMaterial3D.new()
	bm.vertex_color_use_as_albedo = true
	bm.roughness = 0.6
	for i in count:
		var a := rng.randf() * TAU
		var r := rng.randf_range(160.0, 420.0)
		var w := rng.randf_range(30.0, 70.0)
		var h := rng.randf_range(30.0, 90.0) * (2.6 if role.contains("Capital") and r < 280.0 else 1.0)
		if role.contains("Military"): h = rng.randf_range(12.0, 30.0)
		if role.contains("Mission") and i % 5 == 0: h = rng.randf_range(120.0, 200.0)   # smoke stacks
		var pos := Vector3(p2.x + cos(a) * r, gy + h * 0.5, p2.y + sin(a) * r)
		var bxf := Transform3D(Basis.from_euler(Vector3(0, rng.randf() * PI, 0)).scaled(Vector3(w, h, w * rng.randf_range(0.6, 1.4))), pos)
		mm.set_instance_transform(i, bxf)
		solids.append(bxf * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE))   # simple collision: the box's bounds
		var shade := rng.randf_range(0.55, 0.9)
		mm.set_instance_color(i, Color(shade, shade * 0.98, shade * 0.95) if not role.contains("Military") else Color(0.35, 0.4, 0.32))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "Buildings_" + l["id"]
	root.add_child(mmi)
	root.set_meta("solids", solids)
	# the landing pad: flat disc with green guide lights
	var pad := MeshInstance3D.new()
	pad.mesh = _cyl
	pad.scale = Vector3(180, 1.5, 180)
	pad.position = Vector3(p2.x, gy + 1.5, p2.y)
	pad.material_override = ShipFactory.mat(Color(0.3, 0.33, 0.38), false, 0.3)
	root.add_child(pad)
	for i in 12:
		var a2 := i * TAU / 12.0
		var lm := MeshInstance3D.new()
		lm.mesh = _box
		lm.scale = Vector3(4, 2, 4)
		lm.position = Vector3(p2.x + cos(a2) * 84.0, gy + 4.0, p2.y + sin(a2) * 84.0)
		lm.material_override = ShipFactory.mat(Color(0.3, 1.0, 0.6), true)
		lm.set_meta("blink", i * 0.08)
		root.add_child(lm)

## Rock spires / ice pillars / stacks so open tiles still have landmarks to fly around (rocky biomes only).
static func _landmarks(root: Node3D, planet_id: String, tile: int, rng: RandomNumberGenerator) -> void:
	_prims()
	var b := biome(planet_id, tile)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var spire := CylinderMesh.new()   # tapered rock spire
	spire.top_radius = 0.18
	spire.bottom_radius = 0.6
	spire.radial_segments = 7
	spire.rings = 2
	mm.mesh = spire
	mm.instance_count = 24
	for i in 24:
		var x := rng.randf_range(-EDGE, EDGE)
		var z := rng.randf_range(-EDGE, EDGE)
		var gy := height(planet_id, tile, x, z)
		var h := rng.randf_range(120.0, 380.0)
		var r := rng.randf_range(20.0, 55.0)
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))).scaled(Vector3(r, h, r)), Vector3(x, gy + h * 0.45, z)))
		mm.set_instance_color(i, (b["high"] as Color).lerp(b["mid"], 0.5))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "Spires"
	root.add_child(mmi)
