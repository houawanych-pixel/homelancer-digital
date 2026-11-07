class_name Data
extends RefCounted
## Static game data for Homelancer Digital v1.2. All names, ships and places are original Homelancer content.

# Beta version shown on the start screen and on the Hova Matrix landing page (which reads it from web_shell.html).
# Scheme (owner): the letter is the Chief job that shipped it: v1.2x, v1.2y, v1.2z, then v1.3a, v1.3b ...
# Change it in BOTH places for every job: here and the hl-version meta + title in web_shell.html (a test checks it).
# v1.8t: the background content packs, in the order they are fetched (PACK_PARALLEL at a time): what the game needs to
# play first (planet ground, the mech), the big ones (enemy pictures 17 MB, structures 56 MB) last.
const PACK_ORDER := ["sky", "worlds", "planets", "mechs", "cockpit", "structures", "voice_m1", "voice_m2", "voice_m3", "voice_m4", "voice_f1", "voice_f2", "voice_f3", "voice_f4", "voice_a1", "voice_a2", "voice_r1", "voice_mask", "lancer", "ranger", "hauler", "enemies"]
const PACK_PARALLEL := 2
const RING_PACKS := ["ring_gate", "ring_dock"]   # v1.9r (owner: missing dock rings): the jump gate ring and the dock arch, fetched on arrival in every system
# v1.8v (owner: fewer enemies, asteroids and moving cargo ships, to keep memory low): the lighter numbers below, plus
# ASTEROID_COUNT 34 -> 18, ASTEROID_PIECES_MAX 220 -> 120 and ROSTER_PATROL_SIZE 3 -> 2.
const PATROL_GROUPS := 2            # patrol wings out in a system at once (each system has 3 patrol points; the first ones are used)
const TRAFFIC_PER_RUN := 1          # moving cargo ships on each station <-> planet run (was 3: hauler, freighter, tanker)
# v1.8w (owner): what the one who pays you says when a job is done ({pay} = the credits)
const CONGRATS := [
	"[smile]Job done, pilot. {pay} credits are in your account. Good flying.",
	"[smile]That's the one. Nice work out there. {pay} credits sent.",
	"[smile]Clean work. {pay} credits, as promised. Come back when you want more.",
]
# v1.8z (owner): cloned voices. Every fixed radio line is pre-recorded in one of 12 voices cloned from the owner's
# talking clips (art/voices; who borrows which voice: art/voices/voice_map.csv), one small content pack per voice.
# v1.8x (owner): every bounty is a capture (BOUNTY_ALIVE_RANK 4 -> 1: destroy the ship, TRACTOR the pilot, hand them in);
# the threats jobs send ONE rank: PATROL = all level-1 soldiers, ELITE = all level-5 soldiers.
# v1.9a (owner): the escort job on a planet: a freighter flies from one base to another (sector to sector), the rival
# hits it twice on the way; it waits for you when you are not with it. GO TO / the waypoint follow it (no warp down there).
const LAND_ESCORT_WAIT := 1300.0    # m: farther than this from you, the freighter waits
const LAND_ESCORT_ALT := 150.0      # m over the ground it flies
const VERSION := "v12.45"
## v11.40/v11.41 (owner: "every version saved as a new version per station set, and a set can be attached to a station"):
## room SETS per faction. Set "1" is the faction's first rooms (assets/rooms/<faction>/<room>.*); a newer set lists only the
## rooms it changes (room -> file name in the same folder, the old files stay). STATION_ROOM_SET says which set each
## station uses (by system id); a station not listed uses set "1".
const ROOM_SETS := {
	"orion": {"2": {"shipyard": "shipyard4", "weapons": "weapons2", "private_quarters": "private_quarters2", "mech_dealer": "mech_dealer2"}, "3": {"shipyard": "shipyard2"}, "4": {"shipyard": "shipyard3"}},   # set 3: hangar A; set 4: hangar B   # set 2: the owner's Nov 1 Fleet Command sheets (more rooms join as they are animated)
}
const STATION_ROOM_SET := {"dreadholm": "2", "korrath": "3", "battlespire": "4"}   # Fleet Command (Orion capital); Korrath Garrison
## v11.54 (owner, Dreadholm update): every star system has four ROLES. HUB = the home faction's own station (the system's
## main station, its full room set); ALLY = an allied faction's station (the Galaxy Bible's allies; small ally stations
## share ONE art set, told apart by tint only); RIVAL = the rival faction's station, often HIDDEN (in the system's main
## nebula, off the map until you find it); SPY = a covert contact (a person at the hub) or a small hidden outpost.
## A system listed here drops its catalog placeholder stations. Dreadholm is the first one filled in.
const SYSTEM_ROLES := {
	"dreadholm": {
		"hub": {"name": "Fleet Command"},
		"ally": {"name": "Covenant Embassy", "faction": "Covenant", "model": "HL_Station_Covenant_Trade_retopo", "tint": Color(0.82, 0.74, 1.0),
			"desc": "Covenant embassy station: Orion's allies keep an envoy, a trader and a medic here."},
		"rival": {"name": "Unity Listening Post", "faction": "Unity", "model": "HL_Station_Unity_Military_retopo", "hidden": true, "in_nebula": true,
			"desc": "A Unity listening post hidden in the Dreadholm Veil, spying on Fleet Command."},
		"spy": {"type": "contact", "at": "hub", "faction": "Unity", "name": "Veil Informant",
			"desc": "A covert contact at Fleet Command who trades word on the hidden Unity post."},
	},
	"solara": {   # v11.91 (owner: the starting system, souped up): Unity's hub, its Liberator friends, the Imperium watching
		"hub": {"name": "Liberty Hub"},
		"ally": {"name": "Liberator Freeport", "faction": "Liberator", "model": "HL_Station_Liberator_Military_retopo", "tint": Color(0.75, 0.95, 0.9),
			"desc": "Liberator freeport: Unity's allies run a fuel depot, a mech shop and a clinic for pilots passing through."},
		"rival": {"name": "Imperium Watch Post", "faction": "Imperium", "model": "HL_Station_Imperium_Military_retopo", "hidden": true, "in_nebula": true,
			"desc": "An Imperium watch post hidden in the Violet Reach: it sends the raids on Solara's lanes."},
		"spy": {"type": "contact", "at": "hub", "faction": "Imperium", "name": "Dockside Whisper",
			"desc": "A dock worker at Liberty Hub who sells word on the hidden Imperium post."},
	},
}
## v11.65 (owner, Dreadholm map talk-through, Nov 3): a system laid out by hand, in MAP SQUARES [column, row] as the map
## reads them (A = 1 ... J = 10 across, 1 ... 10 down; .5 = the middle of a square). The star sits right by the lava world
## (that's why it burns red hot), the Covenant embassy and Vassal are moved, the jump gates sit further out, and the trade
## lanes are a network: spokes from Fleet Command plus an OUTER RING, meeting at CHOKE POINTS (one lane in, a T out to two
## places). A rock field and a storm cloud sit on the straight lines, so the lanes go round them.
const SYSTEM_LAYOUT := {
	"solara": {   # v11.91 (owner: the starting system needs souping up): a full lane network, an ally, a hidden rival, a second world
		"hub": [6.0, 6.0], "planet": [7.6, 3.4], "sun": [4.0, 4.0], "belt": [4.4, 5.6], "nebula": [2.8, 2.6],
		"add_planets": [{"name": "Haven", "palette": "ice", "at": [3.0, 7.6], "radius": 650.0,
			"desc": "Ice world. Mining camps and a quiet harbour for new pilots. Fly into the atmosphere to go down."}],
		"stations": {"Liberator Freeport": [8.6, 7.2], "Imperium Watch Post": [2.8, 2.6]},
		"add_stations": [{"name": "Haven Station", "faction": "Unity", "model": "HL_Station_Unity_Trade_retopo", "at": [2.4, 8.2],
			"desc": "Unity's west corner station by Haven: ice haulers, a repair dock and a quiet bar for new pilots."}],
		"gates": {"vega": [6.2, 1.9], "veranthos": [5.6, 9.0]},
		"clouds": [
			{"name": "Outer Drift", "at": [10.0, 5.0], "radius": 26000.0, "weather": "rocks", "color": Color(0.62, 0.58, 0.55)},
			{"name": "Ash Wisps", "at": [1.0, 8.4], "radius": 24000.0, "weather": "storm", "color": Color(0.5, 0.45, 0.75)},
			{"name": "Liberty Haze", "at": [7.4, 8.6], "radius": 22000.0, "weather": "storm", "color": Color(0.35, 0.6, 0.95)},
			{"name": "North Veil", "at": [4.9, 2.4], "radius": 30000.0, "weather": "storm", "color": Color(0.6, 0.35, 0.9)},   # v11.94: north of mid
			{"name": "Ion Shoals", "at": [9.0, 2.0], "radius": 22000.0, "weather": "rocks", "color": Color(0.55, 0.6, 0.7)},
			{"name": "Lantern Cloud", "at": [4.6, 6.9], "radius": 20000.0, "weather": "storm", "color": Color(0.95, 0.7, 0.4)},
			{"name": "Crossing Rocks", "at": [4.9, 8.6], "radius": 16000.0, "weather": "rocks", "color": Color(0.6, 0.52, 0.45)},
			{"name": "Frost Veil", "at": [2.6, 4.5], "radius": 70000.0, "weather": "storm", "color": Color(0.45, 0.7, 0.95), "disturbance": true},   # v12.6 (owner: "4B is good, put a big cloud there"): the disturbance hides here, well away from Haven Station
		],
		"junctions": {"North Choke Point": [6.9, 4.7], "Liberty Crossing": [6.6, 7.7]},
		"lanes": [
			["hub", "North Choke Point"], ["North Choke Point", "planet"], ["North Choke Point", "Liberator Freeport"],
			["planet", "gate:vega"], ["hub", "Liberty Crossing"], ["Liberty Crossing", "gate:veranthos"],
			["Liberty Crossing", "Liberator Freeport"], ["Liberty Crossing", "Haven Station"], ["Haven Station", "gate:veranthos"],
		],
	},
	"dreadholm": {
		"sun": [5.5, 4.5],
		"planets": {"Vassal": [2.5, 6.5]},
		"stations": {"Covenant Embassy": [4.5, 8.5]},
		"gates": {"ogden": [3.5, 5.5], "heart": [6.5, 2.8], "foggiest": [9.0, 5.5], "korrath": [3.3, 9.0], "battlespire": [7.8, 9.0]},   # v11.69 (owner's map marks): in off the edge squares
		"clouds": [
			{"name": "Cinder Shards", "at": [7.0, 4.6], "radius": 26000.0, "weather": "rocks", "color": Color(0.78, 0.42, 0.26)},
			{"name": "Ember Veil", "at": [5.0, 4.6], "radius": 30000.0, "weather": "storm", "color": Color(0.85, 0.3, 0.22)},
		],
		"junctions": {"South Choke Point": [6.8, 7.5], "East Choke Point": [7.6, 6.9], "Northeast Choke Point": [8.0, 3.6]},
		"lanes": [   # v11.69: lanes may cross clouds, never asteroids or the star; none runs through a station
			["hub", "planet"], ["hub", "South Choke Point"], ["South Choke Point", "Covenant Embassy"], ["South Choke Point", "gate:battlespire"],
			["hub", "East Choke Point"], ["East Choke Point", "gate:battlespire"], ["East Choke Point", "Northeast Choke Point"],
			["Northeast Choke Point", "gate:foggiest"], ["Northeast Choke Point", "planet"], ["Northeast Choke Point", "gate:heart"],
			["planet", "gate:heart"], ["hub", "gate:ogden"],
			["gate:korrath", "gate:ogden"], ["gate:korrath", "Covenant Embassy"], ["Covenant Embassy", "gate:battlespire"],
			["gate:battlespire", "gate:foggiest"], ["gate:heart", "gate:ogden"],
		],
	},
}
## v11.57 (owner's Orion planet biomes, Planet_biome art on Drive; originals in art/reference/planet_cards): each main
## planet's biome (its palette in flight) and its map card picture. Vortegan is a desert now (v3), not a gas giant.
const PLANET_BIOMES := {"dreadholm": "lava", "korrath": "dead", "battlespire": "desert", "ironvast": "desert", "omicron_major": "terran", "vortegan": "desert"}
const PLANET_CARDS := {"dreadholm": "res://assets/planet_cards/dreadholm.jpg", "korrath": "res://assets/planet_cards/korrath.jpg",
	"battlespire": "res://assets/planet_cards/battlespire.jpg", "ironvast": "res://assets/planet_cards/ironvast.jpg",
	"omicron_major": "res://assets/planet_cards/omicron_major.jpg", "vortegan": "res://assets/planet_cards/vortegan.jpg"}
## v11.57 (owner): a planet's own hub: its 10 rooms (assets/rooms/<faction>/planet_<system>_<room>.jpg|ogv, e.g.
## planet_dreadholm_main_hub) under its own sky; any room missing falls back to the system's main station hub room.
const PLANET_HUB_ROOMS := {"dreadholm": ["main_hub", "command", "mech_dealer", "medical_bay", "mission_center", "pilots_lounge", "private_quarters", "shipyard", "supplies", "weapons"]}
const PLANET_HUB_SKY := {"dreadholm": Color(1.0, 0.62, 0.45)}   # lava-sky light on the planet's rooms
## v11.57 (owner): Dreadholm natives: magma-skinned people (cracked obsidian skin, glowing magma seams), Orion explorers
## and pioneers, not enemies. NPCs in the Dreadholm hubs (planet and Fleet Command); their pictures come later
## (assets/crew/orion/<file>_face.png etc., like the other crew). Look prompt for the art in docs/rooms/ANIMATE_PROMPT.md.
const MAGMA_NATIVES := {"faction": "Orion", "where": ["dreadholm"], "look": "magma-skinned people: cracked obsidian skin with glowing magma seams; Orion explorers and pioneers in white-and-forest-green Exploration Corps gear; Epic Seven anime splash-art style with sci-fi MMO detail"}
const ALLY_ROOMS := ["main_hub", "supplies", "medical_bay", "mission_center", "weapons"]    # the 5 pages of an ally station (one shared art set)
const RIVAL_ROOMS := ["main_hub", "supplies", "medical_bay", "mission_center", "weapons"]   # the 5 pages of a rival station
const HIDDEN_FIND_RANGE := 2500.0   # m: fly this close to a hidden station (or scan it) and it is charted for good
const STATION_SIZE := 2.0   # v11.21 (owner: "double the size of all space stations")
const ESCORT_FREIGHTER_LEN := 360.0   # v11.89 (owner): cargo ships 2x
#  # v11.16 (owner): the escort / cargo-run freighter is a big ship (m long), not fighter-sized (was 16)
# v11.63 (owner's freighter block, Nov 3): cargo freighters fly the trade lanes. One object with three zones: the FRONT
# HEAD (cockpit, the size of the Cadet on every freighter), the CARGO BODY, the REAR BOOSTER. Type 1 is the normal size;
# type 2 has the same head and a much bigger body (and a booster to match). Hit the booster until it breaks and the
# freighter crawls at FREIGHTER_CRAWL of its speed; it only blows up when its whole hull is gone. No escorts.
# Stand-in models: the side views cut from the owner's 8-faction freight sheet (Tripo), one per faction.
const CARGO_FACTIONS := ["Elyza", "Unity", "Solarion", "Imperium", "Covenant", "Orion", "Savagers", "Liberator"]   # sheet row order
const CARGO_SHIPS := {"Elyza": {"t1": "cargo_elyza_t1", "t2": "cargo_elyza_t2"}, "Unity": {"t1": "cargo_unity_t1", "t2": "cargo_unity_t2"}, "Solarion": {"t1": "cargo_solarion_t1", "t2": "cargo_solarion_t2"}, "Imperium": {"t1": "cargo_imperium_t1", "t2": "cargo_imperium_t2"}, "Covenant": {"t1": "cargo_covenant_t1", "t2": "cargo_covenant_t2"}, "Orion": {"t1": "cargo_orion_t1", "t2": "cargo_orion_t2"}, "Savagers": {"t1": "cargo_savagers_t1", "t2": "cargo_savagers_t2"}, "Liberator": {"t1": "cargo_liberator_t1", "t2": "cargo_liberator_t2"}}
const FREIGHTER_HEAD_LEN := 18.0   # v11.89: 2x
#                # m: the head, the Cadet's length, the same on both types
const FREIGHTER_LEN := [64.0, 92.2]   # v11.89 (owner): cargo ships 2x
#            # m nose to tail: type 1, type 2 (the GLBs are built to these)
const FREIGHTER_ZONES := [{"head": 0.28, "booster": 0.17}, {"head": 0.195, "booster": 0.118}]   # share of the length from the nose / from the tail
const FREIGHTER_HIT_R := [9.0, 12.0]   # v11.89: 2x
#            # m: the hull's half-thickness (shots closer than this to the spine hit)
const FREIGHTER_HP := [900.0, 1600.0]           # whole hull
const FREIGHTER_BOOSTER_SHARE := 0.25           # the booster breaks after this share of the hull, taken on the booster
const FREIGHTER_SPEED := 55.0                   # m/s along the lane
const FREIGHTER_CRAWL := 0.1                    # booster broken: this share of the speed
const DRIFT_BOOST_RATE := 1.6               # v11.64: THRUST in a warp-speed drift swings the momentum to the nose this fast (same speed)
const FREIGHTERS_PER_SYSTEM := 6   # v11.89 (owner): the system's own, its ally's and Unity's (universal)
#               # one of each type, on the trade lanes
const FREIGHTER_RESPAWN := 90.0                 # s after one is destroyed, another starts on the lanes

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
	{"id": "special", "name": "Special lock-on (hold on target, release to fire)", "key": "F", "rebind": true, "extra": true},   # v1.5o
	{"id": "map_orient", "name": "Map / radar: north-up or heading-up", "key": "N", "rebind": true, "extra": true},
	{"id": "map_tilt", "name": "Map / radar: angled or overhead", "key": "B", "rebind": true, "extra": true},
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
# v1.7y (owner): saving progress. One save file on the device (the browser keeps it); written when you dock, when a job
# pays, after a jump and every SAVE_EVERY seconds in flight; START picks up where you left off. Settings > START OVER
# erases it. The keys are the GameState names and are never renamed.
const SAVE_PATH := "user://homelancer_save.txt"
const SAVE_SLOT_PATH := "user://homelancer_save_%d.txt"   # v1.9j (owner): one file per pilot
const SAVE_SLOTS := 3
const PILOT_NAME_MAX := 16
const SAVE_EVERY := 30.0
const SAVE_DELTAS_MAX := 2000000   # characters: crater notes past this size are left out of the save (the ground regrows)
# v1.8e (owner: smooth on the phone): the 3D world is drawn at most RENDER_PIXELS_MAX pixels and stretched to the
# screen (phones have very sharp screens: drawing every pixel is the biggest cost); the HUD stays sharp. On touch
# screens the 3D edge smoothing (MSAA) is off once the picture is scaled.
const RENDER_PIXELS_MAX := 1000000.0   # about 1333 x 750
const RENDER_SCALE_MIN := 0.5
# v1.7z (owner, concept art): the MECH first-person view. VIEW in mech form looks out of the mech's head: its own arms
# hold a rifle in front of you and sway with the sticks; ZOOM looks down the rifle's scope.
const FPV_EYE := Vector3(0, 3.4, -0.4)      # the mech's eye, in its own axes (m)
const FPV_FOV := 72.0
const FPV_ZOOM_FOV := 26.0                  # looking down the scope
const FPV_SWAY := Vector2(0.55, 0.4)        # how far the arms lag behind a turn (m at full stick)
const FPV_BOB := 0.12                       # m the arms bob while walking
const FPV_KICK := 0.35                      # m the rifle kicks back on each shot
const FPV_ARM_DIRS := {                      # where the bones point, in the model's own axes (+Z = forward)
	"RightUpperArm": Vector3(0.2, -0.42, 0.88), "RightLowerArm": Vector3(0.28, 0.12, 0.95),
	"LeftUpperArm": Vector3(-0.3, -0.4, 0.86), "LeftLowerArm": Vector3(-0.9, 0.12, 0.45)}
const FPV_GUN_SCALE := 0.6                  # the rifle's size in the hands
# v1.8h (owner): his futuristic gun model in the mech's hands (mechs pack); the code-made rifle is the stand-in until it loads
const FPV_GUN_MODEL := "res://assets/mechs/mech_gun_futuristic.glb"
const FPV_GUN_LENGTH := 3.6                 # m long in the hands (muzzle at -Z)
const FPV_GUN_YAW := 180.0                  # the owner's gun model points its barrel along +Z: turned to fire along -Z
const FPV_GUN_GRIP := Vector3(0.05, 0.3, -0.9)   # where the gun's middle sits from the right hand (m)
const HAND_GUN_LENGTH := 4.2                # m: the same gun in the mech's right hand, seen from outside (chase view)
const HAND_GUN_LIFT := 0.35                 # m the gun sits above the right hand (the hand under the grip)
const HAND_GUN_ARM_DIRS := {                 # the two-handed hold, seen from outside (model's own axes, +Z = forward)
	"RightUpperArm": Vector3(0.15, -0.55, 0.82), "RightLowerArm": Vector3(0.3, 0.05, 0.95),
	"LeftUpperArm": Vector3(-0.25, -0.5, 0.83), "LeftLowerArm": Vector3(-0.75, 0.1, 0.65)}
const FPV_GUN_COLORS := {"body": Color(0.86, 0.87, 0.88), "dark": Color(0.12, 0.13, 0.15), "glow": Color(0.3, 0.85, 1.0)}

# ---------------------------------------------------------------- Job K (v1.4g): jump-gate docking + warp tunnel
# Every Job K number lives in this one block. The jump destination logic is unchanged (gate "to" in the galaxy data).
const JUMP_TUNNEL_BUILD := 1.2        # s: the tunnel builds up (streaks + shake + blur) as the ship pushes through the gate
const JUMP_TUNNEL_HOLD_MIN := 1.2     # s: shortest time at full tunnel before the swap; the real load time adds to it
const JUMP_TUNNEL_CLEAR := 0.8        # s: the tunnel snaps clear once the next system is ready
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

# ---------------------------------------------------------------- Job E2 (v1.4i): placeholder planets and stations
# Every Job E2 number lives in this one block. (The new ships' stats are in SHIPS below, like every other ship.)
# Each system's first planet and station are the dockable ones; the rest of its catalog contents are placeholders:
# visible, solid, targetable, on the system map, reachable by GO TO. No docking or landing on them yet.
const PH_PLANET_DIST := 4300.0        # the first placeholder planet sits this far from the system centre ...
const PH_PLANET_STEP := 1900.0         # ... and each further one this much farther out
const PH_PLANET_JITTER := 600.0       # random extra distance (0 .. this)
const PH_PLANET_ANGLE := 1.05         # radians between one placeholder planet and the next, round the centre
const PH_PLANET_HEIGHT := 700.0       # placeholder planets sit up to this far above / below the system plane
const PH_PLANET_RADIUS := [260.0, 430.0]      # size range of a rocky placeholder planet
const PH_GIANT_RADIUS := [520.0, 680.0]       # size range of a gas giant
const PH_STATION_DIST := 1100.0       # the first placeholder station sits this far from the system centre ...
const PH_STATION_STEP := 380.0        # ... and each further one this much farther out
const PH_STATION_JITTER := 200.0      # random extra distance (0 .. this)
const PH_STATION_HEIGHT := 160.0      # placeholder stations sit up to this far above / below the system plane
const PH_STATION_MODEL_K := 0.6      # v2.2: the station model standing in for a station with no model of its own (~90 m)
const PH_STATION_RADIUS := 42.0       # collision radius of a placeholder station
const PH_GOTO_STANDOFF := 160.0       # GO TO stops this far off a placeholder's surface
const PH_BUILD_DELAY := 1.2           # s after a system loads before its placeholders are built (keeps arrival smooth)
const PH_CLEARANCE := 900.0           # v1.4m: free space kept between one planet and the next (was 260)
const PH_STATION_CLEARANCE := 260.0   # free space kept round a placeholder station (and between a planet and anything that is not a planet)
const PH_PLACE_TRIES := 30            # positions tried to find a clear spot
const PH_SPHERE_SEGMENTS := 40        # roundness of a placeholder planet (the main planet uses 72)

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

# ---------------------------------------------------------------- Job M (v1.4j): lead box, missile locks, dodging
const LEAD_BOX_SIZE := 14.0           # half-width (px) of the aim box drawn ahead of the targeted enemy
const LEAD_BOX_RANGE := 6.0           # the box shows inside this x your gun range
const LEAD_BOX_ON := 16.0             # px: reticle this close to the box centre = "on target" (box turns green)
const LOCK_CONE_DEG := 15.0           # keep the target inside this cone to build missile locks
const LOCK_RANGE := 800.0
const LOCK_SPREAD_DEG := 32.0         # v1.9r: the shared locks also go to other hostiles inside this wider cone ...
const LOCK_SPREAD_MAX := 6            # ... at most this many hostiles at once (the target included)
const LIGHT_LOCK_COLOR := Color(1.0, 0.25, 0.22)   # the light missile's lock counter: red, on top of the box
const HEAVY_LOCK_COLOR := Color(0.72, 0.35, 1.0)   # the heavy missile's (slower) lock counter: purple, under the box
const LOCK_STEP := 0.5                # seconds per lock
const HEAVY_LOCKS := 4                # v11.12 (owner: "fire more if lock on more"): up to four super-missile locks (+ heavy pods), one missile per lock
const HEAVY_MISSILE_HULL_FRAC := 0.85 # heavy does at least this share of the target's hull
# the rack on the LIGHT slot. "triple" comes with every ship; "swarm" is bought at Equipment.
const MISSILE_RACKS := {
	"triple": {"name": "Triple Rack", "price": 0, "locks": 3, "damage": 1.0, "desc": "Locks three missiles on one target."},
	"swarm": {"name": "Six Rack", "price": 1800, "locks": 6, "damage": 0.6, "desc": "Locks six lighter missiles on one target."},   # v1.4l: six locks; every pilot starts with it fitted
}
const RACK_ORDER := ["triple", "swarm"]
const VOLLEY_GAP := 0.12              # seconds between missiles of one volley
const VOLLEY_SPREAD := 26.0           # sideways launch speed so a volley fans out
const MISSILE_SPEED := 190.0
const MISSILE_TURN := 2.6             # how hard a missile steers (higher = harder to shake)
const DODGE_RANGE := 140.0            # v1.8b (owner: "missiles track you too, but timing can beat them"): a missile can only be shaken inside this distance; boost too early and it just follows you (SUPERSEDES 250)
const DODGE_SIDE_FRAC := 1.15         # ...by moving sideways faster than this x your normal top speed (needs boost)
const ENEMY_DODGE_CHANCE := 0.3       # chance an enemy tries a side-boost when your missile closes in
const ENEMY_DODGE_TIME := 0.7
const ENEMY_DODGE_BOOST := 2.0        # x its normal speed, sideways
const ENEMY_MISSILE_EVERY := [12.0, 20.0]   # seconds between missiles from one enemy (types with "missiles": true)
const ENEMY_MISSILE_RANGE := 600.0
const ENEMY_MISSILE_DAMAGE := 22.0
const ENEMY_MISSILE_SPEED := 125.0
const ENEMY_MISSILE_TURN := 1.8
const ENEMY_MISSILE_LIFE := 8.0
const ENEMY_MISSILE_HIT := 7.0        # hit radius

# ---------------------------------------------------------------- Job N (v1.4k): signature attacks
# A unit whose ENEMIES entry has "signature": "<id>" fires this instead of the plain missile. Dodging works the same.
# Lockon (Cybermorph, machines only): hex tubes fire charcoal darts with crimson optic slits; a razor-red needle
# trail with dotted hex sparks that kinks once when the lock hardens; impact punches, then blooms a cyan-white core
# and a red hex-shard ring, and leaves a pulsing lock-brand scorch. Machine debris only.
const SIGNATURES := {
	"lockon": {"name": "Lock-Brand Darts", "owner": "Lockon", "faction": "Cybermorph",
		"launch": "prow_split",          # the prow splits along a hard seam: needs Lockon's model (not made yet)
		"tubes": 6, "volley": 3,         # hexagonal tubes on the model; darts per attack
		"damage": 16.0, "speed": 150.0, "turn": 2.2, "life": 8.0, "fan": 22.0,
		"dart": Color(0.13, 0.13, 0.15), "slit": Color(1.0, 0.08, 0.12), "dart_size": Vector3(0.5, 0.5, 2.6),
		"trail": Color(1.0, 0.1, 0.14), "trail_size": 1.5, "trail_life": 0.35,
		"hex_every": 0.09, "hex_size": 0.7, "hex_life": 0.45,       # the dotted hex sparks along the trail
		"kink": 16.0,                    # sideways jolt (m/s), once, when the lock hardens (inside DODGE_RANGE)
		"punch_size": 3.5, "punch_delay": 0.08,                     # punch first...
		"bloom": Color(0.78, 1.0, 1.0), "bloom_size": 5.0, "bloom_life": 0.5,   # ...then the cyan-white core
		"ring": Color(1.0, 0.1, 0.14), "ring_size": 1.3, "ring_grow": 2.2, "ring_life": 0.6, "shards": 6, "shard_speed": 14.0,
		"brand_size": 0.9, "brand_life": 4.0, "brand_pulse": 3.0,    # the lock-brand scorch left on the hull
		"debris": Color(0.42, 0.42, 0.46), "debris_count": 5,
		"hull_reach": 3.5},              # the effect is drawn this close to the ship's centre, so it sits on the hull,
}

# ---------------------------------------------------------------- Job O (v1.4l)
# missile trails: a flat white ribbon behind every missile, bright at the missile, wider and fainter toward the end
const TRAIL_LIFE := 2.2               # seconds a piece of trail lasts
const TRAIL_STEP := 0.04              # seconds between trail points
const TRAIL_WIDTH0 := 0.55             # ribbon half-width at the missile (m)...
const TRAIL_WIDTH1 := 5.0             # ...and at the fading end
const TRAIL_COLOR := Color(1.0, 1.0, 1.0)
# missiles weave on the way in (the swing dies away close to the target so they still hit)
const WEAVE_AMP := 30.0               # sideways swing (m/s)
const WEAVE_HZ := [0.9, 1.8]          # each missile picks its own rhythm in this range
const WEAVE_FADE := 120.0             # no weave inside this distance of the target
# explosions: [flash size, fireballs, debris bits, later pops, seconds between pops]
const BLAST_WING := [15.0, 9, 8, 2, 0.16]
const BLAST_DEATH := [44.0, 20, 18, 6, 0.2]
const BLAST_ENEMY := [52.0, 18, 14, 5, 0.15]   # v6.7 (owner: massive explosions, like Freelancer): was [24, 10, 8, 2, 0.14]
const BLAST_SIZE_PER_RADIUS := 0.12            # bigger ships blow up bigger: x (1 + this x (radius - 7))
const BLAST_SCREEN_FLASH := 0.55               # a white flash on screen when a ship goes up close by (0..1)
const BLAST_FLASH_RANGE := 600.0
# trade lanes: rings in a row between two places in one system. Dock a ring and the ship is carried down the chain.
const LANE_RING_GAP := 7000.0         # metres between rings (v9.0: systems fill their tile, lanes run 50-200 km)
const LANE_MAX_RINGS := 24
const LANE_MIN_LEN := 1400.0          # shorter runs get no lane
const LANE_RING_RADIUS := 68.0   # v11.89 (owner): lanes 2x (was 34)
const LANE_RING_TUBE := 0.2      # v11.99: how thick the solid ring frame is (share of the ring radius)
const LANE_STACK := 220.0   # v11.89: 2x with the rings
#            # the two directions sit this far apart, one ring above the other
const LANE_PLANET_STANDOFF := 4400.0   # v11.89: 2x
#  # v11.73 (owner: lanes too close to the planet): past the outer air, this much further out
const LANE_STANDOFF := 900.0   # v11.89 (owner: room to see the lane when you come out): was 330
#         # the end rings sit this far from the station / planet surface / gate
const LANE_STATION_EXTRA := 1600.0   # v11.89: was 700
#    # v11.43 (owner): the station end ring sits this much further out again (big spiky stations)
const LANE_DOCK_RANGE := 480.0   # v11.89: 2x
#       # the LANE prompt shows inside this distance of a ring
const LANE_SPEED := 10000.0           # cruise in the lane (m/s) (v11.2 owner: half; was 20000) (v9.0 owner, Freelancer-size systems: any lane ride ~10-30 s; was 650)
const LANE_RAMP := 2.5                # seconds to reach it
const LANE_SLOW_DIST := 26000.0       # start slowing this far from the last ring (v9.0: was 700 at 650 m/s)
const LANE_EXIT_SPEED := 50.0
const LANE_TINT := Color(0.35, 0.85, 1.0)
const LANE_TUNNEL_LEN := 640.0        # the energy tunnel that rides on the ship (v1.4u: was 240; long enough to pass behind the camera)
const LANE_MIN_SPREAD := 30.0         # v11.10 (owner): degrees two lanes leaving one place must be apart; closer = chain from the nearer place
const LANE_RING_STRETCH := 220.0   # v11.89: 2x
#     # v11.10 (owner): each light ring is a soft band this long along the lane
const LANE_RING_GLOW := 0.45          # v11.10: how bright the band is at its middle (see-through)
const LANE_LIGHT_RINGS := 7           # v11.7 (owner): rings of light rushing past in a lane
const LANE_RING_PACE := [0.8, 4.0]     # v11.7: rings passing per second, slow -> full lane speed
const LANE_TUNNEL_RADIUS := 92.0   # v11.89: 2x
#      # v1.4u: was 15; wide enough that the chase camera sits inside it
const LANE_SPLASH := 0.5              # seconds of ring glow as you pass
# planet type -> surface biome for the one-tile surfaces on every planet (scripts/surface.gd)
const PLANET_BIOME := {"terran": "forest", "jungle": "jungle", "ocean": "ocean", "ice": "ice", "desert": "desert", "lava": "volcanic",
	"dead": "barren", "gas": "clouds", "city": "city", "crystal": "crystal", "toxic": "toxic", "machine": "machine"}

# ---------------------------------------------------------------- Job P (v1.4m)
const TEXT_BUMP := 2                  # HUD and room text below TEXT_BUMP_BELOW px is drawn this much bigger
const TEXT_BUMP_BELOW := 17
const TEXT_MIN := 13                  # nothing on the HUD is smaller than this
# v1.7p (owner: "better readability on phone all around, bigger text"): every size in the game is scaled by this
# (the HUD, maps, hub, settings, title), and nothing drawn is under TEXT_FLOOR px.
const TEXT_SCALE := 1.25
const TEXT_FLOOR := 15
static func ts(size: int) -> int:
	return maxi(TEXT_FLOOR, int(round(size * TEXT_SCALE)))

# v1.7r (owner): the tutorial. Tap CALL with nothing targeted and the guide teaches the next lesson.
# The guide is Kim, the owner's tech officer ("tutor" in CHARACTERS; faces tutor_normal / smile / serious / sad).
# Each lesson can have an acted clip (owner's videos, numbered 1-10): assets/tutor/tutor_<n>.ogv, its own pack
# "tutor_<n>". With the clip ready it plays in her comms portrait with its own voice; without it the line is spoken.
const TUTOR_ID := "tutor"
const TUTOR_HINT := "Need help? Tap LOG, pick TARGET / CONTROL, then CALL for a lesson."
const TUTOR_CLIPS := 10
const TUTOR_VIDEO := false   # v1.8a (owner: the clips stuttered on the phone): Kim talks with pictures and text, not video
# Each lesson: id, the line (what she says in the clip), "when" (a situation that moves it to the front:
# "hostiles", "planet", or ""; not "dock": you start next to a station), and "video" (the clip number). The intro always comes first.
const TUTORIAL := [
	{"id": "intro", "when": "", "video": 1, "line": "[smile]Oh! Hey, pilot. I'm Kim, your tech officer. Need help? Just tap CALL."},
	{"id": "fly", "when": "", "video": 2, "line": "[smile]Hey, it's okay, I gotcha. Left stick flies, right stick aims."},
	{"id": "fire", "when": "hostiles", "video": 3, "line": "[smile]Ooh, want to shoot something? Tap FIRE once, and it keeps going."},
	{"id": "missile", "when": "hostiles", "video": 4, "line": "[serious]Okay, focus. Hold the missile button until it locks, then let go."},
	{"id": "shield", "when": "hostiles", "video": 5, "line": "[sad]Ouch, you're taking hits! Tap SHIELD, then REPAIR. You'll be fine."},
	{"id": "map", "when": "", "video": 6, "line": "[smile]Hmm, lost? Open the MAP, tap GO TO, and follow the gold line."},
	{"id": "dock", "when": "", "video": 7, "line": "[smile]Ah, yeah. Need credits? Dock at a station and grab a job."},
	{"id": "planet", "when": "planet", "video": 8, "line": "[normal]You know what? On planets, shoot the ground to dig. Caves hide down there."},
	{"id": "mech", "when": "", "video": 9, "line": "[smile]Oh, this is my favourite! Tap MECH and your ship walks!"},
	{"id": "warp", "when": "", "video": 10, "line": "[smile]Warp gates jump systems. That's it, pilot, you're ready. Call me anytime."},
]
static func tutor_clip(n: int) -> String: return "res://assets/tutor/tutor_%d.ogv" % n
# ---------------------------------------------------------------- Job AR (v1.5o): the special lock-on super move (docs/SPECIAL_MOVE.md)
const SPECIAL_ARM_AT := [0.5, 0.25]     # hull shares at which the special arms (half, then critical); once each until repaired
const SPECIAL_RESET_AT := 0.75          # repaired above this, both are ready to earn again
const SPECIAL_LOCK_TIME := 2.4          # (before v1.9b) the old hold-to-lock time; the charge now builds missile locks (LOCK_STEP each)
const SPECIAL_MIN_POWER := 0.35         # v1.9c: a quick tap's beam hits the hull at this share of a full charge (shields still go)
const SPECIAL_TURN_TIME := 0.6          # v1.9c: on release the ship turns to face the target within this many seconds ...
const SPECIAL_TURN_RATE := 9.0          # ... swinging round this fast (share of the angle per second) ...
const SPECIAL_FACE_DEG := 3.0           # ... until it points within this of the target, then fires
const SPECIAL_CONE_DEG := 25.0          # keep the target inside this cone ...
const SPECIAL_RANGE := 1300.0  # v1.9b: press SPECIAL with a hostile this close           # ... and this range while charging, or the lock breaks
const SPECIAL_BREAK_CHANCE := 0.55      # chance per second the target jinks to break the lock
const SPECIAL_ROLL_TIME := 0.8          # one full barrel roll while charging takes this long
const SPECIAL_CUTIN_TIME := 2.2         # the pilot cut-in
const SPECIAL_BEAM_TIME := 0.9          # the energy blast on screen
const SPECIAL_BEAM_WIDTH := 16.0        # its radius (m): a big, hard-to-miss hit area
const SPECIAL_BEAM_OVERFLOW := 0.45     # after stripping the shields, this share of the target's max hull goes through
const SPECIAL_SIDE_HIT := 0.55          # |beam . target's side| above this = a side hit: that wing comes off
const SPECIAL_SWARM_TURN := 1.6         # the special swarm steers this much harder than normal missiles
const SPECIAL_SWARM_DODGE := 0.35       # ... and the target's dodge chance against it is this share of normal
const SPECIAL_LAUNCHERS := 1            # identical light launchers fitted (the twin-launcher rule: locks x launchers); 1 until the hangar fits two
const MISSILE_EXPIRE_BLAST := true      # a missile that runs out of life bursts into a round explosion zone
# v1.7u (owner: "missiles should always track"): your missiles can't be shaken off. An enemy may still swerve or
# outrun one, but the fuse is short: after MISSILE_LIFE seconds it blows up where it is. Every missile blast shows its
# radius: a white see-through sphere (light) or a six-pointed star burst (super), and anything inside takes splash.
const MISSILE_LIFE := 4.0               # s: the fuse
const MISSILE_BLAST_RADIUS := 18.0      # m: a light missile's blast sphere
const HEAVY_MISSILE_BLAST_RADIUS := 60.0  # m: the super missile's star burst
const MISSILE_SPLASH := 0.5             # share of the missile's damage at the centre of the blast (falls to 0 at the edge); the hit target takes full damage
const BLAST_SHAPE_COLOR := Color(1, 1, 1, 0.32)
const BLAST_SHAPE_TIME := 0.6           # s: grows, then fades
const BLAST_STAR_POINTS := 6            # the super blast: a sphere with this many spikes (one each way along three axes)
const DECOY_RADIUS := 26.0              # an enemy missile this close to one of your mines detonates on it (the mine goes too)
const PLAYER_PILOT_FACE := "gp/unity_01"  # v1.5q placeholder (owner: a character picture for now): the cut-in shows it big in the middle
# ---------------------------------------------------------------- Job AS (v1.5p): the Elyza fighter (folding wings) and the hangar
# The owner's hl_s_elyza file held two forms of one ship; the open form (wings out on their arms) was the clean, even
# one, so the game copy is that one, mirrored, nose at -Z, split into Body / WingL / WingR. The closed form is the same
# model with the wings folded in by SHIP_WINGS (model units): that is how it flies. Each ship can have its own SPECIAL
# move (SHIP_SPECIAL_MOVE): the Elyza fighter swings its wings out while it barrel-rolls; any other ship just rolls.
# ---------------------------------------------------------------- EXPERIMENT (branch planet-blocks-test): big-block ground
# The owner's Minecraft-style destructible ground, light version (no voxel engine): one test patch on New Terra's
# mountains tile built from big blocks that will split into four when hit, down to half a mech. Step 1: looks only.
const BLOCK_TEST := {"planet": "new_terra", "tile": 3, "center": Vector2(500, -700), "size": 800.0}
const BLOCK_BIG := 20.0        # big block (m): a ship-sized chunk; splits 20 -> 10 -> 5
const BLOCK_MIN := 5.0         # the smallest block: half a mech; also the height step of the ground
const BLOCK_SKIRT := 120.0     # how deep the outer edge of the patch goes (covers the sunk sheet's slope)
const BLOCK_SINK := 260.0      # the smooth ground under the patch is sunk this far (out of sight below the blocks)
const BLOCK_MARGIN := 3.0      # column tops sit this much over the highest ground sampled under them
# Step 9 (v1.7a): the whole planet as blocks. The ground near you is built from the seed in square regions as you fly
# (the far ground stays the smooth sheet, cut out wherever a region stands). Behind ?blocks until the owner says go.
const BLOCK_REGION := 500.0         # region side (m): 10 x 10 regions per 5 km tile, 100 x 100 cells each
const BLOCK_REGION_REACH := 1       # regions this many squares around yours are built (1 = a 3 x 3 block of 1.5 km)
const BLOCK_REGION_KEEP := 1        # ...and freed once you are more than this many squares away
# v1.7c (owner): landing pads sit on a floating island of blocks above the ground, so the block ground runs natural
# right under them (no flattening) and world building never has to step round a city. Later: buildings up there.
const PAD_ISLAND_RADIUS := 120.0    # island radius (m); the pad itself is 90
const PAD_ISLAND_CLEAR := 70.0      # its top floats this far over the highest ground under it (arches, roots and all)
const PAD_ISLAND_DEPTH := 45.0      # how far its rocky underside hangs down at the middle (m)
const PAD_ISLAND_CELL := 10.0       # its block size (m)
const BLOCK_REGION_FEATURES := 0.39 # features per region compared with the 800 m test patch (its area share)
const BLOCK_CUTS_MAX := 32         # (the terrain shader holds this many cut-out squares)
const BLOCK_REGION_CANYON := 0.2    # the chance a region has a canyon running through it
const BLOCK_ROCK := Color(0.32, 0.3, 0.29)   # the deep rock colour under the surface
# Step 2 (v1.5t): craters. Every block inside a blast's radius is hit; a block only partly inside splits into four
# (20 -> 10 -> 5 m) so only the hit part goes; obsidian never splits (it chips, then breaks off whole, in half).
const BLOCK_HITS := {"sand": 1, "dirt": 2, "stone": 4, "obsidian": 8, "gold": 6, "diamond": 12, "wood": 3, "leaf": 1, "leaf2": 1, "vine": 2, "frond": 1, "glow": 1, "bloom": 1}   # light-gun hits to break a 5 m layer, by tier
const BLOCK_BLAST := {"gun": [2.4, 1], "missile": [12.0, 4], "heavy": [20.0, 8], "special": [40.0, 16], "thrust": [7.5, 1], "thrust_soft": [7.5, 2]}   # [radius m, hits dealt]; thrust = the mech pushing into a wall
const BLOCK_BREAK_PIECES := {"obsidian": 2, "stone": 3, "dirt": 4, "sand": 5, "gold": 4, "diamond": 3, "wood": 3, "leaf": 5, "leaf2": 5}   # each material breaks its own way: harder = fewer, bigger pieces
const BLOCK_CLEAVE_SPEED := 12.0     # an obsidian piece landing faster than this (m/s) cleaves in half once more
const BLOCK_RUBBLE_FRAC := 0.5       # about half of what a blast breaks flies out as rubble (the rest is dust); obsidian always flies whole
const BLOCK_RUBBLE_PER_BLAST := 10   # at most this many flying pieces per blast (big chunks at the edge, small in the middle)
const BLOCK_RUBBLE_LIVE := 60        # pieces alive at once (the oldest go first)
const BLOCK_RUBBLE_REST := 25.0      # seconds a landed piece lies there before it sinks away (settling/merging is a later step)
const BLOCK_DEPTH_FLOOR := 200.0     # nothing digs deeper than this under the original ground (the kill floor comes later)
const BLOCK_DELTAS_MAX := 4000       # crater notes kept per patch (oldest dropped)
const BLOCK_CHUNK := 40              # the patch is drawn in squares of this many 5 m cells (only the hit squares redraw)
const BLOCK_SLICE_BUDGET_MS := 250.0   # v1.7q test: the longest staged slice allowed on the test machine (a phone is a few times slower)
const BLOCK_CHUNK_REGION := 20   # v1.9c: was 25 (v1.7q): smaller squares, so redrawing one after a hit is a shorter hitch
const BLOCK_REDRAW_BUDGET_MS := 6.0  # v1.9c: changed ground squares redraw a frame at a time while this much frame time is left (at least one)
# Tones from the planet's own ground colour, darker = tougher: [mix toward white (+) or black (-), keep saturation]
# v1.7g (owner's pictures, docs/blocks_look/): dirt is earthy brown under a thin grass cap in the planet's own colour,
# and the ground is built from blocks of many sizes: long rectangles and big solid cubes, not one size of square.
const BLOCK_GRASS_BAND := 1.2        # m of grass cap down the side of a natural top
const DIRT_BROWN := Color(0.46, 0.31, 0.19)   # dirt's own colour...
const DIRT_PLANET := 0.25            # ...with this much of the planet's ground colour in it
const BLOCK_SHAPES := [[1, 1, 34], [2, 1, 18], [1, 2, 18], [2, 2, 12], [3, 1, 6], [1, 3, 6], [3, 2, 3], [2, 3, 3]]   # [cols wide, cols deep, weight]
const BLOCK_SHAPE_EVEN := 10.0       # m: columns only join into one block where the ground under them is this even
const BLOCK_BIG_RISE := 0.25         # the chance a big joined block (4+ columns) stands a step or two proud of the ground
const BLOCK_TONES := {"sand": [0.38, 0.8], "dirt": [-0.12, 0.9], "stone": [-0.45, 0.45], "obsidian": [-0.8, 0.35]}
const BLOCK_DAMAGE_DARK := 0.35      # a cracked block darkens up to this much before it breaks
# v1.5u (owner): underground you touch walls all the time. Over the block ground a bump is free up to cruising speed
# (and always while braking); only faster than that hurts (counted from this speed up). The mech is never hurt by
# the ground at all. Lava and enemy fire are unchanged.
const BLOCK_SAFE_BUMP := 40.0        # m/s (50 still hurts)
# v1.5y step 5, support and collapse: shots can dig INTO walls (tunnels, overhangs, caves). A piece over a hole stays up
# only if it is joined sideways to grounded ground within its material's reach (5 m cells); otherwise it falls.
const BLOCK_REACH := {"sand": 0, "dirt": 1, "stone": 3, "obsidian": 5, "gold": 3, "diamond": 5, "wood": 4, "leaf": 2, "leaf2": 2, "vine": 3, "frond": 2, "glow": 2, "bloom": 2}
# v1.5z step 6, settling: landed rubble merges into the ground as its own material (nothing mixes); dirt sticks to
# the wall it hits; sand slumps into a pile; pieces that fall keep their material.
const BLOCK_MERGE_DELAY := 1.0       # s a landed piece lies there before it becomes ground
const BLOCK_DEPOSIT_MAX := 3.0       # most layers one piece can add
const BLOCK_SAND_STEP := 1           # sand stands at most this many layers over a neighbour (45-degree sides)
# v1.6a the skin over the blocks (look only, collision stays square): [inset m, drop m] where the top steps down.
const BLOCK_SKIN := {"sand": [2.2, 4.0], "dirt": [1.4, 1.8], "stone": [1.2, 1.5], "gold": [1.0, 1.2], "diamond": [0.8, 1.0], "obsidian": [0.0, 0.0]}   # v12.41 (owner: "not so boxy"): rounder edges (was dirt 1.0/1.2, stone 0.7/0.8)
const BLOCK_SHARD_HEIGHT := 8.0      # how far a fused obsidian top points up (m, at most)
# v1.7e the slanted outer form (look only, blocks underneath for the logic): natural ground where the top steps down
# leans into slanted slabs and wedges instead of square stairs, worked out per corner so slabs always meet edge
# to edge (no gaps); where something stands higher the block stays square, so slabs and steps interlock.
const BLOCK_SLANT_MAX := 10.0        # how far a top corner may lean down (m)
const BLOCK_SLANT_ZONE := -1.0       # v12.41 (owner: "anything we can do so they don't look so boxy"): every whole big block of sand / dirt / stone may lean now (was 0.22: patches only). v1.7g (owner: "a few slants"): slants only in patches, where the planet's slant
const BLOCK_SLANT_FREQ := 0.006      #   noise is over this; the rest is square steps like the owner's pictures
# v1.6b water and lava. Sealed pockets from the seed (water in stone, lava deeper in obsidian), asleep until opened;
# they flow only near the player. Water turns sand to dirt; lava eats sand, trades with dirt, stops at stone; lava +
# water = obsidian. Lava burns.
const FLUID_POCKETS := {"water": 8, "lava": 5}
## v12.32 (owner: "take the basic geography of the planet and make the whole planet more of that genre ... it may not
## have water but it may have lava"): each kind of land has its own ground. Underground water / lava pockets scaled by land
## (missing = 1.0); impact craters (moons, dead worlds); wind-blown dunes (deserts).
const GEO_FLUID := {"barren": {"water": 0.0, "lava": 0.4}, "volcanic": {"water": 0.0, "lava": 3.0}, "desert": {"water": 0.0, "lava": 0.3},
	"wasteland": {"water": 0.0, "lava": 0.8}, "ice": {"water": 1.2, "lava": 0.0}, "crystal": {"water": 0.0, "lava": 0.0}, "machine": {"water": 0.0, "lava": 0.0},
	"jungle": {"water": 1.6, "lava": 0.0}, "forest": {"water": 1.2, "lava": 0.1}, "ocean": {"water": 1.4, "lava": 0.0}, "coast": {"water": 1.2, "lava": 0.1},
	"toxic": {"water": 1.0, "lava": 0.0}, "clouds": {"water": 0.0, "lava": 0.0}, "canyon": {"water": 0.4, "lava": 0.5}, "mountains": {"water": 0.8, "lava": 0.3}}
const GEO_CRATERS := {"barren": 1.4, "wasteland": 0.45, "volcanic": 0.3, "crystal": 0.2}
const GEO_DUNES := {"desert": 1.0, "wasteland": 0.25}
const FLUID_DEPTH := {"water": [20.0, 60.0], "lava": [60.0, 150.0]}   # m under the ground
const FLUID_TICK := 0.25             # s per flow step
const LAVA_SLOW := 3                 # lava moves every this many steps (slower)
const FLUID_RADIUS := 250.0          # m: only this close to the player does anything flow
const FLUID_MAX_MOVES := 200         # moves per step at most
const FLUID_COLOR := {"water": Color(0.12, 0.42, 0.95, 0.62), "lava": Color(1.0, 0.42, 0.08, 0.85)}
const LAVA_DPS := 25.0               # hull per second while in lava (ship and mech)
# v1.6c mining. Gold and diamond veins from the seed: deep (diamond often in the obsidian round a lava pocket), and on
# some worlds a few right out on the surface. Very tough. Breaking one drops pickup pieces (they never fuse back); the
# blast destroys the rest, so careful digging keeps more (MINING_KEEP by weapon). The tractor beam pulls them in.
const VALUABLE_COLOR := {"gold": Color(1.0, 0.78, 0.22), "diamond": Color(0.78, 0.95, 1.0)}
const MINE_VEINS := {"gold": 6, "diamond": 3}
const VEIN_DEPTH := {"gold": [25.0, 120.0], "diamond": [80.0, 170.0]}
const SURFACE_TREASURE_CHANCE := 0.6   # chance a world has a few veins right out on the surface
const MINING_KEEP := {"gun": 0.75, "thrust": 0.75, "thrust_soft": 0.75, "missile": 0.5, "heavy": 0.35, "special": 0.2}
const MINE_VALUE := {"gold": 40, "diamond": 120}   # base credits per piece (v1.8l: paid when you SELL it at a base)
# v1.8l (owner): mined gold / diamond goes into the hold (one stack each in GS.cargo) and is sold at a station or planet
# base under YOUR SHIP. Every base pays its own fixed share of the base price (from its name, nothing stored).
const ORE_PRICE_SWING := [0.8, 1.5]
const ORE_NAME := {"gold": "Gold", "diamond": "Diamond"}
# v1.6d world generation, part 1. Caves: a few self-contained pockets of winding tunnels (3D noise in a rounded box),
# sealed. The bottom of the ground (BLOCK_DEPTH_FLOOR down) is the KILL FLOOR under a KILL_CAP of obsidian: dug open
# it glows; water, lava and rubble reaching it are gone; the ship touching it is destroyed.
const CAVE_COUNT := 5
const CAVE_SIZE := 24                # cells across (70 m)
const CAVE_LAYERS := 12               # layers tall (40 m)
const CAVE_DEPTH := [45.0, 110.0]    # m under the ground (its middle)
const CAVE_NOISE_FREQ := 0.11
const CAVE_THRESHOLD := 0.18
# v1.7h MOLDS (owner's voxel notes + picture 07): designed shapes stamped into the ground as filled volumes of 5 m
# cells, either cut out (caves) or added (trees, roots: next). The first: a cave system with a big chamber, tunnels
# out to side rooms (floors at different heights) and one tunnel climbing to a surface entrance, all big enough to fly.
# v1.7j winding tunnels (the notes' "spaghetti caves"): from a mold cave's side rooms, tunnels wander by noise out to
# the nearest sealed caves, so the cave system links up (deliberately connected, as the notes ask).
const LINK_MAX := 2                  # tunnels out of each mold cave
const LINK_REACH := 70               # cells: only caves this close get a tunnel
const LINK_RADIUS := 2               # cells: tunnel radius (about 20 m across, room to fly)
const LINK_TALL := 4                 # layers
const LINK_WANDER := 0.55            # how much it winds
const MOLD_CAVE_CHANCE := 0.3        # the share of regions with one
const MOLD_CHAMBER := [16, 20]       # chamber width in cells (80-100 m)
const MOLD_CHAMBER_TALL := 7         # layers (35 m)
const MOLD_TUNNEL_W := 4             # cells (20 m): room to fly
const MOLD_TUNNEL_TALL := 4          # layers (20 m)
const MOLD_TUNNEL_LEN := [8, 14]     # cells from the chamber to a side room
const MOLD_ROOM := [7, 10]           # side room width in cells
const MOLD_ROOM_TALL := 5            # layers
const MOLD_CEILING := 3              # layers of rock left over the chamber and rooms at least (15 m)
const MOLD_RAMP := 2                 # the entrance tunnel climbs one layer every this many cells, then a shaft opens up
# v1.7i ALIEN TREES (the owner's picture 06): a chunky twisting WOOD trunk and branches under big flat LEAF slabs in
# two colours (teal and purple), roots spreading underground; one tree beside each mold cave sends a root down into
# its chamber. Wood and leaves CATCH FIRE (owner): missiles and lava set them burning, fire spreads to touching wood
# and leaves, burns them away and dies out; water puts it out. Like the fluids, fire only runs near the player.
const WOOD_COLOR := Color(0.40, 0.35, 0.30)
const LEAF_COLORS := {"leaf": Color(0.16, 0.55, 0.50), "leaf2": Color(0.52, 0.40, 0.72),
	"vine": Color(0.10, 0.40, 0.22), "frond": Color(0.30, 0.68, 0.26), "glow": Color(0.22, 0.95, 0.92), "bloom": Color(0.95, 0.34, 0.74)}   # (v12.22: the lush ones keep their own colour)
## v12.22 (owner: "lush forests ... Avatar style ... floating voxels connected by vines ... high lush waterfalls ... lots of
## different vegetation"): jungle ground grows a dense mixed forest (giant trees, palms, glowing mushrooms, bushes,
## ferns), floating islands of rock held up by vines that hang to the ground (and vine bridges between them), with
## waterfalls pouring off their edges. Counts are per 500 m region.
const LUSH := {"jungle": {"trees": 16, "gap": 8, "tall_bonus": 4, "plants": 150, "islands": 3, "island_falls": 2}}
const LUSH_PLANTS := {"palm": 0.30, "bush": 0.30, "fern": 0.22, "mushroom": 0.18}   # the mix
const ISLAND_LIFT := [12, 22]        # layers (60-110 m) from the highest ground under it to an island's underside
const ISLAND_RADIUS := [6, 10]       # cells (30-50 m)
const ISLAND_BRIDGE := 46            # cells: islands this close get a vine bridge
# v12.0 (owner): leaf colour pairs by the land: [leaf, leaf2], one pair per planet (BlockField.leaf_colors)
const LEAF_SETS := {
	"hot": [[Color(0.92, 0.45, 0.12), Color(0.78, 0.15, 0.10)], [Color(0.80, 0.16, 0.14), Color(0.50, 0.20, 0.62)], [Color(0.95, 0.62, 0.15), Color(0.85, 0.30, 0.10)]],
	"cold": [[Color(0.78, 0.92, 0.98), Color(0.45, 0.75, 0.92)], [Color(0.70, 0.75, 0.88), Color(0.62, 0.55, 0.85)]],
	"toxic": [[Color(0.62, 0.85, 0.12), Color(0.88, 0.82, 0.15)], [Color(0.25, 0.70, 0.30), Color(0.15, 0.55, 0.55)]],
	"crystal": [[Color(0.92, 0.45, 0.75), Color(0.55, 0.35, 0.90)], [Color(0.35, 0.85, 0.90), Color(0.85, 0.35, 0.85)]],
	"green": [[Color(0.16, 0.55, 0.50), Color(0.52, 0.40, 0.72)], [Color(0.22, 0.60, 0.18), Color(0.40, 0.72, 0.22)], [Color(0.12, 0.45, 0.22), Color(0.78, 0.72, 0.18)]]}
const TREES_PER_TILE := {"forest": 10, "coast": 4, "mountains": 3, "city": 3, "canyon": 2, "industrial": 1, "ocean": 1, "desert": 0, "ice": 0, "volcanic": 0, "sun": 0, "barren": 0, "crystal": 0, "machine": 0, "wasteland": 0, "clouds": 0, "toxic": 1}   # per 800 m (a region gets its share); others 2 (v12.32: no trees on moons and dead worlds)
const TREE_TRUNK := [2, 3]           # trunk width in cells (10-15 m)
const TREE_TALL := [6, 10]           # trunk height in layers (30-50 m)
const TREE_BRANCHES := [3, 5]
const TREE_CANOPY := [5, 9]          # leaf slab width in cells
const TREE_ROOTS := [3, 5]
# v1.7l WATERFALLS (the owner's picture 06): where a cliff drops sharply, a pool set back on its top pours over a rock
# lip down the face into a pool with white foam at its foot. The falling sheet is a moving picture; the pools are real
# water. Blast the lip or the cliff face and the fall stops.
const FALLS_PER_TILE := {"jungle": 6, "forest": 3, "coast": 3, "mountains": 4, "canyon": 3, "city": 1, "industrial": 1, "ocean": 1, "desert": 0, "volcanic": 0, "ice": 0, "sun": 0, "barren": 0, "crystal": 0, "machine": 0, "wasteland": 0, "clouds": 0, "toxic": 1}   # per 800 m; others 2 (v12.32: no waterfalls on dry worlds)
const FALL_DROP := 20.0              # m: the least drop for a waterfall
const FALL_WIDE := 2                 # cells across (10 m)
const FALL_COLOR := Color(0.62, 0.86, 1.0, 0.85)
# v1.7m UNDERGROUND LIGHT (the design notes): under cover (cave floors, roofs, walls facing a hole) the sun and the sky
# don't reach, so it is dark; light comes from the ship's flashlight and from things that glow by themselves: lava,
# fire, gold (warm), diamond (cold), the kill floor. Obsidian is glossy. Cheap for phones: the glows are emissive,
# only a few real lights (the nearest ones to you) light their surroundings.
const CAVE_DARK := 0.12              # how much of the sun and sky reaches a covered face
const BLOCK_GLOW := {"gold": 0.55, "diamond": 1.1, "glow": 1.0, "bloom": 0.55}   # how brightly treasure glows by itself
const BLOCK_GLOSS := {"obsidian": 1.0, "diamond": 0.8, "gold": 0.6}   # glassy shine
const GLOW_LIGHTS := 3               # real lights at the nearest glowing things to you
const GLOW_LIGHT := {"lava": [Color(1.0, 0.45, 0.12), 2.2, 34.0], "fire": [Color(1.0, 0.55, 0.15), 2.0, 30.0], "diamond": [Color(0.7, 0.9, 1.0), 1.6, 22.0], "gold": [Color(1.0, 0.8, 0.35), 1.2, 16.0], "kill": [Color(1.0, 0.35, 0.1), 3.0, 60.0]}   # [colour, energy, range m]
const GLOW_REACH := 140.0            # m: glowing things this near you get a real light
const FLASHLIGHT := [Color(1.0, 0.97, 0.9), 3.0, 160.0, 28.0]   # [colour, energy, range m, cone degrees]: on underground
# v1.8j (planet polish): the lamp shows a small glare at the ship's nose when it is on; under water it is always on,
# turns sea-green and reaches less far, and the view is tinted (light through water).
const FLASHLIGHT_FLARE := [Color(1.0, 0.95, 0.8, 0.55), 2.2]     # [glare colour, size m]
const FLASHLIGHT_WATER := [Color(0.55, 1.0, 0.92), 4.0, 70.0, 34.0]   # under water: [colour, energy, range m, cone degrees]
const UNDERWATER_TINT := Color(0.05, 0.35, 0.45, 0.38)
# v1.8k (owner): bounty targets come back, so the boards never run out: a pilot you hand in breaks out later, one you
# killed is back (a new ship) later; real time, so it carries over between sessions. Handed in at a station or killed:
# 30 minutes; handed in at a planet (more secure): an hour. The price stays the same.
const BOUNTY_ESCAPE_STATION := 1800.0   # s
const BOUNTY_ESCAPE_PLANET := 3600.0    # s
const FIRE_TICK := 0.5               # s
const FIRE_BURN := {"wood": 4.0, "leaf": 1.5, "leaf2": 1.5, "vine": 2.5, "frond": 1.5, "glow": 1.5, "bloom": 1.5}   # s a burning layer lasts before it is gone
const FIRE_SPREAD := {"wood": 0.25, "leaf": 0.5, "leaf2": 0.5, "vine": 0.35, "frond": 0.5, "glow": 0.4, "bloom": 0.4}   # chance per tick it catches from a burning neighbour
const GRASS_COVER := {"forest": 0.4, "jungle": 0.75, "coast": 0.25, "mountains": 0.2, "toxic": 0.32, "city": 0.12, "canyon": 0.08, "wasteland": 0.1, "industrial": 0.06, "crystal": 0.12, "volcanic": 0.05}   # v12.7: share of the dirt ground with grass blocks, by land
const GRASS_PATCH_FREQ := 0.012      # the grass grows in patches and meadows ~80 m across
const GRASS_TIP_GREEN := Color(0.72, 0.95, 0.42)   # v12.8: green land: light green tips ...
const GRASS_ROOT_GREEN := Color(0.22, 0.5, 0.18)   # ... from a green root (mixed with the ground's own colour)
const GRASS_VIEW := 520.0            # m: grass further than this isn't drawn
const GRASS_MAX_LAYERS := 4          # owner: "4 blocks is the most"
const GRASS_BLADES := 7              # blades across one sheet
const GRASS_SEGMENTS := 5            # bends along a sheet (the weave)
## v12.27 (owner: "inside a block ... three by three or four by four blades of grass", "merge into a bigger blade", "a
## shape like a flower"): each grass block is a 4 x 4 grid of tufts (3 blades each); four blocks together are one clump
## twice the size (the blades twice as big). Some blocks are flowers instead: star bloom, glow bulb, fan flower, bell
## flower; four together open into one giant bloom.
## v12.28 (owner: "how do the animals work? ... the sheep or the deer", alien ones): wildlife on the grass (scripts/wildlife.gd).
## size: metres (the model is ~1 unit); walk / run: m/s; flee: how near the player can come before it bolts.
# v12.41 (owner: planet wildlife, "sheep, deer, bear, giant worm" - original alien fauna with clear roles; docs/WILDLIFE.md):
# data-driven species profiles. All PLACEHOLDERS (owner: "those animals will be placeholders"); what matters is the role:
#   role prey     - never fights: notices you, warns the herd, runs
#   role defense  - stands its ground: warns, holds; fights only if you come right up or hurt it; never hunts or chases far
#   role predator - hunts: goes after prey animals, warns you once briefly, then attacks if you stay in its ground
# arch: grazer (graze, herd, flee) / prey (alert the herd, bolt) / predator (patrol, warn,
# attack, give up past its territory) / burrower (ripple, telegraph, emerge, exposed, re-burrow) / giant (threat display,
# charge, slam, throw). size = metres (the model is ~1 unit), notice / flee / territory / reach in m, dmg per hit.
# ground: grass (only on grass), flowers, land (any dry ground). model: which body is drawn (variants share one).
# col: the colour overrides for a variant. active: when it is about (the surface has no clock yet: data only for now).
const WILDLIFE := {
	"strider": {"role": "prey", "name": "Strider", "arch": "prey", "size": 6.0, "walk": 4.0, "run": 26.0, "notice": 90.0, "flee": 70.0, "alert_t": 0.6,
		"flag": 60.0, "herd": [2, 4], "ground": "grass", "hp": 60.0, "diet": "leaves, flowers", "active": "dawn, dusk"},
	"prismhart": {"role": "prey", "name": "Prismhart", "arch": "prey", "model": "strider", "crystal": true, "size": 6.0, "walk": 4.0, "run": 24.0, "notice": 90.0,
		"flee": 70.0, "alert_t": 0.6, "flag": 60.0, "herd": [2, 3], "ground": "land", "hp": 70.0, "diet": "mineral lichen", "active": "dawn, dusk",
		"col": {"hide": Color(0.43, 0.35, 0.66), "stripe": Color(1.0, 0.44, 0.82), "belly": Color(0.9, 0.88, 1.0), "antler": Color(0.79, 0.65, 1.0)}},
	"grazer": {"role": "prey", "name": "Glow grazer", "arch": "grazer", "size": 5.0, "walk": 2.0, "run": 6.0, "notice": 30.0, "flee": 22.0, "alert_t": 1.0,
		"herd": [1, 3], "ground": "grass", "hp": 80.0, "diet": "grass", "active": "night"},
	"hopper": {"role": "prey", "name": "Hopper", "arch": "prey", "size": 1.8, "walk": 3.0, "run": 14.0, "notice": 45.0, "flee": 35.0, "alert_t": 0.2,
		"herd": [2, 5], "ground": "flowers", "hp": 15.0, "diet": "flowers", "active": "day"},
	"mossfleece": {"role": "prey", "name": "Mossfleece", "arch": "grazer", "size": 2.6, "walk": 2.5, "run": 11.0, "notice": 40.0, "flee": 30.0, "alert_t": 1.0,
		"herd": [4, 7], "ground": "grass", "hp": 40.0, "diet": "grass, moss", "active": "day"},
	"drift_woolly": {"role": "prey", "name": "Drift woolly", "arch": "grazer", "model": "mossfleece", "size": 2.8, "walk": 2.2, "run": 10.0, "notice": 40.0,
		"flee": 30.0, "alert_t": 1.0, "herd": [3, 6], "ground": "land", "hp": 45.0, "diet": "ice moss", "active": "day",
		"col": {"wool": Color(0.95, 0.97, 1.0), "skin": Color(0.18, 0.29, 0.45), "moss": Color(0.62, 0.9, 1.0), "horn": Color(0.81, 0.91, 1.0)}},
	"grumbark": {"role": "defense", "name": "Grumbark", "arch": "predator", "size": 6.5, "walk": 3.0, "run": 15.0, "notice": 60.0, "warn_t": 2.0, "territory": 160.0,
		"reach": 9.0, "dmg": 10.0, "cd": 1.8, "herd": [1, 1], "cap": 1, "ground": "land", "hp": 260.0, "diet": "berries, grazers", "active": "day"},
	"rime_grumbark": {"role": "defense", "name": "Rime grumbark", "arch": "predator", "model": "grumbark", "size": 6.8, "walk": 3.0, "run": 14.0, "notice": 60.0,
		"warn_t": 2.0, "territory": 160.0, "reach": 9.0, "dmg": 11.0, "cd": 1.8, "herd": [1, 1], "cap": 1, "ground": "land", "hp": 280.0,
		"diet": "fur grazers", "active": "any",
		"col": {"fur": Color(0.87, 0.91, 0.96), "bark": Color(0.44, 0.53, 0.66), "moss": Color(0.66, 0.94, 1.0)}},
	"vexmaw": {"role": "predator", "name": "Vexmaw", "arch": "predator", "size": 4.5, "walk": 4.0, "run": 22.0, "notice": 70.0, "warn_t": 2.0, "territory": 150.0,
		"reach": 8.0, "dmg": 8.0, "cd": 1.4, "herd": [1, 2], "cap": 2, "ground": "land", "hp": 160.0, "hunts": true, "diet": "meat (striders)", "active": "dusk, night"},
	"shale_stalker": {"role": "predator", "name": "Shale stalker", "arch": "predator", "model": "vexmaw", "size": 4.5, "walk": 4.0, "run": 20.0, "notice": 70.0,
		"warn_t": 2.0, "territory": 150.0, "reach": 8.0, "dmg": 8.0, "cd": 1.4, "herd": [1, 2], "cap": 2, "ground": "land", "hp": 200.0, "hunts": true,
		"diet": "meat", "active": "any",
		"col": {"skin": Color(0.54, 0.48, 0.42), "stripe": Color(0.35, 0.29, 0.25), "eye": Color(0.48, 1.0, 0.85)}},
	"sandmaw": {"role": "defense", "name": "Sandmaw", "arch": "burrower", "size": 18.0, "walk": 6.0, "run": 16.0, "notice": 120.0, "territory": 300.0, "ring": 13.0,
		"tele_t": 1.5, "exposed_t": 4.0, "dmg": 18.0, "herd": [1, 1], "cap": 1, "ground": "land", "hp": 500.0, "diet": "anything that walks", "active": "any"},
	"rimeback": {"role": "defense", "name": "Rimeback", "arch": "giant", "size": 14.0, "walk": 3.5, "run": 13.0, "notice": 100.0, "warn_t": 2.5, "territory": 250.0,
		"reach": 14.0, "slam_r": 22.0, "dmg": 14.0, "throw_dmg": 9.0, "cd": 2.6, "herd": [1, 1], "cap": 1, "ground": "land", "hp": 600.0,
		"diet": "fur grazers, ice moss", "active": "any"},
}
## Which animals live on which ground (tile kind): the share each kind spawns at and the most at once.
const WILDLIFE_BIOMES := {
	"jungle": {"max": 14, "kinds": {"strider": 0.3, "grazer": 0.28, "hopper": 0.24, "vexmaw": 0.18}},
	"forest": {"max": 12, "kinds": {"mossfleece": 0.35, "strider": 0.3, "hopper": 0.2, "grumbark": 0.15}},
	"coast": {"max": 8, "kinds": {"mossfleece": 0.4, "grazer": 0.3, "hopper": 0.3}},
	"mountains": {"max": 6, "kinds": {"strider": 0.45, "mossfleece": 0.35, "grumbark": 0.2}},
	"toxic": {"max": 6, "kinds": {"grazer": 0.6, "hopper": 0.4}},
	"ice": {"max": 8, "kinds": {"drift_woolly": 0.55, "rimeback": 0.2, "rime_grumbark": 0.25}},
	"crystal": {"max": 7, "kinds": {"prismhart": 0.75, "hopper": 0.25}},
	"desert": {"max": 4, "kinds": {"sandmaw": 0.4, "shale_stalker": 0.6}},
	"canyon": {"max": 4, "kinds": {"shale_stalker": 0.6, "sandmaw": 0.4}},
}
const WILDLIFE_PAD_CLEAR := 260.0     # m: nothing spawns this near a base / landing pad, and hunters won't follow you in
const WILDLIFE_DMG := {"gun": 10.0, "missile": 35.0, "heavy": 70.0, "special": 45.0}   # what a blast near an animal takes off it
const WILDLIFE_TOON := true           # cel shading + an ink outline (the anime look)
## The wildlife test area (?wildtest / HL_WILDTEST): every species at fixed spots round the landing point, [kind, angle deg, distance m, count].
const WILDLIFE_PARK := [["mossfleece", 0, 110, 5], ["drift_woolly", 25, 150, 3], ["strider", 50, 140, 3], ["prismhart", 75, 170, 2],
	["hopper", 100, 95, 4], ["grazer", 125, 120, 2], ["grumbark", 160, 210, 1], ["vexmaw", 205, 200, 1], ["shale_stalker", 245, 230, 1],
	["rimeback", 290, 240, 1], ["sandmaw", 330, 220, 1]]
const WILDLIFE_SPAWN := [80.0, 260.0]   # m from the player: where new ones appear
const WILDLIFE_DESPAWN := 420.0         # m: further than this they go
const WILDLIFE_SHADOWLESS := true       # (phones: no shadows from the animals)
const GRASS_GRID := 4
## v12.40 (owner, on foot: "grass and flowers too high, make lower, I'm like an ant"): grass was 5-15 m tall (1-3 blocks);
## now about knee to shoulder height for the pilot, ankle-high for the mech. Flowers scaled the same way.
const GRASS_HEIGHT_K := 0.17
const FELL_PIECES := 14
const ROCK_JAG := 2.2     # v12.43: m bare rock walls push in / out (0 = flat walls)
const ROCK_ROW := 2.5     # m between the rows of a rock wall's grid    # v12.43: falling pieces when a burnt tree comes down
const FLOWER_HEIGHT_K := 0.3
const FLOWER_SHARE := {"jungle": 0.14, "forest": 0.07, "coast": 0.05, "toxic": 0.06, "mountains": 0.03, "city": 0.02}   # share of the grass that is flowers
const FLOWER_KINDS := ["star", "bulb", "fan", "bell"]
const FLOWER_COLORS := {"star": [Color(1.0, 0.42, 0.78), Color(0.72, 0.42, 1.0)], "bulb": [Color(0.3, 1.0, 0.92), Color(0.5, 0.85, 1.0)],
	"fan": [Color(1.0, 0.62, 0.25), Color(1.0, 0.85, 0.3)], "bell": [Color(0.55, 0.6, 1.0), Color(0.95, 0.95, 1.0)]}
const GRASS_FIRE_CHANCE := {"gun": 0.35, "missile": 0.6, "heavy": 0.5, "special": 0.8}   # a shot sets the grass alight (else blows it away)
const GRASS_SPREAD := 0.45           # chance per tick the fire jumps to the next clump
const GRASS_BURN := 1.6              # s a clump burns before it is gone
const FIRE_MAX := 300                # burning layers at once at most
const FIRE_RADIUS := 300.0           # m: fire only runs this near the player
const FIRE_GUN_CHANCE := 0.2         # a light-gun hit on wood sets it alight this often (missiles always do)
# v12.7 (owner: "amazing terrain ... very unworldly, high drop-off cliffs, lots of different canyons, huge caves and
# caverns ... mountains that bend a certain way ... they're not supposed to all look like Earth"): the alien sculpt on
# top of each biome's own shape (Surface._alien_at), by how alien the land is (0 = Earth-like, 1 = full).
const TERRAIN_ALIEN := {"crystal": 1.0, "barren": 1.0, "canyon": 1.0, "volcanic": 0.9, "jungle": 0.85, "toxic": 0.8, "wasteland": 0.85,
	"desert": 0.6, "mountains": 0.7, "ice": 0.6, "machine": 0.35, "forest": 0.35, "industrial": 0.15, "coast": 0.15}
const ALIEN_WARP := 1400.0          # m the ridges and canyons are bent sideways (curves and arcs instead of straight lines)
const ALIEN_WARP_FREQ := 0.00032
const ALIEN_RIDGE_FREQ := 0.00036   # bent crests ~2-3 km apart
const ALIEN_RIDGE := 1.05           # their height (share of the biome's amp)
const ALIEN_MESA_FREQ := 0.00022    # plateaus ~4 km across ...
const ALIEN_MESA := 0.42            # ... each step this tall (share of amp): sheer cliffs at the edges
const ALIEN_CANYON_FREQ := 0.00028
const ALIEN_CANYON := 0.75          # how deep the canyons cut (share of amp)
const KILL_CAP := 30.0               # m of obsidian over the kill floor
const KILL_COLOR := Color(1.0, 0.82, 0.45)
# v1.6e world generation, part 2: landmarks. Flyable arches (stone, some obsidian, some with treasure in the span) and
# Pride Rock promontories (a slab jutting out over open air). Sizes in 5 m cells / metres; realistic, no thin spikes.
const LANDMARK_TEST := {"ARCH_COUNT": 3, "ARCH_SPAN": [6, 11], "ARCH_CLEAR": [25.0, 45.0], "OVERHANG_COUNT": 2, "OVERHANG_JUT": [3, 5], "OVERHANG_RISE": [35.0, 60.0],
	"LANDMARK_FLAT": 25.0, "CAVE_SIZE": 14, "CAVE_LAYERS": 8, "HALL_SIZE": 24, "HALL_LAYERS": 10, "CANYON_DEPTH": [40.0, 70.0], "SLAB_COUNT": 4, "AFRAME_COUNT": 3}   # v12.7: the route tests' ground keeps the sizes they were written for
const ARCH_COUNT := 0   # v12.32 (owner: "get rid of those arcs ... looks dumb all over the place"); v12.7 was 6
const ARCH_SPAN := [8, 20]           # cells of open air between the legs (30-55 m)
const ARCH_CLEAR := [40.0, 90.0]     # m of headroom under the middle
const ARCH_THICK := 10.0             # m of rock over the opening
const OVERHANG_COUNT := 0   # v12.32: the pillar-and-slab rocks go with the arches; v12.7 was 4
const OVERHANG_JUT := [4, 8]         # cells the slab juts out (15-25 m)
const OVERHANG_RISE := [45.0, 100.0]  # m the promontory stands over the ground
const OVERHANG_THICK := 10.0
# v1.7f leaning slabs (owner: "two leaning slabs make a natural A-frame arch; shoot the prop and it falls flat").
# Blocks underneath for the logic (a staircase of cells over air, propped), one straight tilted slab for the eyes
# while it's whole; break any part and it shows as the blocks it really is, and what loses its prop falls.
const SLAB_COUNT := 0                # lean-tos (a slab propped on a pillar) per 800 m of ground (a region gets its share)
const AFRAME_COUNT := 0              # A-frames (two slabs leaning on each other) per 800 m
const SLAB_LEN := [6, 10]            # cells along the slab (30-50 m)
const SLAB_RISE := [20.0, 35.0]      # how high its raised end stands over the ground (m)
const SLAB_WIDE := 3                 # cells across (15 m)
const SLAB_THICK := 10.0             # m
const LANDMARK_FLAT := 40.0         # m: how uneven the ground under a landmark may be
# v1.6f world generation, part 3. Realistic heights (no thin spires), a winding canyon, obsidian roots piercing the
# surface.
const SPIRE_MAX := 15.0              # m a column may stand over all its neighbours
const CANYON_DEPTH := [60.0, 120.0]   # m under the ground
const CANYON_WIDTH := 3.0            # cells (half-width; 15 m)
const ROOT_COUNT := 6
const ROOT_RISE := [12.0, 35.0]      # m the shards stand out of the ground
const ROOT_DEPTH := 80.0             # m the obsidian root runs down under them
const ROOT_SOIL_CHANCE := 0.6        # v1.8i: chance each spot beside a tree's buttress roots gets sand / dirt banked up in it
const ROOT_SOIL_SAND := 0.35         # ...and the share of those that are sand (the rest dirt)
# v1.6h the deep world: great halls right over the obsidian cap, with obsidian trunks and branches holding the rock up
# and lava pools glowing between them. In sections, sealed.
const HALL_COUNT := 3
const HALL_SIZE := 36               # cells across (120 m)
const HALL_LAYERS := 14             # layers tall (50 m)
const HALL_TRUNK_SPACING := 5       # cells between trunks
const HALL_LAVA := 0.04             # share of the floor that is a lava pool
# v1.5v (owner): the mech digs by thrusting its body into a wall, by the same break rules as a shot. Sand and dirt it
# plows straight through; stone breaks but shoves it back each push (chip, bounce, chip); obsidian won't break, it just
# bounces the mech off. Never any damage to the mech.
const MECH_DIG_REACH := 4.5          # m ahead of the mech's middle where it meets a wall
const MECH_DIG_STEP := 5.0           # a rise up to this is just a step it walks up, not a wall
const MECH_DIG_SOFT_TICK := 0.12     # s between digs into sand / dirt (one 5 m dirt layer each)
const MECH_DIG_STONE_TICK := 0.35    # s between pushes into stone (one hit each, then the bounce)
const MECH_DIG_BOUNCE := 14.0        # m/s the stone / obsidian shoves the mech back
# ---------------------------------------------------------------- Job AT (v1.5q): clean-up + placeholder fighters
# The owner's placeholder fighter set (hlpshplholder_faction): one fighter per faction, tinted in its own colour, so every
# faction's six pilots have a ship (and their voices) until the real ships come. Factions that already fly the owner's
# own ships keep them; PLACEHOLDER_SHIPS says which placeholder each faction has (one line each to swap in).
const PLACEHOLDER_SHIP_LEN := 11.0
const PLACEHOLDER_SHIPS := {"Savagers": "ph_savagers", "Liberator": "ph_liberator", "Unity": "ph_unity", "Imperium": "ph_imperium",
	"Elyza": "ph_elyza", "Covenant": "ph_covenant", "Solarion": "ph_solarion", "Orion": "ph_orion", "Cybermorph": "ph_cybermorph",
	"Solrath": "ph_solrath", "Gadversee": "ph_gadversee", "Arctides": "ph_arctides", "Phenom": "ph_phenom", "Kaijurai": "ph_kaijurai"}
const ELYZA_FIGHTER_LEN := 12.0
const SHIP_WINGS := {"elyza_fighter": 1.2}            # model key -> how far the wings fold in (model units; 0 = open). v10: the remodel is in metres (12 m)
const SHIP_SPECIAL_MOVE := {"elyza_fighter": "wings_out"}   # model key -> its own special move ("roll" when not listed)
const WINGS_OPEN_RATE := 2.5                          # wings open / close per second (fraction of the way)

# ---------------------------------------------------------------- Job AQ (v1.5n): thrust arc (looks only, flight unchanged)
const THRUST_ARC_DEG := 22.0      # how far the nose rears up at most while THRUST is on
const THRUST_ARC_BASE := 0.45     # share of that on a level boost; climbing or pulling up adds the rest
const THRUST_ARC_IN := 5.0        # how fast it rears up
const THRUST_ARC_OUT := 2.5       # how fast it settles back to level after you let go

# ---------------------------------------------------------------- Job AP (v1.5m): GPS stage 3: fastest route, lanes clear of rocks, GO
const LANE_BELT_CLEAR := 350.0     # the asteroid field keeps this far (past its radius) from every trade-lane line
const GPS_LANE_GAIN := 0.85        # the GPS sends you by trade lane when that is at least this much faster than flying direct
const GPS_WARP_FROM := 1500.0      # legs longer than this count as flown at warp (as the autopilot does)

# ---------------------------------------------------------------- Job AO (v1.5l): the roster deployed across the game
const BOUNTY_SLOTS := [2, 3, 4, 6]            # who is wanted, in every faction with ships
const BOUNTY_FACTIONS := ["Savagers", "Imperium", "Liberator", "Covenant", "Phenom", "Kaijurai", "Cybermorph", "Solrath"]
const COORDINATOR_HINTS := ["officer", "strategist", "leader", "engineer", "warden", "scientist", "captain"]   # a role that sounds like handing out work

# ---------------------------------------------------------------- Job AN (v1.5k): test-flow foundation (owner's brief of 8 Oct)
## The opening system's enemies: the start system's RIVAL NATION (Unity's rival, the Imperium), low ranks only, always
## hostile: ordinary troops, never a story boss or a placeholder raider leader. Slot 01 (Imperium Trooper, male) and
## 02 (Vexa Drak, female) so both voices are heard.
const OPENING_SYSTEMS := {"solara": {"faction": "Imperium", "max_slot": 2}}
const PATROL_MAX_SLOT := 5           # patrols never fly a faction's leader (slot 06): leaders keep their story roles
const HUB_LAUNCH_SIZE := Vector2(230, 58)   # the hub's LAUNCH button (always on screen, upper right)

# ---------------------------------------------------------------- Job AM (v1.5j): voice system stage 1 (scripts/voice.gd, Sfx.play_character_voice)
const VOICE_LIVE_API := false                 # stage 3 only, behind a secure server: never a key in this client
const VOICE_PROFILE_ROLLOUT := ["*"]   # v1.5k: everyone (was the four test characters: Rennick, Vale, UNIT-01, Kaijurai trooper)
const VOICE_PITCH_RANGE := [0.55, 1.5]        # never so far that speech is hard to follow
const VOICE_RATE_RANGE := [0.75, 1.35]
const VOICE_SEX_PITCH_NUDGE := 1.18           # the device has no voice of that sex: raise (female) / lower (male) the pitch this much instead
## Defaults per voice persona (the roster documents' "voice_persona"); effect = sounds played around the line.
const VOICE_PERSONAS := {
	"male": {"voice_type": "male", "pitch": 0.95, "speaking_rate": 1.0, "volume": 80, "effect": "radio"},
	"female": {"voice_type": "female", "pitch": 1.06, "speaking_rate": 1.02, "volume": 80, "effect": "radio"},
	"male_masked": {"voice_type": "male", "pitch": 0.86, "speaking_rate": 0.98, "volume": 80, "effect": "radio"},
	"male_augmented": {"voice_type": "male", "pitch": 0.78, "speaking_rate": 0.94, "volume": 85, "effect": "radio"},
	"male_alien": {"voice_type": "male", "pitch": 0.76, "speaking_rate": 1.12, "volume": 80, "effect": "alien"},
	"male_alien_masked": {"voice_type": "male", "pitch": 0.72, "speaking_rate": 1.06, "volume": 80, "effect": "alien"},
	"male_alien_augmented": {"voice_type": "male", "pitch": 0.66, "speaking_rate": 0.95, "volume": 85, "effect": "alien"},
	"female_alien": {"voice_type": "female", "pitch": 1.24, "speaking_rate": 1.12, "volume": 80, "effect": "alien"},
	"male_hive": {"voice_type": "male", "pitch": 0.8, "speaking_rate": 1.0, "volume": 80, "effect": "alien"},
	"male_masked_hive": {"voice_type": "male", "pitch": 0.76, "speaking_rate": 0.98, "volume": 80, "effect": "alien"},
	"female_hive": {"voice_type": "female", "pitch": 1.16, "speaking_rate": 1.05, "volume": 80, "effect": "alien"},
	"neutral_machine_echo": {"voice_type": "machine", "pitch": 0.72, "speaking_rate": 0.9, "volume": 85, "effect": "robot"},
	"neutral_machine_echo_heavy": {"voice_type": "machine", "pitch": 0.62, "speaking_rate": 0.85, "volume": 90, "effect": "robot"},
	"neutral_machine_echo_command": {"voice_type": "machine", "pitch": 0.58, "speaking_rate": 0.82, "volume": 90, "effect": "robot"},
}
## One character on top of their persona (editable).
const VOICE_PROFILES := {
	"rennick": {"voice_persona_note": "older hauler captain", "pitch": 0.88, "speaking_rate": 0.93},
	"vale": {"voice_persona_note": "station commander", "pitch": 1.04, "speaking_rate": 0.97},
}
## The sounds an effect plays: [before the line, behind it (quiet, looped while speaking), after it] ("" = none).
const VOICE_EFFECT_SOUNDS := {"radio": ["fx_static", "", ""], "robot": ["fx_robot", "fx_hum", "fx_robot"], "alien": ["fx_alien", "", "fx_alien"]}
const TALK_FINISH_WAIT := 1.5               # after you let go of TALK, wait this long at most for the browser's last words
const VOICE_SAME_LINE_GUARD := 0.4            # the same line for the same character within this many seconds is not spoken twice

# ---------------------------------------------------------------- Job AL (v1.5i): GPS (destination list, A -> B route, distance and ETA)
const GPS_ARRIVE := 250.0          # this close, the GPS says you have arrived and clears the destination
const GPS_ROUTE_COLOR := Color(0.35, 0.65, 1.0)   # the blue route line
const GPS_LIST_ROWS := 9           # destinations listed at once on the map (nearest first)
const GPS_MAX_STOPS := 3           # stops a route can hold (the last one is the final destination)

# ---------------------------------------------------------------- Job AK (v1.5h): planet surface terrain and water (scripts/surface.gd)
const TERRAIN_RIDGE_HIGH := 0.55      # ridge share for big-amplitude country (mountains), squared ridges (was 0.8, sharp)
const TERRAIN_RIDGE_LOW := 0.25       # ...for everything else
const TERRAIN_RIDGE_AMP := 700.0      # amplitude from which a biome counts as mountain country
const TERRAIN_PEAK_EASE := 0.85       # above this share of the amplitude, ground rises at under half the rate (broad peaks)
const WATER_GRID := 64                # the sea's grid per tile (64 x 64 quads)
const WATER_WAVE_H := 1.6             # wave height (m) in open water
const WATER_WAVE_SPEED := 1.0
const WATER_FOAM_DEPTH := 7.0         # foam where the sea is shallower than this (m)
const WATER_SHALLOW_DEPTH := 45.0     # shallows turn turquoise above this depth (m)

# ---------------------------------------------------------------- Job AJ (v1.5g): ship scan (tap a ship to target it, tap the target box to scan it)
const SCAN_RANGE := 1500.0            # a ship this close can be scanned
const SCAN_TIME := 1.2                # seconds the scan takes
const SHIP_TAP_STICK := 34.0          # v1.8u: ...inside a stick's side of the screen the tap must be this close (and clear of the stick itself)
const SHIP_BOX := 18.0                # v1.8u: the size of the lock box every ship on screen wears
const SHIP_TAP_RADIUS := 46.0         # a tap this close to a ship on screen targets it
const SCAN_GOODS := ["Water", "Fuel cells", "Ore", "Medical supplies", "Food rations", "Machine parts", "Electronics", "Coolant", "Scrap metal", "Munitions"]
const SCAN_ENEMY_GOODS := {"Savagers": ["Scrap metal", "Stolen goods", "Munitions"], "Cybermorph": ["Nanite slurry", "Data cores"], "Kaijurai": ["Behemoth spores", "Bio-resin"],
	"Phenom": ["Crystal relics", "Void glass"], "Solrath": ["Void ash", "Dark alloy"]}

# ---------------------------------------------------------------- Job AI (v1.5f): missions (scripts/missions.gd)
const MISSION_POINT_DIST := [3200.0, 5200.0]   # a mission point lies this far from the station
const MISSION_ARRIVE := 700.0                   # this close to the point, its wave is there
const MISSION_PLANET_CLEAR := 900.0             # a point keeps this much clear of a planet's surface
const MISSION_GROUP := [3, 3]                   # ships in a wave: [first waves, last wave] (v1.9b: a bounty's last wave = target + BOUNTY_HELPERS)
const BOUNTY_HELPERS := 6
# v11.97 (owner): a bounty is two waypoints, harder by its level (the pilot's rank 1-6): [ships, fighter level] at the
# first point, then at the second (plus the target). Level 2 = elite fighters. Rank 5-6 targets fly a Level 3 ship.
const BOUNTY_WAVES := {1: [[5, 1], [10, 1]], 2: [[10, 1], [15, 1]], 3: [[10, 1], [10, 2]], 4: [[10, 2], [15, 2]], 5: [[15, 2], [20, 2]], 6: [[20, 2], [30, 2]]}
const BOUNTY_BOSS_TIER := {1: 2, 2: 2, 3: 2, 4: 2, 5: 3, 6: 3}
const BOUNTY_POINT_DIST := [9000.0, 14000.0]   # bounty points lie further out than other jobs' (owner: "too close")
const BOUNTY_DIST_PER_RANK := 1500.0           # and further still the higher the level
const BOUNTY_WAVE_LIVE := 15                   # at most this many of a wave at once; the rest jump in as reinforcements
const BOUNTY_REINFORCE_AT := 6                 # reinforcements come when fewer than this are left
# v11.97 (owner): every Level 3 ship fires super missiles and drops mines (they only hit you, never their own side)
const ENEMY_SUPER_EVERY := [9.0, 15.0]
const ENEMY_SUPER_DAMAGE := 60.0
const ENEMY_MINE_EVERY := [10.0, 16.0]
const ENEMY_MINE_DAMAGE := 45.0
const ENEMY_MINE_R := 40.0
const ENEMY_MINE_LIFE := 40.0
const PLATFORM_RADIUS := 70.0                   # v1.9b (owner): every planet's floating docking platform: deck radius (m)
const PLATFORM_ALT := 260.0                     # ... how far over the planet's surface it floats                       # v1.9b (owner): a bounty target never flies alone: at least six of its own wing with it
const MISSION_PAY := {"threats": 900, "escort": 700, "convoy": 1600, "ground": 1400, "outlaws": 600, "land_escort": 1200, "invasion": 3600, "disturbance_ship": 9000, "disturbance_base": 14000}   # v1.7w: "convoy" = the cargo run into the next system
# v1.8m (owner): ground jobs. A strike on the system's planet: fly down into the atmosphere, go to two mission points in
# one sector of the surface and destroy the landing party at each. Paid on the spot when the last one is down.
const MISSION_GROUND_ALT := 220.0               # a ground job's wave waits this high over the ground
const MISSION_GROUND_SPREAD := 1500.0           # its points lie within this of the sector's centre
# v1.8n (owner): enemy mechs on foot. Each wave of a ground job also has Assault Mechs walking the ground under it.
const MISSION_GROUND_MECHS := [1, 2]            # mechs on foot at [the first point, the last point]
const SURFACE_PATROL_SLOT := 2                   # v1.8o: the rival patrol over a planet sector sends soldiers up to this slot
const WALKER_STAND := 7.0                       # m: a mech on foot stands this far over the ground (its middle)
const WALKER_SPEED := 0.45                      # share of its flying speed when it walks
const WALKER_HOLD := 220.0                      # m: this close (flat distance or not) it stops and fires
const WALKER_STRIDE_RATE := 5.0                 # leg swings (rad / s)
const WALKER_STRIDE_DEG := 28.0                 # how far the legs swing at full walk
const MISSION_HARD_MULT := 2.2                  # the ELITE threats job pays this much more
const MISSION_PATROL_SLOT := 3                  # v11.13 (owner: "common soldiers ... should be more elite"): PATROL sends level-3 veterans (was level 1)
const MISSION_HARD_SLOT := 5                    # ...and sends the slot 05 elites
const MISSION_FALLBACK_ENEMIES := ["Kaijurai", "Phenom", "Cybermorph", "Solrath"]   # when nobody raids the owner
const BOUNTY_ALIVE_RANK := 1                    # named pilots of this rank and up are wanted ALIVE (bring them back); below, dead (paid on the spot)
const REP_MISSION := 3.0                        # standing gained with the giver's faction per job done
const CARGO_HOLD := 8                           # pods and crates a ship carries
const ESCORT_HULL := 600.0                      # the escorted freighter's hull
const ESCORT_FIRE := 25.0                       # hull it loses a second per attacker within ESCORT_RANGE
const ESCORT_RANGE := 500.0
const ESCORT_SPEED := 45.0                      # m/s on its run station -> planet
const ESCORT_AMBUSH := 900.0                    # ambush waves appear this far off the freighter
const ESCORT_DOCK := 260.0                      # this close to the planet dock point it has arrived
# v1.7w (owner): the cargo run. The freighter flies from the station to the jump gate (one ambush on the way), jumps
# to the next system, and you follow it through; there it flies from the arrival gate to that system's station with a
# bigger fight on the way. Paid when it docks there. The only job that leaves the system.
const CONVOY_GATE := 220.0                      # this close to the gate, the freighter jumps
const CONVOY_START := 700.0                     # in the next system it comes out this far in front of the arrival gate
const CONVOY_WAVE_AT := [0.5, 0.35]             # how far along each leg its ambush comes
const CONVOY_WAVE_SHIPS := [3, 4]               # ships in each ambush (the second, in the next system, is the battle)
# v1.7x (owner): asteroids made of blocks, for mining. Rock outside, obsidian streaks, gold / diamond in some cores; no
# sand or dirt. Zero gravity: broken blocks drift off, and anything floating past the field's invisible sphere is gone.
const ASTEROIDS_BLOCK := true
const FIELD_ROCKS := 900               # v10.4: more for the bigger fields. v9.0: scenery rocks drawn through a whole field (3 batches; fixed, however big the field)
const FIELD_ROCK_SIZE := [14.0, 260.0]   # their size range (m), most small
const FIELD_THICK := 0.12               # how thick the field is (share of its radius, up and down)
const ASTEROID_BUBBLE := 2500.0         # v9.0: the mineable block asteroids stay within this of you inside the field
const ASTEROID_COUNT := 18                # block asteroids per field (they replace the old round rocks)
const ASTEROID_SIZE := [4, 8]             # blocks across (most are small: the size leans to the low end)
const ASTEROID_BIG := [3, 11]             # [how many big ones, blocks across]
const ASTEROID_CELL := 6.0                # m per block (v1.8d owner: big blocks, like the planet; was 3)
const ASTEROID_TREASURE := {"gold": 0.4, "diamond": 0.15}   # chance an asteroid hides a gold / diamond cluster in its core
# v1.8d (owner): asteroids break like the arcade game: whole -> 2 big pieces -> 4 each -> 4 each -> destroyed.
const ASTEROID_TIER_HP := [150.0, 80.0, 40.0, 16.0]   # damage a piece takes before it splits (laser bolts ~8 each)
const ASTEROID_SPLIT := [2, 4, 4]                     # pieces each tier splits into; the last tier is destroyed
const ASTEROID_OBSIDIAN_TOUGH := 1.5      # an obsidian-heavy piece is tougher: x(1 + this x its obsidian share)
const ASTEROID_MISSILE := {"missile": [160.0, 14.0, 70.0], "heavy": [600.0, 30.0, 260.0]}   # [damage to the piece hit, splash radius m, splash damage at the middle]
const ASTEROID_SPLIT_SPEED := [3.0, 9.0]  # m/s the pieces fly apart
const ASTEROID_PIECES_MAX := 120          # pieces in a field at once (past it a hit piece is destroyed instead of splitting)
const ASTEROID_BOUND := 1.3               # the invisible sphere = field radius x this; pieces and pickups drifting past it are gone
# v1.8f (owner: "a planet like Saturn with rings of asteroids"): Nebulax, a gas giant in a quiet system, has a ring:
# a see-through band you see from far away, and block asteroids in it you can mine (same rules as the fields).
const RINGED_PLANETS := {"nebulax": {"inner": 1.5, "outer": 2.3, "count": 70, "tilt_deg": 14.0, "thick": 40.0,
	"size": [3, 6], "band": Color(0.86, 0.8, 0.68), "treasure": {"gold": 0.5, "diamond": 0.2}}}
# ---------------------------------------------------------------- Job AG (v1.5c): Covenant, Cybermorph, Solrath fighters; Liberator and Imperium rebuilt
# Light, mirrored, levelled copies from the owner's sets (hl_2covenant, hl_Cybermorph, hl_solrath, hl_Liberator, hl_Imperium).
# Fighters only (the owner: ships and battleships matter, not the look-alike missiles and turrets). Nose at -Z, yaw 0.
const COVENANT_FIGHTER_LEN := 11.0
const COVENANT_INTERCEPTOR_LEN := 12.0
const COVENANT_LANCE_LEN := 14.0
const CYBERMORPH_FIGHTER_LEN := 13.0
const CYBERMORPH_STAR_LEN := 10.0
const SOLRATH_BATWING_LEN := 14.0
const SOLRATH_BLADE_LEN := 13.0
const SOLRATH_SPIRE_LEN := 15.0
const LIBERATOR_CROSS_LEN := 9.0
# ---------------------------------------------------------------- Job AC (v1.4y): Kaijurai and Phenom ships
# The owner's Kaijurai and Phenom ship sets (hl_Kaijurai_ship_set, hl_Phenom_ship_set): light, mirrored copies. Every
# one was levelled and checked from above: nose at -Z, so the extra yaw is 0. Names are guesses from the shapes.
const KAIJURAI_DART_LEN := 12.0
const KAIJURAI_HEAVY_LEN := 15.0
const KAIJURAI_GUNSHIP_LEN := 18.0
const PHENOM_FIGHTER_LEN := 12.0
const PHENOM_INTERCEPTOR_LEN := 12.0    # thruster repair: the upright tail cannon was cut off, thrusters from Phenom fighter c grafted on
const PHENOM_SCOUT_LEN := 11.0          # thruster repair, same donor
const PHENOM_HEAVY_LEN := 15.0
const ALIEN_SHIP_YAW := 0.0
# v6.2 (owner, Oct 27): the second Kaijurai set (hl_kaiju_fighter, hl_kdest, hl_kaiju_cat, hl_kdog, hl_kbird). Names are
# guesses from the shapes. Each was checked from above with its yaw: nose up. Creatures and some ships are bigger.
const KAIJURAI_FANG_LEN := 16.0        # hl_kaiju_fighter: wide spiked fighter (lies across: yaw 90)
const KAIJURAI_FANG_YAW := 90.0
const KAIJURAI_RAVAGER_LEN := 140.0     # hl_kdest: the long spined destroyer (its model faces back: yaw 180)
const KAIJURAI_RAVAGER_YAW := 180.0
const KAIJURAI_STALKER_LEN := 95.0     # hl_kaiju_cat: tentacled creature ship
const KAIJURAI_HOUND_LEN := 80.0       # hl_kdog: legged creature ship
const KAIJURAI_REAPER_LEN := 115.0      # hl_kbird: many-tailed creature (lies across: yaw 90)
const KAIJURAI_REAPER_YAW := 90.0
# v6.4 (owner): the kaiju creatures are cruiser / destroyer size and take a lot to bring down, but fly like fighters.
# Come close and their tentacles reach out; each grab tears one thing off: first your shields, then your wings, then you.
# Their fighters fly in packs of at least ten, with lasers and missiles.
const KAIJU_REACH := 45.0          # m past the creature's own size where the tentacles can take you
const KAIJU_WINDUP := 0.7          # s the tentacles stretch out before they grab (time to break away)
const KAIJU_GRAB_EVERY := 2.0      # s between grabs
const KAIJU_PACK := 10             # fighters in a Kaijurai fighter pack
const KAIJU_PACK_SHIPS := ["kaijurai_fang", "kaijurai_dart", "kaijurai_fang", "kaijurai_heavy", "kaijurai_fang", "kaijurai_dart", "kaijurai_fang", "kaijurai_gunship", "kaijurai_fang", "kaijurai_dart"]
const KAIJU_NEST := {   # v10.8 (owner): the carriers in the unknown areas and how many fighters each keeps in the air
	"vessel": {"unit": "kaijurai_hound", "brood": 5},
	"battleship": {"unit": "kaijurai_reaper", "brood": 10},
	"station": {"unit": "kaiju_hive", "brood": 15, "scale": 2.6}}
const NEST_FIGHTERS := ["kaijurai_fang", "kaijurai_dart", "kaijurai_fang", "kaijurai_heavy"]
const NEST_WAKE := 6000.0          # a carrier launches only while you are this close (m)
const NEST_LAUNCH_EVERY := 3.0     # s between launches from one carrier
const NEST_MAX_OUT := 18           # fighters from all the nests in the air at once, at most (phones)
const NEST_HIVE_CHANCE := 0.4      # share of unknown areas that also hold a Kaijurai hive station
const BOARD_BEASTS := {"Kaijurai": [["kaijurai_fang", "kaijurai_stalker"], ["kaijurai_hound", "kaijurai_reaper"]]}   # v12.5 (owner): who guards a boarded ship on foot instead of mechs: [guards, alpha]
const BEAST_LEN := 34.0        # m: a brood beast on a boarded deck (a mech stands about 14 m)
const BEAST_BOSS_LEN := 60.0   # m: the alpha that guards the reactor / bridge
const KAIJU_BIG := ["kaijurai_stalker", "kaijurai_hound", "kaijurai_reaper", "kaijurai_ravager"]
# v6.2 (owner): "the strange tail behind it ... a very strange kind of flow movement": the back of these models waves.
# key: [tail direction in the model's own axes, wave size (share of the model), waves along the body, speed]
const SHIP_FLOW := {
	"kaijurai_stalker": [Vector3(0, 0, 1), 0.06, 5.0, 2.2], "kaijurai_hound": [Vector3(0, 0, 1), 0.04, 4.0, 2.6],
	"kaijurai_reaper": [Vector3(-1, 0, 0), 0.07, 5.5, 1.9], "kaijurai_ravager": [Vector3(0, 0, -1), 0.02, 3.0, 1.4],
	"kaijurai_fang": [Vector3(-1, 0, 0), 0.025, 3.5, 3.0],
}
# which ships fly the patrols of an enemy home system (by the map's role text). The patrol's ships are taken from this
# list in turn. Systems not listed keep sys["enemy"].
const HOME_FLEETS := {
	"Kaijurai home": ["kaijurai_dart", "kaijurai_fang", "kaijurai_heavy", "kaijurai_stalker", "kaijurai_gunship", "kaijurai_reaper", "kaijurai_hound", "kaijurai_ravager"],
	"Gadversee home": ENEMY_SPACE_FLEET,   # v6.2: no ships of their own yet: Kaijurai stand in (owner)
	"Arctides home": ENEMY_SPACE_FLEET,
	"Phenom home": ["phenom_fighter", "phenom_interceptor", "phenom_scout", "phenom_heavy"],
	"Cybermorph home": ["cybermorph_fighter", "cybermorph_star", "cybermorph_fighter", "cybermorph_fighter"],   # v1.5c
	"Solrath home": ["solrath_blade_a", "solrath_blade_b", "solrath_batwing", "solrath_spire"],   # v1.5c
}
# ---------------------------------------------------------------- Job AD (v1.4z): the six enemy casts
# whose people fly the patrols of an enemy home system (by the map's role text). Only factions with a roster AND
# ships in the game are listed; the ship lists above stay as the fallback when no one from the roster can fly.
const HOME_FACTION := {"Kaijurai home": "Kaijurai", "Phenom home": "Phenom", "Cybermorph home": "Cybermorph", "Solrath home": "Solrath"}   # v1.5c: + Cybernet, Void System
# ---------------------------------------------------------------- Job AB (v1.4x): one warp effect, three looks
# gate kind -> look.  tunnel = jump gate (energy tube), cloud = warp gate (gas anomaly), rift = rift gate (a tear in space)
const WARP_SKINS := {"jump": "tunnel", "warp": "cloud", "rift": "rift"}
const WARP_BUILD := {"tunnel": 1.2, "cloud": 2.0, "rift": 3.0}   # v5.7 (owner: too fast, it skipped): longer     # s: slow start, then fast
const WARP_CLEAR := {"tunnel": 0.8, "cloud": 1.2, "rift": 1.1}     # s: ease out on arrival
const WARP_FLASH := {"tunnel": 0.55, "cloud": 0.0, "rift": 0.0}    # white flash on arrival (0 = smooth, no flash)
const WARP_RINGS := {"tunnel": true, "cloud": false, "rift": false} # (v1.9z: a warp gate is a hole in space: no rings) # fly through the gate rings first (the rift just opens)
const WARP_PACE_SLOW := 0.45         # layers passing per second at the start ("slow booms")
const WARP_PACE_FAST := 4.2          # layers passing per second at full speed (held while the next system loads)
const WARP_SPIN_SLOW := 0.15         # turns per second at the start
const WARP_SPIN_FAST := 1.3          # turns per second at full speed
const WARP_BOOM_BELOW := 0.75        # each passing layer makes a boom while the pace is below this share of full speed
const RIFT_STAR_R := 58.0            # v10.9 (owner): the rift gate is a six-pointed star this big (point radius, m) ...
const RIFT_STAR_BAND := 4.5          # ... its frame this thick (v11.7: no frame any more)
const RIFT_CLOTH := 5.0              # v11.7 (owner): the sheet ripples like fabric this far (m)
const RIFT_SPARKS := 140             # v11.7: sparks thrown off its edge
const RIFT_MIST_PUFFS := 28          # v11.7: cloud puffs boiling round it
const RIFT_STAR_GLOW := Color(0.78, 0.55, 1.0)   # the electric violet round it
const RIFT_BOLT_BOW := 0.55          # how far a bolt bows out from its chord (share of its length)
const RIFT_BOLT_RATE := 0.45         # bolts per second per pair of points (each boils up, bows, snaps)
const RIFT_LAYERS := 10              # sheets of sky in the tear (1..12)
const RIFT_OVAL := 1.6               # the tear is this much wider than tall
const RIFT_RAGGED := 0.2             # how torn the edge is (0 = clean oval)
const RIFT_MIST := 0.6               # coloured mist on each tear's edge
const RIFT_TINT_MIN_HUE := 0.12      # two tears in a row differ in hue by at least this
const TUNNEL_WIND := 0.0            # v2.5 (owner, like MvC2's portal): the jump and warp-gate tunnels snake left then right
const TUNNEL_WIND_FREQ := 0.45       # how tight the S bends are (lower = longer, gentler swoops)
const TUNNEL_TWIST := 0.55           # jump tunnel: how much the energy bands corkscrew
const TUNNEL_BANDS := 3.0            # jump tunnel: bands around the tube (whole number)
const CLOUD_LAYERS := 6              # warp-gate anomaly: gas layers rushing past
const WARP_MAX_STEP := 0.05      # v1.5d: the most warp time one frame may advance (a long build frame does not jump the layers)
const WARP_MIN_COLOUR := 0.55       # the effect's main colour is at least this saturated
const WARP_ALPHA := 0.96             # how solid the effect is at full strength
# ---------------------------------------------------------------- Job AA (v1.4w): seven more faction casts
const GUARD_SIZE := 2                # a faction's own guard wing near its main station (factions that have fighters)
const GUARD_DIST := 2400.0   # v11.90: clear of the 4x stations
#           # how far from the station the wing holds
const GUARD_MAX_SLOT := 5            # the faction commander (slot 06) does not fly guard duty
const IMPERIUM_FIGHTER_LEN := 12.0
const IMPERIUM_GUNSHIP_LEN := 16.0
const LIBERATOR_FIGHTER_LEN := 12.0
const LIBERATOR_HEAVY_LEN := 15.0
const LIBERATOR_YAW := 0.0           # v1.5c: the Liberator copies were rebuilt levelled and mirrored, nose at -Z (was 180: the old copies lay tail-first)
const FACTION_FACE_PX := 84          # portrait size in the FACTION page's pilot strip
# what a faction pilot says when you hail them and they are not hostile ({name}, {faction}); placeholder wording until
# the owner writes each character's lines
const ROSTER_HAIL := ["[normal]{name}, {faction} patrol. You are clear, pilot.", "[normal]This is {name}. Keep your weapons cold and fly safe."]

# ---------------------------------------------------------------- Job Z (v1.4v): named stations, three placed models, the fog beacon
const FOG_RADIUS := 700.0            # Foggiest: the grey cloud that wraps Greywhistle Beacon
const FOG_COLOR := Color(0.62, 0.65, 0.7)
# v1.9s (owner: Freelancer-style nebulae): each cloud is hundreds of soft smoke puffs drawn in one batch, real fog inside
# that thickens the deeper you go, smoke streaming past the ship, lightning flashes, and more clouds per system.
const NEBULA_SIZE := 165.0            # v10.4 (owner: "Freelancer clouds were huge"): ~2.3x (main cloud ~150 km across, was ~65). the system's own nebula is this many times its listed radius (v9.0 owner, Freelancer: ~40 km across; was 3.2)
const BELT_CLOUD_OFF := 0.55         # v10.4: the field's cloud sits this share of the field's radius off its middle ...
const BELT_CLOUD_SIZE := 0.75        # ... and is this share of the field's radius
const NEBULA_STATION_GAP := 8000.0   # v10.4: the main station stays this far outside its system's (bigger) cloud
const NEBULA_EXTRA := 5               # extra unnamed clouds in every system, other sizes and colours
const NEBULA_EXTRA_RADIUS := [45000.0, 90000.0]   # v11.97 (owner): bigger. was [32000, 70000];   # v10.4: ~2.5x. v9.1: 1,000 km systems (v8.9: 9-22 km; was 700-1600)
const NEBULA_GATE_RADIUS := [18000.0, 30000.0]   # v10.4: 2x. the cloud a gate hides in (Freelancer: gates in the clouds); one of the extras (v9.0: was 850-1300)
const NEBULA_EXTRA_DIST := [90000.0, 350000.0]   # how far from the main station the extra clouds sit (v9.0: was 2.6-5.8 km)
const NEBULA_AVOID_K := 8.0          # v9.0: the clouds keep this many times their old gaps from stations, planets and the field
const NEBULA_BACKDROPS := 3          # v12.2: huge clouds out past the system edge (backdrop only)
const NEBULA_BACKDROP_R := [160000.0, 260000.0]
const NEBULA_PUFFS := 240             # smoke puffs in a full-size cloud (smaller clouds get fewer)
const NEBULA_PUFF_ALPHA := 0.55
const NEBULA_FOG_DENSITY := 0.005   # (v1.9z: thicker: deep inside you see a few hundred metres, not the other side)    # fog at the heart of a cloud (things ~600 m off fade into the haze)
const NEBULA_STREAM := 40             # smoke puffs streaming past the ship inside a cloud
const NEBULA_STREAM_RANGE := 320.0
const NEBULA_FLASH_EVERY := [2.5, 8.0]  # seconds between lightning flashes in each cloud
# v1.9z (owner: "inside a Freelancer cloud you can't see out; it has its own weather"): deep inside, the fog hides the
# sky completely, and every cloud has its own weather: snow, rain, an electric storm (rain + much more lightning) or a
# rock field (drifting rocks you can hit, with dust).
const NEBULA_WEATHERS := ["snow", "rain", "storm", "rocks"]
const NEBULA_WEATHER_NAME := {"snow": "SNOW", "rain": "RAIN", "storm": "ELECTRIC STORM", "rocks": "ROCK FIELD"}
const NEBULA_WX := 260               # weather flakes / streaks kept round the ship
const NEBULA_WX_RANGE := 80.0
const NEBULA_ROCKS := 140            # rocks in a rock-field cloud and in every main cloud (v10.4: 26 -> 140, in clumps)
const NEBULA_ROCK_CLUMPS := 5        # v10.4: they gather in this many clumps ...
const NEBULA_ROCK_CLUMP_R := 3500.0  # ... about this wide (m)
const NEBULA_ROCK_SIZE := [8.0, 90.0]   # their size range (m), most small (was 6-34)
const NEBULA_STORM_FLASH := [0.8, 2.6]
const DETOUR_PAD := 500.0   # v11.91: m the autopilot keeps round a station in its way
const GATE_GROW := 2.0   # v11.89 (owner): jump, warp and rift gates 2x
const WARP_HOLE_SIZE := 240.0          # v1.9z (owner): the warp gate as a Freelancer-style hole: its size (m)
const WARP_HOLE_SPARKS := 120
const WARP_HOLE_RIM := Color(1.0, 0.45, 0.75)
const WARP_TUNNEL_TINT := Color(1.0, 0.42, 0.82)   # v10.6 (owner: "that amazing pink, alive"): the warp tunnel takes the gate's pink
const WARP_HOLE_CLOUD := Color(0.75, 0.25, 0.6)   # the cloud each warp gate hides in
const JUMP_TUNNEL_SPIN := [0.04, 0.22]   # v1.9z (owner): the jump-gate tunnel (his picture) spins, turns a second slow .. full speed
const NEBULA_MIST := Color(0.93, 0.95, 1.0)   # v6.7 (owner): white mist inside a cloud, like Freelancer
const NEBULA_MIST_MIX := 0.65      # how far toward white (0 = the cloud's own colour)
const NEBULA_DOME_SCALE := 0.55    # the cloud wall's noise is stretched this much (no repeating tiles)
const NEBULA_DOME_CONTRAST := 0.45 # soft billows, not a hard pattern
const NEBULA_STREAM_ALPHA := 0.75  # the smoke rushing past the ship
const NEBULA_DOME_R := 1400.0       # the cloud shell round the camera (beyond it, only haze)
const NEBULA_HUD_TINT := 0.16         # the screen tint inside a cloud (the fog does most of the work now; was 0.36)
const STATION_MODEL_YAW := {"hollow_requiem": 90.0}   # degrees: the dead liner lies across the docking approach

# ---------------------------------------------------------------- Job Y (v1.4u): more room, cleaner prompts, lane tunnel
const SYSTEM_SPREAD := 1.8           # every system: planets, gates, belt, nebula and patrols sit this much farther from the main station (v1.5m: was 1.4)
# v9.0 (owner, Freelancer maps: "use the whole tile"): after SYSTEM_SPREAD each system is fanned out again (same shape, just
# bigger) so its typical object sits about SYSTEM_REACH out; the fan stays between these limits
const SYSTEM_REACH := 230000.0       # v9.0: a typical object (60th percentile) ends up about this far from the main station
const SYSTEM_FAN := [6.0, 120.0]
const SYSTEM_EDGE_SOFT := 380000.0   # past this, places are pulled in toward the centre (they bunch a little near the border)
const FIELD_GROW := 95.0             # v10.4 (owner): ~2.1x (fields ~36 km out from their middle, was ~17). v9.0: asteroid fields grow this much (380 m radius -> ~11 km)
const PLANET_GROW := 8.0             # v10.6 (owner): twice the size again (was 4.0). v9.0: planets grow this much (so they read across a 400 km system)
const SUN_LANE_CLEAR := 3.2         # v10.6 (owner: "the sun is so close to the trade lanes"): the sun keeps this many of its radii from every lane line and place
const SUN_KEEP_OUT := 2.2            # v9.0: nothing is placed within this many sun radii of the sun
const UNKNOWN_STORMS := 6                        # v12.6 (owner): the uncharted areas: big storm clouds ...
const UNKNOWN_STORM_R := [55000.0, 95000.0]
const UNKNOWN_ROCK_FIELDS := 4                   # ... and asteroid-rock clouds (fields to hide in)
const UNKNOWN_ROCK_R := [45000.0, 75000.0]
const UNKNOWN_ALLY_KIND := "cruiser"            # the nearest fleet faction's vessel hiding in a rock cloud there
const UNKNOWN_BELT_K := 1.8                      # their main field is this much bigger
const UNKNOWN_CLOUD_COLORS := [Color(0.55, 0.3, 0.85), Color(0.3, 0.75, 0.7), Color(0.85, 0.4, 0.35), Color(0.4, 0.5, 0.95), Color(0.75, 0.65, 0.3), Color(0.8, 0.35, 0.65)]
const UNKNOWN_CLOUD_WORDS := ["Hollow", "Murk", "Ember", "Gloam", "Thorn", "Wraith", "Pale", "Shiver", "Cinder", "Drowned"]
const UNKNOWN_ORBITS := {"station": 90000.0, "planet": 210000.0, "asteroids": 300000.0, "nebula": 240000.0, "gate": 380000.0, "extra": [140000.0, 400000.0]}   # v9.0 (owner): the unknown areas: the sun in the middle, everything on orbits round it
const DOCK_RANGE_STATION := 190.0    # was 260: you must be this close to a station (or its docking mouth) for DOCK
const DOCK3D_PAD := 450.0   # v12.6: a big 3D station's hull stops you up to ~400 m outside its dock ring from some sides: this much more reach
const DOCK_RANGE_PLANET := 240.0     # was 300: measured from the planet's surface
const LANE_TUNNEL_BACK := 0.42       # share of the lane tunnel's length that trails BEHIND the ship (so the camera never sees its rim)

# ---------------------------------------------------------------- Job X (v1.4t): voice ON by default
const VOICE_DEFAULT := "read"            # "read" = voice ON (lines are spoken), "bleep" = voice OFF (radio blips)
const VOICE_DIR := "res://assets/voices/"   # <voice_id>/<line key>.ogg : a character's recorded or generated lines
const VOICE_KEY_LEN := 60                # letters of the line used for the clip's file name
# v1.8z: who speaks with which cloned voice (folder under VOICE_DIR, one content pack each). Made by
# tools/voices/build_voice_lines.py from art/voices/voice_map.csv; a voice_id not listed keeps its own folder.
const VOICE_POOL := {
	"amari": "v_f3", "arctides_01_ice_guard": "v_mask", "arctides_02_seryn": "v_f1", "arctides_03_kaldren": "v_m1", "arctides_04_lysara": "v_f3",
	"arctides_05_house_warden": "v_mask", "arctides_06_vorstane": "v_m4", "ax01": "v_mask", "ax02": "v_mask", "ax03": "v_mask",
	"ax04": "v_mask", "ax05": "v_mask", "ax06": "v_mask", "banshee": "v_f2", "covenant_01_acolyte": "v_mask",
	"covenant_02_nerea": "v_f2", "covenant_03_kael": "v_m1", "covenant_04_lyra": "v_a2", "covenant_05_hierarch_guard": "v_mask", "covenant_06_selen": "v_m4",
	"cybermorph_01_unit": "v_r1", "cybermorph_02_vx_raid": "v_r1", "cybermorph_03_orion_k": "v_r1", "cybermorph_04_nex_m7": "v_r1", "cybermorph_05_ax9": "v_r1",
	"cybermorph_06_prime_nexus": "v_r1", "elyza_01_soldier": "v_mask", "elyza_02_serin": "v_f1", "elyza_03_cael": "v_m2", "elyza_04_lyra": "v_f3",
	"elyza_05_elite_guard": "v_mask", "elyza_06_aurelia": "v_f4", "gadversee_01_thrall": "v_mask", "gadversee_02_mireya": "v_f2", "gadversee_03_grath": "v_m3",
	"gadversee_04_vesh": "v_a2", "gadversee_05_spore_guard": "v_mask", "gadversee_06_mother": "v_f4", "imperium_01_trooper": "v_mask", "imperium_02_vexa": "v_f1",
	"imperium_03_garrik": "v_m3", "imperium_04_nyx": "v_a2", "imperium_05_dominion_guard": "v_mask", "imperium_06_kraeg": "v_m1", "jackal": "v_f1",
	"kaijurai_01_containment_trooper": "v_mask", "kaijurai_02_zhara": "v_a2", "kaijurai_03_drakk": "v_a1", "kaijurai_04_syrak": "v_f3", "kaijurai_05_cradle_guard": "v_mask",
	"kaijurai_06_vorrax": "v_m4", "kessler": "v_m4", "liberator_01_trooper": "v_mask", "liberator_02_lena": "v_f2", "liberator_03_brok": "v_a1",
	"liberator_04_kai": "v_f3", "liberator_05_vanguard": "v_mask", "liberator_06_marcus": "v_m3", "oduya": "v_f4", "orion_01_survey_trooper": "v_mask",
	"orion_02_ryan": "v_m2", "orion_03_syra": "v_a2", "orion_04_korvax": "v_a1", "orion_05_vanguard": "v_mask", "orion_06_caleb": "v_m4",
	"phenom_01_aurelian_guard": "v_mask", "phenom_02_vyrela": "v_f1", "phenom_03_thalen": "v_m4", "phenom_04_isara": "v_a2", "phenom_05_ascendant_guard": "v_mask",
	"phenom_06_xerathion": "v_m1", "rennick": "v_m3", "revenant": "v_mask", "savagers_01_soldier": "v_mask", "savagers_02_jackal": "v_m2",
	"savagers_03_razor": "v_f1", "savagers_04_veil": "v_f3", "savagers_05_brakk": "v_m1", "savagers_06_dreadmaw": "v_a1", "solarion_01_trooper": "v_mask",
	"solarion_02_lira": "v_f2", "solarion_03_taron": "v_m3", "solarion_04_seraph": "v_f1", "solarion_05_guard": "v_mask", "solarion_06_valen": "v_m1",
	"solrath_01_void_trooper": "v_mask", "solrath_02_velkira": "v_a2", "solrath_03_kharvek": "v_a1", "solrath_04_nyssara": "v_f3", "solrath_05_void_enforcer": "v_mask",
	"solrath_06_azrath": "v_m1", "tutor": "v_f2", "unity_01_trooper": "v_mask", "unity_02_mira": "v_f2", "unity_03_rowan": "v_m2",
	"unity_04_selene": "v_f1", "unity_05_elite_guard": "v_mask", "unity_06_elara": "v_f4", "vale": "v_f4", "voss": "v_m1",
	"wraith": "v_f3",
}

# ---------------------------------------------------------------- Job W (v1.4s): static faction hub backgrounds
# v3.5 (owner): every station room is a 360 panorama you look round in (drag, the right stick, or turn the phone).
# Only factions whose rooms are stitched are listed; the rest keep the station picture for now.
# v3.7 (owner): the station assistant stands in the HOME room (his green-screen clips, keyed in the game). She stays at
# one spot in the 360 room, so she moves when you look round. Tap her to talk; the brain answers (Echo Vision's later).
const ASST_YAW := 0.188         # where she stands along the room loop (the front view's middle)
const ASST_HEIGHT := 0.65       # her height as a share of the screen
const EVEE_VS_MECH := 0.27      # v5.1 (owner): Evee beside a mech reaches a little under its knee
const CALL_FOLD_AFTER := 9.0   # v5.6: s before a greeting folds to its tab
const CALL_FACE := 170.0       # v5.5 (owner): a caller's face is this big everywhere (flight comms and the talk box)
const MAP_CELLS := 10           # v10.3 (owner): 10 x 10, columns A-J, rows 1-10, 100 km a square. v9.0 (owner, Freelancer): the system map is an 8 x 8 grid, columns A-H, rows 1-8
const SYS_MAP_FOG := Color(0.0, 0.0, 0.01, 0.9)    # v9.0: unseen map squares stay dark ...
const SYS_MAP_SEEN := Color(0.07, 0.19, 0.34, 0.9)   # ... the ones you have seen are lit
const FOG_REVEAL := 90000.0      # v9.0: the map squares within this of your ship are uncovered as you fly (fog of war)
const ORIGIN_GRID := 20000.0   # v9.1: the draw shift moves the world in steps of this (m): the ship is drawn within 10 km of zero
const PLACE_EDGE := 0.78   # v11.69 (owner: "nothing in the border squares except asteroids or clouds"): stations, planets and gates stay inside this share of the edge (the outer ring of map squares starts at 0.8)
const SPACE_EDGE := 500000.0   # v9.1 (owner): 1,000 km tile (500 km each way; the draw shift keeps it steady). v8.9: 500 km. v6.2 (owner): each system's space is one tile;
                               # past it you cross into the neighbouring tile of the galaxy board (Pac-Man wrap at the board's edge)
const WARP_GATE_SQUARES := [3, 4]   # v6.5 (owner): how far a warp gate in the unknown reaches (squares, with the wrap)
const RIFT_GATE_SQUARES := [5, 6]   # ... and a rift gate
const RIFT_CLOUD := Color(0.55, 0.25, 0.95)   # v6.5: the purple cloud round a rift gate (in space and on planets)
const PLANET_RIFT_POS := Vector3(1400.0, 0.0, -1400.0)   # where a planet's rift gate stands on its tile (height: above the ground)
const PLANET_RIFT_HEIGHT := 650.0
const ENEMY_SPACE_POWER := 1.6   # v6.2 (owner): enemy space is deadlier: hull, shields, damage and pay x this
const ENEMY_SPACE_GROUPS := 1     # v11.99 (owner): alien space has every patrol wing out (3, not 2)
const ENEMY_SPACE_EXTRA := 2      # ... and one more ship in every patrol
const ENEMY_SPACE_FLEET := ["kaijurai_fang", "kaijurai_stalker", "kaijurai_fang", "kaijurai_hound", "kaijurai_reaper", "kaijurai_ravager"]
const ENEMY_OUTPOST_MODEL := "HL_Station_Kaijurai_Military_retopo"   # v6.2: the outposts in enemy-held squares (Kaijurai stand in for all)   # enemies with no ships of their own fly Kaijurai (owner: placeholders for the rest)
const ROOM_SND_FRONT := 0.75   # v11.9 (owner): a room part's own sound when you face its middle (was 0.5)
const ROOM_SND_SEAM := 0.5     # v11.9 (owner): each of the two at a join (was 0.25); turned out of view = silent
const HUB_MUSIC := 0.1         # v5.9 (owner): the faction's music under the hub, at 10%
const CALL_VOICE_DB := 0.0     # v5.9 (owner): calls (Evee, the station's people) at 100%
const ASST_TOP := 70.0         # v5.7 (owner): her head comes up to just under the menu bar
const ASST_SCREEN_X := 0.42    # where she stands on arrival (v8.5: left of the right-hand panel)
const ASST_KEY := Color(0.08, 0.75, 0.1)   # the green to remove
# v11.14 (owner): a faction's crew stand in its station rooms like Evee (scripts/crew.gd). Clips in
# assets/crew/<faction>/<file>_{idle,talk,walk_fwd,walk_side}.ogv (magenta screen), <file>_greet.mp3, <file>_face.png.
# home = their own room; also = the rooms they visit in turn (they move every CREW_VISIT_S seconds).
const CREW := {
	"orion": [
		{"id": "orion_lyra", "file": "lyra", "name": "Lyra Ashwind", "role": "Mission Officer", "home": "mission_center", "also": ["command", "main_hub"], "female": true,
			"line": "The Imperium moved two wings into Dreadholm. I have work, if you have the nerve."},
		{"id": "orion_sable", "file": "sable", "name": "Sable Venn", "role": "Hangar Pilot", "home": "shipyard", "also": ["pilots_lounge", "mech_dealer"], "female": true,
			"line": "You flew that bucket in here? Fine. Let's make it worth something, pilot."},
		{"id": "orion_iri", "file": "iri", "name": "Iri Valen", "role": "Quartermaster", "home": "supplies", "also": ["medical_bay", "pilots_lounge"], "female": true,
			"line": "Missiles, shields, repair kits. Pay first. Cry later."},
		{"id": "orion_garrick", "file": "garrick", "name": "Garrick Holt", "role": "Armory Sergeant", "home": "weapons", "also": ["main_hub", "pilots_lounge"], "female": false,
			"line": "Pick a gun that fits your hands, not your ego."},
		{"id": "orion_vael", "file": "vael", "name": "Vael Korrin", "role": "Recon Scout", "home": "pilots_lounge", "also": ["main_hub", "shipyard"], "female": false,
			"line": "Back from the deep clouds. Something out there is hiding a lot of guns."},   # v11.25 (owner's new character; name to be confirmed)
	],
}
const CREW_VISIT_S := 600.0         # how often the crew change rooms (s of real time)
const CREW_SCREEN_X := 0.62         # where they stand on arrival (share of the screen, between the page and the calls)
const CREW_HEIGHT := 0.66           # their full-body clip's height (share of the screen)
const CREW_FEET := 0.98             # their feet line (share of the screen)
const CREW_ASPECT := 2.0 / 3.0      # clip width / height
const CREW_BODY_SHARE := 0.9        # v11.60: how much of the clip's height the person fills (head to feet)
const CREW_FOOT_PAD := 0.03         # v11.60: the clip's empty strip under their feet (share of its height)
const CREW_WALK_EVERY := [14.0, 26.0]   # s between their walks to the side
const CREW_WALK_SPAN := 0.035       # how far a walk takes them (share of the loop)
const CREW_WALK_TIME := 4.0         # the side-walk clip's length (s)
const LOC_ROOMS := {"aurelion_aurelioncitadel": ["hangar", "hub", "lounge", "supplies"], "aurelion_aurelionprime": ["hangar", "hub", "lounge", "supplies"], "aurelion_aurelionshipyard": ["hangar", "hub", "lounge", "supplies"], "aurelion_calyx": ["hangar", "hub", "lounge", "supplies"], "aurelion_covenantwatchpost": ["hangar", "hub", "lounge", "supplies"], "aurelion_diplomaticandtradehub": ["hangar", "hub", "lounge", "supplies"], "aurelion_lumen": ["hangar", "hub", "lounge", "supplies"], "aurelion_solarionrelay": ["hangar", "hub", "lounge", "supplies"], "aurelion_thornwild": ["hangar", "hub", "lounge", "supplies"], "aurelion_verdance": ["hangar", "hub", "lounge", "supplies"], "dreadholm_academy": ["hangar", "hub", "lounge", "supplies"], "dreadholm_covenantembassy": ["hangar", "hub", "lounge", "supplies"], "dreadholm_dreadgiant": ["hangar", "hub", "lounge", "supplies"], "dreadholm_munitions": ["hangar", "hub", "lounge", "supplies"], "dreadholm_unitylisteningpost": ["hangar", "hub", "lounge", "supplies"], "dreadholm_vassal": ["hangar", "hub", "lounge", "supplies"], "sepheron_elyzawatchpost": ["hangar", "hub", "lounge", "supplies"], "sepheron_librarystation": ["hangar", "hub", "lounge", "supplies"], "sepheron_orionembassy": ["hangar", "hub", "lounge", "supplies"], "sepheron_sanctorum": ["hangar", "hub", "lounge", "supplies"], "sepheron_sealedvaultstation": ["hangar", "hub", "lounge", "supplies"], "sepheron_sepheron": ["hangar", "hub", "lounge", "supplies"], "sepheron_sepheronobservatory": ["hangar", "hub", "lounge", "supplies"], "sepheron_vaultmoon": ["hangar", "hub", "lounge", "supplies"], "sepheron_veilgiant": ["hangar", "hub", "lounge", "supplies"], "solara_haven": ["hangar", "hub", "lounge", "supplies"], "solara_havenstation": ["hangar", "hub", "lounge", "supplies"], "solara_imperiumwatchpost": ["hangar", "hub", "lounge", "supplies"], "solara_liberatorfreeport": ["hangar", "hub", "lounge", "supplies"], "solara_libertyhub": ["hangar", "hub", "lounge", "supplies"], "solara_newterra": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_brightside": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_datafarm": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_elyzadepot": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_forge": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_grandexchange": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_orionwatchpost": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_portis": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_solgiant": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_synthari": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_syntharimainshipyard": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_synthariresearchlabstation": ["hangar", "hub", "lounge", "supplies"], "synthari_capital_synthariwarpgatehub": ["hangar", "hub", "lounge", "supplies"], "vantara_refugeehavenstation": ["hangar", "hub", "lounge", "supplies"], "vantara_resistanceheadquarters": ["hangar", "hub", "lounge", "supplies"], "vantara_savagerswatchpost": ["hangar", "hub", "lounge", "supplies"], "vantara_unityembassy": ["hangar", "hub", "lounge", "supplies"], "vantara_vantara": ["hangar", "hub", "lounge", "supplies"], "vantara_vantarashipyard": ["hangar", "hub", "lounge", "supplies"], "vega_edenprime": ["hangar", "hub", "lounge", "supplies"], "vega_frontierexchange": ["hangar", "hub", "lounge", "supplies"], "vega_liberatorfreeport": ["hangar", "hub", "lounge", "supplies"], "vega_savagersden": ["hangar", "hub", "lounge", "supplies"], "vega_vegaminor": ["hangar", "hub", "lounge", "supplies"], "veranthos_bastion": ["hangar", "hub", "lounge", "supplies"], "veranthos_concord": ["hangar", "hub", "lounge", "supplies"], "veranthos_customsstation": ["hangar", "hub", "lounge", "supplies"], "veranthos_diplomaticsummitstation": ["hangar", "hub", "lounge", "supplies"], "veranthos_fleetheadquarters": ["hangar", "hub", "lounge", "supplies"], "veranthos_halcyon": ["hangar", "hub", "lounge", "supplies"], "veranthos_imperiumwatchpost": ["hangar", "hub", "lounge", "supplies"], "veranthos_liberatorrelay": ["hangar", "hub", "lounge", "supplies"], "veranthos_meridian": ["hangar", "hub", "lounge", "supplies"], "veranthos_senatestation": ["hangar", "hub", "lounge", "supplies"], "veranthos_veranthosprime": ["hangar", "hub", "lounge", "supplies"]}   # v12.4: a place's own room set (tools/rooms/install_loc.py)
const LOC_ROOM_OF := {"main_hub": "hub", "command": "hub", "mission_center": "hub", "shipyard": "hangar", "mech_dealer": "hangar",
	"supplies": "supplies", "weapons": "supplies", "medical_bay": "supplies", "pilots_lounge": "lounge"}   # v12.4: a game page -> the place's GPT room (private quarters keep the faction room)
const LOC_ROOM_ALIAS := {"vega_vegasecundus": "vega_vegaminor", "aurelion_solarionfreeport": "aurelion_solarionrelay", "synthari_capital_elyzafreeport": "synthari_capital_elyzadepot", "vantara_unityrelay": "vantara_unityembassy"}   # (the checklist's name for a place -> the game's)
const ROOM_FACTIONS := ["liberator", "savagers", "orion", "covenant", "imperium", "solarion", "elyza", "unity"]
const ROOM_OF := {"hub": "main_hub", "ships": "shipyard", "mechs": "mech_dealer", "repair": "medical_bay", "board": "mission_center",
	"missions": "mission_center", "bounty": "mission_center", "ship": "private_quarters", "faction": "command", "surface": "main_hub",
	"lounge": "pilots_lounge", "supplies": "supplies", "command": "command"}   # v9.5: SUPPLIES and COMMAND have their own links
# v11.84 (owner: "Freelancer used GLB characters ... we have them and rigs, we just need a toon shader"): the 3D crowd.
# Per room: count, share walking, and the floor at the back and front of the room as [feet line, body height] in shares
# of the strip's height (read off the picture's own people). Rooms not listed have no 3D crowd.
const CROWD3D_ROOMS := {
	"planet_dreadholm_main_hub": {"count": 22, "walkers": 0.65, "back": [0.66, 0.22], "front": [0.88, 0.44], "crew": "orion"},   # v12.9: Orion's capital: the Orion crew. v12.10 (owner: "match size more accurate"): sizes from the painted people (YOLO, upper fit)
}
const CROWD3D_CREWS := {"orion": {"pack": "crowd3d_orion", "folder": "res://assets/crowd3d_orion", "suffix": "_Rigged", "models": ["HL_Orion_02_WhiteDragonSoldier", "HL_Orion_03_DarkHairedPilot", "HL_Orion_04_LavenderElfOfficer", "HL_Orion_05_BrunetteCommander", "HL_Orion_06_WhiteDragonCommander", "HL_Orion_07_BlondFlightPilot", "HL_Orion_08_LavenderCommandOfficer", "HL_Orion_09_DragonWomanTechnician", "HL_Orion_10_BlondArmoredPilot", "HL_Orion_11_VioletMechTechnician", "HL_Orion_12_FemaleMedic", "HL_Orion_13_MaleMedic", "HL_Orion_14_RedHairedPilot", "HL_Orion_15_DarkHairedArmoredOfficer", "HL_Orion_16_SilverPonytailOfficer", "HL_Orion_17_VioletMissionSpecialist", "HL_Orion_18_MagmaOfficer"]}}   # v12.9: a faction's own crowd (its own pack)
const CROWD3D_TALL := {"WhiteDragonSoldier": 1.06, "DarkHairedPilot": 1.0, "LavenderElfOfficer": 0.93, "BrunetteCommander": 0.93, "WhiteDragonCommander": 0.97,
	"BlondFlightPilot": 1.0, "LavenderCommandOfficer": 0.93, "DragonWomanTechnician": 0.95, "BlondArmoredPilot": 1.0, "VioletMechTechnician": 0.92, "FemaleMedic": 0.93,
	"MaleMedic": 1.0, "RedHairedPilot": 0.92, "DarkHairedArmoredOfficer": 1.0, "SilverPonytailOfficer": 0.93, "VioletMissionSpecialist": 0.93, "MagmaOfficer": 1.02}   # v12.10: real heights (the models all come 1 m tall)
## v12.11: the owner's placements from the Crowd Placer tool (room -> people), and that room's floor size line
## [a, b] (a person's height = a * feet + b, shares of the strip's height). Empty: the random crowd as before.
const DEV_TOOLS := true   # v12.11 (owner: "an editing tool for me ... take it off later before the launch"): Crowd Edit on every room. SET false FOR LAUNCH.
const CROWD3D_PLACED := {}
const CROWD3D_PLACED_FIT := {}
const CROWD3D_MAX_MODELS := 8   # different people drawn in one room at most (each costs 3 small views: phones)
const CROWD3D_WALK := 1.3   # m/s: normal walking speed
const ROOM_FRONT := 0.188       # where the front view's middle sits along the loop (you face it on arrival)
const ROOM_ZOOM := 1.14         # the loop is this much taller than the screen: room to look up and down a little
const ROOM_STICK := 0.09        # share of the loop the right stick turns per second at full tilt
const ROOM_DRIFT := 0.0025      # a slow drift once you leave it alone a while (share per second)
const ROOM_DRIFT_AFTER := 8.0   # s untouched before it drifts
const ROOM_WASH := 0.12         # a light dark wash so the panels read
const BOARD_DRAG_START := 12.0   # v11.3: px a finger moves on a board list before it scrolls instead of tapping
const ROOM_SEAM_PICK := {"unity_main_hub": 0.8363}   # v11.6 (owner): the seam Evee covers, picked by eye (the woman cut in two); other rooms use room_seams.gd's worst
const HUB_BOARD_ASPECT := 1.5   # v11.4 (owner): the MISSION BOARD is a big landscape window, 3 wide for 2 tall
const ASST_ROOM_STAND := {"pilots_lounge": [0.24, 0.93]}   # v11.4 (owner): rooms where everyone sits: Evee's head and feet lines (share of the room picture's height)
const HUB_PANEL_ASPECT := 2.0 / 3.0   # v11.2 (owner): the one panel is a 2 x 3 portrait window (width = height x this)
const HUB_GLASS := Color(0.02, 0.07, 0.15, 0.82)   # v11.11 (owner): darker blue see-through glass (v11.2 light blue was hard to read)
const HUB_DARK_GLASS := Color(0.02, 0.07, 0.14, 0.88)   # v11.11: the call screens
const CALL_PORTRAIT_TALL := 1.25   # v11.11 (owner): the caller's ID portrait, 4 wide for 5 tall
const HUB_PANEL_FRAC := 0.4    # v8.5 (owner, hub spec): the one floating panel on the right takes this share of the width
const ROOM_SPLIT := 0.30        # the left window takes this share of the width; the right window (the page) the rest
const HUB_BG_WASH := 0.38        # dark wash over the faction picture so text reads (0 = none)
const HUB_PANEL_ALPHA := 0.5     # the big content panel: see-through so the faction art stays visible
const HUB_BUTTON_ALPHA := 0.72   # menu and action buttons
const HUB_HEADER_BAND := 0.45    # darkness of the strip behind the title and the credits
# radar: normal range, and zoom-out when you are far from everything
const RADAR_RANGE := 1600.0
const RADAR_OVERVIEW := 6.0   # v1.7o: s the radar stays zoomed out after launching with a job (station, bases, target)
const RADAR_FIT := 1.15               # zoomed out, the farthest place sits this far inside the rim
const RADAR_ZOOM_SPEED := 2.5
# missiles pick a new target when theirs is gone, and firing one wakes the target's wing
const MISSILE_RETARGET := 900.0
const MISSILE_ALERT := 700.0
# galaxy map (flat, fog of war)
const MAP_FOG := Color(0.02, 0.03, 0.06)
const MAP_ZOOM_STEP := 1.6       # v1.9e: each + / - on the galaxy chart zooms this much ...
const MAP_ZOOM_MAX := 10.0       # ... up to this (v10.6: was 5; pinch right in to see a system's star and planets)
const MAP_ORRERY_DETAIL := 260.0  # v10.6: a charted tile at least this wide shows the system itself (star, orbits, planets)
const MAP_BOX_DETAIL := 110.0    # px: a charted tile at least this wide shows its box (counts, station names)

# ---------------------------------------------------------------- Job S (v1.4p): GPS-style navigation map and radar
const NAV_ORIENT_DEFAULT := "north"     # "north" (north-up, never rotates) | "heading" (the map turns round the ship)
const NAV_TILT_DEFAULT := "angled"      # "angled" (GPS tilt) | "flat" (straight down)
const NAV_TILT := 0.454                 # radians the angled view leans back (26 degrees)
const NAV_DEPTH := 2.6                  # angled view: camera distance, x the map's half height (bigger = less depth)
const NAV_GRID_MAJOR_PX := 110.0        # bold grid lines are between this and 5x this apart on screen
const NAV_GRID_ALPHA := [0.62, 0.16, 0.5]   # major lines, faintest minor lines, micro-ticks
const NAV_GRID_WIDTH := [2.0, 1.0]      # major, minor (pixels)
const NAV_GRID_MAX_LINES := 90          # per layer and direction
const NAV_GRID_MAX_TICKS := 1400
const NAV_ZOOM := [0.6, 40.0]           # how far the map zooms out / in (1 = the whole system fits)
const NAV_ZOOM_STEP := 1.5              # one press of + or -, one wheel notch
const NAV_HEADING_ANCHOR := 0.74        # heading-up: the player arrow sits this far down the map
const NAV_HEADING_SPAN := 5200.0        # heading-up: metres across the map at zoom 1
const NAV_HIT_RADIUS := 40.0            # how close a tap must land to pick an object (pixels)
const NAV_TAP_SLOP := 14.0              # a press that moves less than this is a tap, more is a drag
const NAV_ROUTE_WIDTH := 6.0
const NAV_PIN_PULSE := 0.18
const NAV_SIDES := {"planet": 16, "star": 12, "orbit": 18, "ring": 16}   # polygon circles: 12 to 20 straight sides
const NAV_TYPE_PICTURES := {            # info-card picture per type, used when the object has no picture of its own
	"planet": "res://assets/nav/planet.jpg", "moon": "res://assets/nav/moon.jpg", "station": "res://assets/nav/station.jpg",
	"gate": "res://assets/nav/gate.jpg", "warp_gate": "res://assets/nav/warp_gate.jpg", "belt": "res://assets/nav/asteroids.jpg", "nebula": "res://assets/nav/nebula.jpg",
	"star": "res://assets/nav/star.jpg", "enemy": "res://assets/nav/ship_hostile.jpg", "traffic": "res://assets/nav/ship_trader.jpg",
	"ship": "res://assets/nav/ship_friendly.jpg"}
const NAV_STATION_SERVICES := ["Equipment", "Ship Dealer", "Repair / Resupply", "Navigation"]   # a dockable station with no "services" list
const RADAR_HIT_RADIUS := 22.0          # a tap this close to a radar blip picks it
const RADAR_HEADING_ANCHOR := 0.42      # heading-up radar: your arrow sits this far below the centre (x radius)

# ---------------------------------------------------------------- Job Q (v1.4n): comms split, big racks, restock, burst thrust
# comms console: contacts on the right edge, message log on the left edge, the middle of the screen stays clear
const COMMS_PANEL_W := [200.0, 270.0]   # min / max width of each side panel
const COMMS_PANEL_FRAC := 0.21          # of the screen width
const COMMS_ROW_H := 46.0               # one contact row
const COMMS_IDLE_CLOSE := 20.0          # seconds untouched before the console tucks itself away
# every ship carries the same racks
const MISSILE_LOAD := 100
const HEAVY_LOAD := 50
const MINE_LOAD := 20      # v1.9u (owner): at least 20 mines on every ship (was 3-10)
# flight: stick forward builds up to FORWARD_MULT x ship speed (Cadet: 100 m/s); THRUST is an instant burst at
# BURST_MULT x ship speed (Cadet: 120 m/s) in the stick's direction, straight UP with the stick centred
const FORWARD_MULT := 100.0 / 46.0
const FORWARD_RATE := 0.9               # how quickly stick-forward speed builds (lower = more gradual)
const BURST_MULT := 120.0 / 46.0
const BURST_RATE := 9.0                 # how hard a held burst holds its line
# v1.8r (owner): GROUND mode, down on a planet, for the mech and the ship alike. Gravity is on: you come down and stand
# on the ground (no damage: the ship lands as if on wheels). Stick = walk / roll that way, centred = stop. THRUST on the
# ground with the stick centred = a jump; with the stick pushed = a burst that way. In the air THRUST does nothing: you fall.
const GROUND_GRAVITY := 32.0            # m/s2
const GROUND_FALL_MAX := 90.0           # m/s: the fastest it comes down
const GROUND_WALK := 0.5                # share of the ship's speed on the ground
const GROUND_GRIP := 6.0                # how fast it takes the stick's speed on the ground (centred = stops this fast)
const GROUND_AIR_STEER := 1.5           # ...and in the air (a little steering while you fall)
const GROUND_STICK := 6.0                # m: a drop smaller than this underfoot and it stays on the ground (slopes)
const GROUND_JUMP := 40.0               # m/s up
const GROUND_DASH_MULT := 3.2           # a burst: x the ground pace
const GROUND_DASH_TIME := 0.45          # s
const GROUND_THRUST_CD := 0.6           # s between jumps / bursts
const GROUND_THRUST_ENERGY := 18.0      # energy a jump or burst takes
const MECH_BURST_MULT := 3.2            # mech dash (x its walking pace), also used straight up

# ---------------------------------------------------------------- ships
# model: key understood by ShipFactory. "cadet_glb" etc. load real GLBs when present under assets/ships/.
const SHIPS := {
	"cadet": {"name": "Cadet", "class": "Starter fighter", "price": 0, "hull": 100, "shield": 60, "speed": 46.0,
		"turn": 1.7, "guns": 2, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "cadet", "desc": "Unity-issue trainer. Light, nimble, forgiving. Twin cannons on top."},
	"ranger": {"name": "Ranger", "class": "Patrol fighter", "price": 1500, "hull": 160, "shield": 95, "speed": 50.0,
		"turn": 1.55, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "ranger", "desc": "Faster frame, thicker plating. A long cannon on top and one on each wing."},
	"hauler": {"name": "Hauler", "class": "Armed cargo ship", "price": 2500, "hull": 320, "shield": 110, "speed": 38.0,
		"turn": 1.0, "guns": 2, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD + 10, "model": "hauler", "desc": "A cargo ship you can own. The toughest hull on sale, a big rack, and slow."},
	"lancer": {"name": "Lancer", "class": "Heavy fighter", "price": 4000, "hull": 240, "shield": 140, "speed": 42.0,
		"turn": 1.25, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD + 6, "model": "lancer", "desc": "Four cannons: two on the wings, two beside the nose. Heavy shield. Slow to turn."},
	"elyza": {"name": "Elyza Fighter", "class": "Folding-wing fighter", "price": 3500, "hull": 190, "shield": 130, "speed": 50.0,   # v1.5p
		"turn": 1.5, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "elyza_fighter", "desc": "Elyza design. Flies with its armoured arms out; they swing in when it warps."},
	"elyza_starfighter": {"name": "Elyza Starfighter", "class": "Elyza faction fighter", "price": 3400, "hull": 180, "shield": 130, "speed": 52.0,   # v11.32
		"turn": 1.55, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "elyza_starfighter", "faction": "Elyza", "desc": "Elyza faction fighter, from the Elyza fleet sheet. Small and quick."},
	"elyza_fighter_l2": {"name": "Elyza Fighter Mk II", "class": "Elyza Level 2 fighter", "price": 7000, "hull": 360, "shield": 260, "speed": 52.0,   # v11.68
		"turn": 1.45, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "elyza_fighter_l2", "faction": "Elyza", "desc": "Elyza Level 2 fighter, from the owner's fighter sheet. Tougher and better armed."},
	"elyza_fighter_l3": {"name": "Elyza Fighter Mk III", "class": "Elyza Level 3 fighter", "price": 12000, "hull": 540, "shield": 390, "speed": 49.0,   # v11.68
		"turn": 1.3, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD + 2, "mines": MINE_LOAD + 6, "model": "elyza_fighter_l3", "faction": "Elyza", "desc": "Elyza Level 3 heavy fighter, from the owner's fighter sheet. The biggest of the line."},
	"unity_starfighter": {"name": "Unity Starfighter", "class": "Unity faction fighter", "price": 3000, "hull": 190, "shield": 120, "speed": 50.0,   # v11.32
		"turn": 1.5, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "unity_starfighter", "faction": "Unity", "desc": "Unity faction fighter, from the Unity fleet sheet. Small and quick."},
	"unity_fighter_l2": {"name": "Unity Fighter Mk II", "class": "Unity Level 2 fighter", "price": 7000, "hull": 380, "shield": 240, "speed": 52.0,   # v11.68
		"turn": 1.45, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "unity_fighter_l2", "faction": "Unity", "desc": "Unity Level 2 fighter, from the owner's fighter sheet. Tougher and better armed."},
	"unity_fighter_l3": {"name": "Unity Fighter Mk III", "class": "Unity Level 3 fighter", "price": 12000, "hull": 570, "shield": 360, "speed": 49.0,   # v11.68
		"turn": 1.3, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD + 2, "mines": MINE_LOAD + 6, "model": "unity_fighter_l3", "faction": "Unity", "desc": "Unity Level 3 heavy fighter, from the owner's fighter sheet. The biggest of the line."},
	"solarion_starfighter": {"name": "Solarion Starfighter", "class": "Solarion faction fighter", "price": 3600, "hull": 170, "shield": 140, "speed": 53.0,   # v11.32
		"turn": 1.6, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "solarion_starfighter", "faction": "Solarion", "desc": "Solarion faction fighter, from the Solarion fleet sheet. Small and quick."},
	"solarion_fighter_l2": {"name": "Solarion Fighter Mk II", "class": "Solarion Level 2 fighter", "price": 7000, "hull": 340, "shield": 280, "speed": 52.0,   # v11.68
		"turn": 1.45, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "solarion_fighter_l2", "faction": "Solarion", "desc": "Solarion Level 2 fighter, from the owner's fighter sheet. Tougher and better armed."},
	"solarion_fighter_l3": {"name": "Solarion Fighter Mk III", "class": "Solarion Level 3 fighter", "price": 12000, "hull": 510, "shield": 420, "speed": 49.0,   # v11.68
		"turn": 1.3, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD + 2, "mines": MINE_LOAD + 6, "model": "solarion_fighter_l3", "faction": "Solarion", "desc": "Solarion Level 3 heavy fighter, from the owner's fighter sheet. The biggest of the line."},
	"imperium_starfighter": {"name": "Imperium Starfighter", "class": "Imperium faction fighter", "price": 3800, "hull": 220, "shield": 120, "speed": 47.0,   # v11.32
		"turn": 1.4, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "imperium_starfighter", "faction": "Imperium", "desc": "Imperium faction fighter, from the Imperium fleet sheet. Small and quick."},
	"imperium_fighter_l2": {"name": "Imperium Fighter Mk II", "class": "Imperium Level 2 fighter", "price": 7000, "hull": 440, "shield": 240, "speed": 52.0,   # v11.68
		"turn": 1.45, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "imperium_fighter_l2", "faction": "Imperium", "desc": "Imperium Level 2 fighter, from the owner's fighter sheet. Tougher and better armed."},
	"imperium_fighter_l3": {"name": "Imperium Fighter Mk III", "class": "Imperium Level 3 fighter", "price": 12000, "hull": 660, "shield": 360, "speed": 49.0,   # v11.68
		"turn": 1.3, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD + 2, "mines": MINE_LOAD + 6, "model": "imperium_fighter_l3", "faction": "Imperium", "desc": "Imperium Level 3 heavy fighter, from the owner's fighter sheet. The biggest of the line."},
	"covenant_starfighter": {"name": "Covenant Starfighter", "class": "Covenant faction fighter", "price": 3500, "hull": 175, "shield": 145, "speed": 51.0,   # v11.32
		"turn": 1.55, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "covenant_starfighter", "faction": "Covenant", "desc": "Covenant faction fighter, from the Covenant fleet sheet. Small and quick."},
	"covenant_fighter_l2": {"name": "Covenant Fighter Mk II", "class": "Covenant Level 2 fighter", "price": 7000, "hull": 350, "shield": 290, "speed": 52.0,   # v11.68
		"turn": 1.45, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "covenant_fighter_l2", "faction": "Covenant", "desc": "Covenant Level 2 fighter, from the owner's fighter sheet. Tougher and better armed."},
	"covenant_fighter_l3": {"name": "Covenant Fighter Mk III", "class": "Covenant Level 3 fighter", "price": 12000, "hull": 525, "shield": 435, "speed": 49.0,   # v11.68
		"turn": 1.3, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD + 2, "mines": MINE_LOAD + 6, "model": "covenant_fighter_l3", "faction": "Covenant", "desc": "Covenant Level 3 heavy fighter, from the owner's fighter sheet. The biggest of the line."},
	"orion_starfighter": {"name": "Orion Starfighter", "class": "Orion faction fighter", "price": 3300, "hull": 185, "shield": 125, "speed": 50.0,   # v11.32
		"turn": 1.5, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "orion_starfighter", "faction": "Orion", "desc": "Orion faction fighter, from the Orion fleet sheet. Small and quick."},
	"orion_fighter_l2": {"name": "Orion Fighter Mk II", "class": "Orion Level 2 fighter", "price": 7000, "hull": 370, "shield": 250, "speed": 52.0,   # v11.68
		"turn": 1.45, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "orion_fighter_l2", "faction": "Orion", "desc": "Orion Level 2 fighter, from the owner's fighter sheet. Tougher and better armed."},
	"orion_fighter_l3": {"name": "Orion Fighter Mk III", "class": "Orion Level 3 fighter", "price": 12000, "hull": 555, "shield": 375, "speed": 49.0,   # v11.68
		"turn": 1.3, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD + 2, "mines": MINE_LOAD + 6, "model": "orion_fighter_l3", "faction": "Orion", "desc": "Orion Level 3 heavy fighter, from the owner's fighter sheet. The biggest of the line."},
	"savagers_starfighter": {"name": "Savagers Starfighter", "class": "Savagers faction fighter", "price": 2800, "hull": 210, "shield": 90, "speed": 49.0,   # v11.32
		"turn": 1.45, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "savagers_starfighter", "faction": "Savagers", "desc": "Savagers faction fighter, from the Savagers fleet sheet. Small and quick."},
	"savagers_fighter_l2": {"name": "Savagers Fighter Mk II", "class": "Savagers Level 2 fighter", "price": 7000, "hull": 420, "shield": 180, "speed": 52.0,   # v11.68
		"turn": 1.45, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "savagers_fighter_l2", "faction": "Savagers", "desc": "Savagers Level 2 fighter, from the owner's fighter sheet. Tougher and better armed."},
	"savagers_fighter_l3": {"name": "Savagers Fighter Mk III", "class": "Savagers Level 3 fighter", "price": 12000, "hull": 630, "shield": 270, "speed": 49.0,   # v11.68
		"turn": 1.3, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD + 2, "mines": MINE_LOAD + 6, "model": "savagers_fighter_l3", "faction": "Savagers", "desc": "Savagers Level 3 heavy fighter, from the owner's fighter sheet. The biggest of the line."},
	"liberator_starfighter": {"name": "Liberator Starfighter", "class": "Liberator faction fighter", "price": 3200, "hull": 195, "shield": 115, "speed": 51.0,   # v11.32
		"turn": 1.5, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "liberator_starfighter", "faction": "Liberator", "desc": "Liberator faction fighter, from the Liberator fleet sheet. Small and quick."},
	"liberator_fighter_l2": {"name": "Liberator Fighter Mk II", "class": "Liberator Level 2 fighter", "price": 7000, "hull": 390, "shield": 230, "speed": 52.0,   # v11.68
		"turn": 1.45, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": MINE_LOAD, "model": "liberator_fighter_l2", "faction": "Liberator", "desc": "Liberator Level 2 fighter, from the owner's fighter sheet. Tougher and better armed."},
	"liberator_fighter_l3": {"name": "Liberator Fighter Mk III", "class": "Liberator Level 3 fighter", "price": 12000, "hull": 585, "shield": 345, "speed": 49.0,   # v11.68
		"turn": 1.3, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD + 2, "mines": MINE_LOAD + 6, "model": "liberator_fighter_l3", "faction": "Liberator", "desc": "Liberator Level 3 heavy fighter, from the owner's fighter sheet. The biggest of the line."},
}
# v1.3c: all three are the owner's models with weapons mounted (tools/shipkit/make_fleet3.py). Guns = cannons you can see.
const FLEET_FIGHTERS_FOR_SALE := ["elyza_starfighter", "unity_starfighter", "solarion_starfighter", "imperium_starfighter", "covenant_starfighter", "orion_starfighter", "savagers_starfighter", "liberator_starfighter"]   # v11.32
const FLEET_FIGHTERS_L2L3 := ["elyza_fighter_l2", "elyza_fighter_l3", "unity_fighter_l2", "unity_fighter_l3", "solarion_fighter_l2", "solarion_fighter_l3", "imperium_fighter_l2", "imperium_fighter_l3", "covenant_fighter_l2", "covenant_fighter_l3", "orion_fighter_l2", "orion_fighter_l3", "savagers_fighter_l2", "savagers_fighter_l3", "liberator_fighter_l2", "liberator_fighter_l3"]   # v11.68 (owner's fighter sheet: Level 1 is not made yet)
const SHIP_ORDER := ["cadet", "ranger", "hauler", "elyza", "lancer", "elyza_starfighter", "unity_starfighter", "solarion_starfighter", "imperium_starfighter", "covenant_starfighter", "orion_starfighter", "savagers_starfighter", "liberator_starfighter", "elyza_fighter_l2", "elyza_fighter_l3", "unity_fighter_l2", "unity_fighter_l3", "solarion_fighter_l2", "solarion_fighter_l3", "imperium_fighter_l2", "imperium_fighter_l3", "covenant_fighter_l2", "covenant_fighter_l3", "orion_fighter_l2", "orion_fighter_l3", "savagers_fighter_l2", "savagers_fighter_l3", "liberator_fighter_l2", "liberator_fighter_l3"]   # (v11.32: + FLEET_FIGHTERS_FOR_SALE)   # v11.8 (owner): the two freighters are gone (bad designs; the new heavy freighter replaces them)
# v9.8 (owner): the remodelled Cadet's Harrier-style side engines (Nacelle_L / Nacelle_R in the model)
const NACELLE_MIN_SPEED := 4.0     # m/s: below this the engines rest pointing back
const NACELLE_TURN_DEG_S := 220.0  # how fast they swing (degrees per second)

# ---------------------------------------------------------------- weapons (per gun)
const WEAPONS := {
	"pulse1": {"name": "Pulse Laser Mk I", "short": "Pulse I", "model": "wpn_shell_smg", "price": 0, "damage": 8.0, "rate": 4.0, "speed": 420.0, "range": 520.0, "color": Color(0.45, 0.9, 1.0)},
	"pulse2": {"name": "Pulse Laser Mk II", "short": "Pulse II", "model": "wpn_gunnar_rifle", "price": 600, "damage": 12.0, "rate": 4.5, "speed": 440.0, "range": 540.0, "color": Color(0.5, 1.0, 0.8)},
	"ion": {"name": "Ion Repeater", "short": "Ion", "model": "wpn_teal_gatling", "price": 1200, "damage": 9.0, "rate": 7.5, "speed": 470.0, "range": 480.0, "color": Color(0.7, 0.6, 1.0)},
	"plasma": {"name": "Plasma Driver", "short": "Plasma", "model": "wpn_blue_quad_cannon", "price": 2600, "damage": 26.0, "rate": 2.4, "speed": 340.0, "range": 560.0, "color": Color(1.0, 0.6, 0.25)},
	"warden": {"name": "Warden Gun", "short": "Warden", "model": "wpn_warden_gun", "price": 3800, "damage": 18.0, "rate": 3.6, "speed": 460.0, "range": 560.0, "color": Color(1.0, 0.85, 0.45)},
	"bone_rifle": {"name": "Crystal-Bone Rifle", "short": "Bone Rifle", "model": "wpn_crystal_bone_rifle", "price": 5200, "damage": 40.0, "rate": 1.6, "speed": 620.0, "range": 780.0, "color": Color(0.85, 0.95, 1.0)},
	"arm_cannon": {"name": "Mech-Arm Cannon", "short": "Arm Cannon", "model": "wpn_mech_arm_cannon", "price": 7000, "damage": 34.0, "rate": 2.2, "speed": 400.0, "range": 600.0, "color": Color(0.6, 1.0, 0.4)},
	# v1.9h: the owner's rail guns and heavy mounts (hl_wepmount, hl_hevwepm). "heavy" = shoulder mounts only. PROVISIONAL stats.
	"rail_carbine": {"name": "Rail Carbine", "short": "Rail Carb", "model": "wpn_rail_carbine", "price": 2000, "damage": 16.0, "rate": 3.0, "speed": 700.0, "range": 650.0, "color": Color(0.6, 0.85, 1.0)},
	"twin_cannon": {"name": "Twin Cannon", "short": "Twin Cannon", "model": "wpn_twin_cannon", "price": 3200, "damage": 14.0, "rate": 5.0, "speed": 420.0, "range": 520.0, "color": Color(1.0, 0.75, 0.4)},
	"rail_rifle": {"name": "Rail Rifle", "short": "Rail Rifle", "model": "wpn_rail_rifle", "price": 4400, "damage": 30.0, "rate": 1.8, "speed": 760.0, "range": 760.0, "color": Color(0.55, 0.8, 1.0)},
	"charge_cannon": {"name": "Charge Cannon", "short": "Charge Cnn", "model": "wpn_charge_cannon", "price": 4800, "damage": 38.0, "rate": 1.6, "speed": 380.0, "range": 580.0, "color": Color(1.0, 0.5, 0.3)},
	"rail_lance": {"name": "Rail Lance", "short": "Rail Lance", "model": "wpn_rail_lance", "price": 6200, "damage": 52.0, "rate": 1.1, "speed": 820.0, "range": 840.0, "color": Color(0.7, 0.9, 1.0)},
	"hv_cannon": {"name": "Heavy Cannon Turret", "short": "Hvy Cannon", "model": "wpn_hv_cannon_turret", "price": 9000, "damage": 60.0, "rate": 1.4, "speed": 420.0, "range": 640.0, "color": Color(1.0, 0.55, 0.2), "heavy": true, "share": 0.2},
	# v1.9u (owner): the NEXUS PRISM blasters. Five colours, each splits its damage between shield and hull its own way
	# ("shield" = the share that hits the shield; the rest goes straight to the hull, past any shield). Shield damage is
	# lost once the shield is down, so pick the colour for the job. Levels Mk I-V raise damage (BLASTER_LEVEL_DMG each).
	"nx_blue": {"name": "Nexus Blue Shieldbreaker", "short": "NX Blue", "model": "wpn_shell_smg", "price": 700, "damage": 16.0, "rate": 4.0, "speed": 460.0, "range": 560.0, "color": Color(0.3, 0.6, 1.0), "shield": 1.0, "sound": "blaster_blue", "family": "nexus",
		"desc": "Shield only: 100% shield, no hull damage."},
	"nx_green": {"name": "Nexus Green Arc Splitter", "short": "NX Green", "model": "wpn_gunnar_rifle", "price": 800, "damage": 14.0, "rate": 4.2, "speed": 460.0, "range": 560.0, "color": Color(0.3, 1.0, 0.45), "shield": 0.75, "sound": "blaster_green", "family": "nexus",
		"desc": "75% shield, 25% hull."},
	"nx_yellow": {"name": "Nexus Yellow Balancer", "short": "NX Yellow", "model": "wpn_warden_gun", "price": 900, "damage": 13.0, "rate": 4.2, "speed": 460.0, "range": 560.0, "color": Color(1.0, 0.88, 0.25), "shield": 0.5, "sound": "blaster_yellow", "family": "nexus",
		"desc": "50% shield, 50% hull."},
	"nx_red": {"name": "Nexus Red Ripper", "short": "NX Red", "model": "wpn_twin_cannon", "price": 1000, "damage": 14.0, "rate": 4.0, "speed": 460.0, "range": 560.0, "color": Color(1.0, 0.25, 0.2), "shield": 0.25, "sound": "blaster_red", "family": "nexus",
		"desc": "25% shield, 75% hull."},
	"nx_purple": {"name": "Nexus Purple Phase Piercer", "short": "NX Purple", "model": "wpn_rail_carbine", "price": 1400, "damage": 12.0, "rate": 3.6, "speed": 480.0, "range": 580.0, "color": Color(0.75, 0.3, 1.0), "shield": 0.0, "sound": "blaster_purple", "family": "nexus",
		"desc": "Hull only: passes through shields, 100% hull."},
	"hv_rail": {"name": "Heavy Rail Launcher", "short": "Hvy Rail", "model": "wpn_hv_rail_launcher", "price": 11000, "damage": 90.0, "rate": 0.8, "speed": 900.0, "range": 900.0, "color": Color(0.6, 0.9, 1.0), "heavy": true, "share": 0.22},
}
# v1.9g: three more guns from the owner's models (stats PROVISIONAL: CombatEcon will put every gun in its tier table)
# v1.9w (owner's three-level slot sheet): every ship is a LEVEL. Level 1 Core Interceptor: 4 core slots (front gun,
# light missile bay, super missile bay, mine bay), 1 wing slot a side, 2 ability modules. Level 2 Strike Fighter: a
# second front gun (5 core), 2 wing slots a side, 4 modules. Level 3 Capital Variant: a third (belly) gun (6 core),
# 3 wing slots a side, 6 modules. Wing slot ids: 0/1 left inner/tip, 2/3 right inner/tip, 4/5 left/right middle.
# Core ids: -1 front gun, -5 second front gun, -6 belly gun, -2 light bay, -3 super bay, -4 mine bay.
const SHIP_LEVEL := {"cadet": 1, "hauler": 1, "ranger": 2, "elyza": 2, "lancer": 2, "elyza_fighter_l2": 2, "elyza_fighter_l3": 3, "unity_fighter_l2": 2, "unity_fighter_l3": 3, "solarion_fighter_l2": 2, "solarion_fighter_l3": 3, "imperium_fighter_l2": 2, "imperium_fighter_l3": 3, "covenant_fighter_l2": 2, "covenant_fighter_l3": 3, "orion_fighter_l2": 2, "orion_fighter_l3": 3, "savagers_fighter_l2": 2, "savagers_fighter_l3": 3, "liberator_fighter_l2": 2, "liberator_fighter_l3": 3}   # (level 3: the new heavy freighter, when it comes in)
const LEVELS := {
	1: {"name": "Core Interceptor", "art": "res://assets/ui/ship_lv1.png", "icon": "res://assets/ui/ship_lv1.png", "mech_name": "Scout Frame", "mech_art": "res://assets/ui/mech_cut1.png", "mech_icon": "res://assets/ui/mech_lv1.png", "mech_uv": {-1: Vector2(0.503, 0.308), -2: Vector2(0.410, 0.395), -3: Vector2(0.598, 0.395), -4: Vector2(0.503, 0.479), 0: Vector2(0.134, 0.466), 2: Vector2(0.874, 0.466)}, "guns": [-1], "wings": [0, 2], "modules": 2,
		"uv": {-1: Vector2(0.488, 0.362), -2: Vector2(0.371, 0.521), -3: Vector2(0.605, 0.521), -4: Vector2(0.488, 0.67), 0: Vector2(0.163, 0.815), 2: Vector2(0.81, 0.815)}},
	2: {"name": "Strike Fighter", "art": "res://assets/ui/ship_lv2.png", "icon": "res://assets/ui/ship_lv2.png", "mech_name": "Assault Frame", "mech_art": "res://assets/ui/mech_cut2.png", "mech_icon": "res://assets/ui/mech_lv2.png", "mech_uv": {-1: Vector2(0.448, 0.163), -5: Vector2(0.552, 0.163), -2: Vector2(0.390, 0.311), -3: Vector2(0.606, 0.311), -4: Vector2(0.500, 0.423), 0: Vector2(0.169, 0.486), 1: Vector2(0.126, 0.574), 2: Vector2(0.823, 0.486), 3: Vector2(0.866, 0.574)}, "guns": [-1, -5], "wings": [0, 1, 2, 3], "modules": 4,
		"uv": {-1: Vector2(0.435, 0.263), -5: Vector2(0.563, 0.263), -2: Vector2(0.381, 0.509), -3: Vector2(0.616, 0.509), -4: Vector2(0.5, 0.741),
			0: Vector2(0.284, 0.728), 1: Vector2(0.137, 0.824), 2: Vector2(0.719, 0.728), 3: Vector2(0.86, 0.824)}},
	3: {"name": "Capital Variant", "art": "res://assets/ui/ship_lv3.png", "icon": "res://assets/ui/ship_lv3.png", "mech_name": "Heavy Frame", "mech_art": "res://assets/ui/mech_cut3.png", "mech_icon": "res://assets/ui/mech_lv3.png", "mech_uv": {-1: Vector2(0.442, 0.118), -5: Vector2(0.563, 0.118), -2: Vector2(0.358, 0.282), -3: Vector2(0.642, 0.282), -4: Vector2(0.442, 0.477), -6: Vector2(0.563, 0.477), 0: Vector2(0.196, 0.430), 4: Vector2(0.171, 0.511), 1: Vector2(0.148, 0.583), 2: Vector2(0.804, 0.430), 5: Vector2(0.829, 0.511), 3: Vector2(0.857, 0.583)}, "guns": [-1, -5, -6], "wings": [0, 1, 2, 3, 4, 5], "modules": 6,
		"uv": {-1: Vector2(0.49, 0.235), -5: Vector2(0.596, 0.235), -2: Vector2(0.442, 0.546), -3: Vector2(0.65, 0.546), -4: Vector2(0.49, 0.818), -6: Vector2(0.596, 0.818),
			0: Vector2(0.312, 0.715), 4: Vector2(0.246, 0.805), 1: Vector2(0.154, 0.877), 2: Vector2(0.78, 0.715), 5: Vector2(0.848, 0.805), 3: Vector2(0.936, 0.877)}},
}
# v2.7 (owner: no more top view): every hangar is a front view with a round pad; the ship and the mech stand on it and
# turn. Each faction has its own bay; others use the two spares. The number is where the pad's centre sits (share of
# the picture's height from the top).
const BAYS := {"unity": 0.75, "orion": 0.71, "solarion": 0.72, "liberator": 0.69, "imperium": 0.63, "elyza": 0.65,
	"blue": 0.86, "scarlet": 0.92,
	# v3.0 (owner): more station hangars (space outside)
	"arctides": 0.7, "phenom": 0.71, "gadversee": 0.72, "solrath": 0.73, "cybermorph": 0.73, "kaijurai": 0.7,
	# v2.8 (owner): planet hangars (doors open on the world), used when you dock on a planet
	"p_imperium": 0.65, "p_unity": 0.765, "p_orion": 0.71, "p_liberator": 0.69, "p_savagers": 0.69, "p_covenant": 0.72, "p_elyza": 0.66, "p_solarion": 0.73, "p_kaijurai": 0.76, "p_phenom": 0.76, "p_cybermorph": 0.76, "p_arctides": 0.76, "p_solrath": 0.76}
const BAY_SPARES := ["blue", "scarlet"]
const SHIP_ON_PAD := 0.8      # the ship's width as a share of the bay picture's height
const SHIP_BAY_VIEW := Vector3(0.0, 0.22, -1.0)   # v4.5 (owner): the ship on the pad seen front-on (nose to you), a little from above
const MECH_ON_PAD := 0.62     # the mech's height as a share of the bay picture's height
const BAY_SPIN := 0.0          # v3.5 (owner): it stands still; press and drag to turn it (was a slow spin)
const BAY_SPIN_WAIT := 4.0     # s it waits after you drag it or pick a slot
const BAY_TAGS_FACING := 0.93  # the slot name tags show while it faces you (cos of its turn)
const MOUNT_MID_AT := 0.62   # v1.9w: the middle wing slot (level 3) sits this far out along the wing, on top
# v1.9w: ABILITY MODULES (names from the owner's sheet; effects PROVISIONAL). One of each kind at a time.
const MODULE_ORDER := ["power_cell", "shield_generator", "sensor_array", "control_unit", "processor_unit", "maintenance_port", "heat_shield"]
const MODULES := {
	"power_cell": {"name": "Power Cell", "price": 800, "icon": "res://assets/ui/mod_power_cell.png", "energy_regen": 0.3, "desc": "Energy recharges 30% faster."},
	"shield_generator": {"name": "Shield Generator", "price": 1000, "icon": "res://assets/ui/mod_shield_generator.png", "shield": 0.2, "desc": "Shields 20% stronger."},
	"sensor_array": {"name": "Sensor Array", "price": 900, "icon": "res://assets/ui/mod_sensor_array.png", "radar": 0.3, "desc": "Radar reaches 30% farther."},
	"control_unit": {"name": "Control Unit", "price": 1100, "icon": "res://assets/ui/mod_control_unit.png", "turn": 0.15, "desc": "The ship turns 15% faster."},
	"processor_unit": {"name": "Processor Unit", "price": 1200, "icon": "res://assets/ui/mod_processor_unit.png", "lock": 0.25, "desc": "Missiles lock 25% faster."},
	"heat_shield": {"name": "Heat Shield", "price": 6000, "icon": "res://assets/ui/mod_shield_generator.png", "desc": "Special armour: the heat inside a star can't hurt you."},   # v1.9z (owner)
	"maintenance_port": {"name": "Maintenance Port", "price": 1400, "icon": "res://assets/ui/mod_maintenance_port.png", "repair": 0.01, "desc": "Repairs 1% of the hull a second when you are not under fire."},
}
# v2.2 (owner): the shop's weapon pictures, cut from his hangar concept (and his blaster, one per Nexus colour)
const WEAPON_ICON := {"pulse1": "laser_cannon", "pulse2": "beam_laser", "ion": "triple_beam_laser", "plasma": "heavy_cannon",
	"warden": "light_cannon", "bone_rifle": "sniper_railgun", "arm_cannon": "light_cannon", "rail_carbine": "railgun",
	"twin_cannon": "twin_cannon", "rail_rifle": "sniper_railgun", "charge_cannon": "heavy_cannon", "rail_lance": "railgun",
	"hv_cannon": "heavy_cannon", "hv_rail": "dual_railgun", "nx_blue": "nx_blue", "nx_green": "nx_green", "nx_yellow": "nx_yellow",
	"nx_red": "nx_red", "nx_purple": "nx_purple", "missile_pod": "missile_pod", "rocket_rack": "homing_missile_rack",
	"hv_missile_box": "quad_missile_pod", "hv_rocket_arm": "homing_missile_rack", "hv_quad": "quad_missile_pod",
	"light_missile": "missile_pod", "heavy_missile": "homing_missile_rack"}
# v2.2 (owner: "that's a mech rifle"): the mech carries its own weapons, from his mech weapon pictures (his Nexus colours
# included); the ship's Nexus blasters are his concept laser cannon in each colour
const MECH_WEAPON_ICON := {"nx_blue": "coil_blue", "nx_green": "twin_green", "nx_yellow": "rifle_yellow", "nx_red": "blaster_red",
	"nx_purple": "sniper_purple", "pulse1": "cannon_blue", "pulse2": "triple_laser", "ion": "minigun", "plasma": "dish_cannon",
	"warden": "cannon_blue", "bone_rifle": "sniper_rail", "arm_cannon": "dish_cannon", "rail_carbine": "dual_rail",
	"twin_cannon": "dual_rail", "rail_rifle": "sniper_rail", "charge_cannon": "dish_cannon", "rail_lance": "sniper_rail",
	"hv_cannon": "dish_cannon", "hv_rail": "dual_rail", "missile_pod": "missile_rack", "rocket_rack": "missile_rack",
	"hv_missile_box": "quad_missile", "hv_rocket_arm": "missile_rack", "hv_quad": "quad_missile",
	"light_missile": "missile_rack", "heavy_missile": "quad_missile"}
static func weapon_icon(id: String, mech := false) -> String:
	if mech and MECH_WEAPON_ICON.has(id): return "res://assets/ui/mech_weapons/%s.png" % MECH_WEAPON_ICON[id]
	return "res://assets/ui/weapons/%s.png" % WEAPON_ICON[id] if WEAPON_ICON.has(id) else ""
const NEXUS_BLASTERS := ["nx_blue", "nx_green", "nx_yellow", "nx_red", "nx_purple"]   # v1.9u
const BLASTER_LEVELS := 5          # v1.9u: Mk I-V
const BLASTER_LEVEL_DMG := 0.25    # +25% damage per level above Mk I
const BLASTER_UPGRADE_K := 1.0     # upgrading to the next level costs the gun's price x its current level
const WEAPON_ORDER := ["pulse1", "nx_blue", "nx_green", "nx_yellow", "nx_red", "nx_purple", "pulse2", "ion", "rail_carbine", "plasma", "twin_cannon", "warden", "rail_rifle", "charge_cannon", "bone_rifle", "rail_lance", "arm_cannon", "hv_cannon", "hv_rail"]
const WING_GUN_LEN := 2.6        # v1.9g: m, the length the gun models are built at ...
const WING_GUN_SHARE := 0.3      # ... then sized on the wing to this share of the ship's length ...
const WING_POD_SHARE := 0.12     # ... and a missile pod to this
# v1.9e (owner: "equip a weapon on the wing, like a blaster, as well as missiles"): each hardpoint carries a gun or a
# missile pod. A pod on a mount carries more light missiles and adds locks (so a bigger volley). PROVISIONAL numbers.
const MOUNT_SHOULDER_AT := 0.3   # v1.9e (owner): the shoulder mount sits this far out along the wing (share of half the span), on top ...
const MOUNT_TIP_AT := 0.92       # ... the tip mount this far out, underneath ...
const MOUNT_DROP := 0.5          # ... and this far (m) above / below the wing
const MOUNT_PODS := {
	"missile_pod": {"name": "Missile Pod", "short": "Pod", "model": "wpn_missile_pod", "price": 900, "ammo": 6, "locks": 2, "desc": "A wing pod: +6 light missiles carried and +2 locks per volley."},
	# v1.9h: the owner's missile mounts (the rocket rack's loose caps put back on). "heavy" = shoulder mounts only. PROVISIONAL.
	"rocket_rack": {"name": "Rocket Rack", "short": "Rack", "model": "wpn_rocket_rack", "price": 1500, "ammo": 9, "locks": 3},
	"hv_missile_box": {"name": "Heavy Missile Box", "short": "Hvy Box", "model": "wpn_hv_missile_box", "price": 3000, "ammo": 12, "locks": 3, "heavy": true, "share": 0.16},
	"hv_rocket_arm": {"name": "Heavy Rocket Arm", "short": "Hvy Arm", "model": "wpn_hv_rocket_arm", "price": 3600, "ammo": 12, "locks": 4, "heavy": true, "share": 0.17},
	"hv_quad": {"name": "Quad Launcher Turret", "short": "Quad Turret", "model": "wpn_hv_quad_launcher", "price": 5200, "ammo": 16, "locks": 4, "heavy": true, "share": 0.18},
	"hv_missile_turret": {"name": "Missile Turret", "short": "Msl Turret", "model": "wpn_hv_missile_turret", "price": 6000, "ammo": 16, "locks": 5, "heavy": true, "share": 0.18},
}
# v1.9i (owner): mechs are playable AND fought. Every faction has its own mech; a bigger copy is its boss. A mech is
# three parts you swap like a ship's wings: ARMS (both, always a pair), CORE (the upper body) and LEGS (the lower body).
# Buying a frame gives you all three of its parts. Part stats (PROVISIONAL): core "armor" = share of damage it stops
# in mech form, arms "arm" = x gun damage in mech form, legs "speed" = x walking / flying pace in mech form.
# Faction picks are guesses from the colours; the owner decides.
const MECHS := {
	"blackgold": {"name": "Black-Gold Frame", "short": "Black-Gold", "model": "mech_player", "price": 0, "armor": 0.10, "arm": 1.00, "speed": 1.00},
	"tannavy": {"name": "Tan-Navy Assault Frame", "short": "Tan-Navy", "model": "mech_tan", "price": 9000, "armor": 0.14, "arm": 1.05, "speed": 0.95},
	"orange": {"name": "Red-Eye Cannon Frame", "short": "Red-Eye", "model": "mf_orange", "price": 12000, "armor": 0.16, "arm": 1.12, "speed": 0.92},
	"rifle": {"name": "Gatling Rifle Frame", "short": "Gatling", "model": "mf_rifle", "price": 11000, "armor": 0.12, "arm": 1.15, "speed": 0.97},
	"minigun_a": {"name": "White Minigun Frame", "short": "White Gun", "model": "mf_minigun_a", "price": 13000, "armor": 0.18, "arm": 1.10, "speed": 0.90},
	"minigun_b": {"name": "Teal Minigun Frame", "short": "Teal Gun", "model": "mf_minigun_b", "price": 13500, "armor": 0.18, "arm": 1.12, "speed": 0.90},
	"teal": {"name": "Teal Guardian Frame", "short": "Guardian", "model": "mf_teal", "price": 14000, "armor": 0.22, "arm": 1.00, "speed": 0.88},
	"white": {"name": "White Lancer Frame", "short": "Lancer", "model": "mf_white", "price": 15000, "armor": 0.10, "arm": 1.08, "speed": 1.15},
	"headless": {"name": "Headless Frame", "short": "Headless", "model": "mf_headless", "price": 12500, "armor": 0.20, "arm": 1.05, "speed": 0.94},
	"mecblu": {"name": "Blue-White Frame", "short": "Blue-White", "model": "mf_mecblu", "price": 16000, "armor": 0.15, "arm": 1.10, "speed": 1.08},
	"acmec": {"name": "Missile Wing Frame", "short": "Missile Wg", "model": "mf_acmec", "price": 18000, "armor": 0.16, "arm": 1.18, "speed": 1.00},
	"mecbrn": {"name": "Cockpit Brute Frame", "short": "Brute", "model": "mf_mecbrn", "price": 17000, "armor": 0.25, "arm": 1.06, "speed": 0.86},
}
const MECH_ORDER := ["blackgold", "tannavy", "rifle", "orange", "headless", "minigun_a", "minigun_b", "teal", "white", "mecblu", "mecbrn", "acmec"]
const MECH_PART_NAMES := {"arms": "Arms", "core": "Core (upper body)", "legs": "Legs (lower body)"}
const FACTION_MECH := {"Savagers": "orange", "Imperium": "rifle", "Unity": "white", "Liberator": "minigun_a", "Elyza": "mecblu",
	"Covenant": "teal", "Solarion": "mecbrn", "Orion": "minigun_b", "Cybermorph": "headless", "Solrath": "acmec", "Kaijurai": "tannavy"}
const MECH_BOSS_SCALE := 1.8       # a faction's boss mech is its own mech this much bigger ...
const MECH_BOSS_COUNT := 1         # ... and one of the mechs at a ground mission's last point is the boss
## the model key a faction's mechs wear (its own frame, else the tan assault mech)
static func faction_mech_model(faction: String) -> String:
	return str(MECHS[FACTION_MECH.get(faction, "tannavy")]["model"])
# v1.9k (owner): far planets no longer pop; a captured bounty shows the way home; music varies by system and danger
const BOARD_FONT := 20            # v1.9k: mission and bounty board row text
const OBJECTIVE_FONT := 17        # v1.9k: the job line at the top of the flight screen
const OBJECTIVE_TAP_W := 760.0    # its tap area (centred)
const OBJECTIVE_TAP_H := 40.0
const MAN_TIME := 1.1              # v1.9l: a SPECIAL manoeuvre (climb, dive, burst, roll), seconds
const MAN_UTURN_TIME := 0.9        # the U-turn (a second tap in a climb or dive)
const MAN_BOOST := 70.0            # m/s the burst adds
const MAN_PITCH_DEG := 55.0        # how far the nose goes up (down) in a climb (dive)
const MAN_SETTLE := 6.0            # how fast it levels out after
## v1.9m (owner): difficulty tiers, easiest to hardest. The board frames each job's picture (and each bounty face)
## in its tier's colour. A job's tier comes from its pay, so harder, better-paid work shows a higher colour.
const TIER_COLORS := [Color(0.25, 0.55, 1.0), Color(0.25, 0.85, 0.35), Color(1.0, 0.9, 0.2), Color(1.0, 0.55, 0.15), Color(0.95, 0.2, 0.2),
	Color(0.65, 0.3, 0.95), Color(0.04, 0.04, 0.05), Color(0.97, 0.97, 1.0), Color(0.72, 0.75, 0.8), Color(1.0, 0.78, 0.25)]
const TIER_NAMES := ["BLUE", "GREEN", "YELLOW", "ORANGE", "RED", "PURPLE", "BLACK", "WHITE", "SILVER", "GOLD"]
const TIER_PAY_STEP := 400        # each 400 cr of pay = one tier up (1..10)
static func tier_of_pay(pay: int) -> int: return clampi(int(ceil(float(pay) / TIER_PAY_STEP)), 1, TIER_COLORS.size())
## v1.9n (owner): SILVER (tier 9): an enemy faction's fleet invades. 3 heavy battleships (the target), 2 warships, a
## destroyer and a Star Command Station that keeps launching fighters (fewer once it is down). Allies fly with you.
# v11.13 (owner: "too hard, just one battleship"): 1 battleship, no warships or destroyer, 12 fighters (was 3 / 2 / 1 / 20)
const INVASION := {"battleships": 1, "warships": 0, "destroyers": 0, "fighters": 12, "wave": 3, "wave_every": 9.0, "station_down_slow": 3.0,
	"ally_fighters": 6, "ally_frigates": 1, "arrive": 2600.0, "spread": 900.0, "dist": 7000.0}   # dist: how far out from the station the fleet comes in
const INVASION_DRAW := {"fighter": 2200.0, "capital": 9000.0, "lod_bias": 0.5, "capital_lod_bias": 0.08}   # m drawn to; lod_bias < 1 = simpler meshes sooner
const CAPITAL_MISSILE_DAMAGE := 120.0   # a light missile on a capital ship (heavy x3.5; a mine as a heavy)
const CAPITAL_SPECIAL_DAMAGE := 1500.0  # the special beam's hull damage on a capital ship at full charge
const ALLY_FIGHTER := {"hull": 260.0, "speed": 52.0, "turn": 1.4, "damage": 6.0, "rate": 1.5, "range": 460.0, "hit_r": 7.0}
const ALLY_FRIGATE := {"hull": 7000.0, "speed": 8.0, "damage": 10.0, "rate": 2.5, "range": 1300.0, "hit_r": 60.0}
const PRISONER_HOME_STANDING := -70.0   # v1.9o: your standing with a faction after you bring one of theirs home as a prisoner (hostile)
const CHASER_WING := 3                  # the freed pilot comes after you with this many ships in all
const BOLT_HEAD := 7.0            # the glowing head (m; was 5.5): bolts flying straight away from the camera still read
const BOLT_LEN := 30.0            # v10.6 (owner: Freelancer lasers from every gun): a laser bolt's streak (m; was 14)
const BOLT_CORE_W := 0.6
const BOLT_HALO_W := 1.5
const GUN_MEET_K := 0.85           # the guns' streams meet this share of their range ahead (was 0.45, min 250 m) ...
const GUN_MEET_MIN := 600.0
const GUN_MEET_MAX := 1100.0       # ... or at the locked target
const GUN_FLASH_SIZE := 4.6        # each gun's muzzle flash (was 3.2)
const GUN_BEAM_LEN := 70.0        # v10.6: the blink of a beam each gun throws as it fires (m) ...
const GUN_BEAM_W := 0.7
const GUN_BEAM_TIME := 0.09        # ... gone in this long (s)
const CAM_UP := 3.6               # v10.6 (owner: see every gun fire): the chase camera sits this high (was 2.2)
const CAM_SWAY_K := 0.09          # v10.4 (owner): the chase camera trails sliding moves: metres per m/s of climb / slide
const CAM_SWAY_UP := 3.2          # ... at most this far (climbing lifts the ship up the screen, diving drops it)
const CAM_SWAY_SIDE := 2.6        # ... and this far sideways
const CAM_SWAY_EASE := 2.4        # how fast it catches up (per second); level off and the ship settles back
const CAM_PIVOT_UP := 1.2        # v1.9p: the chase camera's line of sight starts this high above the ship (m)
const CAM_PIVOT_UP_MECH := 4.0   # ... and above a mech
const CAM_CLEAR := 1.2           # it stays this far off the ground / a wall
const CAM_CLIP_STEPS := 8        # ground samples along the line
const CAM_FPV_DIST := 3.0        # pulled in closer than this: the ship is hidden (you look from it)
const SPACE_CAM_FAR := 1200000.0    # m: the space camera sees this far (v9.0: the whole 500 km tile; was 32 km)
const PLANET_SHELL_RANGE := 12000.0   # m: past this a planet's haze and cloud shells are not drawn (no depth fight far away)
const EPIC_RANK := 4               # a fight with a pilot of this rank or up (or a boss) plays the EPIC battle music
const BOUNTY_THANKS := "[smile]Great job, {pilot}. {target} is in our cells now. Here's your {pay} credits. We've got plenty of work, so choose another one."
const MISSION_ICON_DIR := "res://assets/missions/"   # <kind>.png (patrol, elite, escort, convoy, ground, land_escort, outlaws); a labelled tile until a picture arrives
const MISSILE_PRICE := 10
const MISSILE_DAMAGE := 45.0 # light missile minimum; it does LIGHT_MISSILE_HULL_FRAC of the target's hull when bigger
const LIGHT_MISSILE_HULL_FRAC := 0.3
const HEAVY_MISSILE_PRICE := 50
const HEAVY_MISSILE_DAMAGE := 120.0
# v1.5w (owner): the SUPER (heavy) missile is the bigger hitter everywhere: a bigger hitbox and a bigger explosion in
# space fights (and a bigger crater in the block ground: BLOCK_BLAST heavy 20 m vs missile 12 m).
const MISSILE_HIT_RADIUS := 9.0        # m: a regular missile goes off this close to its target
const HEAVY_MISSILE_HIT_RADIUS := 14.0 # m: the super missile's bigger hitbox
const BLAST_HEAVY_MISSILE := [30.0, 12, 10, 3, 0.15]   # its explosion ([flash size, fireballs, debris, later pops, gap])
# v1.5x (owner): the super missile hits A LOT harder (one = 3 to 4 regular missiles) and takes much longer to lock
# (you send off 1 or 2). Mines are as strong as a super missile; two kinds, both with a blast radius: BLAST (the
# old one) and MAGNETIC (it pulls the ships it hits in and holds them stuck for a few seconds).
const HEAVY_MISSILE_MULT := 3.5        # a super missile = this many full regular missiles
const HEAVY_LOCK_STEP := 1.6           # s per super-missile lock (v11.12: was 2.5, so four locks build in a fight)
const MAG_MINE_HOLD := 3.5             # s a magnetic mine holds the ships it caught
const MAG_MINE_PULL := 4.0             # how hard it drags them in to the blast point
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
const ATMO_OUTER := 1.15  # planet radius x: outer atmosphere (haze, glow, rumble, surface data starts loading) (v10.6: was 1.3; planets x2, the air keeps its old depth in metres)
const ATMO_INNER := 1.01  # planet radius x: entry sphere (commits to the surface) (v10.6: was 1.02; planets x2, so it stays ~80 m up and the docking band stays clear)
const WARP_EASE := 2.2   # v9.0: the autopilot's warp speed is at most (distance left) / this many seconds
const WARP_MULT := 65.0 # x ship speed (v9.0 owner, Freelancer-size systems: ~3 km/s for the Cadet; was 6)
const THRUST_MULT := 2.0 # afterburner x ship speed
const CRUISE := 0.55     # default cruise (x ship speed) with the left stick centred; full back = stop
# The sun (see docs/DESIGN.md §15): a sphere far out toward the system's edge, with a billboard glow on it.
const SUN_DIST := 80000.0        # from the system centre: far past the gate (~4,200) and everything else
const SUN_RADIUS := 20000.0      # the sphere: ~5x the biggest planet (v9.0: planets grew x3; was 5,500). Touching it destroys the ship
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
	"nuke": {"label": "NUKE", "sub": "", "icon": "heavy"},   # v11.25 (owner): fitted with SELECT (the pause menu)
}
# v11.25 (owner): the NUKE: 3x a super missile's hit, twice its blast, and a second, bigger blast after it.
# v11.26 (owner): INVESTIGATE ENEMY DISTURBANCE: a hidden enemy in one of the system's nebula clouds. Their fighters
# keep coming (topped up to the number) until you destroy the battleship, or the hidden station.
# v11.31 (owner: "not a space station: a big high-level ship, and a cruiser"): "base" is now a FLAGSHIP (a huge
# destroyer) with a CRUISER escort; both must go before the fighters stop. Stand-in models until each faction has its own.
const DISTURBANCE := {"ship": {"capital": "inv_battleship", "role": "battleship", "fighters": 10}, "base": {"capital": "inv_flagship", "role": "flagship", "escort": "inv_warship", "fighters": 15},
	"arrive": 3000.0, "refill_every": 4.0, "wave": 4}
const NUKE_MAX := 50   # v11.33 (owner: "I need fifty nukes")
const NUKE_PRICE := 400               # expensive (a super missile is 50); the hard jobs pay for them
const NUKE_MULT := 3.0
const NUKE_SEEK := 3000.0              # v12.29 (owner: heat-seeking): with no target picked it grabs the nearest ship ahead within this (m) ...
const NUKE_SEEK_CONE := 0.5            # ... inside this cone (cos of the half-angle: 60 degrees)
const NUKE_BLAST_K := 2.0             # x the super missile's blast radius
const NUKE_SECOND := [0.7, 3.0, 1.5]  # the second blast: after s, x the super radius, x the super splash damage
const NUKE_TILES := 6                  # v11.85 (owner): the blast ball is 6 x NUKE_TILES^2 hard square tiles, each a small pyramid point
const NUKE_SMOKE := 10                 # purple smoke puffs inside
const NUKE_ARCS := 6                   # streams of electricity twisting round inside
const NUKE_TURN := PI                  # v11.85 (owner): a slow half turn over the whole blast
const NUKE_SWIRL_R := 4.5              # m: the 4 light streams round a fired nuke
const NUKE_SWIRL_HZ := 2.2             # turns a second
const NUKE_FX_TIMES := [0.5, 1.3, 0.9]   # s: grows to the first blast, grows on to the second, fades out together (still growing)
const NUKE_FX_SIZE := 1.6              # v11.66 (owner: "the nuke needs to be bigger"): the fireball is drawn this much past its blast radius
const FX_SPARKS := 70                  # v11.66 (owner: "sparks, particles, amazing effects"): per normal ship blast (more for big ones)
const FX_EMBERS := 36
const FX_SMOKE := 10
const FX_DEBRIS := 14
const FX_FIRE := 18                    # v11.67 (owner, Freelancer): fire puffs in the billowing fireball
const FX_LIGHTS := 3                   # quick explosion lights alive at once
const FX_PIECES := 4                   # burning pieces a ship breaks into
const FX_PIECE_LIFE := [1.6, 3.2]      # s each piece tumbles and burns before it pops
const FX_BURST_MAX := 8                # bursts alive at once (phones)
const FX_BURST_RANGE := 6000.0         # m: only bursts this close are made (x the blast size)
const BLAST_NUKE := [80.0, 26, 22, 6, 0.12]
const BLAST_NUKE_2 := [140.0, 34, 28, 8, 0.1]
const MINES_MAX := 50                 # v11.25 (owner): every ship carries 30 mines; v11.33 (owner): fifty
const DEFAULT_SLOTS := ["light_missile", "heavy_missile", "mine"]
# Loot pods dropped by destroyed ships; the tractor beam pulls them in.
# Three-part damage: each side section (wing / arm) has this share of the unit's hull as its own health.
const SECTION_SHARE := 0.4
const LOOT_RANGE := 700.0
const TRACTOR_TIME := 4.0
# v6.9 (owner): the SPECIAL is now an electric storm: every hostile in tractor range is shocked: shields gone, frozen in
# place for a few seconds, and hit about as hard as a heavy (super) missile. Same rules for when it is ready (half hull,
# then critical); until then a tap is still an evasive move.
const RADAR_HEADING_UP := true      # v6.9 (owner: why is it pointing down?): the radar turns round you; you always point up
const CLOAK_DRAIN := 7.0            # v8.3 (owner): energy per second while cloaked (it drops when the power runs out)
const CLOAK_ZAP := 1.4             # v10.6 (owner): seconds of electric crackle round the ship as the cloak comes on (and off)
const CLOAK_COCKPIT_ALPHA := 0.5   # v11.49 (owner): the cockpit view while cloaked: half see-through, ice-blue
const CLOAK_RADAR := 0.3            # v10.6 (owner: "it's draining your radar"): the radar shows only this share of its range while cloaked
const CLOAK_ALPHA := 0.82            # v8.3: how see-through the ship goes
const ROLL_DEFLECT := true           # v8.3 (owner, Star Fox): a barrel roll knocks incoming fire away
const SUPER_FROM_DEALT := 1800.0     # v7.5 (owner): damage you deal that fills the super meter once
const SUPER_FROM_TAKEN := 450.0      # v7.5: damage you take that fills it once (fighting back pays more than soaking)
const LIGHTNING_RANGE_MULT := 1.0    # x the tractor's reach (Data.LOOT_RANGE)
const LIGHTNING_STUN := 3.0          # s frozen, shields down
const LIGHTNING_DAMAGE := 120.0      # = HEAVY_MISSILE_DAMAGE
const LIGHTNING_COLOR := Color(0.6, 0.85, 1.0)
const REPAIR_AMOUNT := 0.4 # fraction of max hull

# ---------------------------------------------------------------- Job U (v1.4q): the true Savagers ships
# length in metres and the turn (degrees) that points each model's nose at -Z like every other ship
const SAVAGER_SKIRMISH_LEN := 11.0
const SAVAGER_SKIRMISH_YAW := 180.0   # v1.4s: the mirrored copy is straight
const SAVAGER_GUNBOAT_LEN := 13.0
const SAVAGER_GUNBOAT_YAW := 180.0
const SAVAGER_CARRIER_LEN := 130.0
const SAVAGER_CARRIER_YAW := 180.0
const SCRAPFANG_LEN := 9.0
const REDCLAW_LEN := 11.0
const IRONHOWL_LEN := 14.0
const WARBOAR_LEN := 18.0
const SAVAGER_CRUISER_LEN := 40.0
const SAVAGER_CRUISER_YAW := 180.0
# ---------------------------------------------------------------- v11.32 (owner: "the battleships were a success ... the
# little ships are great. Separate them under the names, put them in the game, sell the little ships as faction fighters")
# The all-factions flagship sheet (HL_AllFactions_FlagshipSheet_v1, split by tools/assetkit): per faction a battleship,
# a cruiser and a frigate (Elyza: no frigate on the sheet) and a starfighter. Faction names are a guess from the colours.
const FLEET_BATTLESHIP_LEN := 1360.0   # v11.89 (owner): battleships 4x (was 340)
#   # m (v11.36 owner: "only as big as a station": = STATION_WIDTH)
const FLEET_CRUISER_LEN := 360.0   # v11.89 (owner): the other capital vessels 3x (was 120)
const FLEET_FRIGATE_LEN := 186.0   # v11.89: 3x (was 62)
const FLEET_STARFIGHTER_LEN := 11.0
const FLEET_YAW := 0.0                 # the light copies already face -Z (top views checked)
const FLEET_STARFIGHTER_YAW := 0.0
const FLEET_LAUNCH_MIX := {"battleship": [0.4, 0.35, 0.25], "cruiser": [0.6, 0.4, 0.0], "frigate": [1.0, 0.0, 0.0]}   # v11.68: share of starfighter / Level 2 / Level 3 a carrier launches
const HOME_BATTLESHIPS := 3   # v11.87 (owner): battleships patrolling a faction's home system (every other system: 1)
const FACTION_FLEET := {
	"Elyza": {"battleship": "elyza_battleship", "cruiser": "elyza_cruiser", "frigate": "", "starfighter": "elyza_starfighter", "fighter_l2": "elyza_fighter_l2", "fighter_l3": "elyza_fighter_l3"},
	"Unity": {"battleship": "unity_battleship", "cruiser": "unity_cruiser", "frigate": "unity_frigate", "starfighter": "unity_starfighter", "fighter_l2": "unity_fighter_l2", "fighter_l3": "unity_fighter_l3"},
	"Solarion": {"battleship": "solarion_battleship", "cruiser": "solarion_cruiser", "frigate": "solarion_frigate", "starfighter": "solarion_starfighter", "fighter_l2": "solarion_fighter_l2", "fighter_l3": "solarion_fighter_l3"},
	"Imperium": {"battleship": "imperium_battleship", "cruiser": "imperium_cruiser", "frigate": "imperium_frigate", "starfighter": "imperium_starfighter", "fighter_l2": "imperium_fighter_l2", "fighter_l3": "imperium_fighter_l3"},
	"Covenant": {"battleship": "covenant_battleship", "cruiser": "covenant_cruiser", "frigate": "covenant_frigate", "starfighter": "covenant_starfighter", "fighter_l2": "covenant_fighter_l2", "fighter_l3": "covenant_fighter_l3"},
	"Orion": {"battleship": "orion_battleship", "cruiser": "orion_cruiser", "frigate": "orion_frigate", "starfighter": "orion_starfighter", "fighter_l2": "orion_fighter_l2", "fighter_l3": "orion_fighter_l3"},
	"Savagers": {"battleship": "savagers_battleship", "cruiser": "savagers_cruiser", "frigate": "savagers_frigate", "starfighter": "savagers_starfighter", "fighter_l2": "savagers_fighter_l2", "fighter_l3": "savagers_fighter_l3"},
	"Liberator": {"battleship": "liberator_battleship", "cruiser": "liberator_cruiser", "frigate": "liberator_frigate", "starfighter": "liberator_starfighter", "fighter_l2": "liberator_fighter_l2", "fighter_l3": "liberator_fighter_l3"},
}
# v11.33 (owner: "it should only take like 35 nukes to blow up one of those battleships; they carry 90 fighters but
# only 15 at a time, to prevent lag; once those are gone, or the battleship is, no more come out; a cruiser holds 30"):
# [fighters carried, most out at once]; nukes = how many direct nuke hits destroy it (its whole hull and shield).
const FLEET_CARRIER := {"battleship": [90, 15], "cruiser": [30, 5], "frigate": [0, 0]}   # (v11.38 owner: a cruiser launches 5 at a time)
# v11.38 (owner: battleships out on patrol in the star systems): each system of a fleet faction has its battleship and
# cruiser out, this far from the station (m), each on its own loop of this radius; peaceful unless provoked or your
# standing with the faction is orange / red. They replace the capital's looping display fleet (FLEET_GUARD_ON).
const FLEET_PATROL_AT := {"battleship": 12800.0, "cruiser": 7800.0}   # v11.89: 4x / 3x with the ships
const FLEET_PATROL_LOOP := {"battleship": 5600.0, "cruiser": 2700.0}
const FLEET_GUARD_ON := false
# v11.42 (owner: "I want to go inside the battleship as a mech"): BOARDING. A boardable faction's battleship has parts
# you can shoot off: the SHIELD TOWER on top (its power: down = the shield is off and the open side hangar lets you in),
# the BRIDGE at the front (down = it stops moving) and the TURRETS on its back (all down = its guns stop). With the
# shield down, fly into the side hangar as a MECH: inside (scripts/boarding.gd) their mechs come three at a time, ten
# in all, then the boss; grab the bounty it drops, blow the reactor core (= the battleship is destroyed, like the 35
# nukes) and get out through the hangar before the countdown ends. Solarion first (the owner is in their space).
const BOARDABLE := ["Elyza", "Unity", "Solarion", "Imperium", "Covenant", "Orion", "Savagers", "Liberator"]   # (owner, by voice: "now we could do everyone": every fleet faction; one shared inside in its own colours and mechs)
const BOARD_BAY_REACH := 360.0   # v11.89: 4x with the battleship
#         # m from the side hangar's opening: in you go (as a mech)
const BOARD_MECHS := [3, 10]           # [most at once, in all]
const BOARD_ESCAPE := 90.0             # s to get out after the core blows
const BOARD_PAY := 9000                # cr for the battleship (v11.70: paid once the wave outside is down)
const BOARD_WAVE := 20                 # v11.70 (owner): the ships waiting outside when you get out
const BOARD_WAVE_AT := [1800.0, 3200.0]   # m from you
const BOARD_BOUNTY_PAY := 3000         # cr for the bounty pilot
const BOARD_GRAB := 26.0               # m: walk the mech up to the bounty pilot to take him
const BOARD_PARTS := {   # part: [enemy kind, where on the hull (x: -1 port .. 1 starboard, y: -1 keel .. 1 top, z: -1 nose .. 1 tail)]
	"tower": ["ship_tower", Vector3(0.0, 1.0, 0.1)],
	"bridge": ["ship_bridge", Vector3(0.0, 0.35, -0.82)],
	"turret_l": ["ship_turret", Vector3(-0.75, 0.75, -0.3)],
	"turret_r": ["ship_turret", Vector3(0.75, 0.75, -0.3)],
}
const BOARD_BAY_AT := Vector3(1.0, 0.0, 0.15)   # the open side hangar (starboard, amidships)

# v11.41 (owner: rival battleships that see each other fight, the fighters swarm out, only while you are near enough to
# see it, "that's how we prevent lag"): in a fleet faction's system (not its capital) the rival's battleship raids now
# and then; seen within FLEET_CLASH_SIGHT of each other while you are within FLEET_CLASH_WATCH, they close to
# FLEET_CLASH_RANGE and trade fire, and launch fighters (the same hangars: 15 out of 90) that dogfight each other.
const FLEET_CLASH_CHANCE := 0.35
const FLEET_CLASH_APART := 16800.0   # v11.89: 4x
#     # m between the two loops' centres
const FLEET_CLASH_SIGHT := 6000.0      # m: the battleships see each other
const FLEET_CLASH_WATCH := 9000.0      # m: you must be this close for the battle to run (out of sight it holds still)
const FLEET_CLASH_RANGE := 1300.0      # m: they close to this and hold, trading fire
const FLEET_CLASH_SPEED_K := 2.0       # x their patrol speed while closing
const FLEET_CLASH_DMG_K := 1.5         # x a turret shot, battleship on battleship (a battle lasts a few minutes)
const FLEET_NPC_HIT := 0.55            # a fighter's shot at a rival ship lands this often
const FLEET_NUKES_TO_KILL := {"battleship": 35, "cruiser": 15, "frigate": 6}
const FLEET_LAUNCH_EVERY := 1.6        # s between launches from one carrier
const FLEET_LAUNCH_WAKE := 9000.0      # m: they launch once you are this close (and fly home when you are further)
const FLEET_LAND_GAP := 60.0           # m from the hull: a fighter flying home lands (v11.39)
# Each faction's battleship (with its cruiser, frigate and two starfighters) patrols round the main station of the
# faction's capital system, not hostile; scan it and 3D VIEW it. They follow one loop, one behind the other.
const FLEET_GUARD_ORBIT := 2600.0      # m from the station
const FLEET_GUARD_SPEED := 30.0        # m/s
const FLEET_GUARD_GAP := [0.0, 0.12, 0.18, 0.01, 0.01]   # radians behind the battleship: battleship, cruiser, frigate, fighters
const FLEET_GUARD_SIDE := [0.0, 0.0, 0.0, 170.0, -170.0]  # m out (+) or in (-) from the loop (the fighters fly beside the battleship)
# ---------------------------------------------------------------- Job V (v1.4r): faction population + reputation
# Faction rosters (data only; the faction records themselves are in scripts/factions.gd).
# THE RULE for every roster (each faction, later each star system or planet): six characters in slots 1..6, and the
# higher the slot the stronger: a better fighter, tougher, harder guns, a little faster, bigger reward.
# Slot 01 is the common soldier (many at once). Slots 02..06 are NAMED, persistent people: never two of the same one at
# once. "bounty": true = can be hunted from a station's BOUNTY board; "sys" = where that bounty hides.
# Source of truth for the Savagers: the owner's "SAVAGERS - Faction Roster, Voice Personas & Fighter Assignments v1".
# Sex, species, name, voice and ship come from THIS data, never from the picture. Voice chat is not built yet: the
# voice_* / *_emotion fields are kept ready for it.
const RANK_HULL_STEP := 0.3      # hull, wings and shield: x (1 + step x (rank - 1))
const RANK_DAMAGE_STEP := 0.18   # gun damage
const RANK_SPEED_STEP := 0.03    # top speed
const RANK_REWARD_STEP := 0.5    # kill reward
const BOUNTY_REWARD := 600       # paid on return: this x rank
const ALT_FIGHTER_CHANCE := 0.25 # how often a character flies an alternate fighter instead of the primary one
const ROSTER_PATROL_SIZE := 2    # ships per patrol in a roster faction's own space (other space keeps 2)
const INCURSION_CHANCE := 0.4    # per visit to a rival's system: one small raiding party is there
const INCURSION_SIZE := 2
const INCURSION_NAMED_CHANCE := 0.15   # that the party is led by slot 02 instead of two common soldiers
const BOUNTY_FACE_PX := 112       # portrait size on the bounty board
const PILOT_POD_LIFE := 100000.0  # a captured-pilot pod never times out
# reputation: one number per rival pair (-100 .. +100). A faction's standing = its base + its side of that number.
const REP_BANDS := [["purple", 75.0], ["blue", 40.0], ["green", 5.0], ["yellow", -20.0], ["orange", -60.0], ["red", -1000.0]]   # standing at or above
const REP_INFO := {
	"purple": {"name": "TRUSTED", "color": Color(0.7, 0.45, 1.0), "hostile": false, "note": "Allied. Best support and access; may fight beside you."},
	"blue": {"name": "FRIENDLY", "color": Color(0.35, 0.65, 1.0), "hostile": false, "note": "Welcomes you. Good mission access."},
	"green": {"name": "ACCEPTED", "color": Color(0.4, 0.95, 0.55), "hostile": false, "note": "Peaceful. Normal access."},
	"yellow": {"name": "CAUTIOUS", "color": Color(1.0, 0.9, 0.35), "hostile": false, "note": "Watching you. Will warn, will not attack on sight."},
	"orange": {"name": "HOSTILE", "color": Color(1.0, 0.6, 0.2), "hostile": true, "note": "Patrols attack on sight."},
	"red": {"name": "HUNTED", "color": Color(1.0, 0.3, 0.25), "hostile": true, "note": "Attacks on sight and sends hunters when you enter their space."},
	"gray": {"name": "ENEMY", "color": Color(0.62, 0.64, 0.68), "hostile": true, "note": "Permanent enemy. No diplomacy."},
}
const REP_LIMIT := 100.0
const REP_REPAIR_UNTIL := 5.0     # v11.55 (owner): Repair Reputation at an ally station lifts you back to this (green), no further
const REP_REPAIR_STEP := 10.0     # standing gained per repair
const REP_REPAIR_BASE := 1500.0   # credits for one step at the green line ...
const REP_REPAIR_SCALE := 40.0    # ... and +100 % for every this many points below it
const REP_KILL := 1.5            # standing lost with a faction per ship of theirs you destroy, x the pilot's rank
const REP_BOUNTY := 6.0          # extra standing lost when you hand in one of their named pilots
const REP_RIVAL_SHARE := 1.0     # the rival gains this share of what the faction lost (one shared number per pair)
const REP_HUNTER_SIZE := 3       # RED: a hunter group this big meets you when you enter their space
const REP_HUNTER_DIST := 1100.0
# stations and the light beacon
const STATION_MODEL_SCALE := {"savagers_cross_station": 1.45, "worlds_end_emporium": 1.6, "hollow_requiem": 2.2}   # x the standard station width
# v1.9d Station3D-Retopo v1: the owner's 3D stations (assets/stations3d/<key>.glb with _lod1 / _lod2, one pack each,
# fetched when you enter the system). System -> {catalog station name: model key}; "*" = the system's main station.
# Aurelion and Veranthos keep their station slots; neutral ones are each system's own station; the Living Asteroid
# Base is the Savagers' Raider Outpost (Ravage Major: "built on a chunk of a cracked moon"). Ogden's trading post
# file has not arrived yet, so Ogden keeps its stand-in.
const STATION3D := {
	# (owner: capitals have 2 stations: the Shipyard, Diplomatic Summit and Customs models are kept in art/stations3d)
	"aurelion": {"*": "st3d_aurelion_citadel", "Diplomatic and Trade Hub": "st3d_aurelion_tradehub"},
	"veranthos": {"*": "st3d_veranthos_senate", "Fleet Headquarters": "st3d_veranthos_fleethq"},
	"voidtex": {"*": "st3d_voidtex_crosswind"}, "beta_7": {"*": "st3d_beta7_pathfinder"}, "perimeter": {"*": "st3d_perimeter_picket"},
	"sigma_19": {"*": "st3d_sigma19_deepcut"}, "omega": {"*": "st3d_omega_emporium"}, "foggiest": {"*": "st3d_foggiest_greywhistle"},
	"radiant": {"*": "st3d_radiant_dawnchoir"}, "ravage_major": {"*": "st3d_savagers_asteroid"},
}
const STATION3D_ROAMERS := {"cybernet": [["st3d_cyber_hexdominator", "Hexdominator"], ["st3d_cyber_shardstorm", "Shardstorm"]]}   # roaming Cybermorph battleships: [model key, name]
const STATION3D_SCALE := {"st3d_aurelion_citadel": 1.6, "st3d_veranthos_senate": 1.6, "st3d_veranthos_summit": 1.6}   # (v11.90: every station is 4x now, STATION_GROW)   # x the standard station width (PROVISIONAL; others 1.0)
const STATION3D_DEFAULT_YAW := 180.0  # the file's front (-Z) turned to face the docking approach (+Z)
const STATION3D_YAW := {}             # per-model exceptions (degrees)
const STATION3D_LOD := [10400.0, 28000.0]   # m: LOD0 out to this, LOD1 out to the next, LOD2 beyond
const STATION3D_HIT := 0.42           # bump sphere radius = this x the station's width (a simple collision hull)
const ROAMER_ORBIT := 1700.0          # m: the roaming battleships loop round the main station this far out ...
const ROAMER_SPEED := 22.0            # ... at this speed (m/s) ...
const ROAMER_BOB := 120.0             # ... rising and falling this much
const ROAMER_SCALE := 1.4             # x the standard station width
# v1.9q RETOPO import (owner, Oct 24): 38 stations (12k tris) and 15 planetary buildings (8k tris), static PBR GLBs with
# their file names kept as delivered: assets/stations3d/HL_Station_<Faction>_<Style>_retopo.glb (one pack each, fetched
# when you enter the system) and assets/buildings3d/HL_<Faction>_<CommandCenter|Hangar>_v01_retopo.glb (one pack per
# faction). Textures are imported at 1024 px for phones (the files themselves are untouched).
# Placed by style: Capital = the faction's homeworld (its main station), Military = a frontline / defence system,
# Trade = a hub system, Outpost = a fringe system. Applied after STATION3D, so it wins where both name a slot.
# System -> {"*": main station | catalog station name: second station | "+Name": a station added to the system}.
const RETOPO_STATIONS := {
	"sepheron": {"*": "HL_Station_Covenant_Capital_retopo"},          # Covenant capital
	"valdris": {"*": "HL_Station_Covenant_Military_retopo"},          # borders the Phenom home and Imperium
	"sanctum_major": {"*": "HL_Station_Covenant_Trade_retopo"},       # Sanctuary Station (links to Sigma-19)
	"aurelion": {"*": "HL_Station_Elyza_Capital_retopo"},             # Elyza capital
	"velanthos": {"*": "HL_Station_Elyza_Military_retopo"},           # borders the Solrath home and Unity
	"crystara": {"*": "HL_Station_Elyza_Trade_retopo"},               # Elyza's inner hub (4 jump links)
	"malachar": {"*": "HL_Station_Imperium_Capital_retopo"},          # Imperium capital
	"obsidrath": {"*": "HL_Station_Imperium_Military_retopo"},        # Armory, borders the Phenom home and Covenant
	"empire_major": {"*": "HL_Station_Imperium_Trade_retopo"},        # Imperial Customs Station
	"vantara": {"*": "HL_Station_Liberator_Capital_retopo"},          # Liberator capital
	"exodus_point": {"*": "HL_Station_Liberator_Military_retopo"},    # borders the Gadversee home
	"solara": {"*": "st3d_veranthos_customs"},                        # v11.91 (owner): Liberty Hub, Unity, the starting system
	"dreadholm": {"*": "st3d_veranthos_summit"},                      # Orion capital (v11.86 owner: the domed ring; the cobra station is kept for the coming Zards faction)
	"korrath": {"*": "HL_Station_Orion_Military_retopo"},             # Garrison, borders two Savagers systems
	"raptian_major": {"*": "HL_Station_Savagers_Capital_retopo"},     # Savagers capital
	"plundros": {"*": "HL_Station_Savagers_Military_retopo"},         # borders the Cybermorph home and Liberator
	"synthari_capital": {"*": "HL_Station_Solarion_Capital_retopo"},  # Solarion capital
	"techanis": {"*": "HL_Station_Solarion_Military_retopo"},         # borders the Arctides home and Unity
	"crossma_major": {"*": "HL_Station_Solarion_Trade_retopo"},       # Crossma Freeport (4 jump links)
	"kellova": {"*": "HL_Station_Solarion_Outpost_retopo"},           # Cargo Depot on the far edge
	"veranthos": {"*": "HL_Station_Unity_Capital_retopo"},            # Unity capital
	"federis": {"*": "HL_Station_Unity_Military_retopo"},             # borders two Solarion systems
	"aurentum": {"*": "HL_Station_Unity_Trade_retopo"},               # has the Trade Dock
	"void_system": {"*": "HL_Station_Solrath_Capital_retopo", "Gate Anchor": "HL_Station_Solrath_Military_retopo"},
	"kronos": {"*": "HL_Station_Arctides_Capital_retopo", "+Arctides Military Station": "HL_Station_Arctides_Military_retopo"},
	"cynthara": {"*": "HL_Station_Gadversee_Capital_retopo", "+Gadversee Military Station": "HL_Station_Gadversee_Military_retopo"},
	"cybernet": {"*": "HL_Station_Cybermorphs_Capital_retopo", "Signal Relay": "HL_Station_Cybermorphs_Military_retopo"},
	"noctyra": {"*": "HL_Station_Phenom_Capital_retopo", "+Phenom Military Station": "HL_Station_Phenom_Military_retopo"},
	"genesis": {"*": "HL_Station_Kaijurai_Capital_retopo", "+Kaijurai Military Station": "HL_Station_Kaijurai_Military_retopo"},
	"rimgate": {"*": "HL_Station_Unclaimed_Capital_retopo"},          # neutral: between the Elyza and Unity capitals
	"farreach_outpost": {"*": "HL_Station_Unclaimed_Military_retopo"},  # neutral: borders the void and Elyza
	"void_1": {"*": "HL_Station_Unknown_Capital_retopo"},             # unknown space (the void systems)
	"void_3": {"*": "HL_Station_Unknown_Military_retopo"},
}
const RETOPO_STYLE_SCALE := {"Capital": 1.6, "Military": 1.15, "Trade": 1.3, "Outpost": 0.9}   # x the standard station width
const RETOPO_ADDED_DIST := 9600.0   # v11.90: 4x with the stations
#    # m: an added station sits this far from the main one
# Planetary buildings: homeworld system -> faction. Its Command Center and Hangar stand on the system's main planet.
const RETOPO_BUILDINGS := {"sepheron": "Covenant", "aurelion": "Elyza", "malachar": "Imperium", "vantara": "Liberator",
	"dreadholm": "Orion", "raptian_major": "Savagers", "synthari_capital": "Solarion", "void_system": "Solrath", "veranthos": "Unity"}
# v11.91 (owner's Tripo bases, approved Nov 4): which bases stand on which world (system id -> [[file, name, side]]).
# side: "hostile" (attackable nest, gun batteries beside it) / "friendly" / "neutral".
const PLANET_BASES := {
	"solara": [["HL_Base_Unity_ResearchDome", "New Terra Research Dome", "neutral"]],
	"veranthos": [["HL_Base_Unity_Capitol", "Veranthos Capitol", "neutral"], ["HL_Base_Unity_Hangar", "Senate Hangar", "neutral"]],
	"dreadholm": [["HL_Base_Orion_RingSpire", "Ring Spire", "friendly"], ["HL_Base_Orion_FieldDepot", "Magma Field Depot", "friendly"]],
	"raptian_major": [["HL_Base_Savagers_ScrapYard", "Scrap Yard", "hostile"], ["HL_Base_Savagers_WarCamp", "War Camp", "hostile"]],
	"noctyra": [["HL_Base_Phenom_CrystalGate", "Crystal Gate", "hostile"]],
	"genesis": [["HL_Base_Kaijurai_SpikeHive", "Spike Hive", "hostile"]],
	"synthari_capital": [["HL_Base_Solarion_SunTemple", "Sun Temple", "neutral"], ["HL_Base_Solarion_TradeYard", "Trade Yard", "neutral"]],
	"vantara": [["HL_Base_Liberator_Outpost", "Liberator Outpost", "friendly"]],
	"sepheron": [["HL_Base_Covenant_Sanctum", "Covenant Sanctum", "friendly"]],
	"malachar": [["HL_Base_Imperium_Bastion", "Imperium Bastion", "hostile"]],
	"aurelion": [["HL_Base_Elyza_CrystalCourt", "Crystal Court", "neutral"]],
}
const BASE_WIDTH := 260.0        # m across
const BASE_PAD_R := 230.0        # v11.92: m: the flat land pad under a base (blends out to 1.8x); its parts stand on its edge
const BASE_PAD_MIN_H := 8.0      # m: a pad never sits lower than this (above the sea: an island in the ocean)
const BUNKER_WIDTH := 120.0     # v11.96: m: a bunker entrance (a facility without a faction base over it)
const FACILITY_NEAR := 140.0    # m from a facility: INFILTRATE shows (v12.33 owner: "close to the facility, standing next to it"; was 420)
const FACILITY_HIGH := 70.0     # m above it at most
# v12.2 (owner): the super's colours: primary when few hostiles are on you, primary and secondary when many
const SUPER_PRIMARY := [Color(1.0, 0.15, 0.15), Color(0.2, 0.45, 1.0), Color(1.0, 0.9, 0.15)]
const SUPER_SECONDARY := [Color(0.7, 0.2, 1.0), Color(0.2, 1.0, 0.35), Color(1.0, 0.55, 0.1)]
const SUPER_MANY := 4          # this many hostiles engaged or more: all six colours
const SUPER_CYCLE_HZ := 1.6    # how fast the colours run through the beam
const SUPER_WAVE_R := 120.0    # how far the shock rings burst out
const SIDESTEP_SPEED := 160.0   # v12.2: m/s added sideways by SIDESTEP
const SIDESTEP_CD := 1.2
# v12.15 (owner): the mech's LASER SHIELD (the spare button) and SWORD (SIDESTEP in the mech)
const LSHIELD_COLOR := Color(0.35, 0.75, 1.0, 0.32)   # blue glow, see-through
const LSHIELD_SIZE := Vector2(7.0, 9.5)               # m wide, tall
const LSHIELD_DIST := 4.2                              # m out from the mech's middle
const LSHIELD_Y := 0.5
const LSHIELD_COVER := 0.35                            # shots coming from within ~70 deg of where it faces are stopped
const LSHIELD_SWING := 6.0                             # how fast it swings front <-> left (1 / s)
const LSHIELD_AFTER_SHOT := 0.6                        # s it stays on the left after a shot
const SWORD_DASH_SPEED := 300.0                        # m/s forward dash
const SWORD_DASH_TIME := 0.45
const SWORD_COMBO := 4                                 # slashes in a forward dash
## v12.25 (owner: "a building mold ... materials just like Minecraft ... a button on the top that says BUILD"): BUILD
## (top bar; the mech on a planet) swaps FIRE for PLACE and shows the material slots. The sword cuts wood (it doesn't set
## it alight) and breaks stone and harder rock into them; only building materials are kept: no sand or dirt, and no
## water or lava. A placed block goes where the crosshair meets the ground or another block (it falls if nothing holds it).
## v12.31 (owner: "I don't want the Minecraft build ... take that out ... more focused on just the gameplay and the
## destruction"): BUILD mode is off: no BUILD button, no material slots, nothing collected. The sword still cuts.
const BUILD_ON := false
## v12.32 (owner: "never a situation where I'm in a pitch black area"): light you carry (space.gd _update_lamp)
const LEVEL_LIGHTS := 6      # v12.35: level lamps on at once inside a ship / base (the nearest; WebGL can't take ~120)
const LAMP_BOARD := 1.2        # always on you inside a ship or base
const LAMP_SURFACE := 0.35     # on a world (night, caves)
const LAMP_SHIELD := 2.6       # more with the shield up (blue)
const LAMP_FLASH := 3.5        # the sword's flash on a swing / hit
const LAMP_RANGE := 55.0
const LAMP_UP := 5.0
const LAMP_BOLT_LIGHTS := 6    # your laser bolts that carry a light at once (phones: kept few)
const LAMP_BOLT_ENERGY := 2.2
const LAMP_BOLT_RANGE := 22.0
const LAMP_FIRES := 4          # lights on the nearest burning blocks
const LAMP_FIRE_ENERGY := 2.4
const LAMP_FIRE_RANGE := 30.0
const BUILD_MATS := ["stone", "wood", "obsidian", "gold", "diamond"]
const BUILD_SLOTS := 9               # slots on the bar (the rest wait for new materials)
const BUILD_REACH := 60.0            # m along the crosshair
const BUILD_MAT_COLOR := {"stone": Color(0.55, 0.56, 0.6), "wood": Color(0.45, 0.3, 0.18), "obsidian": Color(0.16, 0.12, 0.22), "gold": Color(1.0, 0.8, 0.2), "diamond": Color(0.55, 0.95, 1.0)}
const SWORD_CUTS := ["stone", "wood", "obsidian", "gold", "diamond", "leaf", "leaf2", "vine", "frond", "glow", "bloom"]   # what the blade cuts (it bounces off dirt and sand)
const SWORD_HARVEST_MAX := 6         # layers one slash takes
const SWORD_COMBO_GAP := 0.11                          # s between them
const SWORD_SIDE_SPEED := 220.0
const SWORD_SIDE_TIME := 0.32
const SWORD_SPIN_TIME := 0.7
const SWORD_SPIN_HITS := 3
const SWORD_SEEK_MAX := 6.0                            # s the lock-on dash may run
const SWORD_SEEK_GAP := 0.14                           # s between spinning hits
const SWORD_HOLD := 0.35                               # s held before it starts locking on
const SWORD_LOCK_EVERY := 0.3                          # s per extra lock
const SWORD_MAX_LOCKS := 8
const SWORD_LOCK_RANGE := 700.0
const SWORD_LOCK_CONE := 0.35                          # ahead (dot)
const SWORD_REACH := 16.0                              # m the blade reaches
const SWORD_CONE := 0.2
const SWORD_DMG_MULT := 1.0                            # x a light missile hit
const SWORD_BLADE_LEN := 9.0
const SWORD_HAND := Vector3(3.2, 1.0, -1.0)            # where the blade sits on the mech
const SHIP_DECK_LEVEL := 2                             # v12.18: an enemy battleship's deck plan size (1-4; +1 on a mission ship)
const BOARD_MAX_SPEED := 110.0                         # m/s top speed inside a battleship (a ship can't punch through the walls)
const BUNKER_WALK_W := 0.85   # v12.3: a bunker's walkway sections, in bunker widths (long side)
const FORT_RADIUS := 1.45     # v12.2: a bunker fort's corners sit this many bunker widths from its middle
const FORT_GATE_W := 0.9      # the gate tower, in bunker widths
const FORT_TOWER_W := 0.55    # a corner tower
const FORT_WALL_H := 0.32     # the walls' height, in bunker widths
const DISTURBANCE_STATION_GAP := 40000.0   # v12.6: a disturbance cloud's edge stays this far from every station (m)
const BORDER_GLITCH_OUT := 1.6    # v12.4 (owner): crossing a border: static, the lines zoom up and fade, white (s)
const BORDER_GLITCH_BACK := 1.1   # the static comes back and the picture fixes itself on the other side (s)
const BORDER_MARGIN := 0.25   # v12.3: map squares kept clear inside the border squares (nothing but clouds out there)
const UNKNOWN_KAIJU_MULT := 3.0   # v12.3 (owner: "high level areas ... like level 3 fighters"): Kaijurai in the uncharted areas are 3x as tough
const STATION_INFIL_LEVEL := 3   # v11.99: an alien station is infiltrated as a level 3 facility
const FACILITY_PAY := 3500      # cr x difficulty for clearing a facility
const BASE_PART_WIDTH := 45.0    # m: a gun battery / generator beside a hostile base
const BASE_SPOTS := [Vector2(700.0, 500.0), Vector2(-750.0, 450.0), Vector2(150.0, 900.0), Vector2(-500.0, -800.0)]   # (4: up to 4 facilities a world)   # sector-local x, z (clear of the Command Center and Hangar)
const BUILDING_KINDS := ["CommandCenter", "Hangar"]   # Imperium, Liberator and Solrath have no Hangar file yet
const BUILDING_WIDTH := {"CommandCenter": 170.0, "Hangar": 140.0}   # m across (the landing pad is 180 m)
const BUILDING_SPOT := {"CommandCenter": Vector2(-150.0, -420.0), "Hangar": Vector2(180.0, -400.0)}   # m from the sector centre (x east, z south)
const BUILDING_YAW := {"CommandCenter": 180.0, "Hangar": 180.0}   # the file's front (-Z) turned to face the sector centre
const BUILDING_SINK := 2.0            # m pushed into the ground so no corner floats on a slope
const BUILDING_SEARCH_STEP := 160.0   # m between candidate sites when looking for flat ground ...
const BUILDING_SEARCH_STEPS := 6      # ... this many steps each way round the wanted spot
const BUILDING_GAP := 40.0            # m kept clear between the two buildings
const BUILDING_PROBES := [Vector2.ZERO, Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]   # footprint samples (x half-width)
const BUILDING_FLAT_OK := 45.0        # m: the test accepts this much rise under a footprint (hilly worlds)
const RETOPO_BOX_PAD := 8.0           # m: the ship's own size added to a model's collision box
static func is_st3d(model: Variant) -> bool:
	var m := str(model)
	return m.begins_with("st3d_") or m.begins_with("HL_Station_")
## Station width multiplier for a 3D station model (the RETOPO set by its style, the older set from STATION3D_SCALE).
const STATION_GROW := 8.0   # v11.90 (owner: every station 4x, with the 4x battleships): was 2.0
#  # v10.6 (owner: "stations need to be bigger, twice the size"): every 3D station model
static func st3d_scale(key: String) -> float:
	if STATION3D_SCALE.has(key): return float(STATION3D_SCALE[key]) * STATION_GROW
	if key.begins_with("HL_Station_"):
		for st in RETOPO_STYLE_SCALE:
			if key.find("_%s_" % st) >= 0: return float(RETOPO_STYLE_SCALE[st]) * STATION_GROW
	return STATION_GROW
static func building_file(faction: String, kind: String) -> String:
	return "res://assets/buildings3d/HL_%s_%s_v01_retopo.glb" % [faction, kind]
const BEACON_SYSTEMS := ["solara"]   # extra systems with a light beacon in their nebula (every roster-faction hideout system has one)
const BEACON_FACTIONS := ["Savagers"]
const BEACON_SIZE := 150.0           # width of the beacon station
const BEACON_LAMP_Y := 0.33          # lamp height on the model (model is 1.0 wide, centred)
const BEACON_LIGHT_COLOR := Color(1.0, 0.93, 0.72)
const BEACON_LIGHT_RANGE := 1100.0   # how far the lamp lights ships, rocks and the station itself
const BEACON_LIGHT_ENERGY := 6.0
const BEACON_GLOW_SIZE := 620.0      # the bright halo that lights up the cloud around it
const BEACON_GLOW_ALPHA := 0.9
const BEACON_CORE_SIZE := 120.0      # the bright star at the lamp itself
const BEACON_PULSE := 0.25           # share of the brightness that breathes
const BEACON_PULSE_RATE := 0.7       # breaths per second (x TAU)
const BEACON_PUFFS := 7              # lit cloud puffs round the lamp
const BEACON_PUFF_ALPHA := 0.22
const BEACON_HAZE_CLEAR := 0.75      # next to the lamp the nebula haze on screen thins by this share and takes the lamp's colour
const BUOYS_PER_CLOUD := 12         # v10.4 (owner: beacons in the clouds to show direction): buoys in a line through every cloud
const BUOY_REACH := 0.92             # the line starts / ends this share of the cloud's radius out from its middle
const BUOY_GLOW := 380.0             # the halo of a buoy light (m); far off it never shrinks below a small dot (shader)
const BUOY_SIZE := 45.0              # the owner's beacon model under each buoy light (m wide)
const BUOY_PULSE_RATE := 0.5         # how fast the pulse runs along the line toward the way out
const BUOY_LIGHT_RANGE := 900.0      # next to a buoy its light thins the haze ...
const BUOY_HAZE := 0.6               # ... by up to this share of the big beacon's effect
const BEACON_SENSOR_HELP := 0.7      # ... and the sensors get this share of their range back
static var ROSTERS: Dictionary = RosterData.merged(ROSTERS_CORE)   # v1.4w: Savagers (below) + the seven casts in roster_data.gd
const ROSTERS_CORE := {
	"Savagers": {"leader": "Dreadmaw", "pilots": [
		{"character_id": "savagers_01_soldier", "id": "savagers_01", "slot": 1, "rank": 1, "unit": "SV-01", "name": "Soldier", "type": "Level 1 Grunt", "role": "Common Soldier",
			"sex": "male", "species": "Human", "persona": "obedient, aggressive, low-rank thug, disposable but dangerous in groups",
			"voice_id": "savagers_01_soldier", "voice_sex": "male", "voice_persona": "male, filtered helmet voice", "normal_emotion": "alert / rough / militarized", "damaged_emotion": "panicked / angry / breathless", "critical_emotion": "panicked / desperate",
			"fighter_primary": "scrapfang", "fighter_alternates": [], "spawn_weight": 70.0, "named_unique": false, "bounty": false,
			"voice": 0.8, "female": false, "hurt": "...Still breathing..."},
		{"character_id": "savagers_02_jackal", "id": "savagers_02", "slot": 2, "rank": 2, "unit": "SV-02", "name": "Jackal", "type": "Level 2 Raider", "role": "Raider",
			"sex": "male", "species": "Hyena Alien", "persona": "mocking, feral, reckless, enjoys chasing prey",
			"voice_id": "savagers_02_jackal", "voice_sex": "male", "voice_persona": "male", "normal_emotion": "raspy / taunting / laughing", "damaged_emotion": "enraged / snarling", "critical_emotion": "snarling / cornered",
			"fighter_primary": "scrapfang", "fighter_alternates": ["redclaw"], "spawn_weight": 12.0, "named_unique": true, "bounty": true, "sys": "derelicta",
			"voice": 0.7, "female": false, "hurt": "...I'll chew through you..."},
		{"character_id": "savagers_03_razor", "id": "savagers_03", "slot": 3, "rank": 3, "unit": "SV-03", "name": "Razor", "type": "Level 3 Assault Raider", "role": "Assault Raider",
			"sex": "female", "species": "Human", "persona": "arrogant, violent, bold, intimidation-driven",
			"voice_id": "savagers_03_razor", "voice_sex": "female", "voice_persona": "female", "normal_emotion": "sharp / cocky / aggressive", "damaged_emotion": "furious / wounded", "critical_emotion": "furious / desperate",
			"fighter_primary": "redclaw", "fighter_alternates": ["scrapfang"], "spawn_weight": 6.0, "named_unique": true, "bounty": true, "sys": "plundros",
			"voice": 1.15, "female": true, "hurt": "...That all you got?.."},
		{"character_id": "savagers_04_veil", "id": "savagers_04", "slot": 4, "rank": 4, "unit": "SV-04", "name": "Veil", "type": "Level 4 Ace Pilot", "role": "Ace Pilot",
			"sex": "female", "species": "Human", "persona": "cool, focused, dangerous, observant, calculating",
			"voice_id": "savagers_04_veil", "voice_sex": "female", "voice_persona": "female, low, precise outlaw pilot", "normal_emotion": "calm / low / precise", "damaged_emotion": "cold anger / strained", "critical_emotion": "strained / desperate",
			"fighter_primary": "redclaw", "fighter_alternates": ["ironhowl"], "spawn_weight": 5.0, "named_unique": true, "bounty": true, "sys": "scavaris",
			"voice": 0.95, "female": true, "hurt": "...Not finished..."},
		{"character_id": "savagers_05_brakk", "id": "savagers_05", "slot": 5, "rank": 5, "unit": "SV-05", "name": "Brakk", "type": "Level 5 Lieutenant", "role": "Enforcer Lieutenant",
			"sex": "male", "species": "Human-Hybrid", "persona": "brutal, tactical, loyal to the boss, intimidating",
			"voice_id": "savagers_05_brakk", "voice_sex": "male", "voice_persona": "male", "normal_emotion": "deep / stern / commanding", "damaged_emotion": "furious / forceful", "critical_emotion": "furious / forceful",
			"fighter_primary": "ironhowl", "fighter_alternates": ["redclaw"], "spawn_weight": 5.0, "named_unique": true, "bounty": false,
			"voice": 0.6, "female": false, "hurt": "...Hold the line, dogs..."},
		{"character_id": "savagers_06_dreadmaw", "id": "savagers_06", "slot": 6, "rank": 6, "unit": "SV-06", "name": "Dreadmaw", "type": "Level 6 Gang Boss", "role": "Savager Boss",
			"sex": "male", "species": "Boar Alien", "persona": "ruthless, territorial, cunning, domineering, dangerous strategist",
			"permanent_features": "boar face, scar across one eye, permanent eyepatch",
			"voice_id": "savagers_06_dreadmaw", "voice_sex": "male", "voice_persona": "male", "normal_emotion": "deep / gravelly / mocking threat", "damaged_emotion": "berserk rage / wounded but dominant", "critical_emotion": "berserk rage",
			"fighter_primary": "warboar", "fighter_alternates": ["ironhowl"], "spawn_weight": 2.0, "named_unique": true, "bounty": true, "sys": "raptian_major",
			"voice": 0.5, "female": false, "hurt": "...Space belongs to the Savages..."},
	]},
}

## The roster that flies in this system: its faction's (a per-system roster can be added here later). Empty = none yet.
static func roster(system: Dictionary) -> Array:
	return ROSTERS.get(str(system.get("faction", "")), {}).get("pilots", [])

## One roster character by character_id or by portrait id ("savagers_04_veil" or "savagers_04"), with its faction added.
static func roster_pilot(id: String) -> Dictionary:
	for f in ROSTERS:
		for p in ROSTERS[f]["pilots"]:
			if p["id"] == id or p["character_id"] == id:
				var d: Dictionary = (p as Dictionary).duplicate()
				d["faction"] = f
				d["leader"] = ROSTERS[f]["leader"]
				# v1.5l: characters 2, 3, 4 and 6 of every faction with ships are wanted (BOUNTY_SLOTS); they hide in their own space
				if not d.get("bounty", false) and int(d.get("slot", 0)) in BOUNTY_SLOTS and f in BOUNTY_FACTIONS and ENEMIES.has(str(d.get("fighter_primary", ""))):
					var owned: Array = faction_systems(f)
					if not owned.is_empty():
						d["bounty"] = true
						d["sys"] = owned[int(d["slot"]) % owned.size()]
				d["portrait_clean"] = "res://assets/enemy_pilots/%s_clean.jpg" % p["id"]
				d["portrait_damaged"] = "res://assets/enemy_pilots/%s_damaged.jpg" % p["id"]
				return d
	return {}

## v1.5a: the shortest way from one system to another through the gates, as a list of system ids (both ends in it).
## [] = no way. Every gate works both ways, so each system's own gate list is enough.
static func gate_route(from: String, to: String) -> Array:
	if not SYSTEMS.has(from) or not SYSTEMS.has(to): return []
	if from == to: return [from]
	var key := from + ">" + to
	if _route_cache.has(key): return _route_cache[key]   # (asked every frame by the HUD while a mission is on)
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for g in SYSTEMS[cur].get("gates", []):
			var nx: String = str(g.get("to", ""))
			if nx == "" or prev.has(nx) or not SYSTEMS.has(nx): continue
			prev[nx] = cur
			if nx == to:
				var out: Array = [to]
				while out[0] != from: out.push_front(prev[out[0]])
				_route_cache[key] = out
				return out
			queue.append(nx)
	_route_cache[key] = []
	return []
static var _route_cache := {}

static func bounties() -> Array:
	var out: Array = []
	for f in ROSTERS:
		for p in ROSTERS[f]["pilots"]:
			var d := roster_pilot(p["id"])
			if d.get("bounty", false): out.append(d)
	return out

## v1.5l: the bounties a station posts: the targets of its owner's enemies (its rival nation, the permanent enemies,
## and the Savagers, who are outlaws everywhere), never its own people.
static func bounties_for(owner: String) -> Array:
	# v1.8c (owner): a board only posts its owner's rivals. A rival with no wanted pilots: the Savagers pirates instead.
	var riv := Factions.rival(owner)
	var out: Array = bounties().filter(func(p): return str(p["faction"]) == riv and riv != owner)
	if out.is_empty() and owner != "Savagers": out = bounties().filter(func(p): return str(p["faction"]) == "Savagers")
	return out

## v1.5l: where a faction's people hide: the systems it owns (a permanent enemy: its home system), in a fixed order.
static var _owned_cache := {}
static func faction_systems(f: String) -> Array:
	if _owned_cache.has(f): return _owned_cache[f]
	var out: Array = []
	for id in SYSTEMS:
		if str(SYSTEMS[id].get("faction", "")) == f or str(SYSTEMS[id].get("enemy_faction", "")) == f: out.append(id)
	out.sort()
	_owned_cache[f] = out
	return out

static func rank_mult(rank: int, step: float) -> float: return 1.0 + step * float(maxi(1, rank) - 1)
static func bounty_reward(id: String) -> int: return BOUNTY_REWARD * int(roster_pilot(id).get("rank", 1))

# ---------------------------------------------------------------- enemies
const ENEMIES := {
	"ship_tower": {"name": "Shield Tower", "class": "shield generator", "model": "none", "scale": 1.0, "hull": 1600.0, "shield": 0.0, "speed": 0.0, "turn": 0.0, "damage": 0.0, "rate": 0.5, "reward": 700, "capital": true, "hit_r": 22.0, "range": 0.0, "radius": 20.0},   # v11.42
	"ship_bridge": {"name": "Bridge", "class": "bridge and drive", "model": "none", "scale": 1.0, "hull": 1300.0, "shield": 0.0, "speed": 0.0, "turn": 0.0, "damage": 0.0, "rate": 0.5, "reward": 600, "capital": true, "hit_r": 20.0, "range": 0.0, "radius": 18.0},
	"ship_turret": {"name": "Turret", "class": "gun turret", "model": "none", "scale": 1.0, "hull": 520.0, "shield": 0.0, "speed": 0.0, "turn": 0.0, "damage": 7.0, "rate": 1.4, "reward": 250, "capital": true, "hit_r": 13.0, "range": 1100.0, "radius": 12.0},
	"ship_core": {"name": "Reactor Core", "class": "reactor", "model": "none", "scale": 1.0, "hull": 1800.0, "shield": 0.0, "speed": 0.0, "turn": 0.0, "damage": 0.0, "rate": 0.5, "reward": 0, "capital": true, "hit_r": 26.0, "range": 0.0, "radius": 24.0},
	"elyza_battleship": {"name": "Elyza Battleship", "class": "battleship", "faction": "Elyza", "model": "elyza_battleship", "scale": 1.0, "hull": 5000.0, "shield": 1800.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3200, "capital": true, "hit_r": 340.0, "range": 2800.0, "radius": 420.0, "carrier": "battleship"},   # v11.32
	"elyza_cruiser": {"name": "Elyza Cruiser", "class": "cruiser", "faction": "Elyza", "model": "elyza_cruiser", "scale": 1.0, "hull": 2600.0, "shield": 900.0, "speed": 24.0, "turn": 0.09, "damage": 7.5, "rate": 2.2, "reward": 1200, "capital": true, "hit_r": 96.0, "range": 2400.0, "radius": 114.0, "carrier": "cruiser"},
	"elyza_starfighter": {"name": "Elyza Starfighter", "class": "fighter", "faction": "Elyza", "model": "elyza_starfighter", "radius": 7.0, "hull": 80.0, "shield": 50.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 230, "missiles": true},
	"elyza_fighter_l2": {"name": "Elyza Fighter Mk II", "class": "fighter", "faction": "Elyza", "model": "elyza_fighter_l2", "radius": 8.0, "hit_r": 9.0, "hull": 160.0, "shield": 100.0, "speed": 53.0, "turn": 1.45, "damage": 12.0, "rate": 1.8, "reward": 460, "missiles": true, "level": 2},   # v11.68
	"elyza_fighter_l3": {"name": "Elyza Fighter Mk III", "class": "fighter", "faction": "Elyza", "model": "elyza_fighter_l3", "radius": 11.0, "hit_r": 12.0, "hull": 240.0, "shield": 150.0, "speed": 50.0, "turn": 1.3, "damage": 18.0, "rate": 1.9, "reward": 690, "missiles": true, "level": 3},   # v11.68
	"unity_battleship": {"name": "Unity Battleship", "class": "battleship", "faction": "Unity", "model": "unity_battleship", "scale": 1.0, "hull": 5000.0, "shield": 1800.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3200, "capital": true, "hit_r": 340.0, "range": 2800.0, "radius": 420.0, "carrier": "battleship"},   # v11.32
	"unity_cruiser": {"name": "Unity Cruiser", "class": "cruiser", "faction": "Unity", "model": "unity_cruiser", "scale": 1.0, "hull": 2600.0, "shield": 900.0, "speed": 24.0, "turn": 0.09, "damage": 7.5, "rate": 2.2, "reward": 1200, "capital": true, "hit_r": 96.0, "range": 2400.0, "radius": 114.0, "carrier": "cruiser"},
	"unity_frigate": {"name": "Unity Frigate", "class": "frigate", "faction": "Unity", "model": "unity_frigate", "scale": 1.0, "hull": 1800.0, "shield": 600.0, "speed": 30.0, "turn": 0.11, "damage": 6.5, "rate": 2.0, "reward": 800, "capital": true, "hit_r": 54.0, "range": 2100.0, "radius": 66.0, "carrier": "frigate"},
	"unity_starfighter": {"name": "Unity Starfighter", "class": "fighter", "faction": "Unity", "model": "unity_starfighter", "radius": 7.0, "hull": 80.0, "shield": 50.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 230, "missiles": true},
	"unity_fighter_l2": {"name": "Unity Fighter Mk II", "class": "fighter", "faction": "Unity", "model": "unity_fighter_l2", "radius": 8.0, "hit_r": 9.0, "hull": 160.0, "shield": 100.0, "speed": 53.0, "turn": 1.45, "damage": 12.0, "rate": 1.8, "reward": 460, "missiles": true, "level": 2},   # v11.68
	"unity_fighter_l3": {"name": "Unity Fighter Mk III", "class": "fighter", "faction": "Unity", "model": "unity_fighter_l3", "radius": 11.0, "hit_r": 12.0, "hull": 240.0, "shield": 150.0, "speed": 50.0, "turn": 1.3, "damage": 18.0, "rate": 1.9, "reward": 690, "missiles": true, "level": 3},   # v11.68
	"solarion_battleship": {"name": "Solarion Battleship", "class": "battleship", "faction": "Solarion", "model": "solarion_battleship", "scale": 1.0, "hull": 5000.0, "shield": 1800.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3200, "capital": true, "hit_r": 340.0, "range": 2800.0, "radius": 420.0, "carrier": "battleship"},   # v11.32
	"solarion_cruiser": {"name": "Solarion Cruiser", "class": "cruiser", "faction": "Solarion", "model": "solarion_cruiser", "scale": 1.0, "hull": 2600.0, "shield": 900.0, "speed": 24.0, "turn": 0.09, "damage": 7.5, "rate": 2.2, "reward": 1200, "capital": true, "hit_r": 96.0, "range": 2400.0, "radius": 114.0, "carrier": "cruiser"},
	"solarion_frigate": {"name": "Solarion Frigate", "class": "frigate", "faction": "Solarion", "model": "solarion_frigate", "scale": 1.0, "hull": 1800.0, "shield": 600.0, "speed": 30.0, "turn": 0.11, "damage": 6.5, "rate": 2.0, "reward": 800, "capital": true, "hit_r": 54.0, "range": 2100.0, "radius": 66.0, "carrier": "frigate"},
	"solarion_starfighter": {"name": "Solarion Starfighter", "class": "fighter", "faction": "Solarion", "model": "solarion_starfighter", "radius": 7.0, "hull": 80.0, "shield": 50.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 230, "missiles": true},
	"solarion_fighter_l2": {"name": "Solarion Fighter Mk II", "class": "fighter", "faction": "Solarion", "model": "solarion_fighter_l2", "radius": 8.0, "hit_r": 9.0, "hull": 160.0, "shield": 100.0, "speed": 53.0, "turn": 1.45, "damage": 12.0, "rate": 1.8, "reward": 460, "missiles": true, "level": 2},   # v11.68
	"solarion_fighter_l3": {"name": "Solarion Fighter Mk III", "class": "fighter", "faction": "Solarion", "model": "solarion_fighter_l3", "radius": 11.0, "hit_r": 12.0, "hull": 240.0, "shield": 150.0, "speed": 50.0, "turn": 1.3, "damage": 18.0, "rate": 1.9, "reward": 690, "missiles": true, "level": 3},   # v11.68
	"imperium_battleship": {"name": "Imperium Battleship", "class": "battleship", "faction": "Imperium", "model": "imperium_battleship", "scale": 1.0, "hull": 5000.0, "shield": 1800.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3200, "capital": true, "hit_r": 340.0, "range": 2800.0, "radius": 420.0, "carrier": "battleship"},   # v11.32
	"imperium_cruiser": {"name": "Imperium Cruiser", "class": "cruiser", "faction": "Imperium", "model": "imperium_cruiser", "scale": 1.0, "hull": 2600.0, "shield": 900.0, "speed": 24.0, "turn": 0.09, "damage": 7.5, "rate": 2.2, "reward": 1200, "capital": true, "hit_r": 96.0, "range": 2400.0, "radius": 114.0, "carrier": "cruiser"},
	"imperium_frigate": {"name": "Imperium Frigate", "class": "frigate", "faction": "Imperium", "model": "imperium_frigate", "scale": 1.0, "hull": 1800.0, "shield": 600.0, "speed": 30.0, "turn": 0.11, "damage": 6.5, "rate": 2.0, "reward": 800, "capital": true, "hit_r": 54.0, "range": 2100.0, "radius": 66.0, "carrier": "frigate"},
	"imperium_starfighter": {"name": "Imperium Starfighter", "class": "fighter", "faction": "Imperium", "model": "imperium_starfighter", "radius": 7.0, "hull": 80.0, "shield": 50.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 230, "missiles": true},
	"imperium_fighter_l2": {"name": "Imperium Fighter Mk II", "class": "fighter", "faction": "Imperium", "model": "imperium_fighter_l2", "radius": 8.0, "hit_r": 9.0, "hull": 160.0, "shield": 100.0, "speed": 53.0, "turn": 1.45, "damage": 12.0, "rate": 1.8, "reward": 460, "missiles": true, "level": 2},   # v11.68
	"imperium_fighter_l3": {"name": "Imperium Fighter Mk III", "class": "fighter", "faction": "Imperium", "model": "imperium_fighter_l3", "radius": 11.0, "hit_r": 12.0, "hull": 240.0, "shield": 150.0, "speed": 50.0, "turn": 1.3, "damage": 18.0, "rate": 1.9, "reward": 690, "missiles": true, "level": 3},   # v11.68
	"covenant_battleship": {"name": "Covenant Battleship", "class": "battleship", "faction": "Covenant", "model": "covenant_battleship", "scale": 1.0, "hull": 5000.0, "shield": 1800.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3200, "capital": true, "hit_r": 340.0, "range": 2800.0, "radius": 420.0, "carrier": "battleship"},   # v11.32
	"covenant_cruiser": {"name": "Covenant Cruiser", "class": "cruiser", "faction": "Covenant", "model": "covenant_cruiser", "scale": 1.0, "hull": 2600.0, "shield": 900.0, "speed": 24.0, "turn": 0.09, "damage": 7.5, "rate": 2.2, "reward": 1200, "capital": true, "hit_r": 96.0, "range": 2400.0, "radius": 114.0, "carrier": "cruiser"},
	"covenant_frigate": {"name": "Covenant Frigate", "class": "frigate", "faction": "Covenant", "model": "covenant_frigate", "scale": 1.0, "hull": 1800.0, "shield": 600.0, "speed": 30.0, "turn": 0.11, "damage": 6.5, "rate": 2.0, "reward": 800, "capital": true, "hit_r": 54.0, "range": 2100.0, "radius": 66.0, "carrier": "frigate"},
	"covenant_starfighter": {"name": "Covenant Starfighter", "class": "fighter", "faction": "Covenant", "model": "covenant_starfighter", "radius": 7.0, "hull": 80.0, "shield": 50.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 230, "missiles": true},
	"covenant_fighter_l2": {"name": "Covenant Fighter Mk II", "class": "fighter", "faction": "Covenant", "model": "covenant_fighter_l2", "radius": 8.0, "hit_r": 9.0, "hull": 160.0, "shield": 100.0, "speed": 53.0, "turn": 1.45, "damage": 12.0, "rate": 1.8, "reward": 460, "missiles": true, "level": 2},   # v11.68
	"covenant_fighter_l3": {"name": "Covenant Fighter Mk III", "class": "fighter", "faction": "Covenant", "model": "covenant_fighter_l3", "radius": 11.0, "hit_r": 12.0, "hull": 240.0, "shield": 150.0, "speed": 50.0, "turn": 1.3, "damage": 18.0, "rate": 1.9, "reward": 690, "missiles": true, "level": 3},   # v11.68
	"orion_battleship": {"name": "Orion Battleship", "class": "battleship", "faction": "Orion", "model": "orion_battleship", "scale": 1.0, "hull": 5000.0, "shield": 1800.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3200, "capital": true, "hit_r": 340.0, "range": 2800.0, "radius": 420.0, "carrier": "battleship"},   # v11.32
	"orion_cruiser": {"name": "Orion Cruiser", "class": "cruiser", "faction": "Orion", "model": "orion_cruiser", "scale": 1.0, "hull": 2600.0, "shield": 900.0, "speed": 24.0, "turn": 0.09, "damage": 7.5, "rate": 2.2, "reward": 1200, "capital": true, "hit_r": 96.0, "range": 2400.0, "radius": 114.0, "carrier": "cruiser"},
	"orion_frigate": {"name": "Orion Frigate", "class": "frigate", "faction": "Orion", "model": "orion_frigate", "scale": 1.0, "hull": 1800.0, "shield": 600.0, "speed": 30.0, "turn": 0.11, "damage": 6.5, "rate": 2.0, "reward": 800, "capital": true, "hit_r": 54.0, "range": 2100.0, "radius": 66.0, "carrier": "frigate"},
	"orion_starfighter": {"name": "Orion Starfighter", "class": "fighter", "faction": "Orion", "model": "orion_starfighter", "radius": 7.0, "hull": 80.0, "shield": 50.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 230, "missiles": true},
	"orion_fighter_l2": {"name": "Orion Fighter Mk II", "class": "fighter", "faction": "Orion", "model": "orion_fighter_l2", "radius": 8.0, "hit_r": 9.0, "hull": 160.0, "shield": 100.0, "speed": 53.0, "turn": 1.45, "damage": 12.0, "rate": 1.8, "reward": 460, "missiles": true, "level": 2},   # v11.68
	"orion_fighter_l3": {"name": "Orion Fighter Mk III", "class": "fighter", "faction": "Orion", "model": "orion_fighter_l3", "radius": 11.0, "hit_r": 12.0, "hull": 240.0, "shield": 150.0, "speed": 50.0, "turn": 1.3, "damage": 18.0, "rate": 1.9, "reward": 690, "missiles": true, "level": 3},   # v11.68
	"savagers_battleship": {"name": "Savagers Battleship", "class": "battleship", "faction": "Savagers", "model": "savagers_battleship", "scale": 1.0, "hull": 5000.0, "shield": 1800.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3200, "capital": true, "hit_r": 340.0, "range": 2800.0, "radius": 420.0, "carrier": "battleship"},   # v11.32
	"savagers_cruiser": {"name": "Savagers Cruiser", "class": "cruiser", "faction": "Savagers", "model": "savagers_cruiser", "scale": 1.0, "hull": 2600.0, "shield": 900.0, "speed": 24.0, "turn": 0.09, "damage": 7.5, "rate": 2.2, "reward": 1200, "capital": true, "hit_r": 96.0, "range": 2400.0, "radius": 114.0, "carrier": "cruiser"},
	"savagers_frigate": {"name": "Savagers Frigate", "class": "frigate", "faction": "Savagers", "model": "savagers_frigate", "scale": 1.0, "hull": 1800.0, "shield": 600.0, "speed": 30.0, "turn": 0.11, "damage": 6.5, "rate": 2.0, "reward": 800, "capital": true, "hit_r": 54.0, "range": 2100.0, "radius": 66.0, "carrier": "frigate"},
	"savagers_starfighter": {"name": "Savagers Starfighter", "class": "fighter", "faction": "Savagers", "model": "savagers_starfighter", "radius": 7.0, "hull": 80.0, "shield": 50.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 230, "missiles": true},
	"savagers_fighter_l2": {"name": "Savagers Fighter Mk II", "class": "fighter", "faction": "Savagers", "model": "savagers_fighter_l2", "radius": 8.0, "hit_r": 9.0, "hull": 160.0, "shield": 100.0, "speed": 53.0, "turn": 1.45, "damage": 12.0, "rate": 1.8, "reward": 460, "missiles": true, "level": 2},   # v11.68
	"savagers_fighter_l3": {"name": "Savagers Fighter Mk III", "class": "fighter", "faction": "Savagers", "model": "savagers_fighter_l3", "radius": 11.0, "hit_r": 12.0, "hull": 240.0, "shield": 150.0, "speed": 50.0, "turn": 1.3, "damage": 18.0, "rate": 1.9, "reward": 690, "missiles": true, "level": 3},   # v11.68
	"liberator_battleship": {"name": "Liberator Battleship", "class": "battleship", "faction": "Liberator", "model": "liberator_battleship", "scale": 1.0, "hull": 5000.0, "shield": 1800.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3200, "capital": true, "hit_r": 340.0, "range": 2800.0, "radius": 420.0, "carrier": "battleship"},   # v11.32
	"liberator_cruiser": {"name": "Liberator Cruiser", "class": "cruiser", "faction": "Liberator", "model": "liberator_cruiser", "scale": 1.0, "hull": 2600.0, "shield": 900.0, "speed": 24.0, "turn": 0.09, "damage": 7.5, "rate": 2.2, "reward": 1200, "capital": true, "hit_r": 96.0, "range": 2400.0, "radius": 114.0, "carrier": "cruiser"},
	"liberator_frigate": {"name": "Liberator Frigate", "class": "frigate", "faction": "Liberator", "model": "liberator_frigate", "scale": 1.0, "hull": 1800.0, "shield": 600.0, "speed": 30.0, "turn": 0.11, "damage": 6.5, "rate": 2.0, "reward": 800, "capital": true, "hit_r": 54.0, "range": 2100.0, "radius": 66.0, "carrier": "frigate"},
	"liberator_starfighter": {"name": "Liberator Starfighter", "class": "fighter", "faction": "Liberator", "model": "liberator_starfighter", "radius": 7.0, "hull": 80.0, "shield": 50.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 230, "missiles": true},
	"liberator_fighter_l2": {"name": "Liberator Fighter Mk II", "class": "fighter", "faction": "Liberator", "model": "liberator_fighter_l2", "radius": 8.0, "hit_r": 9.0, "hull": 160.0, "shield": 100.0, "speed": 53.0, "turn": 1.45, "damage": 12.0, "rate": 1.8, "reward": 460, "missiles": true, "level": 2},   # v11.68
	"liberator_fighter_l3": {"name": "Liberator Fighter Mk III", "class": "fighter", "faction": "Liberator", "model": "liberator_fighter_l3", "radius": 11.0, "hit_r": 12.0, "hull": 240.0, "shield": 150.0, "speed": 50.0, "turn": 1.3, "damage": 18.0, "rate": 1.9, "reward": 690, "missiles": true, "level": 3},   # v11.68
	# v1.9n (owner): the SILVER fleet invasion's big ships (capital = slow, turrets all round, a big hit box; missiles,
	# mines and the special do set damage to them, not a share of their hull)
	"inv_battleship": {"name": "Battleship", "model": "savager_carrier", "scale": 4.0, "hull": 4500.0, "shield": 1500.0, "speed": 14.0, "turn": 0.05, "damage": 9.0, "rate": 3.0, "reward": 3000, "capital": true, "hit_r": 248.0, "range": 2600.0, "radius": 280.0},
	"inv_flagship": {"name": "Flagship", "model": "savager_carrier", "scale": 7.2, "hull": 7000.0, "shield": 2500.0, "speed": 10.0, "turn": 0.04, "damage": 10.0, "rate": 3.4, "reward": 5000, "capital": true, "hit_r": 420.0, "range": 3000.0, "radius": 480.0},   # v11.31: the huge destroyer
	"inv_warship": {"name": "Warship", "model": "savager_cruiser", "scale": 6.0, "hull": 4500.0, "shield": 1500.0, "speed": 20.0, "turn": 0.08, "damage": 8.0, "rate": 2.4, "reward": 1500, "capital": true, "hit_r": 114.0, "range": 2200.0, "radius": 126.0},
	"inv_destroyer": {"name": "Destroyer", "model": "savager_cruiser", "scale": 4.2, "hull": 3000.0, "shield": 1000.0, "speed": 28.0, "turn": 0.1, "damage": 7.0, "rate": 2.0, "reward": 1000, "capital": true, "hit_r": 84.0, "range": 2000.0, "radius": 90.0},
	"kaiju_hive": {"name": "Kaijurai Hive", "class": "hive station", "faction": "Kaijurai", "model": "kaijurai_ravager", "scale": 1.0, "hull": 9000.0, "shield": 3000.0, "speed": 0.0, "turn": 0.0, "damage": 10.0, "rate": 1.6, "reward": 3500, "capital": true, "hit_r": 90.0, "range": 1300.0, "radius": 40.0},   # v10.8: a placeholder hive (the Ravager, grown) until a real one is made
	"inv_command": {"name": "Star Command Station", "model": "station", "scale": 1.0, "hull": 12000.0, "shield": 4000.0, "speed": 0.0, "turn": 0.0, "damage": 10.0, "rate": 2.0, "reward": 4000, "capital": true, "hit_r": 72.0, "range": 1400.0, "radius": 80.0},
	"raider": {"name": "Raider", "hull": 60.0, "shield": 30.0, "speed": 44.0, "turn": 1.3, "damage": 5.0, "rate": 1.6, "reward": 150},
	"corsair": {"name": "Corsair", "model": "enemy2", "hull": 90.0, "shield": 50.0, "speed": 48.0, "turn": 1.4, "damage": 6.0, "rate": 1.9, "reward": 220, "missiles": true},
	# v1.4w: stand-in fighters from the owner's Imperium and Liberator ship sets (light for slots 1-3, heavy for 4-6)
	"imperium_fighter": {"name": "Imperium Fighter", "class": "fighter", "faction": "Imperium", "model": "imperium_fighter", "hull": 75.0, "shield": 40.0, "speed": 47.0, "turn": 1.4, "damage": 6.0, "rate": 1.7, "reward": 200},
	"imperium_gunship": {"name": "Imperium Gunship", "class": "gunship", "faction": "Imperium", "model": "imperium_gunship", "radius": 9.0, "hull": 130.0, "shield": 70.0, "speed": 42.0, "turn": 1.1, "damage": 7.5, "rate": 2.0, "reward": 360, "missiles": true},
	"liberator_fighter": {"name": "Liberator Fighter", "class": "fighter", "faction": "Liberator", "model": "liberator_fighter", "hull": 65.0, "shield": 40.0, "speed": 49.0, "turn": 1.5, "damage": 5.5, "rate": 1.7, "reward": 190},
	"liberator_heavy": {"name": "Liberator Strike Fighter", "class": "heavy fighter", "faction": "Liberator", "model": "liberator_heavy", "radius": 9.0, "hull": 110.0, "shield": 60.0, "speed": 45.0, "turn": 1.25, "damage": 7.0, "rate": 1.9, "reward": 330, "missiles": true},
	# v1.5c: Covenant (a main faction: its people fly its patrols), Cybermorph and Solrath (permanent enemies: home patrols), Liberator cross fighter
	"covenant_fighter": {"name": "Covenant Fighter", "class": "fighter", "faction": "Covenant", "model": "covenant_fighter", "hull": 70.0, "shield": 50.0, "speed": 49.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 210},
	"covenant_interceptor": {"name": "Covenant Interceptor", "class": "interceptor", "faction": "Covenant", "model": "covenant_interceptor", "hull": 65.0, "shield": 50.0, "speed": 52.0, "turn": 1.6, "damage": 6.0, "rate": 1.8, "reward": 230},
	"covenant_lance": {"name": "Covenant Lance", "class": "heavy fighter", "faction": "Covenant", "model": "covenant_lance", "radius": 9.0, "hull": 115.0, "shield": 75.0, "speed": 46.0, "turn": 1.25, "damage": 7.0, "rate": 1.9, "reward": 340, "missiles": true},
	"cybermorph_fighter": {"name": "Cybermorph Frame Fighter", "class": "fighter", "faction": "Cybermorph", "model": "cybermorph_fighter", "hull": 80.0, "shield": 40.0, "speed": 48.0, "turn": 1.4, "damage": 6.5, "rate": 1.7, "reward": 230},
	"cybermorph_star": {"name": "Cybermorph Star Drone", "class": "drone", "faction": "Cybermorph", "model": "cybermorph_star", "hull": 55.0, "shield": 30.0, "speed": 54.0, "turn": 1.7, "damage": 5.0, "rate": 1.5, "reward": 170},
	"ph_savagers": {"name": "Savagers Fighter", "class": "fighter", "faction": "Savagers", "model": "placeholder_savagers", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_liberator": {"name": "Liberator Fighter", "class": "fighter", "faction": "Liberator", "model": "placeholder_liberator", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_unity": {"name": "Unity Fighter", "class": "fighter", "faction": "Unity", "model": "placeholder_unity", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_imperium": {"name": "Imperium Fighter", "class": "fighter", "faction": "Imperium", "model": "placeholder_imperium", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_elyza": {"name": "Elyza Fighter", "class": "fighter", "faction": "Elyza", "model": "placeholder_elyza", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_covenant": {"name": "Covenant Fighter", "class": "fighter", "faction": "Covenant", "model": "placeholder_covenant", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_solarion": {"name": "Solarion Fighter", "class": "fighter", "faction": "Solarion", "model": "placeholder_solarion", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_orion": {"name": "Orion Fighter", "class": "fighter", "faction": "Orion", "model": "placeholder_orion", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_cybermorph": {"name": "Cybermorph Fighter", "class": "fighter", "faction": "Cybermorph", "model": "placeholder_cybermorph", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_solrath": {"name": "Solrath Fighter", "class": "fighter", "faction": "Solrath", "model": "placeholder_solrath", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_gadversee": {"name": "Gadversee Fighter", "class": "fighter", "faction": "Gadversee", "model": "placeholder_gadversee", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_arctides": {"name": "Arctides Fighter", "class": "fighter", "faction": "Arctides", "model": "placeholder_arctides", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_phenom": {"name": "Phenom Fighter", "class": "fighter", "faction": "Phenom", "model": "placeholder_phenom", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"ph_kaijurai": {"name": "Kaijurai Fighter", "class": "fighter", "faction": "Kaijurai", "model": "placeholder_kaijurai", "hull": 75.0, "shield": 45.0, "speed": 48.0, "turn": 1.45, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true, "placeholder": true},
	"elyza_fighter": {"name": "Elyza Fighter", "class": "fighter", "faction": "Elyza", "model": "elyza_fighter", "radius": 8.0, "hull": 80.0, "shield": 55.0, "speed": 50.0, "turn": 1.5, "damage": 6.5, "rate": 1.7, "reward": 240, "missiles": true},   # v1.5p
	"solrath_blade_a": {"name": "Solrath Blade", "class": "fighter", "faction": "Solrath", "model": "solrath_blade_a", "hull": 70.0, "shield": 45.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 220},
	"solrath_blade_b": {"name": "Solrath Shard", "class": "interceptor", "faction": "Solrath", "model": "solrath_blade_b", "hull": 65.0, "shield": 45.0, "speed": 52.0, "turn": 1.6, "damage": 6.0, "rate": 1.8, "reward": 230},
	"solrath_batwing": {"name": "Solrath Batwing", "class": "heavy fighter", "faction": "Solrath", "model": "solrath_batwing", "radius": 9.0, "hull": 120.0, "shield": 65.0, "speed": 45.0, "turn": 1.25, "damage": 7.0, "rate": 1.9, "reward": 340, "missiles": true},
	"solrath_spire": {"name": "Solrath Spire", "class": "gunship", "faction": "Solrath", "model": "solrath_spire", "radius": 10.0, "hull": 150.0, "shield": 80.0, "speed": 41.0, "turn": 1.1, "damage": 8.0, "rate": 2.0, "reward": 420, "missiles": true},
	"liberator_cross": {"name": "Liberator Cross Fighter", "class": "light fighter", "faction": "Liberator", "model": "liberator_cross", "hull": 55.0, "shield": 35.0, "speed": 52.0, "turn": 1.6, "damage": 5.0, "rate": 1.6, "reward": 160},
	# v1.4y: the owner's Kaijurai and Phenom sets (permanent enemies: no roster, no reputation; they fly their home systems' patrols)
	"kaijurai_dart": {"name": "Kaijurai Dart Fighter", "class": "fighter", "faction": "Kaijurai", "model": "kaijurai_dart", "hull": 70.0, "shield": 40.0, "speed": 49.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 210, "missiles": true},
	"kaijurai_heavy": {"name": "Kaijurai Heavy Fighter", "class": "heavy fighter", "faction": "Kaijurai", "model": "kaijurai_heavy", "radius": 9.0, "hull": 120.0, "shield": 65.0, "speed": 45.0, "turn": 1.25, "damage": 7.0, "rate": 1.9, "reward": 340, "missiles": true},
	"kaijurai_gunship": {"name": "Kaijurai Gunship", "class": "gunship", "faction": "Kaijurai", "model": "kaijurai_gunship", "radius": 10.0, "hull": 150.0, "shield": 80.0, "speed": 41.0, "turn": 1.1, "damage": 8.0, "rate": 2.0, "reward": 420, "missiles": true},
	# v6.2: the second Kaijurai set (enemy space; stronger still there, Data.ENEMY_SPACE_POWER)
	"kaijurai_fang": {"name": "Kaijurai Fang", "class": "fighter", "faction": "Kaijurai", "model": "kaijurai_fang", "radius": 9.0, "hull": 110.0, "shield": 60.0, "speed": 50.0, "turn": 1.5, "damage": 7.0, "rate": 1.6, "reward": 260, "missiles": true},
	"kaijurai_hound": {"name": "Kaijurai Hound", "class": "kaiju cruiser", "faction": "Kaijurai", "model": "kaijurai_hound", "radius": 26.0, "hull": 1600.0, "shield": 400.0, "speed": 46.0, "turn": 1.25, "damage": 10.0, "rate": 2.2, "reward": 2400, "kaiju": true},
	"kaijurai_stalker": {"name": "Kaijurai Stalker", "class": "kaiju cruiser", "faction": "Kaijurai", "model": "kaijurai_stalker", "radius": 30.0, "hull": 1900.0, "shield": 450.0, "speed": 45.0, "turn": 1.2, "damage": 10.0, "rate": 2.2, "reward": 2800, "kaiju": true},
	"kaijurai_reaper": {"name": "Kaijurai Reaper", "class": "kaiju destroyer", "faction": "Kaijurai", "model": "kaijurai_reaper", "radius": 36.0, "hull": 2400.0, "shield": 550.0, "speed": 44.0, "turn": 1.15, "damage": 11.0, "rate": 2.2, "reward": 3400, "kaiju": true},
	"kaijurai_ravager": {"name": "Kaijurai Ravager", "class": "destroyer", "faction": "Kaijurai", "model": "kaijurai_ravager", "radius": 40.0, "hull": 3000.0, "shield": 800.0, "speed": 42.0, "turn": 1.0, "damage": 12.0, "rate": 1.8, "reward": 4000, "missiles": true},
	"phenom_fighter": {"name": "Phenom Fighter", "class": "fighter", "faction": "Phenom", "model": "phenom_fighter", "hull": 70.0, "shield": 45.0, "speed": 49.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 210},
	"phenom_interceptor": {"name": "Phenom Interceptor", "class": "interceptor", "faction": "Phenom", "model": "phenom_interceptor", "hull": 65.0, "shield": 45.0, "speed": 52.0, "turn": 1.6, "damage": 6.0, "rate": 1.8, "reward": 230},
	"phenom_scout": {"name": "Phenom Scout", "class": "scout", "faction": "Phenom", "model": "phenom_scout", "hull": 55.0, "shield": 40.0, "speed": 53.0, "turn": 1.6, "damage": 5.0, "rate": 1.6, "reward": 180},
	"phenom_heavy": {"name": "Phenom Heavy Fighter", "class": "heavy fighter", "faction": "Phenom", "model": "phenom_heavy", "radius": 9.0, "hull": 120.0, "shield": 70.0, "speed": 45.0, "turn": 1.25, "damage": 7.0, "rate": 1.9, "reward": 340, "missiles": true},
	# v1.4r: the Savagers fighter ladder (strike craft only: no battleships as a pilot's ride)
	"scrapfang": {"name": "Scrapfang Light Fighter", "class": "light fighter", "faction": "Savagers", "model": "savager_scrapfang", "hull": 60.0, "shield": 30.0, "speed": 46.0, "turn": 1.4, "damage": 5.0, "rate": 1.6, "reward": 150},
	"redclaw": {"name": "Redclaw Interceptor", "class": "interceptor", "faction": "Savagers", "model": "savager_redclaw", "hull": 80.0, "shield": 45.0, "speed": 50.0, "turn": 1.5, "damage": 6.0, "rate": 1.8, "reward": 220},
	"ironhowl": {"name": "Ironhowl Heavy Fighter", "class": "heavy fighter", "faction": "Savagers", "model": "savager_ironhowl", "radius": 9.0, "hull": 115.0, "shield": 60.0, "speed": 44.0, "turn": 1.2, "damage": 7.0, "rate": 2.0, "reward": 320, "missiles": true},
	"warboar": {"name": "Warboar Command Fighter", "class": "command fighter", "faction": "Savagers", "model": "savager_warboar", "radius": 11.0, "hull": 160.0, "shield": 90.0, "speed": 42.0, "turn": 1.1, "damage": 8.0, "rate": 2.2, "reward": 500, "missiles": true},
	# assault mech: two arm guns + a chest cannon; flies with the raiders/corsairs
	"mech": {"name": "Assault Mech", "hull": 120.0, "shield": 40.0, "speed": 40.0, "turn": 1.2, "damage": 6.0, "rate": 1.4, "reward": 280, "model": "mech_tan", "mech": true, "missiles": true},
	# v1.9i: a faction's boss mech (its own mech, MECH_BOSS_SCALE bigger; the model comes from FACTION_MECH)
	"mech_boss": {"name": "Boss Mech", "hull": 620.0, "shield": 220.0, "speed": 34.0, "turn": 1.0, "damage": 11.0, "rate": 1.3, "reward": 2600, "model": "mech_tan", "mech": true, "missiles": true, "boss": true, "radius": 14.0},
	# Cybermorph (v1.4k): Lockon. Placed in no system yet: no concept sheet or model (the mech body is a stand-in for tests).
	"lockon": {"name": "Lockon", "faction": "Cybermorph", "hull": 220.0, "shield": 80.0, "speed": 42.0, "turn": 1.2, "damage": 7.0, "rate": 1.4, "reward": 600,
		"model": "mech_tan", "mech": true, "missiles": true, "signature": "lockon", "stand_in": true},
}

# ---------------------------------------------------------------- star systems
# Positions in metres-ish world units. The player spawns at `spawn` (station launch) or at the gate exit.
# Every system in the game: the hand-made ones below (CORE_SYSTEMS) plus all the rest of the 11 x 11 map, built by
# SystemBuilder from the map tables. sys["gates"] lists every gate; sys["gate"] is the first one.
static var SYSTEMS: Dictionary = StationNames.apply(ArtRefs.apply(SystemBuilder.all(CORE_SYSTEMS)))   # v1.4k: concept-art references on stations and planets
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
	"assistant": {"name": "Evee", "role": "Your companion (aboard)", "color": Color(0.55, 0.85, 1.0),   # v5.0 (owner): rides in your ship; no "system" = reachable anywhere
		"face": "evee", "voice": 1.3, "female": true,
		"lines": {"friendly": ["[smile]I'm right here, pilot. What do you need?"]}},
	"tutor": {"name": "Kim", "role": "Tech Officer", "color": Color(0.4, 0.75, 1.0),   # v1.7r: the owner's tutorial guide (name to come); no "system" = reachable anywhere
		"face": "tutor", "voice": 1.35, "female": true,
		"lines": {"friendly": ["[smile]Need help? Tap CALL with nothing targeted and I'll walk you through it."]}},
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

# ---------------------------------------------------------------- v9.2 (owner): the hub lockdown (Breakout)
# Dock where your standing is HOSTILE or worse: the alarm goes off, no launching until you fight through to the hangar.
# v9.6 (owner's rules): force fields (open only while a guard fires), hits by rank, zones, laser blade duels, waves.
const BREAKOUT_ON := true
## v12.30 (owner: "a mini game is better than the panorama"): the lockdown is a 3D on-foot escape through destructible
## graybox rooms (StationEscape / VoxRoom); then their fleet chases you and that station won't let you dock.
const ESCAPE_3D := true
const ESCAPE_IN_SPACE := true   # v12.38: the breakout runs in the real mech game (boarding), with the whole HUD
const ESCAPE_TIME := 300.0
## v12.39 EJECT / ENTER (owner): on foot at human size on a world
const FOOT_H := 1.8            # m tall
const FOOT_SPEED := 7.0        # m/s at most
const SPRINT_K := 1.8          # v12.45: SPEED RUN top speed at the start (x the walk)
const SPEED_BOOST_K := 4.0     # ... and fully built up (Metroid's speed booster)
const SPEED_BUILD := 1.6       # s of running to build it up
const JETPACK_SPEED := 22.0    # m/s flying on foot with GROUND off
const JETPACK_BOOST_K := 1.8   # THRUST boost
const EJECT_MAX_SPEED := 6.0   # slow enough to get out
const EJECT_MAX_ALT := 14.0    # m over the ground at most
const EJECT_STEP := 9.0        # m to the side you step out
const ENTER_REACH := 16.0      # m from your mech / ship to ENTER      # s to reach the launch bay
const ESCAPE_PILOT_H := 13.0    # m: the pilot drawn at the mech's size (the decks are mech-sized)
const ESCAPE_CHASERS := 20
# v11.15 (owner): a faction's own lockdown art: every guard is its helmeted soldier, and ONE boss (the marshal who
# comes to arrest you, laser blade) holds the hangar; the rooms before it end with no boss. boss_rush = how often he
# closes in for a blade duel instead of firing.
const BREAKOUT_ART := {
	"orion": {"guard": "res://assets/characters/orion/orion_guard_full.webp", "guard_portrait": "res://assets/characters/orion/orion_guard_portrait.webp",
		"boss": "res://assets/characters/orion/orion_warden_full.webp", "boss_portrait": "res://assets/characters/orion/orion_warden_portrait.webp",
		"boss_name": "Marshal Kade Voss", "one_boss": true, "boss_rush": 0.55,
		"anim": "res://assets/characters/orion/anim", "anim_pack": "anim_orion", "layers": true},   # v11.17: the owner's clips as sprite sheets (tools/crew/clip_sheet.py)
}
## v11.56 (owner): a battleship's inside: exactly 3 military rooms in its faction's own style (pictures:
## assets/rooms_battleship/<faction>/hangar.jpg, spine.jpg, generator.jpg; until they are in, a station room lit red).
## Alarm, waves pour in from all sides; clear one room to open the next; the generator core is the goal; then back out.
const BS_INTERIOR_ROOMS := ["bs_hangar", "bs_spine", "bs_generator"]
const BS_INTERIOR_TITLES := {"bs_hangar": "Breach hangar", "bs_spine": "Reactor spine", "bs_generator": "Generator core"}
const BS_INTERIOR_FALLBACK := {"bs_hangar": "shipyard", "bs_spine": "command", "bs_generator": "mech_dealer"}
const BS_INTERIOR_WAVES := [[5], [5, 8], [6, 10]]   # crew / soldiers per wave, room by room; then the room's boss
const BS_ESCAPE_TIME := 4.0                          # s: the run back to the hangar before you fly out
const BOARD_HP_OPEN := 0.5                           # v11.66 (owner): a battleship's hull at half (or less): its shield is gone for good, board it
const BOARD_SHIELD_DELAY := 15.0                     # v11.66 (owner: "the shield recovery takes a while"): s after the last hit before a battleship's shield starts back
const BOARD_SHIELD_REGEN := 0.01                     # ... then this share of the shield a second (other capitals: 0.02)
const BOARD_NEAR := 2800.0   # v11.89: 4x
#                           # v11.60: BOARD shows within this many metres of a battleship's hull (shield broken)
const REP_INFILTRATE := 15.0                         # standing lost with a faction whose battleship you infiltrate (owner: allies too)
const BREAKOUT_ROOMS := ["main_hub", "pilots_lounge", "shipyard"]   # the way to the hangar, one fight each
const BREAKOUT_WAVES := [[5], [5], [5, 10]]     # guards per wave, room by room (the hangar: five, then ten); then the boss
const BREAKOUT_MAX_ON_FLOOR := 5                # guards on the floor at once (the rest wait to walk in)
# the floor's zones, one guard each: [x from, x to, depth 0 = back .. 1 = front] (fractions of the screen)
const BREAKOUT_ZONES := [[0.08, 0.30, 0.0], [0.40, 0.60, 0.0], [0.70, 0.92, 0.0], [0.14, 0.38, 0.75], [0.62, 0.86, 0.75]]
const BREAKOUT_BOSS_ZONE := [0.38, 0.62, 0.45]
const BREAKOUT_SOLDIER_SLOTS := [1, 1, 1, 1, 5]   # roster slots of the guards (01 common trooper, 05 elite guard)
const BREAKOUT_LEADER_SLOTS := [2, 3, 4]         # the named member who leads each room, in turn ...
const BREAKOUT_FINAL_LEADER := 6                 # ... and the faction's leader holds the hangar
const BREAKOUT_HP := 100.0             # yours, full again in every room
const BREAKOUT_DMG_BASE := 4.0         # a shot that finds you: base + per rank of the shooter
const BREAKOUT_DMG_PER_RANK := 2.0
const BREAKOUT_BLADE_DMG := 14.0       # a blade strike you misread
const BREAKOUT_FIRE_RATE := 3.0        # your shots a second while the sight is on someone (one hit each)
const BREAKOUT_AIM_TIME := 0.9         # s a guard aims (the red line, field down) before it fires: time to duck or side-step
const BREAKOUT_FIRE_TIME := 0.7        # s it stays open after the shot
const BREAKOUT_CALM := [1.4, 3.4]      # s a guard patrols behind its field between shots
const BREAKOUT_WALK := 0.07            # how fast guards pace their zone (screen widths a second)
const BREAKOUT_RUSH_CHANCE := 0.18     # a guard runs at you instead of firing: blades
const BREAKOUT_RUSH_TIME := 1.1
const BREAKOUT_DUEL_WINDUP := 1.0      # s from the blade going up to the strike landing
const BREAKOUT_DUEL_RECOVER := 0.6
const BREAKOUT_CLEAR_PAUSE := 1.6
const BREAKOUT_DOWN_PAUSE := 2.2
const BREAKOUT_SIREN_SECONDS := 4.0
# v11.19 (owner: "4 layers ... they try to get closer and closer; at the front they catch you"): the LAYERS fight
# (a faction's BREAKOUT_ART "layers"): no force fields and no blade duels. Soldiers run in at the back, run sideways,
# and step up one layer at a time; each shot is a muzzle flash and a real laser bolt flying at you that you dodge
# (duck / side-step); one that stays at the front layer for BREAKOUT_CATCH_TIME catches you (arrested).
const BREAKOUT_LAYER_DEPTH := [0.0, 0.34, 0.67, 1.0]   # 4 layers, back to front
const BREAKOUT_LAYER_FEET := [0.60, 0.70, 0.81, 0.96]  # where their feet are on each layer (share of the screen)
const BREAKOUT_LAYER_SCALE := [0.50, 0.70, 0.95, 1.30] # how big they are there
const BREAKOUT_RUN := 0.22             # how fast they run sideways (screen widths a second)
const BREAKOUT_ADVANCE_TIME := 1.4     # s to step up one layer
const BREAKOUT_LAYER_WAIT := [1.6, 3.6] # s on a layer between moves (a shot or a step up)
const BREAKOUT_ADVANCE_CHANCE := 0.5   # each move: step up (else fire)
const BREAKOUT_CATCH_TIME := 3.2       # s at the front layer before they catch you
const BREAKOUT_TURN := 0.32          # v11.21 (owner: "360"): the LAYERS fight's view turns this share of the room a second (left stick)
const BREAKOUT_VIEW := 0.3           # share of the room's loop on screen
const BREAKOUT_FALL_SPEED := 2.0     # v11.23 (owner: "they fall down slow"): the fall clips play this much faster
const BREAKOUT_DEAD_SHOW := 2.4      # s a fallen one stays before it fades
const BREAKOUT_BOLT_TIME := 0.75       # s a laser bolt takes to reach you (time to dodge)
