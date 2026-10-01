class_name Galaxy
extends RefCounted
## The travel network as lightweight DATA only (see docs/DESIGN.md §7–8). A system here is a few fields:
## id, name, position, cluster/faction, type, discovery and connections. Seeing 1,000 systems on the map never loads
## them; only systems listed in PLAYABLE have real content (Data.SYSTEMS), loaded when you travel there.
##
## Travel tiers: spaceway (in-system highway), warp (the ship), WARP GATE (built, system to system),
## JUMP GATE (natural corridor: nebula vortex / gravity rift, often hidden or unstable), RIFT GATE (rare, extreme range).

const PLAYABLE := ["solara", "vega"]

# region name, faction, centre (galactic units), spread, member count, shade index (0 pale .. 4 navy)
const CLUSTERS := [
	["Liberty Reach", "Unity", Vector3(0, 0, 0), 26.0, 8, 3],
	["Frontier Drift", "Independent", Vector3(95, 6, -40), 30.0, 10, 2],
	["Corsair Expanse", "Corsair clans", Vector3(60, -8, 85), 28.0, 8, 4],
	["Azure Veil", "Uncharted nebula", Vector3(-80, 10, 70), 24.0, 8, 1],
	["Core Worlds", "Unity Senate", Vector3(-90, -5, -75), 30.0, 12, 4],
	["Outer Rim", "Unknown", Vector3(10, 14, -150), 40.0, 10, 0],
]
const SYLL := ["al", "ar", "bel", "cor", "dra", "el", "fen", "gal", "hal", "ir", "kel", "lun", "mar", "nor", "or", "pra", "quin", "ros", "sel", "tor", "ul", "ver", "xan", "yor", "zen"]

# hand-made spaceways for the playable systems (body ids from Data.SYSTEMS)
const SPACEWAYS := {
	"solara": [["Liberty Spaceway", "station", "planet"], ["Aquila Lane", "station", "gate"]],
	"vega": [["Frontier Spaceway", "station", "planet"], ["Ice Run", "station", "gate"]],
}

static var _cache: Dictionary = {}

## The whole network: {"systems": {id: {...}}, "links": [[a, b, kind], ...]}. Built once from a fixed seed.
static func network() -> Dictionary:
	if not _cache.is_empty(): return _cache
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	var systems := {}
	var by_cluster: Array = []
	for ci in CLUSTERS.size():
		var c: Array = CLUSTERS[ci]
		var ids: Array = []
		for k in int(c[4]):
			var id := ""
			var nm := ""
			var pos := Vector3.ZERO
			if ci == 0 and k == 0:
				id = "solara"; nm = "Solara"; pos = c[2]
			elif ci == 0 and k == 1:
				id = "vega"; nm = "Vega"; pos = c[2] + Vector3(14, 2, -9)
			else:
				nm = (SYLL[rng.randi() % SYLL.size()] + SYLL[rng.randi() % SYLL.size()]).capitalize()
				if rng.randf() < 0.4: nm += " " + ["Prime", "Major", "Minor", "II", "IV", "Reach", "Gate"][rng.randi() % 7]
				id = "sys_%d_%d" % [ci, k]
				pos = (c[2] as Vector3) + Vector3(rng.randfn(0, c[3]), rng.randfn(0, c[3] * 0.25), rng.randfn(0, c[3]))
			systems[id] = {"id": id, "name": nm, "pos": pos, "cluster": c[0], "faction": c[1], "shade": c[5],
				"star": ["yellow", "white", "blue", "red dwarf", "binary"][rng.randi() % 5],
				"planets": rng.randi_range(1, 6), "stations": rng.randi_range(0, 3), "spaceways": rng.randi_range(0, 3),
				"playable": id in PLAYABLE, "discovered": id in PLAYABLE or (ci == 0 and rng.randf() < 0.5)}
			if id in PLAYABLE:   # real systems report their real contents
				systems[id]["planets"] = 1
				systems[id]["stations"] = 1
				systems[id]["spaceways"] = SPACEWAYS[id].size()
				systems[id]["star"] = "yellow" if id == "solara" else "blue-white"
			ids.append(id)
		by_cluster.append(ids)
	var links: Array = []
	var seen := {}
	var add := func(a: String, b: String, kind: String):
		var key := a + "|" + b if a < b else b + "|" + a
		if seen.has(key): return
		seen[key] = true
		links.append([a, b, kind])
	# warp gates: each system to its nearest neighbours inside its cluster (a connected, built network)
	for ids in by_cluster:
		for i in range(1, ids.size()):
			var best := ""
			var bd := INF
			for j in i:
				var d := (systems[ids[i]]["pos"] as Vector3).distance_to(systems[ids[j]]["pos"])
				if d < bd:
					bd = d
					best = ids[j]
			add.call(ids[i], best, "warp_gate")
		for k in maxi(1, ids.size() / 4):   # a few extra gates so the network has loops
			var a2: String = ids[rng.randi() % ids.size()]
			var b2: String = ids[rng.randi() % ids.size()]
			if a2 != b2: add.call(a2, b2, "warp_gate")
	add.call("solara", "vega", "warp_gate")
	# jump gates: natural corridors between neighbouring clusters (some hidden)
	for ci in by_cluster.size():
		for cj in range(ci + 1, by_cluster.size()):
			if (CLUSTERS[ci][2] as Vector3).distance_to(CLUSTERS[cj][2]) > 150.0: continue
			for k in 2:
				add.call(by_cluster[ci][rng.randi() % by_cluster[ci].size()], by_cluster[cj][rng.randi() % by_cluster[cj].size()], "jump_gate")
	# rift gates: a few very long links between region hubs
	add.call("solara", by_cluster[5][0], "rift_gate")
	add.call(by_cluster[4][0], by_cluster[2][0], "rift_gate")
	add.call(by_cluster[1][0], by_cluster[3][0], "rift_gate")
	_cache = {"systems": systems, "links": links}
	return _cache

static func links_of(id: String) -> Array:
	return network()["links"].filter(func(l): return l[0] == id or l[1] == id)

## Bodies to draw when a system is expanded: real ones for playable systems, survey placeholders for the rest.
static func bodies(id: String) -> Array:
	var out: Array = []
	if Data.SYSTEMS.has(id):
		var s: Dictionary = Data.SYSTEMS[id]
		out.append({"key": "station", "name": s["station"]["name"], "kind": "station", "pos": s["station"]["pos"]})
		out.append({"key": "planet", "name": s["planet"]["name"], "kind": "planet", "pos": s["planet"]["pos"]})
		out.append({"key": "gate", "name": s["gate"]["name"], "kind": "warp gate", "pos": s["gate"]["pos"]})
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
