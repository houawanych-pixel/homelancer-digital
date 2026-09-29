extends Control
## Full-screen transition overlay: fades, captions and the jump-gate warp tunnel.

var fade := 0.0 # 0 clear .. 1 black
var fade_color := Color(0, 0, 0)
var warp := 0.0 # 0..1 streak intensity
var warp_color := Color(0.4, 0.8, 1.0)
var caption := ""
var sub := ""
var t := 0.0
var font: Font = ThemeDB.fallback_font
var streaks: Array = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 140:
		streaks.append([rng.randf() * TAU, rng.randf(), rng.randf_range(0.4, 1.0)])

func _process(dt: float) -> void:
	t += dt
	queue_redraw()

func _draw() -> void:
	var S := get_viewport_rect().size
	var c := S * 0.5
	if warp > 0.0:
		draw_rect(Rect2(Vector2.ZERO, S), Color(warp_color.darkened(0.85), warp * 0.85))
		var maxr := S.length() * 0.6
		for s in streaks:
			var a: float = s[0] + t * 0.25
			var ph: float = fmod(s[1] + t * (0.6 + s[2]) * (0.5 + warp * 1.6), 1.0)
			var r0 := pow(ph, 2.2) * maxr
			var r1 := r0 + (30.0 + 260.0 * warp) * ph
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * r0, c + dir * r1, Color(warp_color.lightened(0.3), warp * ph * s[2]), 1.0 + 3.0 * ph)
		draw_circle(c, 40.0 + 140.0 * warp * (0.8 + 0.2 * sin(t * 9.0)), Color(1, 1, 1, warp * 0.35))
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, S), Color(fade_color, fade))
	if caption != "":
		var a2 := clampf(maxf(fade, warp) * 1.5, 0.0, 1.0)
		draw_string_outline(font, Vector2(0, c.y - 6), caption, HORIZONTAL_ALIGNMENT_CENTER, S.x, 38, 6, Color(0, 0, 0, a2 * 0.8))
		draw_string(font, Vector2(0, c.y - 6), caption, HORIZONTAL_ALIGNMENT_CENTER, S.x, 38, Color(1, 1, 1, a2))
		if sub != "":
			draw_string(font, Vector2(0, c.y + 30), sub, HORIZONTAL_ALIGNMENT_CENTER, S.x, 18, Color(0.6, 0.9, 1.0, a2))
