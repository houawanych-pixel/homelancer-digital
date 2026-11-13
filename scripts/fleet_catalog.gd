class_name FleetCatalog
extends RefCounted
## v12.97 (owner brief "Put the eight friendly faction fleets into the game's systems"): the 8 factions x 9 classes
## of the faction fleet rosters (HL_<Faction>Fleet_TopDown_20261109_v1.png). Ids are lowercase faction_class
## (unity_capital, elyza_scout, imperium_destroyer, ...).
##
## What exists for each ship today:
##   - token: the ship cut out of its faction's roster sheet (tools/fleet/crop_tokens.py; the crop box is in
##     assets/fleet_tokens/fleet_crops.json). The in-space stand-in is this flat top-down token, labelled PLACEHOLDER.
##     There are NO 3D models of these 72 ships yet (no approved front/side/back views; nothing sent to Tripo).
##   - holodeck: the official one-deck plan (HL_<Faction><Class>_HoloDeck_YYYYMMDD_vN), when the owner has made it.
##   - stage: the walkable interior built from that plan (scripts/ship_interior.gd), when it has been blocked out.
## The player's own ships (Data.SHIPS: Cadet, Ranger, Lancer) and the older faction battleships (Data.FACTION_FLEET)
## are untouched.

const FACTIONS := ["Unity", "Elyza", "Solarion", "Covenant", "Savagers", "Imperium", "Orion", "Liberator"]
const CLASSES := ["Capital", "Cruiser", "Destroyer", "Resupply", "TroopTransport", "Frigate", "Escort", "Scout", "Bomber"]
const CLASS_NAME := {"Capital": "Capital Ship", "Cruiser": "Cruiser", "Destroyer": "Destroyer", "Resupply": "Resupply Ship",
	"TroopTransport": "Troop Transport", "Frigate": "Frigate", "Escort": "Escort", "Scout": "Scout", "Bomber": "Bomber"}
const ROLE := {
	"Capital": "Command ship with a hangar.",
	"Cruiser": "Warship.",
	"Destroyer": "Strike warship.",
	"Resupply": "Cargo and logistics.",
	"TroopTransport": "Barracks and dropship.",
	"Frigate": "Smaller warship.",
	"Escort": "Smaller warship; screens the bigger ships.",
	"Scout": "Recon.",
	"Bomber": "Munitions; bomb bay.",
}

# ============================================================================================================
# PLACEHOLDER STATS: NOT owner-approved numbers. Scaled only by class (capitals biggest and slowest, scouts and
# bombers smallest and fastest). Every faction uses the same row for a class. Replace this table when the real
# numbers are decided; nothing else in the game reads fleet stats from anywhere else.
#   len   = length in metres of the in-space stand-in (Capital matches the existing FLEET_BATTLESHIP_LEN)
#   speed = m/s cruise   turn = rad/s   hull / shield / guns = same units as Data.SHIPS
const PLACEHOLDER_STATS := {
	"Capital":        {"len": 1360.0, "speed": 40.0,  "turn": 0.10, "hull": 9000, "shield": 6000, "guns": 24},
	"Cruiser":        {"len": 360.0,  "speed": 60.0,  "turn": 0.18, "hull": 4000, "shield": 2600, "guns": 12},
	"Destroyer":      {"len": 260.0,  "speed": 75.0,  "turn": 0.25, "hull": 2600, "shield": 1600, "guns": 10},
	"Resupply":       {"len": 220.0,  "speed": 50.0,  "turn": 0.16, "hull": 2200, "shield": 900,  "guns": 2},
	"TroopTransport": {"len": 180.0,  "speed": 70.0,  "turn": 0.22, "hull": 1800, "shield": 900,  "guns": 4},
	"Frigate":        {"len": 150.0,  "speed": 95.0,  "turn": 0.35, "hull": 1200, "shield": 700,  "guns": 6},
	"Escort":         {"len": 110.0,  "speed": 110.0, "turn": 0.45, "hull": 800,  "shield": 500,  "guns": 4},
	"Scout":          {"len": 45.0,   "speed": 170.0, "turn": 0.9,  "hull": 240,  "shield": 160,  "guns": 2},
	"Bomber":         {"len": 30.0,   "speed": 150.0, "turn": 0.8,  "hull": 300,  "shield": 140,  "guns": 2},
}
# ============================================================================================================

const ART_DATE := "20261109"
const TOKEN_DIR := "res://assets/fleet_tokens/"
const HOLODECK_DIR := "res://assets/holodeck/"
## The official deck-plan files that existed in Homelancer Art when this was built (v1, 2026-11-09). A missing
## faction/class has no interior: its fleet entry stays a stub until the file appears (no substitute map).
const HOLODECK_FILES := [
	"HL_UnityCapital_HoloDeck_20261109_v1", "HL_UnityCruiser_HoloDeck_20261109_v1", "HL_UnityDestroyer_HoloDeck_20261109_v1",
	"HL_UnityResupply_HoloDeck_20261109_v1", "HL_UnityTroopTransport_HoloDeck_20261109_v1", "HL_UnityFrigate_HoloDeck_20261109_v1",
	"HL_UnityEscort_HoloDeck_20261109_v1", "HL_UnityScout_HoloDeck_20261109_v1", "HL_UnityBomber_HoloDeck_20261109_v1",
	"HL_ElyzaCapital_HoloDeck_20261109_v1", "HL_ElyzaCruiser_HoloDeck_20261109_v1", "HL_ElyzaDestroyer_HoloDeck_20261109_v1",
	"HL_ElyzaResupply_HoloDeck_20261109_v1", "HL_ElyzaFrigate_HoloDeck_20261109_v1",
	# v13.03 (owner: "build every one of those fleet ships ... build what we have first"): the big ships first
	"HL_ImperiumCapital_HoloDeck_20261109_v1", "HL_ImperiumCruiser_HoloDeck_20261109_v1", "HL_ImperiumDestroyer_HoloDeck_20261109_v1",
	"HL_ImperiumResupply_HoloDeck_20261109_v1", "HL_ImperiumTroopTransport_HoloDeck_20261109_v1",
	"HL_CovenantCapital_HoloDeck_20261109_v1", "HL_CovenantCruiser_HoloDeck_20261109_v1", "HL_CovenantDestroyer_HoloDeck_20261109_v1",
	"HL_CovenantResupply_HoloDeck_20261109_v1", "HL_CovenantTroopTransport_HoloDeck_20261109_v1",
]
## v13.117: ships with no deck-plan file whose main deck was COMPOSED inside the fleet token
## (tools/trace/fleetmain.py, PROPOSED, waiting for the owner's OK): boardable from assets/holodeck/<id>.json, map
## picture assets/holodeck/<id>_plan.jpg. The official HoloDeck pointer stays empty.
const COMPOSED := [
	"solarion_capital", "solarion_cruiser", "solarion_destroyer", "solarion_resupply", "solarion_trooptransport",
	"solarion_frigate", "solarion_escort", "solarion_scout",
	"savagers_capital", "savagers_cruiser", "savagers_destroyer", "savagers_resupply", "savagers_trooptransport",
	"savagers_frigate", "savagers_escort", "savagers_scout",
]
## How a faction's own systems show its fleet (FleetCatalog.spawn_plan): where each class sits.
##   patrol = slow loop well out from the station; screen = tighter loop near the station;
##   docked = parked beside the station (a visitor); traffic = runs the station-planet lane.
const PRESENCE := {"Capital": "patrol", "Cruiser": "patrol", "Destroyer": "patrol", "Frigate": "screen", "Escort": "screen",
	"Resupply": "docked", "TroopTransport": "docked", "Scout": "traffic", "Bomber": "traffic"}

static func id_of(faction: String, cls: String) -> String: return "%s_%s" % [faction.to_lower(), cls.to_lower()]

static var _all := {}
## Every entry, keyed by id (72).
static func all() -> Dictionary:
	if not _all.is_empty(): return _all
	for f in FACTIONS:
		for c in CLASSES:
			var id := id_of(f, c)
			var hd := "HL_%s%s_HoloDeck_%s_v1" % [f, c, ART_DATE]
			var has_hd: bool = hd in HOLODECK_FILES
			var stage := "%s%s.json" % [HOLODECK_DIR, id]
			_all[id] = {
				"id": id, "name": "%s %s" % [f, CLASS_NAME[c]], "faction": f, "class": c, "role": ROLE[c],
				"holodeck": (hd + ".png") if has_hd else "",                     # the official file name (Drive: Homelancer Art)
				"holodeck_res": (HOLODECK_DIR + hd + ".jpg") if has_hd else ((HOLODECK_DIR + id + "_plan.jpg") if id in COMPOSED else ""),
				"stage": stage if (has_hd or id in COMPOSED) and FileAccess.file_exists(stage) else "",
				"sheet": "HL_%sFleet_TopDown_%s_v1.png" % [f, ART_DATE],
				"token": TOKEN_DIR + "%s.png" % id,
				"stats": PLACEHOLDER_STATS[c], "stats_placeholder": true,
				"presence": PRESENCE[c],
			}
	return _all

static func get_entry(id: String) -> Dictionary: return all().get(id, {})
static func of_faction(faction: String) -> Array:
	return CLASSES.map(func(c): return all()[id_of(faction, c)])
## The token-sheet crop box [x0, y0, x1, y1] (sheet pixels) of a ship, from tools/fleet/crop_tokens.py.
static var _crops := {}
static func crop(id: String) -> Array:
	if _crops.is_empty():
		var f := FileAccess.open(TOKEN_DIR + "fleet_crops.json", FileAccess.READ)
		if f: _crops = JSON.parse_string(f.get_as_text())
	var e := get_entry(id)
	if e.is_empty() or not _crops.has(e["faction"]): return []
	return (_crops[e["faction"]]["crops"] as Dictionary).get(e["class"], [])

static func with_stage() -> Array: return all().values().filter(func(e): return str(e["stage"]) != "")
static func missing_holodecks() -> Array: return all().values().filter(func(e): return str(e["holodeck"]) == "").map(func(e): return e["id"])

## The systems that fly a faction's fleet: the ones the faction owns (Data.SYSTEMS "faction"; no new systems).
static func systems_of(faction: String) -> Array:
	return Data.faction_systems(faction).filter(func(sid): return str(Data.SYSTEMS[sid].get("faction", "")) == faction)

## Dealer hook (ADDITIONAL entries only; the Cadet / Ranger / Lancer dealer list is unchanged): the station's faction
## fleet, shown below the ships for sale as "not for sale" cards. A ship with a stage gets a DECK PLAN button.
static func dealer_entries(faction: String) -> Array:
	if not faction in FACTIONS: return []
	return of_faction(faction)
