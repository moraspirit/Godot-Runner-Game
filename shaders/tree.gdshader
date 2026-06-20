shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

uniform float CURVATURE = 2.0;
uniform float CURVATURE_DISTANCE = 110.0;
uniform vec3 leaf_color : source_color = vec3(0.06, 0.26, 0.09);
uniform vec3 leaf_top : source_color = vec3(0.13, 0.36, 0.13);
uniform vec3 trunk_color : source_color = vec3(0.22, 0.13, 0.06);
uniform float tree_height = 6.5;   // world-space height of the tree (set per instance)
uniform float trunk_frac = 0.16;   // bottom fraction that is the woody trunk

varying float h;

void vertex() {
	// VERTEX is in world space (world_vertex_coords); tree base sits at y ~ 0
	h = clamp(VERTEX.y / max(tree_height, 0.001), 0.0, 1.0);
	float dist = length(INV_VIEW_MATRIX[3].xyz - VERTEX) / CURVATURE_DISTANCE;
	VERTEX.y -= pow(dist, CURVATURE);
}

void fragment() {
	vec3 foliage = mix(leaf_color, leaf_top, smoothstep(trunk_frac, 1.0, h));
	vec3 col = mix(trunk_color, foliage, smoothstep(trunk_frac * 0.55, trunk_frac, h));
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
