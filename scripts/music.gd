extends Node
## Music (autoload "Music"). The owner's 28 tracks, used by MOOD, not by place (see docs/DESIGN.md §19 and the Drive
## doc "HOMELANCER — Music Guide"). Each mood has several takes; one is picked at random, and when it ends another
## take of the same mood follows. Changing mood cross-fades. Every track is its own small content pack
## ("mus_<id>", assets/music/<id>.ogg) fetched the first time it is wanted, so music adds nothing to the first load.

## mood -> takes. "ruins" (spooky exploration / horror missions) and "puzzle" are held: nothing asks for them yet.
const MOODS := {
	"intro": ["theme_1"],                                   # Homelancer game: the main theme
	"space": ["spaceways_1", "spaceways_2", "spaceways_3", "spaceways_4", "veranthos_1", "veranthos_2", "veranthos_3", "veranthos_4"],   # relaxed travel / drifting
	"explore": ["interstellar_1", "interstellar_2"],        # exploration, the search
	"battle": ["rift_1", "rift_2", "rift_3", "rift_4"],     # Rift Gate Collapse: battles and chases
	"dark": ["bloodwater_1", "bloodwater_2"],               # Bloodwater Corridor: dark faction territory
	"void": ["void_1", "void_2", "void_3", "void_4"],       # Void Drift: unknown areas, lost, alone
	"heart": ["stars_1", "stars_2"],                        # Stars Remember Us: heart moments, calm after a victory
	"ruins": ["ruins_1", "ruins_2", "ruins_3", "ruins_4"],  # Architect Ruins: HELD for horror / ruins missions
	"puzzle": ["puzzle_1"],                                 # Homelancer game 1: HELD for puzzles
}
## v1.4l (owner): in flight the music follows whose space you are in. One track per faction; it keeps playing until
## you cross into another faction's space. "Stars Remember Us" (the love song) is HELD for later, like the ruins set.
const FACTION_TRACK := {
	"Unity": "veranthos_1", "Elyza": "interstellar_1", "Solarion": "spaceways_1", "Liberator": "spaceways_2",
	"Savagers": "spaceways_3", "Neutral": "spaceways_4", "Orion": "veranthos_2", "Covenant": "interstellar_2",
	"Imperium": "bloodwater_1", "Enemy": "bloodwater_2", "Hidden": "void_1", "Void": "void_2", "Heart": "veranthos_3",
}
const HELD := ["stars_1", "stars_2", "ruins_1", "ruins_2", "ruins_3", "ruins_4", "puzzle_1"]
static func faction_mood(faction: String) -> String: return "f:" + (faction if FACTION_TRACK.has(faction) else "Neutral")
static func takes(m: String) -> Array:
	if m.begins_with("f:"): return [FACTION_TRACK[m.substr(2)]]
	return MOODS.get(m, [])
const VOLUME_DB := -9.0
const FADE := 2.2

var mood := ""          # what is wanted now ("" = silence)
var track := ""         # the take that is playing or on its way
var muted := false
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _last := {}         # mood -> last take, so the same one is not picked twice running
var _rng := RandomNumberGenerator.new()

static func path(id: String) -> String: return "res://assets/music/%s.ogg" % id
static func pack(id: String) -> String: return "mus_" + id

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_a = _player()
	_b = _player()
	Packs.pack_ready.connect(_on_pack)

func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = -60.0
	add_child(p)
	p.finished.connect(func():
		if p == _a and mood != "": _start(_pick(mood)))   # the take ended: another take of the same mood
	return p

## Ask for a mood. The same mood again changes nothing; a new mood picks a take and cross-fades to it.
func want(m: String) -> void:
	if m == mood: return
	mood = m
	if m == "" or takes(m).is_empty():
		track = ""
		_fade(_a, -60.0, true)
		return
	_start(_pick(m))

func _pick(m: String) -> String:
	var tk: Array = takes(m)
	var id: String = tk[_rng.randi() % tk.size()]
	if tk.size() > 1 and id == _last.get(m, ""): id = tk[(tk.find(id) + 1) % tk.size()]
	_last[m] = id
	return id

func _start(id: String) -> void:
	track = id
	if Packs.is_ready(pack(id)): _play(id)
	else: Packs.request(pack(id))    # keeps playing what it has until the new track arrives

func _on_pack(pk: String) -> void:
	if track != "" and pk == pack(track) and Packs.is_ready(pk): _play(track)

func _play(id: String) -> void:
	var st: AudioStream = load(path(id))
	if st == null: return
	if st is AudioStreamOggVorbis: (st as AudioStreamOggVorbis).loop = false
	var old := _a
	_a = _b
	_b = old
	_fade(_b, -60.0, true)
	_a.stream = st
	_a.volume_db = -60.0
	_a.play()
	_fade(_a, -60.0 if muted else VOLUME_DB, false)

func _fade(p: AudioStreamPlayer, to_db: float, stop: bool) -> void:
	if p.has_meta("tw") and is_instance_valid(p.get_meta("tw")): (p.get_meta("tw") as Tween).kill()
	var tw := create_tween()
	p.set_meta("tw", tw)
	tw.tween_property(p, "volume_db", to_db, FADE)
	if stop: tw.tween_callback(p.stop)

func set_muted(m: bool) -> void:
	muted = m
	if _a.playing: _fade(_a, -60.0 if m else VOLUME_DB, false)

func is_playing() -> bool: return _a.playing
