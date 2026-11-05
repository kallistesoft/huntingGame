// Frosted glass for UI panels: blurs whatever is behind the panel, tints
// it, rounds the corners, adds a hairline light border, a soft sheen and a
// shadow outside the shape. Drawn by GlassBox over a rect grown by `inset`
// on every side so the shadow has room.
shader_type canvas_item;
render_mode blend_mix;

uniform vec4 tint : source_color = vec4(0.04, 0.07, 0.05, 0.55);
uniform float radius : hint_range(0.0, 400.0) = 20.0;
uniform float blur : hint_range(0.0, 6.0) = 3.0; // mip level of the screen copy
uniform float border : hint_range(0.0, 1.0) = 0.16;
uniform float shadow : hint_range(0.0, 1.0) = 0.4;
uniform vec2 rect_size = vec2(100.0, 100.0); // the panel, in canvas pixels
uniform float inset = 14.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 d = abs(p) - half_size + vec2(r);
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2 full = rect_size + vec2(inset * 2.0);
	vec2 p = UV * full - vec2(inset) - rect_size * 0.5;
	float r = min(radius, min(rect_size.x, rect_size.y) * 0.5);
	float d = rounded_box(p, rect_size * 0.5, r);
	float mask = 1.0 - smoothstep(-1.0, 0.6, d);

	// Blur: the screen copy's mip level, plus four taps for a smoother result.
	vec2 px = SCREEN_PIXEL_SIZE * pow(2.0, blur) * 0.75;
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur).rgb * 0.36;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), blur).rgb * 0.16;
	bg += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), blur).rgb * 0.16;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), blur).rgb * 0.16;
	bg += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), blur).rgb * 0.16;

	vec3 col = mix(bg, tint.rgb, tint.a);
	col += vec3(0.05) * (1.0 - smoothstep(0.0, 0.6, UV.y)); // light from above
	float edge = 1.0 - smoothstep(0.0, 1.8, abs(d + 1.2));
	col += vec3(border) * edge;

	float a_shadow = exp(-max(d, 0.0) / (inset * 0.55)) * shadow * (1.0 - mask);
	float a = clamp(mask + a_shadow, 0.0, 1.0);
	vec3 rgb = (col * mask) / max(a, 0.0001);
	COLOR = vec4(rgb, a);
}
