// Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert, specular_schlick_ggx;
// The Compatibility renderer shades colours as stored (sRGB); Mobile/Forward shade in linear and
// hand Color/source_color inputs over already linear. These macros give the same picture on both.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define TO_LIN(x) dec(x)
#define FROM_LIN(x) enc(x)
#define VCOL(x) enc(x)
#define SKYOUT(x) (x)
#else
#define TO_LIN(x) (x)
#define FROM_LIN(x) (x)
#define VCOL(x) (x)
#define SKYOUT(x) enc(x)
#endif
global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
uniform vec4 albedo : source_color = vec4(0.18, 0.37, 0.53, 1.0);
uniform float opacity = 0.84;
uniform sampler2D nmap : filter_linear_mipmap, repeat_enable;
uniform vec2 rep = vec2(36.0, 14.0);
uniform float nscale = 0.35;
uniform vec3 fogc : source_color = vec3(0.5);
uniform bool two_sided = false;
vec3 dec(vec3 x) { return x * (x * (x * 0.305306011 + 0.682171111) + 0.012522878); }
vec3 enc(vec3 x) { return max(vec3(1.055) * pow(max(x, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0)); }
void vertex() {
	VERTEX.y += sin(VERTEX.x * 0.35 + TIME * 1.1) * 0.07 + cos(VERTEX.z * 0.45 + TIME * 1.4) * 0.05;
}
void fragment() {
	vec2 uv = UV * rep;
	vec3 m1 = texture(nmap, uv + vec2(TIME * 0.011, -TIME * 0.017)).xyz * 2.0 - 1.0;
	vec3 m2 = texture(nmap, uv * 0.37 + vec2(-TIME * 0.009, TIME * 0.014)).xyz * 2.0 - 1.0;
	m1.xy *= nscale; m2.xy *= nscale;
	vec3 n1 = normalize(vec3(m1.x, m1.z, -m1.y));
	vec3 n2 = normalize(vec3(m2.x, m2.z, -m2.y));
	vec3 wsum = n1 + n2 * 0.5;
	vec3 wn = dot(wsum, wsum) > 1e-8 ? normalize(wsum) : vec3(0.0, 1.0, 0.0);
	if (two_sided && !FRONT_FACING) wn.y = -wn.y;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float fv = clamp(1.0 - abs(dot(normalize(VIEW), NORMAL)), 0.0, 1.0);
	float fr = fv * fv * fv;
	vec3 c = albedo.rgb;
	vec3 alb = mix(c, c * 0.6 + fogc * 0.45, fr * 0.5);
	ALBEDO = alb;
	ROUGHNESS = 0.34;
	SPECULAR = 0.5;
	EMISSION = FROM_LIN(TO_LIN(alb) * mix(hemi_ground, hemi_sky, clamp(wn.y * 0.5 + 0.5, 0.0, 1.0)));
	ALPHA = clamp(mix(opacity, 1.0, fr * 0.4), 0.0, 1.0);
}
