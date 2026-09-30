extends Node
## Session state (autoload "GS"). Credits, ship, equipment and discovery persist for the whole play session.

signal changed

var credits := 500
var ship_id := "cadet"
var owned_ships := ["cadet"]
var weapon_id := "pulse1"
var owned_weapons := ["pulse1"]
var hull := 100.0
var shield := 60.0
var repairs := Data.MAX_REPAIRS
var missiles := 6
var heavy_missiles := 2
var mines := 3
var slots: Array = Data.DEFAULT_SLOTS.duplicate()
var shield_charges := Data.MAX_SHIELD_CHARGES
var energy_cells := Data.MAX_ENERGY_CELLS
var energy := Data.ENERGY_MAX
# lasers fire themselves and energy cells top up on their own; shield, repair, missiles and mines are your buttons
var modes := {"shield": "manual", "hull": "manual", "energy": "auto", "guns": "auto", "missile": "manual", "mine": "manual"}
var view := "chase" # "chase" or "cockpit"
var system_id := "solara"
var discovered := ["solara"]
var last_base := "liberty_hub"
var kills := 0
var met: Array = [] # character ids, most recent first
var mood := {} # id -> friendly | neutral | enraged
var god_mode := false # only used by the automated route test

func ship() -> Dictionary: return Data.SHIPS[ship_id]
func weapon() -> Dictionary: return Data.WEAPONS[weapon_id]
func max_hull() -> float: return float(ship()["hull"])
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

func restore_full() -> void:
	hull = max_hull()
	shield = max_shield()
	repairs = Data.MAX_REPAIRS
	missiles = max_missiles()
	mines = max_mines()
	heavy_missiles = max_heavy()
	energy = Data.ENERGY_MAX
	shield_charges = Data.MAX_SHIELD_CHARGES
	energy_cells = Data.MAX_ENERGY_CELLS
	changed.emit()

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

func damage(amount: float) -> void:
	if god_mode: amount *= 0.0
	var absorbed := minf(shield, amount)
	shield -= absorbed
	hull = maxf(0.0, hull - (amount - absorbed))
	changed.emit()

func use_repair() -> bool:
	if repairs <= 0 or hull >= max_hull(): return false
	repairs -= 1
	hull = minf(max_hull(), hull + max_hull() * Data.REPAIR_AMOUNT)
	changed.emit()
	return true
