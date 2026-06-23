extends Node3D

signal body_entered


func _ready() -> void:
	pass


# warning-ignore:unused_argument
func _on_area_body_entered(body):
	emit_signal("body_entered")
