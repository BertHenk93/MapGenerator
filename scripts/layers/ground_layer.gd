class_name GroundLayer
extends RefCounted

## Layer 1 - base ground you walk ON. Always present, never blocks movement by itself
## (except WATER, which is a hard block unless a bridge/ford mechanic is added later).

enum Type { MUD, CLAY, ROCK, GRAVEL, WATER, SAND, LIME }

## Base traction multiplier before vegetation/weather modifiers. 1.0 = normal going.
const TRACTION = {
	Type.MUD: 1.6,
	Type.CLAY: 1.4,
	Type.ROCK: 1.3,
	Type.GRAVEL: 1.1,
	Type.WATER: 8.0,
	Type.SAND: 1.5,
	Type.LIME: 1.0,
}

const COLORS = {
	Type.MUD: Color(0.36, 0.25, 0.16),
	Type.CLAY: Color(0.55, 0.35, 0.25),
	Type.ROCK: Color(0.55, 0.55, 0.55),
	Type.GRAVEL: Color(0.65, 0.62, 0.55),
	Type.WATER: Color(0.25, 0.45, 0.75),
	Type.SAND: Color(0.83, 0.75, 0.55),
	Type.LIME: Color(0.72, 0.70, 0.55),
}
