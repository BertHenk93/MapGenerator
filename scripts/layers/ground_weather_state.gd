class_name GroundWeatherState
extends RefCounted

## Per-tile mutable state for layer 5 - how wet/snowed-over this specific hex
## currently is. Updated over time by whatever system is driving the weather.

var type: int = GroundWeather.Type.DRY
var depth: float = 0.0   # accumulation, roughly 0-1 (dry -> saturated/deep snow)

func _init(_type: int = GroundWeather.Type.DRY, _depth: float = 0.0) -> void:
	type = _type
	depth = _depth
