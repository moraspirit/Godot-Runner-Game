extends MeshInstance3D

var timer: Timer = Timer.new()

func _ready():
	timer.wait_time = 5
	timer.autostart = true
# warning-ignore:return_value_discarded
	timer.connect("timeout", Callable(self, "timer_timeout"))
	add_child(timer)
	add_to_group("coins")
	# The .tscn material assignment is ignored by Godot 4 (legacy format), so
	# apply a shiny gold coin material here at runtime.
	if mesh != null:
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color(1.0, 0.78, 0.22)
		gold.metallic = 0.95
		gold.roughness = 0.30
		gold.emission_enabled = true
		gold.emission = Color(1.0, 0.72, 0.18)
		gold.emission_energy_multiplier = 0.45
		for i in mesh.get_surface_count():
			set_surface_override_material(i, gold)

func _process(delta):
	global_translate(Vector3(0, 0, 15.0 * delta))
	rotate_y(5 * delta)
	
func timer_timeout():
	#print("coin destroyed")
	queue_free()
