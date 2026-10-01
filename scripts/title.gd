extends Control
## Startup screen in Homelancer's navigation style: a white field with the blue star network slowly panning, the
## HOMELANCER letters resolving one by one, then a strong START. (Galaxy map drawing is shared: galaxymap.gd.)

signal start_pressed

const GM := preload("res://scripts/galaxymap.gd")
const WORD := "HOMELANCER"
var t := 0.0
var font: Font = ThemeDB.fallback_font
var start_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	start_btn = Button.new()
	start_btn.name = "StartButton"
	start_btn.text = "START"
	start_btn.custom_minimum_size = Vector2(320, 86)
	start_btn.add_theme_font_size_override("font_size", 38)
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

func _process(dt: float) -> void:
	t += dt
	var S := get_viewport_rect().size
	start_btn.position = Vector2(S.x * 0.5 - 160, S.y * 0.62)
	start_btn.modulate.a = clampf((t - 2.1) / 0.5, 0.0, 1.0)   # START appears once the logo has resolved
	queue_redraw()

func _draw() -> void:
	var S := get_viewport_rect().size
	GM.draw_network(self, S, 0.2 + t * 0.03, 0.05, t, Vector3(-10, 0, -20), "", "", null, false)
	draw_rect(Rect2(Vector2.ZERO, S), Color(GM.BG, 0.35))
	# the letters resolve one after another: each fades in and settles from a slight offset
	var size := clampi(int(S.y * 0.13), 56, 110)
	var total := font.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + (WORD.length() - 1) * size * 0.18
	var x := S.x * 0.5 - total * 0.5
	var y := S.y * 0.42
	for i in WORD.length():
		var ch := WORD[i]
		var k := clampf((t - 0.25 - i * 0.14) / 0.45, 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		draw_string(font, Vector2(x, y + (1.0 - e) * 18.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(GM.NAVY, e))
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + size * 0.18
	var k2 := clampf((t - 1.8) / 0.5, 0.0, 1.0)
	draw_line(Vector2(S.x * 0.5 - total * 0.5 * k2, y + 22), Vector2(S.x * 0.5 + total * 0.5 * k2, y + 22), Color(GM.MID, k2), 2.0)
	draw_string(font, Vector2(0, y + 52), "DIGITAL  ·  %s" % Data.VERSION, HORIZONTAL_ALIGNMENT_CENTER, S.x, 18, Color(GM.DEEP, k2))
	draw_string(font, Vector2(0, S.y - 26), "Landscape · left thumb flies · right thumb aims · lasers fire on their own", HORIZONTAL_ALIGNMENT_CENTER, S.x, 14, Color(GM.MID, k2))
