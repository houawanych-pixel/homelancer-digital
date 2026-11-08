class_name Missions
## Job AI (v1.5f): missions the way Freelancer does them. A station's MISSIONS board offers work; accepting one sets a
## chain of waypoints you follow:
##   bounty (dead)    : fly to the first point (the target's escort wing), beat it, the waypoint moves to the target's
##                      own wing, beat that, destroy the target: paid on the spot.
##   bounty (alive)   : the same chain, but the target bails out: TRACTOR the pilot into your hold and bring them back
##                      to the station that gave you the job to be paid.
##   threats          : two waves of a hostile faction's soldiers at two points of this system (easy = slot 01 soldiers,
##                      hard = the slot 05 elites, paid more). Paid when the last one goes down.
##   escort           : a freighter leaves this station for the planet; raiders ambush it on the way. Keep the raiders
##                      off it (it loses hull while an attacker is close) until it docks: paid then.
## State lives in GS.mission (one job at a time; the bounty's own record stays in GS.bounty). Points are stored as a
## bearing and a distance from the system's station, so the same job builds the same points every visit.
## Everything numeric is in the Job AI block of scripts/data.gd.

## The board of a station: the same offers for the whole visit (made once per docking from the station's id and the
## number of jobs done, so a board changes once you have worked it).
## v1.8o: who a base's jobs (and a planet's patrols) are against: its owner's rival; when the rival has no ships, the
## opening system's rival nation, the owner's raiders, then the nearest permanent enemy with ships. "" = nobody.
static func enemy_of(sys_id: String, owner := "") -> String:
	var sys: Dictionary = Data.SYSTEMS[sys_id]
	var own := owner if owner != "" else str(sys.get("faction", ""))
	var enemy := Factions.rival(own) if Factions.has_fighters(Factions.rival(own)) else ""   # v1.8c (owner): the jobs are against the owner's rival
	if enemy == "": enemy = str(Data.OPENING_SYSTEMS.get(sys_id, {}).get("faction", ""))   # v1.5k: the opening system's rival nation
	if enemy == "": enemy = Factions.raider_of(own)
	if enemy == "":   # nobody raids this owner: the nearest permanent enemy with ships does the dirty work
		for f in Data.MISSION_FALLBACK_ENEMIES:
			if Factions.has_fighters(f): return f
	return enemy

## v1.9b (owner): a planet's board (its docking platform or a base down on it) offers only jobs on THAT planet; a
## station's board only jobs out in space. `where` = "planet" or "station".
const PLANET_KINDS := ["ground", "land_escort", "intercept", "air_sweep", "facility", "planet_invasion"]
## v12.56 (owner: "redo the planetary missions: they're giving you missions from outer space; on the planet only:
## escorting, intercepting, destroying facilities (the dungeons), mechs and pilots, planetary bounty sweeps (20 fighters,
## 30 reinforcements by difficulty); nothing in space unless it's a planetary invasion, where the last part is
## intercepting them in space"): the jobs that run down on a planet
static func on_land(m: Dictionary) -> bool:
	var k := str(m.get("kind", ""))
	return k in PLANET_KINDS
static func offers(sys_id: String, station_id: String, owner := "", where := "station") -> Array:
	var pid := planet_of(sys_id, station_id) if where == "planet" else str(Data.SYSTEMS[sys_id]["planet"].get("id", ""))
	var full := _all_offers(sys_id, station_id, owner, pid)
	if where != "planet": return full.filter(func(o): return not planet_board_kind(str(o["kind"])))
	return full.filter(func(o): return planet_board_kind(str(o["kind"])))
## v12.58: what the planet board offers: the planet's jobs, and the final armada (it's fought in orbit)
static func planet_board_kind(k: String) -> bool: return k in PLANET_KINDS or k == "mothership"

## The planet a base belongs to: the planet itself, a base down on it, else the system's main planet.
static func planet_of(sys_id: String, base_id: String) -> String:
	if Surface.has_surface(base_id): return base_id
	for pid in Surface.PLANETS:
		for l in Surface.PLANETS[pid].get("locations", []):
			if str(l.get("id", "")) == base_id: return str(pid)
	return str(Data.SYSTEMS[sys_id]["planet"].get("id", ""))

static func _all_offers(sys_id: String, station_id: String, owner: String, pid: String) -> Array:
	var sys: Dictionary = Data.SYSTEMS[sys_id]
	var enemy := enemy_of(sys_id, owner)   # v1.8o (owner): a base's jobs are against ITS owner's rival (a planet base's too)
	var foe := enemy if enemy != "" else str(Data.ENEMIES[sys["enemy"]]["name"])   # v1.8o: nobody with a roster to send: the system's own raiders (the threats job is always there)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(station_id) + GS.missions_done * 7919
	var out: Array = []
	for hard in [false, true]:   # v1.8o (owner): destroying enemy soldiers is always on the board
		var pay := int(Data.MISSION_PAY["threats"] * (Data.MISSION_HARD_MULT if hard else 1.0))
		out.append({"kind": "threats", "hard": hard, "faction": enemy, "slot": Data.MISSION_HARD_SLOT if hard else Data.MISSION_PATROL_SLOT, "pay": pay,
			"title": "%s: eliminate the %s threat" % ["ELITE" if hard else "PATROL", foe], "giver": station_id, "giver_sys": sys_id, "sys": sys_id,
			"brief": "%s %s have been seen in two places in the %s system. Clear both. %s" % ["Elite" if hard else "", foe, sys["name"],
				"Their best soldiers: expect a hard fight." if hard else "Veteran soldiers: a real fight."],
			"points": _points(rng, 2)})
	if Factions.has_fighters(enemy) or enemy != "":
		out.append({"kind": "escort", "faction": enemy, "slot": 2, "pay": Data.MISSION_PAY["escort"], "title": "Escort a freighter to %s" % sys["planet"]["name"],
			"giver": station_id, "giver_sys": sys_id, "sys": sys_id,
			"brief": "A freighter is leaving for %s. Stay with it: %s will try to stop it on the way. If it arrives, you are paid." % [sys["planet"]["name"], enemy if enemy != "" else "raiders"],
			"points": _points(rng, 2)})
		var dest := convoy_dest(sys_id)   # v1.7w: the cargo run into the next system
		if dest != "":
			out.append({"kind": "convoy", "faction": enemy, "slot": 2, "pay": Data.MISSION_PAY["convoy"], "title": "Cargo run to %s" % Data.SYSTEMS[dest]["name"],
				"giver": station_id, "giver_sys": sys_id, "sys": sys_id, "dest": dest, "leg": 0,
				"brief": "A freighter is taking cargo to %s in the %s system. Fly with it to the jump gate, follow it through, and get it to the station there. %s will hit it on both sides of the gate." % [Data.SYSTEMS[dest]["station"]["name"], Data.SYSTEMS[dest]["name"], enemy if enemy != "" else "Raiders"],
				"points": _points(rng, 2)})
	# v1.8m: a strike down on the planet (last, so the older offers keep their points); v1.9b: on the board's own planet
	var pname: String = str(Surface.PLANETS.get(pid, {}).get("name", sys["planet"]["name"]))
	if enemy != "" and Surface.has_surface(pid) and not Surface.is_sun(pid):
		var g := Surface.grid(pid)
		var tile := rng.randi() % (g * g)
		for k in g * g:   # v1.8n: a sector with land to stand on (the mechs walk): not the open ocean
			if str(Surface.PLANETS[pid]["tiles"][tile]) != "ocean": break
			tile = (tile + 1) % (g * g)
		var p0 := _dry_point(rng, pid, tile, Vector2.INF)
		var p1 := _dry_point(rng, pid, tile, p0)
		out.append({"kind": "ground", "faction": enemy, "slot": 2, "pay": Data.MISSION_PAY["ground"], "title": "Strike on %s: destroy the %s landing party" % [pname, enemy],
			"giver": station_id, "giver_sys": sys_id, "sys": sys_id, "planet": pid, "tile": tile,
			"brief": "%s have landed on %s, in %s. Fly down into the atmosphere, go to both mission points and destroy them: ships overhead and mechs on the ground." % [enemy, pname, sector_name(pid, tile)],
			"points": [{"x": p0.x, "z": p0.y}, {"x": p1.x, "z": p1.y}]})
	# v1.9a (owner): on the planet: escort a freighter (sector to sector)
	# v12.56 (owner: "not one dock to the other: one's the alliance, one's the rival; you don't send things to your
	# rivals: from the dock to your own facility"): from the dock that gives the job to one of its own side's facilities
	if enemy != "" and Surface.has_surface(pid) and not Surface.is_sun(pid):
		var locs: Array = Surface.PLANETS[pid].get("locations", [])
		var ia := -1
		for i in locs.size(): if str(locs[i].get("id", "")) == station_id: ia = i
		if ia >= 0:
			var side := str(locs[ia].get("faction", ""))
			var own: Array = (Surface.facility_sites(pid) as Array).filter(func(st): return str(st.get("faction", "")) == side)
			if not own.is_empty():
				var st: Dictionary = own[rng.randi() % own.size()]
				var to := {"name": str(st["name"]), "tile": int(st["tile"]), "pos": st["spot"]}
				out.append({"kind": "land_escort", "faction": enemy, "slot": 2, "pay": Data.MISSION_PAY["land_escort"], "planet": pid, "from": ia, "to": to,
					"title": "Escort a supply freighter on %s: %s to %s" % [pname, locs[ia]["name"], to["name"]],
					"giver": station_id, "giver_sys": sys_id, "sys": sys_id, "pos": [], "points": [{}, {}],
					"brief": "A supply freighter is flying from %s to our facility %s on %s. Go down and stay with it: %s will hit it on the way. It waits for you when you are not with it." % [locs[ia]["name"], to["name"], pname, enemy]})
	if Surface.has_surface(pid) and not Surface.is_sun(pid):
		_planet_offers(out, rng, sys_id, station_id, pid, enemy if enemy != "" else foe)
	# v1.8p (owner): the system's own outlaws (raiders / corsairs) are always a job too: there is no end of them
	var outlaw := str(Data.ENEMIES[sys["enemy"]]["name"])
	out.append({"kind": "outlaws", "faction": "", "slot": 1, "pay": Data.MISSION_PAY["outlaws"], "title": "%sS: clear the %s threat" % [outlaw.to_upper(), outlaw], "giver": station_id, "giver_sys": sys_id, "sys": sys_id,
		"brief": "%ss have been seen in two places in the %s system. Clear both. Outlaws, not soldiers: an easier fight, smaller pay." % [outlaw, sys["name"]],
		"points": _points(rng, 2)})
	# v11.26 (owner): INVESTIGATE ENEMY DISTURBANCE: a hidden enemy in one of the system's nebula clouds (only where
	# the system has a cloud): a battleship (10 fighters always out) or a hidden station (15); hard, big pay
	var clouds: Array = SpaceSystem.nebulae_of(sys_id, sys).filter(func(c): return not bool(c.get("backdrop", false)) and SystemBuilder.inside_cells(c["center"]) == c["center"])   # (v12.2: not the backdrop clouds; v12.3: never one out on the border)
	if enemy != "" and not clouds.is_empty():
		var cl: Dictionary = clouds[rng.randi() % clouds.size()]
		# v12.6 (owner: "that mission is right next to that space station, way too close"): a cloud marked for it, else
		# one well clear of every station (the farthest if none is)
		var marked: Array = clouds.filter(func(c): return bool(c.get("disturbance", false)))
		var spots: Array = [sys["station"]["pos"]] + (sys.get("more_stations", []) as Array).map(func(x): return x["pos"])
		var gap := func(c: Dictionary) -> float:
			var g := INF
			for sp in spots: g = minf(g, (c["center"] as Vector3).distance_to(sp) - float(c["radius"]))
			return g
		if not marked.is_empty(): cl = marked[0]
		else:
			var clear: Array = clouds.filter(func(c): return gap.call(c) > Data.DISTURBANCE_STATION_GAP)
			if not clear.is_empty(): cl = clear[rng.randi() % clear.size()]
			else:
				for c in clouds: if gap.call(c) > gap.call(cl): cl = c
		var st0: Vector3 = sys["station"]["pos"]
		var v: Vector3 = (cl["center"] as Vector3) - st0
		for which in ["ship", "base"]:
			var pk: String = "disturbance_" + str(which)
			out.append({"kind": "disturbance", "target": which, "faction": enemy, "slot": Data.PATROL_MAX_SLOT, "pay": Data.MISSION_PAY[pk],
				"title": "Investigate disturbance: the %s cloud" % str(cl.get("name", "nebula")) if str(cl.get("name", "")) != "" else "Investigate disturbance in the nebula",
				"giver": station_id, "giver_sys": sys_id, "sys": sys_id, "cloud": str(cl.get("name", "")),
				# v12.3 (owner: "it should just be: investigate the cloud over in this sector, ships have been disappearing ...
				# they're not gonna tell you there's a battleship there"): only what they know
				"brief": "Ships have been disappearing in the %s cloud, sector %s. Our fighters picked up something big in there before we lost contact. Investigate the disturbance. Be cautious." % [str(cl.get("name", "")) if str(cl.get("name", "")) != "" else "nebula", _sector(cl["center"])],
				"points": [{"dir": atan2(v.z, v.x), "dist": Vector2(v.x, v.z).length(), "y": 0.0}]})
	# v1.9n (owner): SILVER: the rival faction's fleet invades this system (3 battleships to kill; allies fly with you)
	if enemy != "":
		out.append({"kind": "invasion", "faction": enemy, "slot": Data.PATROL_MAX_SLOT, "pay": Data.MISSION_PAY["invasion"], "title": "SILVER: %s fleet invasion" % enemy,
			"giver": station_id, "giver_sys": sys_id, "sys": sys_id, "left": int(Data.INVASION["battleships"]),
			"brief": "A %s invasion fleet is coming into the %s system: one heavy battleship and a Star Command Station launching fighters. Our wing and a frigate fly with you. Destroy the battleship. Knock out the station to slow their fighters. This is a war, not a patrol." % [enemy, sys["name"]],
			"points": _points(rng, 1).map(func(p): p["dist"] = float(Data.INVASION["dist"]); p["y"] = 0.0; return p)})
	return out

## v12.56: the planet's own jobs (besides the strike and the base-to-base escort): INTERCEPT a raiding wing, the
## AIR SWEEP (the planetary bounty: two waypoints, a big wing and its reinforcements, sized by difficulty), DESTROY A
## FACILITY of the other side (the dungeon), and the PLANETARY INVASION (gold: their battleships in the atmosphere,
## then the fleet in orbit).
static func _planet_offers(out: Array, rng: RandomNumberGenerator, sys_id: String, station_id: String, pid: String, enemy: String) -> void:
	var pname: String = str(Surface.PLANETS.get(pid, {}).get("name", "the planet"))
	var g := Surface.grid(pid)
	var land_tile := func() -> int:
		var t := rng.randi() % (g * g)
		for k in g * g:
			if str(Surface.PLANETS[pid]["tiles"][t]) != "ocean": break
			t = (t + 1) % (g * g)
		return t
	var base := {"giver": station_id, "giver_sys": sys_id, "sys": sys_id, "planet": pid, "faction": enemy}
	# INTERCEPT (owner: "intercept an enemy going to an enemy facility: their transport; you run into their mechs, like
	# Armored Core"): one of the other side's transports is flying in to its facility with fighters round it and mechs
	# on the ground by the facility: bring it down before it gets there
	var mine0 := ""
	for l in Surface.PLANETS[pid].get("locations", []): if str(l.get("id", "")) == station_id: mine0 = str(l.get("faction", ""))
	var theirs: Array = (Surface.facility_sites(pid) as Array).filter(func(st): return mine0 == "" or str(st.get("faction", "")) != mine0)
	if not theirs.is_empty():
		var fs: Dictionary = theirs[rng.randi() % theirs.size()]
		var fsp: Vector2 = fs["spot"]
		var ang := rng.randf() * TAU
		var st0 := fsp + Vector2(cos(ang), sin(ang)) * Data.TRANSPORT_RUN
		st0 = Vector2(clampf(st0.x, -Surface.EDGE + 400.0, Surface.EDGE - 400.0), clampf(st0.y, -Surface.EDGE + 400.0, Surface.EDGE - 400.0))
		out.append(base.merged({"kind": "intercept", "faction": str(fs.get("faction", enemy)), "slot": 2, "pay": Data.MISSION_PAY["intercept"], "tile": int(fs["tile"]),
			"site": str(fs["name"]), "to": {"x": fsp.x, "z": fsp.y},
			"title": "Intercept: a %s transport bound for %s" % [str(fs.get("faction", enemy)), fs["name"]],
			"brief": "A %s transport is flying supplies in to their facility %s on %s, %s, with fighters round it and their mechs on the ground at the facility. Bring the transport down before it gets there." % [str(fs.get("faction", enemy)), fs["name"], pname, sector_name(pid, int(fs["tile"]))],
			"points": [{"x": st0.x, "z": st0.y}]}))
	for hard in [false, true]:
		var t2: int = land_tile.call()
		var a := _dry_point(rng, pid, t2, Vector2.INF)
		var b := _dry_point(rng, pid, t2, a)
		var wv: Array = Data.AIR_SWEEP_HARD if hard else Data.AIR_SWEEP
		out.append(base.merged({"kind": "air_sweep", "hard": hard, "slot": Data.MISSION_HARD_SLOT if hard else 2, "pay": int(Data.MISSION_PAY["air_sweep"] * (Data.MISSION_HARD_MULT if hard else 1.0)), "tile": t2,
			"title": "%sBounty sweep on %s: %d fighters, %d more coming" % ["ELITE " if hard else "", pname, int(wv[0][0]), int(wv[1][0])],
			"brief": "Bounty board: %s fighters are holding two waypoints over %s, %s. Clear the first (%d of them) and their reinforcements at the second (%d). Paid by the head when it's done." % [enemy, pname, sector_name(pid, t2), int(wv[0][0]), int(wv[1][0])],
			"points": [{"x": a.x, "z": a.y}, {"x": b.x, "z": b.y}], "waves": wv}))
	# the other side's facilities on this world (the dungeons)
	var mine := ""
	for l in Surface.PLANETS[pid].get("locations", []): if str(l.get("id", "")) == station_id: mine = str(l.get("faction", ""))
	var shown := 0
	for st in Surface.facility_sites(pid):
		if shown >= 2: break
		if mine != "" and str(st.get("faction", "")) == mine: continue
		shown += 1
		var lv := int(st.get("difficulty", 1))
		out.append(base.merged({"kind": "facility", "slot": 2, "pay": Data.FACILITY_PAY * lv + Data.MISSION_PAY["facility"], "tile": int(st["tile"]), "site": str(st["name"]),
			"title": "Destroy %s (level %d facility)" % [st["name"], lv],
			"brief": "%s's facility %s is dug in on %s, %s. Fly down, find the entrance and go in: fight through to its reactor and blow it. Expect their mechs and their pilots." % [str(st.get("faction", enemy)), st["name"], pname, sector_name(pid, int(st["tile"]))],
			"points": [{"x": (st["spot"] as Vector2).x, "z": (st["spot"] as Vector2).y}]}))
	# v12.58 (owner: "the planetary invasion: in the sky a battleship with fighters; weaken it, dock on it, destroy it from
	# inside; only then come out and destroy the remaining fighters; then you get paid. A harder version: two battleships.
	# Only inside the planet"): GOLD (one battleship) and GOLD+ (two)
	for lv in [1, 2]:
		var t3: int = land_tile.call()
		var c := _dry_point(rng, pid, t3, Vector2.INF)
		out.append(base.merged({"kind": "planet_invasion", "slot": Data.PATROL_MAX_SLOT, "pay": Data.MISSION_PAY["planet_invasion"] * lv, "tile": t3,
			"left": lv, "bs_down": 0,
			"title": "%s: %s invasion of %s (%d battleship%s)" % ["GOLD" if lv == 1 else "GOLD+", enemy, pname, lv, "" if lv == 1 else "s"],
			"brief": "A %s invasion is coming down on %s: %s in the sky over %s, fighters all round. Strip its shield, dock on it and destroy it from the inside; then come out and finish the fighters. Paid when the sky is clear." % [enemy, pname, "a battleship" if lv == 1 else "two battleships", sector_name(pid, t3)],
			"points": [{"x": c.x, "z": c.y}], "waves": [[Data.PLANET_INV_FIGHTERS * lv, 3]]}))
	# v12.58 (owner: "a final mission: outside the atmosphere: 3 battleships, 5 vessels and a mothership (infinite high-level
	# fighters; battleships carry 90 each, vessels 30). Destroy all 3 battleships before you can dock the mothership; it's
	# huge, you fly inside with the ship ... for now space stations as placeholders")
	out.append(base.merged({"kind": "mothership", "slot": Data.PATROL_MAX_SLOT, "pay": Data.MISSION_PAY["mothership"], "left": 3,
		"title": "FINAL: the %s armada over %s" % [enemy, pname],
		"brief": "The %s armada is holding orbit over %s: three battleships, five warships and their MOTHERSHIP, which never stops launching its best fighters. Break the three battleships; then its shield drops: dock with the mothership and fly in. It's a maze of tunnels and chambers: fly it with care (side moves and dodges are safe, ramming the walls under thrust is not). Destroy it from the inside." % [enemy, pname],
		"points": [{"dir": rng.randf() * TAU, "dist": float(Data.INVASION["dist"]), "y": 0.0}]}))

## v1.8n: a ground job's point: on dry land when a few tries find some, and well away from the other point.
static func _dry_point(rng: RandomNumberGenerator, pid: String, tile: int, other: Vector2) -> Vector2:
	var sp: float = Data.MISSION_GROUND_SPREAD
	var best := Vector2.ZERO
	for k in 10:
		var p := Vector2(rng.randf_range(-sp, sp), rng.randf_range(-sp, sp))
		if k == 0: best = p
		if other != Vector2.INF and p.distance_to(other) < sp * 0.6: continue
		best = p
		if Surface.height(pid, tile, p.x, p.y) > 3.0: break
	return best

## v1.8m: "sector B2 (city)": how a ground job names its place on the planet.
static func sector_name(pid: String, tile: int) -> String:
	var g := Surface.grid(pid)
	return "sector %s%d (%s)" % ["ABCDEFG"[tile / g], tile % g + 1, str(Surface.biome(pid, tile)["name"]).to_lower()]

## v1.8m: where a ground job's point is from the sector you are flying over (the planet wraps: the short way round).
static func ground_pos(space: SpaceSystem, i: int) -> Vector3:
	var m: Dictionary = GS.mission
	var pts: Array = m.get("points", [])
	if i < 0 or i >= pts.size() or not space.surface_mode or space.planet_id != str(m.get("planet", "")): return Vector3.INF
	var g := Surface.grid(space.planet_id)
	var dx := int(m["tile"]) % g - space.tile % g
	var dz := int(m["tile"]) / g - space.tile / g
	if dx * 2 > g: dx -= g
	elif dx * 2 < -g: dx += g
	if dz * 2 > g: dz -= g
	elif dz * 2 < -g: dz += g
	var x := float(pts[i]["x"]) + dx * Surface.TILE
	var z := float(pts[i]["z"]) + dz * Surface.TILE
	return Vector3(x, (space._ground(x, z) if dx == 0 and dz == 0 else 0.0) + Data.MISSION_GROUND_ALT, z)

## v1.7w: where a cargo run from this system goes: the system through its first jump gate ("" = no gate out).
static func convoy_dest(sys_id: String) -> String:
	for g in Data.SYSTEMS[sys_id].get("gates", []):
		if Data.SYSTEMS.has(str(g.get("to", ""))): return str(g["to"])
	return ""

static func _sector(p: Vector3) -> String:   # v12.3: a map square's name, "E5"
	var c := SystemBuilder.cell_of(p)
	return "%s%d" % ["ABCDEFGHIJ"[clampi(int(c.x) - 1, 0, 9)], clampi(int(c.y), 1, 10)]

static func _points(rng: RandomNumberGenerator, n: int, far := 0.0) -> Array:
	var pts: Array = []
	var a := rng.randf() * TAU
	var lo: float = Data.BOUNTY_POINT_DIST[0] + far if far > 0.0 else Data.MISSION_POINT_DIST[0]
	var hi: float = Data.BOUNTY_POINT_DIST[1] + far if far > 0.0 else Data.MISSION_POINT_DIST[1]
	for i in n:
		pts.append({"dir": a, "dist": rng.randf_range(lo, hi), "y": rng.randf_range(-200.0, 300.0)})
		a += rng.randf_range(1.6, 2.6)
	return pts

## Where a mission point is in this system (the points are relative to the main station).
static func point_pos(space: SpaceSystem, i: int) -> Vector3:
	var m: Dictionary = GS.mission
	if m.get("kind", "") == "ground" or (on_land(m) and m.has("tile")): return ground_pos(space, i)
	var pts: Array = m.get("points", [])
	if i < 0 or i >= pts.size() or not is_instance_valid(space.station): return Vector3.INF
	var p: Dictionary = pts[i]
	var base: Vector3 = space.station.global_position
	var dir := Vector3(cos(float(p["dir"])), 0.0, sin(float(p["dir"])))
	var at := SystemBuilder.inside_cells(base + dir * float(p["dist"]) + Vector3(0, float(p.get("y", 0.0)), 0))   # (v12.3: never on the border)
	if is_instance_valid(space.planet):   # never inside a planet's air: step out along the bearing until clear
		var keep: float = float(space.sys["planet"].get("radius", 800.0)) + Data.MISSION_PLANET_CLEAR
		for k in 12:
			if at.distance_to(space.planet.global_position) >= keep: break
			at += dir * 600.0
	return at

## Take a job from the board. "" = taken.
static func accept(offer: Dictionary) -> String:
	var dropped := ""
	if not GS.mission.is_empty() or not GS.bounty.is_empty():   # v12.60 (owner): accepting a job disengages the one you had
		dropped = disengage() + " "
	var m := offer.duplicate(true)
	m["stage"] = 0
	m["spawned"] = -1
	m["escort_hp"] = Data.ESCORT_HULL
	m["start"] = m.duplicate(true)   # v1.9r: how the job looked when taken (dying restarts it from here)
	GS.mission = m
	GS.changed.emit()
	return "%sJob taken: %s. %s A mission waypoint is set: follow the gold marker." % [dropped, m["title"], m["brief"]]

## The bounty board's jobs go through here too: the target's record stays in GS.bounty (older code reads it); the
## chain of points is the mission.
static func accept_bounty(id: String) -> String:
	var p: Dictionary = Data.roster_pilot(id)
	if p.is_empty(): return "No such bounty."
	if not GS.mission.is_empty() or GS.bounty.get("state", "") == "captured": disengage()   # v12.60 (owner): the new job replaces the old one
	var said := GS.accept_bounty(id)
	if GS.bounty.get("id", "") != id: return said
	GS.bounty["sys"] = GS.system_id   # v1.7v (owner): the hunt happens in the system you took it in, not far away
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var alive: bool = int(p.get("rank", 1)) >= Data.BOUNTY_ALIVE_RANK
	GS.mission = {"kind": "bounty", "id": id, "alive": alive, "faction": str(p.get("faction", "")), "slot": 2, "pay": Data.bounty_reward(id),
		"title": "Bounty: %s (%s)" % [p["name"], "wanted alive" if alive else "wanted dead"], "giver": GS.last_base, "giver_sys": GS.system_id, "sys": GS.system_id,
		"brief": "%s has been tracked to the %s system with an escort wing. Fly to the first waypoint and deal with the escort; then the waypoint moves to %s. %s" % [p["name"], Data.SYSTEMS[GS.system_id]["name"], p["name"],
			"Destroy the ship, TRACTOR the pilot in and bring them back here." if alive else "Destroy the ship: paid on the spot."],
		"points": _points(rng, 2, Data.BOUNTY_DIST_PER_RANK * float(clampi(int(p.get("rank", 1)), 1, 6))), "stage": 0, "spawned": -1, "escort_hp": 0.0,
		"rank": clampi(int(p.get("rank", 1)), 1, 6)}   # v11.97 (owner): further out, waves by level (Data.BOUNTY_WAVES)
	GS.mission["start"] = GS.mission.duplicate(true)   # v1.9r
	GS.changed.emit()
	return "Bounty accepted: %s. %s A mission waypoint is set: follow the gold marker." % [p["name"], GS.mission["brief"]]

# ---------------------------------------------------------------- v1.5k: select / deselect / switch on the board
## Is this board offer the job being tracked?
static func is_current(offer: Dictionary) -> bool:
	var m: Dictionary = GS.mission
	return not m.is_empty() and m.get("kind", "") == offer.get("kind", "") and bool(m.get("hard", false)) == bool(offer.get("hard", false)) and str(m.get("giver", "")) == str(offer.get("giver", ""))

## Tap on a job: not tracked -> track it (dropping whatever was tracked); tracked -> drop it.
static func toggle(offer: Dictionary) -> String:
	if is_current(offer):
		abandon()
		return "Stopped tracking: %s." % offer["title"]
	return accept(offer)   # (v12.60: it drops what you had)

## Tap on a bounty: the same rules.
static func toggle_bounty(id: String) -> String:
	if GS.bounty.get("id", "") == id and GS.bounty.get("state", "") == "hunt":
		abandon()
		GS.bounty = {}
		GS.changed.emit()
		return "Stopped tracking the bounty on %s." % Data.roster_pilot(id).get("name", id)
	if not GS.mission.is_empty() or not GS.bounty.is_empty(): disengage()   # (v12.60: it drops what you had)
	return accept_bounty(id)

## The one thing that can stop a switch: a prisoner in the hold must be handed in first.
static func _switch_block() -> String:
	if not GS.mission.is_empty():   # v11.97 (owner): one mission at a time
		return "You already have a job: %s. Finish it or DISENGAGE first: one mission at a time." % str(GS.mission.get("title", "a job"))
	if GS.bounty.get("state", "") == "captured":
		return "%s is in your hold: hand them in at %s first, or DISENGAGE to let them go." % [Data.roster_pilot(str(GS.bounty["id"])).get("name", "The pilot"), giver_name(GS.mission) if not GS.mission.is_empty() else Data.SYSTEMS[GS.system_id]["station"]["name"]]
	return ""

## What the board says is being tracked and where its waypoint leads, from here (works docked: no space needed).
static func tracking_line(here: String) -> String:
	var m: Dictionary = GS.mission
	if m.is_empty(): return "Tracking: nothing. Select a job or a bounty."
	var where := str(m.get("sys", here))
	if m.get("kind", "") == "bounty" and GS.bounty.get("state", "") == "captured":
		return "Tracking: %s. Waypoint: back to %s." % [m["title"], Data.SYSTEMS[m["giver_sys"]]["station"]["name"]]
	if where != here:
		var route: Array = Data.gate_route(here, where)
		var gate_name := "?"
		if route.size() >= 2:
			for g in Data.SYSTEMS[here]["gates"]:
				if str(g["to"]) == str(route[1]): gate_name = str(g["name"])
		return "Tracking: %s. Waypoint: %s, %d jump%s away (first take the %s)." % [m["title"], Data.SYSTEMS[where]["name"], route.size() - 1, "" if route.size() == 2 else "s", gate_name]
	if m.get("kind", "") == "ground": return "Tracking: %s. Waypoint: down on %s, %s." % [m["title"], Surface.PLANETS[m["planet"]]["name"], sector_name(str(m["planet"]), int(m["tile"]))]
	return "Tracking: %s. Waypoint: mission point %d of %d in this system." % [m["title"], int(m.get("stage", 0)) + 1, (m.get("points", []) as Array).size()]

## Drop the job (no pay, no penalty beyond the lost time).
## v1.9o (owner: "I need to abort a mission"): DISENGAGE: drop the job you have, wherever you are. A prisoner in the
## hold is let go (out of the hold, back to flying).
static func disengage() -> String:
	if GS.mission.is_empty() and GS.bounty.is_empty(): return "No job to drop."
	var title := str(GS.mission.get("title", "the bounty"))
	var freed := ""
	if GS.bounty.get("state", "") == "captured": freed = release_captive()
	abandon()
	GS.bounty = {}
	GS.changed.emit()
	return "Disengaged: %s.%s Pick another job when you are ready." % [title, (" %s" % freed) if freed != "" else ""]

## The prisoner in the hold walks free (no pay). Returns what to say ("" = nobody aboard).
static func release_captive() -> String:
	if GS.bounty.get("state", "") != "captured": return ""
	var id := str(GS.bounty.get("id", ""))
	GS.cargo = GS.cargo.filter(func(c): return not (c.get("kind", "") == "pilot" and str(c.get("id", "")) == id))
	GS.bounty = {}
	GS.changed.emit()
	return "%s is out of your hold and free." % Data.roster_pilot(id).get("name", "The pilot")

## v1.9r (owner: "if you die the mission should be failed and restarted from the beginning"): the job goes back to
## how it was when taken (first waypoint, every wave again, a fresh freighter); a prisoner in the hold is lost and the
## bounty is hunted again. Returns what to say ("" = no job).
static func restart_after_death() -> String:
	if GS.mission.is_empty(): return ""
	var m: Dictionary = GS.mission
	var title := str(m.get("title", "the job"))
	var fresh: Dictionary = (m.get("start", {}) as Dictionary).duplicate(true)
	if fresh.is_empty():   # (a job taken before v1.9r)
		fresh = m.duplicate(true)
		fresh["stage"] = 0
		fresh["spawned"] = -1
		fresh["escort_hp"] = Data.ESCORT_HULL if str(m.get("kind", "")) != "bounty" else 0.0
	fresh["start"] = fresh.duplicate(true)
	if not GS.bounty.is_empty() and str(m.get("kind", "")) == "bounty":
		var id := str(GS.bounty.get("id", ""))
		GS.cargo = GS.cargo.filter(func(c): return not (c.get("kind", "") == "pilot" and str(c.get("id", "")) == id))
		GS.bounty = {"id": id, "sys": str(fresh.get("sys", GS.system_id)), "state": "hunt"}
	GS.mission = fresh
	GS.mission_fails += 1
	GS.changed.emit()
	return "MISSION FAILED: %s. It restarts from the beginning: follow the gold waypoint again." % title

static func abandon() -> void:
	if GS.mission.is_empty(): return
	if GS.mission.get("kind", "") == "bounty" and GS.bounty.get("state", "") == "hunt": GS.bounty = {}
	GS.mission = {}
	GS.changed.emit()

## What the HUD and the map point at, in THIS system: {node, title, line, hops} or {} when the job has nothing here.
static func waypoint(space: SpaceSystem) -> Dictionary:
	var m: Dictionary = GS.mission
	if m.is_empty() or not is_instance_valid(space.player): return {}
	var kind := str(m["kind"])
	var stage := int(m["stage"])
	if kind == "land_escort" and space.surface_mode and space.planet_id == str(m["planet"]):   # v1.9a: the freighter is the waypoint
		if is_instance_valid(space.escort_node):
			return {"node": space.escort_node, "title": space.escort_node.name, "line": "Escort: stay with the freighter to %s (hull %d%%)" % [land_base(m, "to")["name"], int(100.0 * float(m["escort_hp"]) / Data.ESCORT_HULL)], "hops": 0}
		return {}
	if on_land(m) and kind != "ground" and kind != "land_escort":   # v12.56: the planet's own jobs
		if not space.surface_mode:
			if str(m["sys"]) != space.sys_id: return _to_place(space, str(m["sys"]), m["title"])
			var pn2: Node3D = space.planet_node(str(m["planet"]))
			if pn2 == null: return {}
			return {"node": pn2, "title": pn2.name, "line": "%s: fly down into %s's atmosphere, %s" % [m["title"], pn2.name, sector_name(str(m["planet"]), int(m["tile"]))], "hops": 0}
		if space.planet_id != str(m["planet"]): return {}
		if kind == "intercept":
			var trs: Array = space.enemies.filter(func(e): return bool(e.get("transport", false)))
			if not trs.is_empty(): return {"node": trs[0]["node"], "title": trs[0]["node"].name, "line": "Intercept: bring down the transport before it reaches %s" % m["site"], "hops": 0}
			var tw0 := "" if space.tile == int(m["tile"]) else " (%s)" % sector_name(str(m["planet"]), int(m["tile"]))
			return {"node": space.mission_point(point_pos(space, 0)), "title": "Transport", "line": "Intercept: get to the transport's route%s" % tw0, "hops": 0}
		if kind == "facility":
			var fp := space.mission_point(point_pos(space, 0))
			var tw := "" if space.tile == int(m["tile"]) else " (%s)" % sector_name(str(m["planet"]), int(m["tile"]))
			return {"node": fp, "title": str(m["site"]), "line": "Facility: find the entrance of %s and go in%s" % [m["site"], tw], "hops": 0}
	if kind == "ground" or kind == "land_escort":   # v1.8m: in space the planet is the waypoint; down there the points are
		if not space.surface_mode:
			if str(m["sys"]) != space.sys_id: return _to_place(space, str(m["sys"]), m["title"])
			var pn: Node3D = space.planet_node(str(m["planet"]))   # v1.9b: a job on one of the other planets points there
			if pn == null: return {}
			if kind == "land_escort": return {"node": pn, "title": pn.name, "line": "Escort: fly down into %s's atmosphere to the freighter" % pn.name, "hops": 0}
			return {"node": pn, "title": pn.name, "line": "Strike: fly down into %s's atmosphere, %s" % [pn.name, sector_name(str(m["planet"]), int(m["tile"]))], "hops": 0}
		if space.planet_id != str(m["planet"]): return {}
	elif space.surface_mode:   # v1.8y (owner): a job out in space while you are down on a planet: the waypoint is the way up
		var pp: Vector3 = space.player.global_position
		var upn := space.mission_point(Vector3(pp.x, Surface.CEILING + 400.0, pp.z))
		return {"node": upn, "title": "Orbit", "line": "%s: climb above %d m to reach orbit (the job is out in space)" % [m["title"], int(Surface.CEILING)], "hops": 0}
	# bounty, pilot in the hold: back to the station that gave the job
	if kind == "bounty" and GS.bounty.get("state", "") == "captured":
		return giver_place(space, m, "Return to %s: hand %s over" % [giver_name(m), Data.roster_pilot(str(m["id"])).get("name", "the pilot")])
	if str(m["sys"]) != space.sys_id: return _to_place(space, str(m["sys"]), m["title"])
	match kind:
		"invasion", "mothership":   # v1.9n: the fleet's point, then the nearest battleship (v12.56: the planetary one's orbit fight too)
			var bs: Array = space.invasion_units("battleship")
			if int(m.get("spawned", -1)) >= 0 and not bs.is_empty():
				bs.sort_custom(func(x, y): return space.player.global_position.distance_to(x["node"].global_position) < space.player.global_position.distance_to(y["node"].global_position))
				var st: String = "station DOWN" if bool(m.get("station_down", false)) else "station launching fighters"
				return {"node": bs[0]["node"], "title": bs[0]["node"].name, "line": "SILVER: destroy the battleships (%d of %d left) · %d fighters · %s · %d allies" % [bs.size(), int(Data.INVASION["battleships"]), space.invasion_units("fighter").size(), st, space.allies.size()], "hops": 0}
			var ip := space.mission_point(point_pos(space, 0))
			return {"node": ip, "title": "Invasion fleet", "line": "SILVER: fly to the invasion fleet (%d battleship%s)" % [int(m.get("left", 3)), "" if int(m.get("left", 3)) == 1 else "s"], "hops": 0}
		"disturbance":   # v11.26: the cloud, then the hidden battleship / station
			var dc: Dictionary = Data.DISTURBANCE[str(m.get("target", "ship"))]
			var tg: Array = space.invasion_units(str(dc["role"])) + (space.invasion_units("warship") if dc.has("escort") else [])
			if int(m.get("spawned", -1)) >= 0 and tg.is_empty() and not space.invasion_units().is_empty():   # v11.30: the big one is down: the rest
				var rest: Array = space.invasion_units()
				return {"node": rest[0]["node"], "title": rest[0]["node"].name, "line": "DISTURBANCE: finish the rest · %d left" % rest.size(), "hops": 0}
			if int(m.get("spawned", -1)) >= 0 and not tg.is_empty():
				return {"node": tg[0]["node"], "title": tg[0]["node"].name, "line": "DISTURBANCE: destroy the %s · %d fighters out" % ["battleship" if str(m["target"]) == "ship" else ("flagship" if tg[0]["inv_role"] == "flagship" else "cruiser"), space.invasion_units("fighter").size()], "hops": 0}
			return {"node": space.mission_point(point_pos(space, 0)), "title": "Enemy disturbance", "line": "DISTURBANCE: investigate the %s cloud" % str(m.get("cloud", "nebula")), "hops": 0}
		"escort", "convoy":
			if is_instance_valid(space.escort_node):
				return {"node": space.escort_node, "title": space.escort_node.name, "line": "Escort: stay with %s (hull %d%%)" % [space.escort_node.name, int(100.0 * float(m["escort_hp"]) / Data.ESCORT_HULL)], "hops": 0}
			return {}
		_:
			var live: Array = space.enemies.filter(func(o): return int(o.get("mission", -1)) == stage and is_instance_valid(o["node"]))
			if not live.is_empty():
				var boss: Array = live.filter(func(o): return o.has("bounty"))
				var n: Node3D = (boss[0] if not boss.is_empty() else live[0])["node"]
				var what: String = "Destroy %s (%d left)" % [n.name, live.size()] if boss.is_empty() else "Destroy %s's ship%s" % [n.name, ", then TRACTOR the pilot in" if m.get("alive", false) else ""]
				return {"node": n, "title": n.name, "line": what, "hops": 0}
			if kind == "bounty":
				for l in space.loot:
					if l.get("bounty", "") == m["id"] and is_instance_valid(l["node"]): return {"node": l["node"], "title": "%s (pilot)" % Data.roster_pilot(str(m["id"])).get("name", ""), "line": "TRACTOR the pilot in", "hops": 0}
			if stage < (m.get("points", []) as Array).size():
				var mp := space.mission_point(point_pos(space, stage))
				var where := "" if kind != "ground" or space.tile == int(m["tile"]) else ", in %s" % sector_name(str(m["planet"]), int(m["tile"]))
				if on_land(m) and kind != "ground": where = "" if space.tile == int(m["tile"]) else ", in %s" % sector_name(str(m["planet"]), int(m["tile"]))
				var label: String = {"bounty": "Bounty", "ground": "Strike", "intercept": "Intercept", "air_sweep": "Bounty sweep", "planet_invasion": "Invasion"}.get(kind, "Threats")
				return {"node": mp, "title": "Mission point %d" % (stage + 1), "line": "%s: fly to mission point %d of %d%s" % [label, stage + 1, (m["points"] as Array).size(), where], "hops": 0}
	return {}

## v1.9k: the name of the dock that gave the job (stored when it was taken; older saves: that system's station).
static func giver_name(m: Dictionary) -> String:
	return str(m.get("giver_name", Data.SYSTEMS[str(m["giver_sys"])]["station"]["name"]))

## v1.9k: the way back to the dock that gave the job: that very dock when you are in its system (station, a planet's
## platform or a 3D extra station), else the first gate towards it.
static func giver_place(space: SpaceSystem, m: Dictionary, line: String) -> Dictionary:
	if str(m["giver_sys"]) == space.sys_id:
		for n in [space.station] + space.docks3d + space.platforms:
			if is_instance_valid(n) and n.has_meta("info") and str((n.get_meta("info") as Dictionary).get("id", "")) == str(m.get("giver", "")):
				return {"node": n, "title": n.name, "line": line, "hops": 0}
	return _to_place(space, str(m["giver_sys"]), line)

## The gate that starts the shortest way to another system, or that system's station when you are there.
static func _to_place(space: SpaceSystem, sys_id: String, line: String) -> Dictionary:
	if sys_id == space.sys_id:
		if not is_instance_valid(space.station): return {}
		return {"node": space.station, "title": space.station.name, "line": line, "hops": 0}
	var route: Array = Data.gate_route(space.sys_id, sys_id)
	if route.size() < 2: return {}
	for g in space.gates:
		if is_instance_valid(g) and str((g.get_meta("info", {}) as Dictionary).get("to", "")) == str(route[1]):
			var hops: int = route.size() - 1
			return {"node": g, "title": g.name, "line": "%s: %d jump%s to %s. Take the %s" % [line, hops, "" if hops == 1 else "s", Data.SYSTEMS[sys_id]["name"], g.name], "hops": hops}
	return {}

## Every frame in flight: spawn a wave when you reach its point, move the stage on when a wave is gone, run the escort.
static func tick(space: SpaceSystem, dt: float) -> void:
	var m: Dictionary = GS.mission
	if m.is_empty() or not is_instance_valid(space.player) or str(m["sys"]) != space.sys_id: return
	var kind := str(m["kind"])
	var land: bool = on_land(m)
	if land != space.surface_mode: return   # v1.8m: a ground job runs down on the planet, the others in space
	if land and space.planet_id != str(m.get("planet", "")): return
	if kind == "facility": return   # (v12.56: done when you blow its reactor: main.leave_boarding)
	if kind == "intercept":
		_tick_intercept(space, dt, m)
		return
	if kind == "mothership":
		space.invasion_tick(dt, m)
		return
	if kind == "planet_invasion" and int(m.get("bs_down", 0)) >= int(m.get("left", 1)):   # v12.58: the battleships are gone: the rest of the sky
		var rest: Array = space.enemies.filter(func(e): return str(e.get("faction", "")) == str(m["faction"]) and bool(e.get("aggro", false)) and space.tile == int(m["tile"]))
		m["calm"] = float(m.get("calm", 0.0)) + dt if rest.is_empty() else 0.0   # (a moment's quiet: the last wave may still be launching)
		if float(m["calm"]) >= Data.PLANET_INV_CALM:
			_pay(space, "The %s invasion of %s is broken: battleships gone, the sky's clear. %s pays %d cr." % [m["faction"], Surface.PLANETS[str(m["planet"])]["name"], giver_name(m), int(m["pay"])])
		return
	if kind == "land_escort":
		_tick_land_escort(space, dt, m)
		return
	var stage := int(m["stage"])
	var pts: Array = m.get("points", [])
	if kind == "escort":
		_tick_escort(space, dt, m)
		return
	if kind == "convoy":
		_tick_convoy(space, dt, m)
		return
	if kind == "invasion":   # v1.9n
		space.invasion_tick(dt, m)
		return
	if kind == "disturbance":   # v11.26
		space.disturbance_tick(dt, m)
		return
	if stage >= pts.size(): return
	if int(m["spawned"]) < stage:
		var at := point_pos(space, stage)
		if at != Vector3.INF and space.player.global_position.distance_to(at) < Data.MISSION_ARRIVE:
			var last: bool = stage == pts.size() - 1
			var count: int = Data.MISSION_GROUP[1] if last else Data.MISSION_GROUP[0]
			var boss := ""
			var tier := 2
			var boss_tier := -1
			if kind == "bounty" and last:
				boss = str(m["id"])
				count = 1 + Data.BOUNTY_HELPERS   # v1.9b: the target and its six helpers
			if m.has("waves"):   # v12.56: this job's own wave sizes (the rest jump in as reinforcements)
				var wv2: Array = m["waves"][mini(stage, (m["waves"] as Array).size() - 1)]
				count = int(wv2[0])
				tier = int(wv2[1])
				m["queue"] = maxi(0, count - Data.BOUNTY_WAVE_LIVE)
				m["qtier"] = tier
				count = mini(count, Data.BOUNTY_WAVE_LIVE)
			if kind == "bounty" and m.has("rank"):   # v11.97 (owner): the wave for this level and point
				var wv: Array = Data.BOUNTY_WAVES[int(m["rank"])][mini(stage, 1)]
				count = int(wv[0]) + (1 if last else 0)
				tier = int(wv[1])
				boss_tier = int(Data.BOUNTY_BOSS_TIER[int(m["rank"])])
				m["queue"] = maxi(0, count - Data.BOUNTY_WAVE_LIVE)
				m["qtier"] = tier
				count = mini(count, Data.BOUNTY_WAVE_LIVE)
			m["need"] = space.spawn_mission_group(at, str(m["faction"]), count, int(m["slot"]), boss, stage, kind == "threats", tier, boss_tier).size()   # v1.8x: PATROL = level 1s, ELITE = level 5s
			if kind == "ground":
				m["need"] = int(m["need"]) + space.spawn_ground_mechs(at, str(m["faction"]), int(Data.MISSION_GROUND_MECHS[1 if last else 0]), stage, Data.MECH_BOSS_COUNT if last else 0).size()   # (v1.9i: the last point has the faction's boss mech)   # v1.8n
				var foot: Array = space.spawn_ground_mechs(at + Vector3(80, 0, 60), str(m["faction"]), Data.MISSION_GROUND_PILOTS, stage, 0)   # v12.56 (owner: "mechs as well as pilots"): pilots on foot too
				for fp in foot: space._soldierify(fp, str(m["faction"]))
				m["need"] = int(m["need"]) + foot.size()
			if kind == "planet_invasion":   # GOLD: their battleships, already in the atmosphere (the ones not yet destroyed)
				for bi in int(m.get("left", 1)) - int(m.get("bs_down", 0)):
					var bs: Dictionary = space.spawn_planet_capital(at + Vector3(bi * 500.0 - 250.0, 400.0, 300.0), str(m["faction"]), stage)
					if not bs.is_empty(): m["need"] = int(m["need"]) + 1
			m["killed"] = 0
			m["spawned"] = stage
			space.message.emit("%s: %s" % ["Mission", "the target's wing is here. Engage." if kind == "bounty" and last else "hostiles at the waypoint. Engage."])
		return
	# the wave is out: gone when none of its ships is left
	var live := space.enemies.filter(func(o): return int(o.get("mission", -1)) == stage and is_instance_valid(o["node"]))
	if int(m.get("queue", 0)) > 0 and live.size() < Data.BOUNTY_REINFORCE_AT:   # v11.97: the rest of the wave jumps in
		var at2 := point_pos(space, stage)
		var n2 := mini(int(m["queue"]), Data.BOUNTY_WAVE_LIVE - live.size())
		if at2 != Vector3.INF and n2 > 0:
			space.spawn_mission_group(at2 + Vector3(0, 0, 400), str(m["faction"]), n2, int(m["slot"]), "", stage, false, int(m.get("qtier", 2)))
			m["queue"] = int(m["queue"]) - n2
			space.message.emit("Mission: enemy reinforcements jumping in (%d more)." % (n2 + int(m["queue"])))
		return
	if not live.is_empty(): return
	if kind == "bounty" and stage == pts.size() - 1: return   # the last stage ends on the kill / capture (on_kill, claim)
	if on_land(m) and int(m.get("killed", 0)) < int(m.get("need", 0)) and int(m.get("queue", 0)) <= 0:   # v1.8m: you left them behind (another sector, orbit): they wait at the point
		m["spawned"] = stage - 1
		return
	m["stage"] = stage + 1
	if int(m["stage"]) < pts.size():
		space.message.emit("Mission: wave cleared. The waypoint moves to point %d of %d." % [int(m["stage"]) + 1, pts.size()])
	elif kind == "ground":
		_pay(space, "The landing party is destroyed. %s pays %d cr." % [Data.SYSTEMS[m["giver_sys"]]["station"]["name"], int(m["pay"])])
	elif kind == "threats" or kind == "outlaws":
		_pay(space, "Threats eliminated. %s pays %d cr." % [Data.SYSTEMS[m["giver_sys"]]["station"]["name"], int(m["pay"])])
	elif kind == "intercept":
		_pay(space, "Raid intercepted. %s pays %d cr." % [giver_name(m), int(m["pay"])])
	elif kind == "air_sweep":
		_pay(space, "Sweep done: every fighter down. The bounty board pays %d cr." % int(m["pay"]))
	elif kind == "planet_invasion":   # (shot down from outside: it counts)
		m["bs_down"] = int(m.get("left", 1))

## v12.56: the transport run. It sets off when you're in its sector (it waits otherwise); down = paid; at the
## facility = the job's failed.
static func _tick_intercept(space: SpaceSystem, dt: float, m: Dictionary) -> void:
	if space.tile != int(m["tile"]): return
	var tgt := Vector3(float(m["to"]["x"]), 0.0, float(m["to"]["z"]))
	tgt.y = space._ground(tgt.x, tgt.z) + Data.TRANSPORT_ALT
	if int(m.get("spawned", -1)) < 0:
		var at := point_pos(space, 0)
		if at == Vector3.INF: return
		at.y = space._ground(at.x, at.z) + Data.TRANSPORT_ALT
		var tr: Dictionary = space.spawn_transport(at, tgt, str(m["faction"]))
		if tr.is_empty(): return
		m["spawned"] = 0
		m["need"] = 1
		space.spawn_mission_group(at + Vector3(0, 60, 0), str(m["faction"]), Data.TRANSPORT_ESCORT, 2, "", 0)
		var mid := at.lerp(tgt, 0.8)
		space.spawn_ground_mechs(Vector3(mid.x, 0, mid.z), str(m["faction"]), Data.TRANSPORT_MECHS, 0, 0)
		space.message.emit("Mission: the %s transport is on its way to %s. Bring it down!" % [m["faction"], m["site"]])
		return
	var live: Array = space.enemies.filter(func(e): return bool(e.get("transport", false)))
	if live.is_empty():
		_pay(space, "Transport down! %s pays %d cr." % [giver_name(m), int(m["pay"])])
		return
	var n: Node3D = live[0]["node"]
	var to := tgt - n.global_position
	if to.length() < Data.TRANSPORT_ARRIVE:
		space.message.emit("The transport made it to %s. Mission failed." % m["site"])
		abandon()
		return
	n.global_position += to.normalized() * Data.TRANSPORT_SPEED * dt
	SpaceSystem.face(n, to)

## True when this bounty is wanted dead (no pod drops: the kill is the job).
static func wants_dead(id: String) -> bool:
	var m: Dictionary = GS.mission
	return m.get("kind", "") == "bounty" and str(m.get("id", "")) == id and not bool(m.get("alive", true))

## A kill: a bounty wanted dead ends here; everything else is counted by tick().
static func on_kill(space: SpaceSystem, e: Dictionary) -> void:
	var m: Dictionary = GS.mission
	if on_land(m) and int(e.get("mission", -1)) == int(m.get("stage", 0)): m["killed"] = int(m.get("killed", 0)) + 1   # v1.8m (v12.56: every land job)
	if m.is_empty() or not e.has("bounty") or m.get("kind", "") != "bounty" or e["bounty"] != m.get("id", ""): return
	if bool(m.get("alive", false)): return   # the pod drops; the tractor and the hand-in finish it
	var id := str(m["id"])
	var p: Dictionary = Data.roster_pilot(id)
	GS.bounties_done.append(id)
	GS.bounty = {}
	GS.cast_state(str(p.get("character_id", id)))["alive"] = false
	GS.jail(id, "station")   # v1.8k: back in a new ship later (the boards never run out)
	Factions.adjust(str(p.get("faction", "")), -Data.REP_BOUNTY)
	_pay(space, "Bounty on %s: paid on the spot, %d cr." % [p.get("name", "the pilot"), int(m["pay"])])

## Docking at the giver with the pilot in the hold: paid. "" = nothing to pay here.
static func claim_at(station_id: String, where_kind := "station") -> String:
	var m: Dictionary = GS.mission
	if m.get("kind", "") != "bounty" or GS.bounty.get("state", "") != "captured": return ""
	if str(m.get("giver", "")) != station_id: return "%s is in your hold. The bounty is paid at %s." % [Data.roster_pilot(str(m["id"])).get("name", "The pilot"), giver_name(m)]
	var said := GS.claim_bounty(where_kind)
	GS.cargo = GS.cargo.filter(func(c): return not (c.get("kind", "") == "pilot" and c.get("id", "") == m["id"]))
	GS.missions_done += 1
	Factions.adjust(str(Data.SYSTEMS[m["giver_sys"]].get("faction", "")), Data.REP_MISSION)
	GS.mission = {}
	GS.changed.emit()
	return said

static var last_paid := {}   # v1.8w: the job just paid ({giver_sys, pay, title}) for the giver's congratulations call

static func _pay(space: SpaceSystem, said: String) -> void:
	var m: Dictionary = GS.mission
	last_paid = {"giver_sys": str(m["giver_sys"]), "pay": int(m["pay"]), "title": str(m.get("title", ""))}
	GS.add_credits(int(m["pay"]))
	GS.missions_done += 1
	Factions.adjust(str(Data.SYSTEMS[m["giver_sys"]].get("faction", "")), Data.REP_MISSION)
	GS.mission = {}
	GS.changed.emit()
	GS.save_game()   # v1.7y: a paid job saves
	space.message.emit(said)
	space.mission_done.emit(said)

# ---------------------------------------------------------------- v1.7w cargo run
# ---------------------------------------------------------------- v1.9a escort on a planet
## A base of the job ("from" / "to"): {name, tile, x, z, g (planet-wide position, metres)}.
static func land_base(m: Dictionary, which: String) -> Dictionary:
	var pid := str(m["planet"])
	var l: Dictionary = m[which] if m[which] is Dictionary else Surface.PLANETS[pid]["locations"][int(m[which])]   # (v12.56: a facility is a dictionary)
	var g := Surface.grid(pid)
	var t := int(l["tile"])
	var lp: Vector2 = l["pos"]
	return {"name": str(l["name"]), "tile": t, "x": lp.x, "z": lp.y, "g": Vector2((t % g) * Surface.TILE + lp.x, (t / g) * Surface.TILE + lp.y)}

## The short way from a to b on a planet that wraps round.
static func wrap_d(pid: String, a: Vector2, b: Vector2) -> Vector2:
	var w := float(Surface.grid(pid)) * Surface.TILE
	var d := b - a
	d.x = fposmod(d.x + w * 0.5, w) - w * 0.5
	d.y = fposmod(d.y + w * 0.5, w) - w * 0.5
	return d

## Where a planet-wide position is from the sector you are flying over.
static func land_local(space: SpaceSystem, gp: Vector2) -> Vector3:
	var g := Surface.grid(space.planet_id)
	var origin := Vector2((space.tile % g) * Surface.TILE, (space.tile / g) * Surface.TILE)
	var d := wrap_d(space.planet_id, origin, gp)
	return Vector3(d.x, 0.0, d.y)

static func _tick_land_escort(space: SpaceSystem, dt: float, m: Dictionary) -> void:
	var a := land_base(m, "from")
	var b := land_base(m, "to")
	if (m.get("pos", []) as Array).size() < 2: m["pos"] = [a["g"].x, a["g"].y]
	var gp := Vector2(float(m["pos"][0]), float(m["pos"][1]))
	if not is_instance_valid(space.escort_node):
		if int(m["stage"]) >= 90: return
		space.make_escort(Vector3.ZERO, Vector3.ZERO)
		if not is_instance_valid(space.escort_node): return
	var n: Node3D = space.escort_node
	var lp := land_local(space, gp)
	var ground: float = space._ground(lp.x, lp.z) if absf(lp.x) < Surface.EDGE and absf(lp.z) < Surface.EDGE else 0.0
	var at := lp + Vector3(0, maxf(ground, 0.0) + Data.LAND_ESCORT_ALT, 0)
	var togo := wrap_d(space.planet_id, gp, b["g"])
	var trip := maxf(1.0, wrap_d(space.planet_id, a["g"], b["g"]).length())
	var near: bool = space.player.global_position.distance_to(at) < Data.LAND_ESCORT_WAIT
	if near and togo.length() > 1.0:   # it only flies on while you are with it
		gp += togo.normalized() * minf(Data.ESCORT_SPEED * dt, togo.length())
		m["pos"] = [gp.x, gp.y]
	n.global_position = n.global_position.lerp(at, minf(1.0, dt * 4.0)) if n.global_position.distance_to(at) < 400.0 else at
	if togo.length() > 1.0: SpaceSystem.face(n, Vector3(togo.x, 0, togo.y))
	var done: float = 1.0 - togo.length() / trip
	for i in 2:   # ambushes at a third and two thirds of the way
		if int(m["spawned"]) < i and done >= (float(i) + 1.0) / 3.0:
			space.spawn_mission_group(n.global_position + Vector3(Data.ESCORT_AMBUSH * 0.6, 40.0, 0).rotated(Vector3.UP, float(i) * 2.2), str(m["faction"]), Data.MISSION_GROUP[0], int(m["slot"]), "", i)
			m["spawned"] = i
			space.message.emit("Mission: %s on the freighter. Keep them off it." % m["faction"])
	var attackers := 0
	for o in space.enemies:
		if o.has("mission") and is_instance_valid(o["node"]) and (o["node"] as Node3D).global_position.distance_to(n.global_position) < Data.ESCORT_RANGE: attackers += 1
	if attackers > 0:
		m["escort_hp"] = float(m["escort_hp"]) - Data.ESCORT_FIRE * attackers * dt
		if float(m["escort_hp"]) <= 0.0:
			space._explode(n.global_position)
			n.queue_free()
			space.escort_node = null
			m["stage"] = 99
			space.message.emit("Mission failed: the freighter is lost.")
			space.mission_done.emit("failed")
			GS.mission = {}
			GS.changed.emit()
			return
	if togo.length() < Data.ESCORT_DOCK:
		n.queue_free()
		space.escort_node = null
		m["stage"] = 90
		_pay(space, "The freighter is down at %s. %s pays %d cr." % [b["name"], Data.SYSTEMS[m["giver_sys"]]["station"]["name"], int(m["pay"])])

## The gate in this system that leads to sys_id (null = none).
static func gate_to(space: SpaceSystem, sys_id: String) -> Node3D:
	for g in space.gates:
		if is_instance_valid(g) and str((g.get_meta("info", {}) as Dictionary).get("to", "")) == sys_id: return g
	return null

## Leg 0: station -> the gate to the destination (it jumps there). Leg 1, in the destination system: out of the
## arrival gate -> that system's station (paid when it docks). Hull carries over; losing it fails the job.
static func _tick_convoy(space: SpaceSystem, dt: float, m: Dictionary) -> void:
	var leg := int(m.get("leg", 0))
	var gate: Node3D = gate_to(space, str(m["dest"]) if leg == 0 else str(m["giver_sys"]))
	if not is_instance_valid(space.escort_node):
		if int(m["stage"]) >= 90 or not is_instance_valid(space.station): return
		if leg == 0: space.make_escort(space.dock_point(space.station) + Vector3(0, 60, 0), gate.global_position if gate != null else space.planet_dock_point())
		else:
			var from: Vector3 = gate.global_position if gate != null else space.player.global_position
			var goal0: Vector3 = space.dock_point(space.station) + Vector3(0, 60, 0)
			space.make_escort(from + (goal0 - from).normalized() * Data.CONVOY_START, goal0)
		return
	var n: Node3D = space.escort_node
	var goal: Vector3 = n.get_meta("goal", space.planet_dock_point())
	var to := goal - n.global_position
	var d := to.length()
	if d > 1.0:
		n.global_position += to.normalized() * minf(Data.ESCORT_SPEED * dt, d)
		n.look_at(goal, Vector3.UP)
	var done: float = 1.0 - d / maxf(1.0, n.get_meta("trip", 1.0))
	var pts: Array = m.get("points", [])
	if int(m["spawned"]) < leg and leg < pts.size() and done >= float(Data.CONVOY_WAVE_AT[leg]):
		space.spawn_mission_group(n.global_position + Vector3(cos(float(pts[leg]["dir"])), 0.2, sin(float(pts[leg]["dir"]))) * Data.ESCORT_AMBUSH, str(m["faction"]), int(Data.CONVOY_WAVE_SHIPS[leg]), int(m["slot"]), "", leg)
		m["spawned"] = leg
		space.message.emit("Mission: %s on the freighter%s. Keep them off it." % [m["faction"], "" if leg == 0 else " — this is the big one"])
	if _escort_hits(space, dt, m, n): return
	if leg == 0 and d < Data.CONVOY_GATE:   # through the gate: you follow
		n.queue_free()
		space.escort_node = null
		m["leg"] = 1
		m["sys"] = str(m["dest"])
		space.message.emit("The freighter has jumped to %s. Follow it through the gate." % Data.SYSTEMS[m["dest"]]["name"])
		GS.changed.emit()
	elif leg == 1 and d < Data.ESCORT_DOCK:
		n.queue_free()
		space.escort_node = null
		m["stage"] = 90
		_pay(space, "The cargo is in at %s. %s pays %d cr." % [Data.SYSTEMS[m["dest"]]["station"]["name"], Data.SYSTEMS[m["giver_sys"]]["station"]["name"], int(m["pay"])])

## Attackers near the freighter wear its hull down; true when it is lost (the job fails).
static func _escort_hits(space: SpaceSystem, dt: float, m: Dictionary, n: Node3D) -> bool:
	var attackers := 0
	for o in space.enemies:
		if o.has("mission") and is_instance_valid(o["node"]) and (o["node"] as Node3D).global_position.distance_to(n.global_position) < Data.ESCORT_RANGE: attackers += 1
	if attackers == 0: return false
	m["escort_hp"] = float(m["escort_hp"]) - Data.ESCORT_FIRE * attackers * dt
	if int(space.time * 4.0) % 2 == 0: space._spark(n.global_position + Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-8, 8)), Color(1.0, 0.6, 0.3), 3.0, 0.2)
	if float(m["escort_hp"]) > 0.0: return false
	space._explode(n.global_position)
	n.queue_free()
	space.escort_node = null
	m["stage"] = 99
	space.message.emit("Mission failed: the freighter is lost.")
	space.mission_done.emit("failed")
	GS.mission = {}
	GS.changed.emit()
	return true

# ---------------------------------------------------------------- escort
## The freighter: made when you launch (or arrive) with the job; flies station -> planet at ESCORT_SPEED; two ambush
## waves wait along the way; while a mission attacker is within ESCORT_RANGE it loses ESCORT_FIRE hull a second.
static func _tick_escort(space: SpaceSystem, dt: float, m: Dictionary) -> void:
	if not is_instance_valid(space.escort_node):
		if int(m["stage"]) >= 90: return   # over
		space.make_escort()
		return
	var n: Node3D = space.escort_node
	var goal: Vector3 = space.planet_dock_point()
	var to := goal - n.global_position
	var d := to.length()
	var step: float = minf(Data.ESCORT_SPEED * dt, d)
	if d > 1.0:
		n.global_position += to.normalized() * step
		n.look_at(goal, Vector3.UP)
	var done: float = 1.0 - d / maxf(1.0, n.get_meta("trip", 1.0))
	# ambushes at a third and two thirds of the way
	var pts: Array = m.get("points", [])
	for i in pts.size():
		if int(m["spawned"]) < i and done >= (float(i) + 1.0) / (float(pts.size()) + 1.0):
			space.spawn_mission_group(n.global_position + Vector3(cos(float(pts[i]["dir"])), 0.2, sin(float(pts[i]["dir"]))) * Data.ESCORT_AMBUSH, str(m["faction"]), Data.MISSION_GROUP[0], int(m["slot"]), "", i)
			m["spawned"] = i
			space.message.emit("Mission: %s raiders on the freighter. Keep them off it." % m["faction"])
	var attackers := 0
	for o in space.enemies:
		if o.has("mission") and is_instance_valid(o["node"]) and (o["node"] as Node3D).global_position.distance_to(n.global_position) < Data.ESCORT_RANGE: attackers += 1
	if attackers > 0:
		m["escort_hp"] = float(m["escort_hp"]) - Data.ESCORT_FIRE * attackers * dt
		if int(space.time * 4.0) % 2 == 0: space._spark(n.global_position + Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-8, 8)), Color(1.0, 0.6, 0.3), 3.0, 0.2)
		if float(m["escort_hp"]) <= 0.0:
			space._explode(n.global_position)
			n.queue_free()
			space.escort_node = null
			m["stage"] = 99
			space.message.emit("Mission failed: the freighter is lost.")
			space.mission_done.emit("failed")
			GS.mission = {}
			GS.changed.emit()
			return
	if d < Data.ESCORT_DOCK:
		n.queue_free()
		space.escort_node = null
		m["stage"] = 90
		_pay(space, "The freighter has docked. %s pays %d cr." % [Data.SYSTEMS[m["giver_sys"]]["station"]["name"], int(m["pay"])])
