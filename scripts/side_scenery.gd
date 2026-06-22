class_name SideScenery
extends RefCounted

## Procedural roadside props — buildings, people, vehicles, water features.

# Real 3D models — add paths here when you drop new .glb files into models/
const CAR_MODELS: Array = [
	"res://models/car/car1.glb",
	"res://models/car/car2.glb",
]
const BOAT_MODELS: Array = [
	"res://models/boats/boat.glb",
]
const FLOWER_BUSH_GLB: String = "res://models/nature/Bushes.glb"
const LAKE_TREE_GLBS: Array = [
	"res://models/nature/Trees.glb",
	"res://models/nature/PineTrees.glb",
]

const CAR_TARGET_LENGTH: float = 4.0
const BOAT_TARGET_LENGTH: float = 3.2
const LAKE_TREE_HEIGHT: float = 4.5
const LAKE_SHRUB_HEIGHT: float = 1.4


static func create_random(rng: RandomNumberGenerator, kind: String = "") -> Node3D:
	if kind == "":
		kind = _pick_kind(rng)
	match kind:
		"building":
			return _make_building(rng, rng.randi_range(2, 4))
		"tower":
			return _make_building(rng, rng.randi_range(5, 8))
		"shop":
			return _make_shop(rng)
		"car":
			return _make_vehicle(rng)
		"lamp":
			return _make_street_lamp()
		"bench":
			return _make_bench()
		"shed":
			return _make_shed(rng)
		"human":
			return _make_human(rng)
		"cluster":
			return _make_building_cluster(rng)
		"river":
			return _make_river_strip(rng)
		"bridge":
			return _make_bridge(rng)
		"boat":
			return _make_boat(rng)
		_:
			return _make_building(rng, 3)


static func create_boat_yard_lake(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var water_mat: Material = load("res://models/water_shadermat.tres") as Material
	var lake_w: float = 22.0
	var lake_l: float = 100.0
	var near_shore: float = 1.6
	var water_cx: float = -(lake_w * 0.5 - near_shore)

	_add_water_plane(root, water_mat, Vector3(water_cx, 0.02, 0.0), Vector2(lake_w, lake_l))

	var grass := _mat(Color(0.24, 0.38, 0.20))
	var mud := _mat(Color(0.30, 0.26, 0.20))
	# far bank — trees sit here with lake in front
	_box(Vector3(2.2, 0.14, lake_l), grass, Vector3(water_cx - lake_w * 0.46, 0.04, 0.0), root)
	# narrow wet shore between road and open water
	_box(Vector3(1.6, 0.08, lake_l), mud, Vector3(water_cx + lake_w * 0.34, 0.02, 0.0), root)

	var reed := _mat(Color(0.35, 0.52, 0.22))
	for _i in 6:
		_box(
			Vector3(0.08, rng.randf_range(0.35, 0.75), 0.08),
			reed,
			Vector3(
				rng.randf_range(water_cx - lake_w * 0.38, water_cx + lake_w * 0.22),
				0.12,
				rng.randf_range(-lake_l * 0.46, lake_l * 0.46)
			),
			root
		)

	_add_boat_yard_lake_nature(rng, root, water_mat, water_cx, lake_w, lake_l, grass)

	var wood := _mat(Color(0.48, 0.32, 0.18), 0.85)
	var dock_z: float = rng.randf_range(-8.0, 8.0)
	var dock_x: float = water_cx - lake_w * 0.28
	for i in 7:
		_box(Vector3(0.55, 0.12, 1.35), wood, Vector3(dock_x, 0.06, dock_z + float(i) * 1.3), root)
	_box(Vector3(2.8, 0.14, 0.65), wood, Vector3(dock_x - 1.0, 0.08, dock_z + 2.5), root)

	if _has_boat_models():
		var boat := _make_boat(rng)
		boat.position = Vector3(
			water_cx - lake_w * 0.08,
			0.0,
			dock_z + rng.randf_range(-2.0, 4.0)
		)
		boat.rotation.y = rng.randf_range(-0.5, 0.5)
		root.add_child(boat)

	return root


static func _add_water_plane(parent: Node3D, water_mat: Material, center: Vector3, size: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = water_mat
	mi.position = center
	parent.add_child(mi)


static func _add_boat_yard_lake_nature(
	rng: RandomNumberGenerator,
	root: Node3D,
	water_mat: Material,
	water_cx: float,
	lake_w: float,
	lake_l: float,
	grass_mat: StandardMaterial3D
) -> void:
	# three flower bushes on tiny grass islands surrounded by water
	var island_z: Array = [-16.0, 2.0, 18.0]
	var island_x: float = water_cx + lake_w * 0.08
	for z in island_z:
		var iz: float = float(z) + rng.randf_range(-1.0, 1.0)
		_add_water_plane(root, water_mat, Vector3(island_x, 0.015, iz), Vector2(4.2, 4.2))
		_box(Vector3(1.8, 0.1, 1.8), grass_mat, Vector3(island_x, 0.05, iz), root)
		var bush: Node3D = _make_flower_bush(rng)
		bush.position = Vector3(island_x, 0.0, iz)
		bush.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(bush)

	# trees on the far bank — lake water sits in front of them
	var tree_bank_x: float = water_cx - lake_w * 0.40
	var tree_z: Array = [-24.0, -10.0, 8.0, 22.0]
	for z in tree_z:
		var tree: Node3D = _make_lake_tree(rng)
		tree.position = Vector3(
			tree_bank_x + rng.randf_range(-0.8, 0.8),
			0.0,
			float(z) + rng.randf_range(-2.0, 2.0)
		)
		tree.rotation.y = rng.randf_range(0.0, TAU)
		var ts: float = rng.randf_range(0.85, 1.1)
		tree.scale = Vector3(ts, ts, ts)
		root.add_child(tree)

	# extra shrubs along the waterline on both sides
	var shrub_spots: Array = [
		Vector3(water_cx - lake_w * 0.22, 0.0, -6.0),
		Vector3(water_cx - lake_w * 0.18, 0.0, 14.0),
		Vector3(water_cx + lake_w * 0.18, 0.0, -12.0),
	]
	for spot: Vector3 in shrub_spots:
		_add_water_plane(root, water_mat, Vector3(spot.x, 0.015, spot.z), Vector2(3.0, 3.0))
		_box(Vector3(1.4, 0.08, 1.4), grass_mat, Vector3(spot.x, 0.04, spot.z), root)
		var shrub: Node3D = _make_lake_shrub(rng)
		shrub.position = spot
		shrub.rotation.y = rng.randf_range(0.0, TAU)
		root.add_child(shrub)


static func _make_lake_tree(rng: RandomNumberGenerator) -> Node3D:
	var path: String = _pick_model_path(LAKE_TREE_GLBS, rng)
	if path == "":
		return Node3D.new()
	return _load_glb_prop(path, rng.randf_range(LAKE_TREE_HEIGHT * 0.85, LAKE_TREE_HEIGHT * 1.15))


static func _make_lake_shrub(rng: RandomNumberGenerator) -> Node3D:
	if ResourceLoader.exists(FLOWER_BUSH_GLB):
		return _load_glb_prop(FLOWER_BUSH_GLB, rng.randf_range(LAKE_SHRUB_HEIGHT * 0.9, LAKE_SHRUB_HEIGHT * 1.1))
	return _make_flower_bush_procedural(rng)


static func _make_flower_bush(rng: RandomNumberGenerator) -> Node3D:
	if ResourceLoader.exists(FLOWER_BUSH_GLB):
		var wrapper := Node3D.new()
		var scene: PackedScene = load(FLOWER_BUSH_GLB) as PackedScene
		if scene != null:
			var inst: Node3D = scene.instantiate() as Node3D
			if inst != null:
				wrapper.add_child(inst)
				var s: float = rng.randf_range(0.26, 0.38)
				inst.scale = Vector3(s, s, s)
				var aabb: AABB = _local_mesh_aabb(inst)
				if aabb.size.length_squared() > 0.000001:
					inst.position.y = -aabb.position.y
				return wrapper
	return _make_flower_bush_procedural(rng)


static func _make_flower_bush_procedural(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var leaf := _mat(Color(0.28, 0.52, 0.24))
	var flowers: Array = [
		Color(0.92, 0.45, 0.62), Color(0.95, 0.82, 0.22), Color(0.88, 0.55, 0.92),
	]
	_sphere(0.32, leaf, Vector3(0.0, 0.22, 0.0), root)
	_sphere(0.2, leaf, Vector3(0.12, 0.16, 0.08), root)
	for i in 3:
		_sphere(
			0.07,
			_mat(flowers[i % flowers.size()], 0.75),
			Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(0.32, 0.46), rng.randf_range(-0.18, 0.18)),
			root
		)
	return root


static func _pick_model_path(models: Array, rng: RandomNumberGenerator) -> String:
	var available: Array = []
	for path in models:
		var p: String = str(path)
		if ResourceLoader.exists(p):
			available.append(p)
	if available.is_empty():
		return ""
	return available[rng.randi() % available.size()]


static func _has_boat_models() -> bool:
	for path in BOAT_MODELS:
		if ResourceLoader.exists(str(path)):
			return true
	return false


static func _pick_boat_model_path(rng: RandomNumberGenerator) -> String:
	return _pick_model_path(BOAT_MODELS, rng)


static func _pick_car_model_path(rng: RandomNumberGenerator) -> String:
	return _pick_model_path(CAR_MODELS, rng)


static func _local_mesh_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in _gather_mesh_instances(root):
		var xf: Transform3D = _relative_transform_to(root, mi)
		var local: AABB = xf * mi.get_aabb()
		if first:
			out = local
			first = false
		else:
			out = out.merge(local)
	return out


static func _relative_transform_to(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var current: Node = node
	while current != null:
		if current is Node3D:
			xf = (current as Node3D).transform * xf
		if current == root:
			break
		current = current.get_parent()
	return xf


static func _gather_mesh_instances(node: Node) -> Array:
	var found: Array = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_gather_mesh_instances(child))
	return found


static func _load_glb_prop(path: String, target_length: float) -> Node3D:
	var root := Node3D.new()
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return root
	var inst: Node3D = scene.instantiate() as Node3D
	if inst == null:
		return root
	root.add_child(inst)
	var aabb: AABB = _local_mesh_aabb(inst)
	if aabb.size.length_squared() > 0.000001:
		var horiz: float = maxf(aabb.size.x, aabb.size.z)
		if horiz > 0.001:
			var s: float = target_length / horiz
			inst.scale = Vector3(s, s, s)
		aabb = _local_mesh_aabb(inst)
		if aabb.size.length_squared() > 0.000001:
			inst.position.y = -aabb.position.y
	return root


static func _make_boat(rng: RandomNumberGenerator, _style: String = "") -> Node3D:
	var path: String = _pick_boat_model_path(rng)
	if path == "":
		return Node3D.new()
	var boat: Node3D = _load_glb_prop(path, BOAT_TARGET_LENGTH)
	boat.position.y = 0.06
	return boat


static func _make_vehicle(rng: RandomNumberGenerator) -> Node3D:
	var path: String = _pick_car_model_path(rng)
	if path == "":
		return Node3D.new()
	return _load_glb_prop(path, CAR_TARGET_LENGTH)


static func _pick_kind(rng: RandomNumberGenerator) -> String:
	var kinds: Array = [
		"building", "building", "building", "building", "building",
		"tower", "tower", "shop", "shop", "shed", "shed",
		"cluster", "cluster", "cluster",
		"lamp", "bench", "human", "human", "car", "river", "bridge",
	]
	return kinds[rng.randi() % kinds.size()]


static func _mat(color: Color, rough: float = 0.82, emit: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.04
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emit
	return m


static func _box(size: Vector3, mat: Material, pos: Vector3, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _sphere(r: float, mat: Material, pos: Vector3, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


static func _make_building(rng: RandomNumberGenerator, floors: int) -> Node3D:
	var root := Node3D.new()
	var w: float = rng.randf_range(2.4, 4.2)
	var d: float = rng.randf_range(2.2, 3.6)
	var wall_palettes: Array = [
		[Color(0.55, 0.50, 0.46), Color(0.62, 0.58, 0.52)],
		[Color(0.48, 0.52, 0.58), Color(0.56, 0.60, 0.66)],
		[Color(0.58, 0.46, 0.40), Color(0.66, 0.52, 0.44)],
	]
	var pal: Array = wall_palettes[rng.randi() % wall_palettes.size()]
	var wall_a := _mat(pal[0])
	var wall_b := _mat(pal[1])
	var roof := _mat(Color(0.26, 0.20, 0.18))
	var window := _mat(Color(0.50, 0.68, 0.88, 0.92), 0.3, 0.06)
	var door := _mat(Color(0.32, 0.22, 0.14))
	var h: float = 0.0
	for f in floors:
		var fh: float = rng.randf_range(1.05, 1.4)
		var wall_mat: Material = wall_a if f % 2 == 0 else wall_b
		_box(Vector3(w, fh, d), wall_mat, Vector3(0, h + fh * 0.5, 0), root)
		var cols: int = maxi(1, int(w / 1.1))
		for c in cols:
			var wx: float = -w * 0.5 + (c + 0.5) * (w / float(cols))
			_box(Vector3(0.32, fh * 0.42, 0.12), window, Vector3(wx, h + fh * 0.58, d * 0.51), root)
		h += fh
	_box(Vector3(w * 1.08, 0.2, d * 1.08), roof, Vector3(0, h + 0.1, 0), root)
	_box(Vector3(0.55, 1.05, 0.14), door, Vector3(0, 0.52, d * 0.52), root)
	root.rotation.y = rng.randf_range(-0.12, 0.12)
	return root


static func _make_shop(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var w: float = rng.randf_range(3.5, 5.5)
	var wall := _mat(Color(0.72, 0.58, 0.42))
	var awning := _mat(Color(0.82, 0.22, 0.18), 0.55, 0.08)
	var glass := _mat(Color(0.55, 0.72, 0.88, 0.85), 0.25, 0.05)
	_box(Vector3(w, 1.25, 2.8), wall, Vector3(0, 0.62, 0), root)
	_box(Vector3(w * 1.05, 0.12, 3.0), awning, Vector3(0, 1.32, 0.15), root)
	_box(Vector3(w * 0.82, 0.72, 0.08), glass, Vector3(0, 0.72, 1.42), root)
	var lamp := _make_street_lamp()
	lamp.position = Vector3(w * 0.55, 0, 1.8)
	root.add_child(lamp)
	return root


static func _make_building_cluster(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var count: int = rng.randi_range(2, 4)
	for i in count:
		var b := _make_building(rng, rng.randi_range(2, 6))
		b.position = Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-3.5, 3.5))
		b.rotation.y = rng.randf_range(-0.3, 0.3)
		var s: float = rng.randf_range(0.75, 1.05)
		b.scale = Vector3(s, s, s)
		root.add_child(b)
	return root


static func _make_street_lamp() -> Node3D:
	var root := Node3D.new()
	var pole := _mat(Color(0.32, 0.34, 0.36), 0.65)
	var head := _mat(Color(0.95, 0.88, 0.55), 0.4, 0.32)
	_box(Vector3(0.14, 3.6, 0.14), pole, Vector3(0, 1.8, 0), root)
	_box(Vector3(0.55, 0.12, 0.28), head, Vector3(0.18, 3.55, 0), root)
	return root


static func _make_bench() -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color(0.42, 0.28, 0.16), 0.88)
	var metal := _mat(Color(0.25, 0.26, 0.28), 0.7)
	_box(Vector3(1.6, 0.08, 0.55), wood, Vector3(0, 0.52, 0), root)
	_box(Vector3(1.6, 0.08, 0.55), wood, Vector3(0, 0.72, 0), root)
	for x in [-0.65, 0.65]:
		_box(Vector3(0.08, 0.55, 0.08), metal, Vector3(x, 0.28, 0), root)
	return root


static func _make_shed(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var w: float = rng.randf_range(2.5, 4.2)
	var wall := _mat(Color(0.58, 0.42, 0.28))
	var roof := _mat(Color(0.22, 0.18, 0.16))
	_box(Vector3(w, 1.35, 2.2), wall, Vector3(0, 0.68, 0), root)
	_box(Vector3(w * 1.08, 0.22, 2.35), roof, Vector3(0, 1.45, 0), root)
	return root


static func _make_human(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var skin := _mat(Color(0.78, 0.62, 0.48))
	var shirt_palettes: Array = [
		Color(0.22, 0.45, 0.72), Color(0.82, 0.24, 0.22), Color(0.28, 0.62, 0.34),
		Color(0.92, 0.82, 0.22), Color(0.55, 0.38, 0.68),
	]
	var pants_palettes: Array = [Color(0.18, 0.22, 0.32), Color(0.32, 0.28, 0.24), Color(0.42, 0.36, 0.30)]
	var shirt := _mat(shirt_palettes[rng.randi() % shirt_palettes.size()])
	var pants := _mat(pants_palettes[rng.randi() % pants_palettes.size()])
	var hair := _mat(Color(0.12, 0.08, 0.06))
	_box(Vector3(0.42, 0.72, 0.28), shirt, Vector3(0, 0.92, 0), root)
	_box(Vector3(0.18, 0.62, 0.18), pants, Vector3(-0.12, 0.31, 0), root)
	_box(Vector3(0.18, 0.62, 0.18), pants, Vector3(0.12, 0.31, 0), root)
	_sphere(0.16, skin, Vector3(0, 1.48, 0), root)
	_box(Vector3(0.2, 0.08, 0.18), hair, Vector3(0, 1.62, 0), root)
	for sx in [-1, 1]:
		_box(Vector3(0.1, 0.48, 0.1), shirt, Vector3(sx * 0.32, 0.88, 0), root)
	root.rotation.y = rng.randf_range(-0.4, 0.4)
	return root


static func _make_river_strip(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var water_mat: Material = load("res://models/water_shadermat.tres") as Material
	var length: float = rng.randf_range(14.0, 24.0)
	var width: float = rng.randf_range(2.8, 4.5)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, length)
	mi.mesh = pm
	mi.material_override = water_mat
	mi.position = Vector3(0, -0.08, 0)
	root.add_child(mi)
	# simple bank
	var bank := _mat(Color(0.22, 0.34, 0.18))
	_box(Vector3(width * 0.35, 0.12, length), bank, Vector3(-width * 0.55, 0.02, 0), root)
	_box(Vector3(width * 0.35, 0.12, length), bank, Vector3(width * 0.55, 0.02, 0), root)
	if rng.randf() < 0.45:
		var rock := _mat(Color(0.38, 0.36, 0.34), 0.9)
		for i in 3:
			_box(
				Vector3(0.35, 0.22, 0.35),
				rock,
				Vector3(rng.randf_range(-width * 0.3, width * 0.3), 0.08, rng.randf_range(-length * 0.4, length * 0.4)),
				root
			)
	return root


static func _make_bridge(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var deck := _mat(Color(0.42, 0.40, 0.38), 0.75)
	var rail := _mat(Color(0.28, 0.30, 0.32), 0.7)
	var span: float = rng.randf_range(5.0, 8.0)
	_box(Vector3(span, 0.18, 1.8), deck, Vector3(0, 0.55, 0), root)
	for sx in [-1, 1]:
		_box(Vector3(span, 0.55, 0.1), rail, Vector3(0, 0.82, sx * 0.95), root)
		_box(Vector3(0.22, 0.55, 0.22), rail, Vector3(-span * 0.5, 0.82, sx * 0.5), root)
		_box(Vector3(0.22, 0.55, 0.22), rail, Vector3(span * 0.5, 0.82, sx * 0.5), root)
	var water := _make_river_strip(rng)
	water.position.y = -0.35
	root.add_child(water)
	return root
