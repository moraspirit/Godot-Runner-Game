shader_type spatial;
render_mode world_vertex_coords, cull_disabled, blend_mix, depth_draw_opaque, depth_prepass_alpha;

uniform float CURVATURE = 2.0;
uniform float CURVATURE_DISTANCE = 110.0;
uniform vec3 water_deep : source_color = vec3(0.06, 0.20, 0.36);
uniform vec3 water_shallow : source_color = vec3(0.14, 0.42, 0.58);
uniform float water_alpha : hint_range(0.0, 1.0) = 0.82;

varying vec3 wpos;

void vertex() {
	wpos = VERTEX;
	float dist = length(INV_VIEW_MATRIX[3].xyz - VERTEX) / CURVATURE_DISTANCE;
	VERTEX.y -= pow(dist, CURVATURE);
}

void fragment() {
	float ripple = sin(wpos.x * 0.65 + wpos.z * 0.22) * 0.5 + 0.5;
	vec3 col = mix(water_deep, water_shallow, ripple);
	ALBEDO = col;
	ROUGHNESS = 0.18;
	METALLIC = 0.08;
	SPECULAR = 0.35;
	ALPHA = water_alpha;
}
