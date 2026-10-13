extends Node
## Dump the galaxy as the game builds it (systems, grid cell, faction, planets, stations, gates) to JSON. Work tool.
func _ready() -> void:
	var out := {"systems": [], "gates": []}
	var rows := {}
	for t in GalaxyData.TILES: rows[t[0]] = t
	for id in Data.SYSTEMS:
		var sy: Dictionary = Data.SYSTEMS[id]
		var t: Array = rows.get(id, [])
		var planets: Array = [str(sy["planet"]["name"])]
		for p in sy.get("more_planets", []): planets.append(str(p["name"]))
		var stations: Array = [str(sy["station"]["name"])]
		var models: Array = [str(sy["station"].get("model", ""))]
		for s2 in sy.get("more_stations", []):
			stations.append(str(s2["name"]))
			models.append(str(s2.get("model", "")))
		out["systems"].append({"id": id, "name": str(sy.get("name", id)), "tile": t[2] if t else "", "col": t[3] if t else -1, "row": t[4] if t else -1,
			"faction": t[5] if t else str(sy.get("faction", "")), "role": t[6] if t else str(sy.get("role", "")), "planets": planets, "stations": stations, "models": models,
			"roamers": Data.STATION3D_ROAMERS.get(id, []).map(func(r): return r[1])})
	for g in GalaxyData.GATES: out["gates"].append(g)
	var f := FileAccess.open((OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://galaxy.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("DUMPED ", out["systems"].size(), " systems, ", out["gates"].size(), " gates")
	get_tree().quit()
