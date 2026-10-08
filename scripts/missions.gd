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
static func offers(sys_id: String, station_id: String) -> Array:
	var sys: Dictionary = Data.SYSTEMS[sys_id]
	var own := str(sys.get("faction", ""))
	var enemy := str(Data.OPENING_SYSTEMS.get(sys_id, {}).get("faction", ""))   # v1.5k: the opening system's rival nation
	if enemy == "": enemy = Factions.raider_of(own)
	if enemy == "" and Factions.has_fighters(Factions.rival(own)): enemy = Factions.rival(own)   # the owner's rival nation, if it has ships
	if enemy == "":   # nobody raids this owner: the nearest permanent enemy with ships does the dirty work
		for f in Data.MISSION_FALLBACK_ENEMIES:
			if Factions.has_fighters(f):
				enemy = f
				break
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(station_id) + GS.missions_done * 7919
	var out: Array = []
	if enemy != "":
		for hard in [false, true]:
			var pay := int(Data.MISSION_PAY["threats"] * (Data.MISSION_HARD_MULT if hard else 1.0))
			out.append({"kind": "threats", "hard": hard, "faction": enemy, "slot": Data.MISSION_HARD_SLOT if hard else 1, "pay": pay,
				"title": "%s: eliminate the %s threat" % ["ELITE" if hard else "PATROL", enemy], "giver": station_id, "giver_sys": sys_id, "sys": sys_id,
				"brief": "%s %s have been seen in two places in the %s system. Clear both. %s" % ["Elite" if hard else "", enemy, sys["name"],
					"Their best soldiers: expect a hard fight." if hard else "Common soldiers."],
				"points": _points(rng, 2)})
	if Factions.has_fighters(enemy) or enemy != "":
		out.append({"kind": "escort", "faction": enemy, "slot": 2, "pay": Data.MISSION_PAY["escort"], "title": "Escort a freighter to %s" % sys["planet"]["name"],
			"giver": station_id, "giver_sys": sys_id, "sys": sys_id,
			"brief": "A freighter is leaving for %s. Stay with it: %s will try to stop it on the way. If it arrives, you are paid." % [sys["planet"]["name"], enemy if enemy != "" else "raiders"],
			"points": _points(rng, 2)})
	return out

static func _points(rng: RandomNumberGenerator, n: int) -> Array:
	var pts: Array = []
	var a := rng.randf() * TAU
	for i in n:
		pts.append({"dir": a, "dist": rng.randf_range(Data.MISSION_POINT_DIST[0], Data.MISSION_POINT_DIST[1]), "y": rng.randf_range(-200.0, 300.0)})
		a += rng.randf_range(1.6, 2.6)
	return pts

## Where a mission point is in this system (the points are relative to the main station).
static func point_pos(space: SpaceSystem, i: int) -> Vector3:
	var m: Dictionary = GS.mission
	var pts: Array = m.get("points", [])
	if i < 0 or i >= pts.size() or not is_instance_valid(space.station): return Vector3.INF
	var p: Dictionary = pts[i]
	var base: Vector3 = space.station.global_position
	var dir := Vector3(cos(float(p["dir"])), 0.0, sin(float(p["dir"])))
	var at := base + dir * float(p["dist"]) + Vector3(0, float(p.get("y", 0.0)), 0)
	if is_instance_valid(space.planet):   # never inside a planet's air: step out along the bearing until clear
		var keep: float = float(space.sys["planet"].get("radius", 800.0)) + Data.MISSION_PLANET_CLEAR
		for k in 12:
			if at.distance_to(space.planet.global_position) >= keep: break
			at += dir * 600.0
	return at

## Take a job from the board. "" = taken.
static func accept(offer: Dictionary) -> String:
	if not GS.mission.is_empty() or not GS.bounty.is_empty():
		var blk := _switch_block()
		if blk != "": return blk
		abandon()
		GS.bounty = {}
	var m := offer.duplicate(true)
	m["stage"] = 0
	m["spawned"] = -1
	m["escort_hp"] = Data.ESCORT_HULL
	GS.mission = m
	GS.changed.emit()
	return "Job taken: %s. %s A mission waypoint is set: follow the gold marker." % [m["title"], m["brief"]]

## The bounty board's jobs go through here too: the target's record stays in GS.bounty (older code reads it); the
## chain of points is the mission.
static func accept_bounty(id: String) -> String:
	var p: Dictionary = Data.roster_pilot(id)
	if p.is_empty(): return "No such bounty."
	if not GS.mission.is_empty():
		var blk := _switch_block()
		if blk != "": return blk
		abandon()
	var said := GS.accept_bounty(id)
	if GS.bounty.get("id", "") != id: return said
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var alive: bool = int(p.get("rank", 1)) >= Data.BOUNTY_ALIVE_RANK
	GS.mission = {"kind": "bounty", "id": id, "alive": alive, "faction": str(p.get("faction", "")), "slot": 2, "pay": Data.bounty_reward(id),
		"title": "Bounty: %s (%s)" % [p["name"], "wanted alive" if alive else "wanted dead"], "giver": GS.last_base, "giver_sys": GS.system_id, "sys": str(p["sys"]),
		"brief": "%s was last seen in the %s system with an escort wing. Fly to the first waypoint and deal with the escort; then the waypoint moves to %s. %s" % [p["name"], Data.SYSTEMS[p["sys"]]["name"], p["name"],
			"Destroy the ship, TRACTOR the pilot in and bring them back here." if alive else "Destroy the ship: paid on the spot."],
		"points": _points(rng, 2), "stage": 0, "spawned": -1, "escort_hp": 0.0}
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
	var blocked := _switch_block()
	if blocked != "": return blocked
	abandon()
	return accept(offer)

## Tap on a bounty: the same rules.
static func toggle_bounty(id: String) -> String:
	if GS.bounty.get("id", "") == id and GS.bounty.get("state", "") == "hunt":
		abandon()
		GS.bounty = {}
		GS.changed.emit()
		return "Stopped tracking the bounty on %s." % Data.roster_pilot(id).get("name", id)
	var blocked := _switch_block()
	if blocked != "": return blocked
	abandon()
	GS.bounty = {}
	return accept_bounty(id)

## The one thing that can stop a switch: a prisoner in the hold must be handed in first.
static func _switch_block() -> String:
	if GS.bounty.get("state", "") == "captured":
		return "%s is in your hold: hand them in at %s first." % [Data.roster_pilot(str(GS.bounty["id"])).get("name", "The pilot"), Data.SYSTEMS[str(GS.mission.get("giver_sys", GS.system_id))]["station"]["name"]]
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
	return "Tracking: %s. Waypoint: mission point %d of %d in this system." % [m["title"], int(m.get("stage", 0)) + 1, (m.get("points", []) as Array).size()]

## Drop the job (no pay, no penalty beyond the lost time).
static func abandon() -> void:
	if GS.mission.is_empty(): return
	if GS.mission.get("kind", "") == "bounty" and GS.bounty.get("state", "") == "hunt": GS.bounty = {}
	GS.mission = {}
	GS.changed.emit()

## What the HUD and the map point at, in THIS system: {node, title, line, hops} or {} when the job has nothing here.
static func waypoint(space: SpaceSystem) -> Dictionary:
	var m: Dictionary = GS.mission
	if m.is_empty() or space.surface_mode or not is_instance_valid(space.player): return {}
	var kind := str(m["kind"])
	var stage := int(m["stage"])
	# bounty, pilot in the hold: back to the station that gave the job
	if kind == "bounty" and GS.bounty.get("state", "") == "captured":
		return _to_place(space, str(m["giver_sys"]), "Dock at %s to hand %s over" % [Data.SYSTEMS[m["giver_sys"]]["station"]["name"], Data.roster_pilot(str(m["id"])).get("name", "the pilot")])
	if str(m["sys"]) != space.sys_id: return _to_place(space, str(m["sys"]), m["title"])
	match kind:
		"escort":
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
				return {"node": mp, "title": "Mission point %d" % (stage + 1), "line": "%s: fly to mission point %d of %d" % ["Bounty" if kind == "bounty" else "Threats", stage + 1, (m["points"] as Array).size()], "hops": 0}
	return {}

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
	if m.is_empty() or space.surface_mode or not is_instance_valid(space.player) or str(m["sys"]) != space.sys_id: return
	var kind := str(m["kind"])
	var stage := int(m["stage"])
	var pts: Array = m.get("points", [])
	if kind == "escort":
		_tick_escort(space, dt, m)
		return
	if stage >= pts.size(): return
	if int(m["spawned"]) < stage:
		var at := point_pos(space, stage)
		if at != Vector3.INF and space.player.global_position.distance_to(at) < Data.MISSION_ARRIVE:
			var last: bool = stage == pts.size() - 1
			var count: int = Data.MISSION_GROUP[1] if last else Data.MISSION_GROUP[0]
			var boss := ""
			if kind == "bounty" and last: boss = str(m["id"])
			space.spawn_mission_group(at, str(m["faction"]), count, int(m["slot"]), boss, stage)
			m["spawned"] = stage
			space.message.emit("%s: %s" % ["Mission", "the target's wing is here. Engage." if kind == "bounty" and last else "hostiles at the waypoint. Engage."])
		return
	# the wave is out: gone when none of its ships is left
	var live := space.enemies.filter(func(o): return int(o.get("mission", -1)) == stage and is_instance_valid(o["node"]))
	if not live.is_empty(): return
	if kind == "bounty" and stage == pts.size() - 1: return   # the last stage ends on the kill / capture (on_kill, claim)
	m["stage"] = stage + 1
	if int(m["stage"]) < pts.size():
		space.message.emit("Mission: wave cleared. The waypoint moves to point %d of %d." % [int(m["stage"]) + 1, pts.size()])
	elif kind == "threats":
		_pay(space, "Threats eliminated. %s pays %d cr." % [Data.SYSTEMS[m["giver_sys"]]["station"]["name"], int(m["pay"])])

## True when this bounty is wanted dead (no pod drops: the kill is the job).
static func wants_dead(id: String) -> bool:
	var m: Dictionary = GS.mission
	return m.get("kind", "") == "bounty" and str(m.get("id", "")) == id and not bool(m.get("alive", true))

## A kill: a bounty wanted dead ends here; everything else is counted by tick().
static func on_kill(space: SpaceSystem, e: Dictionary) -> void:
	var m: Dictionary = GS.mission
	if m.is_empty() or not e.has("bounty") or m.get("kind", "") != "bounty" or e["bounty"] != m.get("id", ""): return
	if bool(m.get("alive", false)): return   # the pod drops; the tractor and the hand-in finish it
	var id := str(m["id"])
	var p: Dictionary = Data.roster_pilot(id)
	GS.bounties_done.append(id)
	GS.bounty = {}
	GS.cast_state(str(p.get("character_id", id)))["alive"] = false
	Factions.adjust(str(p.get("faction", "")), -Data.REP_BOUNTY)
	_pay(space, "Bounty on %s: paid on the spot, %d cr." % [p.get("name", "the pilot"), int(m["pay"])])

## Docking at the giver with the pilot in the hold: paid. "" = nothing to pay here.
static func claim_at(station_id: String) -> String:
	var m: Dictionary = GS.mission
	if m.get("kind", "") != "bounty" or GS.bounty.get("state", "") != "captured": return ""
	if str(m.get("giver", "")) != station_id: return "%s is in your hold. The bounty is paid at %s." % [Data.roster_pilot(str(m["id"])).get("name", "The pilot"), Data.SYSTEMS[m["giver_sys"]]["station"]["name"]]
	var said := GS.claim_bounty()
	GS.cargo = GS.cargo.filter(func(c): return not (c.get("kind", "") == "pilot" and c.get("id", "") == m["id"]))
	GS.missions_done += 1
	Factions.adjust(str(Data.SYSTEMS[m["giver_sys"]].get("faction", "")), Data.REP_MISSION)
	GS.mission = {}
	GS.changed.emit()
	return said

static func _pay(space: SpaceSystem, said: String) -> void:
	var m: Dictionary = GS.mission
	GS.add_credits(int(m["pay"]))
	GS.missions_done += 1
	Factions.adjust(str(Data.SYSTEMS[m["giver_sys"]].get("faction", "")), Data.REP_MISSION)
	GS.mission = {}
	GS.changed.emit()
	space.message.emit(said)
	space.mission_done.emit(said)

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
