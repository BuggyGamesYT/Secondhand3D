// Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
shader_type sky;
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
#define SKYOUT(x) (x)
#endif
vec3 enc(vec3 x) { return max(vec3(1.055) * pow(max(x, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0)); }
uniform vec3 top : source_color = vec3(0.23, 0.47, 0.75);
uniform vec3 hor : source_color = vec3(0.61, 0.78, 0.89);
uniform vec3 sundir = vec3(-0.42, 0.78, 0.46);
uniform vec3 suncol : source_color = vec3(1.0, 0.94, 0.82);
uniform float sunamt = 1.0;
uniform float cloud = 1.0;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col = mix(hor, top, pow(smoothstep(-0.02, 0.75, h), 0.7));
	// (smoothstep needs edge0 < edge1 on GLES: the reversed form is undefined there)
	col = mix(col, hor * 0.85, 1.0 - smoothstep(-0.2, 0.0, h));
	// clouds: sampled outside any branch (mipmapped sampling inside divergent flow is undefined)
	float hp = max(h, 0.0);
	vec2 cp = d.xz / (hp + 0.12) * 0.22;
	float n = texture(noise, cp + vec2(TIME * 0.004, 0.0)).r * 0.65 + texture(noise, cp * 2.7 - vec2(TIME * 0.006, 0.0)).r * 0.35;
	float cl = smoothstep(0.52, 0.78, n) * smoothstep(0.0, 0.25, h) * clamp(cloud, 0.0, 4.0);
	col = mix(col, mix(hor, vec3(1.0), 0.75) * (0.85 + 0.25 * n), clamp(cl * 0.75, 0.0, 1.0));
	float s = clamp(dot(d, normalize(sundir)), 0.0, 1.0);
	float s6 = s * s * s; s6 *= s6;
	float s40 = pow(s, 40.0);
	float s900 = pow(s, 900.0);
	col += suncol * (s900 * 3.0 + s40 * 0.35 + s6 * 0.12) * sunamt;
	// Compatibility shows these stored values as linear; match that look on Mobile
	COLOR = SKYOUT(max(col, vec3(0.0)));
}
