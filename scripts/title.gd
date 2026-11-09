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
var pick_k := 0.0   # v12.94: 0 = the title, 1 = the pilot picker open (the logo moves up out of its way)
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
	var picking := slots_panel != null and is_instance_valid(slots_panel)
	pick_k = move_toward(pick_k, 1.0 if picking else 0.0, dt / 0.35)
	if picking:   # v12.94 (owner: "move the sign up so we can read the words ... why so many layers"): under the logo, alone on screen
		var S0 := get_viewport_rect().size
		slots_panel.position = Vector2((S0.x - slots_panel.size.x) * 0.5, maxf(S0.y * 0.25, S0.y - 56.0 - slots_panel.size.y))
		slots_panel.modulate.a = pick_k
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
	start_btn.modulate.a = clampf((t - 2.1) / 0.5, 0.0, 1.0) * (1.0 - pick_k)   # START appears once the logo has resolved
	music_btn.modulate.a = start_btn.modulate.a
	settings_btn.modulate.a = start_btn.modulate.a
	for b in [start_btn, music_btn, settings_btn]: b.visible = pick_k < 0.99   # (the picker is the only thing to press)
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
		var top := lerpf(0.2, 0.0, pick_k)   # (v12.94: the band rises with the logo, and reaches down behind the picker)
		var span := lerpf(0.62, 1.0, pick_k)
		var y0 := floorf(S.y * (top + span * i / steps))
		var y1 := floorf(S.y * (top + span * (i + 1) / steps))   # whole pixels, edge to edge: no overlap lines
		draw_rect(Rect2(0, y0, S.x, y1 - y0), Color(0.01, 0.02, 0.06, a))
	# the letters resolve one after another: each fades in and settles from a slight offset
	var size := clampi(int(S.y * 0.13), 56, 110)
	var total := font.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + (WORD.length() - 1) * size * 0.18
	var x := S.x * 0.5 - total * 0.5
	var y := lerpf(S.y * 0.42, S.y * 0.15, pick_k * pick_k * (3.0 - 2.0 * pick_k))
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
	draw_string(font, Vector2(24, S.y - 18), "Landscape · left thumb flies · right thumb aims · lasers fire on their own", HORIZONTAL_ALIGNMENT_CENTER, S.x - 320.0, 16, Color(0.85, 0.93, 1.0, k2))   # (v12.94: clear of FULL SCREEN at the right)

# ---------------------------------------------------------------- v1.9j (owner): three pilots on this device
## START opens the pilot picker: each slot is its own save (its own credits, ship and progress). An empty slot asks for
## a name. DELETE asks twice. The picker calls start_pressed once a pilot is chosen.
var slots_panel: PanelContainer = null
var _delete_armed := -1
var _naming := 0

const GLASS := Color(0.02, 0.06, 0.12, 0.58)   # v12.94 (owner: "make the black a little transparent ... not a basic black-and-blue UI")
const NEON := Color(0.36, 0.86, 1.0)
const AMBER := Color(1.0, 0.72, 0.3)
func _box(bg: Color, edge: Color, w := 2, r := 12, pad := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = edge
	b.set_border_width_all(w)
	b.set_corner_radius_all(r)
	if pad > 0: b.set_content_margin_all(pad)
	return b
func _btn(nm: String, text: String, kind: String, w: float, h: float) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", Data.ts(20))
	var c: Array = {"go": [Color(NEON, 0.92), NEON.lightened(0.4), Color(0.02, 0.08, 0.14)], "new": [Color(AMBER, 0.16), AMBER, AMBER.lightened(0.3)],
		"del": [Color(1.0, 0.3, 0.3, 0.12), Color(1.0, 0.42, 0.4, 0.9), Color(1.0, 0.62, 0.58)], "plain": [Color(1, 1, 1, 0.06), Color(NEON, 0.6), Color(0.85, 0.95, 1.0)]}[kind]
	b.add_theme_stylebox_override("normal", _box(c[0], c[1], 2, 10))
	b.add_theme_stylebox_override("focus", _box(c[0], c[1], 2, 10))
	b.add_theme_stylebox_override("hover", _box((c[0] as Color).lightened(0.25), c[1], 3, 10))
	b.add_theme_stylebox_override("pressed", _box((c[0] as Color).lightened(0.4), c[1], 3, 10))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(k, c[2])
	return b

func _open_slots() -> void:
	GS.migrate_old_save()
	if slots_panel != null and is_instance_valid(slots_panel):   # (taken out at once, so the new buttons are the only ones found)
		remove_child(slots_panel)
		slots_panel.queue_free()
	slots_panel = PanelContainer.new()
	slots_panel.name = "SlotsPanel"
	slots_panel.add_theme_stylebox_override("panel", _box(GLASS, Color(NEON, 0.55), 2, 18, 22))
	slots_panel.modulate.a = pick_k
	add_child(slots_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	slots_panel.add_child(v)
	var head := Label.new()
	head.text = "CHOOSE YOUR PILOT"
	head.add_theme_font_size_override("font_size", Data.ts(26))
	head.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var sub := Label.new()
	sub.text = "Continue a pilot, or start a new one"
	sub.add_theme_font_size_override("font_size", Data.ts(15))
	sub.add_theme_color_override("font_color", Color(NEON, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	for i in range(1, Data.SAVE_SLOTS + 1):
		var info: Dictionary = GS.slot_info(i)
		var card := PanelContainer.new()   # each pilot on its own see-through card, a coloured bar down its left side
		var cs := _box(Color(1, 1, 1, 0.05 if info.is_empty() else 0.08), Color(NEON, 0.0), 0, 12, 10)
		cs.border_width_left = 5
		cs.border_color = Color(1, 1, 1, 0.18) if info.is_empty() else NEON
		card.add_theme_stylebox_override("panel", cs)
		var row := HBoxContainer.new()
		row.name = "Slot_%d" % i
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var l := Label.new()
		l.custom_minimum_size = Vector2(440, 56)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if info.is_empty():
			l.text = "%d   ·   EMPTY SLOT" % i
			l.add_theme_font_size_override("font_size", Data.ts(18))
			l.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9, 0.7))
		else:
			l.text = "%d   %s\n     %d cr   ·   %s" % [i, str(info["name"]), int(info["credits"]), info["system"]]
			l.add_theme_font_size_override("font_size", Data.ts(19))
			l.add_theme_color_override("font_color", Color(0.95, 0.99, 1.0))
		row.add_child(l)
		var play := _btn("Play_%d" % i, "NEW PILOT" if info.is_empty() else "CONTINUE", "new" if info.is_empty() else "go", 190, 56)
		play.pressed.connect(_pick_slot.bind(i, info.is_empty()))
		row.add_child(play)
		if not info.is_empty():
			var del := _btn("Delete_%d" % i, "SURE? DELETE" if _delete_armed == i else "DELETE", "del", 160, 56)
			del.pressed.connect(func():
				if _delete_armed == i:
					GS.erase_slot(i)
					_delete_armed = -1
				else: _delete_armed = i
				_open_slots())
			row.add_child(del)
		v.add_child(card)
	if _naming > 0:   # a new pilot's name (desktop: type it here; phone: the phone's own keyboard pops up)
		var nrow := HBoxContainer.new()
		nrow.add_theme_constant_override("separation", 12)
		var le := LineEdit.new()
		le.name = "NameEdit"
		le.placeholder_text = "Pilot name"
		le.max_length = Data.PILOT_NAME_MAX
		le.custom_minimum_size = Vector2(440, 56)
		le.add_theme_font_size_override("font_size", Data.ts(22))
		le.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.08), Color(NEON, 0.7), 2, 10, 10))
		nrow.add_child(le)
		var ok := _btn("NameOK", "FLY", "go", 190, 56)
		ok.pressed.connect(func(): _begin(_naming, le.text))
		le.text_submitted.connect(func(tx: String): _begin(_naming, tx))
		nrow.add_child(ok)
		v.add_child(nrow)
		le.call_deferred("grab_focus")
	var back := _btn("SlotsBack", "BACK", "plain", 170, 48)
	back.pressed.connect(func():
		_naming = 0
		slots_panel.queue_free()
		slots_panel = null)
	v.add_child(back)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slots_panel.reset_size()

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
