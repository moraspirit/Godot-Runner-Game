shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

uniform float CURVATURE = 2.0;
uniform float CURVATURE_DISTANCE = 110.0;
uniform vec3 asphalt : source_color = vec3(0.05, 0.055, 0.062);
uniform vec3 asphalt_worn : source_color = vec3(0.085, 0.088, 0.092);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wpos = VERTEX;
	float dist = length(INV_VIEW_MATRIX[3].xyz - VERTEX) / CURVATURE_DISTANCE;
	VERTEX.y -= pow(dist, CURVATURE);
}

void fragment() {
	// fine grain speckle
	float speck = vnoise(wpos.xz * 9.0);
	vec3 col = asphalt + (speck - 0.5) * 0.03;
	// worn lighter tire tracks at the three lane centres (x = -2, 0, 2)
	float track = 0.0;
	track = max(track, smoothstep(0.55, 0.0, abs(wpos.x + 2.0)));
	track = max(track, smoothstep(0.55, 0.0, abs(wpos.x)));
	track = max(track, smoothstep(0.55, 0.0, abs(wpos.x - 2.0)));
	col = mix(col, asphalt_worn, track * 0.5);
	ALBEDO = col;
	ROUGHNESS = 0.88;
}
