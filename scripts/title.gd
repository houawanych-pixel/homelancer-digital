extends Control
## Startup screen: the owner's intro movie, filling the screen and playing on repeat for as long as the player waits
## (v1.5a: it replaces the panning collage strip, which is archived in art/archive_title/); the HOMELANCER letters
## resolve one by one over a dark band, then a strong START. The movie is picture only: the main theme keeps playing.

signal start_pressed
signal settings_pressed   # Job J: Settings (control mode; Controls list on desktop)

const GM := preload("res://scripts/galaxymap.gd")
const WORD := "HOMELANCER"
var t := 0.0
var font: Font = ThemeDB.fallback_font
var start_btn: Button
var music_btn: Button
var settings_btn: Button
var bg: Texture2D = null   # v1.5q: no stand-in picture (owner): dark until the intro movie arrives
var movie: VideoStreamPlayer = null   # the intro movie ("intro" pack): fades in over the stand-in as soon as it arrives
var art_k := 0.0
const MOVIE := "res://assets/intro/title_movie.ogv"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	start_btn = Button.new()
	start_btn.name = "StartButton"
	start_btn.text = "START"
	start_btn.custom_minimum_size = Vector2(320, 86)
	start_btn.add_theme_font_size_override("font_size", Data.ts(38))
	var sb := StyleBoxFlat.new()
	sb.bg_color = GM.DEEP
	sb.border_color = GM.NAVY
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	var sb2 := sb.duplicate() as StyleBoxFlat
	sb2.bg_color = GM.NAVY
	for s in ["normal", "focus"]: start_btn.add_theme_stylebox_override(s, sb)
	for s in ["hover", "pressed"]: start_btn.add_theme_stylebox_override(s, sb2)
	start_btn.add_theme_color_override("font_color", Color.WHITE)
	start_btn.modulate.a = 0.0
	start_btn.pressed.connect(func(): start_pressed.emit())
	add_child(start_btn)
	music_btn = Button.new()
	music_btn.name = "MusicButton"
	music_btn.custom_minimum_size = SIDE_BTN
	music_btn.add_theme_font_size_override("font_size", Data.ts(22))
	_grey(music_btn)
	music_btn.pressed.connect(func():
		Music.set_muted(not Music.muted)
		_music_label())
	add_child(music_btn)
	_music_label()
	settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = "SETTINGS"
	settings_btn.custom_minimum_size = SIDE_BTN
	settings_btn.add_theme_font_size_override("font_size", Data.ts(22))
	_grey(settings_btn)
	settings_btn.focus_mode = Control.FOCUS_NONE
	settings_btn.pressed.connect(func(): settings_pressed.emit())
	add_child(settings_btn)
	Packs.pack_ready.connect(_take_art)
	Packs.request("intro")
	_take_art()

## v1.4m (owner): MUSIC and SETTINGS sit under START as two big grey buttons, not small ones in the corner.
const SIDE_BTN := Vector2(214, 62)
func _grey(b: Button) -> void:
	var g := StyleBoxFlat.new()
	g.bg_color = Color(0.32, 0.35, 0.4, 0.92)
	g.border_color = Color(0.78, 0.82, 0.88)
	g.set_border_width_all(2)
	g.set_corner_radius_all(12)
	var g2 := g.duplicate() as StyleBoxFlat
	g2.bg_color = Color(0.46, 0.5, 0.56, 0.96)
	for st in ["normal", "focus"]: b.add_theme_stylebox_override(st, g)
	for st in ["hover", "pressed"]: b.add_theme_stylebox_override(st, g2)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.modulate.a = 0.0

func _music_label() -> void:
	music_btn.text = "MUSIC: OFF" if Music.muted else "MUSIC: ON"

func _take_art(pk := "intro") -> void:
	if pk != "intro" or movie != null or not Packs.is_ready("intro") or not ResourceLoader.exists(MOVIE): return
	var st := load(MOVIE) as VideoStream
	if st == null: return
	movie = VideoStreamPlayer.new()
	movie.name = "IntroMovie"
	movie.stream = st
	movie.loop = true
	movie.expand = true
	movie.volume_db = -80.0            # picture only (the clip's own sound is off; the main theme plays)
	movie.show_behind_parent = true    # the dark band, the logo and the buttons are drawn over it
	movie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(movie)
	move_child(movie, 0)
	movie.play()

func _process(dt: float) -> void:
	t += dt
	var S := get_viewport_rect().size
	if movie != null:
		if art_k < 1.0:
			art_k = minf(1.0, art_k + dt / 0.9)
			if art_k >= 1.0: bg = null   # the stand-in is no longer drawn
		# fill the screen edge to edge, keeping the picture's shape (the overflow is cut off evenly)
		var vs: Vector2 = Vector2(movie.get_video_texture().get_size()) if movie.get_video_texture() != null else Vector2(640, 352)
		if vs.x < 2.0 or vs.y < 2.0: vs = Vector2(640, 352)
		var k := maxf(S.x / vs.x, S.y / vs.y)
		movie.size = vs * k
		movie.position = (S - movie.size) * 0.5
		if not movie.is_playing(): movie.play()   # (belt and braces for "on repeat")
	start_btn.position = Vector2(S.x * 0.5 - 160, S.y * 0.6)
	var row_y := start_btn.position.y + 86.0 + 14.0
	music_btn.position = Vector2(S.x * 0.5 - SIDE_BTN.x - 8.0, row_y)
	settings_btn.position = Vector2(S.x * 0.5 + 8.0, row_y)
	start_btn.modulate.a = clampf((t - 2.1) / 0.5, 0.0, 1.0)   # START appears once the logo has resolved
	music_btn.modulate.a = start_btn.modulate.a
	settings_btn.modulate.a = start_btn.modulate.a
	queue_redraw()

func _draw() -> void:
	var S := get_viewport_rect().size
	# v1.7n (owner): a plain light background (the web page's own colour) until the intro movie plays, so the 3D scene
	# behind is never seen first; it fades out as the movie fades in
	if art_k < 1.0: draw_rect(Rect2(Vector2.ZERO, S), Color(0.965, 0.976, 0.988, 1.0 - art_k))
	# the small stand-in picture, until the movie has arrived; it fades away over the movie playing behind
	if bg != null:
		var ks := maxf(S.x / bg.get_width(), S.y / bg.get_height())
		var bs := Vector2(bg.get_width(), bg.get_height()) * ks
		draw_texture_rect(bg, Rect2((S - bs) * 0.5, bs), false, Color(1, 1, 1, 1.0 - art_k))
	# a dark band behind the logo and the button so they read over busy art; the art stays clear above and below
	var steps := 48
	for i in steps:
		var v := (i + 0.5) / steps
		var a := 0.62 * pow(sin(v * PI), 1.6)
		var y0 := floorf(S.y * (0.2 + 0.62 * i / steps))
		var y1 := floorf(S.y * (0.2 + 0.62 * (i + 1) / steps))   # whole pixels, edge to edge: no overlap lines
		draw_rect(Rect2(0, y0, S.x, y1 - y0), Color(0.01, 0.02, 0.06, a))
	# the letters resolve one after another: each fades in and settles from a slight offset
	var size := clampi(int(S.y * 0.13), 56, 110)
	var total := font.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + (WORD.length() - 1) * size * 0.18
	var x := S.x * 0.5 - total * 0.5
	var y := S.y * 0.42
	for i in WORD.length():
		var ch := WORD[i]
		var k := clampf((t - 0.25 - i * 0.14) / 0.45, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		draw_string(font, Vector2(x, y + (1.0 - e) * 18.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, e))
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + size * 0.18
	var k2 := clampf((t - 1.8) / 0.5, 0.0, 1.0)
	draw_line(Vector2(S.x * 0.5 - total * 0.5 * k2, y + 22), Vector2(S.x * 0.5 + total * 0.5 * k2, y + 22), Color(0.45, 0.8, 1.0, k2), 2.0)
	draw_string(font, Vector2(0, y + 52), "DIGITAL  ·  %s" % Data.VERSION, HORIZONTAL_ALIGNMENT_CENTER, S.x, 20, Color(0.75, 0.9, 1.0, k2))
	draw_rect(Rect2(0, S.y - 46, S.x, 46), Color(0.01, 0.02, 0.06, 0.55 * k2))
	draw_string(font, Vector2(0, S.y - 18), "Landscape · left thumb flies · right thumb aims · lasers fire on their own", HORIZONTAL_ALIGNMENT_CENTER, S.x, 16, Color(0.85, 0.93, 1.0, k2))

## Once the game starts, let go of the picture so it doesn't sit in GPU memory.
func release() -> void:
	bg = null
	if movie != null:
		movie.stop()
		movie.queue_free()
		movie = null
