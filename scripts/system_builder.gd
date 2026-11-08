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

## v6.2 (owner): the open squares of the 11 x 11 board are real space too: a 1,000 km tile you fly through, with its
## own sky (art/sky_library spare_NN) and no gate. The ones touching an enemy home are that enemy's space (the galaxy
## draft's rule: the 8 squares round each enemy home): no spaceways, stronger patrols, an outpost you cannot dock at.
## Free squares hold only a nav beacon. Same row shape as GalaxyData.TILES.
static func open_rows() -> Array:
	var occ := {}
	var homes := []
	for t in GalaxyData.TILES:
		occ[Vector2i(int(t[3]), int(t[4]))] = true
		if str(t[6]).ends_with(" home") and t[5] == "Enemy": homes.append(t)
	var rows: Array = []
	var k := 0
	for row in 11:
		for col in 11:
			var c := Vector2i(col, row)
			if occ.has(c): continue
			var tile := "%s%d" % ["ABCDEFGHIJK"[col], row + 1]
			var holder := ""
			for h in homes:
				if absi(int(h[3]) - col) <= 1 and absi(int(h[4]) - row) <= 1 and holder == "": holder = str(h[6]).trim_suffix(" home")
			k += 1
			if holder != "":
				rows.append(["open_" + tile.to_lower(), "%s Space %s" % [holder, tile], tile, col, row, "Enemy", "held by " + holder,
					"Rogue Planetoid " + tile, "dead", "%s Outpost %s" % [holder, tile], k, holder])
			else:   # v6.5 (owner): the unknown areas: not on the map, strange names, no jump gates
				var nm: String = UNKNOWN_NAMES[(rows.filter(func(r): return r[6] == "unknown").size()) % UNKNOWN_NAMES.size()]
				rows.append(["open_" + tile.to_lower(), nm, tile, col, row, "Neutral", "unknown",
					nm + " Prime", ["ice", "dead", "toxic", "gas"][k % 4], "Lost Beacon " + tile, k, ""])
	return rows

static func is_enemy_space(sy: Dictionary) -> bool: return str(sy.get("faction", "")) == "Enemy"
static func is_unknown(sy: Dictionary) -> bool: return str(sy.get("role", "")) == "unknown"

## v12.68 (owner's spec: chart the uncharted squares): which zone an unknown square is (Data.ZONE_TYPES); "" if charted.
static func zone_of(sy: Dictionary) -> String:
	if not is_unknown(sy): return ""
	var t: String = str(sy.get("tile", sy.get("id", "")))
	var col := 0
	var row := 0
	if t.length() >= 2:
		col = "ABCDEFGHIJK".find(t[0].to_upper())
		row = t.substr(1).to_int() - 1
	return Data.ZONE_ORDER[posmod(col * 4 + row * 7, Data.ZONE_ORDER.size())]

## v12.68: who flies an uncharted zone's patrols (the zone's commonest unit; a brood keeps the old default)
static func _zone_enemy(tile: String, dflt) -> String:
	var zk := zone_of({"role": "unknown", "tile": tile})
	if zk == "brood" or (Data.ZONE_TYPES[zk]["units"] as Array).is_empty(): return str(dflt)
	return str(Data.ZONE_TYPES[zk]["units"][0])

## v6.5 (owner): names for the unknown areas (no lore, just strange)
const UNKNOWN_NAMES := ["Whisperfold", "The Hollow Reach", "Ninefold Drift", "Gloamwake", "Sable Expanse", "Umbral Tide",
	"The Quiet Maw", "Ashveil", "Lumen Sink", "Driftmother", "The Broken Choir", "Vesper Null", "Cinder Shoals",
	"The Pale Weave", "Mirelight", "Ossuary Wake", "Starless Fen", "The Unwritten", "Grimglass", "Thornhalo",
	"Echo Vault", "Silt of Ages", "The Murmur", "Wraithwater", "Blindspire Deep", "Hush Meridian", "Saltgrave",
	"The Last Lantern", "Coilshadow", "Veilmarrow", "Dusk Orchard", "The Folded Sky", "Ninth Absence", "Rimewhisper",
	"Gravecradle", "The Unlit Sea", "Nocturne Gap", "Hollowstar", "Sunken Halo", "The Long Static"]

## v6.5 (owner): the unknown areas' gates. No jump gates there: each unknown square has a WARP gate in a nebula cloud
## and its planet has a RIFT gate in a cloud on its surface. Gates move 3 squares (Pac-Man wrap), mostly into other
## unknown squares; only a few lead back to the charted systems, so finding the way home is hard.
## {"warp": {id: to}, "rift": {id: to}} ; rift = planet surface to planet surface (main planets).
static var _ulinks: Dictionary = {}
static func unknown_links() -> Dictionary:
	if not _ulinks.is_empty(): return _ulinks
	var cell := {}
	var at := {}
	var normal := {}
	for t in GalaxyData.TILES:
		at[t[0]] = Vector2i(int(t[3]), int(t[4]))
		cell[at[t[0]]] = t[0]
		if not (t[5] in ["Enemy", "Hidden"]) and not Data.CORE_SYSTEMS.has(t[0]): normal[t[0]] = true
	var unk: Array = []
	for t in open_rows():
		at[t[0]] = Vector2i(int(t[3]), int(t[4]))
		cell[at[t[0]]] = t[0]
		if t[6] == "unknown": unk.append(t[0])
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var reach := {"warp": Data.WARP_GATE_SQUARES, "rift": Data.RIFT_GATE_SQUARES}   # v6.5 (owner): warp 3-4 squares, rift 5-6
	var away := func(id: String, kind: String) -> Array:
		var out: Array = []
		for n in reach[kind]:
			for d in dirs:
				var c := Vector2i(posmod(at[id].x + d.x * n, 11), posmod(at[id].y + d.y * n, 11))
				if cell.has(c) and not (cell[c] in out): out.append(cell[c])
		return out
	var maps := {"warp": {}, "rift": {}}
	for kind in ["warp", "rift"]:
		var m: Dictionary = maps[kind]
		for u in unk:
			if m.has(u): continue
			var cand: Array = away.call(u, kind)
			var pick: Array = cand.filter(func(c): return c in unk and not m.has(c) and maps["warp"].get(u, "") != c)
			if pick.is_empty(): pick = cand.filter(func(c): return normal.has(c) and not m.has(c))
			if pick.is_empty(): continue
			m[u] = pick[0]
			m[pick[0]] = u
	# every group of unknown squares joined by gates has at least one way back to the charted systems
	var seen := {}
	for u in unk:
		if seen.has(u): continue
		var group := [u]
		var todo := [u]
		seen[u] = true
		while not todo.is_empty():
			var x: String = todo.pop_back()
			for kind in ["warp", "rift"]:
				var y: String = maps[kind].get(x, "")
				if y in unk and not seen.has(y):
					seen[y] = true
					group.append(y)
					todo.append(y)
		var exits: bool = group.any(func(g): return normal.has(maps["warp"].get(g, "")) or normal.has(maps["rift"].get(g, "")))
		if exits: continue
		for g in group:   # an extra warp gate out of this pocket
			var out: Array = away.call(g, "warp").filter(func(c): return normal.has(c))
			if out.is_empty(): continue
			maps["warp2"] = maps.get("warp2", {})
			maps["warp2"][g] = out[0]
			break
	_ulinks = maps
	return _ulinks

## The planet a planet-surface rift gate on this planet leads to ("" = none). Main planets only (<system>_planet).
static func planet_rift(pid: String) -> String:
	if not pid.ends_with("_planet"): return ""
	var sid := pid.trim_suffix("_planet")
	var to: String = unknown_links()["rift"].get(sid, "")
	return (to + "_planet") if to != "" else ""

static func all(core: Dictionary) -> Dictionary:
	var out: Dictionary = core.duplicate(true)
	var rows := {}
	for t in GalaxyData.TILES:
		rows[t[0]] = t
		if not out.has(t[0]): out[t[0]] = _system(t)
		out[t[0]]["tile"] = t[2]
		out[t[0]]["faction"] = t[5]
	for t in open_rows():   # v6.2: the open squares
		rows[t[0]] = t
		var o := _system(t)
		o["tile"] = t[2]
		o["faction"] = t[5]
		o["open"] = true
		o["sky_file"] = "spare_%02d" % int(t[10])
		o["traffic"] = []
		o["station"]["nodock"] = true
		if t[11] != "":   # an enemy's space: its home's fleet and people patrol it
			var role: String = str(t[11]) + " home"
			o["held_by"] = t[11]
			o["enemy_ships"] = Data.HOME_FLEETS.get(role, Data.ENEMY_SPACE_FLEET)
			o["enemy_faction"] = Data.HOME_FACTION.get(role, "")
			o["station"]["model"] = Data.ENEMY_OUTPOST_MODEL
		out[t[0]] = o
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
	var ul := unknown_links()   # v6.5: the unknown areas' warp gates (two-way, 3 squares, wrapping)
	for a in ul["warp"]: _link(out, rows, "warp", a, ul["warp"][a], true)
	for a in ul.get("warp2", {}):
		_link(out, rows, "warp", a, ul["warp2"][a], true)
		_link(out, rows, "warp", ul["warp2"][a], a, true)
	for id in out:
		if not out[id].has("gate"): out[id]["gate"] = out[id]["gates"][0] if not out[id]["gates"].is_empty() else {}
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
	spread(out)
	clear_lanes(out)   # v1.5m: the freeways never run through the rocks
	return out

## v11.65: a map square [column, row] (A = 1 across, 1 down; 5.5 = the middle of E) as a point in the system.
static func cell_pos(c: Array, y := 0.0) -> Vector3:
	var w: float = 2.0 * Data.SPACE_EDGE / float(Data.MAP_CELLS)
	return Vector3((float(c[0]) - 1.0) * w - Data.SPACE_EDGE, y, (float(c[1]) - 1.0) * w - Data.SPACE_EDGE)

## v11.65 (owner): the hand-made layouts (Data.SYSTEM_LAYOUT): the star, moved planets and stations, the gates pushed out,
## the extra clouds, the choke points and the lane plan. Runs last, after the roles are placed.
static func apply_layouts(systems: Dictionary) -> void:
	var all := auto_layouts(systems)   # v11.94 (owner: "every system should have all the development basics"): made for the rest
	for k in Data.SYSTEM_LAYOUT: all[k] = Data.SYSTEM_LAYOUT[k]
	for sid in all:
		if not systems.has(sid): continue
		var sy: Dictionary = systems[sid]
		var L: Dictionary = all[sid]
		# v11.91 (owner: Solara, the starting system): the hub, the main planet, the belt and the main nebula by hand too,
		# and planets added to the system (they come in already grown)
		if L.has("hub"): sy["station"]["pos"] = cell_pos(L["hub"], (sy["station"]["pos"] as Vector3).y)
		if L.has("planet"): sy["planet"]["pos"] = cell_pos(L["planet"], (sy["planet"]["pos"] as Vector3).y)
		if L.has("belt") and sy.has("asteroids"): sy["asteroids"]["center"] = cell_pos(L["belt"])
		if L.has("nebula") and sy.has("nebula"): sy["nebula"]["center"] = cell_pos(L["nebula"])
		for ap: Dictionary in L.get("add_planets", []):
			if (sy.get("more_planets", []) as Array).any(func(x): return str(x["name"]) == str(ap["name"])): continue
			sy["more_planets"].append({"id": "%s_%s" % [sid, str(ap["name"]).to_lower().replace(" ", "_")], "name": str(ap["name"]), "palette": str(ap["palette"]),
				"kind": "landmark", "placeholder": true, "pos": cell_pos(ap["at"], float(ap.get("y", 0.0))), "radius": float(ap["radius"]) * Data.PLANET_GROW,
				"desc": str(ap.get("desc", "%s world. Fly into the atmosphere to go down." % str(ap["palette"]).capitalize()))})
		if L.has("spy") and not sy.has("spy"): sy["spy"] = L["spy"]
		for ast: Dictionary in L.get("add_stations", []):   # v11.94: a faction's own outposts placed by hand
			if (sy.get("more_stations", []) as Array).any(func(x): return str(x["name"]) == str(ast["name"])): continue
			sy["more_stations"].append({"id": "%s_%s" % [sid, str(ast["name"]).to_lower().replace(" ", "_")], "name": str(ast["name"]), "catalog_name": str(ast["name"]),
				"kind": "station", "placeholder": false, "color": Color(0.5, 0.5, 0.55), "pos": cell_pos(ast["at"], float(ast.get("y", 0.0))), "radius": Data.PH_STATION_RADIUS,
				"model": str(ast["model"]), "faction": str(ast["faction"]), "role": str(ast.get("role", "outpost")), "hidden": bool(ast.get("hidden", false)), "tint": ast.get("tint", Color.WHITE),
				"desc": str(ast.get("desc", "%s station." % str(ast["faction"]))), "retopo_added": true})
		if L.has("sun"):
			var sp := cell_pos(L["sun"])
			sy["sun_center"] = false
			sy["sun_dir"] = -sp.normalized()
			sy["sun_dist"] = sp.length()
		for x in sy.get("more_planets", []):
			if (L.get("planets", {}) as Dictionary).has(str(x["name"])): x["pos"] = cell_pos(L["planets"][str(x["name"])], (x["pos"] as Vector3).y)
		for x in sy.get("more_stations", []):
			if (L.get("stations", {}) as Dictionary).has(str(x["name"])): x["pos"] = cell_pos(L["stations"][str(x["name"])], (x["pos"] as Vector3).y)
		var st: Vector3 = sy["station"]["pos"]
		var k: float = float(L.get("gate_push", 1.0))
		var lim: float = Data.SPACE_EDGE * Data.PLACE_EDGE
		for g in sy["gates"]:
			var p: Vector3 = st + ((g["pos"] as Vector3) - st) * k
			if (L.get("gates", {}) as Dictionary).has(str(g["to"])): p = cell_pos(L["gates"][str(g["to"])], p.y)   # v11.69: set by hand
			g["pos"] = Vector3(clampf(p.x, -lim, lim), p.y, clampf(p.z, -lim, lim))
		var clouds: Array = []
		for c in L.get("clouds", []):
			clouds.append({"name": str(c["name"]), "center": cell_pos(c["at"]), "radius": float(c["radius"]), "color": c["color"], "main": false, "weather": str(c.get("weather", "storm")), "layout": true, "disturbance": bool(c.get("disturbance", false))})
		sy["layout_clouds"] = clouds
		var j := {}
		for jn in L.get("junctions", {}): j[jn] = cell_pos(L["junctions"][jn])
		sy["junctions"] = j
		sy["lane_plan"] = (L.get("lanes", []) as Array).duplicate(true)
		if sid in REGRID: _regrid(sy)
	# v12.3 (owner: "nothing should ever be placed on that first border tile on any map ... only a nebula cloud"):
	# every station, planet, gate and choke point of every system is kept inside the border squares
	for sid in systems: keep_off_border(systems[sid])
	# v11.99 (owner: "they don't even have jump gates; the only way into their world is through rift gates or warp
	# gates"): every gate into or out of always-hostile alien space is a warp gate (a rift stays a rift)
	for sid in systems:
		var sy: Dictionary = systems[sid]
		for g in sy.get("gates", []):
			var to: String = str(g.get("to", ""))
			if str(g.get("gkind", "jump")) != "jump" or not systems.has(to): continue
			if is_enemy_space(sy) or is_enemy_space(systems[to]):
				g["gkind"] = "warp"
				g["name"] = str(g["name"]).replace("Jump Gate", "Warp Gate")

## v11.94 (owner: "every one of these systems needs redesign ... better trade lanes, more activity, more nebula, clouds,
## asteroids ... there shouldn't be something so simple like a sun, a planet, 2 gates, done"). For every system without a
## hand layout (and not unknown / void space) this works out the same basics Dreadholm and Solara have, in map squares:
## the gates in off the edge squares, a second world, the faction's ally station and a hidden rival post in a nebula
## (a spy at the hub), clouds and asteroid fields (one each on the edge squares, more inside), and a lane network that
## runs through choke points to every place, kept off the star and the rocks. Seeded by the system id: the same every time.
const MAJORS := ["Elyza", "Unity", "Solarion", "Imperium", "Covenant", "Orion", "Savagers", "Liberator"]
const ALLIES := {"Orion": "Covenant", "Covenant": "Orion", "Unity": "Liberator", "Liberator": "Unity", "Imperium": "Savagers",
	"Savagers": "Imperium", "Elyza": "Solarion", "Solarion": "Elyza"}
const CLOUD_COLS := [Color(0.55, 0.3, 0.85), Color(0.3, 0.6, 0.95), Color(0.85, 0.45, 0.3), Color(0.4, 0.8, 0.6), Color(0.85, 0.75, 0.4), Color(0.7, 0.4, 0.6)]
const CLOUD_NAMES := ["Veil", "Drift", "Haze", "Shroud", "Reach", "Mists", "Wisps", "Expanse"]
const ROCK_NAMES := ["Shards", "Rubble", "Scatter", "Teeth", "Shoals", "Cinders"]

static func cell_of(p: Vector3) -> Vector2:
	var w: float = 2.0 * Data.SPACE_EDGE / float(Data.MAP_CELLS)
	return Vector2((p.x + Data.SPACE_EDGE) / w + 1.0, (p.z + Data.SPACE_EDGE) / w + 1.0)

static func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func auto_layouts(systems: Dictionary) -> Dictionary:
	var out := {}
	for sid in systems:
		if Data.SYSTEM_LAYOUT.has(sid) or Data.SYSTEM_ROLES.has(sid): continue
		var sy: Dictionary = systems[sid]
		if is_unknown(sy) or str(sy.get("faction", "")) == "Void" or str(sy.get("role", "")) == "void" or not sy.has("station") or not sy.has("planet"): continue
		var L := _auto_layout(sid, sy)
		if not L.is_empty(): out[sid] = L
	return out

static func _auto_layout(sid: String, sy: Dictionary) -> Dictionary:
	# v11.98 (owner: Rimgate, "look at this mess ... you can't have parallel trade lanes ... we need networks that are
	# bigger in the space area"): the places are spread over the whole map (gates out near the edge, each on its own
	# bearing; the worlds and stations in the open between), the lanes are one clean network (a shortest tree that never
	# crosses itself, never leaves a place two ways at a narrow angle, never runs beside another lane, never passes
	# close by a place it doesn't stop at, plus a loop or two), lanes that would leave a place close together merge
	# first at a named choke point, and the star goes in the biggest open space, off every lane. Seeded by the id.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("develop2:" + sid)
	var lo := 2.2
	var hi := float(Data.MAP_CELLS) + 1.0 - 1.2
	var mid := Vector2((lo + hi) * 0.5, (lo + hi) * 0.5)
	var clampc := func(c: Vector2) -> Vector2: return Vector2(clampf(c.x, lo, hi), clampf(c.y, lo, hi))
	var w: float = 2.0 * Data.SPACE_EDGE / float(Data.MAP_CELLS)
	var sun_r: float = Data.SUN_RADIUS * Data.SUN_KEEP_OUT / w
	var hub: Vector2 = cell_of(sy["station"]["pos"])
	hub = Vector2(clampf(hub.x, mid.x - 1.6, mid.x + 1.6), clampf(hub.y, mid.y - 1.6, mid.y + 1.6))
	var L := {"hub": [hub.x, hub.y]}
	var nodes: Array = [["hub", hub]]   # [lane name, cell]
	var taken: Array = [hub]
	var far := func(c: Vector2, d: float) -> bool:
		for q: Vector2 in taken: if q.distance_to(c) < d: return false
		return true
	# gates: out toward the edge on the bearing they lead (so the galaxy reads right), spread apart
	var gates := {}
	var gl: Array = []
	for g in sy.get("gates", []):
		var gd: Vector2 = cell_of(g["pos"]) - mid
		gl.append([str(g["to"]), atan2(gd.y, gd.x) if gd.length() > 0.05 else rng.randf() * TAU])
	gl.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	var gap: float = TAU / maxf(float(gl.size()), 1.0) * 0.7
	for pass_i in 6:   # push neighbours apart until each pair is at least `gap` apart in bearing
		for i in gl.size():
			for j in gl.size():
				if i == j: continue
				var da: float = wrapf(float(gl[j][1]) - float(gl[i][1]), -PI, PI)
				if absf(da) < gap: gl[j][1] = float(gl[i][1]) + signf(da if da != 0.0 else 1.0) * gap
	for gx in gl:
		var r: float = rng.randf_range(3.0, 3.6)
		var gc: Vector2 = clampc.call(mid + Vector2(cos(float(gx[1])), sin(float(gx[1]))) * r)
		gates[str(gx[0])] = [gc.x, gc.y]
		nodes.append(["gate:" + str(gx[0]), gc])
		taken.append(gc)
	L["gates"] = gates
	# a place in the open: the sampled spot farthest from everything taken, within [rmin, rmax] of `near`
	var open_spot := func(near: Vector2, rmin: float, rmax: float) -> Vector2:
		var best := Vector2.INF
		var best_s := -INF
		for i in 160:
			var a := rng.randf() * TAU
			var c: Vector2 = clampc.call(near + Vector2(cos(a), sin(a)) * rng.randf_range(rmin, rmax))
			var s := INF
			for q: Vector2 in taken: s = minf(s, q.distance_to(c))
			if s > best_s:
				best_s = s
				best = c
		return best
	# the main planet: near the hub, in the open
	var pl: Vector2 = open_spot.call(hub, 1.6, 2.6)
	L["planet"] = [pl.x, pl.y]
	nodes.append(["planet", pl])
	taken.append(pl)
	# the other worlds and stations already in the system, moved out into the open
	var mp := {}
	var ms := {}
	for x in sy.get("more_planets", []):
		var c: Vector2 = open_spot.call(mid, 1.5, 4.0)
		mp[str(x["name"])] = [c.x, c.y]
		nodes.append([str(x["name"]), c])
		taken.append(c)
	for x in sy.get("more_stations", []):
		var c: Vector2 = open_spot.call(mid, 1.5, 4.0)
		ms[str(x["name"])] = [c.x, c.y]
		if not bool(x.get("hidden", false)): nodes.append([str(x["name"]), c])
		taken.append(c)
	L["planets"] = mp
	L["stations"] = ms
	# a second world, when the system has only the one
	if (sy.get("more_planets", []) as Array).is_empty():
		var x2: Vector2 = open_spot.call(mid, 2.0, 4.0)
		taken.append(x2)
		var pal: String = ["ice", "desert", "dead", "gas", "ocean", "jungle", "toxic"][rng.randi() % 7]
		var nm: String = str(sy["name"]) + str([" II", " Minor", " Secundus", "'s Moon"][rng.randi() % 4])
		L["add_planets"] = [{"name": nm, "palette": pal, "at": [x2.x, x2.y], "radius": rng.randf_range(520.0, 820.0)}]
		nodes.append([nm, x2])
	# the fundamentals (owner): a friendly station, a hidden rival post in a nebula and a spy at the hub. A faction's
	# system gets its ally and its rival; neutral space gets a Liberator freeport and a hidden Savagers den.
	var fac := str(sy.get("faction", ""))
	var adds: Array = []
	var ally := ""
	var rival := ""
	var hostile_space := is_enemy_space(sy)   # v11.99 (owner): alien space has no lanes, no friendly stations, no spy
	if hostile_space: pass
	elif fac in MAJORS:
		ally = str(ALLIES.get(fac, ""))
		rival = Factions.rival(fac)
	elif fac == "Neutral":
		ally = "Liberator"
		rival = "Savagers"
	if ally != "":
		var ac: Vector2 = open_spot.call(mid, 2.0, 3.8)
		taken.append(ac)
		var an: String = "%s %s" % [ally, ["Embassy", "Freeport", "Relay", "Depot"][rng.randi() % 4]] if fac != "Neutral" else "%s Freeport" % ally
		adds.append({"name": an, "faction": ally, "model": "HL_Station_%s_Military_retopo" % ally, "at": [ac.x, ac.y], "role": "ally",
			"desc": ("%s station: %s's allies trade, repair and pass word here." % [ally, fac]) if fac != "Neutral" else "A Liberator freeport: free traders, repairs and work, no questions asked."})
		nodes.append([an, ac])
	if rival != "" and rival != fac:
		var rc: Vector2 = open_spot.call(Vector2(2.0 * mid.x, 2.0 * mid.y) - hub, 0.0, 2.2)   # (the far side of the system from the hub)
		taken.append(rc)
		L["nebula"] = [rc.x, rc.y]
		var rn: String = "%s Watch Post" % rival if fac != "Neutral" else "Savagers Den"
		adds.append({"name": rn, "faction": rival, "model": "HL_Station_%s_Military_retopo" % rival, "at": [rc.x, rc.y], "role": "rival", "hidden": true,
			"desc": ("A %s post hidden in the system's nebula, watching %s's lanes." % [rival, fac]) if fac != "Neutral" else "A pirate den hidden in the nebula, preying on the lanes."})
		L["spy"] = {"type": "contact", "at": "hub", "faction": rival, "name": "Dockside Informant", "desc": "A contact at the hub who sells word on the hidden %s post." % rival}
	L["add_stations"] = adds
	# the lane network
	var disp := {"hub": str(sy["station"]["name"]), "planet": str(sy["planet"]["name"])}
	for g in sy.get("gates", []): disp["gate:" + str(g["to"])] = str(g["name"])
	var net := _grid_net(nodes, disp) if not hostile_space else {"lanes": [], "junctions": {}, "segs": [], "moved": {}}   # v11.99 (owner): a freeway grid (was _lane_net, a tree); none in alien space
	for nm in net["moved"]:   # places the grid moved onto a street
		var c: Vector2 = net["moved"][nm]
		var cc := [c.x, c.y]
		if nm == "planet": L["planet"] = cc
		elif str(nm).begins_with("gate:"): L["gates"][str(nm).substr(5)] = cc
		elif mp.has(nm): mp[nm] = cc
		elif ms.has(nm): ms[nm] = cc
		else:
			for ap in L.get("add_planets", []): if str(ap["name"]) == nm: ap["at"] = cc
			for ad in adds: if str(ad["name"]) == nm: ad["at"] = cc
		for t in taken.size(): if (taken[t] as Vector2).distance_to(_old_at(nodes, nm)) < 0.001: taken[t] = c
	var juncs: Dictionary = net["junctions"]
	var segs: Array = net["segs"]
	L["junctions"] = juncs
	L["lanes"] = net["lanes"]
	# the main cloud (rocks gather in its middle) steps off the lanes, taking the hidden post with it
	if L.has("nebula") and sy.has("nebula") and not segs.is_empty():
		var nr: float = float(sy["nebula"].get("radius", 0.0)) * Data.NEBULA_SIZE * 0.65 / w
		var nc := Vector2(L["nebula"][0], L["nebula"][1])
		var clear_of := func(c: Vector2) -> bool:
			for sg in segs: if _seg_d(c, sg[0], sg[1]) < nr + 0.3: return false
			return true
		if not clear_of.call(nc):
			var bst := nc
			var bd := INF
			for i in 400:
				var c := Vector2(rng.randf_range(lo, hi), rng.randf_range(lo, hi))
				if clear_of.call(c) and far.call(c, 0.8) and c.distance_to(nc) < bd:
					bd = c.distance_to(nc)
					bst = c
			L["nebula"] = [bst.x, bst.y]
			for ad in adds: if str(ad.get("role", "")) == "rival": ad["at"] = [bst.x, bst.y]
			for t in taken.size(): if (taken[t] as Vector2).distance_to(nc) < 0.001: taken[t] = bst
	# the star: the open spot farthest from every lane and place
	var all_pts: Array = taken.duplicate()
	for jn in juncs: all_pts.append(Vector2(juncs[jn][0], juncs[jn][1]))
	var clear := func(c: Vector2) -> float:
		var s := INF
		for q: Vector2 in all_pts: s = minf(s, q.distance_to(c))
		for sg in segs: s = minf(s, _seg_d(c, sg[0], sg[1]))
		return s
	var sun := mid
	var sun_s := -INF
	for i in 300:
		var c := Vector2(rng.randf_range(lo, hi), rng.randf_range(lo, hi))
		var s: float = clear.call(c)
		if s > sun_s:
			sun_s = s
			sun = c
	L["sun"] = [sun.x, sun.y]
	all_pts.append(sun)
	# the asteroid field: in the open, off the lanes (its middle at least its size + a gap from every lane)
	if sy.has("asteroids"):
		var br: float = float(sy["asteroids"].get("radius", 0.0)) / w
		var bc := mid
		var bs := -INF
		for i in 300:
			var c := Vector2(rng.randf_range(lo, hi), rng.randf_range(lo, hi))
			var s: float = clear.call(c) - br
			if c.distance_to(sun) < sun_r + br + 0.5: continue
			if s > bs:
				bs = s
				bc = c
		L["belt"] = [bc.x, bc.y]
		all_pts.append(bc)
	# clouds: big storms on two edge squares and in the open inside (lanes may run through them); one rock field
	# inside, kept off every lane
	var clouds: Array = []
	var off_lanes := func(c: Vector2, r_cells: float) -> bool:
		for sg in segs: if _seg_d(c, sg[0], sg[1]) < r_cells + 0.35: return false
		return true
	var N := float(Data.MAP_CELLS)
	# v12.3 (owner): an edge cloud's middle sits on the square next to the border and spills out over it
	var edge_spots := [Vector2(2.4, rng.randf_range(3.0, N - 1.0)), Vector2(N - 0.4, rng.randf_range(3.0, N - 1.0)), Vector2(rng.randf_range(3.0, N - 1.0), 2.4), Vector2(rng.randf_range(3.0, N - 1.0), N - 0.4)]
	for k in 2:
		var e: Vector2 = edge_spots[(int(rng.randi() % 4) + k * 2) % 4]
		var rocks := k == 0
		if rocks:   # (v12.3: now the edge cloud sits inside the border, a rock field must find an edge spot off the lanes, or be a storm)
			rocks = false
			for es in edge_spots:
				if off_lanes.call(es, 30000.0 / w):
					e = es
					rocks = true
					break
		clouds.append({"name": "%s %s" % [str(sy["name"]), ROCK_NAMES[rng.randi() % ROCK_NAMES.size()] if rocks else CLOUD_NAMES[rng.randi() % CLOUD_NAMES.size()]],
			"at": [e.x, e.y], "radius": rng.randf_range(22000.0, 30000.0) if rocks else rng.randf_range(60000.0, 90000.0), "weather": "rocks" if rocks else "storm", "color": CLOUD_COLS[rng.randi() % CLOUD_COLS.size()]})
	var inner := 0
	for tries in 120:
		if inner >= 5: break
		var c := Vector2(rng.randf_range(lo, hi), rng.randf_range(lo, hi))
		var rocks := inner == 1
		var r := rng.randf_range(16000.0, 26000.0) if rocks else rng.randf_range(30000.0, 50000.0)
		var rc2 := r / w
		var ok := c.distance_to(sun) > sun_r + rc2
		for q: Vector2 in all_pts: if q.distance_to(c) < (rc2 + 0.3 if rocks else 0.7): ok = false   # (a storm may wrap round a place a little; rocks never)
		if ok and rocks and not off_lanes.call(c, rc2): ok = false
		if not ok: continue
		clouds.append({"name": "%s %s" % [str(sy["name"]), ROCK_NAMES[rng.randi() % ROCK_NAMES.size()] if rocks else CLOUD_NAMES[rng.randi() % CLOUD_NAMES.size()]],
			"at": [c.x, c.y], "radius": r, "weather": "rocks" if rocks else "storm", "color": CLOUD_COLS[rng.randi() % CLOUD_COLS.size()]})
		all_pts.append(c)
		inner += 1
	L["clouds"] = clouds
	return L

## v11.99 (owner: "like a tic-tac-toe grid ... choke points ... lanes don't go all the way through, they stop at T
## sections ... genuinely how the maps of a real freeway is"): the lane network as streets. A level street and an
## upright street cross at the hub; one more of each runs where the other places cluster. Each place sits on the
## street nearest it, or joins it by a short spur that meets it in a T; a spur that would run beside another spur
## joins that one's place instead. Each street only runs as far as its places (and the crossing it needs to join the
## rest). Every street is cut where things meet, so each stretch between two meeting points is one lane.
## nodes: [[name, cell]...] (nodes[0] = the hub). Returns {lanes, junctions, segs}.
static func _grid_net(nodes: Array, disp: Dictionary = {}) -> Dictionary:
	var hubc: Vector2 = nodes[0][1]
	var names: Array = nodes.map(func(x): return str(x[0]))
	var pts: Array = nodes.map(func(x): return x[1])
	var n := pts.size()
	# the streets: [axis ("h" = level, runs along x at y = v; "v" = upright, along y at x = v), v]
	var streets: Array = [["h", hubc.y], ["v", hubc.x]]
	for ax in ["h", "v"]:
		var far_pts: Array = []   # places far from the hub's street on this axis: their middle is the second street
		for i in range(1, n):
			var p: Vector2 = pts[i]
			var off: float = absf(p.y - hubc.y) if ax == "h" else absf(p.x - hubc.x)
			if off > 1.6: far_pts.append(p)
		if far_pts.size() >= 2:
			var side_pos := far_pts.filter(func(p): return (p.y - hubc.y if ax == "h" else p.x - hubc.x) > 0.0)
			var side_neg := far_pts.filter(func(p): return (p.y - hubc.y if ax == "h" else p.x - hubc.x) < 0.0)
			var use: Array = side_pos if side_pos.size() >= side_neg.size() else side_neg
			if use.size() >= 2:
				var m := 0.0
				for p: Vector2 in use: m += (p.y if ax == "h" else p.x)
				m /= float(use.size())
				var base: float = hubc.y if ax == "h" else hubc.x
				if absf(m - base) >= 1.4: streets.append([ax, m])
	var on_street := func(si: int, p: Vector2) -> Vector2:   # the foot of p on street si
		return Vector2(p.x, streets[si][1]) if streets[si][0] == "h" else Vector2(streets[si][1], p.y)
	var st_d := func(si: int, p: Vector2) -> float: return absf(p.y - float(streets[si][1])) if streets[si][0] == "h" else absf(p.x - float(streets[si][1]))
	# each place: on a street (within 0.35), or a spur to the nearest street, or (beside another spur) to that spur's place
	var stops: Array = []   # per street: [[along, name]] points on it
	for si in streets.size(): stops.append([])
	var extra: Array = []   # [name a, name b] lanes off the streets (spurs, chains)
	var spurs: Array = []   # [foot, place, name]
	var moved := {}         # places moved onto a street: name -> cell
	var jn := {}            # junction name -> cell
	var order: Array = range(n)
	order.sort_custom(func(a, b):
		var da := INF
		var db := INF
		for si in streets.size(): da = minf(da, st_d.call(si, pts[a])); db = minf(db, st_d.call(si, pts[b]))
		return da < db)
	for i in order:
		var p: Vector2 = pts[i]
		var best := 0
		for si in streets.size(): if st_d.call(si, p) < st_d.call(best, p): best = si
		var along: float = p.x if streets[best][0] == "h" else p.y
		if i != 0 and st_d.call(best, p) <= 0.8:   # close to a street: the place moves onto it (no stub of a lane)
			p = on_street.call(best, p)
			pts[i] = p
			moved[names[i]] = p
		if st_d.call(best, p) <= 0.35 or i == 0:
			stops[best].append([along, names[i]])
			if i == 0: stops[1].append([hubc.y, names[0]])   # (the hub sits on both of its streets)
			continue
		var foot: Vector2 = on_street.call(best, p)
		var join_to := ""
		for sp in spurs:   # a spur beside another one (within 0.5, overlapping): join that place instead
			var f2: Vector2 = sp[0]
			var p2: Vector2 = sp[1]
			var same_dir: bool = (p - foot).normalized().dot((p2 - f2).normalized()) > 0.9
			if same_dir and _seg_seg_d(foot, p, f2, p2) < 0.5: join_to = str(sp[2])
		if join_to != "":
			extra.append([join_to, names[i]])
			continue
		var fname: String = "%s Turnoff" % str(disp.get(names[i], names[i]))
		jn[fname] = foot
		stops[best].append([along, fname])
		extra.append([fname, names[i]])
		spurs.append([foot, p, names[i]])
	# the crossings, and each street's span (from its first stop to its last, reaching a crossing if it needs one)
	var span: Array = []
	for si in streets.size():
		var al: Array = stops[si].map(func(x): return float(x[0]))
		span.append([al.min(), al.max()] if not al.is_empty() else [INF, -INF])
	var cross := func(a: int, b: int) -> Vector2:   # where an h street and a v street meet (INF if parallel)
		if streets[a][0] == streets[b][0]: return Vector2.INF
		var h: int = a if streets[a][0] == "h" else b
		var v: int = b if h == a else a
		return Vector2(float(streets[v][1]), float(streets[h][1]))
	var reach := func(si: int, c: Vector2) -> void:   # stretch street si to take in point c
		var t: float = c.x if streets[si][0] == "h" else c.y
		span[si] = [minf(float(span[si][0]), t), maxf(float(span[si][1]), t)]
	var meets := func(a: int, b: int) -> bool:
		var c: Vector2 = cross.call(a, b)
		if c == Vector2.INF: return false
		for s2 in [a, b]:
			var t: float = c.x if streets[s2][0] == "h" else c.y
			if t < float(span[s2][0]) - 0.01 or t > float(span[s2][1]) + 0.01: return false
		return true
	var live: Array = range(streets.size()).filter(func(si): return not (stops[si] as Array).is_empty())
	for guard in 8:   # join the streets up: stretch the cheapest pair until all are one network
		var comp := {}
		for si in live: comp[si] = si
		var root := func(x: int) -> int:
			while comp[x] != x: x = comp[x]
			return x
		for a in live:
			for b in live:
				if a < b and meets.call(a, b): comp[root.call(a)] = root.call(b)
		var groups := {}
		for si in live: groups[root.call(si)] = true
		if groups.size() <= 1: break
		var best_cost := INF
		var best_pair := []
		for a in live:
			for b in live:
				if root.call(a) == root.call(b): continue
				var c: Vector2 = cross.call(a, b)
				if c == Vector2.INF: continue
				var cost := 0.0
				for s2 in [a, b]:
					var t: float = c.x if streets[s2][0] == "h" else c.y
					cost += maxf(0.0, float(span[s2][0]) - t) + maxf(0.0, t - float(span[s2][1]))
				if cost < best_cost:
					best_cost = cost
					best_pair = [a, b, c]
		if best_pair.is_empty(): break
		reach.call(best_pair[0], best_pair[2])
		reach.call(best_pair[1], best_pair[2])
	# crossings become choke points (named for where they are round the hub)
	var cn := 0
	for a in live:
		for b in live:
			if a >= b or not meets.call(a, b): continue
			var c: Vector2 = cross.call(a, b)
			if c.distance_to(hubc) < 0.05: continue   # (the hub's own crossing is the hub)
			var hit := ""
			for s2 in [a, b]:
				for st in stops[s2]: if absf(float(st[0]) - (c.x if streets[s2][0] == "h" else c.y)) < 0.05 and not jn.has(str(st[1])): hit = str(st[1])
			if hit == "":
				var d := c - hubc
				cn += 1
				hit = "%s Choke Point" % ("North" if d.y < -absf(d.x) else ("South" if d.y > absf(d.x) else ("East" if d.x > 0 else "West")))
				while jn.has(hit): hit = hit + " " + str(cn)
				jn[hit] = c
			for s2 in [a, b]:
				var t: float = c.x if streets[s2][0] == "h" else c.y
				if not (stops[s2] as Array).any(func(st): return str(st[1]) == hit): stops[s2].append([t, hit])
	# cut every street at its stops (stops closer than 0.4 along it merge into the first)
	var lanes: Array = []
	var seen := {}
	for si in live:
		var sl: Array = stops[si]
		sl.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
		var prev: Array = []
		for st in sl:
			if not prev.is_empty() and float(st[0]) - float(prev[0]) < 0.4:
				# a spur's foot right by another stop: the spur starts at that stop instead (never drop a place)
				var drop: Array = st if str(st[1]).ends_with("Turnoff") else (prev if str(prev[1]).ends_with("Turnoff") else [])
				if not drop.is_empty():
					var keep: Array = prev if drop == st else st
					for e in extra: if str(e[0]) == str(drop[1]): e[0] = keep[1]
					for ln2 in lanes: for q in 2: if str(ln2[q]) == str(drop[1]): ln2[q] = keep[1]
					jn.erase(str(drop[1]))
					if drop == prev: prev = st
					continue
			# two places on a street too close together: the later one moves along it (a crossing stays put)
			var is_place := func(k: String) -> bool: return not jn.has(k) and k != names[0]
			if not prev.is_empty() and float(st[0]) - float(prev[0]) < 0.7 and is_place.call(str(st[1])):
				st[0] = float(prev[0]) + 0.7
				var np: Vector2 = Vector2(st[0], streets[si][1]) if streets[si][0] == "h" else Vector2(streets[si][1], st[0])
				pts[names.find(str(st[1]))] = np
				moved[str(st[1])] = np
			if not prev.is_empty():
				var key := "%s|%s" % [prev[1], st[1]]
				if not seen.has(key):
					seen[key] = true
					lanes.append([str(prev[1]), str(st[1])])
			prev = st
	lanes.append_array(extra)
	var where := func(k: String) -> Vector2:
		if jn.has(k): return jn[k]
		return pts[names.find(k)]
	var segs: Array = []
	var juncs := {}
	for k in jn: juncs[k] = [(jn[k] as Vector2).x, (jn[k] as Vector2).y]
	lanes = lanes.filter(func(ln): return str(ln[0]) != str(ln[1]))
	for ln in lanes: segs.append([where.call(str(ln[0])), where.call(str(ln[1]))])
	# v12.0 (owner: "a square running around the outside too ... it may be shifty ... it may be a pentagon"): a ring
	# road round the outside, through the outermost places and street ends (their hull), each side only where it is
	# clear: it crosses nothing, passes close by nothing, and leaves its places at a fair angle from their lanes
	var deg := {}
	for ln in lanes: for q in 2: deg[str(ln[q])] = int(deg.get(str(ln[q]), 0)) + 1
	var ends: Array = []
	for k in deg: if int(deg[k]) == 1: ends.append(k)
	var hull := _hull(ends.map(func(k): return where.call(str(k))))
	var hk: Array = hull.map(func(hp): return ends[ends.map(func(k): return where.call(str(k))).find(hp)])
	for i in hk.size():
		if hk.size() < 3: break
		var ka: String = hk[i]
		var kb: String = hk[(i + 1) % hk.size()]
		var A: Vector2 = where.call(ka)
		var B: Vector2 = where.call(kb)
		if A.distance_to(B) < 1.2: continue
		var ok := true
		for sg in segs:
			var touch: bool = (sg[0] as Vector2).distance_to(A) < 0.01 or (sg[1] as Vector2).distance_to(A) < 0.01 or (sg[0] as Vector2).distance_to(B) < 0.01 or (sg[1] as Vector2).distance_to(B) < 0.01
			if touch:
				var at: Vector2 = A if ((sg[0] as Vector2).distance_to(A) < 0.01 or (sg[1] as Vector2).distance_to(A) < 0.01) else B
				var other: Vector2 = sg[1] if (sg[0] as Vector2).distance_to(at) < 0.01 else sg[0]
				var mine: Vector2 = B if at == A else A
				if (other - at).normalized().dot((mine - at).normalized()) > cos(deg_to_rad(30.0)): ok = false
			elif _seg_seg_d(A, B, sg[0], sg[1]) < 0.6: ok = false
		for q: Vector2 in pts + jn.values():
			if q.distance_to(A) > 0.01 and q.distance_to(B) > 0.01 and _seg_d(q, A, B) < 0.6: ok = false
		if ok:
			lanes.append([ka, kb])
			segs.append([A, B])
	return {"lanes": lanes, "junctions": juncs, "segs": segs, "moved": moved}

## v12.0: the convex hull of points (Andrew's monotone chain), round the outside in order.
static func _hull(pts: Array) -> Array:
	var p: Array = pts.duplicate()
	p.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	if p.size() < 3: return p
	var cr := func(o: Vector2, a: Vector2, b: Vector2) -> float: return (a - o).cross(b - o)
	var lower: Array = []
	for q in p:
		while lower.size() >= 2 and cr.call(lower[-2], lower[-1], q) <= 0.0: lower.pop_back()
		lower.append(q)
	var upper: Array = []
	for i in range(p.size() - 1, -1, -1):
		var q: Vector2 = p[i]
		while upper.size() >= 2 and cr.call(upper[-2], upper[-1], q) <= 0.0: upper.pop_back()
		upper.append(q)
	lower.pop_back()
	upper.pop_back()
	return lower + upper

## v11.99 (owner: "yes, the lane rules in Dreadholm"): a hand-made system keeps its places but gets the freeway grid
## (places near a street step onto it) and its star moves to the most open spot off the lanes.
const REGRID := ["dreadholm"]
static func _regrid(sy: Dictionary) -> void:
	var nodes: Array = [["hub", cell_of(sy["station"]["pos"])], ["planet", cell_of(sy["planet"]["pos"])]]
	var disp := {"hub": str(sy["station"]["name"]), "planet": str(sy["planet"]["name"])}
	for g in sy["gates"]:
		nodes.append(["gate:" + str(g["to"]), cell_of(g["pos"])])
		disp["gate:" + str(g["to"])] = str(g["name"])
	for x in sy.get("more_planets", []): nodes.append([str(x["name"]), cell_of(x["pos"])])
	for x in sy.get("more_stations", []): if not bool(x.get("hidden", false)): nodes.append([str(x["name"]), cell_of(x["pos"])])
	var net := _grid_net(nodes, disp)
	for nm in net["moved"]:
		var c: Vector2 = net["moved"][nm]
		if nm == "planet": sy["planet"]["pos"] = cell_pos([c.x, c.y], (sy["planet"]["pos"] as Vector3).y)
		elif str(nm).begins_with("gate:"):
			for g in sy["gates"]: if "gate:" + str(g["to"]) == nm: g["pos"] = cell_pos([c.x, c.y], (g["pos"] as Vector3).y)
		else:
			for x in sy.get("more_planets", []) + sy.get("more_stations", []): if str(x["name"]) == nm: x["pos"] = cell_pos([c.x, c.y], (x["pos"] as Vector3).y)
	var j := {}
	for jn in net["junctions"]: j[jn] = cell_pos(net["junctions"][jn])
	sy["junctions"] = j
	sy["lane_plan"] = net["lanes"]
	# the star: the most open spot, off every lane and place
	var all_pts: Array = nodes.map(func(x): return net["moved"].get(x[0], x[1]))
	for jn in net["junctions"]: all_pts.append(Vector2(net["junctions"][jn][0], net["junctions"][jn][1]))
	var best := Vector2(6, 6)
	var bs := -INF
	for i in 400:
		var c := Vector2(2.4 + fmod(i * 0.6180339, 1.0) * 7.2, 2.4 + fmod(i * 0.7548776, 1.0) * 7.2)
		var sc := INF
		for q: Vector2 in all_pts: sc = minf(sc, q.distance_to(c))
		for sg in net["segs"]: sc = minf(sc, _seg_d(c, sg[0], sg[1]))
		if sc > bs:
			bs = sc
			best = c
	var sp := cell_pos([best.x, best.y])
	sy["sun_center"] = false
	sy["sun_dir"] = -sp.normalized()
	sy["sun_dist"] = sp.length()
	all_pts.append(best)
	# the asteroids (the belt, rock clouds, the rocky main cloud) step off the lanes into the open
	var w: float = 2.0 * Data.SPACE_EDGE / float(Data.MAP_CELLS)
	var off_spot := func(r_cells: float, from: Vector2) -> Vector2:
		var ok := func(c: Vector2) -> bool:
			for sg in net["segs"]: if _seg_d(c, sg[0], sg[1]) < r_cells + 0.3: return false
			for q: Vector2 in all_pts: if q.distance_to(c) < r_cells + 0.3: return false
			return true
		if ok.call(from): return from
		var bst := from
		var bd := INF
		for i in 500:
			var c := Vector2(2.2 + fmod(i * 0.6180339, 1.0) * 7.6, 2.2 + fmod(i * 0.7548776, 1.0) * 7.6)
			if ok.call(c) and c.distance_to(from) < bd:
				bd = c.distance_to(from)
				bst = c
		return bst
	if sy.has("asteroids") and float(sy["asteroids"].get("radius", 0.0)) > 1.0:
		var bc: Vector2 = off_spot.call(float(sy["asteroids"]["radius"]) / w, cell_of(sy["asteroids"]["center"]))
		sy["asteroids"]["center"] = cell_pos([bc.x, bc.y])
		all_pts.append(bc)
	for c in sy.get("layout_clouds", []):
		if str(c.get("weather", "")) != "rocks": continue
		var cc: Vector2 = off_spot.call(float(c["radius"]) / w, cell_of(c["center"]))
		c["center"] = cell_pos([cc.x, cc.y])
		all_pts.append(cc)
	if sy.has("nebula") and float(sy["nebula"].get("radius", 0.0)) > 1.0:
		var nc: Vector2 = off_spot.call(float(sy["nebula"]["radius"]) * Data.NEBULA_SIZE * 0.65 / w, cell_of(sy["nebula"]["center"]))
		sy["nebula"]["center"] = cell_pos([nc.x, nc.y])

## v12.3: the inside of the map (the border squares are cells 1-2 and 10-11 of cell_of): clamp a point in, with a margin.
static func inside_cells(p: Vector3, margin := Data.BORDER_MARGIN) -> Vector3:
	var lo := 2.0 + margin
	var hi := float(Data.MAP_CELLS) - margin
	var c := cell_of(p)
	if c.x >= lo and c.x <= hi and c.y >= lo and c.y <= hi: return p
	return cell_pos([clampf(c.x, lo, hi), clampf(c.y, lo, hi)], p.y)

static func keep_off_border(sy: Dictionary) -> void:
	if sy.has("station"): sy["station"]["pos"] = inside_cells(sy["station"]["pos"])
	if sy.has("planet"): sy["planet"]["pos"] = inside_cells(sy["planet"]["pos"], Data.BORDER_MARGIN + float(sy["planet"].get("radius", 0.0)) / (2.0 * Data.SPACE_EDGE / float(Data.MAP_CELLS)))
	for x in sy.get("more_planets", []): x["pos"] = inside_cells(x["pos"], Data.BORDER_MARGIN + float(x.get("radius", 0.0)) / (2.0 * Data.SPACE_EDGE / float(Data.MAP_CELLS)))
	for x in sy.get("more_stations", []): x["pos"] = inside_cells(x["pos"])
	for g in sy.get("gates", []): g["pos"] = inside_cells(g["pos"])
	var j: Dictionary = sy.get("junctions", {})
	for k in j: j[k] = inside_cells(j[k])
	if sy.has("asteroids"): sy["asteroids"]["center"] = inside_cells(sy["asteroids"]["center"], 0.0)
	var sp := sun_pos_of(sy)
	var sp2 := inside_cells(sp)
	if sp2 != sp and not sy.get("sun_center", false):
		sy["sun_dir"] = -sp2.normalized()
		sy["sun_dist"] = sp2.length()
	for c in sy.get("layout_clouds", []):   # a cloud's middle is inside too (it may spill out over the border)
		c["center"] = inside_cells(c["center"], 0.0)

static func _old_at(nodes: Array, nm: String) -> Vector2:
	for x in nodes: if str(x[0]) == nm: return x[1]
	return Vector2.INF

## v11.98: does segment a-b properly cross segment c-d?
static func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var o := func(p: Vector2, q: Vector2, r: Vector2) -> float: return (q - p).cross(r - p)
	var d1: float = o.call(c, d, a)
	var d2: float = o.call(c, d, b)
	var d3: float = o.call(a, b, c)
	var d4: float = o.call(a, b, d)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0

static func _seg_seg_d(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if _crosses(a, b, c, d): return 0.0
	return minf(minf(_seg_d(a, c, d), _seg_d(b, c, d)), minf(_seg_d(c, a, b), _seg_d(d, a, b)))

## v11.98: may lane a-b join `edges` (each [ia, ib]) over `pts`? No crossing, no narrow angle where it meets another
## lane at a place, no running beside a lane it doesn't touch, no passing close by a place it doesn't stop at.
static func _lane_ok(pts: Array, edges: Array, ia: int, ib: int, min_ang: float, sep: float, pass_d: float) -> bool:
	var a: Vector2 = pts[ia]
	var b: Vector2 = pts[ib]
	for k in pts.size():
		if k != ia and k != ib and _seg_d(pts[k], a, b) < pass_d: return false
	var ca := cos(deg_to_rad(min_ang))
	for e in edges:
		var ea: int = e[0]
		var eb: int = e[1]
		if (ea == ia and eb == ib) or (ea == ib and eb == ia): return false
		var share := -1
		var other := -1
		var mine := -1
		if ea == ia or ea == ib: share = ea; other = eb
		elif eb == ia or eb == ib: share = eb; other = ea
		if share >= 0:
			mine = ib if share == ia else ia
			var d1: Vector2 = ((pts[mine] as Vector2) - (pts[share] as Vector2)).normalized()
			var d2: Vector2 = ((pts[other] as Vector2) - (pts[share] as Vector2)).normalized()
			if d1.dot(d2) > ca: return false
			continue
		if _seg_seg_d(a, b, pts[ea], pts[eb]) < sep: return false
	return true

## v11.98: the lane network over `nodes` ([name, cell]): a shortest tree (Kruskal) that keeps the rules above, loosened
## only if a place can't be reached otherwise; a loop or two where they save a long way round; then each pair of lanes
## leaving one place within 55 degrees of each other merges first at a choke point. Returns lanes, junctions, segs.
static func _lane_net(nodes: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pts: Array = nodes.map(func(n): return n[1])
	var n := pts.size()
	var cand: Array = []
	for i in n:
		for j in range(i + 1, n): cand.append([i, j, (pts[i] as Vector2).distance_to(pts[j])])
	cand.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	var comp: Array = range(n)
	var root := func(x: int) -> int:
		while comp[x] != x: x = comp[x]
		return x
	var edges: Array = []
	for rules in [[40.0, 0.8, 0.6], [30.0, 0.5, 0.45], [18.0, 0.3, 0.3], [0.0, 0.0, 0.15]]:
		for c in cand:
			var ra: int = root.call(int(c[0]))
			var rb: int = root.call(int(c[1]))
			if ra == rb: continue
			if not _lane_ok(pts, edges, int(c[0]), int(c[1]), rules[0], rules[1], rules[2]): continue
			edges.append([int(c[0]), int(c[1])])
			comp[ra] = rb
	# loops: a lane where the network's way round is far longer than straight across
	var adj := func() -> Array:
		var g: Array = []
		for i in n: g.append([])
		for e in edges:
			var l: float = (pts[e[0]] as Vector2).distance_to(pts[e[1]])
			g[e[0]].append([e[1], l])
			g[e[1]].append([e[0], l])
		return g
	var path_len := func(s: int, t: int) -> float:
		var g: Array = adj.call()
		var dist: Array = []
		dist.resize(n)
		dist.fill(INF)
		dist[s] = 0.0
		var todo: Array = range(n)
		while not todo.is_empty():
			var u: int = todo[0]
			for v in todo: if float(dist[v]) < float(dist[u]): u = v
			todo.erase(u)
			for nb in g[u]:
				if float(dist[u]) + float(nb[1]) < float(dist[nb[0]]): dist[nb[0]] = float(dist[u]) + float(nb[1])
		return float(dist[t])
	var loops := 0
	for c in cand:
		if loops >= 2: break
		if float(c[2]) > 4.5: break
		if not _lane_ok(pts, edges, int(c[0]), int(c[1]), 40.0, 0.8, 0.6): continue
		if float(path_len.call(int(c[0]), int(c[1]))) < float(c[2]) * 1.9: continue
		edges.append([int(c[0]), int(c[1])])
		loops += 1
	# choke points: two lanes leaving a place within 55 degrees share their first stretch to a junction
	var names: Array = nodes.map(func(x): return str(x[0]))
	var juncs := {}
	var cmid := Vector2.ZERO
	for p: Vector2 in pts: cmid += p
	cmid /= float(maxi(n, 1))
	var lanes: Array = []
	var used := {}
	var cc := cos(deg_to_rad(55.0))
	for s in n:
		var inc: Array = []
		for ei in edges.size():
			var e: Array = edges[ei]
			if used.has(ei): continue
			if e[0] == s or e[1] == s: inc.append(ei)
		var best := []
		var best_dot := cc
		for x in inc.size():
			for y in range(x + 1, inc.size()):
				var e1: Array = edges[inc[x]]
				var e2: Array = edges[inc[y]]
				var o1: int = e1[1] if e1[0] == s else e1[0]
				var o2: int = e2[1] if e2[0] == s else e2[0]
				var d1: Vector2 = ((pts[o1] as Vector2) - (pts[s] as Vector2)).normalized()
				var d2: Vector2 = ((pts[o2] as Vector2) - (pts[s] as Vector2)).normalized()
				if d1.dot(d2) > best_dot:
					best_dot = d1.dot(d2)
					best = [inc[x], inc[y], o1, o2]
		if best.is_empty(): continue
		var p0: Vector2 = pts[s]
		var l1: float = p0.distance_to(pts[best[2]])
		var l2: float = p0.distance_to(pts[best[3]])
		var bis: Vector2 = (((pts[best[2]] as Vector2) - p0).normalized() + ((pts[best[3]] as Vector2) - p0).normalized()).normalized()
		var jc: Vector2 = p0 + bis * minf(l1, l2) * 0.45
		var dirn := jc - cmid
		var jname: String = "%s Choke Point" % ("North" if dirn.y < -absf(dirn.x) else ("South" if dirn.y > absf(dirn.x) else ("East" if dirn.x > 0 else "West")))
		var base_jn := jname
		var nth := 2
		while juncs.has(jname):
			jname = base_jn.replace("Choke Point", "Crossing") if nth == 2 else "%s %d" % [base_jn, nth]
			nth += 1
		juncs[jname] = [jc.x, jc.y]
		used[best[0]] = true
		used[best[1]] = true
		lanes.append([names[s], jname])
		lanes.append([jname, names[best[2]]])
		lanes.append([jname, names[best[3]]])
	for ei in edges.size():
		if used.has(ei): continue
		lanes.append([names[edges[ei][0]], names[edges[ei][1]]])
	var where := func(k: String) -> Vector2:
		if juncs.has(k): return Vector2(juncs[k][0], juncs[k][1])
		return pts[names.find(k)]
	var segs: Array = []
	for ln in lanes: segs.append([where.call(str(ln[0])), where.call(str(ln[1]))])
	return {"lanes": lanes, "junctions": juncs, "segs": segs}

## v11.65: where a lane-plan name sits: "hub", "planet", "gate:<system id>", a choke point, or a station / planet by name.
static func layout_point(sy: Dictionary, key: String) -> Vector3:
	if key == "hub": return sy["station"]["pos"]
	if key == "planet": return sy["planet"]["pos"]
	if key.begins_with("gate:"):
		for g in sy["gates"]:
			if str(g["to"]) == key.substr(5): return g["pos"]
	if (sy.get("junctions", {}) as Dictionary).has(key): return sy["junctions"][key]
	for x in sy.get("more_stations", []) + sy.get("more_planets", []):
		if str(x["name"]) == key: return x["pos"]
	return Vector3.INF

## v11.65: the planned lanes as [from, to] points (a plan entry whose ends don't exist is left out).
static func layout_segments(sy: Dictionary) -> Array:
	var out: Array = []
	for e in sy.get("lane_plan", []):
		var a := layout_point(sy, str(e[0]))
		var b := layout_point(sy, str(e[1]))
		if a != Vector3.INF and b != Vector3.INF: out.append([a, b])
	return out

## v11.10 (owner: "not all lanes should start from the centre; like waypoints"): the trade-lane network. points[0] is
## the main station, then the planet, then the gates. Each place (nearest first) is linked from the connected place
## nearest to it whose new lane leaves at least Data.LANE_MIN_SPREAD degrees from the lanes already there, so two lanes
## never run side by side out of the station: a far gate behind a nearer one is reached from that one.
## Returns [[from, to], ...] as indices into points.
static func lane_tree(points: Array) -> Array:
	var edges: Array = []
	if points.size() < 2: return edges
	var connected: Array = [0]
	var order: Array = range(1, points.size())
	var p0: Vector3 = points[0]
	order.sort_custom(func(a, b): return p0.distance_to(points[a]) < p0.distance_to(points[b]))
	var lim: float = cos(deg_to_rad(Data.LANE_MIN_SPREAD))
	for t in order:
		var pt: Vector3 = points[t]
		var best := -1
		var best_d := INF
		var fallback := 0
		var fb_d := INF
		for s in connected:
			var ps: Vector3 = points[s]
			var d := ps.distance_to(pt)
			var dir := (pt - ps).normalized()
			var ok := true
			for e in edges:
				var other := -1
				if e[0] == s: other = e[1]
				elif e[1] == s: other = e[0]
				if other < 0: continue
				if dir.dot(((points[other] as Vector3) - ps).normalized()) > lim: ok = false
			if d < fb_d: fb_d = d; fallback = s
			if ok and d < best_d: best_d = d; best = s
		edges.append([best if best >= 0 else fallback, t])
		connected.append(t)
	return edges

## v1.5m: the asteroid field is moved off every trade-lane line (station -> planet, station -> each gate): its middle is
## pushed sideways, level, until the lane passes at least its radius + LANE_BELT_CLEAR away. Lanes stay straight.
static func clear_lanes(out: Dictionary) -> void:
	for id in out:
		var sy: Dictionary = out[id]
		var pts: Array = [sy["station"]["pos"], sy["planet"]["pos"]]
		for g in sy["gates"]: pts.append(g["pos"])
		var segs: Array = lane_tree(pts).map(func(e): return [pts[e[0]], pts[e[1]]])   # v11.10: the lane network
		var belt: Dictionary = sy["asteroids"]
		var need: float = float(belt.get("radius", 400.0)) + Data.LANE_BELT_CLEAR
		for it in 12:
			var moved := false
			for sg in segs:
				var a: Vector3 = sg[0]
				var b: Vector3 = sg[1]
				var c: Vector3 = belt["center"]
				var q := Geometry3D.get_closest_point_to_segment(c, a, b)
				var off := Vector3(c.x - q.x, 0.0, c.z - q.z)
				var d := off.length()
				if d >= need: continue
				if d < 1.0:   # dead on the line: step out to the side of it
					var ab: Vector3 = (b as Vector3) - a
					off = Vector3(-ab.z, 0.0, ab.x)
				belt["center"] = c + off.normalized() * (need - d + 40.0)
				moved = true
			if not moved: break
		belt["lane_clear"] = true

## Is a body of this radius at `pos` clear of everything already in the system? (tests use it too)
static func clear_of(sys: Dictionary, pos: Vector3, radius: float, skip_id := "") -> bool:
	# v1.4m: planets keep a wide gap from other planets (PH_CLEARANCE); everything else keeps the small gap
	var big: bool = radius > 100.0
	var m: float = Data.PH_STATION_CLEARANCE
	if pos.distance_to(sys["planet"]["pos"]) < float(sys["planet"]["radius"]) * 1.15 + radius + (Data.PH_CLEARANCE if big else m): return false
	if pos.distance_to(sys["station"]["pos"]) < 150.0 + radius + m: return false
	for g in sys["gates"]:
		if pos.distance_to(g["pos"]) < 140.0 + radius + m: return false
	for x in sys["more_planets"] + sys["more_stations"]:
		var gap: float = Data.PH_CLEARANCE if (big and float(x["radius"]) > 100.0) else m
		if x["id"] != skip_id and pos.distance_to(x["pos"]) < float(x["radius"]) + radius + gap: return false
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
	if t[6] == "unknown":   # v12.3 (owner): the uncharted areas aren't anyone's port: no beacon station to dock at (a Kaijurai hive holds its place)
		station["nodock"] = true
		station["hidden_hub"] = true
		station["name"] = "Kaijurai Hive " + str(t[2])
		var zk0 := zone_of({"role": "unknown", "tile": str(t[2])})   # v12.68: the charted zone names its hidden place (only a brood is a hive)
		if zk0 != "brood": station["name"] = "%s %s" % [{"wildlife": "Drift Nest", "pirates": "Pirate Den", "drones": "Drone Foundry", "derelict": "Hulk Field"}[zk0], str(t[2])]
	if t[6] == "capital": station["model"] = "wheel_station"
	if t[5] == "Savagers": station["model"] = "savagers_cross_station"   # v1.4r: the patched-together cross station (the owner is making one per system)
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
		"enemy": _zone_enemy(str(t[2]), f[4]) if t[6] == "unknown" else f[4], "enemy_ships": Data.HOME_FLEETS.get(t[6], []), "enemy_faction": ("Kaijurai" if zone_of({"role": "unknown", "tile": str(t[2])}) == "brood" else "") if t[6] == "unknown" else Data.HOME_FACTION.get(t[6], ""), "patrols": patrols,   # (v12.68: only a brood zone is Kaijurai; the others' patrols are the zone's own)
		"traffic": [] if t[6] == "unknown" else [[id + "_station", id + "_planet"]],   # (v12.3: no transports in the uncharted areas)
	}

## v1.4u: more room. Everything in a system moves Data.SYSTEM_SPREAD times farther from its main station (sizes stay).
## v8.9 (owner, Freelancer maps): then the whole system fans out again (same shape) until its farthest object sits about
## Data.SYSTEM_REACH from the centre, fields and planets grow, nothing sits on the sun, and the unknown areas are laid
## out round a sun in the middle.
static func spread(out: Dictionary) -> void:
	for id in out:
		var sy: Dictionary = out[id]
		var o: Vector3 = sy["station"]["pos"]
		var k: float = Data.SYSTEM_SPREAD
		var ds: Array = []
		for p0 in _positions(sy): ds.append(Vector2((p0 as Vector3).x - o.x, (p0 as Vector3).z - o.z).length() * Data.SYSTEM_SPREAD)
		ds.sort()
		var typical: float = ds[int(ds.size() * 0.6)] if not ds.is_empty() else 1.0   # (a typical distance, not the odd far planet)
		var fan: float = clampf(Data.SYSTEM_REACH / maxf(typical, 1.0), Data.SYSTEM_FAN[0], Data.SYSTEM_FAN[1])
		k *= fan
		sy["planet"]["pos"] = o + ((sy["planet"]["pos"] as Vector3) - o) * k
		var done: Array = []
		for g in sy["gates"] + ([sy["gate"]] if not sy["gate"].is_empty() else []):
			if done.any(func(d): return is_same(d, g)): continue
			done.append(g)
			g["pos"] = o + ((g["pos"] as Vector3) - o) * k
		for key in ["asteroids", "nebula"]: sy[key]["center"] = o + ((sy[key]["center"] as Vector3) - o) * k
		var pts: Array = []
		for p in sy["patrols"]: pts.append(o + ((p as Vector3) - o) * k)
		sy["patrols"] = pts
		for x in sy["more_planets"] + sy["more_stations"]: x["pos"] = o + ((x["pos"] as Vector3) - o) * k
		sy["spread"] = k
		sy["fan"] = fan
		# sizes: the fields and the planets grow so they read at this scale
		sy["asteroids"]["radius"] = float(sy["asteroids"].get("radius", 380.0)) * Data.FIELD_GROW
		sy["planet"]["radius"] = float(sy["planet"]["radius"]) * Data.PLANET_GROW
		for x in sy["more_planets"]: x["radius"] = float(x["radius"]) * Data.PLANET_GROW
		if is_unknown(sy):
			_orbit_layout(id, sy)
			_unknown_fill(id, sy)
		_keep_off_sun(sy)
		_keep_in_tile(sy)
		_sun_off_lanes(sy)
		_station_out_of_cloud(sy)

## v10.4 (owner: bigger Freelancer clouds): the bigger main cloud must not swallow the main station (unless the station
## is a lighthouse that lives in the fog): its middle slides straight away from the station until the station is clear.
static func _station_out_of_cloud(sy: Dictionary) -> void:
	if sy["station"].get("lamp", false): return
	var R: float = float(sy["nebula"].get("radius", 0.0)) * Data.NEBULA_SIZE
	if R <= 1.0: return
	var st: Vector3 = sy["station"]["pos"]
	var c: Vector3 = sy["nebula"]["center"]
	var need: float = R + Data.NEBULA_STATION_GAP
	var off := Vector3(c.x - st.x, 0.0, c.z - st.z)
	if off.length() >= need: return
	if off.length() < 1.0: off = Vector3(st.x, 0.0, st.z) * -1.0 if Vector2(st.x, st.z).length() > 1.0 else Vector3(1, 0, 0)
	var nc := st + off.normalized() * need
	var lim: float = Data.SPACE_EDGE * 0.92
	if absf(nc.x) > lim or absf(nc.z) > lim:   # (pushed off the tile: go the other way, toward the middle)
		nc = st - off.normalized() * need
	sy["nebula"]["center"] = Vector3(clampf(nc.x, -lim, lim), c.y, clampf(nc.z, -lim, lim))

## v8.9: one place, pulled in toward the centre if it would sit past Data.SYSTEM_EDGE_SOFT (the far ones bunch up
## a little near the border instead of running off the tile).
static func _soft(p: Vector3) -> Vector3:
	var flat := Vector2(p.x, p.z)
	var d := flat.length()
	var soft: float = Data.SYSTEM_EDGE_SOFT
	if d <= soft: return p
	var d2 := minf(soft + (d - soft) * 0.25, Data.SPACE_EDGE * 0.86)
	flat = flat / d * d2
	return Vector3(flat.x, p.y, flat.y)

## Every place in a system (for measuring and moving).
static func _positions(sy: Dictionary) -> Array:
	var out: Array = [sy["station"]["pos"], sy["planet"]["pos"], sy["asteroids"]["center"], sy["nebula"]["center"]]
	for g in sy["gates"]: out.append(g["pos"])
	for x in sy["more_planets"] + sy["more_stations"]: out.append(x["pos"])
	return out

## Where the sun sits: in the middle of an unknown area, else far out along its light (space.gd uses the same rule).
static func sun_pos_of(sy: Dictionary) -> Vector3:
	if sy.get("sun_center", false): return Vector3.ZERO
	return -(sy.get("sun_dir", Vector3(0, -0.3, 1)) as Vector3).normalized() * float(sy.get("sun_dist", Data.SUN_DIST))

## v10.6 (owner: "that sun is so close to the trade lanes ... things should be fanned out"): the sun keeps its size but
## swings round the system (same height, same distance) to the bearing farthest from every trade-lane line and place;
## if no bearing is clear enough it also backs off, out toward the edge of the tile. The light follows it.
static func _sun_off_lanes(sy: Dictionary) -> void:
	if sy.get("sun_center", false): return
	var sr: float = Data.SUN_RADIUS * (0.35 if sy.get("small_sun", false) else 1.0)
	var need: float = sr * Data.SUN_LANE_CLEAR
	var st: Vector3 = sy["station"]["pos"]
	var pts: Array = [st, sy["planet"]["pos"]]
	for g in sy["gates"]: pts.append(g["pos"])
	var segs: Array = lane_tree(pts).map(func(e): return [pts[e[0]], pts[e[1]]])   # v11.10: the lane network
	var dots: Array = [[sy["planet"]["pos"], float(sy["planet"]["radius"])], [sy["asteroids"]["center"], float(sy["asteroids"].get("radius", 400.0))]]
	for x in sy["more_planets"]: dots.append([x["pos"], float(x["radius"])])
	for x in sy["more_stations"]: dots.append([x["pos"], 600.0])
	var gap := func(sp: Vector3) -> float:
		var best := INF
		for sg in segs: best = minf(best, sp.distance_to(Geometry3D.get_closest_point_to_segment(sp, sg[0], sg[1])))
		for d in dots: best = minf(best, sp.distance_to(d[0]) - float(d[1]))
		return best
	var d0: Vector3 = (sy.get("sun_dir", Vector3(0, -0.3, 1)) as Vector3).normalized()
	var dist: float = Data.SUN_DIST
	if gap.call(-d0 * dist) >= need: return
	var a0 := atan2(d0.z, d0.x)
	var flat := Vector2(d0.x, d0.z).length()
	var lim: float = Data.SPACE_EDGE * 0.8
	while dist <= lim:
		var best_d := d0
		var best_g := -INF
		for k in 72:
			var a := a0 + k * TAU / 72.0
			var dd := Vector3(cos(a) * flat, d0.y, sin(a) * flat)
			var gg: float = gap.call(-dd * dist)
			if gg > best_g + 1.0:
				best_g = gg
				best_d = dd
		if best_g >= need or dist >= lim:
			sy["sun_dir"] = best_d
			sy["sun_dist"] = dist
			return
		dist = minf(lim, dist * 1.35)

## v12.6 (owner: "we need to develop these areas a lot better, more nebula clouds, more asteroid fields, bigger ...
## we don't have jump gates here, so we gotta fill it with other things"): an uncharted area gets big storm clouds and
## asteroid-rock clouds spread over its squares (never on the border squares, clear of the hive, the world, the star
## and the warp gate), and a bigger main field. A friendly vessel of a nearby faction hides in one (space.gd).
static func _unknown_fill(id: String, sy: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("unknown_fill:" + id)
	sy["asteroids"]["radius"] = float(sy["asteroids"]["radius"]) * Data.UNKNOWN_BELT_K
	var keep: Array = [[sy["station"]["pos"], 60000.0], [sy["planet"]["pos"], float(sy["planet"]["radius"]) + 50000.0], [Vector3.ZERO, 70000.0],
		[sy["asteroids"]["center"], float(sy["asteroids"]["radius"]) + 20000.0]]
	for g in sy["gates"]: keep.append([g["pos"], 60000.0])
	var clouds: Array = sy.get("layout_clouds", []).duplicate()
	var cols: Array = Data.UNKNOWN_CLOUD_COLORS
	for want in [["storm", Data.UNKNOWN_STORMS, Data.UNKNOWN_STORM_R], ["rocks", Data.UNKNOWN_ROCK_FIELDS, Data.UNKNOWN_ROCK_R]]:
		var made := 0
		for t in 200:
			if made >= int(want[1]): break
			var r: float = rng.randf_range(float(want[2][0]), float(want[2][1]))
			var c := cell_pos([rng.randf_range(2.8, 9.2), rng.randf_range(2.8, 9.2)], rng.randf_range(-3000.0, 3000.0))
			var ok := true
			for kp in keep: if c.distance_to(kp[0]) < float(kp[1]) + r * 0.5: ok = false
			for oc in clouds: if c.distance_to(oc["center"]) < (float(oc["radius"]) + r) * 0.75: ok = false
			if not ok: continue
			var col: Color = cols[rng.randi() % cols.size()] if want[0] == "storm" else Color(0.55, 0.5, 0.48).lerp(cols[rng.randi() % cols.size()], 0.25)
			clouds.append({"name": "%s %s" % [Data.UNKNOWN_CLOUD_WORDS[rng.randi() % Data.UNKNOWN_CLOUD_WORDS.size()], "Shoals" if want[0] == "rocks" else "Veil"],
				"center": c, "radius": r, "color": col, "main": false, "weather": want[0], "layout": true, "uncharted": true})
			made += 1
	sy["layout_clouds"] = clouds

## v8.9 (owner): the unknown areas: the sun in the middle and everything on its own orbit round it (each keeps its bearing).
static func _orbit_layout(id: String, sy: Dictionary) -> void:
	sy["sun_center"] = true
	var O: Dictionary = Data.UNKNOWN_ORBITS
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("orbits:" + id)
	var put := func(p: Vector3, r: float) -> Vector3:
		var a := atan2(p.z, p.x) if Vector2(p.x, p.z).length() > 1.0 else rng.randf() * TAU
		return Vector3(cos(a) * r, clampf(p.y, -3000.0, 3000.0), sin(a) * r)
	var st_old: Vector3 = sy["station"]["pos"]
	sy["station"]["pos"] = put.call(st_old, O["station"])
	var shift: Vector3 = (sy["station"]["pos"] as Vector3) - st_old
	sy["planet"]["pos"] = put.call(sy["planet"]["pos"], O["planet"])
	sy["asteroids"]["center"] = put.call(sy["asteroids"]["center"], O["asteroids"])
	sy["nebula"]["center"] = put.call(sy["nebula"]["center"], O["nebula"])
	for g in sy["gates"]: g["pos"] = put.call(g["pos"], O["gate"])
	if not sy["gate"].is_empty() and not sy["gates"].any(func(d): return is_same(d, sy["gate"])): sy["gate"]["pos"] = put.call(sy["gate"]["pos"], O["gate"])
	for x in sy["more_planets"] + sy["more_stations"]: x["pos"] = put.call(x["pos"], rng.randf_range(O["extra"][0], O["extra"][1]))
	var pts: Array = []
	for p in sy["patrols"]: pts.append((p as Vector3) + shift)   # the patrols stay round the station
	sy["patrols"] = pts
	sy["sun_dir"] = ((sy["station"]["pos"] as Vector3).normalized() + Vector3(0, -0.3, 0)).normalized()   # the light runs out from the middle

## v8.9: nothing is placed on (or too near) the sun: anything inside SUN_KEEP_OUT sun radii is pushed straight out.
static func _keep_off_sun(sy: Dictionary) -> void:
	var sp := sun_pos_of(sy)
	var keep: float = Data.SUN_RADIUS * (0.35 if sy.get("small_sun", false) else 1.0) * Data.SUN_KEEP_OUT
	var push := func(p: Vector3, r: float) -> Vector3:
		var need := keep + r
		var d := p - sp
		if d.length() >= need: return p
		if d.length() < 1.0: d = Vector3(1, 0, 0)
		return sp + d.normalized() * need
	sy["station"]["pos"] = push.call(sy["station"]["pos"], 2000.0)
	sy["planet"]["pos"] = push.call(sy["planet"]["pos"], float(sy["planet"]["radius"]) * 1.5)
	sy["asteroids"]["center"] = push.call(sy["asteroids"]["center"], float(sy["asteroids"]["radius"]))
	sy["nebula"]["center"] = push.call(sy["nebula"]["center"], float(sy["nebula"].get("radius", 400.0)) * Data.NEBULA_SIZE)
	for g in sy["gates"]: g["pos"] = push.call(g["pos"], 2000.0)
	for x in sy["more_planets"] + sy["more_stations"]: x["pos"] = push.call(x["pos"], float(x.get("radius", 100.0)) * 1.5 + 1000.0)

## v8.9: everything stays inside the tile, a margin in from its edge (the border is where you cross to the next square).
static func _keep_in_tile(sy: Dictionary) -> void:
	var lim: float = Data.SPACE_EDGE * 0.88
	var clampv := func(p: Vector3) -> Vector3:
		var q := _soft(p)
		return Vector3(clampf(q.x, -lim, lim), q.y, clampf(q.z, -lim, lim))
	var pl: float = Data.SPACE_EDGE * Data.PLACE_EDGE   # v11.69 (owner): places stay out of the border squares (fields and clouds may sit there)
	var place := func(p: Vector3) -> Vector3:
		var q := _soft(p)
		return Vector3(clampf(q.x, -pl, pl), q.y, clampf(q.z, -pl, pl))
	sy["station"]["pos"] = place.call(sy["station"]["pos"])
	sy["planet"]["pos"] = place.call(sy["planet"]["pos"])
	sy["asteroids"]["center"] = clampv.call(sy["asteroids"]["center"])
	sy["nebula"]["center"] = clampv.call(sy["nebula"]["center"])
	for g in sy["gates"]: g["pos"] = place.call(g["pos"])
	for x in sy["more_planets"] + sy["more_stations"]: x["pos"] = place.call(x["pos"])

## One gate in system `a` leading to `b`, set in the direction `b` lies on the map (north on the map = -Z in flight).
static func _link(out: Dictionary, rows: Dictionary, kind: String, a: String, b: String, wrap := false) -> void:
	for g in out[a]["gates"]:
		if g["to"] == b: return
	var ta: Array = rows[a]
	var tb: Array = rows[b]
	var dx: int = int(tb[3]) - int(ta[3])
	var dz: int = int(tb[4]) - int(ta[4])
	if wrap:   # (v6.5: the short way round the wrapping board)
		dx = posmod(dx + 5, 11) - 5
		dz = posmod(dz + 5, 11) - 5
	var dir := Vector3(float(dx), 0, float(dz)).normalized()
	var k: Array = GATE_KINDS[kind]
	var n: int = out[a]["gates"].size()
	out[a]["gates"].append({"id": "%s_gate_%s" % [a, b], "name": "%s %s" % [tb[1], k[0]], "pos": CENTRE + dir * float(k[2]) + Vector3(0, 70.0 * n, 0),
		"to": b, "gkind": kind})

## Sun surfaces for every system (one looping tile each), merged into Surface.PLANETS.
static func suns(have: Dictionary) -> Dictionary:
	var out := {}
	for t in GalaxyData.TILES + open_rows():
		var pid: String = t[0] + "_sun"
		if not have.has(pid): out[pid] = {"name": "%s's Star" % t[1], "system": t[0], "grid": 1, "tiles": ["sun"], "locations": [], "sun": true}
	return out


## v1.4l: a one-tile surface for every planet that has none yet (the main planet of each generated system and every
## catalog planet). One tile wraps onto itself, like the stars. The biome follows the planet type (Data.PLANET_BIOME),
## so a yellow world is yellow on the ground. Ids match the ones built above: <sys>_planet and <sys>_planet_<n>.
## v12.26: the planets added to a system by hand or by the builder (SYSTEM_LAYOUT add_planets: Solara's Haven, the
## second worlds) get a surface too, so you can fly down into them instead of hitting them like rock.
static func added_planets(have: Dictionary) -> Dictionary:
	var out := {}
	for sid in Data.SYSTEMS:
		for x in (Data.SYSTEMS[sid] as Dictionary).get("more_planets", []):
			var pid := str(x.get("id", ""))
			if pid == "" or have.has(pid) or out.has(pid): continue
			out[pid] = {"name": str(x["name"]), "system": sid, "grid": 1, "tiles": [Data.PLANET_BIOME.get(str(x.get("palette", "")), "barren")], "locations": []}
	return out

static func planets(have: Dictionary) -> Dictionary:
	var out := {}
	var count := {}
	for t in GalaxyData.TILES + open_rows():
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
