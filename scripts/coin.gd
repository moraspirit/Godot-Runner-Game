extends MeshInstance3D

const WorldScroller = preload("res://scripts/world_scroller.gd")


func _ready() -> void:
	add_to_group("coins")


func _process(delta: float) -> void:
	if not WorldScroller.is_world_active(get_tree()):
		return
	WorldScroller.scroll(self, delta)
	rotate_y(5.0 * delta)
	WorldScroller.despawn_if_passed(self, get_tree())
