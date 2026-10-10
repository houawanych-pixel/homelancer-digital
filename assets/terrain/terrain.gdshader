shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
// Planet terrain: biome colour comes from the vertex colour (blended across tile borders); detail comes from one
// tiling ground texture + bump maps laid over it in world space, so a coarse height grid still looks rich.
//  - vertex colour alpha = how much of the ground texture's own colour to keep (1 desert/canyon, 0 = grey grit only)
//  - steep slopes get horizontal rock strata and the texture projected from the side (no stretching on cliffs)
//  - two normal maps: fine grit from the texture's own brightness, and big soft "render clouds" noise bumps

uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tex_avg = vec3(0.72, 0.49, 0.31);
uniform float detail_scale = 0.014;   // 1 repeat per ~70 m
uniform float strata = 1.0;           // 1 = layered rock on cliffs (canyon/desert), 0 = plain

// v1.7a: where block regions stand, the smooth ground isn't drawn (rects in tile-local x/z: x0, z0, x1, z1)
uniform float cuts[128];
uniform int cut_n = 0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	for (int i = 0; i < 32; i++) {
		if (i >= cut_n) break;
		if (wpos.x > cuts[i * 4] && wpos.z > cuts[i * 4 + 1] && wpos.x < cuts[i * 4 + 2] && wpos.z < cuts[i * 4 + 3]) discard;
	}
	float slope = clamp((1.0 - wnrm.y) * 2.2, 0.0, 1.0);
	vec2 uv_top = wpos.xz * detail_scale;
	vec2 uv_side = vec2(wpos.x + wpos.z, wpos.y * 1.6) * detail_scale;
	vec3 d_top = mix(texture(detail_tex, uv_top).rgb, texture(detail_tex, uv_top * 0.21 + 0.37).rgb, 0.35);
	vec3 d_side = texture(detail_tex, uv_side).rgb;
	vec3 d = mix(d_top, d_side, slope);
	float lum = dot(d, vec3(0.299, 0.587, 0.114)) / dot(tex_avg, vec3(0.299, 0.587, 0.114));
	vec3 own = d / tex_avg;
	// grit fades out with distance so far slopes don't shimmer like TV static
	float near = clamp(1.0 - length(VERTEX) / 1400.0, 0.2, 1.0);
	lum = mix(1.0, lum, near);
	own = mix(vec3(1.0), own, near);
	vec3 grit = mix(vec3(lum), own, COLOR.a);
	vec3 col = COLOR.rgb * grit;
	// layered rock on cliffs: bands that follow height, wobbling a little
	float band = sin(wpos.y * 0.11 + sin(wpos.x * 0.004) * 2.0) * 0.5 + 0.5;
	float band2 = sin(wpos.y * 0.37 + 1.3) * 0.5 + 0.5;
	vec3 rock = col * mix(vec3(0.9), vec3((0.72 + 0.28 * band) * (0.9 + 0.12 * band2)), 0.25 + 0.75 * strata);
	rock = mix(rock, rock * vec3(1.08, 0.86, 0.74), strata * band * 0.5);
	col = mix(col, rock, slope * mix(0.45, 1.0, strata));
	ALBEDO = col;
	vec3 n1 = texture(detail_nrm, mix(uv_top, uv_side, step(0.5, slope))).rgb;
	vec3 n2 = texture(cloud_nrm, wpos.xz * 0.0022).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.45) * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.4;
	ROUGHNESS = 0.95;
}
