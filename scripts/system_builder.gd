class_name SystemBuilder
extends RefCounted
## Builds every star system the game does not have by hand from the galaxy map tables (GalaxyData, generated from
## docs/galaxy). One generator, no copy-paste: each system gets a star, one station, one planet, an asteroid field, a
## nebula, patrols, and one gate per link on the map. Hand-made systems (Data.CORE_SYSTEMS) are kept as they are and
## only receive the extra gates the map gives them. Pure data: nothing here loads art.

# faction: star colour, sky tint, ambient light, station colour, enemy type
const FACTIONS := {
	"Unity": [Color(0.95, 0.97, 1.0), Color(0.04, 0.08, 0.14), Color(0.42, 0.47, 0.58), Color(0.78, 0.9, 0.96), "raider"],
	"Elyza": [Color(0.75, 0.85, 1.0), Color(0.03, 0.06, 0.16), Color(0.38, 0.44, 0.6), Color(0.45, 0.6, 0.95), "raider"],
	"Solarion": [Color(1.0, 0.82, 0.5), Color(0.12, 0.08, 0.04), Color(0.52, 0.46, 0.38), Color(0.95, 0.72, 0.3), "raider"],
	"Imperium": [Color(1.0, 0.6, 0.5), Color(0.13, 0.04, 0.05), Color(0.5, 0.38, 0.38), Color(0.75, 0.25, 0.28), "corsair"],
	"Covenant": [Color(0.85, 0.7, 1.0), Color(0.09, 0.04, 0.14), Color(0.46, 0.4, 0.56), Color(0.6, 0.4, 0.85), "corsair"],
	"Orion": [Color(0.7, 1.0, 0.75), Color(0.03, 0.11, 0.07), Color(0.38, 0.5, 0.42), Color(0.25, 0.7, 0.45), "corsair"],
	"Savagers": [Color(1.0, 0.7, 0.45), Color(0.13, 0.07, 0.03), Color(0.5, 0.42, 0.36), Color(0.78, 0.42, 0.2), "raider"],
	"Liberator": [Color(0.7, 1.0, 0.95), Color(0.03, 0.11, 0.11), Color(0.38, 0.5, 0.5), Color(0.3, 0.75, 0.72), "raider"],
	"Enemy": [Color(1.0, 0.45, 0.4), Color(0.06, 0.03, 0.05), Color(0.34, 0.32, 0.38), Color(0.3, 0.3, 0.34), "corsair"],
	"Neutral": [Color(1.0, 0.9, 0.75), Color(0.08, 0.07, 0.07), Color(0.44, 0.43, 0.44), Color(0.72, 0.66, 0.54), "raider"],
	"Hidden": [Color(0.9, 0.8, 1.0), Color(0.05, 0.03, 0.09), Color(0.4, 0.38, 0.5), Color(0.4, 0.35, 0.55), "corsair"],
	"Void": [Color(0.75, 0.8, 0.95), Color(0.02, 0.02, 0.04), Color(0.26, 0.28, 0.36), Color(0.35, 0.38, 0.45), "raider"],
	"Heart": [Color(1.0, 0.95, 0.75), Color(0.1, 0.06, 0.12), Color(0.5, 0.46, 0.52), Color(0.95, 0.88, 0.6), "raider"],
}
# gate kind: name on the gate, portal colour, distance from the system centre
const GATE_KINDS := {
	"jump": ["Jump Gate", Color(0.35, 0.95, 0.5), 3400.0],
	"warp": ["Warp Gate", Color(0.35, 0.65, 1.0), 4200.0],
	"rift": ["Rift Gate", Color(0.8, 0.4, 1.0), 4900.0],
}
const CENTRE := Vector3(0, 0, -1200)

static func all(core: Dictionary) -> Dictionary:
	var out: Dictionary = core.duplicate(true)
	var rows := {}
	for t in GalaxyData.TILES:
		rows[t[0]] = t
		if not out.has(t[0]): out[t[0]] = _system(t)
		out[t[0]]["tile"] = t[2]
		out[t[0]]["faction"] = t[5]
	for id in out:
		out[id]["more_planets"] = []
		out[id]["more_stations"] = []
	for id in out:
		if not out[id].has("gates"): out[id]["gates"] = [out[id]["gate"]] if out[id].has("gate") else []
		for g in out[id]["gates"]:
			if not g.has("gkind"): g["gkind"] = "jump"
	for g in GalaxyData.GATES:
		_link(out, rows, g[0], g[1], g[2])
		_link(out, rows, g[0], g[2], g[1])
	for id in out:
		if not out[id].has("gate"): out[id]["gate"] = out[id]["gates"][0]
	# the rest of each system from the catalog: placeholder planets and stations, spread round the system and kept
	# clear of everything already there (main planet, main station, gates, each other)
	for e in GalaxyData.EXTRAS:
		var sid: String = e[0]
		var sys: Dictionary = out[sid]
		var f: Array = FACTIONS[rows[sid][5]]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("homelancer:%s:%s" % [sid, e[2]])
		var is_planet: bool = e[1] == "planet"
		var k: int = (sys["more_planets"] if is_planet else sys["more_stations"]).size()
		var radius: float = Data.PH_STATION_RADIUS
		if is_planet: radius = rng.randf_range(Data.PH_GIANT_RADIUS[0], Data.PH_GIANT_RADIUS[1]) if e[3] == "gas" else rng.randf_range(Data.PH_PLANET_RADIUS[0], Data.PH_PLANET_RADIUS[1])
		var a0: float = atan2((sys["planet"]["pos"] as Vector3).z - CENTRE.z, (sys["planet"]["pos"] as Vector3).x - CENTRE.x) + (k + 1) * Data.PH_PLANET_ANGLE if is_planet else rng.randf() * TAU
		var pos := Vector3.ZERO
		for attempt in Data.PH_PLACE_TRIES:
			var a: float = a0 + attempt * 0.47
			var dist: float = (Data.PH_PLANET_DIST + Data.PH_PLANET_STEP * k + rng.randf_range(0.0, Data.PH_PLANET_JITTER)) if is_planet else (Data.PH_STATION_DIST + Data.PH_STATION_STEP * k + rng.randf_range(0.0, Data.PH_STATION_JITTER))
			var h: float = Data.PH_PLANET_HEIGHT if is_planet else Data.PH_STATION_HEIGHT
			pos = CENTRE + Vector3(cos(a) * dist, rng.randf_range(-h, h), sin(a) * dist)
			if clear_of(sys, pos, radius): break
		if is_planet:
			sys["more_planets"].append({"id": "%s_planet_%d" % [sid, k + 2], "name": e[2], "palette": e[3], "kind": "landmark", "placeholder": true,
				"pos": pos, "radius": radius, "desc": "%s world. Fly into the atmosphere to go down." % (e[3] as String).capitalize()})
		else:
			sys["more_stations"].append({"id": "%s_station_%d" % [sid, k + 2], "name": e[2], "kind": "landmark", "placeholder": true, "color": f[3],
				"pos": pos, "radius": radius, "desc": "Station. Placeholder: no docking yet."})
	return out

## Is a body of this radius at `pos` clear of everything already in the system? (tests use it too)
static func clear_of(sys: Dictionary, pos: Vector3, radius: float, skip_id := "") -> bool:
	var m: float = Data.PH_CLEARANCE
	if pos.distance_to(sys["planet"]["pos"]) < float(sys["planet"]["radius"]) * 1.15 + radius + m: return false
	if pos.distance_to(sys["station"]["pos"]) < 150.0 + radius + m: return false
	for g in sys["gates"]:
		if pos.distance_to(g["pos"]) < 140.0 + radius + m: return false
	for x in sys["more_planets"] + sys["more_stations"]:
		if x["id"] != skip_id and pos.distance_to(x["pos"]) < float(x["radius"]) + radius + m: return false
	return true

static func _system(t: Array) -> Dictionary:
	var id: String = t[0]
	var nm: String = t[1]
	var f: Array = FACTIONS[t[5]]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("homelancer:" + id)
	var void_sys: bool = t[5] == "Void"
	var a := rng.randf() * TAU
	var pr := 520.0 if void_sys else rng.randf_range(700.0, 980.0)
	var st_pos := Vector3(rng.randf_range(-500, 500), rng.randf_range(-60, 60), rng.randf_range(-700, -100))
	var pl_pos := CENTRE + Vector3(cos(a) * 1900.0, rng.randf_range(-320, 320), sin(a) * 1900.0)
	var a2 := a + rng.randf_range(1.6, 2.6)
	var a3 := a2 + rng.randf_range(1.4, 2.2)
	var sa := rng.randf() * TAU
	var station := {"id": id + "_station", "name": t[9], "pos": st_pos, "kind": "station", "color": f[3],
		"desc": "Automated beacon. No one lives out here." if void_sys else "%s station in the %s system." % [t[5], nm]}
	if t[6] == "capital": station["model"] = "wheel_station"
	var patrols: Array = []
	for i in 3:
		var pa := rng.randf() * TAU
		patrols.append(CENTRE + Vector3(cos(pa), 0, sin(pa)) * rng.randf_range(700.0, 2300.0) + Vector3(0, rng.randf_range(-80, 120), 0))
	return {
		"name": nm, "star": Color(0.8, 0.85, 1.0) if void_sys else f[0], "sky_tint": f[1], "ambient": f[2],
		"sun_dir": Vector3(cos(sa), -0.32, sin(sa)), "small_sun": void_sys, "role": t[6], "generated": true,
		"station": station,
		"planet": {"id": id + "_planet", "name": t[7], "pos": pl_pos, "radius": pr, "kind": "planet", "palette": t[8],
			"desc": "A dead, frozen world. Too cold to live on." if void_sys else "%s world of the %s system." % [(t[8] as String).capitalize(), nm]},
		"asteroids": {"name": "%s Belt" % nm, "center": CENTRE + Vector3(cos(a2) * 1300.0, 0, sin(a2) * 1300.0), "radius": 380.0,
			"count": 70 if void_sys else 130, "ice": t[8] in ["ice", "dead", "gas"]},
		"nebula": {"name": "%s Veil" % nm, "center": CENTRE + Vector3(cos(a3) * 1700.0, 40, sin(a3) * 1700.0), "radius": 460.0,
			"color": (f[0] as Color).lerp(f[3], 0.6)},
		"enemy": f[4], "patrols": patrols, "traffic": [[id + "_station", id + "_planet"]],
	}

## One gate in system `a` leading to `b`, set in the direction `b` lies on the map (north on the map = -Z in flight).
static func _link(out: Dictionary, rows: Dictionary, kind: String, a: String, b: String) -> void:
	for g in out[a]["gates"]:
		if g["to"] == b: return
	var ta: Array = rows[a]
	var tb: Array = rows[b]
	var dir := Vector3(float(tb[3] - ta[3]), 0, float(tb[4] - ta[4])).normalized()
	var k: Array = GATE_KINDS[kind]
	var n: int = out[a]["gates"].size()
	out[a]["gates"].append({"id": "%s_gate_%s" % [a, b], "name": "%s %s" % [tb[1], k[0]], "pos": CENTRE + dir * float(k[2]) + Vector3(0, 70.0 * n, 0),
		"to": b, "gkind": kind})

## Sun surfaces for every system (one looping tile each), merged into Surface.PLANETS.
static func suns(have: Dictionary) -> Dictionary:
	var out := {}
	for t in GalaxyData.TILES:
		var pid: String = t[0] + "_sun"
		if not have.has(pid): out[pid] = {"name": "%s's Star" % t[1], "system": t[0], "grid": 1, "tiles": ["sun"], "locations": [], "sun": true}
	return out


## v1.4l: a one-tile surface for every planet that has none yet (the main planet of each generated system and every
## catalog planet). One tile wraps onto itself, like the stars. The biome follows the planet type (Data.PLANET_BIOME),
## so a yellow world is yellow on the ground. Ids match the ones built above: <sys>_planet and <sys>_planet_<n>.
static func planets(have: Dictionary) -> Dictionary:
	var out := {}
	var count := {}
	for t in GalaxyData.TILES:
		count[t[0]] = 0
		if Data.CORE_SYSTEMS.has(t[0]): continue
		var pid: String = t[0] + "_planet"
		if not have.has(pid): out[pid] = {"name": t[7], "system": t[0], "grid": 1, "tiles": [Data.PLANET_BIOME.get(t[8], "barren")], "locations": []}
	for e in GalaxyData.EXTRAS:
		if e[1] != "planet": continue
		var k: int = count[e[0]]
		count[e[0]] = k + 1
		var pid2 := "%s_planet_%d" % [e[0], k + 2]
		if not have.has(pid2): out[pid2] = {"name": e[2], "system": e[0], "grid": 1, "tiles": [Data.PLANET_BIOME.get(e[3], "barren")], "locations": []}
	return out
