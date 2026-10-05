#!/usr/bin/env python3
"""Concept-art map (v1.4k). One table: which Drive concept image belongs to which system, station room and planet
location. Writes scripts/art_refs.gd (game data) and docs/ART_MAP.md (the report). The images stay in Drive
(concept-art folder); this only records the reference. Run: python3 tools/art/build_art_refs.py
Standard: Concept-Art-First Pipeline (lore, then concept sheets, then exteriors, interiors, characters)."""
import json, os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROOMS = ["main_hub", "shipyard", "dealer", "weapons_dealer", "supplies", "bar", "mission_board", "rest_quarters"]
ROOM_NAMES = {"main_hub": "Main hub", "shipyard": "Shipyard", "dealer": "Dealer", "weapons_dealer": "Weapons dealer",
              "supplies": "Supplies", "bar": "Bar", "mission_board": "Mission board", "rest_quarters": "Bedroom / rest quarters"}
def st(tag, date="20261004"):
    key = {"main_hub": "MainHub", "shipyard": "Shipyard", "dealer": "Dealer", "weapons_dealer": "WeaponsDealer",
           "supplies": "Supplies", "bar": "Bar", "mission_board": "MissionBoard", "rest_quarters": "Room"}
    return lambda room, did: {"file": "HOMELANCER_Station_%s_%s_Panorama_16x9_%s_v1.png" % (tag, key[room], date), "drive": did}
def ext(tag, did): return {"file": "HOMELANCER_StationExterior_%s_16x9_20261004_v1.png" % tag, "drive": did}
def pl(name, did, v="v1"): return {"file": "HOMELANCER_Planet_Aurelion-Prime_%s_Panorama_16x9_20261005_%s.png" % (name, v), "drive": did}

cit, hub, yard = st("Aurelion-CapitalOrbitalCitadel"), st("Aurelion-DiplomaticTradeHub"), st("Aurelion-Shipyard")
ELF_GUARDS = {"armor": ["paladin", "dark_knight"], "colors": "royal blue and silver (darker variants allowed)",
              "loadouts": ["big gunblade on the back", "pistol gunblade on the hip", "cape, no large weapon", "other weapon"],
              "recycled_characters": False, "none_in": ["rest_quarters"]}
SYSTEMS = {
 "aurelion": {
  "lore": "guide", "faction": "Elyza", "guards": ELF_GUARDS,
  "stations": {
   "Aurelion Citadel": {"sheet": None, "exterior": ext("Aurelion-CapitalOrbitalCitadel", "1d4ifG_T1J4VgmsjJYNGYKjl3qhi30_Zb"), "rooms": {
     "main_hub": cit("main_hub", "1Kx8JlCiyRzUYTrxGGS4dF90ZlbOBdt60"), "shipyard": cit("shipyard", "1qhHeOod9YD23n4ZzurhDE20ujeO6cHUv"),
     "dealer": cit("dealer", "1gWki5sF2P_787-iquKa3JJLZ-Lz12PEd"), "weapons_dealer": cit("weapons_dealer", "1U9QCDcL_kYqdxYAUmr5oewP_Blid4GvH"),
     "supplies": cit("supplies", "1U-y7Az9i5Tgzpc-jBP3-b9y4yaNlG3WS"), "bar": cit("bar", "1DQ3Zv0Nx8Ocac_QF7f62UC9zNcSRo1Bn"),
     "mission_board": cit("mission_board", "1N7XXlT5ZIsgBe9zclYm9mabhxQWf-oxf"), "rest_quarters": cit("rest_quarters", "1dTgYIWpA0CxbS6OFPm3yxA-fmc5eiirL")}},
   "Diplomatic and Trade Hub": {"sheet": None, "exterior": ext("Aurelion-DiplomaticTradeHub", "1KXWQrpRqCzQGravyP4AiejR0lgkpgk59"), "rooms": {
     "main_hub": hub("main_hub", "1f7WWvb8HA9hZLLHxZ6ojoWgikXJyFdel"), "shipyard": hub("shipyard", "14ep4HEITKLNdegexgz_itAOZk2vWAoUz"),
     "dealer": hub("dealer", "12vZY_2WoFV0Ih1bd8hjuxCLwzfmdhBBX"), "weapons_dealer": hub("weapons_dealer", "1g9yAUiWetjPZ-vbmrUskFrgkEl5qMRuf"),
     "supplies": hub("supplies", "12tdIREZzW6QRTLI6GdmDZELmzOf5Nn3t"), "bar": hub("bar", "1uRe6KaE1nvTJ9pdxUznuquSzItfB2vrp"),
     "mission_board": hub("mission_board", "1t_Sx-e4pLSn-qpxfnzFLqXlvORBRtQFq"), "rest_quarters": hub("rest_quarters", "1tfau3yGkMvX2TuhXoOaXhBIjBv3aFsqE")}},
   "Aurelion Shipyard": {"sheet": None, "exterior": ext("Aurelion-Shipyard", "1CVR3HNyxi_luC1g1T07BmDKw2KyrHHo6"), "rooms": {
     "main_hub": yard("main_hub", "1_62xZhJLgL69-8tov_p-xfGd9M4ZeP20"), "shipyard": yard("shipyard", "16HIjxgyx73nnVInfBtaYFH7bNOHl8o3T"),
     "dealer": yard("dealer", "1mYc36qir-S68jUWi8hfjZdEz5HVMHwtN"), "weapons_dealer": yard("weapons_dealer", "1Z4vTtWjj8XICNbR3RKslNdUtLS0s94pS"),
     "supplies": yard("supplies", "1OJbIShgIzZSjjCiflBBltfjkj_xxgINt"), "bar": yard("bar", "1JvXbloHLRZ3Yldv1_BTG_077pepyVf7b"),
     "mission_board": yard("mission_board", "1ibqV5cqMoUg8ysmwxXVwWLtR9hYS94OC"), "rest_quarters": yard("rest_quarters", "1baSkJTvUWBiyHQo33qJFTX9yWx3V1So8")}},
  },
  "planets": {
   "Aurelion Prime": {
     "sheet": {"code": "A01", "file": "HOMELANCER_PlanetConcept_Aurelion-Prime_16x9_20261005_v1.png", "drive": "1-mbfT1FYbjWCbVG0WRVJq1JXVEezlcVH"},
     "locations": [
      {"id": "grovecrown", "name": "Grovecrown", "aerial": dict(pl("Grovecrown_Aerial", "11SdAc7vHO5J8qbyY0jA1ye87qIuvkEeI"), code="A02"),
       "first_person": dict(pl("Grovecrown_FirstPerson", "1sVL20pwYcIo8AnDTsZ9eEMefS_E-KOj6"), code="A03")},
      {"id": "ley_well_sanctum", "name": "Ley-Well Sanctum", "aerial": dict(pl("LeyWellSanctum_Aerial", "10ynTOTe-UjBwsh_hXkmRPzc4tAlyf4DM", "v2"), code="A04"),
       "first_person": dict(pl("LeyWellSanctum_FirstPerson", "1DAM-JVmOoVTNmYgc5eU0NwYcEI7-5Osd"), code="A05")},
      {"id": "silverfall_lakes", "name": "Silverfall Lakes", "aerial": dict(pl("SilverfallLakes_Aerial", "1kfXgmyU2-KJ5j75BI2MflaZzTAtCETAk"), code="A06"),
       "first_person": dict(pl("SilverfallLakes_FirstPerson", "1dzhb_EB1SqoZt7mMN53WwdmVSVVXZ3Ji"), code="A07")},
      {"id": "canopy_spire_port", "name": "Canopy Spire Port", "aerial": dict(pl("CanopySpirePort_Aerial", "1n7o1wRm_fWJl9t9a32P_nvtTmnE_Q1E_"), code="A08"),
       "first_person": dict(pl("CanopySpirePort_FirstPerson", "1HNeIzBcI58HdiIXNtAXHZSBSXte8AYjg"), code="A09")},
     ],
     "scenes": [{"id": "alisa_temple_throne", "name": "Alisa's temple throne", "code": "AU01",
                 "file": "HOMELANCER_Scene_Aurelion-Prime_AlisaTempleThrone_16x9_20261005_v1.png", "drive": "1fnUMdyK9L-bq2O3oTa8wIPQHVccvU-lv"}]},
   "Verdance": None, "Lumen": None, "Thornwild": None, "Calyx": None,
  },
 },
 "scavaris": {
  "lore": "thin", "faction": "Savagers", "guards": None,
  "stations": {"Salvage Hulk": None},
  "planets": {"Scavaris": None, "Husk": None},
 },
 "crystara": {
  "lore": "locked", "faction": "Elyza", "guards": ELF_GUARDS,
  "note": "Lightsaber-crystal harvest (Crystara), deep mining and vaults (Geode), tempering (Prism), cut and ship (Crystal Refinery). Station proper name still open: Opalvein Refinery or Crystal Refinery.",
  "stations": {"Crystal Refinery": None},
  "planets": {"Crystara": None, "Geode": None, "Prism": None},
 },
}
# Faction sheets that are not places (Cybermorph has no stations).
FACTION_SHEETS = {"cybermorph": [
 {"code": "CM01", "name": "Faction concept sheet", "file": "HOMELANCER_Cybermorph_CM01_FactionConceptSheet_MachinesOnly_16x9_20261005_v2.png", "drive": "1m_AXW_TwkmcHhLZXCB6rxu2Ohb6Pzf6e"},
 {"code": "CM02", "name": "Hexdominator", "file": "HOMELANCER_Cybermorph_CM02_Hexdominator_MachinesOnly_16x9_20261005_v2.png", "drive": "13HOa9wOVGpy5j5vuNA72yZ-CkpULCo9s"},
 {"code": "CM03", "name": "Shardstorm", "file": "HOMELANCER_Cybermorph_CM03_Shardstorm_MachinesOnly_16x9_20261005_v2.png", "drive": "1Im6BpvnFXjggxWipKm-fgGPm4CkwAXEG"},
 {"code": "CM04", "name": "Mothership", "file": "HOMELANCER_Cybermorph_CM04_Mothership_MachinesOnly_16x9_20261005_v2.png", "drive": "1T1K8GV6HTISovczrMsfn5dA-ie1B1pcn"},
 {"code": "CM05", "name": "Invasion scene", "file": "HOMELANCER_Cybermorph_CM05_Invasion_MachinesOnly_16x9_20261005_v2.png", "drive": "1TVDfSq6MV2rshLtM97KxXr2r44Ty3O91"},
]}

def gd(v, ind=1):
    t = "\t" * ind
    if v is None: return "null"
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, str): return json.dumps(v, ensure_ascii=False)
    if isinstance(v, list):
        if all(isinstance(x, str) for x in v): return "[" + ", ".join(gd(x) for x in v) + "]"
        return "[\n" + "".join(t + "\t" + gd(x, ind + 1) + ",\n" for x in v) + t + "]"
    if isinstance(v, dict):
        if all(not isinstance(x, (dict, list)) for x in v.values()): return "{" + ", ".join("%s: %s" % (json.dumps(k), gd(x)) for k, x in v.items()) + "}"
        return "{\n" + "".join(t + "\t%s: %s,\n" % (json.dumps(k), gd(x, ind + 1)) for k, x in v.items()) + t + "}"
    return str(v)

HEAD = '''class_name ArtRefs
extends RefCounted
## GENERATED by tools/art/build_art_refs.py: do not edit by hand. Report: docs/ART_MAP.md.
## Concept-art map (v1.4k): which Drive concept image is the visual reference for each station room and planet
## location. The pictures stay in Drive (concept-art); the game only stores the reference until a picture is turned
## into a room strip. null = no art yet (do not invent it: concept sheet first).

const ROOMS := %s
const SYSTEMS := %s
const FACTION_SHEETS := %s

## Write the references into the system data: station["art"], planet["art"] (found by name), sys["art_guards"].
static func apply(systems: Dictionary) -> Dictionary:
	for sid in SYSTEMS:
		if not systems.has(sid): continue
		var sys: Dictionary = systems[sid]
		var a: Dictionary = SYSTEMS[sid]
		sys["art_guards"] = a["guards"]
		sys["art_lore"] = a["lore"]
		for body in [sys["station"], sys["planet"]] + sys.get("more_stations", []) + sys.get("more_planets", []):
			var table: Dictionary = a["stations"] if a["stations"].has(body["name"]) else a["planets"]
			if table.has(body["name"]): body["art"] = table[body["name"]]
	return systems

## The reference for one hub room of a station, or {} when there is no art yet.
static func room(sid: String, station: String, room_id: String) -> Dictionary:
	var s = SYSTEMS.get(sid, {}).get("stations", {}).get(station)
	if s == null: return {}
	var r = s["rooms"].get(room_id)
	return r if r != null else {}

## Everything still without art, as plain lines (the report uses the same list).
static func missing() -> Array:
	var out: Array = []
	for sid in SYSTEMS:
		var a: Dictionary = SYSTEMS[sid]
		for nm in a["stations"]:
			var s = a["stations"][nm]
			if s == null: out.append("%%s / %%s: concept sheet, exterior and all %%d rooms" %% [sid, nm, ROOMS.size()])
			else:
				if s["sheet"] == null: out.append("%%s / %%s: concept sheet" %% [sid, nm])
				for r in ROOMS:
					if s["rooms"].get(r) == null: out.append("%%s / %%s: %%s" %% [sid, nm, r])
		for nm in a["planets"]:
			if a["planets"][nm] == null: out.append("%%s / planet %%s: concept sheet and locations" %% [sid, nm])
	return out
'''
open(os.path.join(ROOT, "scripts/art_refs.gd"), "w").write(HEAD % (gd(ROOMS, 0), gd(SYSTEMS, 0), gd(FACTION_SHEETS, 0)))

L = ["# Concept-art map (v1.4k)", "",
     "GENERATED by `tools/art/build_art_refs.py`. Game data: `scripts/art_refs.gd`. Pictures stay in Drive, folder concept-art.",
     "Order (Concept-Art-First standard): lore, concept sheet, exterior, interiors, characters. Nothing is invented where art is missing.", ""]
def link(r): return "[%s](https://drive.google.com/file/d/%s/view)" % (r["file"], r["drive"])
for sid, a in SYSTEMS.items():
    L += ["## %s (%s) — lore: %s" % (sid.capitalize(), a["faction"], {"guide": "in the Faction Guide, not Bible-locked", "thin": "one line only (name and faction)", "locked": "Bible-locked 2026-10-05"}[a["lore"]]), ""]
    if a.get("note"): L += [a["note"], ""]
    for nm, s in a["stations"].items():
        if s is None: L += ["- Station **%s**: NO ART. Needs concept sheet, exterior, and %d rooms." % (nm, len(ROOMS))]; continue
        L += ["- Station **%s**" % nm, "  - Concept sheet: %s" % ("MISSING" if s["sheet"] is None else link(s["sheet"])), "  - Exterior: %s" % link(s["exterior"])]
        for r in ROOMS: L += ["  - %s: %s" % (ROOM_NAMES[r], link(s["rooms"][r]) if s["rooms"].get(r) else "MISSING")]
    for nm, p in a["planets"].items():
        if p is None: L += ["- Planet **%s**: NO ART. Needs concept sheet and locations." % nm]; continue
        L += ["- Planet **%s**" % nm, "  - %s concept sheet: %s" % (p["sheet"]["code"], link(p["sheet"]))]
        for loc in p["locations"]:
            L += ["  - %s: aerial %s %s, first-person %s %s" % (loc["name"], loc["aerial"]["code"], link(loc["aerial"]), loc["first_person"]["code"], link(loc["first_person"]))]
        for sc in p["scenes"]: L += ["  - Scene %s, %s: %s" % (sc["code"], sc["name"], link(sc))]
    if a["guards"]:
        g = a["guards"]
        L += ["- Guards: %s armor, %s. Loadouts mixed: %s. No recycled characters. No guards in the bedroom." % (" or ".join(x.replace("_", " ") for x in g["armor"]), g["colors"], "; ".join(g["loadouts"]))]
    L += [""]
L += ["## Cybermorph (no stations, machines only)", ""] + ["- %s %s: %s" % (s["code"], s["name"], link(s)) for s in FACTION_SHEETS["cybermorph"]] + [""]
open(os.path.join(ROOT, "docs/ART_MAP.md"), "w").write("\n".join(L))
print("ok")
