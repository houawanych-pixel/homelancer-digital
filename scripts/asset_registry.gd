class_name AssetRegistry
extends RefCounted
## v12.68 (owner's spec: "Tripo Asset Import"): written by tools/tripo_import.py, never by hand.
## MODELS: an old model key -> the new split Tripo file that replaces it (ShipFactory loads the new one).
## ITEMS: every split item: id -> {kind, path, len, socket (the grip, model-local), data (weapon stats file)}.
## Empty until Grok's GLBs land in "HL Tripo Imports" and the script runs.

const MODELS := {}
const ITEMS := {}
const PLACEHOLDERS := ["gatling", "rocket_pod", "missile", "mine", "fleet3_weapon_long", "fleet3_weapon_short", "fleet3_weapon_pod"]
