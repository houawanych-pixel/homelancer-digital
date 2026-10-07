extends Node
## Sound effects and radio voices (autoload "Sfx"). All sounds are synthesized by tools/sfx/make_sfx.py.
## Radio calls: an open chirp, then 'mumble' syllables pitched per character while the line is on screen
## (Star Fox style). Voice mode "read" = VOICE ON (the default since v1.4t): the line is spoken. A recorded or generated
## clip for that character and line is used when there is one (assets/voices/<voice_id>/<line key>.ogg); otherwise the
## device's text-to-speech reads it; a device with neither falls back to the mumble. Voice mode "bleep" = VOICE OFF:
## the mumble blips. The choice is kept in the settings file (section "audio"; nothing renamed).

const BANK := ["comm_open", "comm_close", "laser", "laser_enemy", "missile", "explosion", "shield_hit", "hull_hit", "tractor", "pickup", "mine_wake", "button", "atmo", "whoosh", "warp_spool", "warp_go", "transform"]
const SYLLABLES := 8

var streams := {}
var syl: Array = []
var pool: Array = []          # one-shot players
var voice_player: AudioStreamPlayer
var voice_mode: String = Data.VOICE_DEFAULT     # "read" (voice ON, the default) | "bleep" (voice OFF: radio blips)
var path: String = Data.SETTINGS_PATH   # where the choice is kept (the route test points this at its own file)
var last_voice := ""          # how the last line was voiced: "clip" | "tts" | "blip" (for the HUD and the tests)
var _talk_left := 0.0
var _talk_gap := 0.0
var _talk_pitch := 1.0
var _rng := RandomNumberGenerator.new()
var talking := 0.0            # 0..1 envelope of the current syllable, for the HUD to animate the face

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in BANK: streams[n] = load("res://assets/audio/%s.wav" % n)
	for i in SYLLABLES: syl.append(load("res://assets/audio/syl_%d.wav" % i))
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	voice_player = AudioStreamPlayer.new()
	voice_player.volume_db = -3.0
	add_child(voice_player)
	load_prefs()

func load_prefs() -> void:
	voice_mode = Data.VOICE_DEFAULT
	var cf := ConfigFile.new()
	if cf.load(path) != OK: return
	var m = cf.get_value("audio", "voice_mode", Data.VOICE_DEFAULT)
	if m is String and m in ["read", "bleep"]: voice_mode = m

func save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value("audio", "voice_mode", voice_mode)
	cf.save(path)

func voice_on() -> bool: return voice_mode == "read"

## The file a character's spoken line would be: assets/voices/<voice_id>/<the line, lower case, words joined by _>.ogg
static func clip_path(voice_id: String, text: String) -> String:
	var key := ""
	for ch in text.to_lower():
		key += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while key.find("__") >= 0: key = key.replace("__", "_")
	return "%s%s/%s.ogg" % [Data.VOICE_DIR, voice_id, key.strip_edges().trim_prefix("_").trim_suffix("_").left(Data.VOICE_KEY_LEN)]

func play(n: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(n) or streams[n] == null: return
	for p in pool:
		if not p.playing:
			p.stream = streams[n]
			p.volume_db = vol_db
			p.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
			p.play()
			return

var _tts_yes := false
var _tts_next := 0
## Can this device read a line aloud? Asked again now and then (a browser's voices arrive late), remembered once true.
func tts_available() -> bool:
	if _tts_yes: return true
	var now := Time.get_ticks_msec()
	if now < _tts_next: return false
	_tts_next = now + 4000
	_tts_yes = DisplayServer.tts_get_voices().size() > 0
	return _tts_yes

func toggle_voice() -> String:
	voice_mode = "bleep" if voice_mode == "read" else "read"
	save_prefs()
	if voice_mode == "bleep": return "Voice OFF: radio blips."
	return "Voice ON: lines are spoken." if tts_available() else "Voice ON. This device cannot read lines aloud yet: recorded voices play, the rest stay as blips."

## Start a radio line. pitch ~1.3 lighter voices, ~0.7 deep voices. voice_id = whose recorded voice to look for.
func speak(text: String, pitch := 1.0, female := false, voice_id := "") -> void:
	stop_voice()
	play("comm_open", -4.0)
	_talk_pitch = pitch
	_clip = false
	last_voice = "blip"
	if voice_mode == "read":
		var cp := clip_path(voice_id, text) if voice_id != "" else ""
		if cp != "" and ResourceLoader.exists(cp):   # this character's own recorded / generated voice
			voice_player.stream = load(cp)
			voice_player.pitch_scale = 1.0
			voice_player.play()
			_clip = true
			last_voice = "clip"
			_talk_left = maxf(1.0, (voice_player.stream as AudioStream).get_length())
			_talk_gap = 0.09
			return
		if tts_available():
			var voices := DisplayServer.tts_get_voices_for_language(TranslationServer.get_locale().substr(0, 2))
			if voices.is_empty(): voices = DisplayServer.tts_get_voices_for_language("en")
			if voices.is_empty(): voices = PackedStringArray([DisplayServer.tts_get_voices()[0]["id"]])
			var pick: String = voices[(1 if female and voices.size() > 1 else 0)]
			DisplayServer.tts_speak(text, pick, 80, clampf(pitch, 0.5, 1.8), 1.05)
			last_voice = "tts"
			_talk_left = clampf(text.length() / 15.0, 1.0, 6.0)
			_talk_gap = 0.25
			return
	_talk_left = clampf(text.length() / 22.0, 0.8, 3.2)   # mumble a bit shorter than the text
	_talk_gap = 0.22                                       # let the chirp finish first

var _clip := false

func stop_voice() -> void:
	_talk_left = 0.0
	talking = 0.0
	voice_player.stop()
	if DisplayServer.tts_is_speaking(): DisplayServer.tts_stop()

func hang_up() -> void:
	if _talk_left > 0.0 or DisplayServer.tts_is_speaking():
		stop_voice()
	play("comm_close", -6.0)

func _process(dt: float) -> void:
	talking = maxf(0.0, talking - dt * 7.0)
	if _talk_left <= 0.0: return
	_talk_left -= dt
	if not voice_player.playing: _talk_gap -= dt
	if last_voice != "blip":   # a spoken line (clip or text-to-speech): the face just moves while it lasts
		if _clip and not voice_player.playing: _talk_left = 0.0
		elif _talk_gap <= 0.0 or _clip:
			talking = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.02))
			_talk_gap = 0.09
		return
	if _talk_gap <= 0.0 and not voice_player.playing:
		voice_player.stream = syl[_rng.randi() % syl.size()]
		voice_player.pitch_scale = _talk_pitch * _rng.randf_range(0.9, 1.12)
		voice_player.play()
		talking = 1.0
		# short pause between 'words' now and then
		_talk_gap = _rng.randf_range(0.02, 0.05) + (0.16 if _rng.randf() < 0.22 else 0.0)
