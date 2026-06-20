shader_type spatial;
render_mode world_vertex_coords, cull_disabled;

uniform float CURVATURE = 2.0;
uniform float CURVATURE_DISTANCE = 110.0;
uniform vec3 grass_dark : source_color = vec3(0.03, 0.13, 0.04);
uniform vec3 grass_light : source_color = vec3(0.09, 0.27, 0.10);
uniform vec3 dirt_color : source_color = vec3(0.20, 0.16, 0.10);

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
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = VERTEX;
	float dist = length(INV_VIEW_MATRIX[3].xyz - VERTEX) / CURVATURE_DISTANCE;
	VERTEX.y -= pow(dist, CURVATURE);
}

void fragment() {
	float n = fbm(wpos.xz * 0.13);
	vec3 col = mix(grass_dark, grass_light, smoothstep(0.28, 0.72, n));
	float d = fbm(wpos.xz * 0.045 + vec2(31.0, 17.0));
	col = mix(col, dirt_color, smoothstep(0.80, 0.93, d) * 0.55);
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
