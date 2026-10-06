class_name Data
extends RefCounted
## Static game data for Homelancer Digital v1.2. All names, ships and places are original Homelancer content.

# Beta version shown on the start screen and on the Hova Matrix landing page (which reads it from web_shell.html).
# Scheme (owner): the letter is the Chief job that shipped it: v1.2x, v1.2y, v1.2z, then v1.3a, v1.3b ...
# Change it in BOTH places for every job: here and the hl-version meta + title in web_shell.html (a test checks it).
const VERSION := "v1.4o"

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
const LOCK_STEP := 0.5                # seconds per lock
const HEAVY_LOCKS := 1                # heavy missile: one lock, hits hard
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
const DODGE_RANGE := 250.0            # a missile can only be shaken inside this distance (boost too early and it just follows you)
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
const BLAST_ENEMY := [24.0, 10, 8, 2, 0.14]
# trade lanes: rings in a row between two places in one system. Dock a ring and the ship is carried down the chain.
const LANE_RING_GAP := 900.0          # metres between rings
const LANE_MAX_RINGS := 8
const LANE_MIN_LEN := 1400.0          # shorter runs get no lane
const LANE_RING_RADIUS := 34.0
const LANE_STACK := 110.0             # the two directions sit this far apart, one ring above the other
const LANE_STANDOFF := 330.0          # the end rings sit this far from the station / planet surface / gate
const LANE_DOCK_RANGE := 240.0        # the LANE prompt shows inside this distance of a ring
const LANE_SPEED := 650.0             # cruise in the lane (m/s)
const LANE_RAMP := 2.5                # seconds to reach it
const LANE_SLOW_DIST := 700.0         # start slowing this far from the last ring
const LANE_EXIT_SPEED := 50.0
const LANE_TINT := Color(0.35, 0.85, 1.0)
const LANE_TUNNEL_LEN := 240.0        # the energy tunnel that rides on the ship
const LANE_TUNNEL_RADIUS := 15.0
const LANE_SPLASH := 0.5              # seconds of ring glow as you pass
# planet type -> surface biome for the one-tile surfaces on every planet (scripts/surface.gd)
const PLANET_BIOME := {"terran": "forest", "jungle": "jungle", "ocean": "ocean", "ice": "ice", "desert": "desert", "lava": "volcanic",
	"dead": "barren", "gas": "clouds", "city": "city", "crystal": "crystal", "toxic": "toxic", "machine": "machine"}

# ---------------------------------------------------------------- Job P (v1.4m)
const TEXT_BUMP := 2                  # HUD and room text below TEXT_BUMP_BELOW px is drawn this much bigger
const TEXT_BUMP_BELOW := 17
const TEXT_MIN := 13                  # nothing on the HUD is smaller than this
# people in station rooms (scripts/npc.gd): one rigged character drawn as a moving cut-out
const NPC_VIEW := Vector2(320, 480)   # the character's own little picture (pixels)
const NPC_HEIGHT_NEAR := 0.86         # share of the screen height the figure fills when close (waist-up)...
const NPC_HEIGHT_FAR := 0.6           # ...and when it has walked back (thigh-up)
const NPC_FRAME_NEAR := 0.5           # the frame starts this far up the body when close (0.5 = the waist)...
const NPC_FRAME_FAR := 0.3            # ...and at mid-thigh when back
const NPC_WALK := 0.012               # stroll speed, in room-picture widths per second
const NPC_PAUSE := [2.5, 6.0]         # seconds they stand between strolls
const NPC_TALK_TIME := 6.0
const NPC_GESTURE_TIME := 2.2
# radar: normal range, and zoom-out when you are far from everything
const RADAR_RANGE := 1600.0
const RADAR_FIT := 1.15               # zoomed out, the farthest place sits this far inside the rim
const RADAR_ZOOM_SPEED := 2.5
# missiles pick a new target when theirs is gone, and firing one wakes the target's wing
const MISSILE_RETARGET := 900.0
const MISSILE_ALERT := 700.0
# galaxy map (flat, fog of war)
const MAP_FOG := Color(0.02, 0.03, 0.06)

# ---------------------------------------------------------------- Job Q (v1.4n): comms split, big racks, restock, burst thrust
# comms console: contacts on the right edge, message log on the left edge, the middle of the screen stays clear
const COMMS_PANEL_W := [200.0, 270.0]   # min / max width of each side panel
const COMMS_PANEL_FRAC := 0.21          # of the screen width
const COMMS_ROW_H := 46.0               # one contact row
const COMMS_IDLE_CLOSE := 20.0          # seconds untouched before the console tucks itself away
# every ship carries the same racks
const MISSILE_LOAD := 100
const HEAVY_LOAD := 50
# flight: stick forward builds up to FORWARD_MULT x ship speed (Cadet: 100 m/s); THRUST is an instant burst at
# BURST_MULT x ship speed (Cadet: 120 m/s) in the stick's direction, straight UP with the stick centred
const FORWARD_MULT := 100.0 / 46.0
const FORWARD_RATE := 0.9               # how quickly stick-forward speed builds (lower = more gradual)
const BURST_MULT := 120.0 / 46.0
const BURST_RATE := 9.0                 # how hard a held burst holds its line
const MECH_BURST_MULT := 3.2            # mech dash (x its walking pace), also used straight up

# ---------------------------------------------------------------- ships
# model: key understood by ShipFactory. "cadet_glb" etc. load real GLBs when present under assets/ships/.
const SHIPS := {
	"cadet": {"name": "Cadet", "class": "Starter fighter", "price": 0, "hull": 100, "shield": 60, "speed": 46.0,
		"turn": 1.7, "guns": 2, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": 3, "model": "cadet", "desc": "Unity-issue trainer. Light, nimble, forgiving. Twin cannons on top."},
	"ranger": {"name": "Ranger", "class": "Patrol fighter", "price": 1500, "hull": 160, "shield": 95, "speed": 50.0,
		"turn": 1.55, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": 4, "model": "ranger", "desc": "Faster frame, thicker plating. A long cannon on top and one on each wing."},
	"hauler": {"name": "Hauler", "class": "Armed cargo ship", "price": 2500, "hull": 320, "shield": 110, "speed": 38.0,
		"turn": 1.0, "guns": 2, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": 8, "model": "hauler", "desc": "A cargo ship you can own. The toughest hull on sale, a big rack, and slow."},
	"bulk_empty": {"name": "Frame Freighter", "class": "Empty cargo ship", "price": 4500, "hull": 400, "shield": 150, "speed": 40.0,
		"turn": 1.0, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": 8, "model": "bulk_empty", "desc": "The Bulk Freighter with an empty cargo frame, ready to carry any crate. Lighter, so faster."},
	"bulk": {"name": "Bulk Freighter", "class": "Heavy cargo ship", "price": 6000, "hull": 480, "shield": 160, "speed": 34.0,
		"turn": 0.8, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": 10, "model": "bulk", "desc": "The biggest ship you can own. Six engines, a huge hull and rack. Very slow to turn."},
	"lancer": {"name": "Lancer", "class": "Heavy fighter", "price": 4000, "hull": 240, "shield": 140, "speed": 42.0,
		"turn": 1.25, "guns": 4, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": 6, "model": "lancer", "desc": "Four cannons: two on the wings, two beside the nose. Heavy shield. Slow to turn."},
}
# v1.3c: all three are the owner's models with weapons mounted (tools/shipkit/make_fleet3.py). Guns = cannons you can see.
const SHIP_ORDER := ["cadet", "ranger", "hauler", "lancer", "bulk_empty", "bulk"]

# ---------------------------------------------------------------- weapons (per gun)
const WEAPONS := {
	"pulse1": {"name": "Pulse Laser Mk I", "price": 0, "damage": 8.0, "rate": 4.0, "speed": 420.0, "range": 520.0, "color": Color(0.45, 0.9, 1.0)},
	"pulse2": {"name": "Pulse Laser Mk II", "price": 600, "damage": 12.0, "rate": 4.5, "speed": 440.0, "range": 540.0, "color": Color(0.5, 1.0, 0.8)},
	"ion": {"name": "Ion Repeater", "price": 1200, "damage": 9.0, "rate": 7.5, "speed": 470.0, "range": 480.0, "color": Color(0.7, 0.6, 1.0)},
	"plasma": {"name": "Plasma Driver", "price": 2600, "damage": 26.0, "rate": 2.4, "speed": 340.0, "range": 560.0, "color": Color(1.0, 0.6, 0.25)},
}
const WEAPON_ORDER := ["pulse1", "pulse2", "ion", "plasma"]
const MISSILE_PRICE := 10
const MISSILE_DAMAGE := 45.0 # light missile minimum; it does LIGHT_MISSILE_HULL_FRAC of the target's hull when bigger
const LIGHT_MISSILE_HULL_FRAC := 0.3
const HEAVY_MISSILE_PRICE := 50
const HEAVY_MISSILE_DAMAGE := 120.0
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
	"corsair": {"name": "Corsair", "model": "enemy2", "hull": 90.0, "shield": 50.0, "speed": 48.0, "turn": 1.4, "damage": 6.0, "rate": 1.9, "reward": 220, "missiles": true},
	# assault mech: two arm guns + a chest cannon; flies with the raiders/corsairs
	"mech": {"name": "Assault Mech", "hull": 120.0, "shield": 40.0, "speed": 40.0, "turn": 1.2, "damage": 6.0, "rate": 1.4, "reward": 280, "model": "mech_tan", "mech": true, "missiles": true},
	# Cybermorph (v1.4k): Lockon. Placed in no system yet: no concept sheet or model (the mech body is a stand-in for tests).
	"lockon": {"name": "Lockon", "faction": "Cybermorph", "hull": 220.0, "shield": 80.0, "speed": 42.0, "turn": 1.2, "damage": 7.0, "rate": 1.4, "reward": 600,
		"model": "mech_tan", "mech": true, "missiles": true, "signature": "lockon", "stand_in": true},
}

# ---------------------------------------------------------------- star systems
# Positions in metres-ish world units. The player spawns at `spawn` (station launch) or at the gate exit.
# Every system in the game: the hand-made ones below (CORE_SYSTEMS) plus all the rest of the 11 x 11 map, built by
# SystemBuilder from the map tables. sys["gates"] lists every gate; sys["gate"] is the first one.
static var SYSTEMS: Dictionary = ArtRefs.apply(SystemBuilder.all(CORE_SYSTEMS))   # v1.4k: concept-art references on stations and planets
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
