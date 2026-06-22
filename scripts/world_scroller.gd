class_name WorldScroller
extends RefCounted

## Shared scroll, spawn distance, horizon fade, and cleanup for the endless road.

const SCROLL_SPEED: float = 15.0
const SPAWN_AHEAD: float = 95.0
const DESPAWN_BEHIND: float = 14.0

const HORIZON_FADE_END: float = 108.0
const HORIZON_FADE_MARGIN: float = 52.0

static var _scrollers: Array[Node3D] = []
static var _coins: Array[Node3D] = []


static func reset_registry() -> void:
	_scrollers.clear()
	_coins.clear()


static func register_scroller(node: Node3D) -> void:
	if node != null and node not in _scrollers:
		_scrollers.append(node)


static func unregister_scroller(node: Node3D) -> void:
	_scrollers.erase(node)


static func register_coin(node: Node3D) -> void:
	if node != null and node not in _coins:
		_coins.append(node)


static func unregister_coin(node: Node3D) -> void:
	_coins.erase(node)


static func is_world_active(tree: SceneTree) -> bool:
	var level := tree.get_first_node_in_group("level")
	return level != null and level.has_method("is_world_active") and level.is_world_active()


static func scroll(node: Node3D, delta: float) -> void:
	node.global_translate(Vector3(0, 0, SCROLL_SPEED * delta))


static func player_z(tree: SceneTree) -> float:
	var level := tree.get_first_node_in_group("level")
	if level == null or not level.get("player") or level.player == null:
		return 0.0
	return level.player.global_transform.origin.z


static func despawn_if_passed(node: Node3D, tree: SceneTree) -> void:
	if node.global_position.z > player_z(tree) + DESPAWN_BEHIND:
		node.queue_free()


## One batched scroll pass — avoids hundreds of per-node _process() calls (web WASM bottleneck).
static func scroll_world(tree: SceneTree, delta: float, rotate_coins: bool = true) -> void:
	if not is_world_active(tree):
		return
	var dz: float = SCROLL_SPEED * delta
	var pz: float = player_z(tree)
	var despawn_z: float = pz + DESPAWN_BEHIND

	var i := _scrollers.size() - 1
	while i >= 0:
		var n := _scrollers[i]
		if not is_instance_valid(n):
			_scrollers.remove_at(i)
			i -= 1
			continue
		n.global_translate(Vector3(0.0, 0.0, dz))
		if str(n.get_meta("side_kind", "")) != "fence" and n.global_position.z > despawn_z:
			n.queue_free()
		i -= 1

	i = _coins.size() - 1
	while i >= 0:
		var coin := _coins[i]
		if not is_instance_valid(coin):
			_coins.remove_at(i)
			i -= 1
			continue
		coin.global_translate(Vector3(0.0, 0.0, dz))
		if rotate_coins:
			coin.rotate_y(5.0 * delta)
		if coin.global_position.z > despawn_z:
			coin.queue_free()
		i -= 1


static func apply_horizon_fade(root: Node) -> void:
	if root is GeometryInstance3D:
		var gi := root as GeometryInstance3D
		gi.visibility_range_end = HORIZON_FADE_END
		gi.visibility_range_end_margin = HORIZON_FADE_MARGIN
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for child in root.get_children():
		apply_horizon_fade(child)
