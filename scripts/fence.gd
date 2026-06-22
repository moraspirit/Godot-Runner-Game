extends Node3D

const WorldScroller = preload("res://scripts/world_scroller.gd")

signal body_entered


func _ready() -> void:
	add_to_group("scrollers")
	set_meta("side_kind", "fence")
	WorldScroller.apply_horizon_fade(self)


func _process(delta: float) -> void:
	if not WorldScroller.is_world_active(get_tree()):
		return
	WorldScroller.scroll(self, delta)


func _on_area_body_entered(body) -> void:
	emit_signal("body_entered")
