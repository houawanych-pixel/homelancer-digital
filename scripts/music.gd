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
	"battle": ["rift_1", "rift_2"],                         # Rift Gate Collapse: battles and chases (v1.9k: ordinary fights)
	"epic": ["rift_3", "rift_4"],                           # v1.9k (owner): the big ones: a boss mech, a bounty, a high-rank pilot
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
## v1.9k (owner: I hear the same track all the time): each faction has a few tracks, and each SYSTEM starts on its
## own one of them (picked from the system's id, so a system always sounds the same), then the others follow.
const FACTION_POOL := {
	"Unity": ["veranthos_1", "veranthos_4", "spaceways_1"], "Elyza": ["interstellar_1", "interstellar_2", "veranthos_2"],
	"Solarion": ["spaceways_1", "veranthos_4", "spaceways_4"], "Liberator": ["spaceways_2", "spaceways_1", "veranthos_1"],
	"Savagers": ["spaceways_3", "bloodwater_2", "void_3"], "Neutral": ["spaceways_4", "spaceways_2", "veranthos_2"],
	"Orion": ["veranthos_2", "interstellar_1", "spaceways_3"], "Covenant": ["interstellar_2", "veranthos_3", "veranthos_1"],
	"Imperium": ["bloodwater_1", "bloodwater_2", "spaceways_3"], "Enemy": ["bloodwater_2", "void_3", "bloodwater_1"],
	"Hidden": ["void_1", "void_4", "interstellar_2"], "Void": ["void_2", "void_3", "void_4"], "Heart": ["veranthos_3", "veranthos_1", "interstellar_1"],
}
static func faction_mood(faction: String, sys := "") -> String:
	var f := faction if FACTION_POOL.has(faction) else "Neutral"
	return "f:" + f + ((":" + sys) if sys != "" else "")
## A faction mood's takes, starting with the one this system opens on.
static func takes(m: String) -> Array:
	if m.begins_with("f:"):
		var parts := m.substr(2).split(":")
		var pool: Array = FACTION_POOL.get(parts[0], FACTION_POOL["Neutral"])
		if parts.size() < 2 or parts[1] == "": return pool.duplicate()
		var i: int = int(hash(parts[1]) % pool.size())
		return pool.slice(i) + pool.slice(0, i)
	return MOODS.get(m, [])
## v1.9k: the fight music by what you are up against (space.engaged_tier: 2 = epic, 1 = ordinary).
static func battle_mood(tier: int) -> String: return "epic" if tier >= 2 else "battle"
static func is_battle(m: String) -> bool: return m == "battle" or m == "epic"
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

## v1.8u (owner: the music is choppy): in the browser the music is played by the BROWSER's own player (an <audio>
## element fed the plain .ogg from "music/<id>.ogg" next to the game), not mixed inside the game. The game runs on one
## thread there, so music mixed in the game stutters whenever a frame is slow, and unpacked whole it took 80 MB a
## track. The browser streams the file on its own thread: smooth, and a few MB. If the browser cannot play the file
## (js.ok turns false) the game falls back to its own streamed player.
var web := false
var _poll := 0.0
const WEB_JS := """
window.__hlm = { a: null, ok: true, ended: false, want: null,
  base: location.href.split('?')[0].replace(/[^/]*$/, ''),
  fade: function(el, to, stop) { if (el._t) clearInterval(el._t); var from = el.volume, t0 = performance.now();
    el._t = setInterval(function() { var k = Math.min(1, (performance.now() - t0) / 2200); el.volume = Math.max(0, Math.min(1, from + (to - from) * k));
      if (k >= 1) { clearInterval(el._t); el._t = null; if (stop) { el.pause(); el.removeAttribute('src'); el.load(); } } }, 60); },
  play: function(id, vol) { var self = this; if (this.a) this.fade(this.a, 0, true);
    var n = new Audio(this.base + 'music/' + id + '.ogg'); n.preload = 'auto'; n.volume = 0; this.a = n; this.ended = false; this.want = vol;
    n.addEventListener('ended', function() { if (self.a === n) self.ended = true; });
    n.addEventListener('error', function() { if (self.a === n) self.ok = false; });
    this.go(n, vol); },
  go: function(n, vol) { var self = this; var p = n.play();
    if (p && p.catch) p.catch(function(e) { if (self.a !== n) return;
      if (e && e.name === 'NotAllowedError') { var again = function() { document.removeEventListener('pointerdown', again); document.removeEventListener('keydown', again); if (self.a === n) self.go(n, self.want); };
        document.addEventListener('pointerdown', again); document.addEventListener('keydown', again); }
      else if (e && e.name !== 'AbortError') self.ok = false; });
    this.fade(n, vol, false); },
  vol: function(v) { this.want = v; if (this.a) this.fade(this.a, v, false); },
  stop: function() { if (this.a) { this.fade(this.a, 0, true); this.a = null; } }
};
"""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_a = _player()
	_b = _player()
	Packs.pack_ready.connect(_on_pack)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(WEB_JS, true)
		web = true

func _web_vol() -> float: return 0.0 if muted else db_to_linear(VOLUME_DB)

func _process(dt: float) -> void:
	if not web: return
	_poll += dt
	if _poll < 0.5: return
	_poll = 0.0
	if not bool(JavaScriptBridge.eval("window.__hlm.ok", true)):   # the browser will not play it: the game's own player takes over
		web = false
		JavaScriptBridge.eval("window.__hlm.stop()", true)
		if track != "": _start(track)
	elif track != "" and mood != "" and bool(JavaScriptBridge.eval("window.__hlm.ended", true)):
		_start(_pick(mood))   # the take ended: another take of the same mood

func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM   # v1.8t: music is STREAMED. As a web "sample" a whole track is unpacked into one buffer (3.5 min = 80 MB); when the browser refuses that buffer the error stops the content packs arriving (no mech, no docking ring, stuck entering a planet)
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
		if web: JavaScriptBridge.eval("window.__hlm.stop()", true)
		_fade(_a, -60.0, true)
		return
	_start(_pick(m))

func _pick(m: String) -> String:
	var tk: Array = takes(m)
	if m.begins_with("f:") and not _last.has(m):   # v1.9k: a system always opens on its own track
		_last[m] = tk[0]
		return tk[0]
	var id: String = tk[_rng.randi() % tk.size()]
	if tk.size() > 1 and id == _last.get(m, ""): id = tk[(tk.find(id) + 1) % tk.size()]
	_last[m] = id
	return id

func _start(id: String) -> void:
	track = id
	if web:
		JavaScriptBridge.eval("window.__hlm.play('%s', %f)" % [id, _web_vol()], true)
		return
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
	if web: JavaScriptBridge.eval("window.__hlm.vol(%f)" % _web_vol(), true)
	if _a.playing: _fade(_a, -60.0 if m else VOLUME_DB, false)

func is_playing() -> bool: return _a.playing or (web and track != "")
