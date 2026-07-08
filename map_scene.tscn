class_name TimeSystem
extends RefCounted

## Global time-of-day and brightness. Brightness = a day/night curve, dimmed
## locally by whatever cloud cover WeatherSystem reports overhead.

@export var time_of_day_hours: float = 12.0     # 0-24
@export var day_length_seconds: float = 600.0   # real seconds per full in-game day
@export var min_night_brightness: float = 0.08  # never fully black (moonlight)
@export var max_cloud_dimming: float = 0.65      # how much heavy cloud can cut brightness

func update(delta: float) -> void:
	time_of_day_hours += (delta / day_length_seconds) * 24.0
	if time_of_day_hours >= 24.0:
		time_of_day_hours -= 24.0

## 0 (deep night) - 1 (full midday), before cloud is factored in.
func get_base_brightness() -> float:
	var angle = (time_of_day_hours / 24.0) * TAU
	var raw = (sin(angle - PI / 2.0) + 1.0) / 2.0
	return lerp(min_night_brightness, 1.0, raw)

## Final brightness at a point, given the local cloud cover (0-1).
func get_brightness(cloud_cover: float) -> float:
	var base = get_base_brightness()
	var dimming = lerp(1.0, 1.0 - max_cloud_dimming, cloud_cover)
	return clamp(base * dimming, 0.02, 1.0)
