extends Node
## Session state (autoload "GS"). Credits, ship, equipment and discovery persist for the whole play session.

signal changed

var credits := 500
var has_cutter := true   # v13.73 (owner: "if you have it, it can provide a short cut"): the CUTTER tool (you start with it for now)
var cutter_level := 0    # v13.133 (owner: "a special item you find ... it can only cut level one doors, unless you get a level two cutter, or even a level three"): the card doors your cutter cuts (0: wreckage only); found aboard fleet ships, kept
var ship_id := "cadet"
var owned_ships := ["cadet"]
var weapon_id := "pulse1"
var owned_weapons := ["pulse1"]
var core_gun := ""
var core_gun2 := ""       # v1.9w: the second front gun (level 2+)
var core_gun3 := ""       # v1.9w: the belly gun (level 3)
var modules: Array = []   # v1.9w: the ability module in each module slot ("" = empty)
var owned_modules: Array = []        # v1.9u (owner): the gun in the ship's core (fires from the nose, always fitted); "" = the main gun
var gun_levels: Dictionary = {}   # v1.9u: Mk level of each gun you have upgraded (1 = Mk I)
var gun_off := {}         # v6.7 (owner, Freelancer weapon list): guns switched off ("core0", 0, 1 ...); this flight only
var mounts: Array = []   # v1.9e: what each hardpoint carries (a gun from Data.WEAPONS or "missile_pod"); [] = every mount the weapon_id
var owned_mechs := ["blackgold"]   # v1.9i: mech frames bought (each gives its arms, core and legs)
var mech_parts := {"arms": "blackgold", "core": "blackgold", "legs": "blackgold"}
var ship_parts := {"cockpit": "", "body": "", "wings": "", "tail": ""}
var owned_parts: Array = []   # v13.268: single parts bought on their own ("mech:<frame>:<part>", "ship:<ship>:<part>")   # v13.266: the ship each part of yours comes from ("" = the one you fly)   # v1.9i: the frame each part comes from
var hull := 100.0
var wing_l := 40.0 # left and right wing sections (own health; a destroyed wing takes its guns with it)
var wing_r := 40.0
var shield := 60.0
var repairs := Data.MAX_REPAIRS
var missiles := 12
var heavy_missiles := 2
var mines := 30
var nukes := Data.NUKE_MAX   # v11.25 (owner)
var rack := "swarm"             # missile rack on the LIGHT slot (Data.MISSILE_RACKS); v1.4l: the Six Rack comes fitted
var owned_racks := ["triple", "swarm"]
var slots: Array = Data.DEFAULT_SLOTS.duplicate()
var shield_charges := Data.MAX_SHIELD_CHARGES
var energy_cells := Data.MAX_ENERGY_CELLS
var energy := Data.ENERGY_MAX
# lasers fire themselves and energy cells top up on their own; shield, repair, missiles and mines are your buttons
var modes := {"shield": "manual", "hull": "manual", "energy": "auto", "guns": "auto", "missile": "manual", "mine": "manual"}
var view := "chase" # "chase" or "cockpit"
var form := "ship" # "ship" or "mech" (the player frame transforms between them; damage carries over)
var system_id := "solara"
var discovered := ["solara"]
var found_stations: Array = []   # v11.54: hidden stations you have found (station ids): they stay on the map
var explored := {}   # v8.9 (owner, Freelancer fog of war): system id -> the 10 x 10 map squares you have seen (v10.3: a "0"/"1" string; v8.9: a bit mask of 8 x 8)
## v8.9: the map square (col, row: 0..7, A..H / 1..8) a point of a system lies in.
static func map_cell(p: Vector3) -> Vector2i:
	var E: float = Data.SPACE_EDGE
	var n: int = Data.MAP_CELLS
	return Vector2i(clampi(int(floor((p.x + E) / (2.0 * E / n))), 0, n - 1), clampi(int(floor((p.z + E) / (2.0 * E / n))), 0, n - 1))
## v10.3 (owner: "1,000 km, ten squares A-J"): the seen squares are a string of "0" / "1", one per square, row by row
## (100 squares no longer fit in one number). An older save's 8 x 8 number is turned into the new squares it covers.
func _seen_mask(sys: String) -> String:
	var n: int = Data.MAP_CELLS
	var v = explored.get(sys, "")
	if typeof(v) == TYPE_STRING and (v as String).length() == n * n: return v
	var out := "0".repeat(n * n)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var old := int(v)
		for row in n:
			for col in n:
				var oc := int(floor((col + 0.5) * 8.0 / n))
				var orow := int(floor((row + 0.5) * 8.0 / n))
				if (old >> (orow * 8 + oc)) & 1 == 1: out[row * n + col] = "1"
	return out
func cell_seen(sys: String, c: Vector2i) -> bool:
	return _seen_mask(sys)[c.y * Data.MAP_CELLS + c.x] == "1"
func seen_at(sys: String, p: Vector3) -> bool: return cell_seen(sys, map_cell(p))
## v12.61: the planet map's fog: a sector is charted once you've flown over it, or with the planet's atlas.
func sector_seen(pid: String, t: int) -> bool: return pid in atlases or t in (planet_seen.get(pid, []) as Array)
func see_sector(pid: String, t: int) -> void:
	if pid == "" or t < 0: return
	var a: Array = planet_seen.get(pid, [])
	if not (t in a):
		a.append(t)
		planet_seen[pid] = a
## v12.61: a tip learned: Evee won't give it again
func learn_tip(id: String) -> void:
	if not (id in tips_known): tips_known.append(id)
## Mark every square within `r` of a point as seen. Returns true when something new was seen.
func explore(sys: String, p: Vector3, r: float) -> bool:
	var m: String = _seen_mask(sys)
	var before := m
	var n: int = Data.MAP_CELLS
	var E: float = Data.SPACE_EDGE
	var w := 2.0 * E / n
	for row in n:
		for col in n:
			var lo := Vector2(-E + col * w, -E + row * w)
			var q := Vector2(clampf(p.x, lo.x, lo.x + w), clampf(p.z, lo.y, lo.y + w))
			if q.distance_to(Vector2(p.x, p.z)) <= r: m[row * n + col] = "1"
	explored[sys] = m
	return m != before
var last_base := "liberty_hub"
var kills := 0
## v13.284 (owner: "a police chase with a heat bar in the faction's colour, not GTA stars"): how wanted you are (0..5),
## by whom, and how many of their ships are on your tail right now (they follow you through a jump or into orbit)
var heat := 0.0
var garage: Array = []   # v13.285: the kinds of car kept in your city garage ("car", "bus", "truck")
var gang_rep := {}        # v13.287: standing with each city gang (name -> -100..100)
var phone_job := {}       # the job you took on the phone ({} = none)
var gang_jobs_done := 0
var radio := 0            # v13.286: the car radio station (Data.RADIO_STATIONS)
var rests := 0           # (tests) times you rested at a safehouse
var heat_fac := ""
var heat_follow := 0
var met: Array = [] # character ids, most recent first
var mood := {} # id -> friendly | neutral | enraged
var memory := {} # id -> what that character remembers about you (see scripts/brain.gd)
var heat_shield := false # EARLY idea: a ship upgrade that survives the sun (nothing sells it yet)
var bounty := {}             # v1.4q: the bounty you carry: {id, sys, state: "hunt" | "captured"}; empty = none
var bounties_done: Array = []   # roster ids already paid
var mission_fails := 0       # v1.9r: jobs failed by dying (each one restarts)
var mission := {}            # v1.5f: the job you carry from a MISSIONS board (see scripts/missions.gd); empty = none
var cargo: Array = []        # v1.5f: the hold: [{kind: "pilot", id, name, note}]
var missions_done := 0       # v1.5f: jobs paid (the boards change with it)
var super_charge := 0.0   # v7.5 (owner): the super meter (0..1): fills while you fight; full = the lightning storm is ready
var special_used := {"half": false, "crit": false}   # v1.5o: the special earned at half / critical hull has been spent
var rep := {}                # v1.4r: reputation, one number per rival pair (Factions.axis_key -> -200..200); empty = everyone at their base
var cast := {}               # v1.4r: named characters' state: character_id -> {alive, current_system, custody}
var mine_kind := "blast"         # v1.5x: which mine you drop: "blast" or "magnetic" (switched at the Equipment screen)
var planet_visits := {}     # v12.52: planet id -> landings (Evee's briefing; a fresh world each time)
var respawn := {}           # v12.60: the last dock: {sys, id, surface, planet, tile}; you're towed back there when you die
var respawn_prev := {}      # v12.61: the home point before the last one (when the last turns hostile, you go here)
var home_pinned := false    # v12.61: SET HOME POINT in your quarters pins it (docks no longer move it)
var planet_seen := {}       # v12.61: planet id -> sectors (tile numbers) you have flown over (the planet map's fog)
var atlases: Array = []     # v12.61: planets whose atlas you bought (their whole map is charted)
var tips_on := true         # v12.61: Evee's tips (until you know them)
var tips_known: Array = []  # v12.61: tips you have shown you know (Evee stops giving them)
var loadouts := {}          # v12.67: frame ("mech" / "ship") -> its loadout (see Loadout): weapon sets, armor parts
var loadout_presets: Array = []   # v12.67: saved loadouts (text)
var weapon_state := {}      # v12.67: weapon id -> {ammo, heat, locked} (kept across swaps)
var pilot_body := "hovick"   # v12.74: who you are on foot (hovick / judy)
var pilot_suit := ""         # v12.76: the body suit you wear ("" = your own)
var creator_done := true     # v12.90: a new pilot goes through the PILOT CREATOR first (false until START FLYING)
var owned_gear: Array = []    # v12.74: pilot gear bought at the PILOT GEAR STORE
var l3_found: Array = []    # v12.68: the Level 3 ships you have downed or found (their model keys)
var relics := {}            # v12.58: alien relics from enemy-faction wrecks: faction -> count (crafting still to come)
var block_deltas := {}       # v1.5t EXPERIMENT: crater notes per block patch ("planet|tile" -> [[x, y, z, kind]]); the ground regrows from the seed and these are re-applied
var bounty_jail := {}        # v1.8k: bounty pilots handed in or killed: id -> unix time they are back
var tutorial_seen: Array = []   # v1.7r: tutorial lesson ids already given (see Data.TUTORIAL)
var god_mode := false # only used by the automated route test

# ---------------------------------------------------------------- v1.7y saving
const SAVE_KEYS := ["gang_rep", "radio", "garage", "owned_parts", "ship_parts", "cutter_level", "build_mats", "credits", "ship_id", "owned_ships", "weapon_id", "owned_weapons", "missiles", "heavy_missiles", "mines", "nukes", "rack",
	"owned_racks", "slots", "modes", "view", "system_id", "discovered", "explored", "last_base", "kills", "met", "mood", "memory", "heat_shield",
	"bounty", "bounties_done", "mission", "cargo", "missions_done", "rep", "cast", "mine_kind", "block_deltas", "tutorial_seen", "bounty_jail", "mounts", "core_gun", "core_gun2", "core_gun3", "modules", "owned_modules", "gun_levels", "owned_mechs", "mech_parts", "pilot_name", "found_stations", "planet_visits", "relics", "respawn", "respawn_prev", "home_pinned", "planet_seen", "atlases", "tips_on", "tips_known", "loadouts", "loadout_presets", "weapon_state", "l3_found", "pilot_body", "owned_gear", "pilot_suit", "creator_done"]   # (v1.9e: + mounts; v1.9i: + owned_mechs, mech_parts; v1.9j: + pilot_name)
var save_path: String = Data.SAVE_PATH
var save_enabled := true   # (the route test turns it off, so a test never reads or writes a player's save)
var saves := 0             # (tests) saves written this session

func has_save() -> bool: return FileAccess.file_exists(save_path)

# ---------------------------------------------------------------- v1.9j (owner): three pilots, each their own save
## Each slot is its own save file on this device; the title screen picks one (and names a new pilot).
var slot := 0                # 0 = none picked yet (the old single save path); 1..SAVE_SLOTS once picked
var pilot_name := ""
var slot_pattern: String = Data.SAVE_SLOT_PATH   # (the route test points these at its own files)
var old_save_path: String = Data.SAVE_PATH
func slot_path(i: int) -> String: return slot_pattern % i
func use_slot(i: int) -> void:
	slot = i
	save_path = slot_path(i)
## What a slot holds, for the picker: {} = empty.
func slot_info(i: int) -> Dictionary:
	var path := slot_path(i)
	if not FileAccess.file_exists(path): return {}
	var d = str_to_var(FileAccess.get_file_as_string(path))
	if not d is Dictionary: return {"name": "Pilot %d" % i, "credits": 0, "system": "", "saved": 0}
	var sid := str(d.get("system_id", "solara"))
	return {"name": str(d.get("pilot_name", "")) if str(d.get("pilot_name", "")) != "" else "Pilot %d" % i, "credits": int(d.get("credits", 0)),
		"system": str(Data.SYSTEMS[sid]["name"]) if Data.SYSTEMS.has(sid) else "", "saved": int(d.get("_saved", 0))}
func erase_slot(i: int) -> void:
	if FileAccess.file_exists(slot_path(i)): DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(i)))
## The one save from before slots becomes slot 1, so nobody loses their progress.
func migrate_old_save() -> void:
	if not save_enabled: return
	if FileAccess.file_exists(old_save_path) and not FileAccess.file_exists(slot_path(1)):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(old_save_path), ProjectSettings.globalize_path(slot_path(1)))

## Write the progress (not the moment-to-moment hull / shields: you start each session fully repaired at your base).
func save_game() -> bool:
	if not save_enabled: return false
	var d := {"_version": Data.VERSION, "_saved": Time.get_unix_time_from_system()}
	for k in SAVE_KEYS: d[k] = get(k)
	if var_to_str(block_deltas).length() > Data.SAVE_DELTAS_MAX: d.erase("block_deltas")
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(var_to_str(d))
	f.close()
	saves += 1
	return true

## Read it back. Only keys it knows, and only when the stored value has the same type (a damaged file can't break
## the game). false = no save.
func load_game() -> bool:
	if not save_enabled or not has_save(): return false
	var txt := FileAccess.get_file_as_string(save_path)
	var d = str_to_var(txt)
	if not d is Dictionary: return false
	for k in SAVE_KEYS:
		if not (d as Dictionary).has(k): continue
		var v = d[k]
		var cur = get(k)
		if typeof(v) == typeof(cur) or (typeof(cur) in [TYPE_INT, TYPE_FLOAT] and typeof(v) in [TYPE_INT, TYPE_FLOAT]): set(k, v)
	if not Data.SYSTEMS.has(system_id): system_id = "solara"
	if not Data.SHIPS.has(ship_id): ship_id = "cadet"
	owned_ships = owned_ships.filter(func(x): return Data.SHIPS.has(str(x)))   # v11.8: ships that left the game (the freighters)
	if not ("cadet" in owned_ships): owned_ships.append("cadet")
	if not Data.WEAPONS.has(weapon_id): weapon_id = "pulse1"
	for p in ["arms", "core", "legs"]:   # v1.9i
		if not Data.MECHS.has(str(mech_parts.get(p, ""))) or not owns_mech_part(str(mech_parts.get(p, "")), p): mech_parts[p] = "blackgold"
	if not ("blackgold" in owned_mechs): owned_mechs.append("blackgold")
	for k in owned_parts.duplicate():   # v13.266: single parts not fitted move into the hold
		var b := str(k).split(":")
		if b.size() == 3 and (Data.MECHS if b[0] == "mech" else Data.SHIPS).has(b[1]) and _fitted(b[0], b[2]) != b[1] and not hold_has(str(k)): _hold_put_part(b[0], b[1], b[2])
	owned_parts.clear()
	changed.emit()
	return true

func erase_save() -> void:
	if has_save(): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

func ship() -> Dictionary: return Data.SHIPS[ship_id]
func weapon() -> Dictionary: return Data.WEAPONS[weapon_id]

# ---------------------------------------------------------------- v1.9e (owner): a gun or a missile pod on each mount
## v1.9e (owner): two mounts on each wing: the SHOULDER (close to the core, on the top side) and the TIP (at the end of
## the wing, on the lower side). Index 0, 1 = left shoulder, left tip; 2, 3 = right shoulder, right tip.
const MOUNT_NAMES := ["Left wing inner (top)", "Left wing tip (under)", "Right wing inner (top)", "Right wing tip (under)", "Left wing middle (top)", "Right wing middle (top)"]   # (v1.9v: the owner's slot sheet words)
func mount_names() -> Array: return MOUNT_NAMES.duplicate()
## v1.9x (owner's mech sheet): the same slots on the mech: the wings are its arms (shoulder, elbow, arm).
const MECH_MOUNT_NAMES := ["Left arm shoulder", "Left arm (lower)", "Right arm shoulder", "Right arm (lower)", "Left elbow", "Right elbow"]

## What each mount carries now: a gun id, a pod id or "empty". A new ship has guns on as many mounts as its "guns"
## (shoulders first), the rest empty.
func mount_items() -> Array:
	var out: Array = []
	var g := int(ship()["guns"])
	var dflt := ["shoulder", "shoulder", "tip", "tip"]   # (fill order: both shoulders, then both tips)
	var order := [0, 2, 1, 3]
	var pairs := (g / 2) * 2   # v1.9u (owner): wing guns come in pairs, one each side (the core fires the odd one)
	var fill: Array = [0, 2, 1, 3, 4, 5].filter(func(x): return mount_open(x))
	for i in 6:   # v1.9w: up to 3 a side (level 3)
		var it: String
		if mounts.size() >= 4: it = str(mounts[i]) if i < mounts.size() else "empty"
		else: it = weapon_id if fill.find(i) >= 0 and fill.find(i) < pairs else "empty"
		if not mount_open(i): it = "empty"
		if it != "empty" and (not (Data.WEAPONS.has(it) or Data.MOUNT_PODS.has(it)) or not (it in owned_weapons)): it = weapon_id
		if is_tip(i) and is_heavy(it): it = "empty"   # v1.9h: heavy mounts sit on the shoulders only
		out.append(it)
	return out

func pods_fitted() -> int:
	return mount_items().filter(func(it): return Data.MOUNT_PODS.has(it)).size()

## v1.9h: a heavy gun or pod (shoulder mounts only).
func is_heavy(it: String) -> bool:
	return bool(Data.WEAPONS.get(it, Data.MOUNT_PODS.get(it, {})).get("heavy", false))

## v1.9h: what all fitted pods add together ("ammo" or "locks").
func pod_sum(key: String) -> int:
	var n := 0
	for it in mount_items():
		if Data.MOUNT_PODS.has(it): n += int(Data.MOUNT_PODS[it][key])
	return n

## v1.9u (owner): how many wing mounts this ship has (2 = the shoulders only, 4 = shoulders and tips).
## v1.9w: the wing tips (under the wing): 1 and 3.
static func is_tip(i: int) -> bool: return i == 1 or i == 3
static func mount_side(i: int) -> float: return -1.0 if i in [0, 1, 4] else 1.0
func ship_level() -> int: return int(Data.SHIP_LEVEL.get(ship_id, 1))
func level_def() -> Dictionary: return Data.LEVELS[ship_level()]
func wing_slots() -> int: return (level_def()["wings"] as Array).size()
func mount_open(i: int) -> bool: return i in (level_def()["wings"] as Array)
## v1.9w: the front guns this ship has (-1 front, -5 second front, -6 belly).
func core_slots() -> Array: return (level_def()["guns"] as Array).duplicate()
func module_slots() -> int: return int(level_def()["modules"])
func module_items() -> Array:
	var out: Array = []
	for i in module_slots(): out.append(str(modules[i]) if i < modules.size() and str(modules[i]) in owned_modules else "")
	return out
## The sum of one effect over the fitted modules (0.0 when none).
func mod(key: String) -> float:
	var t := 0.0
	for m in module_items():
		if m != "": t += float(Data.MODULES[m].get(key, 0.0))
	return t
func buy_module(id: String) -> String:
	var md: Dictionary = Data.MODULES[id]
	if id in owned_modules: return "Already owned: fit it in a module slot."
	if credits < int(md["price"]): return "Not enough credits (%d needed)." % int(md["price"])
	credits -= int(md["price"])
	owned_modules.append(id)
	changed.emit()
	return "Bought the %s. Fit it in a module slot." % md["name"]
func fit_module(slot: int, id: String) -> String:
	if slot < 0 or slot >= module_slots(): return "This ship has %d module slots." % module_slots()
	if id != "" and not (id in owned_modules): return "Buy it first."
	var cur := module_items()
	if id != "" and id in cur and cur.find(id) != slot: cur[cur.find(id)] = ""   # one of each kind: it moves here
	cur[slot] = id
	modules = cur
	shield = minf(shield, max_shield())
	changed.emit()
	return ("%s fitted." % Data.MODULES[id]["name"]) if id != "" else "Module slot emptied."

## v1.9u (owner): the core gun, fired from the ship's nose on top of the wing guns.
func core_item(k := -1) -> String:
	var c: String = {-1: core_gun, -5: core_gun2, -6: core_gun3}.get(k, core_gun)
	if c != "" and Data.WEAPONS.has(c) and c in owned_weapons and not is_heavy(c): return c
	return weapon_id if not is_heavy(weapon_id) else "pulse1"

func fit_core(id: String, k := -1) -> String:
	if not Data.WEAPONS.has(id): return "Only a gun fits the core."
	if not (id in owned_weapons): return "Buy it first."
	if is_heavy(id): return "Heavy guns go on a wing's inner slot, not the core."
	if not (k in core_slots()): return "This ship has no such gun slot."
	match k:
		-5: core_gun2 = id
		-6: core_gun3 = id
		_: core_gun = id
	changed.emit()
	return "%s fitted in the %s." % [Data.WEAPONS[id]["name"], {-1: "front gun slot", -5: "second front gun slot", -6: "belly gun slot"}[k]]

## v1.9u: gun levels (Mk I-V) and what they do.
func gun_level(id: String) -> int: return clampi(int(gun_levels.get(id, 1)), 1, Data.BLASTER_LEVELS)
func gun_damage(id: String) -> float:
	return float(Data.WEAPONS[id]["damage"]) * (1.0 + Data.BLASTER_LEVEL_DMG * float(gun_level(id) - 1))
func upgrade_cost(id: String) -> int:
	return int(maxf(300.0, float(Data.WEAPONS[id]["price"])) * Data.BLASTER_UPGRADE_K * float(gun_level(id)))
func upgrade_gun(id: String) -> String:
	if not (id in owned_weapons): return "Buy it first."
	if gun_level(id) >= Data.BLASTER_LEVELS: return "Already Mk %s, the top level." % roman(gun_level(id))
	var c := upgrade_cost(id)
	if credits < c: return "Not enough credits (%d needed)." % c
	credits -= c
	gun_levels[id] = gun_level(id) + 1
	changed.emit()
	return "%s upgraded to Mk %s." % [Data.WEAPONS[id]["name"], roman(gun_level(id))]
static func roman(n: int) -> String: return ["I", "II", "III", "IV", "V", "VI"][clampi(n - 1, 0, 5)]

## Put an owned gun or pod on one mount.
func fit_mount(i: int, item: String) -> String:
	var items := mount_items()
	if i < 0 or i >= items.size(): return "No such mount."
	if not mount_open(i): return "This ship has no such wing slot (a higher-level ship has more)."
	if item != "empty" and not (item in owned_weapons): return "Buy it first."
	if items[i] == item: return "Already fitted."
	if is_tip(i) and is_heavy(item): return "Heavy mounts go on a shoulder (top, near the core)."
	items[i] = item
	if not items.any(func(x): return Data.WEAPONS.has(x)): return "Keep at least one gun fitted."
	mounts = items
	for it in items:   # the main gun is the first gun on a mount (the HUD and the mech rifle use it)
		if Data.WEAPONS.has(it):
			weapon_id = it
			break
	missiles = mini(missiles, max_missiles())
	changed.emit()
	if item == "empty": return "The %s is empty now." % str(mount_names()[i]).to_lower()
	var nm: String = Data.WEAPONS[item]["name"] if Data.WEAPONS.has(item) else Data.MOUNT_PODS[item]["name"]
	return "%s fitted on the %s." % [nm, str(mount_names()[i]).to_lower()]

## v1.9e: buy a missile pod (fit it on a mount at Equipment).
func buy_pod(id: String) -> String:
	var pd: Dictionary = Data.MOUNT_PODS[id]
	if id in owned_weapons: return "Already owned: fit it on a mount."
	if credits < int(pd["price"]): return "Not enough credits (%d needed)." % int(pd["price"])
	credits -= int(pd["price"])
	owned_weapons.append(id)
	changed.emit()
	return "Bought the %s. Fit it on a wing mount below." % pd["name"]
func max_hull() -> float: return float(ship()["hull"])
func wing_max() -> float: return max_hull() * Data.SECTION_SHARE
## v1.9z: the Heat Shield module (or the old flag) keeps you safe inside a star.
func has_heat_shield() -> bool: return heat_shield or "heat_shield" in module_items()
func max_shield() -> float: return float(ship()["shield"]) * (1.0 + mod("shield"))   # (v1.9w: + Shield Generator)
func max_missiles() -> int: return int(ship()["missiles"]) + pod_sum("ammo")   # v1.9e: pods carry more (v1.9h: each pod its own)
func max_mines() -> int: return maxi(int(ship()["mines"]), Data.MINES_MAX)   # v11.25 (owner): 30 mines
func max_nukes() -> int: return Data.NUKE_MAX
func max_heavy() -> int: return int(ship().get("heavy", 2))
func is_auto(id: String) -> bool: return modes.get(id, "auto") == "auto"

## Adds a character to the contacts roster (or updates their mood). Returns true the first time.
func meet(id: String, m := "friendly") -> bool:
	var first := not (id in met)
	met.erase(id)
	met.push_front(id)
	mood[id] = m
	changed.emit()
	return first

## Docking: the free part (shields, energy, charges). Hull and ammo are the REPAIR and RESTOCK buttons at Equipment.
func dock_service() -> void:
	shield = max_shield()
	energy = Data.ENERGY_MAX
	shield_charges = Data.MAX_SHIELD_CHARGES
	energy_cells = Data.MAX_ENERGY_CELLS
	changed.emit()

## REPAIR: hull, both wings and the repair kits, in one tap. Free at any dock.
func repair_all() -> String:
	if hull >= max_hull() and wing_l >= wing_max() and wing_r >= wing_max() and repairs >= Data.MAX_REPAIRS: return "Nothing to repair."
	hull = max_hull()
	wing_l = wing_max()
	wing_r = wing_max()
	repairs = Data.MAX_REPAIRS
	shield = max_shield()
	special_used = {"half": false, "crit": false}
	super_charge = 0.0
	changed.emit()
	return "Hull, wings and repair kits restored."

func needs_repair() -> bool:
	return hull < max_hull() or wing_l < wing_max() or wing_r < wing_max() or repairs < Data.MAX_REPAIRS

## What a full RESTOCK would cost right now (light + heavy missiles + mines).
func restock_cost() -> int:
	return maxi(0, max_missiles() - missiles) * Data.MISSILE_PRICE + maxi(0, max_heavy() - heavy_missiles) * Data.HEAVY_MISSILE_PRICE + maxi(0, max_mines() - mines) * Data.MINE_PRICE + maxi(0, max_nukes() - nukes) * Data.NUKE_PRICE

## RESTOCK: fill every rack and bill it in one go. Short of credits it loads what you can afford, light missiles first.
func restock_all() -> String:
	var cost := restock_cost()
	if cost <= 0: return "All racks are full."
	var before := credits
	if credits >= cost:
		credits -= cost
		missiles = max_missiles()
		heavy_missiles = max_heavy()
		mines = max_mines()
		nukes = max_nukes()
		changed.emit()
		return "Restocked everything for %d credits." % cost
	buy_missiles(9999)
	buy_heavy(9999)
	buy_mines(9999)
	var nn := mini(max_nukes() - nukes, credits / Data.NUKE_PRICE)   # (nukes last: the dear ones)
	if nn > 0:
		credits -= nn * Data.NUKE_PRICE
		nukes += nn
		changed.emit()
	if credits == before: return "Not enough credits to restock."
	return "Loaded what %d credits would buy. Racks are not full." % (before - credits)

func restore_full() -> void:
	special_used = {"half": false, "crit": false}
	super_charge = 0.0
	hull = max_hull()
	wing_l = wing_max()
	wing_r = wing_max()
	shield = max_shield()
	repairs = Data.MAX_REPAIRS
	missiles = max_missiles()
	mines = max_mines()
	heavy_missiles = max_heavy()
	nukes = max_nukes()
	energy = Data.ENERGY_MAX
	shield_charges = Data.MAX_SHIELD_CHARGES
	energy_cells = Data.MAX_ENERGY_CELLS
	changed.emit()

## v1.4q bounties: take one at a station's BOUNTY board, capture the pilot, dock anywhere to be paid.
func accept_bounty(id: String) -> String:
	var p: Dictionary = Data.roster_pilot(id)
	if p.is_empty() or not p.get("bounty", false): return "No such bounty."
	if id in bounties_done: return "That bounty is already paid."
	if bounty.get("state", "") == "captured": return "Hand in the pilot in your hold first."
	bounty = {"id": id, "sys": p["sys"], "state": "hunt"}
	changed.emit()
	return "Bounty accepted: %s (%s). Last seen in the %s system. Destroy the ship, then TRACTOR the pilot in. A mission waypoint is set: follow the gold marker." % [p["name"], p["type"], Data.SYSTEMS[p["sys"]]["name"]]

func capture_bounty(id: String) -> bool:
	if bounty.get("state", "") == "captured": return false
	if bounty.get("id", "") != id:   # v1.9k: the pilot the bounty JOB is after is always caught (a stale board entry could lose the pod)
		if not (mission.get("kind", "") == "bounty" and str(mission.get("id", "")) == id): return false
		bounty = {"id": id, "sys": str(mission.get("sys", system_id)), "state": "hunt"}
	if bounty.get("state", "") != "hunt": return false
	bounty["state"] = "captured"
	changed.emit()
	return true

## Called on docking: pays a captured bounty. "" = nothing to pay.
## v1.8k: lock a handed-in pilot up; they break out after the time for where they were handed in.
func jail(id: String, where_kind := "station") -> void:
	bounty_jail[id] = Time.get_unix_time_from_system() + (Data.BOUNTY_ESCAPE_PLANET if where_kind == "planet" else Data.BOUNTY_ESCAPE_STATION)

## v1.8k: anyone whose time is up is back on the boards (escaped, or flying again). Returns their ids.
func check_escapes() -> Array:
	var out: Array = []
	var now := Time.get_unix_time_from_system()
	for id in bounty_jail.keys():
		if now < float(bounty_jail[id]): continue
		bounty_jail.erase(id)
		bounties_done.erase(id)
		var p: Dictionary = Data.roster_pilot(str(id))
		var cs: Dictionary = cast_state(str(p.get("character_id", id)))
		_back_kind[id] = "escaped" if bool(cs.get("alive", true)) else "replaced"
		cs["custody"] = false
		cs["alive"] = true
		out.append(id)
	if not out.is_empty(): changed.emit()
	return out

var _back_kind := {}
## The line said when a bounty target is back: a prisoner escaped, or a new masked soldier took a dead one's post.
func last_back_line(id: String) -> String:
	var p: Dictionary = Data.roster_pilot(id)
	if str(_back_kind.get(id, "escaped")) == "replaced": return "A new %s has taken the post: the bounty is posted again." % str(p.get("type", "pilot"))
	return "%s has escaped custody! The bounty is posted again." % str(p.get("name", "A prisoner"))

## Minutes until a jailed pilot breaks out (-1 = not jailed).
func jail_minutes(id: String) -> int:
	if not bounty_jail.has(id): return -1
	return maxi(0, int(ceil((float(bounty_jail[id]) - Time.get_unix_time_from_system()) / 60.0)))

func claim_bounty(where_kind := "station") -> String:
	if bounty.get("state", "") != "captured": return ""
	var id: String = bounty["id"]
	var p: Dictionary = Data.roster_pilot(id)
	var pay: int = Data.bounty_reward(id)
	bounties_done.append(id)
	bounty = {}
	cast_state(p.get("character_id", id))["custody"] = true   # handed over: out of the patrols
	jail(id, where_kind)   # v1.8k: ...for a while
	Factions.adjust(str(p.get("faction", "")), -Data.REP_BOUNTY)
	add_credits(pay)
	return "Bounty paid: %s handed over. +%d cr." % [p.get("name", "the pilot"), pay]

## v1.4r: a named character's persistent record (made on first use: alive, at large, nowhere in particular).
func cast_state(character_id: String) -> Dictionary:
	if not cast.has(character_id): cast[character_id] = {"alive": true, "current_system": "", "custody": false}
	return cast[character_id]

var build_mats := {}   # v12.25: building materials the mech carries (material -> blocks)
func build_count(m: String) -> int: return int(build_mats.get(m, 0))

## v1.8l: a mined piece goes into the hold: one stack per mineral ({kind: "ore", id, n}).
func add_ore(mat: String) -> int:   # (v13.266: 0 = the hold is full)
	for c in cargo:
		if c.get("kind", "") == "ore" and c.get("id", "") == mat:
			if int(c.get("n", 0)) % Data.CARGO_STACK == 0 and hold_free() < 1: return 0
			c["n"] = int(c.get("n", 0)) + 1
			return int(c["n"])
	if hold_free() < 1: return 0
	cargo.append({"kind": "ore", "id": mat, "n": 1})
	return 1

func ore_count(mat: String) -> int:
	for c in cargo:
		if c.get("kind", "") == "ore" and c.get("id", "") == mat: return int(c.get("n", 0))
	return 0

## What this base pays for one piece (its own fixed share of the base price).
func ore_price(mat: String, base_name: String) -> int:
	var sw: Array = Data.ORE_PRICE_SWING
	var k := float(absi((base_name + mat).hash()) % 1000) / 999.0
	return int(round(float(Data.MINE_VALUE.get(mat, 20)) * lerpf(float(sw[0]), float(sw[1]), k) / 5.0)) * 5

func ore_worth(base_name: String) -> int:
	var total := 0
	for c in cargo:
		if c.get("kind", "") == "ore": total += int(c.get("n", 0)) * ore_price(str(c.get("id", "")), base_name)
	return total

func sell_ore(base_name: String) -> String:
	var total := ore_worth(base_name)
	if total <= 0: return "No gold or diamond in the hold."
	cargo = cargo.filter(func(c): return c.get("kind", "") != "ore")
	add_credits(total)
	save_game()
	return "Sold for %d cr." % total

func add_credits(n: int) -> void:
	credits += n
	changed.emit()

## v1.9h: a gun bought or equipped goes on every gun mount it can sit on (a heavy one on the shoulders only).
func _gun_everywhere(id: String) -> Array:
	var items := mount_items()
	for i in items.size():
		if Data.WEAPONS.has(items[i]) and not (is_tip(i) and is_heavy(id)): items[i] = id
	return items

func buy_weapon(id: String) -> String:
	var w: Dictionary = Data.WEAPONS[id]
	if id == weapon_id: return "Already equipped."
	if id in owned_weapons:
		weapon_id = id
		mounts = _gun_everywhere(id)   # v1.9e
		changed.emit()
		return "Equipped %s." % w["name"]
	if credits < int(w["price"]): return "Not enough credits (%d needed)." % int(w["price"])
	credits -= int(w["price"])
	owned_weapons.append(id)
	weapon_id = id
	mounts = _gun_everywhere(id)   # v1.9e: on every gun mount; fit mounts one by one below
	changed.emit()
	return "Bought and equipped %s." % w["name"]

func buy_missiles(n: int) -> String:
	var room := max_missiles() - missiles
	n = mini(n, room)
	if n <= 0: return "Missile rack is full."
	var cost := n * Data.MISSILE_PRICE
	if credits < cost:
		n = credits / Data.MISSILE_PRICE
		if n <= 0: return "Not enough credits."
		cost = n * Data.MISSILE_PRICE
	credits -= cost
	missiles += n
	changed.emit()
	return "Loaded %d missile%s for %d credits." % [n, "" if n == 1 else "s", cost]

func buy_heavy(n: int) -> String:
	var room := max_heavy() - heavy_missiles
	n = mini(n, room)
	if n <= 0: return "Heavy missile rack is full."
	var cost := n * Data.HEAVY_MISSILE_PRICE
	if credits < cost:
		n = credits / Data.HEAVY_MISSILE_PRICE
		if n <= 0: return "Not enough credits."
		cost = n * Data.HEAVY_MISSILE_PRICE
	credits -= cost
	heavy_missiles += n
	changed.emit()
	return "Loaded %d heavy missile%s for %d credits." % [n, "" if n == 1 else "s", cost]

## Ammo left for whatever is fitted in a weapon slot.
func slot_ammo(item: String) -> int:
	match item:
		"light_missile": return missiles
		"heavy_missile": return heavy_missiles
		"mine": return mines
		"nuke": return nukes
	return 0

## Buy a missile rack, or fit one you already own.
func buy_rack(id: String) -> String:
	var r: Dictionary = Data.MISSILE_RACKS[id]
	if not (id in owned_racks):
		if credits < int(r["price"]): return "Not enough credits (%d needed)." % int(r["price"])
		credits -= int(r["price"])
		owned_racks.append(id)
	rack = id
	changed.emit()
	return "%s fitted: %d locks per volley." % [r["name"], int(r["locks"])]

## Most locks a slot item can hold on one target.
func max_locks(item: String) -> int:
	if item == "nuke": return 1   # v11.25: one at a time
	if item == "heavy_missile": return Data.HEAVY_LOCKS + pod_locks(true)   # v11.12 (owner): a heavy box / turret adds super-missile locks
	return int(Data.MISSILE_RACKS.get(rack, Data.MISSILE_RACKS["triple"])["locks"]) + pod_locks(false)   # v1.9e: each pod adds locks (v1.9h: its own)

## v11.12: the locks the fitted pods add, light pods to the light missile, heavy ones to the super missile.
func pod_locks(heavy: bool) -> int:
	var n := 0
	for it in mount_items():
		if Data.MOUNT_PODS.has(it) and bool(Data.MOUNT_PODS[it].get("heavy", false)) == heavy: n += int(Data.MOUNT_PODS[it].get("locks", 0))
	return n

func buy_mines(n: int) -> String:
	var room := max_mines() - mines
	n = mini(n, room)
	if n <= 0: return "Mine rack is full."
	var cost := n * Data.MINE_PRICE
	if credits < cost:
		n = credits / Data.MINE_PRICE
		if n <= 0: return "Not enough credits."
		cost = n * Data.MINE_PRICE
	credits -= cost
	mines += n
	changed.emit()
	return "Loaded %d mine%s for %d credits." % [n, "" if n == 1 else "s", cost]

# ---------------------------------------------------------------- v1.9i (owner): mechs, three swappable parts
## Buy a mech frame: you own its arms, core and legs, and your mech wears the whole frame.
func buy_mech(id: String) -> String:
	if not Data.MECHS.has(id): return "No such frame."
	var f: Dictionary = Data.MECHS[id]
	if not (id in owned_mechs):
		if credits < int(f["price"]): return "Not enough credits (%d needed)." % int(f["price"])
		credits -= int(f["price"])
		owned_mechs.append(id)
	mech_parts = {"arms": id, "core": id, "legs": id}
	changed.emit()
	return "%s: all three parts fitted." % f["name"]

## Fit one part (arms / core / legs) from a frame you own. Arms are always a matched pair.
## v13.268: you own a part when you own its whole frame / ship, or bought that part on its own.
## v13.266 (owner: "when you equip a new part the old one goes to your cargo hold, keep it or sell it"): a single part
## is yours while it is fitted or in the hold. (A frame or ship you own keeps all its parts in the hangar.)
func owns_mech_part(fid: String, part: String) -> bool: return fid in owned_mechs or _fitted("mech", part) == fid or ("mech:%s:%s" % [fid, part]) in owned_parts or hold_has("mech:%s:%s" % [fid, part])
func owns_ship_part(sid: String, part: String) -> bool: return sid in owned_ships or _fitted("ship", part) == sid or ("ship:%s:%s" % [sid, part]) in owned_parts or hold_has("ship:%s:%s" % [sid, part])
func _fitted(kind: String, part: String) -> String:
	if kind == "mech": return str(mech_parts.get(part, mech_parts.get("core", "")))
	var id := str(ship_parts.get(part, ""))
	return id if id != "" else ship_id
## A fitted part that's only yours as a single part (not from a frame / ship you own): it goes to the hold when swapped.
func _loose(kind: String, id: String) -> bool:
	if id == "": return false
	return not (id in owned_mechs) if kind == "mech" else (id != ship_id and not (id in owned_ships))

# ---------------------------------------------------------------- v13.266 (owner): the cargo hold
## How much your ship carries: by its level (Level 1 / 2 / 3 fighters), a cargo ship the most.
func hold_size() -> int:
	var s: Dictionary = Data.SHIPS.get(ship_id, {})
	if str(s.get("class", "")).to_lower().find("cargo") >= 0: return Data.HOLD_CARGO_SHIP
	var pr := int(s.get("price", 0))
	return int(Data.HOLD_BY_LEVEL[2 if pr >= Data.HOLD_L3_PRICE else (1 if pr >= Data.HOLD_L2_PRICE else 0)])
## Space one hold item takes: a part or crate 1, a stack 1 per CARGO_STACK pieces, a prisoner none (the brig).
static func hold_slots(c: Dictionary) -> int:
	if c.get("kind", "") == "pilot": return 0
	if c.has("crates"): return int(c["crates"])
	if c.has("n"): return maxi(1, ceili(float(c["n"]) / float(Data.CARGO_STACK)))
	return 1
func hold_used() -> int:
	var n := 0
	for c in cargo: n += hold_slots(c)
	return n
func hold_free() -> int: return Data.HOLD_ROOM_NO_LIMIT if hold_no_limit else hold_size() - hold_used()
## v13.296 (owner: "no limit inventory"): the hold never fills (tests can switch the old ship-level limit back on).
var hold_no_limit := Data.HOLD_NO_LIMIT
## What the HUD and pages say about the hold: "12 things" with no limit, else "used / size".
func hold_text() -> String:
	if hold_no_limit: return "%d" % hold_used()
	return "%d / %d" % [hold_used(), hold_size()]
## v13.296 (owner: "at any station, a SELL ALL inventory option"): what this base pays for everything it will buy
## (ore, goods, spare parts, salvaged weapons). Prisoners and job crates stay; contraband only sells at a smugglers' base.
func sell_all_worth(base_name: String, kind: String, here: String) -> int:
	var t := 0
	for c in cargo: t += _sell_all_one(c, base_name, kind, here)
	return t
func _sell_all_one(c: Dictionary, base_name: String, kind: String, here: String) -> int:
	match str(c.get("kind", "")):
		"ore": return int(c.get("n", 0)) * ore_price(str(c.get("id", "")), base_name)
		"goods": return goods_sell_price(str(c["id"]), str(c.get("from", here)), kind, here) * int(c.get("n", 0))
		"part", "weapon": return cargo_sell_price(c)
	return 0
func sell_all(base_name: String, kind: String, here: String) -> String:
	var t := 0
	var n := 0
	var keep: Array = []
	for c in cargo:
		var p := _sell_all_one(c, base_name, kind, here)
		if p > 0:
			t += p
			n += 1
		else: keep.append(c)
	if n == 0: return "Nothing here this base will buy."
	cargo = keep
	add_credits(t)
	save_game()
	return "Sold %d thing%s from your hold for %d cr.%s" % [n, "" if n == 1 else "s", t, ("  Kept: %d (prisoners, job crates or goods nobody here buys)." % keep.size()) if not keep.is_empty() else ""]
func hold_has(key: String) -> bool:
	for c in cargo:
		if c.get("kind", "") == "part" and str(c.get("key", "")) == key: return true
	return false
func _hold_take(key: String) -> bool:
	for i in cargo.size():
		if cargo[i].get("kind", "") == "part" and str(cargo[i].get("key", "")) == key:
			cargo.remove_at(i)
			return true
	return false
func _hold_put_part(kind: String, id: String, part: String) -> void:
	var D: Dictionary = (Data.MECHS if kind == "mech" else Data.SHIPS)[id]
	cargo.append({"kind": "part", "key": "%s:%s:%s" % [kind, id, part], "name": "%s %s" % [str(D.get("short", D["name"])), part], "note": "spare part"})
## What a station pays for a part from your hold.
func part_sell_price(key: String) -> int:
	var b := key.split(":")
	if b.size() < 3 or not (Data.MECHS if b[0] == "mech" else Data.SHIPS).has(b[1]): return 0
	return int(part_price(b[0], b[1]) * Data.PART_SELL_K)
## What a base pays for one thing in the hold (a part or a salvaged weapon).
func cargo_sell_price(c: Dictionary) -> int:
	if c.get("kind", "") == "part": return part_sell_price(str(c.get("key", "")))
	if c.get("kind", "") == "weapon": return maxi(50, int(int(Data.WEAPONS.get(str(c.get("id", "")), {}).get("price", 0)) * Data.PART_SELL_K))
	return 0
## v13.267: KEEP a salvaged weapon: out of the hold into your armory (fit it under LOADOUT).
func keep_weapon(i: int) -> String:
	if i < 0 or i >= cargo.size() or cargo[i].get("kind", "") != "weapon": return "Nothing to keep."
	var id := str(cargo[i]["id"])
	if id in owned_weapons: return "You have one already: sell this one."
	cargo.remove_at(i)
	owned_weapons.append(id)
	changed.emit()
	save_game()
	return "%s is in your armory. Fit it under LOADOUT." % Data.WEAPONS[id]["name"]
## v13.295 (owner: "a place to check my inventory, discard what I don't want to keep, and equip what I just got"):
## what can be thrown out of the hold in flight (not a prisoner, not a job's delivery crates).
static func can_drop(c: Dictionary) -> bool: return not (str(c.get("kind", "")) in ["pilot", "delivery"])
## DROP from the hold: n pieces of a stack (n < 1 = all of it) or the one thing. Returns what went out ({} = nothing).
func drop_cargo(i: int, n := -1) -> Dictionary:
	if i < 0 or i >= cargo.size() or not can_drop(cargo[i]): return {}
	var c: Dictionary = cargo[i]
	var out := c.duplicate()
	if c.has("n") and n > 0 and n < int(c["n"]):
		c["n"] = int(c["n"]) - n
		out["n"] = n
	else: cargo.remove_at(i)
	changed.emit()
	save_game()
	return out
## EQUIP a weapon from the hold straight onto your guns (it joins your armory; a spare of one you have stays in the hold).
func equip_from_hold(i: int) -> String:
	if i < 0 or i >= cargo.size() or cargo[i].get("kind", "") != "weapon": return "Only a weapon can be equipped from the hold."
	var id := str(cargo[i]["id"])
	if not Data.WEAPONS.has(id): return "Unknown weapon."
	var spare := id in owned_weapons
	if not spare:
		cargo.remove_at(i)
		owned_weapons.append(id)
	weapon_id = id
	mounts = _gun_everywhere(id)
	changed.emit()
	save_game()
	return "%s equipped on your guns.%s" % [Data.WEAPONS[id]["name"], " You had one already: the spare stays in the hold." if spare else ""]
## SELL one thing from the hold (a part or a weapon; ore has its own SELL ORE).
func sell_cargo(i: int) -> String:
	if i < 0 or i >= cargo.size() or not (cargo[i].get("kind", "") in ["part", "weapon"]): return "Nothing to sell."
	var c: Dictionary = cargo[i]
	var pr := cargo_sell_price(c)
	cargo.remove_at(i)
	add_credits(pr)
	save_game()
	return "%s sold for %d cr." % [str(c.get("name", "Part")), pr]
# ---------------------------------------------------------------- v13.268 (owner): light trade
static func goods_def(id: String) -> Dictionary: return Data.TRADE_GOODS.get(id, Data.CONTRABAND.get(id, {}))
static func is_contraband(id: String) -> bool: return Data.CONTRABAND.has(id)
static func shady(sys_id: String) -> bool: return sys_id in Data.SHADY_SYSTEMS
## Jumps between two systems (far if there's no route).
static func jumps(a: String, b: String) -> int:
	var r: Array = Data.gate_route(a, b)
	return Data.TRADE_JUMPS_MAX if r.is_empty() else r.size() - 1
func goods_buy_price(id: String, kind: String) -> int:
	return maxi(1, int(round(float(goods_def(id).get("price", 0)) * (Data.PLANET_BUY_K if kind == "planet" else Data.STATION_BUY_K))))
## What this base pays for one: planets little, stations more, and more for every jump from where it was bought.
func goods_sell_price(id: String, from_sys: String, kind: String, here: String) -> int:
	if is_contraband(id) and not shady(here): return 0
	var k: float = Data.PLANET_SELL_K if kind == "planet" else Data.STATION_SELL_K
	k *= 1.0 + Data.TRADE_JUMP_K * mini(jumps(from_sys, here), Data.TRADE_JUMPS_MAX)
	return maxi(1, int(round(float(goods_def(id).get("price", 0)) * k)))
## n of one good into the hold (stacks by good and where it came from). False = no room.
func add_goods(id: String, from_sys: String, n: int) -> bool:
	for c in cargo:
		if c.get("kind", "") == "goods" and c.get("id", "") == id and c.get("from", "") == from_sys:
			var more := ceili(float(int(c["n"]) + n) / Data.CARGO_STACK) - ceili(float(int(c["n"])) / Data.CARGO_STACK)
			if more > hold_free(): return false
			c["n"] = int(c["n"]) + n
			changed.emit()
			return true
	if ceili(float(n) / Data.CARGO_STACK) > hold_free(): return false
	cargo.append({"kind": "goods", "id": id, "from": from_sys, "n": n, "name": str(goods_def(id).get("name", id)), "note": "contraband" if is_contraband(id) else "trade goods"})
	changed.emit()
	return true
## BUY a lot of goods here (contraband only at a smugglers' base).
func buy_goods(id: String, kind: String, here: String, n := Data.TRADE_BUY_LOT) -> String:
	if goods_def(id).is_empty(): return "No such goods."
	if is_contraband(id) and not shady(here): return "Nobody here sells that."
	var cost := goods_buy_price(id, kind) * n
	if credits < cost: return "Not enough credits (%d cr)." % cost
	if not add_goods(id, here, n): return "Hold full (%s)." % hold_text()
	credits -= cost
	changed.emit()
	return "Bought %d %s for %d cr. Stations farther away pay more." % [n, str(goods_def(id)["name"]), cost]
## SELL one stack of goods from the hold here.
func sell_goods(i: int, kind: String, here: String) -> String:
	if i < 0 or i >= cargo.size() or cargo[i].get("kind", "") != "goods": return "Nothing to sell."
	var c: Dictionary = cargo[i]
	var each := goods_sell_price(str(c["id"]), str(c.get("from", here)), kind, here)
	if each <= 0: return "Nobody here will touch that. Try a smugglers' base (Shroud)."
	var tot := each * int(c["n"])
	cargo.remove_at(i)
	add_credits(tot)
	save_game()
	return "Sold %d %s for %d cr." % [int(c["n"]), str(c.get("name", "goods")), tot]
func contraband_worth() -> int:
	var t := 0
	for c in cargo:
		if c.get("kind", "") == "goods" and is_contraband(str(c["id"])): t += int(goods_def(str(c["id"])).get("price", 0)) * int(c["n"])
	return t
## Docking at a lawful base with contraband: a customs patrol may scan you: it's taken and you're fined. "" = clean.
func customs_scan(here: String, roll: float, fac := "") -> String:
	if shady(here): return ""
	var worth := contraband_worth()
	if worth <= 0 or roll >= Data.CONTRABAND_SCAN: return ""
	if fac != "": Factions.adjust(fac, -Data.REP_CONTRABAND)   # v13.271: your standing with them drops
	var fine := mini(credits, int(worth * Data.CONTRABAND_FINE_K))
	cargo = cargo.filter(func(c): return not (c.get("kind", "") == "goods" and is_contraband(str(c["id"]))))
	credits -= fine
	changed.emit()
	return "CUSTOMS SCAN: a patrol found contraband in your hold. It's confiscated and you're fined %d cr.%s" % [fine, (" Your standing with %s drops." % fac) if fac != "" and Factions.normal(fac) else ""]

## Shot down: the hold goes with the ship (prisoners ride in the brig pod and are kept). Returns how many were lost.
func lose_cargo() -> int:
	var lost := 0
	for c in cargo: if c.get("kind", "") != "pilot": lost += 1
	cargo = cargo.filter(func(c): return c.get("kind", "") == "pilot")
	if lost > 0: changed.emit()
	return lost
## Swap a part in: the new one comes out of the hold if it was there, the old one goes in if it's a single part.
func _swap_part(kind: String, part: String, id: String) -> String:
	var old := _fitted(kind, part)
	var key := "%s:%s:%s" % [kind, id, part]
	var from_hold := hold_has(key)
	var old_in := _loose(kind, old) and old != id
	if old_in and not from_hold and hold_free() < 1: return "Hold full: sell something first."
	if from_hold: _hold_take(key)
	if old_in: _hold_put_part(kind, old, part)
	owned_parts.erase("%s:%s:%s" % [kind, old, part])
	owned_parts.erase(key)
	if kind == "mech": mech_parts[part] = id
	else: ship_parts[part] = "" if id == ship_id else id
	changed.emit()
	return ""
func part_price(kind: String, id: String) -> int:
	var full: int = int((Data.MECHS if kind == "mech" else Data.SHIPS)[id].get("price", 0))
	return maxi(Data.PART_PRICE_MIN, int(full * Data.PART_PRICE_K))
## BUY & EQUIP one part.
func buy_part(kind: String, id: String, part: String) -> String:
	if (kind == "mech" and owns_mech_part(id, part)) or (kind == "ship" and owns_ship_part(id, part)): return fit_mech_part(part, id) if kind == "mech" else fit_ship_part(part, id)
	var pr := part_price(kind, id)
	if credits < pr: return "Not enough credits (%d cr)." % pr
	if _loose(kind, _fitted(kind, part)) and hold_free() < 1: return "Hold full: sell something first."
	credits -= pr
	_swap_part(kind, part, id)
	var D: Dictionary = (Data.MECHS if kind == "mech" else Data.SHIPS)[id]
	return "Bought for %d cr. %s %s fitted." % [pr, str(D["name"]), part]
## UNEQUIP: the frame's / ship's own part back (the core's own head, arms, legs; your ship's own cockpit, wings, tail).
func unequip_part(kind: String, part: String) -> String:
	if kind == "mech":
		if part == "core": return "The core is the frame itself: fit another core instead."
		var note := " The old one is in your hold." if _loose("mech", _fitted("mech", part)) else ""
		var why := _swap_part("mech", part, str(mech_parts.get("core", "blackgold")))
		if why != "": return why
		return "Back to the %s's own %s.%s" % [Data.MECHS[str(mech_parts["core"])]["name"], part, note]
	var note2 := " The old one is in your hold." if _loose("ship", _fitted("ship", part)) else ""
	var why2 := _swap_part("ship", part, ship_id)
	if why2 != "": return why2
	return "Back to the %s's own %s.%s" % [Data.SHIPS[ship_id]["name"], part, note2]

func fit_mech_part(part: String, id: String) -> String:
	if not (part in ["arms", "core", "legs", "head"]) or not Data.MECHS.has(id): return "No such part."
	if not owns_mech_part(id, part): return "Buy that part first."
	if _fitted("mech", part) == id: return "Already fitted."
	var why := _swap_part("mech", part, id)
	if why != "": return why
	return "%s %s fitted." % [Data.MECHS[id]["name"], str(Data.MECH_PART_NAMES[part]).to_lower()]

## v13.266 (owner: "switch out the ship's cockpit, body, wings and tail"): fit one part of your ship from another ship
## you own ("" = back to your own ship's). The look only: the stats stay your ship's.
func fit_ship_part(part: String, id: String) -> String:
	if not (part in ShipParts.PARTS): return "No such part."
	if id != "" and (not Data.SHIPS.has(id) or not owns_ship_part(id, part)): return "Buy that part first."
	if id == "": id = ship_id
	if _fitted("ship", part) == id: return "Already fitted."
	var why := _swap_part("ship", part, id)
	if why != "": return why
	return "%s %s fitted." % [Data.SHIPS[id]["name"], part]

## The model key of each part of your ship (all the same when nothing is swapped).
func ship_keys() -> Dictionary:
	var out := {}
	for p in ShipParts.PARTS:
		var id := str(ship_parts.get(p, ""))
		out[p] = str(Data.SHIPS[id if id != "" and Data.SHIPS.has(id) else ship_id]["model"])
	return out

func ship_swapped() -> bool:
	for p in ShipParts.PARTS:
		var id := str(ship_parts.get(p, ""))
		if id != "" and id != ship_id and Data.SHIPS.has(id): return true
	return false

## The model key each part comes from.
func mech_keys() -> Dictionary:
	var out := {}
	for p in ["arms", "core", "legs"]: out[p] = str(Data.MECHS[str(mech_parts.get(p, "blackgold"))]["model"])
	var hid := str(mech_parts.get("head", ""))
	if not Data.MECHS.has(hid) or not owns_mech_part(hid, "head"): hid = str(mech_parts.get("core", "blackgold"))
	out["head"] = str(Data.MECHS[hid]["model"])   # v13.266: the head (the core's own until you fit another)
	return out

## Mech-form stats from the fitted parts: armor from the core, gun power from the arms, pace from the legs.
func mech_armor() -> float: return float(Data.MECHS[str(mech_parts["core"])]["armor"])
func mech_arm() -> float: return float(Data.MECHS[str(mech_parts["arms"])]["arm"])
func mech_speed() -> float: return float(Data.MECHS[str(mech_parts["legs"])]["speed"])

func buy_ship(id: String) -> String:
	var s: Dictionary = Data.SHIPS[id]
	if id == ship_id: return "You are flying the %s." % s["name"]
	if not (id in owned_ships):
		if credits < int(s["price"]): return "Not enough credits (%d needed)." % int(s["price"])
		credits -= int(s["price"])
		owned_ships.append(id)
	ship_id = id
	mounts = []   # v1.9u (owner): a new ship starts with its own even loadout (the old wing fit could leave one side bare)
	restore_full()
	return "The %s is fuelled, armed and ready." % s["name"]

## Shield first; then the wing on the side that was hit (if it is still there), else the core hull.
## Returns "l"/"r" when that hit just destroyed a wing, else "".
func damage(amount: float, side := "") -> String:
	if god_mode: amount *= 0.0
	var absorbed := minf(shield, amount)
	shield -= absorbed
	var rest := amount - absorbed
	var broke := ""
	if rest > 0.0 and side == "l" and wing_l > 0.0:
		wing_l -= rest
		if wing_l <= 0.0:
			wing_l = 0.0
			broke = "l"
	elif rest > 0.0 and side == "r" and wing_r > 0.0:
		wing_r -= rest
		if wing_r <= 0.0:
			wing_r = 0.0
			broke = "r"
	else:
		hull = maxf(0.0, hull - rest)
	changed.emit()
	return broke

## Collision damage (Job L). v1.4l, owner: the shield takes it first; only what gets through reaches the core hull.
## Returns what was taken in all (shield + hull).
func collide(amount: float) -> float:
	if god_mode: amount = 0.0
	var absorbed := minf(shield, amount)
	shield -= absorbed
	var before := hull
	hull = maxf(0.0, hull - (amount - absorbed))
	changed.emit()
	return absorbed + (before - hull)

func use_repair() -> bool:
	if repairs <= 0 or hull >= max_hull(): return false
	repairs -= 1
	hull = minf(max_hull(), hull + max_hull() * Data.REPAIR_AMOUNT)
	changed.emit()
	return true
