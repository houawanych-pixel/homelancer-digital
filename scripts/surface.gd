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
const GRID_N := 112         # terrain quads per side
const EDGE := TILE * 0.5

# Biomes: height shape, colours by height, sky and fog. "sea" = water level (null = no water).
const BIOMES := {
	"ocean": {"name": "Open ocean", "amp": 260.0, "base": -140.0, "sea": 0.0, "low": Color(0.76, 0.7, 0.52), "mid": Color(0.3, 0.5, 0.28), "high": Color(0.45, 0.45, 0.42),
		"sky": Color(0.32, 0.55, 0.9), "horizon": Color(0.72, 0.82, 0.92), "fog": Color(0.7, 0.8, 0.9), "water": Color(0.08, 0.3, 0.5)},
	"coast": {"name": "Coastal city", "amp": 380.0, "base": 20.0, "sea": 0.0, "low": Color(0.8, 0.74, 0.55), "mid": Color(0.34, 0.55, 0.3), "high": Color(0.5, 0.5, 0.46),
		"sky": Color(0.3, 0.55, 0.92), "horizon": Color(0.78, 0.85, 0.92), "fog": Color(0.74, 0.82, 0.9), "water": Color(0.1, 0.34, 0.52)},
	"desert": {"name": "Desert", "amp": 420.0, "base": 40.0, "sea": null, "low": Color(0.86, 0.7, 0.45), "mid": Color(0.8, 0.58, 0.36), "high": Color(0.62, 0.42, 0.3),
		"sky": Color(0.45, 0.62, 0.9), "horizon": Color(0.95, 0.85, 0.7), "fog": Color(0.92, 0.82, 0.66)},
	"mountains": {"name": "Mountains", "amp": 1350.0, "base": 80.0, "sea": null, "low": Color(0.35, 0.48, 0.3), "mid": Color(0.45, 0.42, 0.38), "high": Color(0.95, 0.96, 1.0),
		"sky": Color(0.3, 0.5, 0.88), "horizon": Color(0.75, 0.82, 0.92), "fog": Color(0.72, 0.78, 0.88)},
	"city": {"name": "Capital city", "amp": 300.0, "base": 30.0, "sea": 0.0, "low": Color(0.55, 0.55, 0.5), "mid": Color(0.4, 0.52, 0.34), "high": Color(0.55, 0.52, 0.48),
		"sky": Color(0.34, 0.55, 0.88), "horizon": Color(0.8, 0.84, 0.9), "fog": Color(0.76, 0.8, 0.86), "water": Color(0.12, 0.32, 0.46)},
	"forest": {"name": "Forest", "amp": 520.0, "base": 60.0, "sea": 0.0, "low": Color(0.2, 0.4, 0.2), "mid": Color(0.14, 0.34, 0.16), "high": Color(0.36, 0.4, 0.3),
		"sky": Color(0.32, 0.52, 0.85), "horizon": Color(0.7, 0.8, 0.82), "fog": Color(0.62, 0.72, 0.7), "water": Color(0.1, 0.28, 0.3)},
	"ice": {"name": "Ice sheet", "amp": 600.0, "base": 60.0, "sea": 0.0, "low": Color(0.78, 0.86, 0.94), "mid": Color(0.9, 0.94, 1.0), "high": Color(1, 1, 1),
		"sky": Color(0.5, 0.65, 0.9), "horizon": Color(0.88, 0.92, 0.98), "fog": Color(0.86, 0.9, 0.96), "water": Color(0.2, 0.4, 0.55)},
	"industrial": {"name": "Industrial zone", "amp": 320.0, "base": 30.0, "sea": null, "low": Color(0.42, 0.4, 0.38), "mid": Color(0.36, 0.34, 0.3), "high": Color(0.5, 0.46, 0.4),
		"sky": Color(0.5, 0.5, 0.52), "horizon": Color(0.7, 0.64, 0.56), "fog": Color(0.62, 0.58, 0.52)},
	"wasteland": {"name": "Wasteland", "amp": 480.0, "base": 30.0, "sea": null, "low": Color(0.5, 0.42, 0.32), "mid": Color(0.42, 0.36, 0.3), "high": Color(0.3, 0.26, 0.24),
		"sky": Color(0.55, 0.5, 0.48), "horizon": Color(0.8, 0.66, 0.52), "fog": Color(0.72, 0.6, 0.5)},
	"jungle": {"name": "Alien jungle", "amp": 560.0, "base": 40.0, "sea": 0.0, "low": Color(0.16, 0.42, 0.28), "mid": Color(0.2, 0.5, 0.2), "high": Color(0.3, 0.36, 0.22),
		"sky": Color(0.36, 0.6, 0.68), "horizon": Color(0.7, 0.86, 0.72), "fog": Color(0.56, 0.74, 0.6), "water": Color(0.08, 0.3, 0.26)},
	"volcanic": {"name": "Volcanic", "amp": 900.0, "base": 40.0, "sea": null, "low": Color(0.14, 0.12, 0.12), "mid": Color(0.24, 0.18, 0.16), "high": Color(0.9, 0.35, 0.12),
		"sky": Color(0.35, 0.2, 0.18), "horizon": Color(0.8, 0.42, 0.25), "fog": Color(0.45, 0.3, 0.26)},
}

# Planets with surfaces. tiles: row-major biome list (row 0 = north). locations: named places you can land at /
# fast-travel to (pos = metres from the tile centre, x east, y south).
const PLANETS := {
	"new_terra": {"name": "New Terra", "system": "solara", "grid": 3,
		"tiles": ["ocean", "coast", "desert", "mountains", "city", "forest", "ice", "industrial", "wasteland"],
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
		]},
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
	var gx := float(tile % g) * TILE + x
	var gz := float(tile / g) * TILE + z
	var b := biome(planet_id, tile)
	var n := _n(planet_id).get_noise_2d(gx, gz)
	var r: float = (_ridge[planet_id] as FastNoiseLite).get_noise_2d(gx, gz)
	var h: float = float(b["base"]) + n * float(b["amp"]) + maxf(0.0, r) * float(b["amp"]) * (0.8 if b["amp"] > 800.0 else 0.25)
	# flatten the ground under each settlement
	for l in locations_in(planet_id, tile):
		var d := Vector2(x, z).distance_to(l["pos"])
		if d < 900.0:
			var k := clampf((d - 450.0) / 450.0, 0.0, 1.0)
			h = lerpf(pad_height(planet_id, tile), h, k * k)
	return h

static func pad_height(planet_id: String, tile: int) -> float:
	var b := biome(planet_id, tile)
	return maxf(float(b["base"]) + 25.0, 30.0 if b["sea"] != null else -INF)

## Build everything visible in one tile under a new root node (terrain, water, clouds, settlements, landmarks).
static func build_tile(planet_id: String, tile: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Tile_%d" % tile
	var b := biome(planet_id, tile)
	var key := "%s|%d" % [planet_id, tile]
	if not _mesh_cache.has(key): _mesh_cache[key] = _terrain_mesh(planet_id, tile)
	var terrain := MeshInstance3D.new()
	terrain.mesh = _mesh_cache[key]
	terrain.name = "Terrain"
	var tm := StandardMaterial3D.new()
	tm.vertex_color_use_as_albedo = true
	tm.roughness = 0.95
	terrain.material_override = tm
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(terrain)
	if b["sea"] != null:
		var w := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(TILE + MARGIN * 2.0, TILE + MARGIN * 2.0)
		w.mesh = pm
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(b["water"], 0.86)
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.metallic = 0.3
		wm.roughness = 0.15
		w.material_override = wm
		w.position.y = float(b["sea"])
		w.name = "Water"
		root.add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for l in locations_in(planet_id, tile): _settlement(root, planet_id, tile, l, rng)
	if PLANETS[planet_id]["tiles"][tile] in ["desert", "mountains", "wasteland", "volcanic", "industrial", "ice"]:
		_landmarks(root, planet_id, tile, rng)
	return root

static func _terrain_mesh(planet_id: String, tile: int) -> ArrayMesh:
	var b := biome(planet_id, tile)
	var n := GRID_N
	var size := TILE + MARGIN * 2.0
	var step := size / n
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := -size * 0.5 + i * step
			var z := -size * 0.5 + j * step
			hs[j * (n + 1) + i] = height(planet_id, tile, x, z)
	var lo: float = float(b["base"]) - float(b["amp"]) * 0.6
	var hi: float = float(b["base"]) + float(b["amp"]) * 1.1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n + 1:
		for i in n + 1:
			var h := hs[j * (n + 1) + i]
			var k := clampf((h - lo) / maxf(1.0, hi - lo), 0.0, 1.0)
			var c: Color = (b["low"] as Color).lerp(b["mid"], clampf(k * 2.0, 0.0, 1.0)) if k < 0.5 else (b["mid"] as Color).lerp(b["high"], clampf(k * 2.0 - 1.0, 0.0, 1.0))
			var jitter := 0.94 + 0.12 * fposmod(sin(i * 12.9898 + j * 78.233) * 43758.5453, 1.0)
			st.set_color(Color(c.r * jitter, c.g * jitter, c.b * jitter))
			st.add_vertex(Vector3(-size * 0.5 + i * step, h, -size * 0.5 + j * step))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + 1)
			st.add_index(a + n + 2)
			st.add_index(a + n + 1)
	st.generate_normals()
	return st.commit()

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
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(0, rng.randf() * PI, 0)).scaled(Vector3(w, h, w * rng.randf_range(0.6, 1.4))), pos))
		var shade := rng.randf_range(0.55, 0.9)
		mm.set_instance_color(i, Color(shade, shade * 0.98, shade * 0.95) if not role.contains("Military") else Color(0.35, 0.4, 0.32))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "Buildings_" + l["id"]
	root.add_child(mmi)
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
	mm.mesh = _cyl
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
