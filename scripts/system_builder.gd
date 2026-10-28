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

## v1.5m: the asteroid field is moved off every trade-lane line (station -> planet, station -> each gate): its middle is
## pushed sideways, level, until the lane passes at least its radius + LANE_BELT_CLEAR away. Lanes stay straight.
static func clear_lanes(out: Dictionary) -> void:
	for id in out:
		var sy: Dictionary = out[id]
		var a: Vector3 = sy["station"]["pos"]
		var ends: Array = [sy["planet"]["pos"]]
		for g in sy["gates"]: ends.append(g["pos"])
		var belt: Dictionary = sy["asteroids"]
		var need: float = float(belt.get("radius", 400.0)) + Data.LANE_BELT_CLEAR
		for it in 12:
			var moved := false
			for b in ends:
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
		"enemy": f[4], "enemy_ships": Data.HOME_FLEETS.get(t[6], []), "enemy_faction": Data.HOME_FACTION.get(t[6], ""), "patrols": patrols, "traffic": [[id + "_station", id + "_planet"]],
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
		if is_unknown(sy): _orbit_layout(id, sy)
		_keep_off_sun(sy)
		_keep_in_tile(sy)

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
	return -(sy.get("sun_dir", Vector3(0, -0.3, 1)) as Vector3).normalized() * Data.SUN_DIST

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
	sy["station"]["pos"] = clampv.call(sy["station"]["pos"])
	sy["planet"]["pos"] = clampv.call(sy["planet"]["pos"])
	sy["asteroids"]["center"] = clampv.call(sy["asteroids"]["center"])
	sy["nebula"]["center"] = clampv.call(sy["nebula"]["center"])
	for g in sy["gates"]: g["pos"] = clampv.call(g["pos"])
	for x in sy["more_planets"] + sy["more_stations"]: x["pos"] = clampv.call(x["pos"])

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
