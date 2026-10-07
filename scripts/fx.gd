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
# Job AB (v1.4x): one warp effect drawn three ways (numbers in the Job AB config block)
var skin := "tunnel"   # tunnel (jump gate) | cloud (warp gate) | rift (rift gate)
var pace := 0.0        # 0..1: slow .. full speed
var travel := 0.0      # layers passed so far
var spin := 0.0        # turns so far
var jumping := false   # a gate jump is on (the surface tile change reuses plain streaks)
var booms := 0         # layers that made a boom (tests)
var tints: Array = []  # one colour per rift layer, taken from the sky pictures
var _warp_rect: ColorRect
var _sky_a: Texture2D
var _sky_b: Texture2D
const SKINS := ["tunnel", "cloud", "rift"]
const WARP_SHADER := """shader_type canvas_item;
uniform int skin = 0;
uniform float k = 0.0;
uniform float travel = 0.0;
uniform float spin = 0.0;
uniform int layers = 10;
uniform vec3 tints[12];
uniform vec3 color = vec3(0.4, 0.8, 1.0);
uniform sampler2D sky_a : repeat_enable, filter_linear;
uniform sampler2D sky_b : repeat_enable, filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float aspect = 1.78;
uniform float oval = 1.6;
uniform float ragged = 0.3;
uniform float mist = 0.85;
uniform float twist = 0.55;
uniform float bands = 3.0;
uniform float alpha = 0.96;
float nz(vec2 uv) { return textureLod(noise_tex, uv, 0.0).r; }
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = length(p) + 0.0001;
	float th = atan(p.y, p.x) / TAU;
	vec3 col = vec3(0.0);
	if (skin == 0) {
		// energy tube: bands of light corkscrewing toward the viewer, a bright far end
		vec2 tuv = vec2(th * bands + twist * 0.18 / r + spin * 0.25, 0.22 / r + travel * 0.6);
		float n = nz(tuv) * 0.65 + nz(tuv * vec2(2.0, 0.5) + 0.37) * 0.5;
		float b = smoothstep(0.38, 0.9, n);
		vec3 warm = color.brg * 0.6 + color * 0.4;
		col = mix(color * 0.1, mix(color, warm, nz(tuv * 0.5 + 0.2)), b) + vec3(1.0) * pow(b, 5.0) * 0.25;
		col *= 0.35 + 0.9 * smoothstep(0.0, 0.45, r);
		col += mix(color, vec3(1.0), 0.7) * (0.035 / (r * r * 6.0 + 0.04));
	} else if (skin == 1) {
		// gas anomaly: layers of cloud rushing past, far to near
		float f = fract(travel);
		float fl = floor(travel);
		col = color * 0.07;
		for (int j = 0; j < 12; j++) {
			if (j >= layers) break;
			float ph = (f + float(j)) / float(layers);
			float id = mod(float(j) - fl, 12.0);
			float sc = mix(1.5, 0.05, ph);
			float ca = cos(id * 1.7 + spin * 0.3), sa = sin(id * 1.7 + spin * 0.3);
			vec2 q = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) * sc + vec2(id * 0.37, id * 0.11);
			vec2 off = vec2(id * 0.37, id * 0.11);
			float n = (nz(q) + nz((q - off) * 0.9 + off) + nz((q - off) * 0.8 + off)) * 0.3667;   // smeared toward the centre: it rushes at you
			float a = smoothstep(0.42, 0.8, n) * sin(ph * 3.14159) * 0.85;
			col = mix(col, mix(tints[int(id)] * (0.35 + 0.65 * ph), vec3(1.0), 0.5 * smoothstep(0.6, 0.9, n)), a);
		}
		col *= 1.0 - 0.45 * smoothstep(0.35, 1.0, r);
		col += mix(color, vec3(1.0), 0.5) * (0.03 / (r * r * 5.0 + 0.05));
	} else {
		// tear in space: sheets of sky, each with a ragged oval rip, turning opposite ways, far to near
		float f = fract(travel);
		float fl = floor(travel);
		col = tints[0] * 0.05 + vec3(1.0) * (0.01 / (r + 0.03));
		for (int j = 0; j < 12; j++) {
			if (j >= layers) break;
			float ph = (f + float(j)) / float(layers);
			float id = mod(float(j) - fl, 12.0);
			float dir = mod(id, 2.0) < 0.5 ? 1.0 : -1.0;
			float ang = spin * TAU * dir + id * 1.3;
			float ca = cos(ang), sa = sin(ang);
			vec2 q = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);
			q.y *= oval;
			float h = 0.045 * pow(70.0, ph);
			float rr = length(q) / h;
			float qa = atan(q.y, q.x) / TAU;
			float edge = 1.0 + ragged * ((nz(vec2(qa * 2.0, id * 0.13)) - 0.5) * 2.0 + (nz(vec2(qa * 9.0, id * 0.31 + 0.5)) - 0.5) * 0.8);
			vec3 tint = tints[int(id)];
			float seen = smoothstep(0.0, 0.18, ph);
			if (rr > edge) {
				vec2 suv = q / h * 0.07 + vec2(id * 0.173, id * 0.091);
				vec3 sk = dir > 0.0 ? textureLod(sky_a, suv, 0.0).rgb : textureLod(sky_b, suv, 0.0).rgb;
				vec3 sheet = mix(sk, tint * 0.5, 0.22) * (0.5 + 0.5 * ph) + tint * exp(-(rr - edge) * 5.0) * mist;
				col = mix(col, sheet, seen);
			} else {
				col += tint * exp(-(edge - rr) * 9.0) * mist * 0.45 * seen;
			}
		}
	}
	COLOR = vec4(col, clamp(k, 0.0, 1.0) * alpha);
}
"""
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
	_warp_rect = ColorRect.new()
	_warp_rect.name = "WarpEffect"
	_warp_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wm := ShaderMaterial.new()
	wm.shader = Shader.new()
	wm.shader.code = WARP_SHADER
	_warp_rect.material = wm
	_warp_rect.visible = false
	_warp_rect.show_behind_parent = true
	add_child(_warp_rect)
	var wn := FastNoiseLite.new()
	wn.seed = 23
	wn.frequency = 0.035
	wn.fractal_octaves = 3
	wm.set_shader_parameter("noise_tex", ImageTexture.create_from_image(wn.get_seamless_image(128, 128)))
	set_skies(null, null)
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
	_warp_rect.visible = jumping and warp > 0.001
	if _warp_rect.visible:
		var before := int(travel)
		travel += dt * lerpf(Data.WARP_PACE_SLOW, Data.WARP_PACE_FAST, pace)
		spin += dt * lerpf(Data.WARP_SPIN_SLOW, Data.WARP_SPIN_FAST, pace)
		if int(travel) != before and skin != "tunnel" and pace < Data.WARP_BOOM_BELOW:   # a layer went by: the slow booms
			booms += 1
			Sfx.play("whoosh", -5.0)
		var m := _warp_rect.material as ShaderMaterial
		var S2 := get_viewport_rect().size
		m.set_shader_parameter("skin", maxi(SKINS.find(skin), 0))
		m.set_shader_parameter("k", warp)
		m.set_shader_parameter("travel", travel)
		m.set_shader_parameter("spin", spin)
		m.set_shader_parameter("layers", clampi(Data.RIFT_LAYERS if skin == "rift" else Data.CLOUD_LAYERS, 1, 12))
		var wc := Color.from_hsv(warp_color.h, maxf(warp_color.s, Data.WARP_MIN_COLOUR), warp_color.v)   # a near-white star still gives a coloured tube
		m.set_shader_parameter("color", Vector3(wc.r, wc.g, wc.b))
		m.set_shader_parameter("aspect", S2.x / maxf(S2.y, 1.0))
		m.set_shader_parameter("oval", Data.RIFT_OVAL)
		m.set_shader_parameter("ragged", Data.RIFT_RAGGED)
		m.set_shader_parameter("mist", Data.RIFT_MIST)
		m.set_shader_parameter("twist", Data.TUNNEL_TWIST)
		m.set_shader_parameter("bands", Data.TUNNEL_BANDS)
		m.set_shader_parameter("alpha", Data.WARP_ALPHA)
	queue_redraw()

## Job AB: start a warp look from rest.
func begin_warp(look: String) -> void:
	skin = look if look in SKINS else "tunnel"
	jumping = true
	travel = 0.0
	spin = 0.0
	pace = 0.0
	booms = 0

func end_warp() -> void:
	jumping = false
	skin = "tunnel"
	pace = 0.0

## Job AB: the two sky pictures the tear is made of (the system you leave, then the one you reach) and the mist
## colours taken from them. With no picture, the colours come from `fallback`.
func set_skies(a: Texture2D, b: Texture2D, fallback: Array = []) -> void:
	if a != null: _sky_a = a
	if b != null: _sky_b = b
	if _sky_a == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(0.05, 0.07, 0.14))
		_sky_a = ImageTexture.create_from_image(img)
	var tb: Texture2D = _sky_b if _sky_b != null else _sky_a
	var m := _warp_rect.material as ShaderMaterial
	m.set_shader_parameter("sky_a", _sky_a)
	m.set_shader_parameter("sky_b", tb)
	var pa := _picture_colors(_sky_a)
	var pb := _picture_colors(tb)
	var pool: Array = []
	for i in 6:
		if i < pa.size(): pool.append(pa[i])
		if i < pb.size(): pool.append(pb[i])
	for c in fallback: pool.append(c)
	if pool.is_empty(): pool = [Color(0.4, 0.8, 1.0)]
	tints = []
	for i in 12:
		var c: Color = pool[i % pool.size()]
		c = Color.from_hsv(c.h, clampf(maxf(c.s, 0.55), 0.0, 1.0), clampf(maxf(c.v, 0.75), 0.0, 1.0))
		if i > 0 and _hue_gap(c.h, (tints[i - 1] as Color).h) < Data.RIFT_TINT_MIN_HUE:   # never two alike in a row
			c = Color.from_hsv(fposmod((tints[i - 1] as Color).h + 0.27 + 0.11 * (i % 3), 1.0), c.s, c.v)
		tints.append(c)
	if _hue_gap((tints[11] as Color).h, (tints[0] as Color).h) < Data.RIFT_TINT_MIN_HUE:
		tints[11] = Color.from_hsv(fposmod((tints[0] as Color).h + 0.5, 1.0), (tints[11] as Color).s, (tints[11] as Color).v)
		if _hue_gap((tints[11] as Color).h, (tints[10] as Color).h) < Data.RIFT_TINT_MIN_HUE:
			tints[11] = Color.from_hsv(fposmod((tints[0] as Color).h + 0.36, 1.0), (tints[11] as Color).s, (tints[11] as Color).v)
	m.set_shader_parameter("tints", PackedVector3Array(tints.map(func(c: Color): return Vector3(c.r, c.g, c.b))))

func _hue_gap(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 1.0 - d)

## The strongest colours of a picture (up to 6), brightest and most coloured first.
func _picture_colors(tex: Texture2D) -> Array:
	if tex == null: return []
	var img: Image = tex.get_image()
	if img == null or img.is_empty(): return []
	img = img.duplicate()
	if img.is_compressed() and img.decompress() != OK: return []
	img.resize(8, 4, Image.INTERPOLATE_BILINEAR)
	var found: Array = []
	for y in 4:
		for x in 8:
			var c := img.get_pixel(x, y)
			found.append([c.s * (0.3 + c.v), c])
	found.sort_custom(func(p, q): return p[0] > q[0])
	var out: Array = []
	for f in found:
		var c: Color = f[1]
		if c.s < 0.08: continue
		var near := false
		for o in out:
			if _hue_gap(c.h, (o as Color).h) < 0.06: near = true
		if not near: out.append(c)
		if out.size() >= 6: break
	return out

## Job K: the speed of each streak layer (far / mid / near) — for tests and tuning.
func streak_layers() -> Array:
	var out := {}
	for s in streaks: out[s[2]] = int(out.get(s[2], 0)) + 1
	return out.keys()

func _draw() -> void:
	var S := get_viewport_rect().size
	var c := S * 0.5
	if warp > 0.0:
		if not jumping: draw_rect(Rect2(Vector2.ZERO, S), Color(warp_color.darkened(0.85), warp * 0.85))
		var maxr := S.length() * 0.6
		for s in (streaks if skin == "tunnel" else []):   # v1.4x: the tube / cloud / tear itself is drawn by the warp shader
			var a: float = s[0] + t * 0.25
			var spd: float = s[2]
			var ph: float = fmod(s[1] + t * (0.3 + spd) * (0.5 + warp * 1.6), 1.0)
			var r0 := pow(ph, 2.2) * maxr
			var r1 := r0 + (30.0 + 260.0 * warp) * ph * (0.6 + 0.4 * spd)   # points stretched into lines moving outward
			var dir := Vector2(cos(a), sin(a))
			draw_line(c + dir * r0, c + dir * r1, Color(warp_color.lightened(0.3), warp * ph * clampf(0.35 + spd * 0.4, 0.0, 1.0)), float(s[3]) * (0.6 + 1.4 * ph))
		if not jumping: draw_circle(c, 40.0 + 140.0 * warp * (0.8 + 0.2 * sin(t * 9.0)), Color(1, 1, 1, warp * 0.35))
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
