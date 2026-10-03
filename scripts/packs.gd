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
	"lancer": {"folders": ["res://assets/ships/player"], "match": "lancer", "probe": "res://assets/ships/player/lancer.glb"},
	"enemies": {"folders": ["res://assets/enemy_pilots"], "probe": "res://assets/enemy_pilots/ax01_normal.jpg"},
	"city": {"folders": ["res://assets/city"], "probe": "res://assets/city/capital_normal.png"},
	"intro": {"folders": ["res://assets/intro"], "probe": "res://assets/intro/title_collage.jpg"},
	"rooms": {"folders": ["res://assets/rooms"], "probe": "res://assets/rooms/main_hub.jpg"},
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
