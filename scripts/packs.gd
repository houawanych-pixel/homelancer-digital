extends Node
## Content packs (autoload "Packs"): content that is not needed to start playing is NOT inside the main game
## download. Each pack is a small .pck next to the web build (packs/<name>.pck), fetched in the background or when
## the player goes somewhere that needs it, then mounted with ProjectSettings.load_resource_pack().
## Rule for growing the universe: every new planet / star system / big model set gets its own pack here, so adding
## content never makes the first load bigger. In the editor and desktop test runs the files are already in res://,
## so every pack counts as ready immediately.

signal pack_ready(name: String)

# folders: whole asset folders in the pack. match: only files whose name starts with this. probe: a file that exists
# once the pack is mounted. The main export leaves these folders out (export_presets.cfg exclude_filter).
const PACKS := {
	"assistant": {"folders": ["res://assets/assistant"], "probe": "res://assets/assistant/idle_a.ogv"},   # v3.7: the owner's station assistant (green screen, keyed in the game)
	"room_savagers_main_hub": {"folders": ["res://assets/rooms/savagers"], "match": "main_hub.", "probe": "res://assets/rooms/savagers/main_hub.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_shipyard": {"folders": ["res://assets/rooms/savagers"], "match": "shipyard.", "probe": "res://assets/rooms/savagers/shipyard.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_mech_dealer": {"folders": ["res://assets/rooms/savagers"], "match": "mech_dealer.", "probe": "res://assets/rooms/savagers/mech_dealer.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_weapons": {"folders": ["res://assets/rooms/savagers"], "match": "weapons.", "probe": "res://assets/rooms/savagers/weapons.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_supplies": {"folders": ["res://assets/rooms/savagers"], "match": "supplies.", "probe": "res://assets/rooms/savagers/supplies.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_mission_center": {"folders": ["res://assets/rooms/savagers"], "match": "mission_center.", "probe": "res://assets/rooms/savagers/mission_center.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_medical_bay": {"folders": ["res://assets/rooms/savagers"], "match": "medical_bay.", "probe": "res://assets/rooms/savagers/medical_bay.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_command": {"folders": ["res://assets/rooms/savagers"], "match": "command.", "probe": "res://assets/rooms/savagers/command.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_private_quarters": {"folders": ["res://assets/rooms/savagers"], "match": "private_quarters.", "probe": "res://assets/rooms/savagers/private_quarters.jpg"},   # v3.8: the owner's 360 room
	"room_savagers_pilots_lounge": {"folders": ["res://assets/rooms/savagers"], "match": "pilots_lounge.", "probe": "res://assets/rooms/savagers/pilots_lounge.jpg"},   # v3.8: the owner's 360 room
	"room_orion_main_hub": {"folders": ["res://assets/rooms/orion"], "match": "main_hub.", "probe": "res://assets/rooms/orion/main_hub.jpg"},   # the owner's 360 room
	"room_orion_shipyard": {"folders": ["res://assets/rooms/orion"], "match": "shipyard.", "probe": "res://assets/rooms/orion/shipyard.jpg"},   # the owner's 360 room
	"room_orion_mech_dealer": {"folders": ["res://assets/rooms/orion"], "match": "mech_dealer.", "probe": "res://assets/rooms/orion/mech_dealer.jpg"},   # the owner's 360 room
	"room_orion_weapons": {"folders": ["res://assets/rooms/orion"], "match": "weapons.", "probe": "res://assets/rooms/orion/weapons.jpg"},   # the owner's 360 room
	"room_orion_supplies": {"folders": ["res://assets/rooms/orion"], "match": "supplies.", "probe": "res://assets/rooms/orion/supplies.jpg"},   # the owner's 360 room
	"room_orion_mission_center": {"folders": ["res://assets/rooms/orion"], "match": "mission_center.", "probe": "res://assets/rooms/orion/mission_center.jpg"},   # the owner's 360 room
	"room_orion_medical_bay": {"folders": ["res://assets/rooms/orion"], "match": "medical_bay.", "probe": "res://assets/rooms/orion/medical_bay.jpg"},   # the owner's 360 room
	"room_orion_command": {"folders": ["res://assets/rooms/orion"], "match": "command.", "probe": "res://assets/rooms/orion/command.jpg"},   # the owner's 360 room
	"room_orion_private_quarters": {"folders": ["res://assets/rooms/orion"], "match": "private_quarters.", "probe": "res://assets/rooms/orion/private_quarters.jpg"},   # the owner's 360 room
	"room_orion_pilots_lounge": {"folders": ["res://assets/rooms/orion"], "match": "pilots_lounge.", "probe": "res://assets/rooms/orion/pilots_lounge.jpg"},   # the owner's 360 room
	"room_covenant_main_hub": {"folders": ["res://assets/rooms/covenant"], "match": "main_hub.", "probe": "res://assets/rooms/covenant/main_hub.jpg"},   # the owner's 360 room
	"room_covenant_shipyard": {"folders": ["res://assets/rooms/covenant"], "match": "shipyard.", "probe": "res://assets/rooms/covenant/shipyard.jpg"},   # the owner's 360 room
	"room_covenant_mech_dealer": {"folders": ["res://assets/rooms/covenant"], "match": "mech_dealer.", "probe": "res://assets/rooms/covenant/mech_dealer.jpg"},   # the owner's 360 room
	"room_covenant_weapons": {"folders": ["res://assets/rooms/covenant"], "match": "weapons.", "probe": "res://assets/rooms/covenant/weapons.jpg"},   # the owner's 360 room
	"room_covenant_supplies": {"folders": ["res://assets/rooms/covenant"], "match": "supplies.", "probe": "res://assets/rooms/covenant/supplies.jpg"},   # the owner's 360 room
	"room_covenant_mission_center": {"folders": ["res://assets/rooms/covenant"], "match": "mission_center.", "probe": "res://assets/rooms/covenant/mission_center.jpg"},   # the owner's 360 room
	"room_covenant_medical_bay": {"folders": ["res://assets/rooms/covenant"], "match": "medical_bay.", "probe": "res://assets/rooms/covenant/medical_bay.jpg"},   # the owner's 360 room
	"room_covenant_command": {"folders": ["res://assets/rooms/covenant"], "match": "command.", "probe": "res://assets/rooms/covenant/command.jpg"},   # the owner's 360 room
	"room_covenant_private_quarters": {"folders": ["res://assets/rooms/covenant"], "match": "private_quarters.", "probe": "res://assets/rooms/covenant/private_quarters.jpg"},   # the owner's 360 room
	"room_covenant_pilots_lounge": {"folders": ["res://assets/rooms/covenant"], "match": "pilots_lounge.", "probe": "res://assets/rooms/covenant/pilots_lounge.jpg"},   # the owner's 360 room
	"room_liberator_main_hub": {"folders": ["res://assets/rooms/liberator"], "match": "main_hub.", "probe": "res://assets/rooms/liberator/main_hub.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_shipyard": {"folders": ["res://assets/rooms/liberator"], "match": "shipyard.", "probe": "res://assets/rooms/liberator/shipyard.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_mech_dealer": {"folders": ["res://assets/rooms/liberator"], "match": "mech_dealer.", "probe": "res://assets/rooms/liberator/mech_dealer.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_weapons": {"folders": ["res://assets/rooms/liberator"], "match": "weapons.", "probe": "res://assets/rooms/liberator/weapons.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_supplies": {"folders": ["res://assets/rooms/liberator"], "match": "supplies.", "probe": "res://assets/rooms/liberator/supplies.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_mission_center": {"folders": ["res://assets/rooms/liberator"], "match": "mission_center.", "probe": "res://assets/rooms/liberator/mission_center.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_medical_bay": {"folders": ["res://assets/rooms/liberator"], "match": "medical_bay.", "probe": "res://assets/rooms/liberator/medical_bay.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_command": {"folders": ["res://assets/rooms/liberator"], "match": "command.", "probe": "res://assets/rooms/liberator/command.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_private_quarters": {"folders": ["res://assets/rooms/liberator"], "match": "private_quarters.", "probe": "res://assets/rooms/liberator/private_quarters.jpg"},   # v3.5: the owner's 360 room
	"room_liberator_pilots_lounge": {"folders": ["res://assets/rooms/liberator"], "match": "pilots_lounge.", "probe": "res://assets/rooms/liberator/pilots_lounge.jpg"},   # v3.5: the owner's 360 room
	"hangar_p_kaijurai": {"folders": ["res://assets/hangars"], "match": "bay_p_kaijurai.", "probe": "res://assets/hangars/bay_p_kaijurai.jpg"},   # v2.9: the owner's planet hangar
	"hangar_p_phenom": {"folders": ["res://assets/hangars"], "match": "bay_p_phenom.", "probe": "res://assets/hangars/bay_p_phenom.jpg"},   # v2.9: the owner's planet hangar
	"hangar_p_cybermorph": {"folders": ["res://assets/hangars"], "match": "bay_p_cybermorph.", "probe": "res://assets/hangars/bay_p_cybermorph.jpg"},   # v2.9: the owner's planet hangar
	"hangar_p_arctides": {"folders": ["res://assets/hangars"], "match": "bay_p_arctides.", "probe": "res://assets/hangars/bay_p_arctides.jpg"},   # v2.9: the owner's planet hangar
	"hangar_p_solrath": {"folders": ["res://assets/hangars"], "match": "bay_p_solrath.", "probe": "res://assets/hangars/bay_p_solrath.jpg"},   # v2.9: the owner's planet hangar
	"hangar_p_imperium": {"folders": ["res://assets/hangars"], "match": "bay_p_imperium.", "probe": "res://assets/hangars/bay_p_imperium.jpg"},   # v2.8: the owner's planet hangar
	"hangar_p_unity": {"folders": ["res://assets/hangars"], "match": "bay_p_unity.", "probe": "res://assets/hangars/bay_p_unity.jpg"},   # v2.8: the owner's planet hangar
	"hangar_p_orion": {"folders": ["res://assets/hangars"], "match": "bay_p_orion.", "probe": "res://assets/hangars/bay_p_orion.jpg"},   # v2.8: the owner's planet hangar
	"hangar_p_liberator": {"folders": ["res://assets/hangars"], "match": "bay_p_liberator.", "probe": "res://assets/hangars/bay_p_liberator.jpg"},   # v2.8: the owner's planet hangar
	"hangar_p_savagers": {"folders": ["res://assets/hangars"], "match": "bay_p_savagers.", "probe": "res://assets/hangars/bay_p_savagers.jpg"},   # v2.8: the owner's planet hangar
	"hangar_p_covenant": {"folders": ["res://assets/hangars"], "match": "bay_p_covenant.", "probe": "res://assets/hangars/bay_p_covenant.jpg"},   # v2.8: the owner's planet hangar
	"hangar_p_elyza": {"folders": ["res://assets/hangars"], "match": "bay_p_elyza.", "probe": "res://assets/hangars/bay_p_elyza.jpg"},   # v2.8: the owner's planet hangar
	"hangar_p_solarion": {"folders": ["res://assets/hangars"], "match": "bay_p_solarion.", "probe": "res://assets/hangars/bay_p_solarion.jpg"},   # v2.8: the owner's planet hangar
	"hangar_arctides": {"folders": ["res://assets/hangars"], "match": "bay_arctides.", "probe": "res://assets/hangars/bay_arctides.jpg"},   # v3.0: the owner's station hangar
	"hangar_phenom": {"folders": ["res://assets/hangars"], "match": "bay_phenom.", "probe": "res://assets/hangars/bay_phenom.jpg"},   # v3.0: the owner's station hangar
	"hangar_gadversee": {"folders": ["res://assets/hangars"], "match": "bay_gadversee.", "probe": "res://assets/hangars/bay_gadversee.jpg"},   # v3.0: the owner's station hangar
	"hangar_solrath": {"folders": ["res://assets/hangars"], "match": "bay_solrath.", "probe": "res://assets/hangars/bay_solrath.jpg"},   # v3.0: the owner's station hangar
	"hangar_cybermorph": {"folders": ["res://assets/hangars"], "match": "bay_cybermorph.", "probe": "res://assets/hangars/bay_cybermorph.jpg"},   # v3.0: the owner's station hangar
	"hangar_kaijurai": {"folders": ["res://assets/hangars"], "match": "bay_kaijurai.", "probe": "res://assets/hangars/bay_kaijurai.jpg"},   # v3.0: the owner's station hangar
	"hangar_unity": {"folders": ["res://assets/hangars"], "match": "bay_unity.", "probe": "res://assets/hangars/bay_unity.jpg"},   # v2.7: the owner's hangar bay (front view)
	"hangar_orion": {"folders": ["res://assets/hangars"], "match": "bay_orion.", "probe": "res://assets/hangars/bay_orion.jpg"},   # v2.7: the owner's hangar bay (front view)
	"hangar_solarion": {"folders": ["res://assets/hangars"], "match": "bay_solarion.", "probe": "res://assets/hangars/bay_solarion.jpg"},   # v2.7: the owner's hangar bay (front view)
	"hangar_liberator": {"folders": ["res://assets/hangars"], "match": "bay_liberator.", "probe": "res://assets/hangars/bay_liberator.jpg"},   # v2.7: the owner's hangar bay (front view)
	"hangar_imperium": {"folders": ["res://assets/hangars"], "match": "bay_imperium.", "probe": "res://assets/hangars/bay_imperium.jpg"},   # v2.7: the owner's hangar bay (front view)
	"hangar_elyza": {"folders": ["res://assets/hangars"], "match": "bay_elyza.", "probe": "res://assets/hangars/bay_elyza.jpg"},   # v2.7: the owner's hangar bay (front view)
	"hangar_blue": {"folders": ["res://assets/hangars"], "match": "bay_blue.", "probe": "res://assets/hangars/bay_blue.jpg"},   # v2.7: the owner's hangar bay (front view)
	"hangar_scarlet": {"folders": ["res://assets/hangars"], "match": "bay_scarlet.", "probe": "res://assets/hangars/bay_scarlet.jpg"},   # v2.7: the owner's hangar bay (front view)
	"mechs": {"folders": ["res://assets/mechs"], "probe": "res://assets/mechs/tan_navy_mecha.scn"},
	# v1.9i: one pack per extra mech frame, fetched when you buy / fit its parts or meet its faction
	"mf_orange": {"folders": ["res://assets/mech_frames"], "match": "mf_orange", "probe": "res://assets/mech_frames/mf_orange.scn"},
	"mf_rifle": {"folders": ["res://assets/mech_frames"], "match": "mf_rifle", "probe": "res://assets/mech_frames/mf_rifle.scn"},
	"mf_minigun_a": {"folders": ["res://assets/mech_frames"], "match": "mf_minigun_a", "probe": "res://assets/mech_frames/mf_minigun_a.scn"},
	"mf_minigun_b": {"folders": ["res://assets/mech_frames"], "match": "mf_minigun_b", "probe": "res://assets/mech_frames/mf_minigun_b.scn"},
	"mf_teal": {"folders": ["res://assets/mech_frames"], "match": "mf_teal", "probe": "res://assets/mech_frames/mf_teal.scn"},
	"mf_white": {"folders": ["res://assets/mech_frames"], "match": "mf_white", "probe": "res://assets/mech_frames/mf_white.scn"},
	"mf_headless": {"folders": ["res://assets/mech_frames"], "match": "mf_headless", "probe": "res://assets/mech_frames/mf_headless.scn"},
	"mf_mecblu": {"folders": ["res://assets/mech_frames"], "match": "mf_mecblu", "probe": "res://assets/mech_frames/mf_mecblu.scn"},
	"mf_acmec": {"folders": ["res://assets/mech_frames"], "match": "mf_acmec", "probe": "res://assets/mech_frames/mf_acmec.scn"},
	"mf_mecbrn": {"folders": ["res://assets/mech_frames"], "match": "mf_mecbrn", "probe": "res://assets/mech_frames/mf_mecbrn.scn"},
	"planets": {"folders": ["res://assets/terrain"], "probe": "res://assets/terrain/ground_albedo.jpg"},
	"ranger": {"folders": ["res://assets/ships/player"], "match": "ranger", "probe": "res://assets/ships/player/ranger.glb"},
	"bulk": {"folders": ["res://assets/ships/player"], "match": "bulk", "probe": "res://assets/ships/player/bulk_empty.glb"},
	"hauler": {"folders": ["res://assets/ships/player"], "match": "hauler", "probe": "res://assets/ships/player/hauler.glb"},
	"lancer": {"folders": ["res://assets/ships/player"], "match": "lancer", "probe": "res://assets/ships/player/lancer.glb"},
	"enemies": {"folders": ["res://assets/enemy_pilots"], "probe": "res://assets/enemy_pilots/ax01_normal.jpg"},
	"intro": {"folders": ["res://assets/intro"], "probe": "res://assets/intro/title_movie.ogv"},
	# v1.4s: one static interface background per faction; only the one for the station you dock at is fetched
	# v2.0: her voice clips, one small pack each
	"worlds": {"folders": ["res://assets/worlds"], "probe": "res://assets/worlds/earth.jpg"},
	"structures": {"folders": ["res://assets/structures"], "probe": "res://assets/structures/jump_gate_ring.glb"},
	"ring_gate": {"folders": ["res://assets/structures"], "match": "jump_gate_ring", "probe": "res://assets/structures/jump_gate_ring.glb"},   # v1.9r: the rings on their own, fetched first
	"ring_dock": {"folders": ["res://assets/structures"], "match": "dock_arch", "probe": "res://assets/structures/dock_arch.glb"},
	"wing_guns": {"folders": ["res://assets/wing_guns"], "probe": "res://assets/wing_guns/wpn_shell_smg.glb"},   # v1.9g: the guns and pods you see on the wing mounts
	# v1.9d Station3D-Retopo v1: one pack per 3D station (its three LODs), fetched when you enter its system
	"st3d_aurelion_citadel": {"folders": ["res://assets/stations3d"], "match": "st3d_aurelion_citadel", "probe": "res://assets/stations3d/st3d_aurelion_citadel.glb"},
	"st3d_aurelion_tradehub": {"folders": ["res://assets/stations3d"], "match": "st3d_aurelion_tradehub", "probe": "res://assets/stations3d/st3d_aurelion_tradehub.glb"},
	"st3d_veranthos_senate": {"folders": ["res://assets/stations3d"], "match": "st3d_veranthos_senate", "probe": "res://assets/stations3d/st3d_veranthos_senate.glb"},
	"st3d_veranthos_fleethq": {"folders": ["res://assets/stations3d"], "match": "st3d_veranthos_fleethq", "probe": "res://assets/stations3d/st3d_veranthos_fleethq.glb"},
	"st3d_voidtex_crosswind": {"folders": ["res://assets/stations3d"], "match": "st3d_voidtex_crosswind", "probe": "res://assets/stations3d/st3d_voidtex_crosswind.glb"},
	"st3d_beta7_pathfinder": {"folders": ["res://assets/stations3d"], "match": "st3d_beta7_pathfinder", "probe": "res://assets/stations3d/st3d_beta7_pathfinder.glb"},
	"st3d_perimeter_picket": {"folders": ["res://assets/stations3d"], "match": "st3d_perimeter_picket", "probe": "res://assets/stations3d/st3d_perimeter_picket.glb"},
	"st3d_sigma19_deepcut": {"folders": ["res://assets/stations3d"], "match": "st3d_sigma19_deepcut", "probe": "res://assets/stations3d/st3d_sigma19_deepcut.glb"},
	"st3d_omega_emporium": {"folders": ["res://assets/stations3d"], "match": "st3d_omega_emporium", "probe": "res://assets/stations3d/st3d_omega_emporium.glb"},
	"st3d_foggiest_greywhistle": {"folders": ["res://assets/stations3d"], "match": "st3d_foggiest_greywhistle", "probe": "res://assets/stations3d/st3d_foggiest_greywhistle.glb"},
	"st3d_radiant_dawnchoir": {"folders": ["res://assets/stations3d"], "match": "st3d_radiant_dawnchoir", "probe": "res://assets/stations3d/st3d_radiant_dawnchoir.glb"},
	"st3d_savagers_asteroid": {"folders": ["res://assets/stations3d"], "match": "st3d_savagers_asteroid", "probe": "res://assets/stations3d/st3d_savagers_asteroid.glb"},
	"st3d_cyber_hexdominator": {"folders": ["res://assets/stations3d"], "match": "st3d_cyber_hexdominator", "probe": "res://assets/stations3d/st3d_cyber_hexdominator.glb"},
	"st3d_cyber_shardstorm": {"folders": ["res://assets/stations3d"], "match": "st3d_cyber_shardstorm", "probe": "res://assets/stations3d/st3d_cyber_shardstorm.glb"},
	# v1.9q RETOPO set: one pack per station (its file keeps the delivered name), fetched when you enter its system
	"HL_Station_Arctides_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Arctides_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Arctides_Capital_retopo.glb"},
	"HL_Station_Arctides_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Arctides_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Arctides_Military_retopo.glb"},
	"HL_Station_Covenant_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Covenant_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Covenant_Capital_retopo.glb"},
	"HL_Station_Covenant_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Covenant_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Covenant_Military_retopo.glb"},
	"HL_Station_Covenant_Trade_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Covenant_Trade_retopo", "probe": "res://assets/stations3d/HL_Station_Covenant_Trade_retopo.glb"},
	"HL_Station_Cybermorphs_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Cybermorphs_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Cybermorphs_Capital_retopo.glb"},
	"HL_Station_Cybermorphs_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Cybermorphs_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Cybermorphs_Military_retopo.glb"},
	"HL_Station_Elyza_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Elyza_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Elyza_Capital_retopo.glb"},
	"HL_Station_Elyza_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Elyza_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Elyza_Military_retopo.glb"},
	"HL_Station_Elyza_Trade_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Elyza_Trade_retopo", "probe": "res://assets/stations3d/HL_Station_Elyza_Trade_retopo.glb"},
	"HL_Station_Gadversee_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Gadversee_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Gadversee_Capital_retopo.glb"},
	"HL_Station_Gadversee_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Gadversee_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Gadversee_Military_retopo.glb"},
	"HL_Station_Imperium_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Imperium_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Imperium_Capital_retopo.glb"},
	"HL_Station_Imperium_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Imperium_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Imperium_Military_retopo.glb"},
	"HL_Station_Imperium_Trade_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Imperium_Trade_retopo", "probe": "res://assets/stations3d/HL_Station_Imperium_Trade_retopo.glb"},
	"HL_Station_Kaijurai_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Kaijurai_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Kaijurai_Capital_retopo.glb"},
	"HL_Station_Kaijurai_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Kaijurai_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Kaijurai_Military_retopo.glb"},
	"HL_Station_Liberator_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Liberator_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Liberator_Capital_retopo.glb"},
	"HL_Station_Liberator_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Liberator_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Liberator_Military_retopo.glb"},
	"HL_Station_Orion_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Orion_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Orion_Capital_retopo.glb"},
	"HL_Station_Orion_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Orion_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Orion_Military_retopo.glb"},
	"HL_Station_Phenom_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Phenom_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Phenom_Capital_retopo.glb"},
	"HL_Station_Phenom_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Phenom_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Phenom_Military_retopo.glb"},
	"HL_Station_Savagers_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Savagers_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Savagers_Capital_retopo.glb"},
	"HL_Station_Savagers_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Savagers_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Savagers_Military_retopo.glb"},
	"HL_Station_Solarion_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Solarion_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Solarion_Capital_retopo.glb"},
	"HL_Station_Solarion_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Solarion_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Solarion_Military_retopo.glb"},
	"HL_Station_Solarion_Outpost_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Solarion_Outpost_retopo", "probe": "res://assets/stations3d/HL_Station_Solarion_Outpost_retopo.glb"},
	"HL_Station_Solarion_Trade_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Solarion_Trade_retopo", "probe": "res://assets/stations3d/HL_Station_Solarion_Trade_retopo.glb"},
	"HL_Station_Solrath_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Solrath_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Solrath_Capital_retopo.glb"},
	"HL_Station_Solrath_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Solrath_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Solrath_Military_retopo.glb"},
	"HL_Station_Unclaimed_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Unclaimed_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Unclaimed_Capital_retopo.glb"},
	"HL_Station_Unclaimed_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Unclaimed_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Unclaimed_Military_retopo.glb"},
	"HL_Station_Unity_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Unity_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Unity_Capital_retopo.glb"},
	"HL_Station_Unity_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Unity_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Unity_Military_retopo.glb"},
	"HL_Station_Unity_Trade_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Unity_Trade_retopo", "probe": "res://assets/stations3d/HL_Station_Unity_Trade_retopo.glb"},
	"HL_Station_Unknown_Capital_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Unknown_Capital_retopo", "probe": "res://assets/stations3d/HL_Station_Unknown_Capital_retopo.glb"},
	"HL_Station_Unknown_Military_retopo": {"folders": ["res://assets/stations3d"], "match": "HL_Station_Unknown_Military_retopo", "probe": "res://assets/stations3d/HL_Station_Unknown_Military_retopo.glb"},
	# v1.9q: one pack per faction's planetary buildings (Command Center + Hangar), fetched when you land on its homeworld
	"bld_covenant": {"folders": ["res://assets/buildings3d"], "match": "HL_Covenant_", "probe": "res://assets/buildings3d/HL_Covenant_CommandCenter_v01_retopo.glb"},
	"bld_elyza": {"folders": ["res://assets/buildings3d"], "match": "HL_Elyza_", "probe": "res://assets/buildings3d/HL_Elyza_CommandCenter_v01_retopo.glb"},
	"bld_imperium": {"folders": ["res://assets/buildings3d"], "match": "HL_Imperium_", "probe": "res://assets/buildings3d/HL_Imperium_CommandCenter_v01_retopo.glb"},
	"bld_liberator": {"folders": ["res://assets/buildings3d"], "match": "HL_Liberator_", "probe": "res://assets/buildings3d/HL_Liberator_CommandCenter_v01_retopo.glb"},
	"bld_orion": {"folders": ["res://assets/buildings3d"], "match": "HL_Orion_", "probe": "res://assets/buildings3d/HL_Orion_CommandCenter_v01_retopo.glb"},
	"bld_savagers": {"folders": ["res://assets/buildings3d"], "match": "HL_Savagers_", "probe": "res://assets/buildings3d/HL_Savagers_CommandCenter_v01_retopo.glb"},
	"bld_solarion": {"folders": ["res://assets/buildings3d"], "match": "HL_Solarion_", "probe": "res://assets/buildings3d/HL_Solarion_CommandCenter_v01_retopo.glb"},
	"bld_solrath": {"folders": ["res://assets/buildings3d"], "match": "HL_Solrath_", "probe": "res://assets/buildings3d/HL_Solrath_CommandCenter_v01_retopo.glb"},
	"bld_unity": {"folders": ["res://assets/buildings3d"], "match": "HL_Unity_", "probe": "res://assets/buildings3d/HL_Unity_CommandCenter_v01_retopo.glb"},
	"sky": {"folders": ["res://assets/sky"], "probe": "res://assets/sky/solara.jpg"},
	# music: one pack per track, fetched the first time that track is wanted (scripts/music.gd)
	"mus_bloodwater_1": {"folders": ["res://assets/music"], "match": "bloodwater_1.", "probe": "res://assets/music/bloodwater_1.ogg"},
	"mus_bloodwater_2": {"folders": ["res://assets/music"], "match": "bloodwater_2.", "probe": "res://assets/music/bloodwater_2.ogg"},
	"mus_interstellar_1": {"folders": ["res://assets/music"], "match": "interstellar_1.", "probe": "res://assets/music/interstellar_1.ogg"},
	"mus_interstellar_2": {"folders": ["res://assets/music"], "match": "interstellar_2.", "probe": "res://assets/music/interstellar_2.ogg"},
	"mus_puzzle_1": {"folders": ["res://assets/music"], "match": "puzzle_1.", "probe": "res://assets/music/puzzle_1.ogg"},
	"mus_rift_1": {"folders": ["res://assets/music"], "match": "rift_1.", "probe": "res://assets/music/rift_1.ogg"},
	"mus_rift_2": {"folders": ["res://assets/music"], "match": "rift_2.", "probe": "res://assets/music/rift_2.ogg"},
	"mus_rift_3": {"folders": ["res://assets/music"], "match": "rift_3.", "probe": "res://assets/music/rift_3.ogg"},
	"mus_rift_4": {"folders": ["res://assets/music"], "match": "rift_4.", "probe": "res://assets/music/rift_4.ogg"},
	"mus_ruins_1": {"folders": ["res://assets/music"], "match": "ruins_1.", "probe": "res://assets/music/ruins_1.ogg"},
	"mus_ruins_2": {"folders": ["res://assets/music"], "match": "ruins_2.", "probe": "res://assets/music/ruins_2.ogg"},
	"mus_ruins_3": {"folders": ["res://assets/music"], "match": "ruins_3.", "probe": "res://assets/music/ruins_3.ogg"},
	"mus_ruins_4": {"folders": ["res://assets/music"], "match": "ruins_4.", "probe": "res://assets/music/ruins_4.ogg"},
	"mus_spaceways_1": {"folders": ["res://assets/music"], "match": "spaceways_1.", "probe": "res://assets/music/spaceways_1.ogg"},
	"mus_spaceways_2": {"folders": ["res://assets/music"], "match": "spaceways_2.", "probe": "res://assets/music/spaceways_2.ogg"},
	"mus_spaceways_3": {"folders": ["res://assets/music"], "match": "spaceways_3.", "probe": "res://assets/music/spaceways_3.ogg"},
	"mus_spaceways_4": {"folders": ["res://assets/music"], "match": "spaceways_4.", "probe": "res://assets/music/spaceways_4.ogg"},
	"mus_stars_1": {"folders": ["res://assets/music"], "match": "stars_1.", "probe": "res://assets/music/stars_1.ogg"},
	"mus_stars_2": {"folders": ["res://assets/music"], "match": "stars_2.", "probe": "res://assets/music/stars_2.ogg"},
	"mus_theme_1": {"folders": ["res://assets/music"], "match": "theme_1.", "probe": "res://assets/music/theme_1.ogg"},
	"mus_veranthos_1": {"folders": ["res://assets/music"], "match": "veranthos_1.", "probe": "res://assets/music/veranthos_1.ogg"},
	"mus_veranthos_2": {"folders": ["res://assets/music"], "match": "veranthos_2.", "probe": "res://assets/music/veranthos_2.ogg"},
	"mus_veranthos_3": {"folders": ["res://assets/music"], "match": "veranthos_3.", "probe": "res://assets/music/veranthos_3.ogg"},
	"mus_veranthos_4": {"folders": ["res://assets/music"], "match": "veranthos_4.", "probe": "res://assets/music/veranthos_4.ogg"},
	"mus_void_1": {"folders": ["res://assets/music"], "match": "void_1.", "probe": "res://assets/music/void_1.ogg"},
	"mus_void_2": {"folders": ["res://assets/music"], "match": "void_2.", "probe": "res://assets/music/void_2.ogg"},
	"mus_void_3": {"folders": ["res://assets/music"], "match": "void_3.", "probe": "res://assets/music/void_3.ogg"},
	"mus_void_4": {"folders": ["res://assets/music"], "match": "void_4.", "probe": "res://assets/music/void_4.ogg"},
	# -- generated sky packs (tools/galaxy/build_game_data.py) --
	"sky_beta_7": {"folders": ["res://assets/skies"], "match": "beta_7.", "probe": "res://assets/skies/beta_7.jpg"},
	"sky_void_system": {"folders": ["res://assets/skies"], "match": "void_system.", "probe": "res://assets/skies/void_system.jpg"},
	"sky_keldrix": {"folders": ["res://assets/skies"], "match": "keldrix.", "probe": "res://assets/skies/keldrix.jpg"},
	"sky_kronos": {"folders": ["res://assets/skies"], "match": "kronos.", "probe": "res://assets/skies/kronos.jpg"},
	"sky_void_1": {"folders": ["res://assets/skies"], "match": "void_1.", "probe": "res://assets/skies/void_1.jpg"},
	"sky_nebulax": {"folders": ["res://assets/skies"], "match": "nebulax.", "probe": "res://assets/skies/nebulax.jpg"},
	"sky_radiant": {"folders": ["res://assets/skies"], "match": "radiant.", "probe": "res://assets/skies/radiant.jpg"},
	"sky_void_6": {"folders": ["res://assets/skies"], "match": "void_6.", "probe": "res://assets/skies/void_6.jpg"},
	"sky_selenvar": {"folders": ["res://assets/skies"], "match": "selenvar.", "probe": "res://assets/skies/selenvar.jpg"},
	"sky_velanthos": {"folders": ["res://assets/skies"], "match": "velanthos.", "probe": "res://assets/skies/velanthos.jpg"},
	"sky_aurentum": {"folders": ["res://assets/skies"], "match": "aurentum.", "probe": "res://assets/skies/aurentum.jpg"},
	"sky_techanis": {"folders": ["res://assets/skies"], "match": "techanis.", "probe": "res://assets/skies/techanis.jpg"},
	"sky_kellova": {"folders": ["res://assets/skies"], "match": "kellova.", "probe": "res://assets/skies/kellova.jpg"},
	"sky_farreach_outpost": {"folders": ["res://assets/skies"], "match": "farreach_outpost.", "probe": "res://assets/skies/farreach_outpost.jpg"},
	"sky_crystara": {"folders": ["res://assets/skies"], "match": "crystara.", "probe": "res://assets/skies/crystara.jpg"},
	"sky_federis": {"folders": ["res://assets/skies"], "match": "federis.", "probe": "res://assets/skies/federis.jpg"},
	"sky_nexarion": {"folders": ["res://assets/skies"], "match": "nexarion.", "probe": "res://assets/skies/nexarion.jpg"},
	"sky_perimeter": {"folders": ["res://assets/skies"], "match": "perimeter.", "probe": "res://assets/skies/perimeter.jpg"},
	"sky_zillance_major": {"folders": ["res://assets/skies"], "match": "zillance_major.", "probe": "res://assets/skies/zillance_major.jpg"},
	"sky_aurelion": {"folders": ["res://assets/skies"], "match": "aurelion.", "probe": "res://assets/skies/aurelion.jpg"},
	"sky_veranthos": {"folders": ["res://assets/skies"], "match": "veranthos.", "probe": "res://assets/skies/veranthos.jpg"},
	"sky_synthari_capital": {"folders": ["res://assets/skies"], "match": "synthari_capital.", "probe": "res://assets/skies/synthari_capital.jpg"},
	"sky_crossma_major": {"folders": ["res://assets/skies"], "match": "crossma_major.", "probe": "res://assets/skies/crossma_major.jpg"},
	"sky_cynthara": {"folders": ["res://assets/skies"], "match": "cynthara.", "probe": "res://assets/skies/cynthara.jpg"},
	"sky_kiral": {"folders": ["res://assets/skies"], "match": "kiral.", "probe": "res://assets/skies/kiral.jpg"},
	"sky_rimgate": {"folders": ["res://assets/skies"], "match": "rimgate.", "probe": "res://assets/skies/rimgate.jpg"},
	"sky_vexara": {"folders": ["res://assets/skies"], "match": "vexara.", "probe": "res://assets/skies/vexara.jpg"},
	"sky_vorreth": {"folders": ["res://assets/skies"], "match": "vorreth.", "probe": "res://assets/skies/vorreth.jpg"},
	"sky_nullpoint": {"folders": ["res://assets/skies"], "match": "nullpoint.", "probe": "res://assets/skies/nullpoint.jpg"},
	"sky_exodus_point": {"folders": ["res://assets/skies"], "match": "exodus_point.", "probe": "res://assets/skies/exodus_point.jpg"},
	"sky_vantara": {"folders": ["res://assets/skies"], "match": "vantara.", "probe": "res://assets/skies/vantara.jpg"},
	"sky_heart": {"folders": ["res://assets/skies"], "match": "heart.", "probe": "res://assets/skies/heart.jpg"},
	"sky_malachar": {"folders": ["res://assets/skies"], "match": "malachar.", "probe": "res://assets/skies/malachar.jpg"},
	"sky_shadenvex": {"folders": ["res://assets/skies"], "match": "shadenvex.", "probe": "res://assets/skies/shadenvex.jpg"},
	"sky_void_3": {"folders": ["res://assets/skies"], "match": "void_3.", "probe": "res://assets/skies/void_3.jpg"},
	"sky_republic_major": {"folders": ["res://assets/skies"], "match": "republic_major.", "probe": "res://assets/skies/republic_major.jpg"},
	"sky_ogden": {"folders": ["res://assets/skies"], "match": "ogden.", "probe": "res://assets/skies/ogden.jpg"},
	"sky_foggiest": {"folders": ["res://assets/skies"], "match": "foggiest.", "probe": "res://assets/skies/foggiest.jpg"},
	"sky_empire_major": {"folders": ["res://assets/skies"], "match": "empire_major.", "probe": "res://assets/skies/empire_major.jpg"},
	"sky_obsidrath": {"folders": ["res://assets/skies"], "match": "obsidrath.", "probe": "res://assets/skies/obsidrath.jpg"},
	"sky_cybernet": {"folders": ["res://assets/skies"], "match": "cybernet.", "probe": "res://assets/skies/cybernet.jpg"},
	"sky_plundros": {"folders": ["res://assets/skies"], "match": "plundros.", "probe": "res://assets/skies/plundros.jpg"},
	"sky_raptian_major": {"folders": ["res://assets/skies"], "match": "raptian_major.", "probe": "res://assets/skies/raptian_major.jpg"},
	"sky_dreadholm": {"folders": ["res://assets/skies"], "match": "dreadholm.", "probe": "res://assets/skies/dreadholm.jpg"},
	"sky_sepheron": {"folders": ["res://assets/skies"], "match": "sepheron.", "probe": "res://assets/skies/sepheron.jpg"},
	"sky_valdris": {"folders": ["res://assets/skies"], "match": "valdris.", "probe": "res://assets/skies/valdris.jpg"},
	"sky_noctyra": {"folders": ["res://assets/skies"], "match": "noctyra.", "probe": "res://assets/skies/noctyra.jpg"},
	"sky_scavaris": {"folders": ["res://assets/skies"], "match": "scavaris.", "probe": "res://assets/skies/scavaris.jpg"},
	"sky_korrath": {"folders": ["res://assets/skies"], "match": "korrath.", "probe": "res://assets/skies/korrath.jpg"},
	"sky_battlespire": {"folders": ["res://assets/skies"], "match": "battlespire.", "probe": "res://assets/skies/battlespire.jpg"},
	"sky_void_4": {"folders": ["res://assets/skies"], "match": "void_4.", "probe": "res://assets/skies/void_4.jpg"},
	"sky_shroud": {"folders": ["res://assets/skies"], "match": "shroud.", "probe": "res://assets/skies/shroud.jpg"},
	"sky_derelicta": {"folders": ["res://assets/skies"], "match": "derelicta.", "probe": "res://assets/skies/derelicta.jpg"},
	"sky_ravage_major": {"folders": ["res://assets/skies"], "match": "ravage_major.", "probe": "res://assets/skies/ravage_major.jpg"},
	"sky_ironvast": {"folders": ["res://assets/skies"], "match": "ironvast.", "probe": "res://assets/skies/ironvast.jpg"},
	"sky_sanctum_major": {"folders": ["res://assets/skies"], "match": "sanctum_major.", "probe": "res://assets/skies/sanctum_major.jpg"},
	"sky_sigma_19": {"folders": ["res://assets/skies"], "match": "sigma_19.", "probe": "res://assets/skies/sigma_19.jpg"},
	"sky_omega": {"folders": ["res://assets/skies"], "match": "omega.", "probe": "res://assets/skies/omega.jpg"},
	"sky_shadow": {"folders": ["res://assets/skies"], "match": "shadow.", "probe": "res://assets/skies/shadow.jpg"},
	"sky_voidtex": {"folders": ["res://assets/skies"], "match": "voidtex.", "probe": "res://assets/skies/voidtex.jpg"},
	"sky_void_5": {"folders": ["res://assets/skies"], "match": "void_5.", "probe": "res://assets/skies/void_5.jpg"},
	"sky_vortegan": {"folders": ["res://assets/skies"], "match": "vortegan.", "probe": "res://assets/skies/vortegan.jpg"},
	"sky_omicron_major": {"folders": ["res://assets/skies"], "match": "omicron_major.", "probe": "res://assets/skies/omicron_major.jpg"},
	"sky_genesis": {"folders": ["res://assets/skies"], "match": "genesis.", "probe": "res://assets/skies/genesis.jpg"},
	"sky_void_2": {"folders": ["res://assets/skies"], "match": "void_2.", "probe": "res://assets/skies/void_2.jpg"},
	# -- end generated sky packs --
	# v1.8z: the cloned radio voices, one pack per voice (tools/voices/build_voice_lines.py)
	"voice_a1": {"folders": ["res://assets/voices/v_a1"], "probe": "res://assets/voices/v_a1/arm_s_gone.ogg"},
	"voice_a2": {"folders": ["res://assets/voices/v_a2"], "probe": "res://assets/voices/v_a2/arm_s_gone.ogg"},
	"voice_f1": {"folders": ["res://assets/voices/v_f1"], "probe": "res://assets/voices/v_f1/arm_s_gone.ogg"},
	"voice_f2": {"folders": ["res://assets/voices/v_f2"], "probe": "res://assets/voices/v_f2/ah_yeah_need_credits_dock_at_a_station_and_grab_a_job.ogg"},
	"voice_f3": {"folders": ["res://assets/voices/v_f3"], "probe": "res://assets/voices/v_f3/arm_s_gone.ogg"},
	"voice_f4": {"folders": ["res://assets/voices/v_f4"], "probe": "res://assets/voices/v_f4/arm_s_gone.ogg"},
	"voice_m1": {"folders": ["res://assets/voices/v_m1"], "probe": "res://assets/voices/v_m1/again_you_are_making_this_easy_to_trace.ogg"},
	"voice_m2": {"folders": ["res://assets/voices/v_m2"], "probe": "res://assets/voices/v_m2/arm_s_gone.ogg"},
	"voice_m3": {"folders": ["res://assets/voices/v_m3"], "probe": "res://assets/voices/v_m3/any_time_you_keep_them_off_me_i_keep_you_in_credits.ogg"},
	"voice_m4": {"folders": ["res://assets/voices/v_m4"], "probe": "res://assets/voices/v_m4/300_credits_that_buys_a_quiet_hour_not_forgiveness.ogg"},
	"voice_mask": {"folders": ["res://assets/voices/v_mask"], "probe": "res://assets/voices/v_mask/alliance_trooper_unity_patrol_you_are_clear_pilot.ogg"},
	"voice_r1": {"folders": ["res://assets/voices/v_r1"], "probe": "res://assets/voices/v_r1/arm_s_gone.ogg"},
	"cockpit": {"folders": ["res://assets/cockpit"], "probe": "res://assets/cockpit/cockpit_b.png"},
}

var state := {}   # name -> "ready" | "loading" | "failed"
var bytes := {}   # name -> downloaded size
var ms := {}      # name -> download + mount time
var _http := {}

func is_ready(name: String) -> bool:
	if state.get(name, "") == "ready": return true
	if ResourceLoader.exists(PACKS[name]["probe"]):
		state[name] = "ready"
		return true
	return false

## Start fetching a pack in the background (no-op if it is ready or already coming).
func request(name: String) -> void:
	if is_ready(name) or state.get(name, "") == "loading": return
	if not OS.has_feature("web"):
		state[name] = "failed"   # desktop builds carry everything; nothing to download
		return
	state[name] = "loading"
	var base: String = JavaScriptBridge.eval("location.href.split('?')[0].replace(/[^/]*$/, '')", true)
	var h := HTTPRequest.new()
	h.download_file = "user://pack_%s.pck" % name
	h.use_threads = false
	h.accept_gzip = false   # the browser already un-gzips; letting Godot try again fails
	h.timeout = 120.0
	add_child(h)
	_http[name] = h
	var t0 := Time.get_ticks_msec()
	h.request_completed.connect(func(result: int, code: int, _hd, _body):
		h.queue_free()
		_http.erase(name)
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			state[name] = "failed"
			printerr("[packs] %s failed (result %d, HTTP %d)" % [name, result, code])
			pack_ready.emit(name)
			return
		bytes[name] = FileAccess.get_file_as_bytes(h.download_file).size()
		var ok := ProjectSettings.load_resource_pack(h.download_file, true)
		state[name] = "ready" if ok and ResourceLoader.exists(PACKS[name]["probe"]) else "failed"
		ms[name] = Time.get_ticks_msec() - t0
		print("[packs] %s %s: %.2f MB in %d ms" % [name, state[name], bytes[name] / 1e6, ms[name]])
		pack_ready.emit(name))
	var err := h.request(base + "packs/%s.pck" % name)
	if err != OK:
		state[name] = "failed"
		pack_ready.emit(name)

## v1.8t: fetch these in order, Data.PACK_PARALLEL at a time (a pack asked for directly with request() still starts at once).
var _queue: Array = []
func queue(names: Array) -> void:
	for n in names:
		if not is_ready(n) and not (n in _queue): _queue.append(n)
	_pump()

func _pump() -> void:
	while not _queue.is_empty():
		var busy := 0
		for n in state:
			if state[n] == "loading": busy += 1
		if busy >= Data.PACK_PARALLEL: return
		var nx: String = _queue.pop_front()
		if is_ready(nx) or state.get(nx, "") == "loading": continue
		if not OS.has_feature("web"): continue
		request(nx)

func _ready() -> void:
	pack_ready.connect(func(_n): _pump())

## Wait (up to `timeout` s) for a pack, requesting it if needed. Returns true when it is mounted.
func wait(name: String, timeout := 60.0) -> bool:
	request(name)
	var t := 0.0
	while state.get(name, "") == "loading" and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	return is_ready(name)

## How far a pack's download has got (0..1), for loading captions.
func progress(name: String) -> float:
	if is_ready(name): return 1.0
	var h: HTTPRequest = _http.get(name)
	if h == null or h.get_body_size() <= 0: return 0.0
	return clampf(float(h.get_downloaded_bytes()) / h.get_body_size(), 0.0, 1.0)
