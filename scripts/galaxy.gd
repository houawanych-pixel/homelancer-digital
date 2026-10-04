class_name Galaxy
extends RefCounted
## The travel network as lightweight DATA only (see docs/DESIGN.md §7–8). A system here is a few fields:
## id, name, position, cluster/faction, type, discovery and connections. Seeing 1,000 systems on the map never loads
## them; only systems listed in PLAYABLE have real content (Data.SYSTEMS), loaded when you travel there.
##
## Travel tiers: spaceway (in-system highway), warp (the ship), WARP GATE (built, system to system),
## JUMP GATE (natural corridor: nebula vortex / gravity rift, often hidden or unstable), RIFT GATE (rare, extreme range).

# galactic units between neighbouring tiles of the 11 x 11 map
const TILE := 24.0
const SHADE := {"Unity": 1, "Elyza": 3, "Solarion": 2, "Imperium": 4, "Covenant": 3, "Orion": 2, "Savagers": 2, "Liberator": 1,
	"Enemy": 4, "Neutral": 0, "Hidden": 4, "Void": 0, "Heart": 4}

# hand-made spaceways for the hand-made systems (body ids from Data.SYSTEMS)
const SPACEWAYS := {
	"solara": [["Liberty Spaceway", "station", "planet"], ["Aquila Lane", "station", "gate"]],
	"vega": [["Frontier Spaceway", "station", "planet"], ["Ice Run", "station", "gate"]],
}

static var _cache: Dictionary = {}
# region name, faction, centre: one label per faction, at the middle of its systems (filled by network())
static var CLUSTERS: Array = []

## Where a tile sits in the galaxy view: the map laid flat, north = -Z, with a little height so it reads in 3D.
static func tile_pos(col: int, row: int, id: String) -> Vector3:
	return Vector3((col - 5) * TILE, float(hash(id) % 17) - 8.0, (row - 5) * TILE)

## The whole network: {"systems": {id: {...}}, "links": [[a, b, kind], ...]}. Built once from the 11 x 11 map
## (GalaxyData). Every system on it can be flown to, so all are "playable"; nothing here loads art.
static func network() -> Dictionary:
	if not _cache.is_empty(): return _cache
	var systems := {}
	var sums := {}
	for t in GalaxyData.TILES:
		var id: String = t[0]
		var d: Dictionary = Data.SYSTEMS[id]
		var pos := tile_pos(t[3], t[4], id)
		systems[id] = {"id": id, "name": d["name"], "pos": pos, "cluster": t[5], "faction": t[5], "shade": SHADE.get(t[5], 0),
			"tile": t[2], "star": "small, cold" if t[5] == "Void" else "yellow", "planets": 1 + (d.get("more_planets", []) as Array).size(), "stations": 1 + (d.get("more_stations", []) as Array).size(),
			"spaceways": (SPACEWAYS.get(id, []) as Array).size(), "playable": true, "discovered": id in GS.discovered}
		if not sums.has(t[5]): sums[t[5]] = [Vector3.ZERO, 0]
		sums[t[5]][0] += pos
		sums[t[5]][1] += 1
	CLUSTERS = []
	for f in sums:
		if f in ["Neutral", "Void", "Hidden", "Heart", "Enemy"]: continue
		CLUSTERS.append([f, f, (sums[f][0] as Vector3) / float(sums[f][1]), TILE * 2.0, sums[f][1], SHADE[f]])
	var links: Array = []
	var seen := {}
	for id in Data.SYSTEMS:
		for g in Data.SYSTEMS[id]["gates"]:
			var a: String = id
			var b: String = g["to"]
			var key := a + "|" + b if a < b else b + "|" + a
			if seen.has(key): continue
			seen[key] = true
			links.append([a, b, str(g.get("gkind", "jump")) + "_gate"])
	_cache = {"systems": systems, "links": links}
	return _cache

## Call when a new system is charted, so the map shows it as discovered.
static func refresh() -> void:
	for id in _cache.get("systems", {}): _cache["systems"][id]["discovered"] = id in GS.discovered

static func links_of(id: String) -> Array:
	return network()["links"].filter(func(l): return l[0] == id or l[1] == id)

## Bodies to draw when a system is expanded: real ones for playable systems, survey placeholders for the rest.
static func bodies(id: String) -> Array:
	var out: Array = []
	if Data.SYSTEMS.has(id):
		var s: Dictionary = Data.SYSTEMS[id]
		out.append({"key": "station", "name": s["station"]["name"], "kind": "station", "pos": s["station"]["pos"]})
		out.append({"key": "planet", "name": s["planet"]["name"], "kind": "planet", "pos": s["planet"]["pos"]})
		for gi in (s["gates"] as Array).size():
			var g: Dictionary = s["gates"][gi]
			out.append({"key": "gate" if gi == 0 else "gate%d" % gi, "name": g["name"], "kind": "%s gate" % g.get("gkind", "jump"), "pos": g["pos"]})
		return out
	var sys: Dictionary = network()["systems"][id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for i in int(sys["planets"]):
		var a := rng.randf() * TAU
		var r := 900.0 + i * 700.0
		out.append({"key": "p%d" % i, "name": "%s %s" % [sys["name"], ["I", "II", "III", "IV", "V", "VI"][i]], "kind": "planet", "pos": Vector3(cos(a) * r, 0, sin(a) * r)})
	for i in int(sys["stations"]):
		var a2 := rng.randf() * TAU
		out.append({"key": "s%d" % i, "name": "Station %d" % (i + 1), "kind": "station", "pos": Vector3(cos(a2) * 1500.0, 0, sin(a2) * 1500.0)})
	return out
