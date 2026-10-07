extends SceneTree
## dump.gd -- out.json : every roster person with their ship, for the overview sheet (tools/rosterkit/board.py).
func _initialize() -> void:
	var out := {}
	for f in Data.ROSTERS:
		var rows: Array = []
		for p in Data.ROSTERS[f]["pilots"]:
			var k: String = p["fighter_primary"]
			var e: Dictionary = Data.ENEMIES.get(k, {})
			var mk: String = e.get("model", "")
			rows.append({"id": p["id"], "name": p["name"], "slot": p["slot"], "role": p.get("role", p.get("type", "")), "ship_key": k, "ship": e.get("name", ""),
				"glb": ProjectSettings.globalize_path(ShipFactory.GLB[mk][0]) if ShipFactory.GLB.has(mk) else "", "yaw": ShipFactory.GLB[mk][2] if ShipFactory.GLB.has(mk) else 0.0})
		out[f] = {"title": Data.ROSTERS[f].get("title", ""), "enemy": not Factions.normal(f), "pilots": rows}
	var fa := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	fa.store_string(JSON.stringify(out))
	fa.close()
	quit()
