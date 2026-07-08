class_name VegetationLayer
extends RefCounted

## Layer 2 - low ground cover / surfaces you walk over or through.
## Roads and paths live here too, since they're just a different kind of ground cover.

enum Type {
	NONE, BARE, SHORT_GRASS, LONG_GRASS, YOUNG_TREES,
	GRAVEL_ROAD, COBBLE_ROAD, DIRT_PATH, ASPHALT_ROAD, RUNWAY
}

const ROAD_TYPES = [Type.GRAVEL_ROAD, Type.COBBLE_ROAD, Type.DIRT_PATH, Type.ASPHALT_ROAD, Type.RUNWAY]

## Extra movement cost added on top of ground traction (roads are negative = faster).
const MOVE_COST = {
	Type.NONE: 0.0,
	Type.BARE: 0.0,
	Type.SHORT_GRASS: 0.1,
	Type.LONG_GRASS: 0.3,
	Type.YOUNG_TREES: 0.6,
	Type.GRAVEL_ROAD: -0.5,
	Type.COBBLE_ROAD: -0.6,
	Type.DIRT_PATH: -0.3,
	Type.ASPHALT_ROAD: -0.8,
	Type.RUNWAY: -0.8,
}

## Concealment given to a unit standing in this vegetation (0-1).
const CONCEALMENT = {
	Type.NONE: 0.0,
	Type.BARE: 0.0,
	Type.SHORT_GRASS: 0.05,
	Type.LONG_GRASS: 0.25,
	Type.YOUNG_TREES: 0.4,
	Type.GRAVEL_ROAD: 0.0,
	Type.COBBLE_ROAD: 0.0,
	Type.DIRT_PATH: 0.0,
	Type.ASPHALT_ROAD: 0.0,
	Type.RUNWAY: 0.0,
}

const COLORS = {
	Type.NONE: Color(0, 0, 0, 0),
	Type.BARE: Color(0.60, 0.55, 0.45),
	Type.SHORT_GRASS: Color(0.55, 0.68, 0.30),
	Type.LONG_GRASS: Color(0.45, 0.60, 0.22),
	Type.YOUNG_TREES: Color(0.30, 0.55, 0.28),
	Type.GRAVEL_ROAD: Color(0.68, 0.65, 0.58),
	Type.COBBLE_ROAD: Color(0.60, 0.58, 0.55),
	Type.DIRT_PATH: Color(0.50, 0.40, 0.28),
	Type.ASPHALT_ROAD: Color(0.20, 0.20, 0.22),
	Type.RUNWAY: Color(0.25, 0.25, 0.27),
}

static func is_road(type: int) -> bool:
	return ROAD_TYPES.has(type)
