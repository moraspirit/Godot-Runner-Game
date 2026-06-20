extends Node

# for coins
@onready var player: CharacterBody3D = $player_body
@onready var spawn_timer: Timer = $spawn_timer
@onready var spawn_env_timer: Timer = $spawn_env_timer
@onready var spawn_obstacle_timer: Timer = $spawn_obstacle_timer

@onready var coin: PackedScene = preload("res://scenes/coin.tscn")

@onready var tree1: PackedScene = preload("res://models/cartoon-assets/tree1.tscn")
@onready var tree2: PackedScene = preload("res://models/cartoon-assets/tree2.tscn")

@onready var fence: PackedScene = preload("res://models/cartoon-assets/fence.tscn")
@onready var rock:  PackedScene = preload("res://models/cartoon-assets/rock.tscn")

@onready var tree_mat: ShaderMaterial = preload("res://models/treemat.tres")
@onready var rock_mat: Material = preload("res://models/rockmat.tres")
@onready var line_mat: ShaderMaterial = preload("res://models/linemat.tres")

# how far the dashed lane lines have scrolled; advanced only while running
# (this _process stops when the tree pauses on game-over, freezing the dashes)
const LANE_SCROLL_SPEED: float = 15.0
var line_scroll: float = 0.0

# roadside street-name signboards that slide past on the left shoulder
@onready var env_move_script = preload("res://scripts/env_script.gd")
var street_names: Array = [
	"Lagaan", "Girl's Hostel", "Boat Yard", "Civil Dep", "Thunmulla",
	"Seetha Gangula", "Sumanadasa", "Steel Building", "Basketball Court",
]
var sign_index: int = 0
var sign_timer: Timer = Timer.new()
var sign_post_mat: StandardMaterial3D
var sign_board_mat: StandardMaterial3D
var sign_frame_mat: StandardMaterial3D

# a spread of natural greens so the trees aren't all identical
# each entry: [foliage base, foliage highlight]
var tree_greens: Array = [
	[Color(0.05, 0.24, 0.09), Color(0.12, 0.34, 0.12)],   # medium green
	[Color(0.03, 0.15, 0.05), Color(0.08, 0.26, 0.09)],   # deep forest
	[Color(0.09, 0.28, 0.07), Color(0.17, 0.40, 0.11)],   # sunny yellow-green
	[Color(0.04, 0.20, 0.12), Color(0.10, 0.32, 0.18)],   # cool blue-green
	[Color(0.12, 0.26, 0.06), Color(0.20, 0.36, 0.10)],   # olive
]

var startz: float = -50.0
var road_spawnx: Array = [-2, 0, 2]
var tree_startx: Array = [10, -10]

@onready var env_assets: Array = [tree1, tree2]

const FENCE_COUNT: int = 30
# example of using object pooling for fences
var fences: Array = []
var fencez: float = 0.0


func _ready():
	var x = 0
	var y = 0
	var z = 5
	for i in FENCE_COUNT:
		var fence_inst = fence.instantiate()
		fence_inst.connect("body_entered", Callable(self, "fence_area_body_entered"))
		fences.append(fence_inst)
		add_child(fence_inst)
		fence_inst.global_transform.origin = Vector3(
			x, y, z
		)
		z -= 1.5
		fencez = z

	_setup_signs()


func _setup_signs() -> void:
	sign_post_mat = StandardMaterial3D.new()
	sign_post_mat.albedo_color = Color(0.28, 0.29, 0.32)
	sign_post_mat.metallic = 0.55
	sign_post_mat.roughness = 0.5
	sign_board_mat = StandardMaterial3D.new()
	sign_board_mat.albedo_color = Color(0.05, 0.30, 0.13)
	sign_board_mat.roughness = 0.45
	sign_board_mat.metallic = 0.1
	sign_board_mat.emission_enabled = true
	sign_board_mat.emission = Color(0.04, 0.18, 0.08)
	sign_board_mat.emission_energy_multiplier = 0.3
	sign_frame_mat = StandardMaterial3D.new()
	sign_frame_mat.albedo_color = Color(0.92, 0.93, 0.9)
	sign_frame_mat.roughness = 0.4
	sign_frame_mat.emission_enabled = true
	sign_frame_mat.emission = Color(0.9, 0.92, 0.88)
	sign_frame_mat.emission_energy_multiplier = 0.18

	sign_timer.name = "sign_timer"
	sign_timer.wait_time = 2.0
	sign_timer.autostart = true
	sign_timer.connect("timeout", Callable(self, "_on_sign_timer"))
	add_child(sign_timer)


func _on_sign_timer() -> void:
	_spawn_sign(street_names[sign_index])
	sign_index = (sign_index + 1) % street_names.size()
	sign_timer.wait_time = randf_range(2.8, 4.2)


func _spawn_sign(text: String) -> Node3D:
	var root := Node3D.new()
	root.set_script(env_move_script)
	add_child(root)
	root.global_transform.origin = Vector3(-4.5, 0.0, startz)
	root.rotation_degrees.y = 26.0   # angle the face toward the running player

	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.16, 3.0, 0.16)
	post.mesh = pm
	post.material_override = sign_post_mat
	post.position = Vector3(0.0, 1.5, 0.0)
	root.add_child(post)

	# white frame slightly behind the green board for a real sign border
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(3.95, 1.22, 0.06)
	frame.mesh = fm
	frame.material_override = sign_frame_mat
	frame.position = Vector3(0.0, 3.0, -0.02)
	root.add_child(frame)

	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.7, 0.98, 0.1)
	board.mesh = bm
	board.material_override = sign_board_mat
	board.position = Vector3(0.0, 3.0, 0.0)
	root.add_child(board)

	var label := Label3D.new()
	label.text = text
	label.font_size = 130
	label.pixel_size = 0.0058
	label.modulate = Color(1, 1, 1)
	label.outline_size = 24
	label.outline_modulate = Color(0.02, 0.1, 0.05)
	label.width = 640.0
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# shrink long names so they always stay inside the board (~3.4 usable)
	var approx_w: float = float(text.length()) * label.font_size * label.pixel_size * 0.55
	if approx_w > 3.4:
		label.pixel_size *= 3.4 / approx_w
	label.position = Vector3(0.0, 3.0, 0.06)
	root.add_child(label)
	return root


func fence_area_body_entered():
	var first_fence = fences.front()
	first_fence.global_transform.origin = Vector3(
		0, 0, fencez
	)
	fences.pop_front()
	fences.append(first_fence)


func _on_spawn_timer_timeout():
	spawn_timer.wait_time = randf_range(1.2, 2.2)
	# A clean trail of coins down a single lane (classic runner pickup line).
	var lane_idx: int = randi() % 3
	var count: int = 4 + (randi() % 5)  # 4..8 coins in a row
	for i in count:
		var coin_inst: MeshInstance3D = coin.instantiate()
		add_child(coin_inst)
		coin_inst.global_transform.origin = Vector3(
			road_spawnx[lane_idx],
			1.0,
			startz + i * 2.5
		)


func _on_spawn_env_timer_timeout():
	randomize()
	# spawn trees on both sides for a fuller, denser environment
	_spawn_tree(1)
	_spawn_tree(-1)
	# occasionally a second, closer-in tree for layered depth
	if randf() < 0.5:
		_spawn_tree(1)
	if randf() < 0.5:
		_spawn_tree(-1)
	spawn_env_timer.wait_time = randf_range(0.45, 0.8)


func _spawn_tree(dir: int) -> void:
	var asset = env_assets[randi() % env_assets.size()].instantiate()
	add_child(asset)
	var s: float = randf_range(0.8, 1.6)
	var greens: Array = tree_greens[randi() % tree_greens.size()]
	var mat := tree_mat.duplicate() as ShaderMaterial
	mat.set_shader_parameter("leaf_color", greens[0])
	mat.set_shader_parameter("leaf_top", greens[1])
	# the tree mesh stands ~6.5 units tall before scaling
	mat.set_shader_parameter("tree_height", 6.5 * s)
	_tint(asset, mat)
	var x: float = dir * randf_range(7.0, 16.0)
	asset.global_transform.origin = Vector3(
		x,
		0,
		startz + randf_range(-3.0, 3.0)
	)
	asset.rotation_degrees.y = randf_range(0, 360)
	asset.scale = Vector3(s, s, s)


# recolour every mesh under a spawned asset by overriding its surface material
func _tint(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, mat)
	for c in node.get_children():
		_tint(c, mat)


func _on_spawn_obstacle_timer_timeout():
	spawn_obstacle_timer.wait_time = randf_range(1.6, 2.8)
	# Block 1 or 2 of the 3 lanes — NEVER all three, so there is always an
	# escape lane (you can also jump a single rock). This keeps the game fair.
	var lanes: Array = [0, 1, 2]
	lanes.shuffle()
	var block_count: int = 1 + (randi() % 2)  # 1 or 2
	for i in block_count:
		var lane_idx: int = lanes[i]
		var rock_inst = rock.instantiate()
		add_child(rock_inst)
		rock_inst.add_to_group("rocks")
		_tint(rock_inst, rock_mat)
		rock_inst.global_transform.origin = Vector3(
			road_spawnx[lane_idx],
			0.0,
			startz
		)
		rock_inst.rotation_degrees.y = randf_range(0, 360)
		var rs: float = randf_range(1.3, 1.6)
		rock_inst.scale = Vector3(rs, rs, rs)


func on_player_entered_rock():
	player.is_dead = true


# Deterministic, lane-aligned collision: you only die if a rock is in YOUR
# lane, has reached you in Z, and you haven't jumped above it.
const HIT_Z: float = 0.9      # how close in depth counts as a hit
const HIT_X: float = 0.9      # must be essentially the same lane (lanes are 2 apart)
const JUMP_CLEAR_Y: float = 0.8   # player origin.y above this = cleared the rock

func _process(delta: float) -> void:
	# flow the dashed lane lines toward the player in lock-step with the
	# obstacles; pausing on game-over halts this _process, freezing the dashes
	line_scroll += LANE_SCROLL_SPEED * delta
	line_mat.set_shader_parameter("scroll_offset", line_scroll)


func _physics_process(_delta: float) -> void:
	if player == null or player.is_dead or player.game_over:
		return
	var pp: Vector3 = player.global_transform.origin
	for r in get_tree().get_nodes_in_group("rocks"):
		if not is_instance_valid(r):
			continue
		var rp: Vector3 = r.global_transform.origin
		if abs(rp.z - pp.z) < HIT_Z and abs(rp.x - pp.x) < HIT_X and pp.y < JUMP_CLEAR_Y:
			player.is_dead = true
			return
