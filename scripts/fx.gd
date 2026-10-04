extends Control
## Full-screen transition overlay: fades, captions, the jump-gate warp tunnel, and the atmosphere pass
## (clouds rushing past + heat glow). Everything is 2D drawing: no particles, no extra 3D.

var fade := 0.0 # 0 clear .. 1 black
var fade_color := Color(0, 0, 0)
var warp := 0.0 # 0..1 streak intensity
var warp_color := Color(0.4, 0.8, 1.0)
var caption := ""
var sub := ""
var t := 0.0
var font: Font = ThemeDB.fallback_font
var streaks: Array = []
var clouds := 0.0 # 0..1 flying through cloud (white-out at 1)
var heat := 0.0   # 0..1 entry heating glow around the nose
var cloud_tint := Color(0.92, 0.94, 0.97)
var puffs: Array = []
var _puff_tex: ImageTexture
var blur := 0.0   # Job K: 0..1 screen blur during the jump tunnel
var flash := 0.0  # Job K: 0..1 white flash as the ship is launched out of the tunnel
var _blur_rect: ColorRect
const BLUR_SHADER := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount = 0.0;
uniform float px = 6.0;
void fragment() {
	vec2 o = SCREEN_PIXEL_SIZE * px * amount;
	vec4 c = texture(screen_tex, SCREEN_UV) * 0.2;
	c += texture(screen_tex, SCREEN_UV + vec2(o.x, 0.0)) * 0.1;
	c += texture(screen_tex, SCREEN_UV - vec2(o.x, 0.0)) * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(0.0, o.y)) * 0.1;
	c += texture(screen_tex, SCREEN_UV - vec2(0.0, o.y)) * 0.1;
	c += texture(screen_tex, SCREEN_UV + o) * 0.1;
	c += texture(screen_tex, SCREEN_UV - o) * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(o.x, -o.y)) * 0.1;
	c += texture(screen_tex, SCREEN_UV + vec2(-o.x, o.y)) * 0.1;
	COLOR = vec4(c.rgb, 1.0);
}
"""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Job K: layered star streaks (far / mid / near): near streaks are brighter, thicker and rush past faster
	for layer in Data.JUMP_STREAK_LAYERS:
		for i in int(layer[0]):
			streaks.append([rng.randf() * TAU, rng.randf(), float(layer[1]), float(layer[2])])
	_blur_rect = ColorRect.new()
	_blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = BLUR_SHADER
	_blur_rect.material = sm
	_blur_rect.visible = false
	_blur_rect.show_behind_parent = true   # blurs the 3D view under the streaks, not the captions
	add_child(_blur_rect)
	for i in 34:
		puffs.append([rng.randf() * TAU, rng.randf(), rng.randf_range(0.6, 1.4), rng.randf_range(0.8, 1.0)])
	# one soft cloud puff texture made from noise
	var n := FastNoiseLite.new()
	n.seed = 11
	n.frequency = 0.06
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			var d := Vector2(x - 47.5, y - 47.5).length() / 48.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * clampf(0.55 + n.get_noise_2d(x, y) * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_puff_tex = ImageTexture.create_from_image(img)

func _process(dt: float) -> void:
	t += dt
	_blur_rect.visible = blur > 0.001
	if _blur_rect.visible:
		(_blur_rect.material as ShaderMaterial).set_shader_parameter("amount", blur)
		(_blur_rect.material as ShaderMaterial).set_shader_parameter("px", Data.JUMP_BLUR_PX)
	queue_redraw()

## Job K: the speed of each streak layer (far / mid / near) — for tests and tuning.
func streak_layers() -> Array:
	var out := {}
	for s in streaks: out[s[2]] = int(out.get(s[2], 0)) + 1
	return out.keys()

func _draw() -> void:
	var S := get_viewport_rect().size
	var c := S * 0.5
	if warp > 0.0:
		draw_rect(Rect2(Vector2.ZERO, S), Color(warp_color.darkened(0.85), warp * 0.85))
		var maxr := S.length() * 0.6
		for s in streaks:
			var a: float = s[0] + t * 0.25
			var spd: float = s[2]
			var ph: float = fmod(s[1] + t * (0.3 + spd) * (0.5 + warp * 1.6), 1.0)
			var r0 := pow(ph, 2.2) * maxr
			var r1 := r0 + (30.0 + 260.0 * warp) * ph * (0.6 + 0.4 * spd)   # points stretched into lines moving outward
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * r0, c + dir * r1, Color(warp_color.lightened(0.3), warp * ph * clampf(0.35 + spd * 0.4, 0.0, 1.0)), float(s[3]) * (0.6 + 1.4 * ph))
		draw_circle(c, 40.0 + 140.0 * warp * (0.8 + 0.2 * sin(t * 9.0)), Color(1, 1, 1, warp * 0.35))
	if heat > 0.0:
		# plasma glow wrapping the nose: warm vignette from the bottom and edges, flickering
		var fl := 0.85 + 0.15 * sin(t * 23.0) * sin(t * 7.0)
		for i in 6:
			var r := S.y * (0.9 - i * 0.12)
			draw_circle(Vector2(c.x, S.y * 1.15), r, Color(1.0, 0.45 + i * 0.07, 0.1, heat * 0.07 * fl))
		for i in 5:
			var w := 40.0 + i * 36.0
			draw_rect(Rect2(Vector2.ZERO, Vector2(w, S.y)), Color(1.0, 0.5, 0.15, heat * 0.035 * fl))
			draw_rect(Rect2(Vector2(S.x - w, 0), Vector2(w, S.y)), Color(1.0, 0.5, 0.15, heat * 0.035 * fl))
			draw_rect(Rect2(Vector2(0, S.y - w), Vector2(S.x, w)), Color(1.0, 0.55, 0.15, heat * 0.05 * fl))
	if clouds > 0.0:
		# cloud puffs rushing outward from the centre, plus an overall haze that becomes a white-out at 1
		draw_rect(Rect2(Vector2.ZERO, S), Color(cloud_tint, clouds * clouds * 0.92))
		for p in puffs:
			var ph: float = fmod(p[1] + t * 0.55 * p[2], 1.0)
			var dir := Vector2(cos(p[0] + t * 0.05), sin(p[0] + t * 0.05))
			var pos := c + dir * pow(ph, 1.6) * S.length() * 0.55
			var sz: float = (80.0 + 520.0 * ph) * float(p[2])
			draw_texture_rect(_puff_tex, Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(cloud_tint * p[3], clouds * minf(1.0, ph * 3.0) * 0.9))
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, S), Color(1, 1, 1, flash * Data.JUMP_FLASH_ALPHA))
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, S), Color(fade_color, fade))
	if caption != "":
		var a2 := clampf(maxf(maxf(fade, warp), maxf(clouds, heat)) * 1.5, 0.0, 1.0)
		draw_string_outline(font, Vector2(0, c.y - 6), caption, HORIZONTAL_ALIGNMENT_CENTER, S.x, 38, 6, Color(0, 0, 0, a2 * 0.8))
		draw_string(font, Vector2(0, c.y - 6), caption, HORIZONTAL_ALIGNMENT_CENTER, S.x, 38, Color(1, 1, 1, a2))
		if sub != "":
			draw_string(font, Vector2(0, c.y + 30), sub, HORIZONTAL_ALIGNMENT_CENTER, S.x, 18, Color(0.6, 0.9, 1.0, a2))
