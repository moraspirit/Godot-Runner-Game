extends Node3D

const WorldScroller = preload("res://scripts/world_scroller.gd")

## Decorative / side scenery mover — scroll handled in WorldScroller.scroll_world().


func _ready() -> void:
	add_to_group("scrollers")
	set_process(false)
	WorldScroller.register_scroller(self)
	if bool(get_meta("horizon_fade", true)) and MobilePerf.use_horizon_fade():
		WorldScroller.apply_horizon_fade(self)
	tree_exiting.connect(_on_tree_exiting)


func _on_tree_exiting() -> void:
	WorldScroller.unregister_scroller(self)
