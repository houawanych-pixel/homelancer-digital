// Shared capital material family (white armour, dark structure, blue glass, amber accents, dark road).
// ONE shader for the whole city kit; each family is the same shader with different uniforms, so the GPU keeps one
// pipeline. Detail is mapped in WORLD space (triplanar, 8 m tiles) so stretched/instanced boxes keep the same panel
// size everywhere and need no UVs. Panel seams, grooves, bolts and vents come from the normal map, not polygons.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 base : source_color = vec4(0.86, 0.87, 0.88, 1.0);
uniform float rough = 0.5;
uniform float metal = 0.15;
uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 1.0);   // emissive colour (glass / lights)
uniform float window_cells = 0.0;   // 1 = light up the window cells from the mask (glass)
uniform float seam_dark = 0.35;     // how much the seams darken the albedo
uniform float tile_m = 8.0;         // metres per texture tile
uniform float detail = 1.0;         // normal-map strength (0 = flat; used by the A/B detail test)
uniform sampler2D panel_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D panel_mask : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = pow(abs(n), vec3(8.0));
	w /= (w.x + w.y + w.z);
	vec2 ux = wpos.zy / tile_m;
	vec2 uy = wpos.xz / tile_m;
	vec2 uz = wpos.xy / tile_m;
	vec3 m = texture(panel_mask, ux).rgb * w.x + texture(panel_mask, uy).rgb * w.y + texture(panel_mask, uz).rgb * w.z;
	// whiteout-blended triplanar normal
	vec3 tx = texture(panel_nrm, ux).xyz * 2.0 - 1.0;
	vec3 ty = texture(panel_nrm, uy).xyz * 2.0 - 1.0;
	vec3 tz = texture(panel_nrm, uz).xyz * 2.0 - 1.0;
	tx.xy *= detail; ty.xy *= detail; tz.xy *= detail;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 wn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float grime = mix(1.0, m.r, 0.6 * detail + 0.2);
	ALBEDO = base.rgb * grime * (1.0 - seam_dark * m.g * detail);
	ROUGHNESS = clamp(rough + (1.0 - m.r) * 0.25, 0.0, 1.0);
	METALLIC = metal;
	EMISSION = glow.rgb * mix(1.0, 0.35 + 1.1 * m.b, window_cells);
}
