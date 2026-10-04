#!/usr/bin/env python3
"""Turn the galaxy map (docs/galaxy/*.csv) into game data. Run after docs/galaxy/galaxy_draft.py.
  python3 tools/galaxy/build_game_data.py
Writes scripts/galaxy_data.gd (the tile and gate tables the game builds every system from), copies each system's
sky from art/sky_library/pano to assets/skies/<id>.jpg, and rewrites the sky pack list in scripts/packs.gd.
Each system gets ONE station and ONE planet for now: the first of the catalog's proposed list (table below)."""
import csv, os, re, shutil

# system: ([(planet name, planet type), ...], [station names ...]) from the Star System Catalog v2 (PROPOSED contents).
# The first planet and the first station are the ones you can dock at; the rest are placeholders you can fly to.
# Types pick the planet map and temporary colour (space.gd PLANET_MAPS / PLANET_LOOKS).
SYS = {
 "Veranthos": ([("Veranthos Prime", "city"), ("Concord", "terran"), ("Bastion", "desert"), ("Meridian", "terran"), ("Halcyon", "gas")], ["Senate Station", "Diplomatic Summit Station", "Fleet Headquarters", "Customs Station"]),
 "Keldrix": ([("Keldrix", "terran"), ("Keld Minor", "desert"), ("Frost", "ice")], ["Keldrix Patrol Base"]),
 "Aurentum": ([("Aurentum", "terran"), ("Fields", "terran"), ("Barren Rock", "dead")], ["Reserve Vault Station", "Trade Dock"]),
 "Federis": ([("Federis", "terran"), ("New Federis", "terran")], ["Embassy Station", "Communications Relay"]),
 "Aurelion": ([("Aurelion Prime", "jungle"), ("Verdance", "terran"), ("Lumen", "crystal"), ("Thornwild", "jungle"), ("Calyx", "gas")], ["Aurelion Citadel", "Diplomatic and Trade Hub", "Aurelion Shipyard"]),
 "Crystara": ([("Crystara", "crystal"), ("Geode", "crystal"), ("Prism", "ice")], ["Crystal Refinery"]),
 "Selenvar": ([("Selenvar", "ice"), ("Vigil", "dead")], ["Selenvar Observatory"]),
 "Velanthos": ([("Velanthos", "ocean"), ("Reefhold", "ocean"), ("Tempest", "gas")], ["Velanthos Research Platform"]),
 "Zillance Major": ([("Zillance Major", "jungle"), ("Monolith", "desert"), ("Ashfall", "dead"), ("Zill", "gas")], ["Zillance Picket", "Zillance Waystation"]),
 "Synthari Capital": ([("Synthari", "city"), ("Forge", "lava"), ("Datafarm", "machine"), ("Portis", "ocean"), ("Sol Giant", "gas"), ("Brightside", "desert")], ["Grand Exchange", "Main Shipyard", "Research Lab Station", "Warp-Gate Hub Station"]),
 "Nexarion": ([("Nexarion", "machine"), ("Relay", "dead"), ("Coolant", "ice")], ["Nexarion Data Relay", "Tech Market"]),
 "Kellova": ([("Kellova", "terran"), ("Market", "desert"), ("Kell Moon", "dead")], ["Kellova Cargo Depot"]),
 "Techanis": ([("Techanis", "desert"), ("Proving Ground", "desert"), ("Scrap", "dead")], ["Techanis Lab Station", "Prototype Shipyard"]),
 "Crossma Major": ([("Crossma Major", "desert"), ("Depot", "dead"), ("Crossma II", "terran"), ("Crossma III", "gas")], ["Crossma Freeport", "Crossma Customs Station"]),
 "Malachar": ([("Malachar Prime", "city"), ("Garrison", "desert"), ("Gaol", "dead"), ("Anvil", "lava"), ("Mal Giant", "gas")], ["Orbital Command", "Imperial Shipyard", "Defense Platform Ring"]),
 "Vorreth": ([("Vorreth", "desert"), ("Vor Mine", "dead"), ("Barren Rock", "dead")], ["Vorreth Garrison"]),
 "Shadenvex": ([("Shadenvex", "dead"), ("Umbra", "dead")], ["Listening Post"]),
 "Empire Major": ([("Empire Major", "city"), ("Colonia", "terran"), ("Mill", "desert"), ("Imperial Giant", "gas")], ["Imperial Customs Station", "Fleet Anchorage"]),
 "Obsidrath": ([("Obsidrath", "lava"), ("Cinder", "lava"), ("Ash", "dead")], ["Obsidrath Armory"]),
 "Sepheron": ([("Sepheron", "ice"), ("Sanctorum", "desert"), ("Vault Moon", "dead"), ("Veilgiant", "gas")], ["Library Station", "Sepheron Observatory", "Sealed Vault Station"]),
 "Valdris": ([("Valdris", "desert"), ("Dig", "desert"), ("Rime", "ice")], ["Cipher Station"]),
 "Sanctum Major": ([("Sanctum Major", "terran"), ("Cloister", "desert"), ("Sanctum III", "dead")], ["Sanctuary Station", "Sanctum Relay"]),
 "Dreadholm": ([("Dreadholm", "lava"), ("Academy", "desert"), ("Munitions", "machine"), ("Vassal", "terran"), ("Dread Giant", "gas")], ["Fleet Command", "Dreadholm Shipyard", "Drydock", "Orbital Battery Ring"]),
 "Ironvast": ([("Ironvast", "desert"), ("Foundry", "lava"), ("Slag", "dead")], ["Ironvast Refinery", "Ironvast Shipyard"]),
 "Korrath": ([("Korrath", "dead"), ("Barren Rock", "dead")], ["Korrath Garrison"]),
 "Battlespire": ([("Battlespire", "desert"), ("Range", "desert")], ["Battle Station", "Arena Station"]),
 "Vortegan": ([("Vortegan", "gas"), ("Frontier Colony", "terran"), ("Vort Giant", "gas")], ["Vortegan Outpost"]),
 "Omicron Major": ([("Omicron Major", "terran"), ("Omicron II", "terran"), ("Omicron III", "desert"), ("Omicron IV", "gas")], ["Fleet Staging Base", "Supply Depot"]),
 "Raptian Major": ([("Raptian Major", "desert"), ("Junkworld", "dead"), ("Feral", "jungle"), ("Raptor Giant", "gas")], ["Scrap Citadel", "Black Market Station", "Salvage Yard"]),
 "Scavaris": ([("Scavaris", "dead"), ("Husk", "dead")], ["Salvage Hulk"]),
 "Plundros": ([("Plundros", "ocean"), ("Hoard", "desert"), ("Plundros III", "ice")], ["Smuggler Den"]),
 "Derelicta": ([("Derelicta", "dead"), ("Tomb", "dead")], ["Derelict Hulk", "Second Derelict Hulk"]),
 "Ravage Major": ([("Ravage Major", "lava"), ("Pit", "desert"), ("Cracked Moon", "dead")], ["Raider Outpost"]),
 "Vantara": ([("Vantara", "terran"), ("Haven", "terran"), ("Harvest", "terran"), ("Hideout", "dead")], ["Resistance Headquarters", "Refugee Haven Station", "Vantara Shipyard"]),
 "Exodus Point": ([("Exodus Point", "desert"), ("Waypoint Moon", "dead")], ["Refugee Transit Station", "Launch Dock"]),
 "Kiral": ([("Kiral", "ice"), ("Kiral Mine", "dead"), ("Ice World", "ice")], ["Kiral Militia Outpost"]),
 "Republic Major": ([("Republic Major", "terran"), ("Colony One", "terran"), ("Colony Two", "desert")], ["Assembly Station", "Republic Trade Station"]),
 "Void System": ([("Void Citadel", "dead"), ("Husk", "dead"), ("Scar", "lava")], ["Void Citadel Station", "Gate Anchor"]),
 "Kronos": ([("Kronos", "ice"), ("Glacier", "ice"), ("Floe", "ice")], ["Cryo Station"]),
 "Cynthara": ([("Cynthara", "toxic"), ("Mire", "toxic"), ("Brood", "jungle")], ["Spore Station"]),
 "Cybernet": ([("Cybernet", "machine"), ("Core", "machine")], ["Assimilation Factory", "Signal Relay"]),
 "Noctyra": ([("Noctyra", "dead"), ("Eclipse", "dead")], ["Unknown Monolith"]),
 "Genesis": ([("Genesis", "toxic"), ("Wildgrowth", "jungle"), ("Titan Moon", "dead")], ["Kaiju Lair"]),
 "Radiant": ([("Radiant Core", "crystal")], ["Shrine Platform"]),
 "Shadow": ([("Shadow Core", "dead"), ("Dead Moon", "dead")], ["Ghost Ship"]),
 "Rimgate": ([("Rimgate I", "desert"), ("Rimgate II", "gas")], ["Rimgate Control"]),
 "Vexara": ([("Vexara", "terran"), ("Vexara II", "dead")], ["Vexara Market"]),
 "Ogden": ([("Ogden", "terran"), ("Ogden's Rock", "dead")], ["Ogden Trading Post"]),
 "Foggiest": ([("Foggiest", "gas"), ("Mist", "dead")], ["Fog Beacon Station"]),
 "Farreach Outpost": ([("Farreach", "desert")], ["Farreach Outpost"]),
 "Perimeter": ([("Perimeter I", "ice"), ("Perimeter II", "ice")], ["Perimeter Picket"]),
 "Nullpoint": ([("Nullpoint", "dead")], ["Null-Zone Beacon"]),
 "Omega": ([("Omega I", "desert"), ("Omega II", "dead"), ("Omega III", "gas")], ["Last Stop Station"]),
 "Sigma-19": ([("Sigma-19", "desert"), ("Sigma-19b", "dead")], ["Sigma Mining Station"]),
 "Beta-7": ([("Beta-7", "terran")], ["Survey Depot"]),
 "Voidtex": ([("Voidtex", "dead"), ("Voidtex II", "dead")], ["Voidtex Transit Station"]),
 "Shroud": ([("Shroud", "gas"), ("Shroud II", "gas")], ["Smugglers' Waystation"]),
 "Nebulax": ([("Nebulax", "gas")], ["Gas Harvest Station"]),
 "THE HEART": ([("Heart World", "crystal")], ["Heart Beacon"]),
}
BODIES = {k: (v[0][0][0], v[0][0][1], v[1][0]) for k, v in SYS.items()}
HEART_SKY = "spare_40"          # magenta ring, gold spiral (owner to choose)
BUILT = ("Solara", "Vega")      # hand-made in scripts/data.gd; they only get their extra gates from here

def sid(name):
    return "heart" if name == "THE HEART" else re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")

root = os.path.join(os.path.dirname(__file__), "..", "..")
tiles = [r for r in csv.DictReader(open(os.path.join(root, "docs/galaxy/galaxy_11x11_tiles.csv"))) if r["system"] != "(open space)"]
gates = list(csv.DictReader(open(os.path.join(root, "docs/galaxy/galaxy_11x11_gates.csv"))))
os.makedirs(os.path.join(root, "assets/skies"), exist_ok=True)
rows, packs = [], []
for r in tiles:
    n, i = r["system"], sid(r["system"])
    col, row = "ABCDEFGHIJK".index(r["tile"][0]), int(r["tile"][1:]) - 1
    if n in BUILT:
        rows.append('\t["%s", "%s", "%s", %d, %d, "%s", "built", "", "", ""],' % (i, n, r["tile"], col, row, r["faction"])); continue
    if r["faction"] == "Void": pl, pt, st = "%s I" % n, "dead", "%s Beacon" % n
    else: pl, pt, st = BODIES[n]
    rows.append('\t["%s", "%s", "%s", %d, %d, "%s", "%s", "%s", "%s", "%s"],' % (i, n.title() if n == "THE HEART" else n, r["tile"], col, row, r["faction"], r["role"], pl, pt, st))
    src = os.path.join(root, "art/sky_library/pano", (HEART_SKY if n == "THE HEART" else i) + ".jpg")
    shutil.copyfile(src, os.path.join(root, "assets/skies", i + ".jpg"))
    packs.append('\t"sky_%s": {"folders": ["res://assets/skies"], "match": "%s.", "probe": "res://assets/skies/%s.jpg"},' % (i, i, i))
extra = []
for r in tiles:
    n = r["system"]
    if n in SYS:
        for pn, pt in SYS[n][0][1:]: extra.append('\t["%s", "planet", "%s", "%s"],' % (sid(n), pn, pt))
        for st in SYS[n][1][1:]: extra.append('\t["%s", "station", "%s", ""],' % (sid(n), st))
grow = ['\t["%s", "%s", "%s"],' % (g["type"], sid(g["from"]), sid(g["to"])) for g in gates if g["to"] != "REALM"]
open(os.path.join(root, "scripts/galaxy_data.gd"), "w").write('''class_name GalaxyData
extends RefCounted
## GENERATED by tools/galaxy/build_game_data.py from docs/galaxy (the 11 x 11 map). Do not edit by hand.
## The game builds every system from these two tables (Data.SYSTEMS); nothing here loads art.

# id, name, tile, column, row, faction, role, planet name, planet type, station name
const TILES := [
%s
]

# kind (jump | warp | rift), system a, system b.  Every gate works both ways.
const GATES := [
%s
]

# The rest of each system from the catalog (PROPOSED): system, kind (planet | station), name, planet type.
# These are placeholders: you can see them, target them and fly to them, but not dock yet.
const EXTRAS := [
%s
]
''' % ("\n".join(rows), "\n".join(grow), "\n".join(extra)))
p = os.path.join(root, "scripts/packs.gd"); s = open(p).read()
a, b = "\t# -- generated sky packs (tools/galaxy/build_game_data.py) --\n", "\t# -- end generated sky packs --\n"
if a not in s: s = s.replace('\t"cockpit": {', a + b + '\t"cockpit": {')
s = s[:s.index(a) + len(a)] + "\n".join(packs) + "\n" + s[s.index(b):]
open(p, "w").write(s)
np_ = sum(len(v[0]) for v in SYS.values()) + 6 + 2; ns_ = sum(len(v[1]) for v in SYS.values()) + 6 + 2
print(len(rows), "systems,", len(grow), "gates,", len(packs), "sky packs;", np_, "planets,", ns_, "stations in the game (", len(extra), "placeholders )")
with open(os.path.join(root, "docs/galaxy/system_contents.csv"), "w", newline="") as f:
    w = csv.writer(f); w.writerow(["tile", "system", "faction", "planets", "stations", "planet names", "station names"])
    for r in tiles:
        n = r["system"]
        if n in SYS: w.writerow([r["tile"], n, r["faction"], len(SYS[n][0]), len(SYS[n][1]), "; ".join("%s (%s)" % x for x in SYS[n][0]), "; ".join(SYS[n][1])])
        elif n in BUILT: w.writerow([r["tile"], n, r["faction"], 1, 1, "New Terra (terran)" if n == "Solara" else "Eden Prime (jungle)", "Liberty Hub" if n == "Solara" else "Frontier Exchange"])
        else: w.writerow([r["tile"], n, r["faction"], 1, 1, "%s I (dead)" % n, "%s Beacon (automated)" % n])
