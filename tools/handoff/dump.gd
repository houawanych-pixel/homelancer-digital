extends RefCounted
## tools/handoff/dump.gd -- writes the game's model table, the ships / enemies / mechs that use them, the mount and
## wing data, and every system's layout (station, planet, gates, sun, belts) to one JSON file, for the asset handoff.
## usage: HL_DUMP=out.json godot --headless --path . -- --autotest --quit-after-test   (runs inside the game)
static func _clean(v):
	match typeof(v):
		TYPE_VECTOR3: return {"x": v.x, "y": v.y, "z": v.z}
		TYPE_VECTOR2: return {"x": v.x, "y": v.y}
		TYPE_VECTOR2I: return {"x": v.x, "y": v.y}
		TYPE_COLOR: return "#" + v.to_html(false)
		TYPE_DICTIONARY:
			var o := {}
			for k in v: o[str(k)] = _clean(v[k])
			return o
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_VECTOR3_ARRAY:
			var a := []
			for x in v: a.append(_clean(x))
			return a
		TYPE_OBJECT: return str(v)
		_: return v

static func run(out: String) -> void:
	var cm: Dictionary = (load("res://scripts/data.gd") as GDScript).get_script_constant_map()
	var consts := {}
	for k in ["SPACE_EDGE", "PLACEHOLDER_SHIP_LEN", "WING_GUN_LEN", "MOUNT_SHOULDER_AT", "MOUNT_MID_AT", "MOUNT_TIP_AT", "MOUNT_DROP", "ALIEN_SHIP_YAW", "LIBERATOR_YAW"]:
		if cm.has(k): consts[k] = cm[k]
	var lens := {}
	for p in cm:
		if str(p).ends_with("_LEN") or str(p).ends_with("_YAW"): lens[p] = cm[p]
	var d := {
		"glb_table": ShipFactory.GLB,
		"ships": Data.SHIPS,
		"enemies": Data.ENEMIES,
		"mechs": cm.get("MECHS", {}),
		"ship_wings": cm.get("SHIP_WINGS", {}),
		"ship_special_move": cm.get("SHIP_SPECIAL_MOVE", {}),
		"ship_levels": cm.get("SHIP_LEVELS", cm.get("LEVELS", {})),
		"lengths_and_yaws": lens,
		"constants": consts,
		"systems": Data.SYSTEMS,
		"surface": {"TILE": Surface.TILE, "EDGE": Surface.EDGE, "planets": Surface.PLANETS},
	}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(_clean(d), "  "))
	f.close()
	print("wrote ", out)
