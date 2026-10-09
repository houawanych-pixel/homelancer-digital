extends Node
## Session state (autoload "GS"). Credits, ship, equipment and discovery persist for the whole play session.

signal changed

var credits := 500
var ship_id := "cadet"
var owned_ships := ["cadet"]
var weapon_id := "pulse1"
var owned_weapons := ["pulse1"]
var hull := 100.0
var wing_l := 40.0 # left and right wing sections (own health; a destroyed wing takes its guns with it)
var wing_r := 40.0
var shield := 60.0
var repairs := Data.MAX_REPAIRS
var missiles := 12
var heavy_missiles := 2
var mines := 3
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
var last_base := "liberty_hub"
var kills := 0
var met: Array = [] # character ids, most recent first
var mood := {} # id -> friendly | neutral | enraged
var memory := {} # id -> what that character remembers about you (see scripts/brain.gd)
var heat_shield := false # EARLY idea: a ship upgrade that survives the sun (nothing sells it yet)
var bounty := {}             # v1.4q: the bounty you carry: {id, sys, state: "hunt" | "captured"}; empty = none
var bounties_done: Array = []   # roster ids already paid
var mission := {}            # v1.5f: the job you carry from a MISSIONS board (see scripts/missions.gd); empty = none
var cargo: Array = []        # v1.5f: the hold: [{kind: "pilot", id, name, note}]
var missions_done := 0       # v1.5f: jobs paid (the boards change with it)
var special_used := {"half": false, "crit": false}   # v1.5o: the special earned at half / critical hull has been spent
var rep := {}                # v1.4r: reputation, one number per rival pair (Factions.axis_key -> -200..200); empty = everyone at their base
var cast := {}               # v1.4r: named characters' state: character_id -> {alive, current_system, custody}
var block_deltas := {}       # v1.5t EXPERIMENT: crater notes per block patch ("planet|tile" -> [[x, y, z, kind]]); the ground regrows from the seed and these are re-applied
var god_mode := false # only used by the automated route test

func ship() -> Dictionary: return Data.SHIPS[ship_id]
func weapon() -> Dictionary: return Data.WEAPONS[weapon_id]
func max_hull() -> float: return float(ship()["hull"])
func wing_max() -> float: return max_hull() * Data.SECTION_SHARE
func max_shield() -> float: return float(ship()["shield"])
func max_missiles() -> int: return int(ship()["missiles"])
func max_mines() -> int: return int(ship()["mines"])
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
	changed.emit()
	return "Hull, wings and repair kits restored."

func needs_repair() -> bool:
	return hull < max_hull() or wing_l < wing_max() or wing_r < wing_max() or repairs < Data.MAX_REPAIRS

## What a full RESTOCK would cost right now (light + heavy missiles + mines).
func restock_cost() -> int:
	return maxi(0, max_missiles() - missiles) * Data.MISSILE_PRICE + maxi(0, max_heavy() - heavy_missiles) * Data.HEAVY_MISSILE_PRICE + maxi(0, max_mines() - mines) * Data.MINE_PRICE

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
		changed.emit()
		return "Restocked everything for %d credits." % cost
	buy_missiles(9999)
	buy_heavy(9999)
	buy_mines(9999)
	if credits == before: return "Not enough credits to restock."
	return "Loaded what %d credits would buy. Racks are not full." % (before - credits)

func restore_full() -> void:
	special_used = {"half": false, "crit": false}
	hull = max_hull()
	wing_l = wing_max()
	wing_r = wing_max()
	shield = max_shield()
	repairs = Data.MAX_REPAIRS
	missiles = max_missiles()
	mines = max_mines()
	heavy_missiles = max_heavy()
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
	if bounty.get("id", "") != id or bounty.get("state", "") != "hunt": return false
	bounty["state"] = "captured"
	changed.emit()
	return true

## Called on docking: pays a captured bounty. "" = nothing to pay.
func claim_bounty() -> String:
	if bounty.get("state", "") != "captured": return ""
	var id: String = bounty["id"]
	var p: Dictionary = Data.roster_pilot(id)
	var pay: int = Data.bounty_reward(id)
	bounties_done.append(id)
	bounty = {}
	cast_state(p.get("character_id", id))["custody"] = true   # handed over: out of the patrols
	Factions.adjust(str(p.get("faction", "")), -Data.REP_BOUNTY)
	add_credits(pay)
	return "Bounty paid: %s handed over. +%d cr." % [p.get("name", "the pilot"), pay]

## v1.4r: a named character's persistent record (made on first use: alive, at large, nowhere in particular).
func cast_state(character_id: String) -> Dictionary:
	if not cast.has(character_id): cast[character_id] = {"alive": true, "current_system": "", "custody": false}
	return cast[character_id]

func add_credits(n: int) -> void:
	credits += n
	changed.emit()

func buy_weapon(id: String) -> String:
	var w: Dictionary = Data.WEAPONS[id]
	if id == weapon_id: return "Already equipped."
	if id in owned_weapons:
		weapon_id = id
		changed.emit()
		return "Equipped %s." % w["name"]
	if credits < int(w["price"]): return "Not enough credits (%d needed)." % int(w["price"])
	credits -= int(w["price"])
	owned_weapons.append(id)
	weapon_id = id
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
	if item == "heavy_missile": return Data.HEAVY_LOCKS
	return int(Data.MISSILE_RACKS.get(rack, Data.MISSILE_RACKS["triple"])["locks"])

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

func buy_ship(id: String) -> String:
	var s: Dictionary = Data.SHIPS[id]
	if id == ship_id: return "You are flying the %s." % s["name"]
	if not (id in owned_ships):
		if credits < int(s["price"]): return "Not enough credits (%d needed)." % int(s["price"])
		credits -= int(s["price"])
		owned_ships.append(id)
	ship_id = id
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
