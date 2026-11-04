extends CanvasLayer
## v12.4 (owner: "when you cross over the borders ... it should be a brand new effect ... like a static glitch ... the
## screen's glitching out like static TV ... the lines start to zoom up and fade ... it turns white, you hit a static
## noise ... then the static comes back, it refixes, and you are now on the other side"): the border crossing.
## out(): static and tearing build, the picture's lines stretch up and fade, then white with static. back(): the static
## comes back over the new system and the picture fixes itself.

const SHADER := """
shader_type canvas_item;
uniform sampler2D scr : hint_screen_texture, filter_linear;
uniform float amt = 0.0;    // static, tearing, colour split
uniform float zoom = 0.0;   // the lines stretch up from the middle and fade
uniform float white = 0.0;  // the white-out
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float t = TIME;
	float tick = floor(t * 18.0);
	float bands = mix(14.0, 70.0, h(vec2(tick, 3.1)));
	float band = floor(uv.y * bands);
	float hitb = step(0.62 - amt * 0.45, h(vec2(band * 1.7, tick)));
	float tear = (h(vec2(band, tick + 0.5)) - 0.5) * 0.14 * amt * hitb;
	float roll = fract(uv.y * 1.3 - t * 0.9);
	tear += (smoothstep(0.0, 0.04, roll) - smoothstep(0.04, 0.09, roll)) * 0.03 * amt;   // the rolling bar
	float cy = 0.5 + (uv.y - 0.5) * (1.0 - zoom * 0.985);   // rows stretch up and down from the middle line
	vec2 s = vec2(uv.x + tear, cy);
	float ca = 0.006 * amt + 0.025 * zoom;
	vec3 col = vec3(texture(scr, s + vec2(ca, 0.0)).r, texture(scr, s).g, texture(scr, s - vec2(ca, 0.0)).b);
	col *= 1.0 - 0.3 * amt * step(0.5, fract(FRAGCOORD.y * 0.5));                      // scanlines
	float n = h(floor(FRAGCOORD.xy * 0.5) + vec2(t * 61.0, t * 37.0));
	float line = step(0.985 - 0.05 * zoom, h(vec2(floor(FRAGCOORD.y * 0.33), tick)));  // bright streak lines
	col += vec3(line) * (0.35 * amt + 0.6 * zoom);
	col = mix(col, vec3(n), clamp(amt * 0.55 + zoom * 0.25, 0.0, 0.85));               // TV static
	col *= 1.0 - zoom * 0.55 * (1.0 - white);                                          // the stretched lines fade
	col = mix(col, vec3(0.86 + 0.14 * n), white);                                      // white, still hissing
	COLOR = vec4(col, 1.0);
}
"""

var rect: ColorRect
var mat: ShaderMaterial
var amt := 0.0:
	set(v): amt = v; _p("amt", v)
var zoom := 0.0:
	set(v): zoom = v; _p("zoom", v)
var white := 0.0:
	set(v): white = v; _p("white", v)

func _ready() -> void:
	layer = 128   # (over everything, the full-screen button too)
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	visible = false

func _p(k: String, v: float) -> void:
	if mat != null: mat.set_shader_parameter(k, v)

## Static builds, the lines zoom up and fade, white. Returns when the screen is white.
func out() -> void:
	amt = 0.0; zoom = 0.0; white = 0.0
	visible = true
	Sfx.play("border_glitch", 0.0)
	var t := 0.0
	var D := Data.BORDER_GLITCH_OUT
	while t < D:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := t / D
		var flick := 0.25 if randf() < 0.18 else 0.0   # it stutters
		amt = clampf(k / 0.45 + flick, 0.0, 1.0)
		zoom = clampf((k - 0.4) / 0.4, 0.0, 1.0)
		white = clampf((k - 0.72) / 0.28, 0.0, 1.0)
	white = 1.0; zoom = 1.0; amt = 1.0

## The static comes back over the new place and the picture fixes itself.
func back() -> void:
	Sfx.play("border_refix", 0.0)
	var t := 0.0
	var D := Data.BORDER_GLITCH_BACK
	while t < D:
		await get_tree().process_frame
		t += get_process_delta_time()
		var k := t / D
		white = clampf(1.0 - k / 0.2, 0.0, 1.0)
		zoom = clampf(1.0 - k / 0.4, 0.0, 1.0)
		var flick := 0.3 if randf() < 0.15 and k < 0.8 else 0.0
		amt = clampf(1.0 - (k - 0.25) / 0.75 + flick, 0.0, 1.0)
	amt = 0.0; zoom = 0.0; white = 0.0
	visible = false
