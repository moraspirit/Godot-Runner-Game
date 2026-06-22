extends Node3D

const WorldScroller = preload("res://scripts/world_scroller.gd")

## Decorative / side scenery mover — scroll, soft horizon fade, cleanup after passing player.


func _ready() -> void:
	add_to_group("scrollers")
	if bool(get_meta("horizon_fade", true)):
		WorldScroller.apply_horizon_fade(self)


func _process(delta: float) -> void:
	if not WorldScroller.is_world_active(get_tree()):
		return
	WorldScroller.scroll(self, delta)
	WorldScroller.despawn_if_passed(self, get_tree())
