extends Node3D

signal body_entered


func _ready() -> void:
	add_to_group("scrollers")

# warning-ignore:unused_argument
func _process(delta):
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("is_world_active") and not level.is_world_active():
		return
	global_translate(Vector3(0, 0, 0.25))


# warning-ignore:unused_argument
func _on_area_body_entered(body):
	emit_signal("body_entered")
