// Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float drain = 0.0;
uniform float glitch = 0.0;
uniform vec3 tint = vec3(1.0);
uniform float t = 0.0;
uniform float px = 1.0;
void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	if (drain > 0.001) { float l = dot(col, vec3(0.299, 0.587, 0.114)); col = mix(col, vec3(l), drain); }
	col *= tint;
	if (glitch > 0.0) {
		vec2 fc = FRAGCOORD.xy / px;
		vec2 b = floor(fc / vec2(56.0, 18.0));
		float h = fract(sin(dot(b + floor(t * 9.0), vec2(12.9898, 78.233))) * 43758.5453);
		if (h < glitch * 0.2) { vec2 c = floor(fc / 6.0); col = mix(vec3(1.0, 0.0, 1.0), vec3(0.02), mod(c.x + c.y, 2.0)); }
		else if (h < glitch * 0.42) col = col.brg;
		else if (h < glitch * 0.52) col = vec3(1.0) - col;
	}
	COLOR = vec4(col, 1.0);
}
