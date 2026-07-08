class_name MapGenerator
extends RefCounted

## Procedural hex map generator for a WW2-style European countryside map.
## Populates all 5 static/semi-static tile layers: ground type, vegetation
## (incl. roads), structures, sparse initial wildlife, and default (dry)
## ground weather. Layer 7 (clouds) and global time/brightness are handled
## separately by WeatherSystem / TimeSystem since they're live systems, not
## something baked into the map once.

enum MapShape { SQUARE, RANDOM }

@export var map_width_km: float = 5.0
@export var map_height_km: float = 5.0
@export var hex_size_m: float = 100.0
@export var seed_value: int = 0
@export var map_shape: MapShape = MapShape.RANDOM
@export var map_shape_detail: float = 0.025    # noise frequency - lower = broader coastline features
@export var map_shape_fill: float = 0.42       # lower = larger/fuller shape, higher = smaller/more carved
@export var num_villages: int = 5
@export var num_rivers: int = 2
@export var river_branch_chance: float = 0.10
@export var village_min_radius: int = 1
@export var village_max_radius: int = 2
@export var boulder_chance: float = 0.08
@export var mature_tree_chance: float = 0.45   # of hexes that roll as forest
@export var wildlife_chance: float = 0.015

const WATER_THRESHOLD: float = 0.32
const HILL_THRESHOLD: float = 0.62
const FOREST_NOISE_THRESHOLD: float = 0.55
const FOREST_MOISTURE_THRESHOLD: float = 0.40
const MIN_RIVER_LENGTH: int = 8
const MAX_RIVER_BRANCH_DEPTH: int = 1
const PIT_ESCAPE_SEARCH_LIMIT: int = 400

var cols: int
var rows: int
var hexes: Dictionary = {}   # Vector2i(q, r) -> HexTile
var villages: Array = []     # Village instances

var _elevation_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var _forest_noise: FastNoiseLite
var _ground_noise: FastNoiseLite
var _shape_noise: FastNoiseLite
var _rng: RandomNumberGenerator

func generate() -> Dictionary:
	cols = int(round(map_width_km * 1000.0 / hex_size_m))
	rows = int(round(map_height_km * 1000.0 / hex_size_m))
	hexes.clear()
	villages.clear()

	_setup_noise()
	_generate_elevation_and_moisture()
	_generate_rivers()
	_assign_ground_types()
	_assign_vegetation()
	_generate_forest_structures()
	_generate_boulders()
	_place_villages()
	_compute_village_walls()
	_generate_roads()
	_spawn_wildlife()

	return hexes

func _setup_noise() -> void:
	var rng_seed: int = seed_value if seed_value != 0 else randi()
	_rng = RandomNumberGenerator.new()
	_rng.seed = rng_seed

	_elevation_noise = FastNoiseLite.new()
	_elevation_noise.seed = rng_seed
	_elevation_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_elevation_noise.frequency = 0.045
	_elevation_noise.fractal_octaves = 4
	_elevation_noise.fractal_gain = 0.5

	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = rng_seed + 1000
	_moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_moisture_noise.frequency = 0.08

	_forest_noise = FastNoiseLite.new()
	_forest_noise.seed = rng_seed + 2000
	_forest_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_forest_noise.frequency = 0.12

	_ground_noise = FastNoiseLite.new()
	_ground_noise.seed = rng_seed + 3000
	_ground_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_ground_noise.frequency = 0.10

	_shape_noise = FastNoiseLite.new()
	_shape_noise.seed = rng_seed + 4000
	_shape_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_shape_noise.frequency = map_shape_detail
	_shape_noise.fractal_octaves = 2

func _generate_elevation_and_moisture() -> void:
	for col in range(cols):
		for row in range(rows):
			if not _is_within_map_shape(col, row):
				continue
			var coord = HexUtils.offset_to_axial(col, row)
			var tile = HexTile.new(coord.x, coord.y)
			tile.elevation = (_elevation_noise.get_noise_2d(col, row) + 1.0) / 2.0
			tile.moisture = (_moisture_noise.get_noise_2d(col, row) + 1.0) / 2.0
			hexes[coord] = tile

## For MapShape.RANDOM, carves an organic, county/province-like boundary out
## of the rectangular grid instead of a hard edge: the center is always
## included, corners are mostly excluded (rounding them off), and the noise
## makes the edge wobble in and out rather than following a straight line.
## Every other generation step only ever iterates hexes.keys(), so simply
## not creating a hex here is enough to keep it out of the map everywhere
## else (rivers, roads, villages, rendering all already check hexes.has()).
func _is_within_map_shape(col: int, row: int) -> bool:
	if map_shape == MapShape.SQUARE:
		return true

	var nx = (float(col) / float(max(cols - 1, 1))) * 2.0 - 1.0
	var ny = (float(row) / float(max(rows - 1, 1))) * 2.0 - 1.0
	var dist = sqrt(nx * nx + ny * ny) / 1.41421356

	var noise_val = (_shape_noise.get_noise_2d(col, row) + 1.0) / 2.0
	var shaped = noise_val * 0.55 + (1.0 - dist) * 0.45
	return shaped > map_shape_fill

func _generate_rivers() -> void:
	var candidates: Array = []
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		if tile.elevation > 0.7:
			candidates.append(coord)
	candidates.shuffle()

	var rivers_made = 0
	for coord in candidates:
		if rivers_made >= num_rivers:
			break
		var path = _trace_downhill_path(coord)
		if path.size() >= MIN_RIVER_LENGTH:
			_mark_river_path(path, 0)
			rivers_made += 1

## Follows steepest descent from `start`, escaping shallow local dips by
## searching outward for the nearest lower ground (or an existing river) so
## rivers reach genuinely low terrain instead of stalling in small pits.
func _trace_downhill_path(start: Vector2i, seed_visited: Dictionary = {}) -> Array:
	var path: Array = [start]
	var visited: Dictionary = seed_visited.duplicate()
	visited[start] = true
	var current = start

	for i in range(cols + rows):
		var current_tile: HexTile = hexes[current]
		if current_tile.elevation < WATER_THRESHOLD or current_tile.has_river:
			break

		var best = _best_downhill_neighbor(current, visited)
		if best == null:
			var spill = _find_spill_path(current, current_tile.elevation, visited)
			if spill.is_empty():
				break
			for c in spill:
				path.append(c)
				visited[c] = true
			current = spill[spill.size() - 1]
			continue

		path.append(best)
		visited[best] = true
		current = best

	return path

func _best_downhill_neighbor(coord: Vector2i, visited: Dictionary):
	var current_tile: HexTile = hexes[coord]
	var best = null
	var best_elev = current_tile.elevation
	for n in HexUtils.neighbors(coord):
		if hexes.has(n) and not visited.has(n):
			var ntile: HexTile = hexes[n]
			if ntile.elevation < best_elev:
				best_elev = ntile.elevation
				best = n
	return best

## Bounded Dijkstra search for the nearest hex that's genuinely lower than
## `current_elev`, or that's already part of another river (a rejoin). Cost
## is the elevation gained en route, so it finds the cheapest way over a
## small ridge rather than the geometrically nearest point.
func _find_spill_path(start: Vector2i, current_elev: float, visited: Dictionary) -> Array:
	var dist: Dictionary = {start: 0.0}
	var came_from: Dictionary = {}
	var frontier: Array = [start]
	var expanded = 0

	while frontier.size() > 0 and expanded < PIT_ESCAPE_SEARCH_LIMIT:
		frontier.sort_custom(func(a, b): return dist.get(a, INF) < dist.get(b, INF))
		var node = frontier.pop_front()
		expanded += 1
		var node_tile: HexTile = hexes[node]

		if node != start and (node_tile.elevation < current_elev or node_tile.has_river):
			var path = [node]
			var c = node
			while came_from.has(c):
				c = came_from[c]
				path.push_front(c)
			return path

		for n in HexUtils.neighbors(node):
			if not hexes.has(n) or visited.has(n):
				continue
			var n_tile: HexTile = hexes[n]
			var step_cost = max(n_tile.elevation - node_tile.elevation, 0.0)
			var new_dist = dist.get(node, 0.0) + step_cost
			if new_dist < dist.get(n, INF):
				dist[n] = new_dist
				came_from[n] = node
				if not frontier.has(n):
					frontier.append(n)

	return []

## Marks a traced path as river, and - away from its very start/end - has a
## small chance to peel off a distributary that flows to its own separate
## endpoint (a "split"). If that branch's path later runs into another
## river, it naturally merges there (a "rejoin"), since tracing always stops
## on contact with an existing river tile.
func _mark_river_path(path: Array, depth: int) -> void:
	var path_visited: Dictionary = {}
	for c in path:
		path_visited[c] = true

	for i in range(path.size()):
		var coord = path[i]
		var tile: HexTile = hexes[coord]
		tile.has_river = true
		tile.elevation = max(tile.elevation - 0.05, 0.0)

		if depth < MAX_RIVER_BRANCH_DEPTH and i > 2 and i < path.size() - 2 and _rng.randf() < river_branch_chance:
			var branch_next = _best_downhill_neighbor(coord, path_visited)
			if branch_next != null:
				var branch_path = _trace_downhill_path(branch_next, path_visited)
				if branch_path.size() >= 2:
					_mark_river_path(branch_path, depth + 1)

func _assign_ground_types() -> void:
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		var gnoise = (_ground_noise.get_noise_2d(coord.x, coord.y) + 1.0) / 2.0

		if tile.has_river or tile.elevation < WATER_THRESHOLD:
			tile.ground_type = GroundLayer.Type.WATER
		elif tile.elevation > HILL_THRESHOLD:
			tile.ground_type = GroundLayer.Type.ROCK if tile.moisture < 0.45 else GroundLayer.Type.GRAVEL
		elif tile.moisture > 0.62:
			tile.ground_type = GroundLayer.Type.MUD
		elif gnoise > 0.65:
			tile.ground_type = GroundLayer.Type.GRAVEL
		elif gnoise < 0.18:
			tile.ground_type = GroundLayer.Type.SAND
		else:
			tile.ground_type = GroundLayer.Type.LIME

func _assign_vegetation() -> void:
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		if tile.ground_type == GroundLayer.Type.WATER:
			tile.vegetation = VegetationLayer.Type.NONE
		elif tile.moisture > 0.55:
			tile.vegetation = VegetationLayer.Type.LONG_GRASS
		else:
			tile.vegetation = VegetationLayer.Type.SHORT_GRASS

func _generate_forest_structures() -> void:
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		if tile.ground_type == GroundLayer.Type.WATER:
			continue
		var fnoise = (_forest_noise.get_noise_2d(coord.x, coord.y) + 1.0) / 2.0
		if fnoise > FOREST_NOISE_THRESHOLD and tile.moisture > FOREST_MOISTURE_THRESHOLD:
			tile.vegetation = VegetationLayer.Type.YOUNG_TREES
			if _rng.randf() < mature_tree_chance:
				tile.structure = Structure.new(Structure.Kind.MATURE_TREE, _pick_tree_species(tile), 1)

func _pick_tree_species(tile: HexTile) -> int:
	if tile.has_river or tile.moisture > 0.75:
		return Structure.TreeSpecies.WILLOW
	if tile.elevation > HILL_THRESHOLD - 0.1:
		return Structure.TreeSpecies.SPRUCE if _rng.randf() < 0.5 else Structure.TreeSpecies.PINE
	return Structure.TreeSpecies.OAK if _rng.randf() < 0.5 else Structure.TreeSpecies.BIRCH

func _generate_boulders() -> void:
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		if tile.structure != null:
			continue
		if tile.ground_type == GroundLayer.Type.ROCK and _rng.randf() < boulder_chance:
			tile.structure = Structure.new(Structure.Kind.BOULDER, -1, 1)

func _place_villages() -> void:
	var good_ground = [GroundLayer.Type.LIME, GroundLayer.Type.GRAVEL, GroundLayer.Type.CLAY]
	var candidates: Array = []
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		if tile.structure != null or not good_ground.has(tile.ground_type):
			continue
		if tile.vegetation == VegetationLayer.Type.YOUNG_TREES:
			continue
		var score = 1.0 - abs(tile.elevation - 0.45)
		if tile.has_river:
			score += 0.5
		candidates.append({"coord": coord, "score": score})

	candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	var min_distance = max(int(cols / float(num_villages + 1)), 3) + village_max_radius * 2
	var placed_centers: Array = []

	for c in candidates:
		if placed_centers.size() >= num_villages:
			break
		var far_enough = true
		for p in placed_centers:
			if HexUtils.distance(c["coord"], p) < min_distance:
				far_enough = false
				break
		if not far_enough:
			continue

		var center: Vector2i = c["coord"]
		placed_centers.append(center)

		var village = Village.new(center)
		var radius = _rng.randi_range(village_min_radius, village_max_radius)
		village.hexes = _grow_village_footprint(center, radius)

		for coord in village.hexes:
			var tile: HexTile = hexes[coord]
			tile.is_village = true
			tile.village_ref = village
			if tile.ground_type == GroundLayer.Type.WATER:
				tile.is_canal = true
				continue
			tile.structure = null
			tile.vegetation = VegetationLayer.Type.COBBLE_ROAD if coord == center else VegetationLayer.Type.SHORT_GRASS

		_place_village_buildings(village)
		_assign_population(village)
		villages.append(village)

## Claims every unclaimed hex within `radius` of `center` for this village,
## water included - a river running through means the village gets a canal
## (see _place_village_buildings), not a gap that splits the town in two.
func _grow_village_footprint(center: Vector2i, radius: int) -> Array:
	var footprint: Array = []
	for coord in hexes.keys():
		if HexUtils.distance(center, coord) > radius:
			continue
		var tile: HexTile = hexes[coord]
		if tile.village_ref == null:
			footprint.append(coord)
	return footprint

func _place_village_buildings(village: Village) -> void:
	var well = Structure.new(Structure.Kind.BUILDING, Structure.BuildingKind.WELL, 0)
	well.blocks_movement = false
	hexes[village.center].structure = well

	var others: Array = []
	var canal_hexes: Array = []
	for coord in village.hexes:
		if coord == village.center:
			continue
		if hexes[coord].is_canal:
			canal_hexes.append(coord)
		else:
			others.append(coord)
	others.shuffle()

	var building_count = int(others.size() * 0.65)
	var church_placed = false

	for i in range(others.size()):
		var tile: HexTile = hexes[others[i]]
		if i >= building_count:
			tile.vegetation = VegetationLayer.Type.COBBLE_ROAD  # open square / street
			continue

		var kind: int
		if not church_placed and _rng.randf() < 0.2:
			kind = Structure.BuildingKind.CHURCH
			church_placed = true
		elif _rng.randf() < 0.15:
			kind = Structure.BuildingKind.BARN
		else:
			kind = Structure.BuildingKind.HOUSE
		tile.structure = Structure.new(Structure.Kind.BUILDING, kind, _rng.randi_range(2, 6))

	# Only bridge canal hexes that actually border a normal town tile (bridging
	# into open water helps nobody), and even then only about one crossing
	# per 3 hexes of canal - a river through town shouldn't be wall-to-wall
	# bridges. Unbridged canal hexes stay a visible-but-uncrossable stream.
	var bridgeable: Array = []
	for coord in canal_hexes:
		if _has_land_neighbor(coord):
			bridgeable.append(coord)
	for i in range(bridgeable.size()):
		if i % 3 == 0:
			_ensure_canal_crossing(bridgeable[i])

func _has_land_neighbor(coord: Vector2i) -> bool:
	for n in HexUtils.neighbors(coord):
		if hexes.has(n):
			var ntile: HexTile = hexes[n]
			if ntile.village_ref != null and not ntile.is_canal:
				return true
	return false

## A river hex claimed by a village gets a footbridge so the town stays
## walkable as one place rather than being split by the water. If the road
## network later needs a proper crossing here, _apply_road can upgrade it.
func _ensure_canal_crossing(coord: Vector2i) -> void:
	var tile: HexTile = hexes[coord]
	if tile.structure != null:
		return
	var bridge = Bridge.new(Bridge.BridgeType.WOODEN_PEDESTRIAN)
	bridge.deck_directions = _canal_deck_directions(coord)
	tile.structure = bridge

## Picks the two neighboring land hexes (within the same village) that are
## closest to directly opposite each other, so the footbridge spans the
## canal cleanly instead of at a sharp angle.
func _canal_deck_directions(coord: Vector2i) -> Array:
	var land_dirs: Array = []
	for d in range(HexUtils.DIRECTIONS.size()):
		var n = coord + HexUtils.DIRECTIONS[d]
		if hexes.has(n):
			var ntile: HexTile = hexes[n]
			if ntile.village_ref != null and not ntile.is_canal:
				land_dirs.append(d)

	if land_dirs.size() < 2:
		return [0, 3]

	var best_pair = [land_dirs[0], land_dirs[1]]
	var best_diff = -1
	for i in range(land_dirs.size()):
		for j in range(i + 1, land_dirs.size()):
			var diff = abs(land_dirs[i] - land_dirs[j])
			diff = min(diff, 6 - diff)
			if diff > best_diff:
				best_diff = diff
				best_pair = [land_dirs[i], land_dirs[j]]
	return best_pair

func _assign_population(village: Village) -> void:
	var base = 15 + village.hexes.size() * 8
	var total = int(base * _rng.randf_range(0.7, 1.3))
	# WW2 setting: many military-age men are away, so villages skew toward
	# women and children.
	var children_ratio = _rng.randf_range(0.30, 0.40)
	var women_ratio = _rng.randf_range(0.38, 0.45)
	village.children = int(total * children_ratio)
	village.women = int(total * women_ratio)
	village.men = max(total - village.children - village.women, 0)

## Marks, per hex and per side, which of a village's edges face outside its
## own footprint - this becomes the outer wall, with no extra bookkeeping
## needed for "which hexes are on the boundary".
func _compute_village_walls() -> void:
	for village in villages:
		for coord in village.hexes:
			var tile: HexTile = hexes[coord]
			for d in range(HexUtils.DIRECTIONS.size()):
				var neighbor = coord + HexUtils.DIRECTIONS[d]
				var neighbor_tile = hexes.get(neighbor)
				var neighbor_in_village = neighbor_tile != null and neighbor_tile.village_ref == village
				if not neighbor_in_village:
					tile.wall_sides[d] = true

## Opens a gate wherever a generated road actually crosses a village's wall.
func _cut_village_gates(village: Village) -> void:
	for coord in village.hexes:
		var tile: HexTile = hexes[coord]
		if not VegetationLayer.is_road(tile.vegetation):
			continue
		for d in range(HexUtils.DIRECTIONS.size()):
			if not tile.wall_sides[d]:
				continue
			var neighbor = coord + HexUtils.DIRECTIONS[d]
			var neighbor_tile = hexes.get(neighbor)
			if neighbor_tile != null and VegetationLayer.is_road(neighbor_tile.vegetation) and neighbor_tile.village_ref != village:
				tile.wall_sides[d] = false

func _generate_roads() -> void:
	if villages.size() < 2:
		return

	var connected: Array = [villages[0]]
	var remaining: Array = villages.slice(1, villages.size())

	while remaining.size() > 0:
		var best_pair = null   # {"a": Vector2i, "b": Vector2i, "village": Village}
		var best_dist = INF
		for va in connected:
			for vb in remaining:
				var pair = _closest_footprint_pair(va, vb)
				if pair["dist"] < best_dist:
					best_dist = pair["dist"]
					best_pair = {"a": pair["coord_a"], "b": pair["coord_b"], "village": vb}

		var path = _find_road_path(best_pair["a"], best_pair["b"])
		_apply_road(path)

		connected.append(best_pair["village"])
		remaining.erase(best_pair["village"])

	for village in villages:
		_cut_village_gates(village)

## Finds the closest pair of non-blocking hexes between two villages' footprints
## (the well is always non-blocking, so there's always at least one candidate).
func _closest_footprint_pair(va: Village, vb: Village) -> Dictionary:
	var best_a: Vector2i = va.hexes[0]
	var best_b: Vector2i = vb.hexes[0]
	var best_dist = INF
	for a in va.hexes:
		var a_tile: HexTile = hexes[a]
		if a_tile.structure != null and a_tile.structure.blocks_movement:
			continue
		for b in vb.hexes:
			var b_tile: HexTile = hexes[b]
			if b_tile.structure != null and b_tile.structure.blocks_movement:
				continue
			var d = HexUtils.distance(a, b)
			if d < best_dist:
				best_dist = d
				best_a = a
				best_b = b
	return {"coord_a": best_a, "coord_b": best_b, "dist": best_dist}

func _apply_road(path: Array) -> void:
	for i in range(path.size()):
		var coord = path[i]
		var tile: HexTile = hexes[coord]

		if tile.ground_type == GroundLayer.Type.WATER:
			var needs_bridge = tile.structure == null
			var is_upgradeable_footbridge = tile.structure is Bridge and tile.structure.bridge_type == Bridge.BridgeType.WOODEN_PEDESTRIAN
			if needs_bridge or is_upgradeable_footbridge:
				var bridge = Bridge.new(_pick_bridge_type())
				bridge.deck_directions = _path_deck_directions(path, i)
				tile.structure = bridge
			continue

		if tile.structure != null and tile.structure.blocks_movement:
			continue

		var near_village = tile.is_village
		if not near_village:
			for n in HexUtils.neighbors(coord):
				if hexes.has(n) and hexes[n].is_village:
					near_village = true
					break
		tile.vegetation = VegetationLayer.Type.COBBLE_ROAD if near_village else VegetationLayer.Type.GRAVEL_ROAD

## Which of this hex's 6 neighbor directions the road actually arrives from
## and leaves toward, so the bridge deck can be drawn along the real path
## direction instead of some fixed axis.
func _path_deck_directions(path: Array, index: int) -> Array:
	var coord: Vector2i = path[index]
	var dirs: Array = []
	if index > 0:
		dirs.append(HexUtils.DIRECTIONS.find(path[index - 1] - coord))
	if index < path.size() - 1:
		dirs.append(HexUtils.DIRECTIONS.find(path[index + 1] - coord))
	return dirs

## Rural WW2 setting, so keep it modest: mostly wooden/metal crossings, with
## a proper concrete span being the least common.
func _pick_bridge_type() -> int:
	var roll = _rng.randf()
	if roll < 0.4:
		return Bridge.BridgeType.WOODEN_PEDESTRIAN
	elif roll < 0.8:
		return Bridge.BridgeType.METAL_DRAWBRIDGE
	else:
		return Bridge.BridgeType.CONCRETE_FLAT

func _find_road_path(start: Vector2i, goal: Vector2i) -> Array:
	var open_set: Array = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: float(HexUtils.distance(start, goal))}

	while open_set.size() > 0:
		open_set.sort_custom(func(a, b): return f_score.get(a, INF) < f_score.get(b, INF))
		var current = open_set.pop_front()

		if current == goal:
			var path = [current]
			while came_from.has(current):
				current = came_from[current]
				path.push_front(current)
			return path

		for n in HexUtils.neighbors(current):
			if not hexes.has(n):
				continue
			var ntile: HexTile = hexes[n]
			if ntile.structure != null and ntile.structure.blocks_movement:
				continue
			var tentative_g = g_score.get(current, INF) + ntile.movement_cost()
			if tentative_g < g_score.get(n, INF):
				came_from[n] = current
				g_score[n] = tentative_g
				f_score[n] = tentative_g + HexUtils.distance(n, goal)
				if not open_set.has(n):
					open_set.append(n)

	return []

func _spawn_wildlife() -> void:
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		if tile.is_village or tile.structure != null:
			continue
		if tile.vegetation != VegetationLayer.Type.YOUNG_TREES and tile.vegetation != VegetationLayer.Type.LONG_GRASS:
			continue
		if _rng.randf() < wildlife_chance:
			tile.add_occupant(LivingEntity.new(LivingEntity.Kind.ANIMAL, LivingEntity.AnimalSpecies.DEER))
