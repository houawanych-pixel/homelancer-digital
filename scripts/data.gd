class_name Data
extends RefCounted
## Static game data for Homelancer Digital v1.2. All names, ships and places are original Homelancer content.

# Beta version shown on the start screen and on the Hova Matrix landing page (which reads it from web_shell.html).
# Scheme (owner): the letter is the Chief job that shipped it: v1.2x, v1.2y, v1.2z, then v1.3a, v1.3b ...
# Change it in BOTH places for every job: here and the hl-version meta + title in web_shell.html (a test checks it).
const VERSION := "v1.4h"

# ---------------------------------------------------------------- Job J (v1.4f): desktop keyboard + mouse controls
# Every Job J number and default lives in this one block. Phone/touch controls do not use any of it.
# Each action: id (also the InputMap action name), name (shown in Settings > Controls), key (default binding:
# a key like "W", "Shift+W", "F3", or a mouse button "Mouse Left" / "Mouse Right" / "Mouse Middle"),
# rebind (can the player change it), extra (a Homelancer-only action on top of the Freelancer baseline).
# Freelancer baseline (owner correction: weapons fire on RIGHT-click; left-click selects a target, left-drag steers).
const KBM_ACTIONS := [
	{"id": "fire", "name": "Fire weapons", "key": "Mouse Right", "rebind": true, "extra": false},
	{"id": "select", "name": "Select target (click) / steer (hold + drag)", "key": "Mouse Left", "rebind": false, "extra": false},
	{"id": "mouse_flight", "name": "Mouse flight on/off", "key": "Space", "rebind": true, "extra": false},
	{"id": "missile", "name": "Fire missiles", "key": "Q", "rebind": true, "extra": false},
	{"id": "forward", "name": "Throttle up", "key": "W", "rebind": true, "extra": false},
	{"id": "back", "name": "Throttle down", "key": "S", "rebind": true, "extra": false},
	{"id": "strafe_left", "name": "Strafe left", "key": "A", "rebind": true, "extra": false},
	{"id": "strafe_right", "name": "Strafe right", "key": "D", "rebind": true, "extra": false},
	{"id": "brake", "name": "Reverse / brake", "key": "X", "rebind": true, "extra": false},
	{"id": "engine_kill", "name": "Engine kill", "key": "Z", "rebind": true, "extra": false},
	{"id": "cruise", "name": "Cruise engine (warp drive) on/off", "key": "Shift+W", "rebind": true, "extra": false},
	{"id": "afterburner", "name": "Afterburner (hold)", "key": "Tab", "rebind": true, "extra": false},
	{"id": "target_closest", "name": "Target closest enemy", "key": "R", "rebind": true, "extra": false},
	{"id": "target_next", "name": "Next target", "key": "T", "rebind": true, "extra": false},
	{"id": "dock", "name": "Dock / activate (stations, planets, jump gates)", "key": "F3", "rebind": true, "extra": false},
	# Homelancer-only extras (same list, also rebindable)
	{"id": "transform", "name": "Transform ship / mech", "key": "G", "rebind": true, "extra": true},
	{"id": "view", "name": "Chase / cockpit view", "key": "V", "rebind": true, "extra": true},
	{"id": "map", "name": "System map", "key": "M", "rebind": true, "extra": true},
	{"id": "yaw_left", "name": "Turn left (keyboard)", "key": "Left", "rebind": true, "extra": true},
	{"id": "yaw_right", "name": "Turn right (keyboard)", "key": "Right", "rebind": true, "extra": true},
	{"id": "pitch_up", "name": "Nose up (keyboard)", "key": "Up", "rebind": true, "extra": true},
	{"id": "pitch_down", "name": "Nose down (keyboard)", "key": "Down", "rebind": true, "extra": true},
	{"id": "settings", "name": "Settings", "key": "F1", "rebind": false, "extra": true},
]
const KBM_RESERVED := []              # keys that can never be bound to an action (empty by default)
const KBM_CANCEL_KEY := "Escape"      # cancels a "Press a key…" prompt (so it can't be bound)
const CONTROL_MODE_DEFAULT := "auto"  # auto | touch | kbm
const MOUSE_FLIGHT_DEFAULT := true    # mouse flight starts ON in keyboard + mouse mode, like Freelancer
const MOUSE_FLIGHT_RANGE := 0.45      # cursor this far from centre (fraction of half the screen height) = full turn
const MOUSE_DEAD_ZONE := 0.06         # no turn while the cursor is this close to the centre (same units)
const MOUSE_DRAG_PX := 8.0            # a left press that moves further than this is a steer drag, not a click
const MOUSE_DRAG_RANGE := 120.0       # pixels of left-drag for a full turn
const MOUSE_PICK_PX := 56.0           # a left click this close (pixels) to something on screen selects it
const WHEEL_THROTTLE := true          # mouse wheel moves the throttle
const WHEEL_STEP := 0.1               # throttle change per wheel notch (-1 .. 1)
const SETTINGS_PATH := "user://settings.cfg"   # new settings file (Job J); section "controls": mode, bindings
const SETTINGS_ROW_H := 48.0          # Controls list row height (big enough for a thumb or a mouse)
const SETTINGS_RESET_CONFIRM_S := 3.0 # press Reset again within this many seconds to confirm

# ---------------------------------------------------------------- Job K (v1.4g): jump-gate docking + warp tunnel
# Every Job K number lives in this one block. The jump destination logic is unchanged (gate "to" in the galaxy data).
const JUMP_TUNNEL_BUILD := 0.5        # s: the tunnel builds up (streaks + shake + blur) as the ship pushes through the gate
const JUMP_TUNNEL_HOLD_MIN := 0.25    # s: shortest time at full tunnel before the swap; the real load time adds to it
const JUMP_TUNNEL_CLEAR := 0.3        # s: the tunnel snaps clear once the next system is ready
const JUMP_SHAKE := 0.35              # camera shake at full tunnel (the atmosphere-entry shake start value)
const JUMP_BLUR := 0.6                # screen blur at full tunnel (0..1)
const JUMP_BLUR_PX := 6.0             # blur radius in pixels at blur 1
const JUMP_PUSH := 260.0              # m the ship travels on through the gate during the build (the old fly-through)
const JUMP_LAUNCH_MULT := 2.2         # arrival "boom": the ship is launched out at this x its top speed
const JUMP_LAUNCH_FLASH := 0.35       # s: white flash as the ship is launched out
const JUMP_FLASH_ALPHA := 0.55        # strength of that flash
const JUMP_REDUCED_FADE := 0.3        # s: reduced-effects jump: a plain fade out / in instead of streaks, shake and blur
const JUMP_STREAK_LAYERS := [[60, 0.45, 1.0], [50, 0.9, 1.8], [30, 1.6, 3.0]]   # [count, speed, width]: far, mid, near (near streaks move faster)
const REDUCED_EFFECTS_DEFAULT := false   # new setting (settings.cfg, section "effects", key "reduced"): full effects

# ---------------------------------------------------------------- Job L (v1.4h): collision damage
# Every Job L number lives in this one block. Damage = (impact speed - threshold) x multiplier, straight to the hull.
# Impact speed = how fast the ship was moving INTO the surface (m/s). Player ship only.
const COLLIDE_THRESHOLD := 8.0        # m/s: slower contact is free (gentle nudges, landings, scrapes)
const COLLIDE_MULT := 0.9             # hull per m/s above the threshold: a full-speed Cadet hit (~46 m/s) costs ~34 of 100
const COLLIDE_GRACE := 0.5            # s after a hit when another collision can't damage the ship
const COLLIDE_FX_FULL := 0.35         # a hit of this fraction of max hull gives the strongest feedback
const COLLIDE_SHAKE_MIN := 0.25       # camera shake for the softest damaging hit (1.0 = strongest)
const COLLIDE_FLASH_MIN := 0.15       # red hit flash (s) for the softest damaging hit ...
const COLLIDE_FLASH_MAX := 0.6        # ... and for the hardest
const COLLIDE_SFX_DB_SOFT := -14.0    # hit sound volume for a soft hit ...
const COLLIDE_SFX_DB_HARD := -2.0     # ... and a hard one

# ---------------------------------------------------------------- ships
# model: key understood by ShipFactory. "cadet_glb" etc. load real GLBs when present under assets/ships/.
const SHIPS := {
	"cadet": {"name": "Cadet", "class": "Starter fighter", "price": 0, "hull": 100, "shield": 60, "speed": 46.0,
		"turn": 1.7, "guns": 2, "missiles": 6, "heavy": 2, "mines": 3, "model": "cadet", "desc": "Unity-issue trainer. Light, nimble, forgiving. Twin cannons on top."},
	"ranger": {"name": "Ranger", "class": "Patrol fighter", "price": 1500, "hull": 160, "shield": 95, "speed": 50.0,
		"turn": 1.55, "guns": 3, "missiles": 10, "heavy": 3, "mines": 4, "model": "ranger", "desc": "Faster frame, thicker plating. A long cannon on top and one on each wing."},
	"lancer": {"name": "Lancer", "class": "Heavy fighter", "price": 4000, "hull": 240, "shield": 140, "speed": 42.0,
		"turn": 1.25, "guns": 4, "missiles": 14, "heavy": 4, "mines": 6, "model": "lancer", "desc": "Four cannons: two on the wings, two beside the nose. Heavy shield. Slow to turn."},
}
# v1.3c: all three are the owner's models with weapons mounted (tools/shipkit/make_fleet3.py). Guns = cannons you can see.
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
const MISSILE_DAMAGE := 45.0 # light missile minimum; it does LIGHT_MISSILE_HULL_FRAC of the target's hull when bigger
const LIGHT_MISSILE_HULL_FRAC := 0.3
const HEAVY_MISSILE_PRICE := 200
const HEAVY_MISSILE_DAMAGE := 75.0
const MINE_PRICE := 60
const MINE_DAMAGE := 70.0
const MINE_RADIUS := 45.0
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 9.0 # per second
const ENERGY_PER_GUN := 1.5 # per shot per gun
const SHIELD_BOOST_COOLDOWN := 3.0
const MAX_SHIELD_CHARGES := 5
const MAX_ENERGY_CELLS := 5
const WARP_CHARGE := 5.0 # seconds of spool; you can keep flying while it charges (SUPERSEDES: warp needed a full stop)
const ATMO_OUTER := 1.3   # planet radius x: outer atmosphere (haze, glow, rumble, surface data starts loading)
const ATMO_INNER := 1.02  # planet radius x: entry sphere (commits to the surface)
const WARP_MULT := 6.0 # x ship speed
const THRUST_MULT := 2.0 # afterburner x ship speed
const CRUISE := 0.55     # default cruise (x ship speed) with the left stick centred; full back = stop
# The sun (see docs/DESIGN.md §15): a sphere far out toward the system's edge, with a billboard glow on it.
const SUN_DIST := 40000.0        # from the system centre: far past the gate (~4,200) and everything else
const SUN_RADIUS := 5500.0       # the sphere: 5.5x a planet (radius 1,000). Touching it destroys the ship
const SUN_WARN := 1.5            # heat warning inside this many radii
const SUN_BLOOM_RANGE := 25000.0 # the screen bloom builds over this distance from the surface
const SUN_SHIELD_SECS := 3.0     # on the sun's surface without a heat shield: shields are gone in this long...
const SUN_HULL_SECS := 8.0       # ...then the hull
const SUN_DRAW_MAX := 11000.0    # the picture of the sun is drawn no farther than this (scaled to look right), so the camera range stays short
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
# Weapon slots (top-right buttons). Later the hub lets you fit any of these into a slot.
const SLOT_ITEMS := {
	"light_missile": {"label": "LIGHT", "sub": "MISSILE", "icon": "missile"},
	"heavy_missile": {"label": "HEAVY", "sub": "MISSILE", "icon": "heavy"},
	"mine": {"label": "MINE", "sub": "", "icon": "mine"},
}
const DEFAULT_SLOTS := ["light_missile", "heavy_missile", "mine"]
# Loot pods dropped by destroyed ships; the tractor beam pulls them in.
# Three-part damage: each side section (wing / arm) has this share of the unit's hull as its own health.
const SECTION_SHARE := 0.4
const LOOT_RANGE := 700.0
const TRACTOR_TIME := 4.0
const REPAIR_AMOUNT := 0.4 # fraction of max hull

# ---------------------------------------------------------------- enemies
const ENEMIES := {
	"raider": {"name": "Raider", "hull": 60.0, "shield": 30.0, "speed": 44.0, "turn": 1.3, "damage": 5.0, "rate": 1.6, "reward": 150},
	"corsair": {"name": "Corsair", "model": "enemy2", "hull": 90.0, "shield": 50.0, "speed": 48.0, "turn": 1.4, "damage": 6.0, "rate": 1.9, "reward": 220},
	# assault mech: two arm guns + a chest cannon; flies with the raiders/corsairs
	"mech": {"name": "Assault Mech", "hull": 120.0, "shield": 40.0, "speed": 40.0, "turn": 1.2, "damage": 6.0, "rate": 1.4, "reward": 280, "model": "mech_tan", "mech": true},
}

# ---------------------------------------------------------------- star systems
# Positions in metres-ish world units. The player spawns at `spawn` (station launch) or at the gate exit.
# Every system in the game: the hand-made ones below (CORE_SYSTEMS) plus all the rest of the 11 x 11 map, built by
# SystemBuilder from the map tables. sys["gates"] lists every gate; sys["gate"] is the first one.
static var SYSTEMS: Dictionary = SystemBuilder.all(CORE_SYSTEMS)
const CORE_SYSTEMS := {
	"solara": {
		"name": "Solara", "star": Color(1.0, 0.86, 0.6), "sky_tint": Color(0.10, 0.06, 0.16), "ambient": Color(0.42, 0.40, 0.55),
		"sun_dir": Vector3(-0.4, -0.35, -1.0),
		"station": {"id": "liberty_hub", "name": "Liberty Hub", "pos": Vector3(0, 0, -260), "kind": "station", "model": "wheel_station",
			"desc": "Unity trade and patrol hub. Repairs, outfitting and a ship dealer.", "color": Color(0.72, 0.78, 0.9)},
		"planet": {"id": "new_terra", "name": "New Terra", "pos": Vector3(1500, -260, -2500), "radius": 1000.0, "kind": "planet",
			"desc": "Temperate colony world. Orbital landing field at Port Meridian.", "palette": "terran"},
		"gate": {"id": "aquila_gate", "name": "Aquila Warp Gate", "pos": Vector3(-300, 40, -4200), "to": "vega"},
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
		"planet": {"id": "eden_prime", "name": "Eden Prime", "pos": Vector3(-1700, 320, -2300), "radius": 880.0, "kind": "planet",
			"desc": "Lush jungle world. Landing at the Verdant Terrace spaceport.", "palette": "jungle"},
		"gate": {"id": "solara_gate", "name": "Solara Warp Gate", "pos": Vector3(0, 0, 0), "to": "solara"},
		"asteroids": {"name": "Vega Ice Field", "center": Vector3(950, -40, -2650), "radius": 420.0, "count": 160, "ice": true},
		"nebula": {"name": "Azure Veil", "center": Vector3(-350, 0, -1450), "radius": 440.0, "color": Color(0.2, 0.55, 0.95)},
		"enemy": "corsair",
		"patrols": [Vector3(250, 0, -1700), Vector3(900, -20, -2300), Vector3(-450, 150, -800)],
		"traffic": [["frontier_exchange", "eden_prime"]],
	},
}
const SYSTEM_LINKS := [["solara", "vega"]]

# ---------------------------------------------------------------- people you meet (placeholder original characters)
# mood: friendly | neutral | enraged. Names/lines are stand-ins until the Homelancer bible assigns canon characters.
# Radio contacts. "face" = portrait set in assets/portraits/<face>_<expression>.png (normal, serious, angry, sad, smile);
# "voice" = mumble pitch (higher = lighter voice). A line may start with [expression] to pick the face for that line.
const CHARACTERS := {
	"vale": {"name": "Cmdr. Vale", "role": "Liberty Hub Control", "system": "solara", "color": Color(0.35, 0.8, 1.0),
		"face": "vale", "voice": 1.3, "female": true,
		"lines": {"friendly": ["[smile]Vale here. Keep your shields up and your credits spent.", "[normal]Liberty Hub is always open to you, pilot."]}},
	"oduya": {"name": "Port Master Oduya", "role": "New Terra Port", "system": "solara", "color": Color(0.45, 1.0, 0.6),
		"face": "oduya", "voice": 1.4, "female": true,
		"lines": {"friendly": ["[smile]Landing beacon's lit whenever you need it. Repairs are on the house.", "[normal]New Terra thanks you for keeping the lanes clear."]}},
	"rennick": {"name": "Capt. Rennick", "role": "Cargo hauler Bright Margin", "system": "solara", "color": Color(1.0, 0.8, 0.4),
		"face": "rennick", "voice": 0.85, "female": false,
		"lines": {"friendly": ["[serious]Rennick here. Appreciate the escort — raiders have been bold lately.", "[smile]If you hear of work on the Vega run, I'm hauling."]}},
	"voss": {"name": "Shade", "role": "Hoard's lieutenant · Raiders", "system": "solara", "color": Color(1.0, 0.3, 0.3),
		"face": "voss", "voice": 0.72, "female": false,
		"lines": {"enraged": ["[angry]You killed my wingmate. I'll be waiting in the belt, cadet.", "[smile]Every raider in Solara knows your ship now.", "[serious]Call me again and I'll trace the signal to your hull."]}},
	"amari": {"name": "Chief Amari", "role": "Frontier Exchange", "system": "vega", "color": Color(1.0, 0.72, 0.35),
		"face": "amari", "voice": 1.35, "female": true,
		"lines": {"friendly": ["[smile]Welcome to the frontier. Out here, we pay for what you bring back.", "[serious]Corsairs run the ice field. Watch your flank."]}},
	"kessler": {"name": "Hoard", "role": "Corsair warlord of Vega", "system": "vega", "color": Color(0.75, 0.4, 1.0),
		"face": "kessler", "voice": 0.62, "female": false,
		"lines": {"enraged": ["[angry]That was my crew, Unity dog. Vega will be your grave.", "[smile]Run back through your gate while you still can.", "[serious]Some secrets should never die. Neither should grudges. There's a price on your ship."]}},
}
# Enemy pilots who hail you (faces from the enemy dossiers). Each enemy ship gets one of its faction's pilots.
const PILOTS := {
	"raider": [
		{"name": "Scar Jackal", "unit": "R-11", "face": "jackal", "voice": 0.85, "female": true,
			"lines": ["[serious]Hunt. Dismantle. Leave nothing.", "[angry]Target acquired. Your hull will be scrap.", "[smile]Pursue. Isolate. Terminate. Repeat."]},
		{"name": "Ember Wraith", "unit": "A-21", "face": "wraith", "voice": 1.25, "female": true,
			"lines": ["[smile]Beauty is just another weapon.", "[angry]Silence is a kinder world. Let me show you.", "[serious]Turn around, pilot. Last warning."]},
	],
	"corsair": [
		{"name": "Iron Revenant", "unit": "X-12", "face": "revenant", "voice": 0.55, "female": false,
			"lines": ["[serious]Death remains the most efficient protocol.", "[angry]Those who resist become data.", "[smile]Steel remembers what you forget."]},
		{"name": "Frost Banshee", "unit": "W-09", "face": "banshee", "voice": 1.3, "female": true,
			"lines": ["[serious]Silence finds you before the cold does.", "[smile]Cold erases louder than bullets.", "[angry]You won't hear me coming."]},
	],
}
const ENEMY_LEADER := {"raider": "voss", "corsair": "kessler"}

# Generic enemy pilots: the rank and file who fly UNDER the named squad leaders above (they never replace them).
# Portraits AX-01..06 from the "enemy comms portraits" sheet, two states each: assets/enemy_pilots/<id>_normal.jpg and
# <id>_damaged.jpg (cracked mask). They live in the "enemies" content pack, not the core download.
# "hurt" = the line they say once their mask has cracked (from the reference sheet).
const GENERIC_PILOTS := [
	{"id": "ax01", "unit": "AX-01", "type": "Standard", "voice": 0.9, "female": false, "hurt": "...Still in the fight..."},
	{"id": "ax02", "unit": "AX-02", "type": "Recon", "voice": 1.1, "female": false, "hurt": "Target... acquired..."},
	{"id": "ax03", "unit": "AX-03", "type": "Desert", "voice": 0.8, "female": false, "hurt": "...Cover me..."},
	{"id": "ax04", "unit": "AX-04", "type": "Arctic", "voice": 1.2, "female": true, "hurt": "We're not done yet..."},
	{"id": "ax05", "unit": "AX-05", "type": "Jungle", "voice": 0.75, "female": false, "hurt": "...Hold the line..."},
	{"id": "ax06", "unit": "AX-06", "type": "Elite", "voice": 1.0, "female": true, "hurt": "You'll regret this..."},
]
const GENERIC_HURT := 0.5   # NORMAL above this share of total health, DAMAGED at or below (latched: never flips back)
# Short combat chatter by event. Named leaders keep their own personality lines (PILOTS / CHARACTERS).
const CHATTER := {
	"target_acquired": ["Target acquired.", "Contact. Engaging.", "Eyes on the target."],
	"taking_fire": ["Taking fire!", "I'm hit!", "He's on me!"],
	"shields_failing": ["Shields failing!", "Shields are down!"],
	"wing_damaged": ["Wing damaged!", "Lost a wing — still flying!"],
	"arm_damaged": ["Arm's gone!", "Lost an arm — still fighting!"],
	"regroup": ["Regroup on me!", "Form up — regroup!"],
	"retreat": ["I'm pulling out!", "Retreat — falling back!"],
	"missile_incoming": ["Missile incoming!", "Missile lock — break!"],
	"leader_down": ["Leader's down!", "We lost the leader!"],
	"reinforcements": ["Reinforcements inbound.", "More of us coming — hold on."],
	"enemy_transforming": ["He's transforming!", "Target's changing shape!"],
	"enemy_warp": ["He's spooling warp — stop him!", "Warp signature! Don't let him jump!"],
	"critical_damage": ["Critical damage!", "Hull critical — I can't hold!"],
}
