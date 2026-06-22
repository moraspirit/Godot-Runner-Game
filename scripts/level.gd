extends Node

@onready var player: CharacterBody3D = $player_body
@onready var spawn_timer: Timer = $spawn_timer
@onready var spawn_env_timer: Timer = $spawn_env_timer
@onready var spawn_obstacle_timer: Timer = $spawn_obstacle_timer

@onready var coin: PackedScene = preload("res://scenes/coin.tscn")
@onready var fence: PackedScene = preload("res://models/cartoon-assets/fence.tscn")

@onready var line_mat: ShaderMaterial = preload("res://models/linemat.tres")
@onready var asphalt_mat: Material = preload("res://models/road_asphalt.tres")
@onready var black_road_mat: Material = preload("res://models/road_black.tres")
@onready var carpet_mat: Material = preload("res://models/road_carpet.tres")

@onready var env_move_script = preload("res://scripts/env_script.gd")

const NATURE_TREES: Array = [
	"res://models/nature/PineTrees.glb",
	"res://models/nature/Trees.glb",
]
const NATURE_SHRUBS: Array = [
	"res://models/nature/Bushes.glb",
]
const NATURE_ROCKS: Array = [
	"res://models/nature/Rocks.glb",
]

var tree_templates: Array = []
var shrub_templates: Array = []
var rock_templates: Array = []

var _last_tree: int = -1
var _last_rock: int = -1

const LANE_SCROLL_SPEED: float = 15.0
var line_scroll: float = 0.0
var run_distance: float = 0.0
const KM_LENGTH: float = 1000.0

# Road edge lines sit at ±3.1 — keep all scenery outside this band.
const ROAD_EDGE_X: float = 3.1
const ROAD_SHOULDER: float = 2.4
const ROAD_KEEP_OUT_X: float = ROAD_EDGE_X + ROAD_SHOULDER

const WorldScroller = preload("res://scripts/world_scroller.gd")

var startz: float = -WorldScroller.SPAWN_AHEAD

var road_spawnx: Array = [-2, 0, 2]

const FENCE_SPACING: float = 1.5
var fences: Array = []

# scrolling road strips — material set by 1 km zones (see _road_material_for_distance)
const ROAD_SEGMENT_LEN: float = 5.0
const ROAD_SEGMENT_COUNT: int = 28
var road_segments: Array = []

# roadside street-name boards
var street_names: Array = [
	"Lagaan", "Girl's Hostel", "Boat Yard", "Civil Dep", "Thunmulla",
	"Seetha Gangula", "Sumanadasa", "Steel Building", "Basketball Court",
]
var sign_index: int = 0
var sign_timer: Timer
var sign_post_mat: StandardMaterial3D
var sign_pole_mat: StandardMaterial3D
var sign_frame_mat: StandardMaterial3D
var sign_reflector_mat: StandardMaterial3D

# concert boards spawn further down the road so they pass after the Lagaan sign
const CONCERT_ROAD_GAP: float = 38.0
const BOAT_YARD_LAKE_GAP: float = 34.0
const BOAT_YARD_SEGMENT_LENGTH: float = 150.0

var _boat_yard_mover: Node3D = null
var _boat_yard_start_distance: float = -1.0

var _segment_start_distance: float = 0.0
var _segment_spawns: Array = []
var _next_spawn_idx: int = 0
var _checkpoint_busy: bool = false
var _world_frozen: bool = false

const BGM := preload("res://sounds/background-music.mp3")

var _bgm_player: AudioStreamPlayer


func _ready():
	add_to_group("level")
	WorldScroller.reset_registry()
	MobilePerf.apply_render_budget(get_viewport())
	if MobilePerf.active:
		_apply_mobile_graphics()
	_load_nature()
	_setup_road_segments()
	_setup_signs()
	var env_range := MobilePerf.env_timer_range()
	spawn_env_timer.wait_time = randf_range(env_range.x, env_range.y)

	if SimConstants.SECURE_SPAWNS:
		spawn_timer.stop()
		spawn_obstacle_timer.stop()
		randomize()
		if not RunSession.checkpoint_resolved.is_connected(_on_checkpoint_resolved):
			RunSession.checkpoint_resolved.connect(_on_checkpoint_resolved)
		call_deferred("_boot_secure_segment")
	else:
		randomize()

	var z_start: float = 6.0
	var z_end: float = -WorldScroller.SPAWN_AHEAD
	var fence_count: int = MobilePerf.fence_count()
	var z_step: float = (z_start - z_end) / float(maxi(fence_count - 1, 1))
	for i in fence_count:
		var fence_inst = fence.instantiate()
		fence_inst.connect("body_entered", Callable(self, "fence_area_body_entered"))
		fences.append(fence_inst)
		add_child(fence_inst)
		fence_inst.global_transform.origin = Vector3(0, 0, z_start - float(i) * z_step)

	_setup_bgm()
	call_deferred("_populate_initial_side_world")


func _setup_bgm() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BackgroundMusic"
	_bgm_player.stream = BGM
	_bgm_player.volume_db = -10.0
	add_child(_bgm_player)


func begin_run() -> void:
	if _bgm_player and not _bgm_player.playing:
		_bgm_player.play()


func _boot_secure_segment() -> void:
	if player == null:
		return
	RunSession.ensure_segment_for_level(player.current_lane)
	_init_secure_segment()


func get_segment_distance() -> float:
	return run_distance - _segment_start_distance


func _game_stopped() -> bool:
	if player == null:
		return true
	if not player.game_started:
		return true
	return player.is_dead or player.game_over


func is_world_active() -> bool:
	return not _game_stopped()


func freeze_world() -> void:
	if _world_frozen:
		return
	_world_frozen = true
	spawn_timer.stop()
	spawn_env_timer.stop()
	spawn_obstacle_timer.stop()
	if sign_timer:
		sign_timer.stop()
	if _bgm_player and _bgm_player.playing:
		_bgm_player.stop()
	for c in get_tree().get_nodes_in_group("coins"):
		if is_instance_valid(c):
			_halt_node(c)
			var coin_area: Area3D = c.get_node_or_null("Area3D") as Area3D
			if coin_area:
				coin_area.monitoring = false
				coin_area.monitorable = false
	for n in get_tree().get_nodes_in_group("scrollers"):
		if is_instance_valid(n):
			_halt_node(n)


func _halt_node(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		if child is Timer:
			(child as Timer).stop()


func _init_secure_segment() -> void:
	_segment_spawns = SegmentMapGen.generate(RunSession.current_seed)
	_next_spawn_idx = 0
	_segment_start_distance = run_distance
	_checkpoint_busy = false
	_clear_gameplay_spawns()


func _clear_gameplay_spawns() -> void:
	for n in get_tree().get_nodes_in_group("coins"):
		if is_instance_valid(n):
			n.queue_free()
	for n in get_tree().get_nodes_in_group("rocks"):
		if is_instance_valid(n):
			n.queue_free()


func _process_secure_spawns() -> void:
	var d: float = get_segment_distance()
	while _next_spawn_idx < _segment_spawns.size():
		var entry: Dictionary = _segment_spawns[_next_spawn_idx]
		if d + SimConstants.SPAWN_LEAD < float(entry.distance):
			break
		_spawn_map_entry(entry)
		_next_spawn_idx += 1


func _spawn_map_entry(entry: Dictionary) -> void:
	match String(entry.get("kind", "")):
		"coin":
			_spawn_seeded_coin(entry)
		"rock":
			_spawn_seeded_rock(entry)


func _spawn_seeded_coin(entry: Dictionary) -> void:
	var coin_inst: MeshInstance3D = coin.instantiate()
	add_child(coin_inst)
	coin_inst.set_meta("object_id", int(entry.object_id))
	coin_inst.set_meta("spawn_lane", int(entry.lane))
	coin_inst.set_meta("map_distance", float(entry.distance))
	coin_inst.global_transform.origin = Vector3(
		road_spawnx[int(entry.lane)],
		1.0,
		SimConstants.SPAWN_Z
	)


func _spawn_seeded_rock(entry: Dictionary) -> void:
	if rock_templates.is_empty():
		return
	var rng := SeededRng.new(int(entry.object_id) + RunSession.current_seed)
	var idx: int = rng.randi_mod(rock_templates.size())
	var mover := _make_mover(rock_templates[idx], false)
	mover.add_to_group("rocks")
	mover.set_meta("object_id", int(entry.object_id))
	mover.set_meta("spawn_lane", int(entry.lane))
	mover.set_meta("map_distance", float(entry.distance))
	add_child(mover)
	mover.global_transform.origin = Vector3(road_spawnx[int(entry.lane)], 0.0, SimConstants.SPAWN_Z)
	mover.rotation.y = rng.randf() * TAU
	var rs: float = rng.randf_range(0.85, 1.1)
	mover.scale = Vector3(rs, rs * 0.52, rs)


func _lane_index_from_x(x: float) -> int:
	var best: int = 0
	var best_d: float = INF
	for i in SimConstants.LANE_X.size():
		var d: float = absf(x - float(SimConstants.LANE_X[i]))
		if d < best_d:
			best_d = d
			best = i
	return best


func _on_checkpoint_resolved(accepted: bool, _data: Dictionary) -> void:
	_checkpoint_busy = false
	if not accepted:
		return
	if player == null or player.is_dead or player.game_over:
		return
	RunSession.apply_next_segment(player.current_lane)
	_init_secure_segment()


func _try_segment_checkpoint() -> void:
	if _checkpoint_busy or player == null or player.is_dead or player.game_over:
		return
	if get_segment_distance() < SimConstants.SEGMENT_LENGTH:
		return
	_checkpoint_busy = true
	RunSession.submit_checkpoint(MoveLog.finish_distance(get_segment_distance()))


func _setup_road_segments() -> void:
	var z: float = -ROAD_SEGMENT_LEN * ROAD_SEGMENT_COUNT * 0.5
	for i in ROAD_SEGMENT_COUNT:
		var seg := MeshInstance3D.new()
		seg.name = "road_seg_%d" % i
		var pm := PlaneMesh.new()
		pm.size = Vector2(6.4, ROAD_SEGMENT_LEN)
		seg.mesh = pm
		seg.material_override = asphalt_mat
		seg.position = Vector3(0.0, 0.02, z)
		add_child(seg)
		road_segments.append(seg)
		z += ROAD_SEGMENT_LEN


func _setup_signs() -> void:
	sign_pole_mat = StandardMaterial3D.new()
	sign_pole_mat.albedo_color = Color(0.42, 0.44, 0.48)
	sign_pole_mat.metallic = 0.72
	sign_pole_mat.roughness = 0.38

	sign_post_mat = StandardMaterial3D.new()
	sign_post_mat.albedo_color = Color(0.04, 0.22, 0.12)
	sign_post_mat.roughness = 0.55
	sign_post_mat.metallic = 0.08

	sign_frame_mat = StandardMaterial3D.new()
	sign_frame_mat.albedo_color = Color(0.94, 0.95, 0.93)
	sign_frame_mat.roughness = 0.35
	sign_frame_mat.metallic = 0.15

	sign_reflector_mat = StandardMaterial3D.new()
	sign_reflector_mat.albedo_color = Color(0.95, 0.78, 0.12)
	sign_reflector_mat.emission_enabled = true
	sign_reflector_mat.emission = Color(0.9, 0.7, 0.1)
	sign_reflector_mat.emission_energy_multiplier = 0.35
	sign_reflector_mat.metallic = 0.4
	sign_reflector_mat.roughness = 0.25

	sign_timer = Timer.new()
	sign_timer.name = "sign_timer"
	sign_timer.wait_time = 8.0
	sign_timer.autostart = true
	sign_timer.timeout.connect(_on_sign_timer)
	add_child(sign_timer)


func _on_sign_timer() -> void:
	if _game_stopped():
		return
	var name: String = street_names[sign_index]
	if name == "Lagaan":
		_spawn_sign("Lagaan")
		_spawn_concert_boards()
		sign_index = (sign_index + 1) % street_names.size()
		var concert_z: float = startz - CONCERT_ROAD_GAP
		var concert_travel: float = abs(concert_z) / LANE_SCROLL_SPEED
		sign_timer.wait_time = concert_travel + 4.0
		return
	if name == "Boat Yard":
		_spawn_sign("Boat Yard")
		_spawn_boat_yard_lake()
		sign_index = (sign_index + 1) % street_names.size()
		sign_timer.wait_time = randf_range(14.0, 18.0)
		return
	_spawn_sign(name)
	sign_index = (sign_index + 1) % street_names.size()
	sign_timer.wait_time = randf_range(7.5, 11.0)


func _spawn_concert_boards() -> void:
	var z_pos: float = startz - CONCERT_ROAD_GAP
	_spawn_epilogue_arch(z_pos)
	_spawn_concert_side(-5.5, z_pos, "CONCERT", "28 JULY", 22.0, 14.0)
	_spawn_concert_side(5.5, z_pos, "LIVE MUSIC", "28 JULY", -22.0, 14.0)


func _spawn_boat_yard_lake() -> void:
	_boat_yard_start_distance = run_distance
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_boat_yard_mover = _spawn_boat_yard_lake_piece(startz - BOAT_YARD_LAKE_GAP, rng)
	_clear_left_scenery_for_boat_yard_start()


func _spawn_boat_yard_lake_piece(z_center: float, rng: RandomNumberGenerator) -> Node3D:
	var prop: Node3D = SideScenery.create_boat_yard_lake(rng)
	var mover := Node3D.new()
	mover.set_script(env_move_script)
	mover.set_meta("lifetime", 62.0)
	mover.set_meta("side_kind", "lake")
	mover.add_child(prop)
	add_child(mover)
	mover.global_transform.origin = Vector3(-7.3, 0.04, z_center)
	return mover


func _is_boat_yard_active() -> bool:
	if _boat_yard_start_distance < 0.0:
		return false
	return run_distance <= _boat_yard_start_distance + BOAT_YARD_SEGMENT_LENGTH


func _is_boat_yard_scenery(node: Node) -> bool:
	if node == _boat_yard_mover:
		return true
	if _boat_yard_mover != null and is_instance_valid(_boat_yard_mover) and _boat_yard_mover.is_ancestor_of(node):
		return true
	var kind: String = str(node.get_meta("side_kind", ""))
	return kind in ["lake", "boat"]


const _BOAT_YARD_LEFT_BLOCK_KINDS: Array = [
	"building", "tower", "shop", "cluster", "shed", "tree", "shrub", "car", "human", "river", "bridge",
]


func _manage_boat_yard_left_scenery() -> void:
	if not _is_boat_yard_active() or player == null:
		return
	var pz: float = player.global_transform.origin.z
	for n in get_tree().get_nodes_in_group("scrollers"):
		if not is_instance_valid(n):
			continue
		if _is_boat_yard_scenery(n):
			continue
		var kind: String = str(n.get_meta("side_kind", ""))
		if kind not in _BOAT_YARD_LEFT_BLOCK_KINDS:
			continue
		var pos: Vector3 = n.global_transform.origin
		if pos.x > -5.5:
			continue
		# Hide before they reach the runner — never pop-delete in front of the camera.
		if pos.z > pz - 8.0 and pos.z < pz + 50.0:
			n.visible = false
		if pos.z < pz - 18.0:
			n.queue_free()


func _clear_left_scenery_for_boat_yard_start() -> void:
	var z_center: float = startz - BOAT_YARD_LAKE_GAP
	for n in get_tree().get_nodes_in_group("scrollers"):
		if not is_instance_valid(n):
			continue
		if _is_boat_yard_scenery(n):
			continue
		var kind: String = str(n.get_meta("side_kind", ""))
		if kind not in _BOAT_YARD_LEFT_BLOCK_KINDS:
			continue
		var pos: Vector3 = n.global_transform.origin
		if pos.x > -5.5:
			continue
		if abs(pos.z - z_center) > 58.0:
			continue
		n.queue_free()


func _side_spawn_min_x(kind: String) -> float:
	match kind:
		"human", "lamp", "bench", "car":
			return ROAD_KEEP_OUT_X + 1.2
		"boat":
			return ROAD_KEEP_OUT_X + 2.5
		"building", "shop", "shed", "tower":
			return ROAD_KEEP_OUT_X + 4.5
		"cluster", "river", "bridge":
			return ROAD_KEEP_OUT_X + 5.5
		"shrub":
			return ROAD_KEEP_OUT_X + 3.0
		"tree":
			return ROAD_KEEP_OUT_X + 4.0
		_:
			return ROAD_KEEP_OUT_X + 3.5


func _side_spawn_max_x(_kind: String) -> float:
	return 20.0


func _road_clearance_for_kind(kind: String) -> float:
	return _side_spawn_min_x(kind) - 0.75


func _purge_road_intrusions() -> void:
	const PURGE_KINDS: Array = [
		"building", "tower", "shop", "cluster", "shed", "bridge", "river",
		"car", "human", "bench", "lamp", "tree", "shrub", "boat",
	]
	for n in get_tree().get_nodes_in_group("scrollers"):
		if not is_instance_valid(n):
			continue
		var kind: String = str(n.get_meta("side_kind", ""))
		if kind not in PURGE_KINDS:
			continue
		var pos: Vector3 = n.global_transform.origin
		if _is_boat_yard_active() and pos.x < 0.0:
			continue
		var limit: float = _road_clearance_for_kind(kind)
		if abs(pos.x) < limit:
			n.queue_free()


func _spawn_epilogue_arch(z: float) -> void:
	# decorative gateway over the road — no collision, the boy runs straight under it
	var root := Node3D.new()
	root.set_script(env_move_script)
	root.set_meta("lifetime", 14.0)
	root.set_meta("side_kind", "concert")
	add_child(root)
	root.global_transform.origin = Vector3(0.0, 0.0, z)

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.78, 0.18)
	gold.metallic = 0.65
	gold.roughness = 0.28
	gold.emission_enabled = true
	gold.emission = Color(0.85, 0.62, 0.08)
	gold.emission_energy_multiplier = 0.4

	var banner := StandardMaterial3D.new()
	banner.albedo_color = Color(0.42, 0.07, 0.52)
	banner.emission_enabled = true
	banner.emission = Color(0.32, 0.04, 0.4)
	banner.emission_energy_multiplier = 0.5
	banner.roughness = 0.42

	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.9, 0.2, 0.36)
	accent.emission_enabled = true
	accent.emission = Color(0.7, 0.1, 0.26)
	accent.emission_energy_multiplier = 0.45

	const POST_X: float = 3.45
	const POST_H: float = 3.65
	const BEAM_Y: float = 3.72

	for side_x in [-POST_X, POST_X]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.28, POST_H, 0.28)
		post.mesh = pm
		post.material_override = sign_pole_mat
		post.position = Vector3(side_x, POST_H * 0.5, 0.0)
		root.add_child(post)

		var cap := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.42, 0.18, 0.42)
		cap.mesh = cm
		cap.material_override = gold
		cap.position = Vector3(side_x, POST_H + 0.06, 0.0)
		root.add_child(cap)

	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(7.35, 0.32, 0.34)
	beam.mesh = bm
	beam.material_override = gold
	beam.position = Vector3(0.0, BEAM_Y, 0.0)
	root.add_child(beam)

	var sign_panel := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(6.8, 1.15, 0.1)
	sign_panel.mesh = sm
	sign_panel.material_override = banner
	sign_panel.position = Vector3(0.0, BEAM_Y + 0.72, 0.0)
	root.add_child(sign_panel)

	var sign_frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(7.05, 1.38, 0.07)
	sign_frame.mesh = fm
	sign_frame.material_override = gold
	sign_frame.position = Vector3(0.0, BEAM_Y + 0.72, -0.03)
	root.add_child(sign_frame)

	for i in range(9):
		var bulb := MeshInstance3D.new()
		var bulb_mesh := SphereMesh.new()
		bulb_mesh.radius = 0.065
		bulb_mesh.height = 0.13
		bulb.mesh = bulb_mesh
		var bulb_mat := StandardMaterial3D.new()
		bulb_mat.albedo_color = Color(1.0, 0.9, 0.4) if i % 2 == 0 else Color(0.5, 0.82, 1.0)
		bulb_mat.emission_enabled = true
		bulb_mat.emission = bulb_mat.albedo_color
		bulb_mat.emission_energy_multiplier = 1.15
		bulb.material_override = bulb_mat
		bulb.position = Vector3(-3.2 + i * 0.8, BEAM_Y - 0.12, 0.0)
		root.add_child(bulb)

	var ribbon := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(7.1, 0.14, 0.06)
	ribbon.mesh = rm
	ribbon.material_override = accent
	ribbon.position = Vector3(0.0, BEAM_Y + 1.38, 0.05)
	root.add_child(ribbon)

	var title := Label3D.new()
	title.text = "EPILOGUE"
	title.font_size = 130
	title.pixel_size = 0.0054
	title.modulate = Color(1, 1, 1)
	title.outline_size = 18
	title.outline_modulate = Color(0.12, 0.02, 0.18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector3(0.0, BEAM_Y + 0.72, 0.12)
	root.add_child(title)

	var subtitle := Label3D.new()
	subtitle.text = "28 JULY"
	subtitle.font_size = 72
	subtitle.pixel_size = 0.004
	subtitle.modulate = Color(1.0, 0.88, 0.32)
	subtitle.outline_size = 10
	subtitle.outline_modulate = Color(0.15, 0.04, 0.22)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector3(0.0, BEAM_Y + 0.38, 0.1)
	root.add_child(subtitle)


func _spawn_concert_side(x: float, z: float, title: String, date_line: String, rot_y: float, lifetime: float) -> void:
	var root := Node3D.new()
	root.set_script(env_move_script)
	root.set_meta("lifetime", lifetime)
	root.set_meta("side_kind", "concert")
	add_child(root)
	root.global_transform.origin = Vector3(x, 0.0, z)
	_add_concert_sign(root, title, date_line, rot_y)


func _spawn_sign(text: String) -> Node3D:
	var root := Node3D.new()
	root.set_script(env_move_script)
	root.set_meta("lifetime", 10.0)
	root.set_meta("side_kind", "sign")
	add_child(root)
	root.global_transform.origin = Vector3(-5.2, 0.0, startz)
	_add_street_sign(root, text, Vector3.ZERO, 22.0)
	return root


func _add_street_sign(root: Node3D, text: String, pos: Vector3, rot_y: float) -> void:
	var mount := Node3D.new()
	mount.position = pos
	mount.rotation_degrees.y = rot_y
	root.add_child(mount)
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.055
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 3.35
	pole.mesh = pole_mesh
	pole.material_override = sign_pole_mat
	pole.position = Vector3(0.0, 1.675, 0.0)
	mount.add_child(pole)

	# base plate
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.22
	base_mesh.bottom_radius = 0.26
	base_mesh.height = 0.08
	base.mesh = base_mesh
	base.material_override = sign_pole_mat
	base.position = Vector3(0.0, 0.04, 0.0)
	mount.add_child(base)

	# yellow reflector strip on pole (real roadside detail)
	var reflector := MeshInstance3D.new()
	var ref_mesh := BoxMesh.new()
	ref_mesh.size = Vector3(0.14, 0.22, 0.04)
	reflector.mesh = ref_mesh
	reflector.material_override = sign_reflector_mat
	reflector.position = Vector3(0.08, 0.55, 0.0)
	mount.add_child(reflector)

	# white outer frame
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(3.85, 1.05, 0.07)
	frame.mesh = frame_mesh
	frame.material_override = sign_frame_mat
	frame.position = Vector3(0.0, 3.15, 0.0)
	mount.add_child(frame)

	# green sign face
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(3.55, 0.82, 0.09)
	board.mesh = board_mesh
	board.material_override = sign_post_mat
	board.position = Vector3(0.0, 3.15, 0.02)
	mount.add_child(board)

	var label := Label3D.new()
	label.text = text.to_upper()
	label.font_size = 120
	label.pixel_size = 0.0055
	label.modulate = Color(1, 1, 1)
	label.outline_size = 18
	label.outline_modulate = Color(0.02, 0.08, 0.05)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var approx_w: float = float(text.length()) * label.font_size * label.pixel_size * 0.58
	if approx_w > 3.2:
		label.pixel_size *= 3.2 / approx_w
	label.position = Vector3(0.0, 3.15, 0.08)
	mount.add_child(label)


func _add_concert_sign(root: Node3D, title: String, date_line: String, rot_y: float) -> void:
	root.rotation_degrees.y = rot_y

	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.78, 0.18)
	gold.metallic = 0.65
	gold.roughness = 0.28
	gold.emission_enabled = true
	gold.emission = Color(0.85, 0.62, 0.08)
	gold.emission_energy_multiplier = 0.45

	var banner := StandardMaterial3D.new()
	banner.albedo_color = Color(0.45, 0.08, 0.55)
	banner.emission_enabled = true
	banner.emission = Color(0.35, 0.05, 0.42)
	banner.emission_energy_multiplier = 0.55
	banner.roughness = 0.4

	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.92, 0.22, 0.38)
	accent.emission_enabled = true
	accent.emission = Color(0.75, 0.12, 0.28)
	accent.emission_energy_multiplier = 0.5

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 4.1
	pole.mesh = pole_mesh
	pole.material_override = sign_pole_mat
	pole.position = Vector3(0.0, 2.05, 0.0)
	root.add_child(pole)

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.28
	base_mesh.bottom_radius = 0.34
	base_mesh.height = 0.1
	base.mesh = base_mesh
	base.material_override = gold
	base.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(base)

	for i in range(5):
		var flag := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.55, 0.38, 0.03)
		flag.mesh = fm
		flag.material_override = gold if i % 2 == 0 else accent
		flag.position = Vector3(-1.1 + i * 0.55, 4.35, 0.0)
		flag.rotation_degrees.z = -18.0 if i % 2 == 0 else 18.0
		root.add_child(flag)

	for i in range(7):
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.07
		bm.height = 0.14
		bulb.mesh = bm
		var bulb_mat := StandardMaterial3D.new()
		bulb_mat.albedo_color = Color(1.0, 0.92, 0.45) if i % 2 == 0 else Color(0.55, 0.85, 1.0)
		bulb_mat.emission_enabled = true
		bulb_mat.emission = bulb_mat.albedo_color
		bulb_mat.emission_energy_multiplier = 1.2
		bulb.material_override = bulb_mat
		bulb.position = Vector3(-1.5 + i * 0.5, 4.05, 0.12)
		root.add_child(bulb)

	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(4.35, 1.35, 0.08)
	frame.mesh = frame_mesh
	frame.material_override = gold
	frame.position = Vector3(0.0, 3.55, 0.0)
	root.add_child(frame)

	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(4.05, 1.05, 0.1)
	board.mesh = board_mesh
	board.material_override = banner
	board.position = Vector3(0.0, 3.55, 0.02)
	root.add_child(board)

	for side in [-1, 1]:
		var ribbon := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.18, 1.2, 0.04)
		ribbon.mesh = rm
		ribbon.material_override = accent
		ribbon.position = Vector3(side * 2.18, 3.55, 0.04)
		root.add_child(ribbon)

	var title_label := Label3D.new()
	title_label.text = title.to_upper()
	title_label.font_size = 100
	title_label.pixel_size = 0.005
	title_label.modulate = Color(1, 1, 1)
	title_label.outline_size = 16
	title_label.outline_modulate = Color(0.15, 0.02, 0.2)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector3(0.0, 3.62, 0.1)
	root.add_child(title_label)

	var date_label := Label3D.new()
	date_label.text = date_line.to_upper()
	date_label.font_size = 88
	date_label.pixel_size = 0.0046
	date_label.modulate = Color(1.0, 0.88, 0.35)
	date_label.outline_size = 14
	date_label.outline_modulate = Color(0.2, 0.05, 0.3)
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date_label.position = Vector3(0.0, 3.28, 0.1)
	root.add_child(date_label)


func _load_nature() -> void:
	_collect(NATURE_TREES, tree_templates)
	_collect(NATURE_SHRUBS, shrub_templates)
	_collect(NATURE_ROCKS, rock_templates)
	# medium-sized rocks — visible on the road but still jumpable
	rock_templates = rock_templates.filter(func(t: MeshInstance3D) -> bool:
		return t.get_meta("height", 99.0) <= 1.25
	)


func _collect(paths: Array, into: Array) -> void:
	for p in paths:
		if not ResourceLoader.exists(p):
			continue
		var inst: Node = (load(p) as PackedScene).instantiate()
		add_child(inst)
		var meshes: Array = []
		_gather_meshes(inst, meshes)
		for m in meshes:
			var tpl := MeshInstance3D.new()
			tpl.mesh = m.mesh
			for si in m.get_surface_override_material_count():
				var om = m.get_surface_override_material(si)
				if om:
					tpl.set_surface_override_material(si, om)
			var gt: Transform3D = m.global_transform
			gt.origin = Vector3.ZERO
			tpl.transform = gt
			var h: float = tpl.get_aabb().size.y
			tpl.set_meta("height", h)
			into.append(tpl)
		remove_child(inst)
		inst.free()


func _gather_meshes(n: Node, into: Array) -> void:
	if n is MeshInstance3D:
		into.append(n)
	for c in n.get_children():
		_gather_meshes(c, into)


func _make_mover(template: MeshInstance3D, horizon_fade: bool = true) -> Node3D:
	var mover := Node3D.new()
	mover.set_script(env_move_script)
	mover.set_meta("horizon_fade", horizon_fade and MobilePerf.use_horizon_fade())
	mover.add_child(template.duplicate())
	return mover


func fence_area_body_entered():
	if _game_stopped():
		return
	var first_fence = fences.front()
	var player_z: float = player.global_transform.origin.z if player else 0.0
	var tail_z: float = _furthest_fence_z() - FENCE_SPACING
	var spawn_z: float = minf(tail_z, player_z - WorldScroller.SPAWN_AHEAD)
	first_fence.global_transform.origin = Vector3(0, 0, spawn_z)
	fences.pop_front()
	fences.append(first_fence)


func _furthest_fence_z() -> float:
	var min_z: float = INF
	for f in fences:
		if is_instance_valid(f):
			min_z = minf(min_z, f.global_transform.origin.z)
	return min_z if min_z != INF else -WorldScroller.SPAWN_AHEAD


func _on_spawn_timer_timeout():
	if _game_stopped():
		return
	spawn_timer.wait_time = randf_range(1.2, 2.2)
	var lane_idx: int = randi() % 3
	var count: int = 4 + (randi() % 5)
	for i in count:
		var coin_inst: MeshInstance3D = coin.instantiate()
		add_child(coin_inst)
		coin_inst.global_transform.origin = Vector3(
			road_spawnx[lane_idx],
			1.0,
			startz + i * 2.5
		)


func _apply_mobile_graphics() -> void:
	var sun := get_node_or_null("sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = false
	var fill := get_node_or_null("fill") as DirectionalLight3D
	if fill:
		fill.visible = false
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		MobilePerf.apply_environment(world_env.environment)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.07, 0.20, 0.08)
	grass.roughness = 1.0
	$planet.material_override = grass
	var ground_mesh := $planet.mesh as PlaneMesh
	if ground_mesh:
		ground_mesh.size = MobilePerf.ground_plane_size()
	if MobilePerf.use_simple_lane_lines():
		var lane := StandardMaterial3D.new()
		lane.albedo_color = Color(0.86, 0.84, 0.72)
		lane.emission_enabled = true
		lane.emission = Color(0.86, 0.84, 0.72) * 0.18
		$line_left.material_override = lane
		$line_right.material_override = lane
		var edge := StandardMaterial3D.new()
		edge.albedo_color = Color(0.92, 0.90, 0.82)
		$edge_left.material_override = edge
		$edge_right.material_override = edge


func _on_spawn_env_timer_timeout():
	if _game_stopped():
		return
	var env_range := MobilePerf.env_timer_range()
	spawn_env_timer.wait_time = randf_range(env_range.x, env_range.y)
	_spawn_tree(1)
	_spawn_tree(-1)
	if randf() < MobilePerf.extra_tree_chance():
		_spawn_tree(1)
	if randf() < MobilePerf.extra_tree_chance():
		_spawn_tree(-1)
	if randf() < MobilePerf.shrub_spawn_chance():
		_spawn_shrub(1)
	if randf() < MobilePerf.shrub_spawn_chance():
		_spawn_shrub(-1)
	_spawn_side_props(1)
	_spawn_side_props(-1)


func _populate_initial_side_world() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var prop_count := MobilePerf.initial_side_prop_count()
	var tree_count := MobilePerf.initial_tree_count()
	var shrub_count := MobilePerf.initial_shrub_count()
	for dir in [-1, 1]:
		for i in range(prop_count):
			var z: float = 8.0 - float(i) * 10.0
			_spawn_side_prop_at(dir, z, rng, i % 3 == 0)
		for i in range(tree_count):
			_spawn_tree(dir, 10.0 - float(i) * 11.0)
		for i in range(shrub_count):
			_spawn_shrub(dir, 6.0 - float(i) * 13.0)
		_spawn_side_prop_at(dir, -18.0, rng, true, "river")
		if not MobilePerf.active:
			_spawn_side_prop_at(dir, -42.0, rng, true, "bridge")


func _spawn_side_props(dir: int) -> void:
	if dir == -1 and _is_boat_yard_active():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base_z: float = startz + rng.randf_range(-6.0, 4.0)
	var prop_chance: float = 0.82 if MobilePerf.active else 0.94
	var extra_chance: float = 0.38 if MobilePerf.active else 0.62
	var car_chance: float = 0.0 if not MobilePerf.allow_heavy_props() else 0.14
	var human_chance: float = 0.0 if not MobilePerf.allow_heavy_props() else 0.22
	var river_chance: float = 0.0 if not MobilePerf.allow_heavy_props() else 0.12
	if rng.randf() < prop_chance:
		_spawn_side_prop_at(dir, base_z, rng, rng.randf() < 0.42)
	if rng.randf() < extra_chance:
		_spawn_side_prop_at(dir, base_z + rng.randf_range(-4.0, 4.0), rng, rng.randf() < 0.28)
	if rng.randf() < car_chance:
		_spawn_side_prop_at(dir, startz + rng.randf_range(-3.0, 3.0), rng, false, "car")
	if rng.randf() < human_chance:
		_spawn_side_prop_at(dir, startz + rng.randf_range(-3.0, 3.0), rng, false, "human")
	if rng.randf() < river_chance:
		_spawn_side_prop_at(dir, startz + rng.randf_range(-2.0, 2.0), rng, false, "river")


func _spawn_side_prop_at(dir: int, z: float, rng: RandomNumberGenerator, cluster: bool, kind: String = "") -> void:
	if kind == "" and cluster:
		kind = "cluster"
	var prop: Node3D = SideScenery.create_random(rng, kind)
	var mover := Node3D.new()
	mover.set_script(env_move_script)
	mover.set_meta("side_kind", kind)
	mover.set_meta("horizon_fade", MobilePerf.use_horizon_fade())
	mover.add_child(prop)
	add_child(mover)
	var min_x: float = _side_spawn_min_x(kind)
	var max_x: float = _side_spawn_max_x(kind)
	mover.global_transform.origin = Vector3(dir * rng.randf_range(min_x, max_x), 0.0, z + rng.randf_range(-2.0, 2.0))
	mover.rotation.y = (PI if dir < 0 else 0.0) + rng.randf_range(-0.35, 0.35)
	var s: float = rng.randf_range(0.8, 1.15)
	if kind == "tower":
		s *= rng.randf_range(1.0, 1.2)
	mover.scale = Vector3(s, s, s)
	if kind in ["building", "tower", "shop", "shed", "cluster"]:
		if rng.randf() < 0.58:
			_spawn_tree(dir, z + rng.randf_range(-3.0, 3.0))
		if rng.randf() < 0.35:
			_spawn_shrub(dir, z + rng.randf_range(-2.0, 2.0))


func _spawn_tree(dir: int, z: float = INF) -> void:
	if dir == -1 and _is_boat_yard_active():
		return
	if tree_templates.is_empty():
		return
	var spawn_z: float = z if z != INF else startz + randf_range(-4.0, 4.0)
	var idx: int = randi() % tree_templates.size()
	if tree_templates.size() > 1 and idx == _last_tree:
		idx = (idx + 1) % tree_templates.size()
	_last_tree = idx

	var mover := _make_mover(tree_templates[idx])
	mover.set_meta("side_kind", "tree")
	add_child(mover)
	var s: float = randf_range(0.85, 1.5)
	mover.global_transform.origin = Vector3(
		dir * randf_range(_side_spawn_min_x("tree"), _side_spawn_max_x("tree")),
		0.0,
		spawn_z
	)
	mover.rotation.y = randf() * TAU
	mover.scale = Vector3(s, s, s)


func _spawn_shrub(dir: int, z: float = INF) -> void:
	if dir == -1 and _is_boat_yard_active():
		return
	if shrub_templates.is_empty():
		return
	var spawn_z: float = z if z != INF else startz + randf_range(-3.0, 3.0)
	var mover := _make_mover(shrub_templates[randi() % shrub_templates.size()])
	mover.set_meta("side_kind", "shrub")
	add_child(mover)
	var s: float = randf_range(0.7, 1.3)
	mover.global_transform.origin = Vector3(
		dir * randf_range(_side_spawn_min_x("shrub"), _side_spawn_max_x("shrub")),
		0.0,
		spawn_z
	)
	mover.rotation.y = randf() * TAU
	mover.scale = Vector3(s, s, s)


func _on_spawn_obstacle_timer_timeout():
	if _game_stopped():
		return
	spawn_obstacle_timer.wait_time = randf_range(1.6, 2.8)
	if rock_templates.is_empty():
		return
	var lanes: Array = [0, 1, 2]
	lanes.shuffle()
	var block_count: int = 1 + (randi() % 2)
	for i in block_count:
		_spawn_rock(lanes[i])


func _spawn_rock(lane_idx: int) -> void:
	var idx: int = randi() % rock_templates.size()
	if rock_templates.size() > 1 and idx == _last_rock:
		idx = (idx + 1) % rock_templates.size()
	_last_rock = idx

	var mover := _make_mover(rock_templates[idx], false)
	mover.add_to_group("rocks")
	add_child(mover)
	mover.global_transform.origin = Vector3(road_spawnx[lane_idx], 0.0, startz)
	mover.rotation.y = randf() * TAU
	var rs: float = randf_range(0.85, 1.1)
	mover.scale = Vector3(rs, rs * 0.52, rs)


const HIT_Z: float = 0.9
const HIT_X: float = 0.9
const JUMP_CLEAR_Y: float = 0.72


func _road_material_for_distance(d: float) -> Material:
	# km 0–1: normal asphalt, km 1–2: black vehicle road, km 2–3: carpet, then repeat
	var zone: int = int(floor(d / KM_LENGTH)) % 3
	match zone:
		0:
			return asphalt_mat
		1:
			return black_road_mat
		_:
			return carpet_mat


func _update_road_materials() -> void:
	for seg in road_segments:
		# subtract z so new road types appear ahead (negative z) and scroll toward the player
		var d: float = run_distance - seg.position.z
		seg.material_override = _road_material_for_distance(d)


func _process(delta: float) -> void:
	if _game_stopped():
		return
	run_distance += LANE_SCROLL_SPEED * delta
	if not MobilePerf.use_simple_lane_lines():
		line_scroll += LANE_SCROLL_SPEED * delta
		line_mat.set_shader_parameter("scroll_offset", line_scroll)
	_scroll_road_segments(delta)
	var mat_stride := MobilePerf.road_material_update_stride()
	if mat_stride <= 1 or Engine.get_process_frames() % mat_stride == 0:
		_update_road_materials()
	WorldScroller.scroll_world(get_tree(), delta, MobilePerf.rotate_coins())
	if _is_boat_yard_active() and Engine.get_process_frames() % 8 == 0:
		_manage_boat_yard_left_scenery()
	if Engine.get_process_frames() % 10 == 0:
		_purge_road_intrusions()
	if SimConstants.SECURE_SPAWNS:
		_process_secure_spawns()
		_try_segment_checkpoint()


func _scroll_road_segments(delta: float) -> void:
	if road_segments.is_empty():
		return
	var dz: float = LANE_SCROLL_SPEED * delta
	for seg in road_segments:
		seg.position.z += dz
	var min_z: float = INF
	for seg in road_segments:
		min_z = minf(min_z, seg.position.z)
	for seg in road_segments:
		if seg.position.z > 28.0:
			min_z -= ROAD_SEGMENT_LEN
			seg.position.z = min_z


func _physics_process(_delta: float) -> void:
	if _game_stopped():
		return
	var stride := MobilePerf.physics_stride()
	if stride > 1 and Engine.get_physics_frames() % stride != 0:
		return
	var pp: Vector3 = player.global_transform.origin
	for r in get_tree().get_nodes_in_group("rocks"):
		if not is_instance_valid(r):
			continue
		var rp: Vector3 = r.global_transform.origin
		if abs(rp.z - pp.z) < HIT_Z and abs(rp.x - pp.x) < HIT_X and pp.y < JUMP_CLEAR_Y:
			if SimConstants.SECURE_SPAWNS:
				var oid: int = int(r.get_meta("object_id", -1))
				var lane: int = int(r.get_meta("spawn_lane", _lane_index_from_x(rp.x)))
				var map_dist: float = float(r.get_meta("map_distance", get_segment_distance()))
				MoveLog.log_collision(oid, lane, map_dist)
				player.die()
				var finish_dist: float = MoveLog.finish_distance(get_segment_distance(), map_dist)
				RunSession.submit_finish(finish_dist, "collision")
			else:
				player.die()
			return
