#!/usr/bin/env python3
"""Turn the galaxy map (docs/galaxy/*.csv) into game data. Run after docs/galaxy/galaxy_draft.py.
  python3 tools/galaxy/build_game_data.py
Writes scripts/galaxy_data.gd (the tile and gate tables the game builds every system from), copies each system's
sky from art/sky_library/pano to assets/skies/<id>.jpg, and rewrites the sky pack list in scripts/packs.gd.
Each system gets ONE station and ONE planet for now: the first of the catalog's proposed list (table below)."""
import csv, os, re, shutil

# system: (planet name, planet type, station name).  Types pick the planet colours (space.gd PLANET_LOOKS).
BODIES = {
 "Veranthos": ("Veranthos Prime", "city", "Senate Station"), "Keldrix": ("Keldrix", "terran", "Keldrix Patrol Base"),
 "Aurentum": ("Aurentum", "terran", "Reserve Vault Station"), "Federis": ("Federis", "terran", "Embassy Station"),
 "Aurelion": ("Aurelion Prime", "jungle", "Aurelion Citadel"), "Crystara": ("Crystara", "crystal", "Crystal Refinery"),
 "Selenvar": ("Selenvar", "ice", "Selenvar Observatory"), "Velanthos": ("Velanthos", "ocean", "Velanthos Research Platform"),
 "Zillance Major": ("Zillance Major", "jungle", "Zillance Picket"),
 "Synthari Capital": ("Synthari", "city", "Grand Exchange"), "Nexarion": ("Nexarion", "machine", "Nexarion Data Relay"),
 "Kellova": ("Kellova", "terran", "Kellova Cargo Depot"), "Techanis": ("Techanis", "desert", "Techanis Lab Station"),
 "Crossma Major": ("Crossma Major", "desert", "Crossma Freeport"),
 "Malachar": ("Malachar Prime", "city", "Orbital Command"), "Vorreth": ("Vorreth", "desert", "Vorreth Garrison"),
 "Shadenvex": ("Shadenvex", "dead", "Listening Post"), "Empire Major": ("Empire Major", "city", "Imperial Customs Station"),
 "Obsidrath": ("Obsidrath", "lava", "Obsidrath Armory"),
 "Sepheron": ("Sepheron", "ice", "Library Station"), "Valdris": ("Valdris", "desert", "Cipher Station"),
 "Sanctum Major": ("Sanctum Major", "terran", "Sanctuary Station"),
 "Dreadholm": ("Dreadholm", "lava", "Fleet Command"), "Ironvast": ("Ironvast", "desert", "Ironvast Refinery"),
 "Korrath": ("Korrath", "dead", "Korrath Garrison"), "Battlespire": ("Battlespire", "desert", "Battle Station"),
 "Vortegan": ("Vortegan", "gas", "Vortegan Outpost"), "Omicron Major": ("Omicron Major", "terran", "Fleet Staging Base"),
 "Raptian Major": ("Raptian Major", "desert", "Scrap Citadel"), "Scavaris": ("Scavaris", "dead", "Salvage Hulk"),
 "Plundros": ("Plundros", "ocean", "Smuggler Den"), "Derelicta": ("Derelicta", "dead", "Derelict Hulk"),
 "Ravage Major": ("Ravage Major", "lava", "Raider Outpost"),
 "Vantara": ("Vantara", "terran", "Resistance Headquarters"), "Exodus Point": ("Exodus Point", "desert", "Refugee Transit Station"),
 "Kiral": ("Kiral", "ice", "Kiral Militia Outpost"), "Republic Major": ("Republic Major", "terran", "Assembly Station"),
 "Void System": ("Void Citadel", "dead", "Void Citadel Station"), "Kronos": ("Kronos", "ice", "Cryo Station"),
 "Cynthara": ("Cynthara", "toxic", "Spore Station"), "Cybernet": ("Cybernet", "machine", "Assimilation Factory"),
 "Noctyra": ("Noctyra", "dead", "Unknown Monolith"), "Genesis": ("Genesis", "toxic", "Kaiju Lair"),
 "Radiant": ("Radiant Core", "crystal", "Shrine Platform"), "Shadow": ("Shadow Core", "dead", "Ghost Ship"),
 "Rimgate": ("Rimgate I", "desert", "Rimgate Control"), "Vexara": ("Vexara", "terran", "Vexara Market"),
 "Ogden": ("Ogden", "terran", "Ogden Trading Post"), "Foggiest": ("Foggiest", "gas", "Fog Beacon Station"),
 "Farreach Outpost": ("Farreach", "desert", "Farreach Outpost"), "Perimeter": ("Perimeter I", "ice", "Perimeter Picket"),
 "Nullpoint": ("Nullpoint", "dead", "Null-Zone Beacon"), "Omega": ("Omega I", "desert", "Last Stop Station"),
 "Sigma-19": ("Sigma-19", "desert", "Sigma Mining Station"), "Beta-7": ("Beta-7", "terran", "Survey Depot"),
 "Voidtex": ("Voidtex", "dead", "Voidtex Transit Station"), "Shroud": ("Shroud", "gas", "Smugglers' Waystation"),
 "Nebulax": ("Nebulax", "gas", "Gas Harvest Station"),
 "THE HEART": ("Heart World", "crystal", "Heart Beacon"),
}
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
''' % ("\n".join(rows), "\n".join(grow)))
p = os.path.join(root, "scripts/packs.gd"); s = open(p).read()
a, b = "\t# -- generated sky packs (tools/galaxy/build_game_data.py) --\n", "\t# -- end generated sky packs --\n"
if a not in s: s = s.replace('\t"cockpit": {', a + b + '\t"cockpit": {')
s = s[:s.index(a) + len(a)] + "\n".join(packs) + "\n" + s[s.index(b):]
open(p, "w").write(s)
print(len(rows), "systems,", len(grow), "gates,", len(packs), "sky packs")
