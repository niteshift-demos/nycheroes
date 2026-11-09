// A thug's wind-up tell: the ground its punch will reach, drawn on a flat 1x1
// plane (scaled to the reach) centered on the thug and turned to face where
// the thug faces (-Z). A faint wedge with a thin rim, and a band sweeping out
// from the thug that reaches the rim when the punch lands (`progress` 0..1).
// Small and unshaded; it has a surface of its own, so it costs the big
// shaders nothing (see ROADMAP.md "Shader compile time").
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.42, 0.12);
// Cosine of the half angle of the wedge (Thug.PUNCH_CONE).
uniform float cone = 0.5;
// How far through the wind-up (0..1): where the sweeping band has got to.
uniform float progress = 0.0;
// Overall opacity, for fading in and out.
uniform float strength = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;  // x right, y toward the thug's back
	float r = length(p);
	float ahead = r > 0.001 ? -p.y / r : 1.0;
	float aa = fwidth(r) * 1.5;
	float inside = smoothstep(cone - 0.04, cone + 0.04, ahead) * (1.0 - smoothstep(1.0 - aa, 1.0, r))
			* smoothstep(0.18, 0.3, r);
	float rim = smoothstep(0.93 - aa, 0.95, r);
	float filled = 1.0 - smoothstep(progress - aa, progress, r);
	float front = smoothstep(progress - 0.12, progress, r) * filled;
	ALBEDO = color;
	ALPHA = inside * strength * (0.1 + 0.12 * filled + 0.35 * front + 0.4 * rim);
}
