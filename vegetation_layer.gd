class_name GroundWeather
extends RefCounted

## Layer 5 - transient ground condition, driven by whatever high-level weather
## (layer 7, see weather_system.gd) has been passing overhead recently.

enum Type { DRY, WET, PUDDLES, SNOW_LIGHT, SNOW_DEEP, ICE }

## Extra movement cost added on top of ground + vegetation cost.
const TRACTION_PENALTY = {
	Type.DRY: 0.0,
	Type.WET: 0.15,
	Type.PUDDLES: 0.35,
	Type.SNOW_LIGHT: 0.25,
	Type.SNOW_DEEP: 0.9,
	Type.ICE: 0.6,
}

## Visual tint overlay (alpha scales with accumulation depth at draw time).
const TINT = {
	Type.DRY: Color(0, 0, 0, 0),
	Type.WET: Color(0.1, 0.1, 0.2, 0.15),
	Type.PUDDLES: Color(0.1, 0.15, 0.3, 0.30),
	Type.SNOW_LIGHT: Color(1, 1, 1, 0.30),
	Type.SNOW_DEEP: Color(1, 1, 1, 0.65),
	Type.ICE: Color(0.7, 0.85, 1.0, 0.40),
}
