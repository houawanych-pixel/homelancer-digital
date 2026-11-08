class_name AssetRegistry
extends RefCounted
## v12.68 (owner's spec: "Tripo Asset Import"): written by tools/tripo_import.py, never by hand.
## MODELS: an old model key -> the new split Tripo item that replaces it (ShipFactory loads the new one).
## ITEMS: every split item: id -> {kind, path, len, socket (the grip, as a share of its length), data (weapon stats)}.

const MODELS := {"l3_sentinel": "HL_SHIP_L3_WhiteFighter_01", "l3_corsair_king": "HL_SHIP_L3_BlueWarship_01"}
const ITEMS := {
	"HL_SHIP_L3_WhiteFighter_01": {"id": "HL_SHIP_L3_WhiteFighter_01", "kind": "ship_l3", "type": "WhiteFighter", "path": "res://assets/ships/level3/HL_SHIP_L3_WhiteFighter_01.glb", "source": "HL_SHIP_L3_WhiteFighter_Sheet.glb (one ship; 1.94M tris -> 30k)", "len": 18.0, "yaw": 0.0},
	"HL_SHIP_L3_BlueWarship_01": {"id": "HL_SHIP_L3_BlueWarship_01", "kind": "ship_l3", "type": "BlueWarship", "path": "res://assets/ships/level3/HL_SHIP_L3_BlueWarship_01.glb", "source": "HL_SHIP_L3_BlueWarship.glb (1.86M tris -> 40k; nose was +Z, turned 180)", "len": 46.0, "yaw": 180.0},
}
const PLACEHOLDERS := ["gatling", "rocket_pod", "missile", "mine", "fleet3_weapon_long", "fleet3_weapon_short", "fleet3_weapon_pod"]
