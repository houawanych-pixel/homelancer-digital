class_name Factions
extends RefCounted
## Job V (v1.4r): the faction records and the reputation rules. Data-driven: a faction is filled in here (and its six
## characters in Data.ROSTERS, its fighters in Data.ENEMIES) when the owner delivers its pack. Nothing here is
## Savagers-only code. Factions whose pack is not in yet keep their placeholder patrols (character_roster "").
##
## reputation_mode "normal": the faction sits on the purple -> red spectrum and shares ONE number with its rival
## (helping one side moves you toward it and away from the other). "enemy": a GRAY permanent enemy, no diplomacy.
## The four rival pairs are a first guess (the Savagers' neighbour on the map is the Liberators): one line each to change.

const DEFS := {
	"Savagers": {"faction_id": "savagers", "ui_background": "savagers", "display_name": "Savagers", "primary_color": Color(0.78, 0.25, 0.12), "secondary_color": Color(0.12, 0.11, 0.11),
		"rival_faction_id": "Liberator", "reputation_mode": "normal", "base_standing": -40.0,
		"character_roster": "Savagers", "fighter_pool": ["scrapfang", "redclaw", "ironhowl", "warboar"],
		"station_pool": ["savagers_cross_station", "light_beacon_station"],
		"base_types": ["hidden station", "nebula hideout", "asteroid base", "underground hangar", "wreck field"],
		"environment_tags": ["desert", "wasteland", "badlands", "scrapyard", "caves", "black market", "salvage"],
		"spawn_weights": {"patrol": 6.0, "raider_group": 3.0, "scavenger_convoy": 1.0, "named": 1.0, "boss": 0.2}, "incursion": true},
	"Liberator": {"faction_id": "liberator", "ui_background": "liberator", "display_name": "Liberators", "primary_color": Color(0.3, 0.75, 0.72), "secondary_color": Color(0.9, 0.92, 0.95),
		"rival_faction_id": "Savagers", "reputation_mode": "normal", "base_standing": 10.0},
	"Unity": {"faction_id": "unity", "ui_background": "unity", "display_name": "Unity", "primary_color": Color(0.78, 0.9, 0.96), "secondary_color": Color(0.2, 0.35, 0.6),
		"rival_faction_id": "Imperium", "reputation_mode": "normal", "base_standing": 10.0},
	"Imperium": {"faction_id": "imperium", "ui_background": "imperium", "display_name": "Imperium", "primary_color": Color(0.75, 0.25, 0.28), "secondary_color": Color(0.15, 0.1, 0.1),
		"rival_faction_id": "Unity", "reputation_mode": "normal", "base_standing": 10.0},
	"Elyza": {"faction_id": "elyza", "ui_background": "elyza", "display_name": "Elyza", "primary_color": Color(0.45, 0.6, 0.95), "secondary_color": Color(0.85, 0.87, 0.95),
		"rival_faction_id": "Covenant", "reputation_mode": "normal", "base_standing": 10.0},
	"Covenant": {"faction_id": "covenant", "ui_background": "covenant", "display_name": "Covenant", "primary_color": Color(0.6, 0.4, 0.85), "secondary_color": Color(0.2, 0.15, 0.3),
		"rival_faction_id": "Elyza", "reputation_mode": "normal", "base_standing": 10.0},
	"Solarion": {"faction_id": "solarion", "ui_background": "solarion", "display_name": "Solarion", "primary_color": Color(0.95, 0.72, 0.3), "secondary_color": Color(0.3, 0.22, 0.1),
		"rival_faction_id": "Orion", "reputation_mode": "normal", "base_standing": 10.0},
	"Orion": {"faction_id": "orion", "ui_background": "orion", "display_name": "Orion", "primary_color": Color(0.25, 0.7, 0.45), "secondary_color": Color(0.1, 0.2, 0.14),
		"rival_faction_id": "Solarion", "reputation_mode": "normal", "base_standing": 10.0},
	"Cybermorph": {"faction_id": "cybermorph", "ui_background": "cybermorphs", "display_name": "Cybermorph", "primary_color": Color(0.62, 0.64, 0.68), "secondary_color": Color(0.1, 0.1, 0.12),
		"rival_faction_id": "", "reputation_mode": "enemy", "base_standing": -100.0},
	# v1.4s: the other permanent-enemy factions. Outside the rival pairs; their interface art is used for captured
	# places, enemy terminals and story screens.
	"Solrath": {"faction_id": "solrath", "ui_background": "solrath", "display_name": "Solrath", "primary_color": Color(0.8, 0.15, 0.2), "secondary_color": Color(0.08, 0.05, 0.06),
		"rival_faction_id": "", "reputation_mode": "enemy", "base_standing": -100.0},
	"Gadversee": {"faction_id": "gadversee", "ui_background": "gadversee", "display_name": "Gadversee", "primary_color": Color(0.55, 0.85, 0.3), "secondary_color": Color(0.08, 0.1, 0.05),
		"rival_faction_id": "", "reputation_mode": "enemy", "base_standing": -100.0},
	"Arctides": {"faction_id": "arctides", "ui_background": "arctides", "display_name": "Arctides", "primary_color": Color(0.6, 0.8, 1.0), "secondary_color": Color(0.08, 0.12, 0.2),
		"rival_faction_id": "", "reputation_mode": "enemy", "base_standing": -100.0},
	"Phenom": {"faction_id": "phenom", "ui_background": "phenom", "display_name": "Phenom", "primary_color": Color(0.65, 0.4, 1.0), "secondary_color": Color(0.08, 0.05, 0.14),
		"rival_faction_id": "", "reputation_mode": "enemy", "base_standing": -100.0},
	"Kaijurai": {"faction_id": "kaijurai", "ui_background": "kaijurai", "display_name": "Kaijurai", "primary_color": Color(0.95, 0.8, 0.35), "secondary_color": Color(0.12, 0.1, 0.05),
		"rival_faction_id": "", "reputation_mode": "enemy", "base_standing": -100.0},
}

static func has(f: String) -> bool: return DEFS.has(f)
static func def(f: String) -> Dictionary: return DEFS.get(f, {})
static func normal(f: String) -> bool: return DEFS.get(f, {}).get("reputation_mode", "") == "normal"
static func rival(f: String) -> String: return str(DEFS.get(f, {}).get("rival_faction_id", ""))
static func majors() -> Array: return DEFS.keys().filter(func(f): return normal(f))

## The systems a faction holds (from the galaxy map): territory_ids / home_systems of the record.
static func territory(f: String) -> Array:
	var out: Array = []
	for id in Data.SYSTEMS:
		if str(Data.SYSTEMS[id].get("faction", "")) == f: out.append(id)
	return out

## Full record with the computed fields the brief lists (territory_ids, home_systems, character_roster as people).
static func record(f: String) -> Dictionary:
	if not DEFS.has(f): return {}
	var d: Dictionary = (DEFS[f] as Dictionary).duplicate()
	d["territory_ids"] = territory(f)
	d["home_systems"] = d["territory_ids"].filter(func(id): return str(Data.SYSTEMS[id].get("role", "")) == "capital")
	d["characters"] = Data.ROSTERS.get(str(d.get("character_roster", "")), {}).get("pilots", [])
	return d

## One shared number per rival pair, stored under the two names in alphabetical order; + favours the first name.
static func axis_key(f: String) -> String:
	var r := rival(f)
	if r == "": return f
	return "%s|%s" % ([f, r] if f < r else [r, f])

static func _side(f: String) -> float:
	var r := rival(f)
	return 1.0 if (r == "" or f < r) else -1.0

static func standing(f: String) -> float:
	if not DEFS.has(f): return 0.0
	return clampf(float(DEFS[f]["base_standing"]) + _side(f) * float(GS.rep.get(axis_key(f), 0.0)), -Data.REP_LIMIT, Data.REP_LIMIT)

## "purple" .. "red", or "gray" for a permanent enemy. Factions with no record yet read "green".
static func band(f: String) -> String:
	if not DEFS.has(f): return "green"
	if not normal(f): return "gray"
	var v := standing(f)
	for b in Data.REP_BANDS:
		if v >= float(b[1]): return b[0]
	return "red"

static func info(f: String) -> Dictionary: return Data.REP_INFO[band(f)]
static func hostile(f: String) -> bool: return bool(Data.REP_INFO[band(f)]["hostile"])
static func hunted(f: String) -> bool: return band(f) == "red"

## Move your standing with a faction (+ helped them, - hurt them). Its rival moves the other way: same number.
static func adjust(f: String, delta: float) -> void:
	if not normal(f): return
	var k := axis_key(f)
	GS.rep[k] = clampf(float(GS.rep.get(k, 0.0)) + _side(f) * delta * (Data.REP_RIVAL_SHARE if rival(f) != "" else 1.0), -Data.REP_LIMIT * 2.0, Data.REP_LIMIT * 2.0)
	GS.changed.emit()

## The faction that raids this system's owner (its rival, if that rival has people and raids). "" = nobody.
static func raider_of(f: String) -> String:
	var r := rival(f)
	if r != "" and DEFS[r].get("incursion", false) and Data.ROSTERS.has(str(DEFS[r].get("character_roster", ""))): return r
	return ""

## v1.4s: the static picture behind a station's interface. Priority: the station's own picture (station
## "ui_background"), then its owner faction's, then none (the hub draws its plain neutral backdrop).
## Returns {path, pack, source}: source is "station", "faction" or "neutral"; path and pack are "" for neutral.
static func hub_background(station: Dictionary, system: Dictionary) -> Dictionary:
	var own := str(station.get("ui_background", ""))
	if own != "": return {"path": Data.HUB_BG_DIR + own + ".jpg", "pack": "hubbg_" + own, "source": "station", "faction": owner_of(station, system)}
	var f := owner_of(station, system)
	var name := str(DEFS.get(f, {}).get("ui_background", ""))
	if name != "": return {"path": Data.HUB_BG_DIR + name + ".jpg", "pack": "hubbg_" + name, "source": "faction", "faction": f}
	return {"path": "", "pack": "", "source": "neutral", "faction": f}

## Who owns a station or planet: its own "faction" if it has one, else the system's.
static func owner_of(station: Dictionary, system: Dictionary) -> String:
	return str(station.get("faction", system.get("faction", "")))
