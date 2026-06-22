extends Node

## Mobile / Web WASM performance budget.
## Based on Godot web export guidance: minimize _process, avoid shadows & heavy
## shaders, use Compatibility renderer, cap FPS, reduce draw calls.

var active: bool = false
var is_web: bool = false


func _ready() -> void:
	is_web = OS.has_feature("web")
	active = _detect_low_end()
	if active:
		Engine.max_fps = max_fps_cap()


func _detect_low_end() -> bool:
	var os := OS.get_name()
	if os == "Android" or os == "iOS":
		return true
	if is_web:
		# WASM is much slower than native; treat all phone browsers as low-end.
		if BrowserBridge.is_mobile_viewport():
			return true
		var w := DisplayServer.window_get_size().x
		return w > 0 and w < 900
	return false


func max_fps_cap() -> int:
	return 40 if active else 0


func apply_render_budget(viewport: Viewport) -> void:
	if not active or viewport == null:
		return
	# Resolution scaling helps GPU on phones (Godot docs: resolution scaling tutorial).
	viewport.scaling_3d_scale = 0.55
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = false


func apply_environment(env: Environment) -> void:
	if not active or env == null:
		return
	env.glow_enabled = false
	env.fog_enabled = false


func use_simple_lane_lines() -> bool:
	return active


func allow_heavy_props() -> bool:
	return not active


func physics_stride() -> int:
	return 2 if active else 1


func env_timer_range() -> Vector2:
	return Vector2(1.15, 1.75) if active else Vector2(0.55, 0.85)


func fence_count() -> int:
	return 28 if active else 64


func initial_side_prop_count() -> int:
	return 4 if active else 10


func initial_tree_count() -> int:
	return 4 if active else 9


func initial_shrub_count() -> int:
	return 2 if active else 5


func use_horizon_fade() -> bool:
	return not active


func extra_tree_chance() -> float:
	return 0.15 if active else 0.5


func shrub_spawn_chance() -> float:
	return 0.28 if active else 0.72


func rotate_coins() -> bool:
	return not active


func road_material_update_stride() -> int:
	return 15 if active else 1


func ground_plane_size() -> Vector2:
	return Vector2(140.0, 180.0) if active else Vector2(220.0, 280.0)


static func simple_water_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.10, 0.34, 0.52, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.35
	m.metallic = 0.05
	return m
