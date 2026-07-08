class_name Bridge
extends Structure

## Layer 3 special case: sits on a WATER hex and, unlike every other
## structure, does NOT block movement - it's specifically what lets a road
## (or a unit) cross a river instead of being stopped by it.

enum BridgeType { WOODEN_PEDESTRIAN, METAL_DRAWBRIDGE, CONCRETE_FLAT }

var bridge_type: int
var max_weight_tons: float
var width_m: float
var deck_directions: Array = []   # up to 2 HexUtils.DIRECTIONS indices - which edges the road enters/exits from

const MAX_WEIGHT_TONS = {
	BridgeType.WOODEN_PEDESTRIAN: 0.3,   # foot traffic, maybe a bicycle
	BridgeType.METAL_DRAWBRIDGE: 40.0,   # light vehicles, half-tracks
	BridgeType.CONCRETE_FLAT: 60.0,      # trucks, most armor
}

const WIDTH_M = {
	BridgeType.WOODEN_PEDESTRIAN: 1.5,
	BridgeType.METAL_DRAWBRIDGE: 4.0,
	BridgeType.CONCRETE_FLAT: 6.0,
}

## Extra movement cost added on top of the base 1.0 "normal ground" rate -
## this replaces the underlying water traction entirely once a bridge exists.
const MOVE_COST_OVERRIDE = {
	BridgeType.WOODEN_PEDESTRIAN: 0.3,   # narrow, foot-only, adds some friction
	BridgeType.METAL_DRAWBRIDGE: 0.1,
	BridgeType.CONCRETE_FLAT: -0.2,      # as fast as a paved road
}

const BRIDGE_COLORS = {
	BridgeType.WOODEN_PEDESTRIAN: Color(0.55, 0.40, 0.25),
	BridgeType.METAL_DRAWBRIDGE: Color(0.50, 0.50, 0.55),
	BridgeType.CONCRETE_FLAT: Color(0.75, 0.75, 0.72),
}

func _init(_bridge_type: int) -> void:
	super(Structure.Kind.BRIDGE, _bridge_type, 0)
	bridge_type = _bridge_type
	blocks_movement = false
	max_weight_tons = MAX_WEIGHT_TONS[_bridge_type]
	width_m = WIDTH_M[_bridge_type]

func can_support(weight_tons: float) -> bool:
	return weight_tons <= max_weight_tons
