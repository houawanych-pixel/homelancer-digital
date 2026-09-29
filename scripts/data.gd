class_name Data
extends RefCounted
## Static game data for Homelancer Digital v1.2. All names, ships and places are original Homelancer content.

const VERSION := "v1.2"

# ---------------------------------------------------------------- ships
# model: key understood by ShipFactory. "cadet_glb" etc. load real GLBs when present under assets/ships/.
const SHIPS := {
	"cadet": {"name": "Cadet", "class": "Starter fighter", "price": 0, "hull": 100, "shield": 60, "speed": 46.0,
		"turn": 1.7, "guns": 2, "missiles": 6, "mines": 3, "model": "cadet", "desc": "Unity-issue trainer. Light, nimble, forgiving."},
	"ranger": {"name": "Ranger", "class": "Patrol fighter", "price": 1500, "hull": 160, "shield": 95, "speed": 50.0,
		"turn": 1.55, "guns": 2, "missiles": 10, "mines": 4, "model": "ranger", "desc": "Faster frame with thicker plating and a bigger rack."},
	"lancer": {"name": "Lancer", "class": "Heavy fighter", "price": 4000, "hull": 240, "shield": 140, "speed": 42.0,
		"turn": 1.25, "guns": 3, "missiles": 14, "mines": 6, "model": "lancer", "desc": "Three hardpoints and a heavy shield. Slow to turn."},
}
const SHIP_ORDER := ["cadet", "ranger", "lancer"]

# ---------------------------------------------------------------- weapons (per gun)
const WEAPONS := {
	"pulse1": {"name": "Pulse Laser Mk I", "price": 0, "damage": 8.0, "rate": 4.0, "speed": 420.0, "range": 520.0, "color": Color(0.45, 0.9, 1.0)},
	"pulse2": {"name": "Pulse Laser Mk II", "price": 600, "damage": 12.0, "rate": 4.5, "speed": 440.0, "range": 540.0, "color": Color(0.5, 1.0, 0.8)},
	"ion": {"name": "Ion Repeater", "price": 1200, "damage": 9.0, "rate": 7.5, "speed": 470.0, "range": 480.0, "color": Color(0.7, 0.6, 1.0)},
	"plasma": {"name": "Plasma Driver", "price": 2600, "damage": 26.0, "rate": 2.4, "speed": 340.0, "range": 560.0, "color": Color(1.0, 0.6, 0.25)},
}
const WEAPON_ORDER := ["pulse1", "pulse2", "ion", "plasma"]
const MISSILE_PRICE := 40
const MISSILE_DAMAGE := 45.0
const MINE_PRICE := 60
const MINE_DAMAGE := 70.0
const MINE_RADIUS := 45.0
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 9.0 # per second
const ENERGY_PER_GUN := 1.5 # per shot per gun
const SHIELD_BOOST_COOLDOWN := 3.0
const MAX_SHIELD_CHARGES := 5
const MAX_ENERGY_CELLS := 5
const WARP_CHARGE := 3.0 # seconds, from a full stop
const WARP_MULT := 6.0 # x ship speed
const THRUST_MULT := 2.0 # afterburner x ship speed
const THRUST_ENERGY := 14.0 # per second
const ENERGY_BOOST_COOLDOWN := 3.0
# The six cockpit systems. AUTO = the ship triggers it when needed; MANUAL = tap the panel.
const SYSTEMS_UI := [
	{"id": "shield", "label": "SHIELD\nRECHARGE", "side": "left"},
	{"id": "hull", "label": "HULL\nREPAIR", "side": "left"},
	{"id": "energy", "label": "ENERGY\nRECHARGE", "side": "left"},
	{"id": "guns", "label": "FIRE\nWEAPONS", "side": "right"},
	{"id": "missile", "label": "FIRE\nMISSILE", "side": "right"},
	{"id": "mine", "label": "DEPLOY\nMINE", "side": "right"},
]
const MAX_REPAIRS := 5
const REPAIR_AMOUNT := 0.4 # fraction of max hull

# ---------------------------------------------------------------- enemies
const ENEMIES := {
	"raider": {"name": "Raider", "hull": 60.0, "speed": 44.0, "turn": 1.3, "damage": 5.0, "rate": 1.6, "reward": 150},
	"corsair": {"name": "Corsair", "hull": 90.0, "speed": 48.0, "turn": 1.4, "damage": 6.0, "rate": 1.9, "reward": 220},
}

# ---------------------------------------------------------------- star systems
# Positions in metres-ish world units. The player spawns at `spawn` (station launch) or at the gate exit.
const SYSTEMS := {
	"solara": {
		"name": "Solara", "star": Color(1.0, 0.86, 0.6), "sky_tint": Color(0.10, 0.06, 0.16), "ambient": Color(0.42, 0.40, 0.55),
		"sun_dir": Vector3(-0.4, -0.35, -1.0),
		"station": {"id": "liberty_hub", "name": "Liberty Hub", "pos": Vector3(0, 0, -260), "kind": "station",
			"desc": "Unity trade and patrol hub. Repairs, outfitting and a ship dealer.", "color": Color(0.72, 0.78, 0.9)},
		"planet": {"id": "new_terra", "name": "New Terra", "pos": Vector3(1500, -260, -2500), "radius": 420.0, "kind": "planet",
			"desc": "Temperate colony world. Orbital landing field at Port Meridian.", "palette": "terran"},
		"gate": {"id": "aquila_gate", "name": "Aquila Jump Gate", "pos": Vector3(-300, 40, -4200), "to": "vega"},
		"asteroids": {"name": "Solara Belt", "center": Vector3(-950, 0, -1700), "radius": 380.0, "count": 150, "ice": false},
		"nebula": {"name": "Violet Reach", "center": Vector3(-350, 60, -3050), "radius": 480.0, "color": Color(0.55, 0.25, 0.85)},
		"enemy": "raider",
		"patrols": [Vector3(520, 30, -1000), Vector3(-760, 0, -1500), Vector3(-200, 60, -3400)],
		"traffic": [["liberty_hub", "new_terra"]],
	},
	"vega": {
		"name": "Vega", "star": Color(0.7, 0.85, 1.0), "sky_tint": Color(0.03, 0.08, 0.14), "ambient": Color(0.38, 0.46, 0.58),
		"sun_dir": Vector3(0.5, -0.3, -1.0),
		"station": {"id": "frontier_exchange", "name": "Frontier Exchange", "pos": Vector3(780, 0, -950), "kind": "station",
			"desc": "Independent frontier market on the edge of charted space.", "color": Color(0.92, 0.72, 0.4)},
		"planet": {"id": "eden_prime", "name": "Eden Prime", "pos": Vector3(-1700, 320, -2300), "radius": 480.0, "kind": "planet",
			"desc": "Lush jungle world. Landing at the Verdant Terrace spaceport.", "palette": "jungle"},
		"gate": {"id": "solara_gate", "name": "Solara Jump Gate", "pos": Vector3(0, 0, 0), "to": "solara"},
		"asteroids": {"name": "Vega Ice Field", "center": Vector3(950, -40, -2650), "radius": 420.0, "count": 160, "ice": true},
		"nebula": {"name": "Azure Veil", "center": Vector3(-350, 0, -1450), "radius": 440.0, "color": Color(0.2, 0.55, 0.95)},
		"enemy": "corsair",
		"patrols": [Vector3(250, 0, -1700), Vector3(900, -20, -2300), Vector3(-900, 150, -1900)],
		"traffic": [["frontier_exchange", "eden_prime"]],
	},
}
const SYSTEM_LINKS := [["solara", "vega"]]
