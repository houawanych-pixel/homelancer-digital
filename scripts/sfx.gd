extends Node
## Sound effects and radio voices (autoload "Sfx"). All sounds are synthesized by tools/sfx/make_sfx.py.
## Radio calls: an open chirp, then 'mumble' syllables pitched per character while the line is on screen
## (Star Fox style). Voice mode "read" = VOICE ON (the default since v1.4t): the line is spoken. A recorded or generated
## clip for that character and line is used when there is one (assets/voices/<voice_id>/<line key>.ogg); otherwise the
## device's text-to-speech reads it; a device with neither falls back to the mumble. Voice mode "bleep" = VOICE OFF:
## the mumble blips. The choice is kept in the settings file (section "audio"; nothing renamed).

const BANK := ["comm_open", "comm_close", "laser", "laser_enemy", "missile", "explosion", "shield_hit", "hull_hit", "tractor", "pickup", "mine_wake", "button", "atmo", "whoosh", "warp_spool", "warp_go", "transform", "fx_static", "fx_robot", "fx_alien", "fx_hum"]
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
	for n in BANK: streams[n] = load("res://assets/audio/%s.wav" % n) if ResourceLoader.exists("res://assets/audio/%s.wav" % n) else null
	for i in SYLLABLES: syl.append(load("res://assets/audio/syl_%d.wav" % i))
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	voice_player = AudioStreamPlayer.new()
	voice_player.volume_db = -3.0
	add_child(voice_player)
	bed_player = AudioStreamPlayer.new()   # v1.5j: the quiet bed behind a line (a machine's hum)
	bed_player.volume_db = -20.0
	add_child(bed_player)
	load_prefs()

func load_prefs() -> void:
	voice_mode = Data.VOICE_DEFAULT
	voice_picks = {}
	var cf := ConfigFile.new()
	if cf.load(path) != OK: return
	var m = cf.get_value("audio", "voice_mode", Data.VOICE_DEFAULT)
	if m is String and m in ["read", "bleep"]: voice_mode = m
	var vp = cf.get_value("voice_pick", "picks", {})   # v1.5j: the device voice picked per character (new section)
	if vp is Dictionary: voice_picks = vp

func _save_picks() -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value("voice_pick", "picks", voice_picks)
	cf.save(path)

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

# ---------------------------------------------------------------- v1.5j voice providers (see scripts/voice.gd)
var bed_player: AudioStreamPlayer
var voice_picks := {}         # character_id -> device voice id (remembered in the settings file)
var last_profile := {}        # the profile the last line was spoken with (tests, HUD)
var last_provider := ""       # "PRELOADED_AUDIO" | "LIVE_API" | "PHONE_TTS" | "BLIPS"
var _tail := ""               # the effect sound to play when the line ends
var _last_key := ""
var _last_key_t := -100.0
var voices_override: Array = []   # tests: pretend the device has these voices

func device_voices() -> Array:
	if not voices_override.is_empty(): return voices_override
	return DisplayServer.tts_get_voices() if tts_available() else []

## THE way the game speaks a line for a character. dialogue_id names a recorded line when there is one (otherwise
## the line's text does); the providers are tried in order (Voice.PROVIDERS). legacy_* serve characters not yet on a
## voice profile (they keep their old pitch / sex values).
func play_character_voice(character_id: String, dialogue_id: String, text: String, legacy_pitch := 1.0, legacy_female := false) -> void:
	var key := "%s|%s" % [character_id, text]
	var now := Time.get_ticks_msec() / 1000.0
	if key == _last_key and now - _last_key_t < Data.VOICE_SAME_LINE_GUARD: return   # the same line asked twice at once: once
	_last_key = key
	_last_key_t = now
	if not Voice.profiled(character_id):
		_speak_legacy(text, legacy_pitch, legacy_female, character_id)
		return
	stop_voice()
	var prof := Voice.profile(character_id)
	last_profile = prof
	var fx: Array = Data.VOICE_EFFECT_SOUNDS.get(str(prof["effect"]), ["", "", ""])
	play("comm_open", -4.0)
	if fx[0] != "": play(fx[0], -8.0)
	_tail = fx[2]
	_talk_pitch = float(prof["pitch"])
	_clip = false
	last_voice = "blip"
	last_provider = "BLIPS"
	if voice_mode == "read":
		# 1. PRELOADED_AUDIO
		var cp := clip_path(character_id, dialogue_id if dialogue_id != "" else text)
		if ResourceLoader.exists(cp):
			voice_player.stream = load(cp)
			voice_player.pitch_scale = 1.0
			voice_player.play()
			_clip = true
			last_voice = "clip"
			last_provider = "PRELOADED_AUDIO"
			_talk_left = maxf(1.0, (voice_player.stream as AudioStream).get_length())
			_talk_gap = 0.09
			return
		# 2. LIVE_API: off until a secure server exists (Data.VOICE_LIVE_API)
		# 3. PHONE_TTS
		var voices := device_voices()
		if not voices.is_empty():
			var pick := Voice.pick_voice(prof, voices, str(voice_picks.get(character_id, "")))
			prof["preferred_voice"] = pick["voice"]
			prof["fallback_voice"] = pick["fallback"]
			var pitch: float = float(prof["pitch"])
			if not pick["matched"]: pitch *= Data.VOICE_SEX_PITCH_NUDGE if prof["voice_type"] == "female" else 1.0 / Data.VOICE_SEX_PITCH_NUDGE
			pitch = clampf(pitch, Data.VOICE_PITCH_RANGE[0], Data.VOICE_PITCH_RANGE[1])
			prof["spoken_pitch"] = pitch
			if voice_picks.get(character_id, "") != pick["voice"]:
				voice_picks[character_id] = pick["voice"]
				_save_picks()
			if voices_override.is_empty(): DisplayServer.tts_speak(text, pick["voice"], int(prof["volume"]), pitch, float(prof["speaking_rate"]))
			last_voice = "tts"
			last_provider = "PHONE_TTS"
			_talk_left = clampf(text.length() / (15.0 * float(prof["speaking_rate"])), 1.0, 7.0)
			_talk_gap = 0.25
			if fx[1] != "" and streams.get(fx[1]) != null:
				bed_player.stream = streams[fx[1]]
				bed_player.play()
			last_profile = prof
			return
	_talk_left = clampf(text.length() / 22.0, 0.8, 3.2)
	_talk_gap = 0.22

## Start a radio line. pitch ~1.3 lighter voices, ~0.7 deep voices. voice_id = whose recorded voice to look for.
## (v1.5j: everything goes through play_character_voice; this keeps the old call working.)
func speak(text: String, pitch := 1.0, female := false, voice_id := "") -> void:
	play_character_voice(voice_id, "", text, pitch, female)

func _speak_legacy(text: String, pitch := 1.0, female := false, voice_id := "") -> void:
	last_provider = ""
	last_profile = {}
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
	_tail = ""
	voice_player.stop()
	if bed_player: bed_player.stop()
	if DisplayServer.tts_is_speaking(): DisplayServer.tts_stop()

func hang_up() -> void:
	if _talk_left > 0.0 or DisplayServer.tts_is_speaking():
		stop_voice()
	play("comm_close", -6.0)

func _process(dt: float) -> void:
	talking = maxf(0.0, talking - dt * 7.0)
	if _talk_left <= 0.0: return
	_talk_left -= dt
	if _talk_left <= 0.0:   # v1.5j: the line is over: stop the bed, play the effect's closing sound
		if bed_player: bed_player.stop()
		if _tail != "": play(_tail, -9.0)
		_tail = ""
		return
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
