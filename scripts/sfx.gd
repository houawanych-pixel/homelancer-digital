extends Node
## Sound effects and radio voices (autoload "Sfx"). All sounds are synthesized by tools/sfx/make_sfx.py.
## Radio calls: an open chirp, then 'mumble' syllables pitched per character while the line is on screen
## (Star Fox style). Voice mode "read" uses the device's text-to-speech instead, when it has one.

const BANK := ["comm_open", "comm_close", "laser", "laser_enemy", "missile", "explosion", "shield_hit", "hull_hit", "tractor", "pickup", "mine_wake", "button", "atmo", "whoosh", "warp_spool", "warp_go", "transform"]
const SYLLABLES := 8

var streams := {}
var syl: Array = []
var pool: Array = []          # one-shot players
var voice_player: AudioStreamPlayer
var voice_mode := "bleep"     # "bleep" | "read"
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

func play(n: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(n) or streams[n] == null: return
	for p in pool:
		if not p.playing:
			p.stream = streams[n]
			p.volume_db = vol_db
			p.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
			p.play()
			return

func tts_available() -> bool:
	return DisplayServer.tts_get_voices().size() > 0

func toggle_voice() -> String:
	voice_mode = "read" if voice_mode == "bleep" else "bleep"
	if voice_mode == "read" and not tts_available():
		voice_mode = "bleep"
		return "Voice: this device has no text-to-speech — using radio mumble."
	return "Voice: reading lines aloud." if voice_mode == "read" else "Voice: radio mumble."

## Start a radio line. pitch ~1.3 lighter voices, ~0.7 deep voices.
func speak(text: String, pitch := 1.0, female := false) -> void:
	stop_voice()
	play("comm_open", -4.0)
	_talk_pitch = pitch
	if voice_mode == "read" and tts_available():
		var voices := DisplayServer.tts_get_voices_for_language(TranslationServer.get_locale().substr(0, 2))
		if voices.is_empty(): voices = DisplayServer.tts_get_voices_for_language("en")
		if voices.is_empty(): voices = PackedStringArray([DisplayServer.tts_get_voices()[0]["id"]])
		var pick: String = voices[(1 if female and voices.size() > 1 else 0)]
		DisplayServer.tts_speak(text, pick, 80, clampf(pitch, 0.5, 1.8), 1.05)
		_talk_left = clampf(text.length() / 15.0, 1.0, 6.0)
		_talk_gap = 0.25
		return
	_talk_left = clampf(text.length() / 22.0, 0.8, 3.2)   # mumble a bit shorter than the text
	_talk_gap = 0.22                                       # let the chirp finish first

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
	if voice_mode == "read" and tts_available():
		if _talk_gap <= 0.0:
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
