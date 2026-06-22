extends Node3D

var timer: Timer = Timer.new()

signal player_entered


func _ready():
	timer.wait_time = float(get_meta("lifetime", 8.0))
	timer.autostart = true
# warning-ignore:return_value_discarded
	timer.connect("timeout", Callable(self, "timer_timeout"))
	add_child(timer)
	add_to_group("scrollers")


# warning-ignore:unused_argument
func _process(delta):
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("is_world_active") and not level.is_world_active():
		return
	global_translate(Vector3(0, 0, 15.0 * delta))


func timer_timeout():
	#print("tree destroyed")
	queue_free()


# every rock is connected to the player script each time a new instance is spawned
func _on_Area_area_entered(area):
	if area.is_in_group("player_skeleton"):
		emit_signal("player_entered")
