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
	start_btn.pressed.connect(_open_slots)   # v1.9j: pick (or name) a pilot first
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
	if slots_panel != null and is_instance_valid(slots_panel): slots_panel.position = (size - slots_panel.size) * 0.5   # v1.9j: the picker sits in the middle
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

# ---------------------------------------------------------------- v1.9j (owner): three pilots on this device
## START opens the pilot picker: each slot is its own save (its own credits, ship and progress). An empty slot asks for
## a name. DELETE asks twice. The picker calls start_pressed once a pilot is chosen.
var slots_panel: PanelContainer = null
var _delete_armed := -1
var _naming := 0

func _open_slots() -> void:
	GS.migrate_old_save()
	if slots_panel != null and is_instance_valid(slots_panel):   # (taken out at once, so the new buttons are the only ones found)
		remove_child(slots_panel)
		slots_panel.queue_free()
	slots_panel = PanelContainer.new()
	slots_panel.name = "SlotsPanel"
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(0.03, 0.05, 0.1, 1.0)
	bgs.border_color = GM.NAVY
	bgs.set_border_width_all(3)
	bgs.set_corner_radius_all(14)
	bgs.set_content_margin_all(22)
	slots_panel.add_theme_stylebox_override("panel", bgs)
	add_child(slots_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	slots_panel.add_child(v)
	var head := Label.new()
	head.text = "CHOOSE YOUR PILOT"
	head.add_theme_font_size_override("font_size", Data.ts(30))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	for i in range(1, Data.SAVE_SLOTS + 1):
		var info: Dictionary = GS.slot_info(i)
		var row := HBoxContainer.new()
		row.name = "Slot_%d" % i
		row.add_theme_constant_override("separation", 12)
		var l := Label.new()
		l.custom_minimum_size = Vector2(430, 64)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", Data.ts(20))
		l.text = "%d.  EMPTY" % i if info.is_empty() else "%d.  %s   ·   %d cr   ·   %s" % [i, info["name"], int(info["credits"]), info["system"]]
		row.add_child(l)
		var play := Button.new()
		play.name = "Play_%d" % i
		play.text = "NEW PILOT" if info.is_empty() else "PLAY"
		play.custom_minimum_size = Vector2(190, 64)
		play.add_theme_font_size_override("font_size", Data.ts(22))
		play.pressed.connect(_pick_slot.bind(i, info.is_empty()))
		row.add_child(play)
		if not info.is_empty():
			var del := Button.new()
			del.name = "Delete_%d" % i
			del.text = "SURE? DELETE" if _delete_armed == i else "DELETE"
			del.custom_minimum_size = Vector2(170, 64)
			del.add_theme_font_size_override("font_size", Data.ts(18))
			del.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
			del.pressed.connect(func():
				if _delete_armed == i:
					GS.erase_slot(i)
					_delete_armed = -1
				else: _delete_armed = i
				_open_slots())
			row.add_child(del)
		v.add_child(row)
	if _naming > 0:   # a new pilot's name (desktop: type it here; phone: the phone's own keyboard pops up)
		var nrow := HBoxContainer.new()
		nrow.add_theme_constant_override("separation", 12)
		var le := LineEdit.new()
		le.name = "NameEdit"
		le.placeholder_text = "Pilot name"
		le.max_length = Data.PILOT_NAME_MAX
		le.custom_minimum_size = Vector2(430, 64)
		le.add_theme_font_size_override("font_size", Data.ts(22))
		nrow.add_child(le)
		var ok := Button.new()
		ok.name = "NameOK"
		ok.text = "FLY"
		ok.custom_minimum_size = Vector2(190, 64)
		ok.add_theme_font_size_override("font_size", Data.ts(22))
		ok.pressed.connect(func(): _begin(_naming, le.text))
		le.text_submitted.connect(func(tx: String): _begin(_naming, tx))
		nrow.add_child(ok)
		v.add_child(nrow)
		le.call_deferred("grab_focus")
	var back := Button.new()
	back.name = "SlotsBack"
	back.text = "BACK"
	back.custom_minimum_size = Vector2(190, 56)
	back.pressed.connect(func():
		_naming = 0
		slots_panel.queue_free()
		slots_panel = null)
	v.add_child(back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_style_all(slots_panel)
	slots_panel.reset_size()
	slots_panel.position = (size - slots_panel.size) * 0.5

func _style_all(n: Node) -> void:
	for c in n.get_children():
		if c is Button:
			var sb := StyleBoxFlat.new()
			sb.bg_color = GM.DEEP
			sb.border_color = GM.NAVY
			sb.set_border_width_all(2)
			sb.set_corner_radius_all(10)
			var sb2 := sb.duplicate() as StyleBoxFlat
			sb2.bg_color = GM.NAVY
			for st in ["normal", "focus"]: c.add_theme_stylebox_override(st, sb)
			for st in ["hover", "pressed"]: c.add_theme_stylebox_override(st, sb2)
			if not c.has_theme_color_override("font_color"): c.add_theme_color_override("font_color", Color.WHITE)
		_style_all(c)

func _pick_slot(i: int, empty: bool) -> void:
	if not empty:
		_begin(i, "")
		return
	if OS.has_feature("web"):   # (the phone's own keyboard: a name box from the browser)
		var nm = JavaScriptBridge.eval("(window.prompt('Pilot name for slot %d', '') || '')" % i, true)
		if str(nm).strip_edges() != "":
			_begin(i, str(nm))
			return
	_naming = i
	_open_slots()

## Start playing as pilot i (a new pilot gets the name; an empty name becomes "Pilot i").
func _begin(i: int, nm: String) -> void:
	GS.use_slot(i)
	var empty := GS.slot_info(i).is_empty()
	if empty:
		var clean := nm.strip_edges().substr(0, Data.PILOT_NAME_MAX)
		GS.pilot_name = clean if clean != "" else "Pilot %d" % i
	_naming = 0
	if slots_panel != null:
		slots_panel.queue_free()
		slots_panel = null
	start_pressed.emit()

## Once the game starts, let go of the picture so it doesn't sit in GPU memory.
func release() -> void:
	bg = null
	if movie != null:
		movie.stop()
		movie.queue_free()
		movie = null
