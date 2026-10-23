shader_type canvas_item;
// Full-screen post pass for big moments: chromatic aberration + a radial
// shockwave ripple. Only enabled (visible) while an effect is live, never on
// the LOW quality profile, and drawn under the HUD so text stays crisp.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// Channel split in UV units (0 = off).
uniform float aberration = 0.0;
// Shockwave in UV space; radius grows from 0 to ~1.2 over the effect.
uniform vec2 wave_center = vec2(0.5, 0.5);
uniform float wave_radius = 0.0;
uniform float wave_strength = 0.0;
uniform float wave_width = 0.09;
// Viewport width / height so the ring stays circular on tall phones.
uniform float aspect = 0.5625;

void fragment() {
	vec2 uv = SCREEN_UV;
	if (wave_strength > 0.0) {
		vec2 d = uv - wave_center;
		d.x *= aspect;
		float dist = length(d);
		float band = 1.0 - smoothstep(0.0, wave_width, abs(dist - wave_radius));
		if (dist > 0.0001) {
			vec2 dir = d / dist;
			dir.x /= aspect;
			uv -= dir * band * wave_strength;
		}
	}
	vec2 split = (uv - vec2(0.5)) * aberration;
	float r = texture(screen_tex, uv + split).r;
	vec4 g = texture(screen_tex, uv);
	float b = texture(screen_tex, uv - split).b;
	COLOR = vec4(r, g.g, b, 1.0);
}
