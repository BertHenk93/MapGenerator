class_name WeatherSystem
extends RefCounted

## Layer 7 - high level weather: clouds/rainclouds drifting across the whole map.
## Not stored per-tile; it's a moving field you sample by world position (in meters).
## Sampling it is what drives layer 5 (ground_weather) and, combined with TimeSystem,
## the global brightness.

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

@export var season: int = Season.WINTER
@export var wind_speed_mps: float = 3.0     # how fast cloud cover drifts, meters/sec
@export var wind_angle_deg: float = 25.0
@export var storm_intensity: float = 0.55   # 0-1, chance a cloudy area is actively precipitating

var elapsed_time: float = 0.0
var _cloud_noise: FastNoiseLite
var _storm_noise: FastNoiseLite

func _init(rng_seed: int = 0) -> void:
	var s: int = rng_seed if rng_seed != 0 else randi()

	_cloud_noise = FastNoiseLite.new()
	_cloud_noise.seed = s
	_cloud_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_cloud_noise.frequency = 0.0006
	_cloud_noise.fractal_octaves = 3

	_storm_noise = FastNoiseLite.new()
	_storm_noise.seed = s + 500
	_storm_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_storm_noise.frequency = 0.0009

func update(delta: float) -> void:
	elapsed_time += delta

func _wind_offset() -> Vector2:
	var dir = Vector2.RIGHT.rotated(deg_to_rad(wind_angle_deg))
	return dir * wind_speed_mps * elapsed_time

## `world_pos` is a real-world meter position, e.g. HexUtils.axial_to_pixel(coord, hex_size_m).
func get_cloud_cover(world_pos: Vector2) -> float:
	var offset = _wind_offset()
	var n = _cloud_noise.get_noise_2d(world_pos.x - offset.x, world_pos.y - offset.y)
	return clamp((n + 1.0) / 2.0, 0.0, 1.0)

func is_precipitating(world_pos: Vector2) -> bool:
	if get_cloud_cover(world_pos) < 0.6:
		return false
	var offset = _wind_offset()
	var storm = (_storm_noise.get_noise_2d(world_pos.x - offset.x, world_pos.y - offset.y) + 1.0) / 2.0
	return storm < storm_intensity

func is_snow_season() -> bool:
	return season == Season.WINTER

func precipitation_ground_type() -> int:
	return GroundWeather.Type.SNOW_LIGHT if is_snow_season() else GroundWeather.Type.WET
