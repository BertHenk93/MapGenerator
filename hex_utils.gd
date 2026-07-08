class_name HexTile
extends RefCounted

var q: int
var r: int
var elevation: float = 0.0
var moisture: float = 0.0

var ground_type: int = GroundLayer.Type.LIME        # layer 1
var vegetation: int = VegetationLayer.Type.BARE     # layer 2
var structure: Structure = null                     # layer 3 - null if empty
var occupants: Array = []                           # layer 4 - LivingEntity standing in the open
var ground_weather: GroundWeatherState              # layer 5

var has_river: bool = false
var is_village: bool = false
var village_ref: Village = null            # null if this hex isn't part of a village
var is_canal: bool = false                 # true if this is a water hex claimed by a village (auto-bridged)
var wall_sides: Array = [false, false, false, false, false, false]  # indexed by HexUtils.DIRECTIONS/EDGE_FOR_DIRECTION

func _init(_q: int, _r: int) -> void:
	q = _q
	r = _r
	ground_weather = GroundWeatherState.new()

func blocks_movement() -> bool:
	if structure != null and structure.kind == Structure.Kind.BRIDGE:
		return false
	if ground_type == GroundLayer.Type.WATER:
		return true
	return structure != null and structure.blocks_movement

func add_occupant(entity: LivingEntity) -> void:
	occupants.append(entity)

func remove_occupant(entity: LivingEntity) -> void:
	occupants.erase(entity)

## Combined movement cost across ground, vegetation and current ground weather.
## A bridge replaces the underlying (very high) water cost with its own rate.
func movement_cost() -> float:
	if structure != null and structure.kind == Structure.Kind.BRIDGE:
		var bridge: Bridge = structure
		return max(1.0 + bridge.MOVE_COST_OVERRIDE[bridge.bridge_type], 0.2)

	var cost = GroundLayer.TRACTION[ground_type]
	cost += VegetationLayer.MOVE_COST[vegetation]
	cost += GroundWeather.TRACTION_PENALTY[ground_weather.type]
	return max(cost, 0.2)
