class_name BoardingJobs
## v13.02 BOARDING missions (owner, 10 Nov): "add a boarding mission to the mission [board] listing rival ships from the
## station ... the ship appears only when the mission is accepted ... 2 or 3 random spawn points a good distance from
## the station ... some hidden in nebula clouds ... bigger ships have 10 to 15 fighters depending on size" and "we are
## only boarding the big ships ... Fighters bombers those you can't board ... for now, just the big ships".
## A job = one rival fleet ship (FleetCatalog) + one of the three deck missions its deck plan has (ShipInterior):
## blow up the generator, capture the captain, rescue the hostage. Reaching the ship boards it; finishing the deck
## mission and leaving by the hangar pays. Nothing here is saved to disk yet (a job lasts until you finish, drop or quit).

const BIG := ["Capital", "Cruiser", "Destroyer", "TroopTransport", "Resupply"]   # "for now, just the big ships"
const FIGHTERS := {"Capital": 15, "Cruiser": 13, "Destroyer": 12, "TroopTransport": 11, "Resupply": 10}
const PAY := {"Capital": 9000, "Cruiser": 7000, "Destroyer": 6000, "TroopTransport": 5000, "Resupply": 4500}
const KIND_PAY := {"sabotage": 1.0, "capture": 1.2, "rescue": 1.35}
const KIND_TITLE := {"sabotage": "BLOW UP THE GENERATOR", "capture": "CAPTURE THE CAPTAIN", "rescue": "RESCUE THE HOSTAGE"}
const KIND_BRIEF := {"sabotage": "Get aboard, reach the generator and set it to blow. A countdown starts: get back to the hangar and out before it goes.",
	"capture": "Get aboard, fight up to the top-level rooms, take the captain and bring them back to the hangar.",
	"rescue": "Get aboard, find the prison on the top access level, free the hostage and bring them back to the hangar."}
const DIST := [16000.0, 19000.0, 22000.0]   # m from the station: the three places the ship can be waiting
const BOARD_RANGE := 260.0                  # m past the hull: this close and you are aboard

## The deck missions a ship's plan has ([] = no deck plan with missions yet).
static func kinds_of(id: String) -> Array:
	if not ShipInterior.can_open(id): return []
	var f := FileAccess.open(FleetCatalog.HOLODECK_DIR + id + ".json", FileAccess.READ)
	if f == null: return []
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary): return []
	return ((d as Dictionary).get("objectives", {}) as Dictionary).keys()

## The board's list at a station owned by `owner`: its rival's big ships, biggest first. A ship whose deck plan has no
## missions yet is listed but cannot be taken ("ready" false).
static func offers(sys_id: String, owner: String) -> Array:
	var out: Array = []
	var rival := Factions.rival(owner)
	if rival == "" or not rival in FleetCatalog.FACTIONS: return out
	for e in FleetCatalog.of_faction(rival):
		var cls := str(e["class"])
		if not cls in BIG: continue
		var ks := kinds_of(str(e["id"]))
		var kind := str(ks[absi(hash(sys_id + str(e["id"]))) % ks.size()]) if not ks.is_empty() else ""
		out.append({"id": str(e["id"]), "name": str(e["name"]), "class": cls, "faction": rival, "sys": sys_id, "kind": kind, "ready": kind != "",
			"fighters": int(FIGHTERS[cls]), "pay": int(round(float(PAY[cls]) * float(KIND_PAY.get(kind, 1.0)) / 100.0)) * 100,
			"title": "BOARD THE %s: %s" % [str(e["name"]).to_upper(), str(KIND_TITLE.get(kind, "DECK NOT BUILT YET"))],
			"brief": ("%s Escort: %d fighters. The ship shows up once you take the job, well away from the station." % [str(KIND_BRIEF[kind]), int(FIGHTERS[cls])]) if kind != ""
				else "This ship's deck plan has no missions built yet."})
	out.sort_custom(func(a, b): return int(a["pay"]) > int(b["pay"]))
	return out

## The three places the ship can wait, about the station at `c`: far out on three bearings; where the system has
## nebula clouds, the first two are inside a cloud. `clouds` = [{center: Vector3, radius: float}].
static func points(sys_id: String, c: Vector3, clouds: Array) -> Array:
	var out: Array = []
	var a0 := float(absi(hash(sys_id + "_boardjob")) % 628) / 100.0
	for i in 3:
		var a := a0 + float(i) * TAU / 3.0
		out.append({"pos": c + Vector3(cos(a) * DIST[i], 180.0 + 120.0 * float(i), sin(a) * DIST[i]), "nebula": false})
	var k := 0
	for cl in clouds:
		if k >= 2: break
		if not (cl is Dictionary) or not (cl as Dictionary).has("center"): continue
		var cc = cl["center"]
		var cp: Vector3 = cc if cc is Vector3 else (Vector3(float(cc[0]), float(cc[1]) if (cc as Array).size() > 2 else 0.0, float(cc[(cc as Array).size() - 1])) if cc is Array else Vector3.ZERO)
		if cp.distance_to(c) < 9000.0: continue      # (too near the station to be "a good distance")
		out[k] = {"pos": cp, "nebula": true}
		k += 1
	return out
