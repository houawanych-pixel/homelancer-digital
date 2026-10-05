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
	"mechs": {"folders": ["res://assets/mechs"], "probe": "res://assets/mechs/tan_navy_mecha.glb"},
	"planets": {"folders": ["res://assets/terrain"], "probe": "res://assets/terrain/ground_albedo.jpg"},
	"ranger": {"folders": ["res://assets/ships/player"], "match": "ranger", "probe": "res://assets/ships/player/ranger.glb"},
	"bulk": {"folders": ["res://assets/ships/player"], "match": "bulk", "probe": "res://assets/ships/player/bulk_empty.glb"},
	"hauler": {"folders": ["res://assets/ships/player"], "match": "hauler", "probe": "res://assets/ships/player/hauler.glb"},
	"lancer": {"folders": ["res://assets/ships/player"], "match": "lancer", "probe": "res://assets/ships/player/lancer.glb"},
	"enemies": {"folders": ["res://assets/enemy_pilots"], "probe": "res://assets/enemy_pilots/ax01_normal.jpg"},
	"city": {"folders": ["res://assets/city"], "probe": "res://assets/city/capital_normal.png"},
	"intro": {"folders": ["res://assets/intro"], "probe": "res://assets/intro/title_collage.jpg"},
	"rooms": {"folders": ["res://assets/rooms"], "probe": "res://assets/rooms/main_hub.jpg"},
	"rooms_aurelion": {"folders": ["res://assets/rooms_aurelion"], "probe": "res://assets/rooms_aurelion/au_main_hub.jpg"},   # v1.4l: Aurelion Citadel hub
	"npc": {"folders": ["res://assets/npc"], "probe": "res://assets/npc/marshal.glb"},   # v1.4m: people in station rooms
	"worlds": {"folders": ["res://assets/worlds"], "probe": "res://assets/worlds/earth.jpg"},
	"structures": {"folders": ["res://assets/structures"], "probe": "res://assets/structures/jump_gate_ring.glb"},
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
