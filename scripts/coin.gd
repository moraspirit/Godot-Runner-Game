extends MeshInstance3D

var timer: Timer = Timer.new()

func _ready():
	timer.wait_time = 5
	timer.autostart = true
# warning-ignore:return_value_discarded
	timer.connect("timeout", Callable(self, "timer_timeout"))
	add_child(timer)
	add_to_group("coins")

func _process(delta):
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("is_world_active") and not level.is_world_active():
		return
	global_translate(Vector3(0, 0, 15.0 * delta))
	rotate_y(5 * delta)
	
func timer_timeout():
	#print("coin destroyed")
	queue_free()
