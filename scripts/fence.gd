extends Node3D

const WorldScroller = preload("res://scripts/world_scroller.gd")

signal body_entered


func _ready() -> void:
	add_to_group("scrollers")
	set_meta("side_kind", "fence")
	set_process(false)
	WorldScroller.register_scroller(self)
	if MobilePerf.use_horizon_fade():
		WorldScroller.apply_horizon_fade(self)
	tree_exiting.connect(_on_tree_exiting)


func _on_tree_exiting() -> void:
	WorldScroller.unregister_scroller(self)


func _on_area_body_entered(body) -> void:
	emit_signal("body_entered")
