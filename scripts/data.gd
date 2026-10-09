class_name Data
extends RefCounted
## Static game data for Homelancer Digital v1.2. All names, ships and places are original Homelancer content.

# Beta version shown on the start screen and on the Hova Matrix landing page (which reads it from web_shell.html).
# Scheme (owner): the letter is the Chief job that shipped it: v1.2x, v1.2y, v1.2z, then v1.3a, v1.3b ...
# Change it in BOTH places for every job: here and the hl-version meta + title in web_shell.html (a test checks it).
const VERSION := "v1.5s"

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
const LANE_TUNNEL_LEN := 640.0        # the energy tunnel that rides on the ship (v1.4u: was 240; long enough to pass behind the camera)
const LANE_TUNNEL_RADIUS := 46.0       # v1.4u: was 15; wide enough that the chase camera sits inside it
const LANE_SPLASH := 0.5              # seconds of ring glow as you pass
# planet type -> surface biome for the one-tile surfaces on every planet (scripts/surface.gd)
const PLANET_BIOME := {"terran": "forest", "jungle": "jungle", "ocean": "ocean", "ice": "ice", "desert": "desert", "lava": "volcanic",
	"dead": "barren", "gas": "clouds", "city": "city", "crystal": "crystal", "toxic": "toxic", "machine": "machine"}

# ---------------------------------------------------------------- Job P (v1.4m)
const TEXT_BUMP := 2                  # HUD and room text below TEXT_BUMP_BELOW px is drawn this much bigger
const TEXT_BUMP_BELOW := 17
const TEXT_MIN := 13                  # nothing on the HUD is smaller than this
# ---------------------------------------------------------------- Job AR (v1.5o): the special lock-on super move (docs/SPECIAL_MOVE.md)
const SPECIAL_ARM_AT := [0.5, 0.25]     # hull shares at which the special arms (half, then critical); once each until repaired
const SPECIAL_RESET_AT := 0.75          # repaired above this, both are ready to earn again
const SPECIAL_LOCK_TIME := 2.4          # hold SPECIAL this long on a locked target to complete the special lock
const SPECIAL_CONE_DEG := 25.0          # keep the target inside this cone ...
const SPECIAL_RANGE := 1300.0           # ... and this range while charging, or the lock breaks
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
const BLOCK_ROCK := Color(0.32, 0.3, 0.29)   # the deep rock colour under the surface
# ---------------------------------------------------------------- Job AT (v1.5q): clean-up + placeholder fighters
# The owner's placeholder fighter set (hlpshplholder_faction): one fighter per faction, tinted in its own colour, so every
# faction's six pilots have a ship (and their voices) until the real ships come. Factions that already fly the owner's
# own ships keep them; PLACEHOLDER_SHIPS says which placeholder each faction has (one line each to swap in).
const PLACEHOLDER_SHIP_LEN := 11.0
const PLACEHOLDER_SHIPS := {"Savagers": "ph_savagers", "Liberator": "ph_liberator", "Unity": "ph_unity", "Imperium": "ph_imperium",
	"Elyza": "ph_elyza", "Covenant": "ph_covenant", "Solarion": "ph_solarion", "Orion": "ph_orion", "Cybermorph": "ph_cybermorph",
	"Solrath": "ph_solrath", "Gadversee": "ph_gadversee", "Arctides": "ph_arctides", "Phenom": "ph_phenom", "Kaijurai": "ph_kaijurai"}
const ELYZA_FIGHTER_LEN := 12.0
const SHIP_WINGS := {"elyza_fighter": 0.125}          # model key -> how far the wings fold in (model units; 0 = open)
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
const SHIP_TAP_RADIUS := 46.0         # a tap this close to a ship on screen targets it
const SCAN_GOODS := ["Water", "Fuel cells", "Ore", "Medical supplies", "Food rations", "Machine parts", "Electronics", "Coolant", "Scrap metal", "Munitions"]
const SCAN_ENEMY_GOODS := {"Savagers": ["Scrap metal", "Stolen goods", "Munitions"], "Cybermorph": ["Nanite slurry", "Data cores"], "Kaijurai": ["Behemoth spores", "Bio-resin"],
	"Phenom": ["Crystal relics", "Void glass"], "Solrath": ["Void ash", "Dark alloy"]}

# ---------------------------------------------------------------- Job AI (v1.5f): missions (scripts/missions.gd)
const MISSION_POINT_DIST := [3200.0, 5200.0]   # a mission point lies this far from the station
const MISSION_ARRIVE := 700.0                   # this close to the point, its wave is there
const MISSION_PLANET_CLEAR := 900.0             # a point keeps this much clear of a planet's surface
const MISSION_GROUP := [3, 3]                   # ships in a wave: [first waves, last wave] (the last of a bounty = target + 2)
const MISSION_PAY := {"threats": 900, "escort": 700}
const MISSION_HARD_MULT := 2.2                  # the ELITE threats job pays this much more
const MISSION_HARD_SLOT := 5                    # ...and sends the slot 05 elites
const MISSION_FALLBACK_ENEMIES := ["Kaijurai", "Phenom", "Cybermorph", "Solrath"]   # when nobody raids the owner
const BOUNTY_ALIVE_RANK := 4                    # named pilots of this rank and up are wanted ALIVE (bring them back); below, dead (paid on the spot)
const REP_MISSION := 3.0                        # standing gained with the giver's faction per job done
const CARGO_HOLD := 8                           # pods and crates a ship carries
const ESCORT_HULL := 600.0                      # the escorted freighter's hull
const ESCORT_FIRE := 25.0                       # hull it loses a second per attacker within ESCORT_RANGE
const ESCORT_RANGE := 500.0
const ESCORT_SPEED := 45.0                      # m/s on its run station -> planet
const ESCORT_AMBUSH := 900.0                    # ambush waves appear this far off the freighter
const ESCORT_DOCK := 260.0                      # this close to the planet dock point it has arrived
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
# which ships fly the patrols of an enemy home system (by the map's role text). The patrol's ships are taken from this
# list in turn. Systems not listed keep sys["enemy"].
const HOME_FLEETS := {
	"Kaijurai home": ["kaijurai_dart", "kaijurai_heavy", "kaijurai_dart", "kaijurai_gunship"],
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
const WARP_BUILD := {"tunnel": 0.5, "cloud": 1.4, "rift": 3.0}     # s: slow start, then fast
const WARP_CLEAR := {"tunnel": 0.3, "cloud": 0.9, "rift": 1.1}     # s: ease out on arrival
const WARP_FLASH := {"tunnel": 0.55, "cloud": 0.0, "rift": 0.0}    # white flash on arrival (0 = smooth, no flash)
const WARP_RINGS := {"tunnel": true, "cloud": true, "rift": false} # fly through the gate rings first (the rift just opens)
const WARP_PACE_SLOW := 0.45         # layers passing per second at the start ("slow booms")
const WARP_PACE_FAST := 4.2          # layers passing per second at full speed (held while the next system loads)
const WARP_SPIN_SLOW := 0.15         # turns per second at the start
const WARP_SPIN_FAST := 1.3          # turns per second at full speed
const WARP_BOOM_BELOW := 0.75        # each passing layer makes a boom while the pace is below this share of full speed
const RIFT_LAYERS := 10              # sheets of sky in the tear (1..12)
const RIFT_OVAL := 1.6               # the tear is this much wider than tall
const RIFT_RAGGED := 0.2             # how torn the edge is (0 = clean oval)
const RIFT_MIST := 0.6               # coloured mist on each tear's edge
const RIFT_TINT_MIN_HUE := 0.12      # two tears in a row differ in hue by at least this
const TUNNEL_TWIST := 0.55           # jump tunnel: how much the energy bands corkscrew
const TUNNEL_BANDS := 3.0            # jump tunnel: bands around the tube (whole number)
const CLOUD_LAYERS := 6              # warp-gate anomaly: gas layers rushing past
const WARP_MAX_STEP := 0.05      # v1.5d: the most warp time one frame may advance (a long build frame does not jump the layers)
const WARP_MIN_COLOUR := 0.55       # the effect's main colour is at least this saturated
const WARP_ALPHA := 0.96             # how solid the effect is at full strength
# ---------------------------------------------------------------- Job AA (v1.4w): seven more faction casts
const GUARD_SIZE := 2                # a faction's own guard wing near its main station (factions that have fighters)
const GUARD_DIST := 520.0            # how far from the station the wing holds
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
const STATION_MODEL_YAW := {"hollow_requiem": 90.0}   # degrees: the dead liner lies across the docking approach

# ---------------------------------------------------------------- Job Y (v1.4u): more room, cleaner prompts, lane tunnel
const SYSTEM_SPREAD := 1.8           # every system: planets, gates, belt, nebula and patrols sit this much farther from the main station (v1.5m: was 1.4)
const DOCK_RANGE_STATION := 190.0    # was 260: you must be this close to a station (or its docking mouth) for DOCK
const DOCK_RANGE_PLANET := 240.0     # was 300: measured from the planet's surface
const LANE_TUNNEL_BACK := 0.42       # share of the lane tunnel's length that trails BEHIND the ship (so the camera never sees its rim)

# ---------------------------------------------------------------- Job X (v1.4t): voice ON by default
const VOICE_DEFAULT := "read"            # "read" = voice ON (lines are spoken), "bleep" = voice OFF (radio blips)
const VOICE_DIR := "res://assets/voices/"   # <voice_id>/<line key>.ogg : a character's recorded or generated lines
const VOICE_KEY_LEN := 60                # letters of the line used for the clip's file name

# ---------------------------------------------------------------- Job W (v1.4s): static faction hub backgrounds
const HUB_BG_DIR := "res://assets/hub_bg/"
const HUB_BG_WASH := 0.38        # dark wash over the faction picture so text reads (0 = none)
const HUB_PANEL_ALPHA := 0.5     # the big content panel: see-through so the faction art stays visible
const HUB_BUTTON_ALPHA := 0.72   # menu and action buttons
const HUB_HEADER_BAND := 0.45    # darkness of the strip behind the title and the credits
# radar: normal range, and zoom-out when you are far from everything
const RADAR_RANGE := 1600.0
const RADAR_FIT := 1.15               # zoomed out, the farthest place sits this far inside the rim
const RADAR_ZOOM_SPEED := 2.5
# missiles pick a new target when theirs is gone, and firing one wakes the target's wing
const MISSILE_RETARGET := 900.0
const MISSILE_ALERT := 700.0
# galaxy map (flat, fog of war)
const MAP_FOG := Color(0.02, 0.03, 0.06)

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
	"gate": "res://assets/nav/gate.jpg", "belt": "res://assets/nav/asteroids.jpg", "nebula": "res://assets/nav/nebula.jpg",
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
	"elyza": {"name": "Elyza Fighter", "class": "Folding-wing fighter", "price": 3500, "hull": 190, "shield": 130, "speed": 50.0,   # v1.5p
		"turn": 1.5, "guns": 3, "missiles": MISSILE_LOAD, "heavy": HEAVY_LOAD, "mines": 4, "model": "elyza_fighter", "desc": "Elyza design. The wings fold in to fly and swing out on their arms for the SPECIAL."},
}
# v1.3c: all three are the owner's models with weapons mounted (tools/shipkit/make_fleet3.py). Guns = cannons you can see.
const SHIP_ORDER := ["cadet", "ranger", "hauler", "elyza", "lancer", "bulk_empty", "bulk"]

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
const ROSTER_PATROL_SIZE := 3    # ships per patrol in a roster faction's own space (other space keeps 2)
const INCURSION_CHANCE := 0.4    # per visit to a rival's system: one small raiding party is there
const INCURSION_SIZE := 2
const INCURSION_NAMED_CHANCE := 0.15   # that the party is led by slot 02 instead of two common soldiers
const BOUNTY_FACE_PX := 96        # portrait size on the bounty board
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
const REP_KILL := 1.5            # standing lost with a faction per ship of theirs you destroy, x the pilot's rank
const REP_BOUNTY := 6.0          # extra standing lost when you hand in one of their named pilots
const REP_RIVAL_SHARE := 1.0     # the rival gains this share of what the faction lost (one shared number per pair)
const REP_HUNTER_SIZE := 3       # RED: a hunter group this big meets you when you enter their space
const REP_HUNTER_DIST := 1100.0
# stations and the light beacon
const STATION_MODEL_SCALE := {"savagers_cross_station": 1.45, "worlds_end_emporium": 1.6, "hollow_requiem": 2.2}   # x the standard station width
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
	return bounties().filter(func(p): return str(p["faction"]) != owner and (str(p["faction"]) == Factions.rival(owner) or not Factions.normal(str(p["faction"])) or str(p["faction"]) == "Savagers"))

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
	"kaijurai_dart": {"name": "Kaijurai Dart Fighter", "class": "fighter", "faction": "Kaijurai", "model": "kaijurai_dart", "hull": 70.0, "shield": 40.0, "speed": 49.0, "turn": 1.5, "damage": 6.0, "rate": 1.7, "reward": 210},
	"kaijurai_heavy": {"name": "Kaijurai Heavy Fighter", "class": "heavy fighter", "faction": "Kaijurai", "model": "kaijurai_heavy", "radius": 9.0, "hull": 120.0, "shield": 65.0, "speed": 45.0, "turn": 1.25, "damage": 7.0, "rate": 1.9, "reward": 340, "missiles": true},
	"kaijurai_gunship": {"name": "Kaijurai Gunship", "class": "gunship", "faction": "Kaijurai", "model": "kaijurai_gunship", "radius": 10.0, "hull": 150.0, "shield": 80.0, "speed": 41.0, "turn": 1.1, "damage": 8.0, "rate": 2.0, "reward": 420, "missiles": true},
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
