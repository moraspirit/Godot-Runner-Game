extends CharacterBody3D

const PLAYER_MODEL: String = "res://models/boy/Rogue.glb"

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var death_audio: AudioStreamPlayer = $DeathSFX
var anim_player: AnimationPlayer

const JUMP_FORCE: float = 9.0
const GRAVITY: float = 22.0
const LANE_SWITCH_SPEED: float = 14.0      # how fast the player slides between lanes
const SWIPE_THRESHOLD: float = 40.0        # min finger travel (px) to count as a swipe

# 3 lanes, matching the obstacle/coin spawn positions in level.gd (road_spawnx)
const LANE_X: Array = [-2.0, 0.0, 2.0]

var ground_y: float = 0.0
var vertical_velocity: float = 0.0

var current_lane: int = 1                  # 0 = left, 1 = center, 2 = right
var jump_requested: bool = false

var run_anim: String = ""
var jump_anim: String = ""
var death_anim: String = ""
var is_jumping: bool = false

var is_dead: bool = false
var dying: bool = false
var game_over: bool = false
var coin_count: int = 0

var coin_label: Label
var _name_label: Label
var _best_label: Label
var overlay: Control
var result_label: Label

var _finish_data: Dictionary = {}
var _finish_done: bool = false
var _finish_success: bool = false
var _finish_ui_finalized: bool = false
var _finish_wait_timer: Timer
var _play_again_btn: Button
var _menu_btn: Button

const FINISH_WAIT_SEC: float = 22.0

# swipe tracking
var _touch_start: Vector2 = Vector2.ZERO
var _swiped: bool = false

func _ready() -> void:
	# keep running while the tree is paused so we can detect the restart tap
	process_mode = Node.PROCESS_MODE_ALWAYS

	# rocks look for an area in this group to know they hit the player
	$collision_area.add_to_group("player_skeleton")

	_spawn_character()
	_setup_hud()

	ground_y = global_transform.origin.y
	run_anim = _find_anim(["Running_A", "Run"])
	jump_anim = _find_anim(["Jump_Full_Long", "Jump"])
	death_anim = _find_anim(["Death_A", "Death"])
	if run_anim != "":
		anim_player.get_animation(run_anim).loop_mode = Animation.LOOP_LINEAR
	_play_run()
	if not RunSession.checkpoint_resolved.is_connected(_on_checkpoint_resolved):
		RunSession.checkpoint_resolved.connect(_on_checkpoint_resolved)
	if not RunSession.finish_resolved.is_connected(_on_finish_resolved):
		RunSession.finish_resolved.connect(_on_finish_resolved)
	if not AuthSession.profile_updated.is_connected(_on_profile_updated):
		AuthSession.profile_updated.connect(_on_profile_updated)
	if death_audio:
		death_audio.process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_layout_hud_panels")
	_refresh_coin_hud()

# Load the boy model, turn it to face the camera, and wire its AnimationPlayer.
func _spawn_character() -> void:
	var model := (load(PLAYER_MODEL) as PackedScene).instantiate()
	model.name = "player"
	var s: float = 0.85
	# 180 deg about Y so the boy faces the camera (front toward viewer).
	model.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3(s, s, s)), Vector3.ZERO)
	add_child(model)
	anim_player = model.get_node("AnimationPlayer")

func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	# Top bar — text only, no background panels.
	_name_label = _make_hud_label(layer, HORIZONTAL_ALIGNMENT_LEFT, Color(0.9, 0.95, 1.0))
	coin_label = _make_hud_label(layer, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 0.96, 0.78))
	coin_label.add_theme_font_size_override("font_size", BrowserBridge.hud_font() + 2)
	coin_label.text = "0"
	_best_label = _make_hud_label(layer, HORIZONTAL_ALIGNMENT_RIGHT, Color(1, 0.88, 0.42))

	_layout_hud_panels()

	# ---- full-screen game-over overlay (dim + centered card) ----
	overlay = Control.new()
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false

	var bg := ColorRect.new()
	overlay.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.66)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var card := PanelContainer.new()
	overlay.add_child(card)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	BrowserBridge.apply_wide_popup(card, 0.48)
	card.add_theme_stylebox_override("panel", _card_style())

	var margin := MarginContainer.new()
	card.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)

	var box := VBoxContainer.new()
	margin.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 20)

	var title := Label.new()
	box.add_child(title)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", BrowserBridge.popup_title_font() + 8)
	title.add_theme_color_override("font_color", Color(1, 0.32, 0.28))
	title.text = "GAME OVER"

	result_label = Label.new()
	box.add_child(result_label)
	result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.add_theme_font_size_override("font_size", BrowserBridge.popup_body_font() + 4)
	result_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	result_label.text = "Score 0     Coins 0"

	box.add_child(_spacer(12))

	_play_again_btn = Button.new()
	box.add_child(_play_again_btn)
	_play_again_btn.custom_minimum_size = Vector2(0, BrowserBridge.popup_button_height())
	_play_again_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_again_btn.add_theme_font_size_override("font_size", BrowserBridge.popup_body_font())
	_play_again_btn.text = "Play"
	_play_again_btn.add_theme_stylebox_override("normal", _pill_style(Color(0.92, 0.95, 1.0)))
	_play_again_btn.add_theme_color_override("font_color", Color(0.08, 0.1, 0.14))
	_play_again_btn.pressed.connect(_restart)

	_menu_btn = Button.new()
	box.add_child(_menu_btn)
	_menu_btn.custom_minimum_size = Vector2(0, BrowserBridge.popup_button_height() - 8)
	_menu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_btn.add_theme_font_size_override("font_size", BrowserBridge.popup_body_font())
	_menu_btn.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	_menu_btn.text = "Menu"
	_menu_btn.add_theme_stylebox_override("normal", _pill_style(Color(0.12, 0.14, 0.2)))
	_menu_btn.pressed.connect(_go_menu)


func _make_hud_label(parent: Node, align: HorizontalAlignment, color: Color) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", BrowserBridge.hud_font())
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 5)
	return label


func _layout_hud_panels() -> void:
	var width := get_viewport().get_visible_rect().size.x
	if width <= 0.0:
		width = float(get_viewport().size.x)
	if width <= 0.0:
		width = 720.0
	var top := 18.0
	var height := 44.0
	var side_w := 220.0
	var coin_w := 120.0
	if _name_label:
		_name_label.position = Vector2(18.0, top)
		_name_label.size = Vector2(side_w, height)
	if coin_label:
		coin_label.position = Vector2((width - coin_w) * 0.5, top)
		coin_label.size = Vector2(coin_w, height)
	if _best_label:
		_best_label.position = Vector2(width - side_w - 18.0, top)
		_best_label.size = Vector2(side_w, height)


func _refresh_coin_hud() -> void:
	if coin_label:
		coin_label.text = str(coin_count)
	var logged_in := AuthSession.is_logged_in()
	if _name_label:
		_name_label.visible = logged_in
	if _best_label:
		_best_label.visible = logged_in
	if not logged_in:
		return
	var player_name := AuthSession.username.strip_edges()
	if player_name == "":
		player_name = AuthSession.index_number.strip_edges()
	if player_name == "":
		player_name = "Player"
	if _name_label:
		_name_label.text = player_name
	if _best_label:
		_best_label.text = "Best %d" % AuthSession.best_coins


func _on_profile_updated(_body: Dictionary) -> void:
	_refresh_coin_hud()


func _on_checkpoint_resolved(accepted: bool, data: Dictionary) -> void:
	if accepted:
		coin_count = int(data.get("run_total_coins", coin_count))
		_refresh_coin_hud()


func _on_finish_resolved(success: bool, data: Dictionary) -> void:
	_finish_data = data
	_finish_success = success
	_finish_done = true
	if success:
		_refresh_coin_hud()
	if game_over and not _finish_ui_finalized:
		_stop_finish_wait()
		_trigger_game_over()


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.14, 0.97)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 0.35, 0.3, 0.7)
	sb.shadow_size = 16
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

func _pill_style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(32)
	return sb

func _find_anim(targets: Array) -> String:
	for target in targets:
		var t: String = String(target).to_lower()
		for a in anim_player.get_animation_list():
			if t in String(a).to_lower():
				return a
	return ""

func _play_run() -> void:
	if run_anim != "":
		anim_player.play(run_anim)

# --- input: swipe to change lane / jump, tap to restart ---------------------
func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
			_swiped = false
	elif event is InputEventScreenDrag:
		_evaluate_swipe(event.position)
	# mouse fallback (for testing on desktop)
	elif event is InputEventMouseButton:
		if event.pressed:
			_touch_start = event.position
			_swiped = false
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_evaluate_swipe(event.position)

func _evaluate_swipe(pos: Vector2) -> void:
	if _swiped:
		return
	var d: Vector2 = pos - _touch_start
	if absf(d.x) > SWIPE_THRESHOLD and absf(d.x) >= absf(d.y):
		_change_lane(1 if d.x > 0.0 else -1)
		_swiped = true
	elif d.y < -SWIPE_THRESHOLD:
		jump_requested = true
		_swiped = true

func _change_lane(dir: int) -> void:
	var old_lane: int = current_lane
	current_lane = clampi(current_lane + dir, 0, LANE_X.size() - 1)
	if old_lane == current_lane:
		return
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("get_segment_distance") and MoveLog.can_log_lane_change():
		MoveLog.log_lane_change(old_lane, current_lane, level.get_segment_distance())

func _restart() -> void:
	get_tree().paused = false
	if SimConstants.API_BASE.is_empty():
		RunSession.restart_run()
		get_tree().reload_current_scene()
		return
	if RunSession.run_ready.is_connected(_on_restart_run_ready):
		RunSession.run_ready.disconnect(_on_restart_run_ready)
	RunSession.run_ready.connect(_on_restart_run_ready, CONNECT_ONE_SHOT)
	RunSession.restart_run()


func _on_restart_run_ready(success: bool, error_message: String) -> void:
	if success:
		get_tree().reload_current_scene()
		return
	get_tree().paused = false
	_finish_success = false
	_finish_done = true
	_finish_data = {
		"message": error_message if error_message != "" else "Could not start a new run.",
	}
	_finish_ui_finalized = false
	_trigger_game_over()


func _go_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _physics_process(delta: float) -> void:
	if game_over:
		return

	if is_dead:
		# Hit a rock: play the death animation and crumple onto the road,
		# THEN show the game-over card (instead of freezing instantly).
		if not dying:
			_start_death()
		return

	# coins-only score — distance does not count
	_refresh_coin_hud()

	# keyboard fallback so it's also playable on desktop
	if Input.is_action_just_pressed("move_left"):
		_change_lane(-1)
	if Input.is_action_just_pressed("move_right"):
		_change_lane(1)
	if Input.is_action_just_pressed("jump"):
		jump_requested = true

	var pos: Vector3 = global_transform.origin

	# slide toward the target lane
	var target_x: float = LANE_X[current_lane]
	pos.x = move_toward(pos.x, target_x, LANE_SWITCH_SPEED * delta)

	# jump only when on the ground
	var on_ground: bool = pos.y <= ground_y + 0.01
	if on_ground and jump_requested:
		vertical_velocity = JUMP_FORCE
		is_jumping = true
		var level := get_tree().get_first_node_in_group("level")
		if level and level.has_method("get_segment_distance"):
			MoveLog.log_jump_start(level.get_segment_distance())
		if jump_anim != "":
			anim_player.play(jump_anim)
	jump_requested = false

	# gravity + vertical move (no floor collider, handled manually)
	vertical_velocity -= GRAVITY * delta
	pos.y += vertical_velocity * delta
	if pos.y <= ground_y:
		pos.y = ground_y
		vertical_velocity = 0.0
		if is_jumping:
			is_jumping = false
			var level := get_tree().get_first_node_in_group("level")
			if level and level.has_method("get_segment_distance"):
				MoveLog.log_jump_land(level.get_segment_distance())
			_play_run()

	global_transform.origin = pos

func _start_death() -> void:
	dying = true
	# submit_finish() runs in level.gd before is_dead — response may arrive first
	if not _finish_done:
		_finish_success = false
		_finish_data = {}
	_finish_ui_finalized = false
	if death_audio:
		death_audio.play()
	if death_anim != "":
		var a := anim_player.get_animation(death_anim)
		if a:
			a.loop_mode = Animation.LOOP_NONE
		anim_player.play(death_anim)
	else:
		# No death clip on this rig: just stop running and topple over on the road.
		anim_player.stop()
		var m := get_node_or_null("player") as Node3D
		if m:
			m.rotate_x(-PI / 2.0)
	# Let the death play out on the road before the game-over card appears.
	await get_tree().create_timer(1.2, true).timeout
	if RunSession.offline_mode:
		_finish_success = true
		_finish_data = {"final_coins": coin_count}
		_show_game_over_loading()
		_trigger_game_over()
		return
	_show_game_over_loading()
	if _finish_done:
		_trigger_game_over()
	else:
		_arm_finish_wait()


func _arm_finish_wait() -> void:
	if _finish_wait_timer == null:
		_finish_wait_timer = Timer.new()
		_finish_wait_timer.one_shot = true
		_finish_wait_timer.wait_time = FINISH_WAIT_SEC
		_finish_wait_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_finish_wait_timer)
		_finish_wait_timer.timeout.connect(_on_finish_wait_timeout)
	_finish_wait_timer.start()


func _stop_finish_wait() -> void:
	if _finish_wait_timer:
		_finish_wait_timer.stop()


func _on_finish_wait_timeout() -> void:
	if _finish_ui_finalized or _finish_done:
		return
	_finish_success = false
	_finish_done = true
	_finish_data = {
		"error": "timeout",
		"message": "Server timed out — score could not be validated.",
	}
	_trigger_game_over()


func _show_game_over_loading() -> void:
	game_over = true
	result_label.text = "Validating score..."
	if _play_again_btn:
		_play_again_btn.disabled = true
	if _menu_btn:
		_menu_btn.disabled = true
	overlay.visible = true
	overlay.modulate.a = 1.0


func _trigger_game_over() -> void:
	if _finish_ui_finalized:
		return
	_finish_ui_finalized = true
	_stop_finish_wait()
	if not game_over:
		game_over = true
		overlay.visible = true
		overlay.modulate.a = 1.0

	get_tree().paused = true

	if _play_again_btn:
		_play_again_btn.disabled = false
	if _menu_btn:
		_menu_btn.disabled = false

	var lines: PackedStringArray = PackedStringArray()
	if _finish_success:
		var display_coins: int = int(_finish_data.get("final_coins", 0))
		lines.append("Coins %d" % display_coins)
		var rank: int = int(_finish_data.get("rank", 0))
		if rank > 0:
			lines.append("Rank #%d" % rank)
	else:
		lines.append(_finish_error_message())
		lines.append("Tap Menu to go back.")

	result_label.text = "\n".join(lines)
	overlay.visible = true
	overlay.modulate.a = 1.0


func _finish_error_message() -> String:
	if _finish_data.has("message"):
		return str(_finish_data.get("message", ""))
	var err := str(_finish_data.get("error", ""))
	if err == "timeout":
		return "Server timed out — score could not be validated."
	if err == "connection_failed" or err == "request_failed":
		return "Connection failed — could not validate score."
	if err != "":
		return "Score validation failed: %s" % err
	return "Could not validate score. Try again later."

func _on_collision_area_entered(area):
	var parent = area.get_parent()
	if parent.is_in_group("coins"):
		audio_player.play()
		coin_count += 1
		_refresh_coin_hud()
		var level := get_tree().get_first_node_in_group("level")
		if level and level.has_method("get_segment_distance"):
			var oid: int = int(parent.get_meta("object_id", -1))
			var lane: int = int(parent.get_meta("spawn_lane", current_lane))
			var dist: float = float(parent.get_meta("map_distance", level.get_segment_distance()))
			MoveLog.log_coin(oid, lane, dist)
		parent.queue_free()
