class_name SegmentMapGen
extends RefCounted

## Deterministic gameplay spawns for one server segment.


static func generate(segment_seed: int) -> Array:
	var entries: Array = []
	var object_id: int = 1
	var chunk_count: int = int(ceil(SimConstants.SEGMENT_LENGTH / SimConstants.CHUNK_LENGTH))
	var lane_last_rock: Array = [-9999.0, -9999.0, -9999.0]

	for chunk_index in chunk_count:
		var rng := SeededRng.new(SeededRng.chunk_seed(segment_seed, chunk_index))
		var chunk_start: float = chunk_index * SimConstants.CHUNK_LENGTH
		var difficulty: float = clampf(chunk_index / float(chunk_count), 0.0, 1.0)

		var rock_count: int = rng.randi_range(0, 1 if difficulty < 0.35 else 2)
		var lanes: Array = [0, 1, 2]
		_shuffle_array(lanes, rng)

		for i in rock_count:
			var lane: int = lanes[i % lanes.size()]
			var dist: float = chunk_start + rng.randf_range(25.0, SimConstants.CHUNK_LENGTH - 25.0)
			if dist - lane_last_rock[lane] < SimConstants.MIN_ROCK_GAP:
				continue
			lane_last_rock[lane] = dist
			entries.append({
				"kind": "rock",
				"lane": lane,
				"distance": dist,
				"object_id": object_id,
			})
			object_id += 1

		var coin_roll: float = rng.randf()
		if coin_roll > 0.25:
			var lane: int = rng.randi_mod(SimConstants.NUM_LANES)
			var count: int = rng.randi_range(3, 6)
			var base_dist: float = chunk_start + rng.randf_range(15.0, SimConstants.CHUNK_LENGTH - count * SimConstants.MIN_COIN_GAP - 10.0)
			for j in count:
				entries.append({
					"kind": "coin",
					"lane": lane,
					"distance": base_dist + j * SimConstants.MIN_COIN_GAP,
					"object_id": object_id,
				})
				object_id += 1

	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.distance == b.distance:
			return a.object_id < b.object_id
		return a.distance < b.distance
	)
	return entries


static func _shuffle_array(arr: Array, rng: SeededRng) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
