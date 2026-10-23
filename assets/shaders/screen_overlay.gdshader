shader_type canvas_item;
// Cheap full-screen overlay (no screen read): danger vignette + color flash.
// Alpha-blended over the world, under the HUD. Safe on every quality profile.

uniform vec4 vignette_color : source_color = vec4(1.0, 0.1, 0.18, 1.0);
uniform float vignette = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float aspect = 0.5625;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect * 1.6, 1.0) * 2.0;
	float edge = smoothstep(0.55, 1.35, length(p));
	float v_a = edge * vignette;
	vec3 col = vignette_color.rgb;
	float a = v_a;
	// Flash sits on top of the vignette.
	col = mix(col, flash_color.rgb, clamp(flash_color.a / max(a + flash_color.a, 0.0001), 0.0, 1.0));
	a = clamp(a + flash_color.a, 0.0, 1.0);
	COLOR = vec4(col, a);
}
