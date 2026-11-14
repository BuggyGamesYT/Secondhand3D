// Secondhand 3D (c) 2026 Buggy Games YT. All rights reserved.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
global uniform vec3 hemi_sky;
global uniform vec3 hemi_ground;
uniform sampler2D tA : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tB : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tC : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tD : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tSplat : filter_linear, repeat_disable;
uniform sampler2D tNoise : filter_linear_mipmap, repeat_enable;
uniform vec4 uSc;
uniform vec4 uBox;
uniform vec3 cA : source_color = vec3(1.0);
uniform vec3 cB : source_color = vec3(1.0);
uniform vec3 cC : source_color = vec3(1.0);
uniform vec3 cD : source_color = vec3(1.0);
vec3 dec(vec3 x) { return x * (x * (x * 0.305306011 + 0.682171111) + 0.012522878); }
vec3 enc(vec3 x) { return max(vec3(1.055) * pow(max(x, vec3(0.0)), vec3(0.416666667)) - vec3(0.055), vec3(0.0)); }
varying vec3 vTW;
varying vec3 vWN;
void vertex() {
	vTW = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vWN = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	vec2 wuv = vTW.xz;
	float mac = texture(tNoise, wuv * 0.011).r;
	float det = texture(tNoise, wuv * 0.29).r - 0.5;
	vec3 base = mix(texture(tA, wuv * uSc.x).rgb, texture(tA, wuv * uSc.x * 0.31 + 0.37).rgb, 0.4) * cA * mix(0.8, 1.16, mac);
	vec3 sp = texture(tSplat, (wuv - uBox.xy) / uBox.zw).rgb;
	vec3 col = base;
	col = mix(col, texture(tB, wuv * uSc.y).rgb * cB, smoothstep(0.32, 0.68, sp.r + det * 0.55));
	col = mix(col, texture(tC, wuv * uSc.z).rgb * cC, smoothstep(0.32, 0.68, sp.g + det * 0.5));
	col = mix(col, texture(tD, wuv * uSc.w).rgb * cD, smoothstep(0.4, 0.6, sp.b + det * 0.25));
	ALBEDO = col;
	ROUGHNESS = 1.0;
	vec3 n = normalize(vWN);
	EMISSION = enc(dec(col) * mix(hemi_ground, hemi_sky, n.y * 0.5 + 0.5));
}
