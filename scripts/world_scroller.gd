class_name WorldScroller
extends RefCounted

## Shared scroll, spawn distance, horizon fade, and cleanup for the endless road.

const SCROLL_SPEED: float = 15.0
const SPAWN_AHEAD: float = 95.0
const DESPAWN_BEHIND: float = 14.0

const HORIZON_FADE_END: float = 108.0
const HORIZON_FADE_MARGIN: float = 52.0


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


static func apply_horizon_fade(root: Node) -> void:
	if root is GeometryInstance3D:
		var gi := root as GeometryInstance3D
		gi.visibility_range_end = HORIZON_FADE_END
		gi.visibility_range_end_margin = HORIZON_FADE_MARGIN
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for child in root.get_children():
		apply_horizon_fade(child)
