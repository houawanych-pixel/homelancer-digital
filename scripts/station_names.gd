class_name StationNames
extends RefCounted
## Job Z (v1.4v): the owner's proper station names and one line of lore each, laid over the map catalog (GalaxyData is
## generated and keeps its role names). system id -> catalog name -> [name, lore]. Ids never change, so saves are safe.
## Applied AFTER the art map, which is keyed by catalog name; each renamed station keeps it as "catalog_name".

const NAMES := {
	"synthari_capital": {
		"Grand Exchange": ["Grand Exchange", "A huge trade ring with holo-billboards and dozens of freighter docking arms, over the city-covered tech planet."],
		"Main Shipyard": ["Synthari Main Shipyard", "Long construction frames where robotic arms build ships, with finished freighters heading out."],
		"Research Lab Station": ["Synthari Research Lab Station", "White-and-gold lab pods around a glowing reactor core, with sensor dishes and test drones."],
		"Warp-Gate Hub Station": ["Synthari Warp Gate Hub", "A station built around a giant warp gate ring, with ships lined up to jump."],
	},
	"nexarion": {
		"Nexarion Data Relay": ["Quantline Datacore", "A data relay of spires around a glowing core, firing laser data beams to relay buoys."],
		"Tech Market": ["Neonmint Bazaar", "A tech-market dome packed with trader ships."],
	},
	"kellova": {
		"Kellova Cargo Depot": ["Ledgerbay Cargo Depot", "A depot frame stacked with containers, with robotic loaders and hauler convoys over the market planet."],
	},
	"techanis": {
		"Techanis Lab Station": ["Sparkwright Labs", "Lab rings around a test reactor."],
		"Prototype Shipyard": ["Firstlight Prototype Yards", "Test frames holding prototype ships over a scorched proving-ground planet."],
	},
	"crossma_major": {
		"Crossma Freeport": ["Coinfall Freeport", "A sprawling open freeport where ships from every faction dock."],
		"Crossma Customs Station": ["Sealmark Customs Station", "Rows of scanning gates and inspection berths, with freighters waiting in line."],
	},
	"crystara": {
		"Crystal Refinery": ["Opalvein Refinery", "Purifies the crystals that power Elyza lightsabers, with glowing crystal columns and leaf-shaped barge piers."],
	},
	"selenvar": {
		"Selenvar Observatory": ["Moonwhisper Observatory", "A silver crescent hull with crystal domes and a huge star-lens telescope."],
	},
	"velanthos": {
		"Velanthos Research Platform": ["Driftleaf Research Platform", "A leaf-shaped platform with garden labs and crystal test pods on energy vines, over a storm-wrapped ocean world."],
	},
	"zillance_major": {
		"Zillance Picket": ["Briarguard Picket", "An armored defense picket with crystal shield emitters and living-wood turrets."],
		"Zillance Waystation": ["Willowbough Waystation", "Habitat pods hanging from a living-wood trunk like fruit on a willow."],
	},
	"keldrix": {
		"Keldrix Patrol Base": ["Steadfast Patrol Base", "A compact patrol cutter base over a frozen planet."],
	},
	"aurentum": {
		"Reserve Vault Station": ["Lodestone Reserve Vault", "A fortified cylinder of sealed vault rings, with armored couriers and escort frigates."],
		"Trade Dock": ["Fairharbor Trade Dock", "A long docking spine where freighters from many factions line up."],
	},
	"federis": {
		"Embassy Station": ["Harmony Embassy Station", "A ring of embassy wings around a central dome where diplomats from visiting factions dock."],
		"Communications Relay": ["Clearsignal Array", "A communications relay covered in antennas, pulsing cyan signal beams."],
	},
	"void_system": {
		"Void Citadel Station": ["Nihil Citadel", "Obsidian spires veined with red light around a pulsing void rift."],
		"Gate Anchor": ["Bloodchain Tether", "A black spike chained by blood-red energy to a giant void gate, where raiders gather for invasion."],
	},
	"cynthara": {
		"Spore Station": ["Sporemother Hive", "A fungus-like organic hive with toxic-green spore pods, over a swamp world."],
	},
	"kronos": {
		"Cryo Station": ["Hoarcrypt Cryo Station", "A jagged black station frosted in ice-blue crystal, over a glacier planet."],
	},
	"noctyra": {
		"Unknown Monolith": ["The Silent Obelisk", "A perfectly smooth black monolith of unknown origin, traced with violet lines of impossible geometry."],
	},
	"genesis": {
		"Kaiju Lair": ["Behemoth Cradle", "A colossal orbital lair holding a sleeping kaiju in radioactive-yellow containment fields."],
	},
	"shroud": {
		"Smugglers' Waystation": ["Ratline Waystation", "A smugglers' stop half-hidden in nebula haze, where ships arrive without lights."],
	},
	"nebulax": {
		"Gas Harvest Station": ["Siphonwell Station", "A gas-harvest rig that hangs scoops into a gas giant."],
	},
	"nullpoint": {
		"Null-Zone Beacon": ["Hushmark Beacon", "A giant rotating beacon that warns ships away from the starless null zone."],
	},
	"vexara": {
		"Vexara Market": ["Haggler's Wheel", "A wheel-shaped market with colorful stalls and signs in many languages."],
	},
	"farreach_outpost": {
		"Farreach Outpost": ["Longhaul Halt", "A lonely refuel stop for long-haul freighters."],
	},
	"rimgate": {
		"Rimgate Control": ["Keystone Control", "Runs traffic through a huge jump gate."],
	},
	"voidtex": {
		"Voidtex Transit Station": ["Crosswind Junction", "A cross-shaped station where two Space Lanes meet."],
	},
	"beta_7": {
		"Survey Depot": ["Pathfinder Depot", "A survey depot with racks of survey drones."],
	},
	"perimeter": {
		"Perimeter Picket": ["Borderline Picket", "A border picket and customs gate."],
	},
	"sigma_19": {
		"Sigma Mining Station": ["Deepcut Transit", "A mining stop with ore hoppers and conveyor arms."],
	},
	"omega": {
		"Last Stop Station": ["World's End Emporium", "The last trading stop before the dark edge of known space."],
	},
	"foggiest": {
		"Fog Beacon Station": ["Greywhistle Beacon", "A tall fog-lamp tower that guides ships through thick grey fog."],
	},
	"ogden": {
		"Ogden Trading Post": ["Tumbleweed Trading Post", "A small frontier post with crates strapped to its hull."],
	},
	"shadow": {
		"Ghost Ship": ["The Hollow Requiem", "A dead passenger liner drifting without power, with ghostly green light and phantom shapes moving inside."],
	},
	"radiant": {
		"Shrine Platform": ["Dawnchoir Shrine", "A white-stone and gold shrine platform circled by golden rings, glowing at its heart."],
	},
	"shadenvex": {
		"Listening Post": ["Tishina Listening Post", "A spy station covered in dish arrays over a shadowed planet and its dark moon."],
	},
	"vorreth": {
		"Vorreth Garrison": ["Krepost Garrison", "A fortress of barracks decks and troop transport docks."],
	},
	"obsidrath": {
		"Obsidrath Armory": ["Molot Armory", "A foundry with a furnace glow that loads weapon crates onto freighters."],
	},
	"empire_major": {
		"Imperial Customs Station": ["Tamozh Customs House", "The Imperium's tax and customs gate, guarded by frigates."],
		"Fleet Anchorage": ["Volkov Roadstead", "A long mooring spine where the warships anchor."],
	},
	"valdris": {
		"Cipher Station": ["Kagemori Cipher Station", "Rotating glyph-lock rings guard secrets over a frozen dig-site planet."],
	},
	"sanctum_major": {
		"Sanctuary Station": ["Yumedera Sanctuary", "A serene temple station with a garden dome where pilgrims arrive."],
		"Sanctum Relay": ["Kotodama Signal Shrine", "A slender temple spire hung with signal lanterns that relays Covenant messages."],
	},
	"ironvast": {
		"Ironvast Refinery": ["Acidmaw Refinery", "A smelting fortress of glowing vats over a slag planet."],
		"Ironvast Shipyard": ["Serpentcoil Yards", "Shipyard frames that coil around half-built warships like a snake."],
	},
	"korrath": {
		"Korrath Garrison": ["Basilisk Redoubt", "A squat garrison with gun towers and drop-ship bays."],
	},
	"battlespire": {
		"Battle Station": ["Wyrmclaw Battle Station", "A spiked fortress shaped like a raised claw, with target hulks on its firing range."],
		"Arena Station": ["Bloodscale Arena", "A colosseum station with an open arena dome where spectator ships dock."],
	},
	"vortegan": {
		"Vortegan Outpost": ["Viperwatch Outpost", "A small scout outpost with a tall scanner mast."],
	},
	"omicron_major": {
		"Fleet Staging Base": ["Hydra Staging Base", "A many-armed base where warships dock like the heads of a hydra."],
		"Supply Depot": ["Gila Supply Depot", "A depot stacked with supplies for the war convoys."],
	},
	"scavaris": {
		"Salvage Hulk": ["Carrion Hulk", "A gutted capital ship being stripped by salvage tugs."],
	},
	"plundros": {
		"Smuggler Den": ["Blackbilge Den", "A crooked smugglers' den hidden in an asteroid's shadow."],
	},
	"derelicta": {
		"Derelict Hulk": ["Old Widowmaker", "The Savager home base: an ancient warship hulk surrounded by a ship graveyard."],
		"Second Derelict Hulk": ["Gallows Grin", "A pirate base in a derelict freighter with a grinning skull painted on its bow."],
	},
	"ravage_major": {
		"Raider Outpost": ["Skullcrack Roost", "A spiked raider roost built on a chunk of a cracked moon."],
	},
	"exodus_point": {
		"Refugee Transit Station": ["Kindred Passage Station", "A refugee transit ring with garden windows where convoys dock."],
		"Launch Dock": ["Oathwing Launch Dock", "Long launch rails for escort ships and convoys."],
	},
	"kiral": {
		"Kiral Militia Outpost": ["Bannerguard Outpost", "A rugged militia outpost over a mining planet."],
	},
	"republic_major": {
		"Assembly Station": ["Voicehall Assembly Station", "A domed assembly hall where delegates meet."],
		"Republic Trade Station": ["Goodweight Trade Station", "A trade ring with hand-painted murals on its hull."],
	},
}

# Stations that wear one of the owner's finished models (assets/structures/<model>.glb), and which have a lamp.
const MODELS := {"omega": "worlds_end_emporium", "shadow": "hollow_requiem", "foggiest": "light_beacon_station", "nullpoint": "light_beacon_station"}
const LAMPS := ["foggiest", "nullpoint"]
# On a planet, not in orbit: told on the planet's own line.
const ON_PLANET := {"aurelion": "Elyria (Grovecrown), the Elyza capital, is down there: a city grown into colossal ancient trees around a giant ancient-energy crystal and the Council Spire."}

static func apply(systems: Dictionary) -> Dictionary:
	for sid in NAMES:
		if not systems.has(sid): continue
		var sys: Dictionary = systems[sid]
		for body in [sys["station"]] + sys.get("more_stations", []):
			if not NAMES[sid].has(body["name"]): continue
			var row: Array = NAMES[sid][body["name"]]
			body["catalog_name"] = body["name"]
			body["name"] = row[0]
			body["desc"] = row[1] if body == sys["station"] else "%s (No docking yet.)" % row[1]
			body["lore"] = row[1]
	for sid in MODELS:
		if systems.has(sid): systems[sid]["station"]["model"] = MODELS[sid]
	for sid in LAMPS:
		if systems.has(sid): systems[sid]["station"]["lamp"] = true
	for sid in ON_PLANET:
		if systems.has(sid): systems[sid]["planet"]["desc"] = "%s %s" % [systems[sid]["planet"].get("desc", ""), ON_PLANET[sid]]
	# Greywhistle stands IN the fog: the system's cloud is grey and wraps the beacon
	if systems.has("foggiest"):
		var fg: Dictionary = systems["foggiest"]
		fg["nebula"]["center"] = fg["station"]["pos"]
		fg["nebula"]["radius"] = Data.FOG_RADIUS
		fg["nebula"]["color"] = Data.FOG_COLOR
		fg["nebula"]["name"] = "The Grey"
	return systems

## How many stations carry a proper name.
static func count() -> int:
	var n := 0
	for sid in NAMES: n += (NAMES[sid] as Dictionary).size()
	return n
