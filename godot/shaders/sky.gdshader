// Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
shader_type sky;
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
	col = mix(col, hor * 0.85, smoothstep(0.0, -0.2, h));
	if (h > 0.0 && cloud > 0.0) {
		vec2 cp = d.xz / (h + 0.12) * 0.22;
		float n = texture(noise, cp + vec2(TIME * 0.004, 0.0)).r * 0.65 + texture(noise, cp * 2.7 - vec2(TIME * 0.006, 0.0)).r * 0.35;
		float cl = smoothstep(0.52, 0.78, n) * smoothstep(0.0, 0.25, h) * cloud;
		col = mix(col, mix(hor, vec3(1.0), 0.75) * (0.85 + 0.25 * n), cl * 0.75);
	}
	float s = max(dot(d, normalize(sundir)), 0.0);
	col += suncol * (pow(s, 900.0) * 3.0 + pow(s, 40.0) * 0.35 + pow(s, 6.0) * 0.12) * sunamt;
	COLOR = col;
}
