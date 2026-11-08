class_name Loadout
## v12.67 (owner's spec: "Weapon Attachment & Modular Armor", clean-room, Armored Core-inspired: no AC code or assets):
## ONE data-driven loadout system for MECHS and SHIPS.
##   * mount points, each with the weapon classes it takes, a max weight and an energy cap
##   * weapons as data (id, class, mounts, mesh, damage, rate, ammo, heat, weight, energy draw, HUD icon)
##   * weapon SETS you hot-swap in combat (the old ones stow on the mech's back / retract into the ship's hull)
##   * modular armor parts (mech Head / Core / Arms / Legs, ship Hull / Wings / Engines), each with its own armor,
##     weight and energy; legs / engines carry the weight, the core / hull's generator powers the energy
##   * the totals feed speed, boost and stagger; over the weight capacity = slower; over the generator = no build
##   * loadouts saved as plain data (GS.loadouts, presets); the AI enemies are given loadouts the same way

# ---------------------------------------------------------------- mount points
## frame -> mount -> {classes, max_w (weight a mount takes), e_cap (energy one weapon there may draw), at (where on
## the frame, as a share of its box: x side, y up, z forward(-) / back(+))}
const MOUNTS := {
	"mech": {
		"L_Arm": {"classes": ["blaster", "rifle", "cannon", "rail"], "max_w": 14.0, "e_cap": 32.0, "at": Vector3(-0.62, 0.52, -0.28), "label": "Left arm"},
		"R_Arm": {"classes": ["blaster", "rifle", "cannon", "rail"], "max_w": 14.0, "e_cap": 32.0, "at": Vector3(0.62, 0.52, -0.28), "label": "Right arm"},
		"L_Shoulder": {"classes": ["heavy", "missile", "rail", "cannon"], "max_w": 36.0, "e_cap": 48.0, "at": Vector3(-0.42, 0.9, 0.05), "label": "Left shoulder"},
		"R_Shoulder": {"classes": ["heavy", "missile", "rail", "cannon"], "max_w": 36.0, "e_cap": 48.0, "at": Vector3(0.42, 0.9, 0.05), "label": "Right shoulder"},
		"Back_Stow": {"classes": [], "max_w": 0.0, "e_cap": 0.0, "at": Vector3(0.0, 0.66, 0.42), "label": "Back (stowed)", "stow": true},
	},
	"ship": {
		"Nose": {"classes": ["blaster", "rifle", "rail"], "max_w": 10.0, "e_cap": 30.0, "at": Vector3(0.0, -0.1, -0.5), "label": "Nose"},
		"Wing_L": {"classes": ["blaster", "rifle", "cannon", "rail", "missile"], "max_w": 14.0, "e_cap": 34.0, "at": Vector3(-0.62, 0.0, 0.05), "label": "Left wing"},
		"Wing_R": {"classes": ["blaster", "rifle", "cannon", "rail", "missile"], "max_w": 14.0, "e_cap": 34.0, "at": Vector3(0.62, 0.0, 0.05), "label": "Right wing"},
		"Dorsal": {"classes": ["heavy", "cannon", "missile"], "max_w": 34.0, "e_cap": 46.0, "at": Vector3(0.0, 0.55, 0.1), "label": "Dorsal (top)"},
		"Ventral": {"classes": ["cannon", "rail", "missile", "blaster"], "max_w": 16.0, "e_cap": 36.0, "at": Vector3(0.0, -0.55, 0.0), "label": "Ventral (belly)"},
	},
	# v12.68 (owner's spec: "shared weapons can be Mech+Pilot, scaled per user"): the pilot on foot
	"pilot": {
		"R_Hand": {"classes": ["blaster", "rifle", "cannon", "rail"], "max_w": 10.0, "e_cap": 24.0, "at": Vector3(0.32, 0.55, -0.25), "label": "Right hand"},
		"Sidearm": {"classes": ["blaster"], "max_w": 7.0, "e_cap": 16.0, "at": Vector3(0.36, 0.47, 0.0), "label": "Sidearm (hip)", "holster": true},   # v12.74: the secondary weapon
		"Back_Stow": {"classes": [], "max_w": 0.0, "e_cap": 0.0, "at": Vector3(0.0, 0.7, 0.3), "label": "Back (stowed)", "stow": true},
	},
}
## v12.68: weapons on these mounts hang UPSIDE DOWN under the ship, the grip clicked into the hardpoint
const HANG_MOUNTS := ["Wing_L", "Wing_R", "Ventral"]
## v12.68: how big a weapon is for each user (a pilot's gun is bigger next to him than a mech's next to it)
const USER_SCALE := {"mech": 1.0, "ship": 1.0, "pilot": 1.5}
const USER_NAME := {"mech": "Mech", "ship": "Ship", "pilot": "Pilot"}
## v12.68: the weight class a weapon shows (Light / Medium / Heavy)
static func weight_class(w: float) -> String: return "Light" if w < 9.0 else ("Medium" if w < 16.0 else "Heavy")
const SETS := 2   # weapon sets you cycle with SWAP

# ---------------------------------------------------------------- weapons as data
## per class: what a weapon of it weighs, draws, heats, carries (ammo -1 = energy: never runs out) and its HUD icon
const CLASS_DEF := {
	"blaster": {"weight": 6.0, "energy": 14.0, "heat": 5.0, "ammo": -1, "icon": "bolt"},
	"rifle": {"weight": 8.0, "energy": 6.0, "heat": 4.0, "ammo": 360, "icon": "rifle"},
	"cannon": {"weight": 12.0, "energy": 10.0, "heat": 9.0, "ammo": 140, "icon": "cannon"},
	"rail": {"weight": 10.0, "energy": 24.0, "heat": 14.0, "ammo": 80, "icon": "rail"},
	"heavy": {"weight": 22.0, "energy": 30.0, "heat": 18.0, "ammo": 60, "icon": "heavy"},
	"missile": {"weight": 11.0, "energy": 4.0, "heat": 6.0, "ammo": 24, "icon": "missile"},
}
## which class each of the game's guns and pods is (anything not listed: blaster)
const WEAPON_CLASS := {
	"pulse1": "blaster", "pulse2": "blaster", "ion": "blaster", "nx_blue": "blaster", "nx_green": "blaster", "nx_yellow": "blaster", "nx_red": "blaster", "nx_purple": "blaster",
	"warden": "rifle", "bone_rifle": "rifle", "rail_carbine": "rifle",
	"plasma": "cannon", "twin_cannon": "cannon", "charge_cannon": "cannon", "arm_cannon": "cannon",
	"rail_rifle": "rail", "rail_lance": "rail",
	"hv_cannon": "heavy", "hv_rail": "heavy",
	"missile_pod": "missile", "rocket_rack": "missile", "hv_missile_box": "heavy", "hv_rocket_arm": "heavy", "hv_quad": "heavy",
}
## the full record of a weapon id: {id, name, short, class, mounts (mount kinds it fits), mesh, damage, rate, speed,
## range, color, ammo, heat, weight, energy, icon}
static func weapon(id: String) -> Dictionary:
	var src: Dictionary = Data.WEAPONS.get(id, Data.MOUNT_PODS.get(id, {}))
	if src.is_empty() and AssetRegistry.ITEMS.has(id) and str(AssetRegistry.ITEMS[id].get("kind", "")) == "weapon": return _tripo_weapon(id)
	if src.is_empty(): return {}
	var cls: String = WEAPON_CLASS.get(id, "blaster")
	var cd: Dictionary = CLASS_DEF[cls]
	var pod: bool = Data.MOUNT_PODS.has(id)
	var price_k: float = clampf(float(src.get("price", 0)) / 6000.0, 0.0, 1.5)   # (dearer guns weigh and draw a little more)
	var out := {"id": id, "name": str(src.get("name", id)), "short": str(src.get("short", src.get("name", id))), "class": cls,
		"mesh": str(src.get("model", "")), "damage": float(src.get("damage", 30.0 if pod else 10.0)), "rate": float(src.get("rate", 1.2 if pod else 3.0)),
		"speed": float(src.get("speed", 260.0 if pod else 420.0)), "range": float(src.get("range", 700.0)), "color": src.get("color", Color(1.0, 0.6, 0.3)),
		"ammo": int(cd["ammo"]) if not pod else int(src.get("ammo", 6)) * 4, "heat": float(cd["heat"]),
		"weight": float(cd["weight"]) * (1.0 + price_k * 0.3), "energy": float(cd["energy"]) * (1.0 + price_k * 0.25), "icon": str(cd["icon"]), "pod": pod}
	out["mounts"] = fits_where(out)
	out["wclass"] = weight_class(float(out["weight"]))
	out["users"] = users_of(out)
	return out

## v12.68: who can use a weapon: Mech / Ship by its mounts; a Pilot too when it is light enough to carry by hand
static func users_of(w: Dictionary) -> Array:
	var u: Array = []
	for fr in ["mech", "ship", "pilot"]:
		for m in (w.get("mounts", []) as Array):
			if str(m).begins_with(fr + ":") and not (fr in u):
				if fr == "pilot" and float(w.get("weight", 0.0)) > float(MOUNTS["pilot"]["R_Hand"]["max_w"]): continue   # (too heavy to carry by hand)
				u.append(fr)
	return u

## v12.68: a weapon that came from the Tripo import (its stats written by tools/tripo_import.py)
static func _tripo_weapon(id: String) -> Dictionary:
	var it: Dictionary = AssetRegistry.ITEMS[id]
	var d: Dictionary = it.get("data", {})
	var cls: String = str(d.get("game_class", "rifle"))
	var cd: Dictionary = CLASS_DEF.get(cls, CLASS_DEF["rifle"])
	var out := {"id": id, "name": str(d.get("name", id)), "short": str(d.get("short", d.get("name", id))), "class": cls, "mesh": id,
		"damage": float(d.get("damage", 10.0)), "rate": float(d.get("rate", 3.0)), "speed": float(d.get("speed", 420.0)), "range": float(d.get("range", 700.0)),
		"color": Color(str(d.get("color", "#ffa040"))), "ammo": int(d.get("ammo", cd["ammo"])), "heat": float(d.get("heat", cd["heat"])),
		"weight": float(d.get("weight", cd["weight"])), "energy": float(d.get("energy", cd["energy"])), "icon": str(d.get("icon", cd["icon"])), "pod": false, "tripo": true}
	out["mounts"] = fits_where(out)
	var allowed: Array = d.get("users", [])   # (the data file can narrow who uses it)
	if not allowed.is_empty(): out["mounts"] = (out["mounts"] as Array).filter(func(m): return USER_NAME.get(str(m).get_slice(":", 0), "") in allowed)
	out["wclass"] = str(d.get("class", weight_class(float(out["weight"]))))
	out["users"] = users_of(out)
	if "Pilot" in allowed and not ("pilot" in (out["users"] as Array)):   # (the owner: these go in the pilot's hands too, whatever their size)
		(out["users"] as Array).append("pilot")
		(out["mounts"] as Array).append("pilot:R_Hand")
	out["hand_any"] = "Pilot" in allowed
	return out

## v12.68: every weapon id there is (the game's guns and pods, then the Tripo imports)
static func all_weapons() -> Array:
	var out: Array = []
	for k in Data.WEAPONS: out.append(k)
	for k in Data.MOUNT_PODS: if not (k in out): out.append(k)
	for k in AssetRegistry.ITEMS: if str(AssetRegistry.ITEMS[k].get("kind", "")) == "weapon": out.append(k)
	return out

## every mount (both frames) a weapon may go on, by its class
static func fits_where(w: Dictionary) -> Array:
	var out: Array = []
	for fr in MOUNTS:
		for m in MOUNTS[fr]:
			if str(w.get("class", "")) in (MOUNTS[fr][m]["classes"] as Array): out.append("%s:%s" % [fr, m])
	return out

# ---------------------------------------------------------------- armor parts
## frame -> part slot -> part id -> {name, armor, weight, energy (it draws), cap (legs / engines: weight carried),
## gen (core / hull: energy made), speed, boost, stagger (resistance), look (how its mesh looks)}
## The mech's core / arms / legs parts come from the mech frames you can buy (their meshes are those frames' parts);
## the head and the ship's parts are kit pieces fitted on the model.
const PARTS := {
	"mech": {
		"head": {
			"hd_std": {"name": "Standard Head", "armor": 6.0, "weight": 4.0, "energy": 4.0, "look": "visor"},
			"hd_sensor": {"name": "Sensor Head", "armor": 3.0, "weight": 3.0, "energy": 9.0, "look": "dish", "lock": 1.2},
			"hd_heavy": {"name": "Heavy Head", "armor": 12.0, "weight": 8.0, "energy": 4.0, "look": "helm", "stagger": 0.1},
		},
		"core": {},   # (filled from Data.MECHS: core_<frame>)
		"arms": {},
		"legs": {},
	},
	"ship": {
		"hull": {
			"hl_light": {"name": "Light Hull Plating", "armor": 10.0, "weight": 10.0, "energy": 4.0, "gen": 120.0, "look": "thin"},
			"hl_std": {"name": "Standard Hull", "armor": 20.0, "weight": 18.0, "energy": 6.0, "gen": 140.0, "look": "plate"},
			"hl_heavy": {"name": "Heavy Hull Armor", "armor": 36.0, "weight": 30.0, "energy": 8.0, "gen": 130.0, "look": "slab", "stagger": 0.2},
			"hl_reactor": {"name": "Reactor Hull", "armor": 14.0, "weight": 22.0, "energy": 4.0, "gen": 190.0, "look": "vents"},
		},
		"wings": {
			"wg_light": {"name": "Light Wings", "armor": 6.0, "weight": 6.0, "energy": 2.0, "speed": 0.05, "look": "fin"},
			"wg_std": {"name": "Standard Wings", "armor": 12.0, "weight": 10.0, "energy": 3.0, "look": "plate"},
			"wg_armored": {"name": "Armored Wings", "armor": 22.0, "weight": 18.0, "energy": 4.0, "look": "slab", "stagger": 0.1},
		},
		"engines": {
			"en_std": {"name": "Standard Engines", "armor": 6.0, "weight": 12.0, "energy": 20.0, "cap": 110.0, "speed": 1.0, "boost": 1.0, "look": "twin"},
			"en_boost": {"name": "Boost Engines", "armor": 4.0, "weight": 10.0, "energy": 34.0, "cap": 90.0, "speed": 1.1, "boost": 1.35, "look": "long"},
			"en_lift": {"name": "Heavy-Lift Engines", "armor": 10.0, "weight": 18.0, "energy": 26.0, "cap": 160.0, "speed": 0.92, "boost": 0.9, "look": "quad"},
		},
	},
	"pilot": {   # v12.68; v12.74 (owner's PILOT GEAR STORE + his armor sheets): suits, booster packs, tactical gear
		# fit: who it is cut for (any / male = Hovick / female = Judy); tint: how the preview shows it until its model is in
		"suit": {
			"st_std": {"name": "Flight Suit", "armor": 6.0, "shield": 0.0, "weight": 4.0, "energy": 2.0, "gen": 40.0, "cap": 24.0, "heat": 5.0, "look": "suit", "price": 0},
			"st_armored": {"name": "Armored Flight Suit", "armor": 14.0, "shield": 4.0, "weight": 9.0, "energy": 3.0, "gen": 44.0, "cap": 30.0, "heat": 10.0, "look": "suit", "stagger": 0.1, "price": 6000, "tint": Color(0.35, 0.4, 0.45)},
			"st_strike": {"name": "Strike Harness", "armor": 10.0, "shield": 10.0, "weight": 5.0, "energy": 3.0, "gen": 46.0, "cap": 28.0, "heat": 8.0, "look": "harness", "fit": "female", "price": 9000, "tint": Color(0.92, 0.92, 0.95), "sheet": "white-haired harness"},
			"st_valk_steel": {"name": "Valkyrie Steel Armor", "armor": 26.0, "shield": 14.0, "weight": 12.0, "energy": 4.0, "gen": 50.0, "cap": 34.0, "heat": 20.0, "look": "armor", "fit": "female", "price": 18000, "tint": Color(0.45, 0.47, 0.5), "sheet": "grey female armor"},
			"st_valk_red": {"name": "Valkyrie Red Armor", "armor": 30.0, "shield": 16.0, "weight": 13.0, "energy": 4.0, "gen": 52.0, "cap": 34.0, "heat": 24.0, "look": "armor", "fit": "female", "price": 20000, "tint": Color(0.75, 0.12, 0.12), "sheet": "black / red female armor"},
			"st_valk_white": {"name": "Valkyrie White Armor", "armor": 32.0, "shield": 20.0, "weight": 14.0, "energy": 5.0, "gen": 54.0, "cap": 36.0, "heat": 28.0, "look": "armor", "fit": "female", "price": 22000, "tint": Color(0.95, 0.93, 0.92), "sheet": "white / red female armor"},
			"st_vanguard": {"name": "Vanguard White Armor", "armor": 36.0, "shield": 18.0, "weight": 18.0, "energy": 5.0, "gen": 54.0, "cap": 38.0, "heat": 28.0, "look": "armor", "fit": "male", "price": 22000, "tint": Color(0.95, 0.92, 0.9), "sheet": "white / red male armor"},
			"st_ares": {"name": "VX-07 Ares Assault Armor", "armor": 42.0, "shield": 20.0, "weight": 22.0, "energy": 6.0, "gen": 56.0, "cap": 40.0, "heat": 32.0, "look": "armor", "fit": "male", "price": 24000, "tint": Color(0.25, 0.26, 0.28), "sheet": "VX-07 Ares"},
		},
		"booster": {
			"bp_std": {"name": "Standard Booster", "armor": 2.0, "weight": 3.0, "energy": 4.0, "speed": 0.0, "boost": 1.0, "price": 0},
			"bp_sprint": {"name": "Sprint Booster", "armor": 1.0, "weight": 3.0, "energy": 7.0, "speed": 0.08, "boost": 1.25, "price": 8000},
			"bp_jump": {"name": "Jump Jet Pack", "armor": 3.0, "weight": 5.0, "energy": 9.0, "speed": 0.04, "boost": 1.45, "price": 14000},
		},
		"tactical": {
			"tg_belt": {"name": "Utility Belt", "armor": 1.0, "weight": 1.0, "energy": 0.0, "price": 0},
			"tg_medkit": {"name": "Field Medkit", "armor": 1.0, "shield": 0.0, "weight": 2.0, "energy": 0.0, "heal": 25.0, "price": 4000},
			"tg_shield": {"name": "Personal Shield Emitter", "armor": 0.0, "shield": 20.0, "weight": 3.0, "energy": 6.0, "price": 12000},
			"tg_grenades": {"name": "Grenade Bandolier", "armor": 2.0, "weight": 4.0, "energy": 0.0, "price": 7000},
		},
	},
}
const SLOTS := {"mech": ["head", "core", "arms", "legs"], "ship": ["hull", "wings", "engines"], "pilot": ["suit", "booster", "tactical"]}

## a part's record (mech core / arms / legs from the frames)
static func part(frame: String, slot: String, id: String) -> Dictionary:
	if frame == "mech" and slot in ["core", "arms", "legs"]:
		var fid := id.substr(slot.length() + 1)
		if not Data.MECHS.has(fid): return {}
		var f: Dictionary = Data.MECHS[fid]
		var ar := float(f.get("armor", 0.1))
		var sp := float(f.get("speed", 1.0))
		match slot:
			"core": return {"name": "%s Core" % f["short"], "armor": 40.0 + ar * 200.0, "weight": 30.0 + ar * 60.0, "energy": 10.0, "gen": 150.0 + (1.0 - sp) * 120.0 + ar * 60.0, "frame": fid}
			"arms": return {"name": "%s Arms" % f["short"], "armor": 14.0 + ar * 80.0, "weight": 12.0 + ar * 30.0, "energy": 6.0, "aim": float(f.get("arm", 1.0)), "frame": fid}
			"legs": return {"name": "%s Legs" % f["short"], "armor": 18.0 + ar * 90.0, "weight": 20.0 + ar * 40.0, "energy": 12.0, "cap": 120.0 + ar * 260.0, "speed": sp, "boost": clampf(sp * 1.05, 0.7, 1.3), "stagger": ar, "frame": fid}
	return PARTS.get(frame, {}).get(slot, {}).get(id, {})

## v12.74: who the pilot is (the body the suits are cut for)
const PILOT_BODIES := {"hovick": {"name": "Hovick", "sex": "male", "glb": "res://assets/pilot/hl_hova.glb"}, "judy": {"name": "Judy", "sex": "female", "glb": "res://assets/pilot/hl_judy.glb"},
	"evee": {"name": "Evee", "sex": "female", "glb": "res://assets/pilot/hl_evee.glb"}}   # (owner: "next Evee and Judy"; Evee's 3D model still to be made)
static func pilot_sex() -> String: return str(PILOT_BODIES.get(GS.pilot_body, PILOT_BODIES["hovick"])["sex"])

## the part ids you can fit in a slot (the mech's frame parts: the frames you own)
static func parts_for(frame: String, slot: String) -> Array:
	if frame == "mech" and slot in ["core", "arms", "legs"]:
		var out: Array = []
		for fid in Data.MECH_ORDER: if fid in GS.owned_mechs or GS.god_mode: out.append("%s_%s" % [slot, fid])
		return out
	return (PARTS.get(frame, {}).get(slot, {}) as Dictionary).keys()

# ---------------------------------------------------------------- a loadout (plain data)
## {"frame", "sets": [{mount: weapon id}, ...], "active": set index, "parts": {slot: part id}}
static func default_loadout(frame: String) -> Dictionary:
	if frame == "mech":
		var mp: Dictionary = GS.mech_parts
		return {"frame": "mech", "active": 0, "parts": {"head": "hd_std", "core": "core_" + str(mp.get("core", "blackgold")), "arms": "arms_" + str(mp.get("arms", "blackgold")), "legs": "legs_" + str(mp.get("legs", "blackgold"))},
			"sets": [{"L_Arm": GS.weapon_id, "R_Arm": GS.weapon_id}, {}]}
	if frame == "pilot": return {"frame": "pilot", "active": 0, "parts": {"suit": "st_std", "booster": "bp_std", "tactical": "tg_belt"}, "sets": [{"R_Hand": "pulse1"}, {}]}
	return {"frame": "ship", "active": 0, "parts": {"hull": "hl_std", "wings": "wg_std", "engines": "en_std"},
		"sets": [{"Nose": GS.weapon_id, "Wing_L": GS.weapon_id, "Wing_R": GS.weapon_id}, {}]}

## the loadout this frame wears now (made the first time it's asked for)
static func current(frame: String) -> Dictionary:
	if not GS.loadouts.has(frame) or not (GS.loadouts[frame] is Dictionary) or (GS.loadouts[frame] as Dictionary).is_empty():
		GS.loadouts[frame] = default_loadout(frame)
	return GS.loadouts[frame]

static func active_set(lo: Dictionary) -> Dictionary:
	var sets: Array = lo.get("sets", [])
	var i := int(lo.get("active", 0))
	return sets[i] if i < sets.size() else {}

# ---------------------------------------------------------------- the rules
## can weapon `wid` go on `mount` of this loadout's set `set_i`? "" = yes, else why not
static func fit_error(lo: Dictionary, set_i: int, mount: String, wid: String) -> String:
	var fr := str(lo["frame"])
	var md: Dictionary = MOUNTS[fr].get(mount, {})
	if md.is_empty(): return "No such mount."
	if md.get("stow", false): return "The back only holds the weapons you swap out."
	var w := weapon(wid)
	if w.is_empty(): return "Unknown weapon."
	if not (fr in (w.get("users", []) as Array)): return "%s isn't made for a %s." % [w["short"], USER_NAME.get(fr, fr)]
	var by_hand: bool = fr == "pilot" and mount == "R_Hand" and bool(w.get("hand_any", false))   # (a Tripo gun made for the pilot's hands too)
	if not by_hand and not (str(w["class"]) in (md["classes"] as Array)): return "%s (%s) doesn't fit the %s: it takes %s." % [w["short"], w["class"], md["label"], ", ".join(md["classes"])]
	if by_hand: pass
	elif float(w["weight"]) > float(md["max_w"]): return "%s weighs %.0f: the %s takes %.0f at most." % [w["short"], w["weight"], md["label"], md["max_w"]]
	if not by_hand and float(w["energy"]) > float(md["e_cap"]): return "%s draws %.0f energy: the %s gives %.0f at most." % [w["short"], w["energy"], md["label"], md["e_cap"]]
	var test := lo.duplicate(true)
	(test["sets"][set_i] as Dictionary)[mount] = wid
	var t := totals(test)
	if float(t["energy"]) > float(t["gen"]): return "Over the generator: %.0f energy needed, %.0f made. Fit a bigger %s or lighter weapons." % [t["energy"], t["gen"], "core" if fr == "mech" else "hull"]
	return ""

## the loadout's totals: weight, capacity, energy, generator, armor, and what they do (speed, boost, stagger)
## (the heaviest of the sets counts: they're all carried, one on the mounts and the rest stowed)
static func totals(lo: Dictionary) -> Dictionary:
	var fr := str(lo["frame"])
	var wt := 0.0
	var en := 0.0
	var ar := 0.0
	var cap := 0.0
	var gen := 0.0
	var spd := 1.0
	var bst := 1.0
	var stg := 0.0
	for s in SLOTS[fr]:
		var p := part(fr, s, str((lo["parts"] as Dictionary).get(s, "")))
		wt += float(p.get("weight", 0.0))
		en += float(p.get("energy", 0.0))
		ar += float(p.get("armor", 0.0))
		cap += float(p.get("cap", 0.0))
		gen += float(p.get("gen", 0.0))
		if p.has("speed"): spd *= float(p["speed"]) if s in ["legs", "engines"] else (1.0 + float(p["speed"]))
		if p.has("boost"): bst *= float(p["boost"])
		stg += float(p.get("stagger", 0.0))
	var set_w := 0.0
	var set_e := 0.0
	for st: Dictionary in lo["sets"]:
		var sw := 0.0
		var se := 0.0
		for m in st:
			var w := weapon(str(st[m]))
			sw += float(w.get("weight", 0.0))
			se += float(w.get("energy", 0.0))
		set_w += sw   # (every set is carried)
		set_e = maxf(set_e, se)   # (only the set on the mounts draws power)
	wt += set_w
	en += set_e
	var over := maxf(0.0, wt - cap)
	var slow := clampf(1.0 - over / maxf(1.0, cap) * Data.LOADOUT_OVERWEIGHT_K, Data.LOADOUT_MIN_SPEED, 1.0)
	return {"weight": wt, "cap": cap, "energy": en, "gen": gen, "armor": ar, "over_w": over, "speed": spd * slow, "boost": bst * slow,
		"stagger": clampf(stg + wt / 400.0, 0.0, 0.9), "blocked": en > gen, "slow": slow}

## the whole loadout fits? "" = yes, else why not (the generator is the one hard limit)
static func build_error(lo: Dictionary) -> String:
	var t := totals(lo)
	if bool(t["blocked"]): return "Build blocked: %.0f energy needed, the generator makes %.0f." % [t["energy"], t["gen"]]
	for i in (lo["sets"] as Array).size():
		for m in lo["sets"][i]:
			var e := fit_error_mount_only(str(lo["frame"]), m, str(lo["sets"][i][m]))
			if e != "": return e
	return ""

static func fit_error_mount_only(fr: String, mount: String, wid: String) -> String:
	var md: Dictionary = MOUNTS[fr].get(mount, {})
	var w := weapon(wid)
	if md.is_empty() or w.is_empty(): return "Bad fit."
	if fr == "pilot" and mount == "R_Hand" and bool(w.get("hand_any", false)): return ""
	if not (str(w["class"]) in (md["classes"] as Array)) or float(w["weight"]) > float(md["max_w"]) or float(w["energy"]) > float(md["e_cap"]): return "%s doesn't fit the %s." % [w["short"], md["label"]]
	return ""

## fit (or "" to clear) a mount of set `set_i`; returns "" on success, else why not (nothing changes then)
static func fit(lo: Dictionary, set_i: int, mount: String, wid: String) -> String:
	if wid == "":
		(lo["sets"][set_i] as Dictionary).erase(mount)
		return ""
	var err := fit_error(lo, set_i, mount, wid)
	if err != "": return err
	(lo["sets"][set_i] as Dictionary)[mount] = wid
	ensure_state(wid)
	return ""

## swap an armor part (blocked if it would put the build over the generator)
static func set_part(lo: Dictionary, slot: String, pid: String) -> String:
	var fit := str(part(str(lo["frame"]), slot, pid).get("fit", "any"))
	if str(lo["frame"]) == "pilot" and fit != "any" and fit != pilot_sex():
		return "The %s is cut for %s." % [part("pilot", slot, pid).get("name", pid), "Judy (and other women pilots)" if fit == "female" else "Hovick (and other men pilots)"]
	var test := lo.duplicate(true)
	test["parts"][slot] = pid
	if bool(totals(test)["blocked"]): return "That part would put the build over the generator."
	lo["parts"][slot] = pid
	if str(lo["frame"]) == "mech" and slot in ["core", "arms", "legs"]: GS.mech_parts[slot] = str(part("mech", slot, pid).get("frame", "blackgold"))
	return ""

# ---------------------------------------------------------------- per-weapon ammo and heat (kept across swaps)
static func ensure_state(wid: String) -> Dictionary:
	if not GS.weapon_state.has(wid):
		var w := weapon(wid)
		GS.weapon_state[wid] = {"ammo": int(w.get("ammo", -1)), "heat": 0.0, "locked": false}
	return GS.weapon_state[wid]

static func refill_all() -> void:
	for wid in GS.weapon_state:
		var w := weapon(wid)
		GS.weapon_state[wid]["ammo"] = int(w.get("ammo", -1))
		GS.weapon_state[wid]["heat"] = 0.0
		GS.weapon_state[wid]["locked"] = false

## can it fire now? (ammo left, not overheated)
static func can_fire(wid: String) -> bool:
	var st := ensure_state(wid)
	return not bool(st["locked"]) and int(st["ammo"]) != 0

## one shot: ammo down, heat up (overheat locks it until it cools)
static func shot(wid: String) -> void:
	var st := ensure_state(wid)
	var w := weapon(wid)
	if int(st["ammo"]) > 0: st["ammo"] = int(st["ammo"]) - 1
	st["heat"] = minf(100.0, float(st["heat"]) + float(w.get("heat", 5.0)))
	if float(st["heat"]) >= 100.0: st["locked"] = true

static func cool(dt: float) -> void:
	for wid in GS.weapon_state:
		var st: Dictionary = GS.weapon_state[wid]
		st["heat"] = maxf(0.0, float(st["heat"]) - Data.LOADOUT_COOL * dt)
		if bool(st.get("locked", false)) and float(st["heat"]) <= Data.LOADOUT_UNLOCK_HEAT: st["locked"] = false

# ---------------------------------------------------------------- save / load as data
static func to_text(lo: Dictionary) -> String: return JSON.stringify(lo)
static func from_text(s: String) -> Dictionary:
	var v = JSON.parse_string(s)
	if not (v is Dictionary) or not (v as Dictionary).has("frame") or not MOUNTS.has(str(v["frame"])): return {}
	var lo: Dictionary = v
	lo["active"] = int(lo.get("active", 0))
	while (lo["sets"] as Array).size() < SETS: (lo["sets"] as Array).append({})
	return lo

static func save_preset(i: int, frame: String) -> void:
	while GS.loadout_presets.size() <= i: GS.loadout_presets.append("")
	GS.loadout_presets[i] = to_text(current(frame))

static func load_preset(i: int) -> String:
	if i >= GS.loadout_presets.size() or str(GS.loadout_presets[i]) == "": return "That preset is empty."
	var lo := from_text(str(GS.loadout_presets[i]))
	if lo.is_empty(): return "That preset is damaged."
	var e := build_error(lo)
	if e != "": return e
	GS.loadouts[str(lo["frame"])] = lo
	return ""

# ---------------------------------------------------------------- the enemies' loadouts (same rules)
## a faction's pilot of tier 1-5 on this frame: its weapons and parts picked by tier; what it does to the unit:
## {"lo", "dmg_k", "hp_k", "speed_k"}
static func for_enemy(frame: String, tier: int, seed_s: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_s)
	var pool := ["pulse1", "pulse2", "ion", "warden", "rail_carbine", "plasma", "twin_cannon", "rail_rifle", "charge_cannon", "rail_lance", "hv_cannon"]
	var top := clampi(2 + tier * 2, 2, pool.size())
	var lo := default_loadout(frame)
	lo["sets"] = [{}, {}]
	for m in MOUNTS[frame]:
		if MOUNTS[frame][m].get("stow", false): continue
		for k in 6:
			var wid: String = pool[rng.randi() % top]
			if fit(lo, 0, m, wid) == "": break
		if (lo["sets"][0] as Dictionary).size() >= 2 + tier / 2: break
	if frame == "ship":
		lo["parts"]["hull"] = ["hl_light", "hl_std", "hl_heavy", "hl_reactor"][clampi(tier - 1, 0, 3)]
	var t := totals(lo)
	var dps := 0.0
	for m in lo["sets"][0]:
		var w := weapon(str(lo["sets"][0][m]))
		dps += float(w["damage"]) * float(w["rate"])
	return {"lo": lo, "dmg_k": clampf(dps / 60.0, 0.7, 2.2), "hp_k": clampf(1.0 + float(t["armor"]) / 200.0, 1.0, 1.6), "speed_k": clampf(float(t["speed"]), 0.7, 1.1)}

# ---------------------------------------------------------------- the mounts on a model
## the model's box in its own space (what its children are placed in; the model node may be scaled)
static func local_box(model: Node3D) -> AABB:
	var keep := model.get_node_or_null("LoadoutRig")
	var keep2 := model.get_node_or_null("LoadoutArmor")
	for k in [keep, keep2]: if k != null: model.remove_child(k)
	var bb: AABB = ShipFactory._aabb(model, model.transform.affine_inverse())
	for k in [keep, keep2]: if k != null: model.add_child(k)
	return bb
## the mount holders on a model (made once): {mount: Node3D}, placed by the model's box
static func rig(model: Node3D, frame: String) -> Dictionary:
	var holder := model.get_node_or_null("LoadoutRig") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "LoadoutRig"
		model.add_child(holder)
		var bb: AABB = local_box(model)
		if bb.size == Vector3.ZERO: bb = AABB(Vector3(-3, -1, -4), Vector3(6, 2, 8))
		var c := bb.get_center()
		for m in MOUNTS[frame]:
			var a: Vector3 = MOUNTS[frame][m]["at"]
			var mn := Node3D.new()
			mn.name = m
			var y := bb.position.y + bb.size.y * a.y if frame != "ship" else c.y + bb.size.y * a.y
			mn.position = Vector3(c.x + bb.size.x * 0.5 * a.x, y, c.z + bb.size.z * a.z)
			holder.add_child(mn)
		holder.set_meta("size", maxf(bb.size.x, bb.size.z))
		var rf := model.find_child("Rifle", true, false) as Node3D
		if frame == "pilot" and rf != null:   # v12.68: the pilot's own rifle gives way: the hand mount sits where he holds it
			(holder.get_node("R_Hand") as Node3D).position = (rf.get_parent() as Node3D).transform * rf.position if rf.get_parent() != model else rf.position
			rf.visible = false
			holder.set_meta("size", bb.size.y * 0.9)
		if frame == "pilot" and model.has_meta("pilot_rig"):   # v12.70 (owner): in his palm, his arms up in the aiming pose
			var hp: Vector3 = (model.get_meta("pilot_rig") as PilotRig).hand_point()
			if hp != Vector3.INF: (holder.get_node("R_Hand") as Node3D).position = hp
	var out := {}
	for c2 in holder.get_children(): out[str(c2.name)] = c2
	return out

## a weapon's mesh, sized for the frame (the game's own model; a kit-built gun when it has none)
static func weapon_mesh(wid: String, frame_size: float, user := "mech") -> Node3D:
	var w := weapon(wid)
	var n: Node3D
	var key := str(w.get("mesh", ""))
	var want_len: float = frame_size * (0.42 if str(w.get("class", "")) == "heavy" else 0.32) * float(USER_SCALE.get(user, 1.0))
	var sock := Vector3(0.0, -0.12, -0.22)   # the grip, as a share of the gun's length (kit guns: under the body, near the back)
	if key != "" and ShipFactory.has_real_model(key):
		n = ShipFactory.build(key)
		var bb: AABB = ShipFactory._aabb(n, Transform3D.IDENTITY)
		var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		if longest > 0.001: n.scale = Vector3.ONE * (want_len / longest)
		var it: Dictionary = AssetRegistry.ITEMS.get(key, {})
		if it.has("socket"):   # the Tripo item's own grip (found by the import script), in its unit length
			var sk: Array = it["socket"]
			sock = Vector3(float(sk[0]), float(sk[1]), float(sk[2]))
		else: sock = Vector3(bb.get_center().x, bb.position.y, bb.get_center().z + bb.size.z * 0.15) / maxf(longest, 0.001)
	else:
		n = kit_gun(str(w.get("class", "blaster")), w.get("color", Color(0.6, 0.8, 1.0)), want_len)
	var ms := Node3D.new()   # v12.68 (owner's spec): the MountSocket: where the gun clicks onto a mount
	ms.name = "MountSocket"
	ms.position = sock * (want_len if n.scale.x == 1.0 else want_len / n.scale.x)
	n.add_child(ms)
	n.name = "W_" + wid
	n.set_meta("weapon", wid)
	n.set_meta("user", user)
	return n

## v12.68: hang a weapon on a mount node so its MountSocket sits right on the mount; upside down under a ship's
## wings and belly (the grip up, clicked into the hardpoint)
static func seat(g: Node3D, frame: String, mount: String) -> void:
	g.rotation = Vector3(0.0, 0.0, PI) if (frame == "ship" and mount in HANG_MOUNTS) else Vector3.ZERO
	if frame == "pilot" and mount == "Sidearm":   # v12.74: holstered on the hip, muzzle down, small
		g.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		g.scale *= 0.55
	var ms := g.get_node_or_null("MountSocket") as Node3D
	if ms == null: return
	g.position = -(g.basis * ms.position)
	g.set_meta("hang", frame == "ship" and mount in HANG_MOUNTS)

## a gun made from a drawn profile (a body with a stepped barrel, swept round: never a plain box)
static func kit_gun(cls: String, col: Color, length: float) -> Node3D:
	var root := Node3D.new()
	var prof: Array = [[0.0, 0.0], [0.16, 0.0], [0.2, 0.06], [0.2, 0.34], [0.13, 0.4], [0.11, 0.62], [0.08, 0.66], [0.08, 1.0], [0.0, 1.0]]
	if cls in ["cannon", "heavy"]: prof = [[0.0, 0.0], [0.24, 0.0], [0.28, 0.1], [0.28, 0.45], [0.2, 0.5], [0.17, 0.92], [0.21, 0.96], [0.21, 1.0], [0.0, 1.0]]
	elif cls == "missile": prof = [[0.0, 0.0], [0.3, 0.0], [0.33, 0.05], [0.33, 0.9], [0.27, 1.0], [0.0, 1.0]]
	elif cls == "rail": prof = [[0.0, 0.0], [0.14, 0.0], [0.18, 0.08], [0.18, 0.3], [0.07, 0.36], [0.07, 1.0], [0.0, 1.0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 12
	for i in prof.size() - 1:
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p0: Array = prof[i]
			var p1: Array = prof[i + 1]
			var v := [Vector3(cos(a0) * p0[0], sin(a0) * p0[0], -p0[1]), Vector3(cos(a1) * p0[0], sin(a1) * p0[0], -p0[1]),
				Vector3(cos(a1) * p1[0], sin(a1) * p1[0], -p1[1]), Vector3(cos(a0) * p1[0], sin(a0) * p1[0], -p1[1])]
			for q in [0, 1, 2, 0, 2, 3]: st.add_vertex((v[q] as Vector3) * length)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = ShipFactory.mat(Color(0.32, 0.34, 0.38), false, 0.7)
	root.add_child(mi)
	var tip := MeshInstance3D.new()   # the muzzle glow in the weapon's colour
	var sm := SphereMesh.new()
	sm.radius = length * 0.06
	sm.height = length * 0.12
	tip.mesh = sm
	tip.position = Vector3(0, 0, -length)
	tip.material_override = ShipFactory.mat(col, true)
	root.add_child(tip)
	if cls == "missile":   # the launcher's tubes, seen from the front
		for k in 4:
			var tube := MeshInstance3D.new()
			var cm := SphereMesh.new()
			cm.radius = length * 0.07
			cm.height = length * 0.14
			tube.mesh = cm
			tube.position = Vector3((k % 2 - 0.5) * length * 0.3, (k / 2 - 0.5) * length * 0.3, -length * 1.0)
			tube.material_override = ShipFactory.mat(Color(0.1, 0.1, 0.12), false)
			root.add_child(tube)
	return root

## put the loadout's weapons on the model: the active set on its mounts; on a mech the other sets' arm guns on its
## back, on a ship the rest retracted (hidden in the hull). Returns {mount: weapon node} of the active set.
static func dress(model: Node3D, lo: Dictionary) -> Dictionary:
	var fr := str(lo["frame"])
	var mounts := rig(model, fr)
	var holder: Node3D = model.get_node("LoadoutRig")
	var size: float = float(holder.get_meta("size", 6.0))
	for mn: Node3D in mounts.values():
		for c in mn.get_children(): c.free()
	var out := {}
	var act := active_set(lo)
	for m in act:
		if not mounts.has(m): continue
		var g := weapon_mesh(str(act[m]), size, fr)
		(mounts[m] as Node3D).add_child(g)
		seat(g, fr, m)
		out[m] = g
	var k := 0
	for i in (lo["sets"] as Array).size():
		if i == int(lo["active"]): continue
		for m in lo["sets"][i]:
			var g2 := weapon_mesh(str(lo["sets"][i][m]), size, fr)
			g2.set_meta("stowed", true)
			if fr in ["mech", "pilot"]:   # slung across the back, side by side
				(mounts["Back_Stow"] as Node3D).add_child(g2)
				g2.position = Vector3((k - 0.5) * size * 0.16, 0.0, 0.0)
				g2.rotation_degrees = Vector3(-70.0, 0.0, 0.0)
			else:   # retracted: inside the hull at its mount
				if mounts.has(m): (mounts[m] as Node3D).add_child(g2)
				g2.scale = Vector3.ONE * 0.001
				g2.visible = false
			k += 1
	_dress_parts(model, lo, size)
	return out

## the armor parts you can see: the mech's head; the ship's hull plating, wing plates and engine pods
static func _dress_parts(model: Node3D, lo: Dictionary, size: float) -> void:
	var old := model.get_node_or_null("LoadoutArmor")
	if old != null: old.free()
	var fr := str(lo["frame"])
	var root := Node3D.new()
	root.name = "LoadoutArmor"
	if fr == "pilot":   # v12.72: the pilot wears his suit (the ship's hull and wing plates were landing on him)
		model.add_child(root)
		return
	model.add_child(root)
	var bb: AABB = local_box(model)
	if bb.size == Vector3.ZERO: return
	var c := bb.get_center()
	var steel := ShipFactory.mat(Color(0.42, 0.45, 0.5), false, 0.75)
	var trim := ShipFactory.mat(Color(1.0, 0.75, 0.3), true)
	var parts: Dictionary = lo["parts"]
	if fr == "mech":
		var look := str(part("mech", "head", str(parts.get("head", ""))).get("look", "visor"))
		var head := _plate([[-0.5, 0.0], [0.5, 0.0], [0.42, 0.6], [0.0, 0.8 if look == "helm" else 0.7], [-0.42, 0.6]], size * (0.16 if look == "helm" else 0.12), size * 0.12, steel)
		head.position = Vector3(c.x, bb.end.y - size * 0.02, c.z - size * 0.02)
		head.name = "Head_" + look
		root.add_child(head)
		var eye := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(size * 0.09, size * 0.015, size * 0.01)
		eye.mesh = em
		eye.material_override = trim
		eye.position = head.position + Vector3(0, size * 0.04, -size * 0.07)
		root.add_child(eye)
		if look == "dish":
			var dish := _plate([[-0.3, 0.0], [0.3, 0.0], [0.5, 0.4], [-0.5, 0.4]], size * 0.08, size * 0.01, steel)
			dish.position = head.position + Vector3(size * 0.08, size * 0.1, 0)
			root.add_child(dish)
		return
	var hl := str(part("ship", "hull", str(parts.get("hull", ""))).get("look", "plate"))
	var wl := str(part("ship", "wings", str(parts.get("wings", ""))).get("look", "plate"))
	var el := str(part("ship", "engines", str(parts.get("engines", ""))).get("look", "twin"))
	# the hull plating: a tapered plate along the spine (thicker for the heavy hull)
	var top := _plate([[-0.5, -0.5], [0.5, -0.5], [0.3, 0.5], [-0.3, 0.5]], bb.size.x * (0.22 if hl == "slab" else 0.16), bb.size.z * 0.34, steel, 0.05 if hl == "thin" else (0.12 if hl == "slab" else 0.08))
	top.position = Vector3(c.x, bb.end.y - bb.size.y * 0.18, c.z + bb.size.z * 0.05)
	top.name = "Hull_" + hl
	root.add_child(top)
	if hl == "vents":   # the reactor hull's glowing vents
		for k in 3:
			var v := _plate([[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]], bb.size.x * 0.03, bb.size.z * 0.025, trim, 0.2)
			v.position = top.position + Vector3((k - 1) * bb.size.x * 0.05, bb.size.y * 0.04, bb.size.z * 0.06)
			root.add_child(v)
	# the wing plates: a swept plate on each wing
	for sd in [-1.0, 1.0]:
		var wp := _plate([[0.0, -0.4], [1.0, -0.1], [1.0, 0.25], [0.0, 0.5]], bb.size.x * (0.2 if wl == "slab" else (0.1 if wl == "fin" else 0.15)), bb.size.z * 0.14, steel, 0.06)
		wp.scale.x = sd
		wp.position = Vector3(c.x + sd * bb.size.x * 0.16, c.y + bb.size.y * 0.06, c.z + bb.size.z * 0.12)
		wp.name = "Wing_" + wl
		root.add_child(wp)
		# the engines: boost = a long pod, heavy-lift = two short pods, standard = the ship's own
		if el == "twin": continue
		for k in (2 if el == "quad" else 1):
			var pod := kit_gun("cannon", Color(0.4, 0.75, 1.0), bb.size.z * (0.22 if el == "long" else 0.14))
			pod.rotation_degrees.y = 180.0   # (the glow faces back: the exhaust)
			pod.position = Vector3(c.x + sd * bb.size.x * (0.14 + 0.06 * k), c.y - bb.size.y * 0.12, bb.end.z - bb.size.z * 0.12)
			pod.name = "Engine_" + el
			root.add_child(pod)

## an extruded plate from a drawn outline (x, z in -1..1 of `w` / `d`), `h` thick
static func _plate(outline: Array, w: float, d: float, m: Material, h := 0.1) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	for q in outline: pts.append(Vector2(float(q[0]) * w, float(q[1]) * d))
	var th := maxf(0.02, h * maxf(w, d))
	var n := pts.size()
	for i in range(1, n - 1):   # top and bottom (a fan: the outlines are convex)
		for y in [th, 0.0]:
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[i]
			var cc: Vector2 = pts[i + 1]
			var tri := [Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(cc.x, y, cc.y)]
			if y == 0.0: tri.reverse()
			for v in tri: st.add_vertex(v)
	for i in n:   # the sides
		var a2: Vector2 = pts[i]
		var b2: Vector2 = pts[(i + 1) % n]
		for v in [Vector3(a2.x, 0, a2.y), Vector3(b2.x, 0, b2.y), Vector3(b2.x, th, b2.y), Vector3(a2.x, 0, a2.y), Vector3(b2.x, th, b2.y), Vector3(a2.x, th, a2.y)]: st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	return mi
