extends Node2D

## Attach this to a Node2D and run the scene to preview the generated map.
## Controls: mouse wheel = zoom, left-click drag = pan, R = regenerate map,
## [ / ] = slow down / speed up time, C = jump time forward 1 hour.

@export var map_width_km: float = 5.0
@export var map_height_km: float = 5.0
@export var hex_size_m: float = 100.0
@export var seed_value: int = 0
@export var num_villages: int = 5
@export var num_rivers: int = 2
@export var hex_size_px: float = 20.0

var generator: MapGenerator
var weather_system: WeatherSystem
var time_system: TimeSystem
var hexes: Dictionary = {}
var _dragging: bool = false
var _press_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD: float = 6.0
var _weather_update_accum: float = 0.0
const WEATHER_UPDATE_INTERVAL: float = 1.0     # ground wetness/snow accumulation - fine to be slow
var _cloud_update_accum: float = 0.0
const CLOUD_UPDATE_INTERVAL: float = 0.15      # faster, so clouds visibly drift instead of jumping once a second
const CLOUD_VISIBLE_THRESHOLD: float = 0.45    # cloud_cover above this actually renders as a cloud shape
const CLOUD_MAX_ALPHA: float = 0.65
const CLOUD_SHADOW_OFFSET: Vector2 = Vector2(-0.45, -0.65)   # x hex_size_px - shifts the cloud shape away from its ground shadow, for a floating/3D look
var _brightness_cache: Dictionary = {}   # Vector2i -> float, refreshed every CLOUD_UPDATE_INTERVAL
var _cloud_cache: Dictionary = {}        # Vector2i -> float (0-1 cloud cover), refreshed every CLOUD_UPDATE_INTERVAL

var selected_coord = null
var info_label: Label

var settings_panel: PanelContainer
var select_button: Button
var select_mode_enabled: bool = true
var daynight_button: Button
var day_night_enabled: bool = false
var clouds_button: Button
var clouds_visible: bool = true
var cloud_speed_slider: HSlider
var _panel_dragging: bool = false
var _width_field: SpinBox
var _height_field: SpinBox
var _hexsize_field: SpinBox
var _seed_field: SpinBox
var _villages_field: SpinBox
var _rivers_field: SpinBox
var shape_option: OptionButton

func _ready() -> void:
	generator = MapGenerator.new()
	weather_system = WeatherSystem.new(seed_value)
	time_system = TimeSystem.new()
	_setup_info_panel()
	_setup_settings_panel()
	_regenerate()

func _setup_info_panel() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)

	var panel = PanelContainer.new()
	panel.position = Vector2(10, 10)
	panel.custom_minimum_size = Vector2(260, 0)
	layer.add_child(panel)

	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_label.text = "Click a hex to inspect its layers."
	panel.add_child(info_label)

func _setup_settings_panel() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)

	settings_panel = PanelContainer.new()
	settings_panel.position = Vector2(get_viewport().get_visible_rect().size.x - 300, 10)
	settings_panel.custom_minimum_size = Vector2(280, 0)
	layer.add_child(settings_panel)

	var vbox = VBoxContainer.new()
	settings_panel.add_child(vbox)

	var title_bar = Label.new()
	title_bar.text = "\u2261 Map Settings (drag to move)"
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.gui_input.connect(_on_title_bar_input)
	vbox.add_child(title_bar)

	_width_field = _add_spinbox(vbox, "Width (km)", 0.5, 50.0, 0.5, map_width_km)
	_height_field = _add_spinbox(vbox, "Height (km)", 0.5, 50.0, 0.5, map_height_km)
	_hexsize_field = _add_spinbox(vbox, "Hex size (m)", 10.0, 1000.0, 10.0, hex_size_m)
	_seed_field = _add_spinbox(vbox, "Seed (0=random)", 0, 999999, 1, seed_value)
	_villages_field = _add_spinbox(vbox, "Villages", 0, 20, 1, num_villages)
	_rivers_field = _add_spinbox(vbox, "Rivers", 0, 10, 1, num_rivers)

	var shape_row = HBoxContainer.new()
	vbox.add_child(shape_row)
	var shape_label = Label.new()
	shape_label.text = "Map Shape"
	shape_label.custom_minimum_size = Vector2(120, 0)
	shape_row.add_child(shape_label)
	shape_option = OptionButton.new()
	shape_option.add_item("Random", MapGenerator.MapShape.RANDOM)
	shape_option.add_item("Square", MapGenerator.MapShape.SQUARE)
	shape_option.selected = 0
	shape_row.add_child(shape_option)

	var cloud_speed_row = HBoxContainer.new()
	vbox.add_child(cloud_speed_row)
	var cloud_speed_label = Label.new()
	cloud_speed_label.text = "Cloud Speed"
	cloud_speed_label.custom_minimum_size = Vector2(120, 0)
	cloud_speed_row.add_child(cloud_speed_label)
	cloud_speed_slider = HSlider.new()
	cloud_speed_slider.min_value = 0.0
	cloud_speed_slider.max_value = 20.0
	cloud_speed_slider.step = 0.5
	cloud_speed_slider.value = weather_system.wind_speed_mps
	cloud_speed_slider.custom_minimum_size = Vector2(120, 0)
	cloud_speed_slider.value_changed.connect(_on_cloud_speed_changed)
	cloud_speed_row.add_child(cloud_speed_slider)

	var button_row = HBoxContainer.new()
	vbox.add_child(button_row)

	var generate_button = Button.new()
	generate_button.text = "Generate"
	generate_button.pressed.connect(_on_generate_pressed)
	button_row.add_child(generate_button)

	select_button = Button.new()
	select_button.text = "Select: ON"
	select_button.toggle_mode = true
	select_button.button_pressed = true
	select_button.toggled.connect(_on_select_toggled)
	button_row.add_child(select_button)

	daynight_button = Button.new()
	daynight_button.text = "Day/Night: OFF"
	daynight_button.toggle_mode = true
	daynight_button.button_pressed = false
	daynight_button.toggled.connect(_on_daynight_toggled)
	button_row.add_child(daynight_button)

	clouds_button = Button.new()
	clouds_button.text = "Clouds: ON"
	clouds_button.toggle_mode = true
	clouds_button.button_pressed = true
	clouds_button.toggled.connect(_on_clouds_toggled)
	button_row.add_child(clouds_button)

func _add_spinbox(parent: Node, label_text: String, min_v: float, max_v: float, step_v: float, default_v: float) -> SpinBox:
	var row = HBoxContainer.new()
	parent.add_child(row)

	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)

	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step_v
	spin.value = default_v
	row.add_child(spin)
	return spin

func _on_title_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_panel_dragging = event.pressed
	elif event is InputEventMouseMotion and _panel_dragging:
		settings_panel.position += event.relative

func _on_generate_pressed() -> void:
	map_width_km = _width_field.value
	map_height_km = _height_field.value
	hex_size_m = _hexsize_field.value
	seed_value = int(_seed_field.value)
	num_villages = int(_villages_field.value)
	num_rivers = int(_rivers_field.value)
	_regenerate()

func _on_select_toggled(pressed: bool) -> void:
	select_mode_enabled = pressed
	select_button.text = "Select: ON" if pressed else "Select: OFF"

func _on_daynight_toggled(pressed: bool) -> void:
	day_night_enabled = pressed
	daynight_button.text = "Day/Night: ON" if pressed else "Day/Night: OFF"

func _on_clouds_toggled(pressed: bool) -> void:
	clouds_visible = pressed
	clouds_button.text = "Clouds: ON" if pressed else "Clouds: OFF"
	queue_redraw()

func _on_cloud_speed_changed(value: float) -> void:
	weather_system.wind_speed_mps = value

func _regenerate() -> void:
	generator.map_width_km = map_width_km
	generator.map_height_km = map_height_km
	generator.hex_size_m = hex_size_m
	generator.seed_value = seed_value
	generator.num_villages = num_villages
	generator.num_rivers = num_rivers
	generator.map_shape = shape_option.get_item_id(shape_option.selected)
	hexes = generator.generate()
	_update_clouds()
	_update_ground_weather()

func _process(delta: float) -> void:
	# Cheap - just advances internal clocks, no noise sampling.
	weather_system.update(delta)
	if day_night_enabled:
		time_system.update(delta)

	_cloud_update_accum += delta
	if _cloud_update_accum >= CLOUD_UPDATE_INTERVAL:
		_cloud_update_accum = 0.0
		_update_clouds()

	_weather_update_accum += delta
	if _weather_update_accum >= WEATHER_UPDATE_INTERVAL:
		_weather_update_accum = 0.0
		_update_ground_weather()

## Fast, cheap pass (one noise sample per hex) - moves the visible cloud
## layer and brightness dimming. This is what makes clouds look like they're
## actually drifting instead of jumping into a new position once a second.
func _update_clouds() -> void:
	for coord in hexes.keys():
		var world_pos = HexUtils.axial_to_pixel(coord, hex_size_m)
		var cloud = weather_system.get_cloud_cover(world_pos)
		_cloud_cache[coord] = cloud
		_brightness_cache[coord] = time_system.get_brightness(cloud)
	queue_redraw()

## Slower pass - ground wetness/snow doesn't need to update smoothly, so it
## stays on its own, cheaper cadence.
func _update_ground_weather() -> void:
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		var world_pos = HexUtils.axial_to_pixel(coord, hex_size_m)
		if weather_system.is_precipitating(world_pos):
			tile.ground_weather.type = weather_system.precipitation_ground_type()
			tile.ground_weather.depth = min(tile.ground_weather.depth + 0.05, 1.0)
		else:
			tile.ground_weather.depth = max(tile.ground_weather.depth - 0.03, 0.0)
			if tile.ground_weather.depth <= 0.0:
				tile.ground_weather.type = GroundWeather.Type.DRY

func _select_hex_at(screen_pos: Vector2) -> void:
	var local_pos = to_local(screen_pos)
	var coord = HexUtils.pixel_to_axial(local_pos, hex_size_px)
	if hexes.has(coord):
		selected_coord = coord
		info_label.text = _describe_tile(hexes[coord])
	else:
		selected_coord = null
		info_label.text = "No hex there - click within the map."
	queue_redraw()

func _describe_tile(tile: HexTile) -> String:
	var lines: Array = []
	lines.append("Hex (%d, %d)" % [tile.q, tile.r])
	lines.append("")
	lines.append("Ground: %s" % GroundLayer.Type.keys()[tile.ground_type])
	lines.append("Vegetation: %s" % VegetationLayer.Type.keys()[tile.vegetation])
	lines.append("Elevation: %.2f   Moisture: %.2f" % [tile.elevation, tile.moisture])

	if tile.structure != null:
		var kind_name = Structure.Kind.keys()[tile.structure.kind]
		var subtype_name = _structure_subtype_name(tile.structure)
		var occ_text = "%s%s" % [kind_name, (" (" + subtype_name + ")") if subtype_name != "" else ""]
		lines.append("Structure: %s" % occ_text)
		if tile.structure.kind == Structure.Kind.BRIDGE:
			var bridge: Bridge = tile.structure
			lines.append("  Max weight: %.1f t   Width: %.1f m" % [bridge.max_weight_tons, bridge.width_m])
		elif tile.structure.capacity > 0:
			lines.append("  Occupants: %d / %d" % [tile.structure.occupants.size(), tile.structure.capacity])
	else:
		lines.append("Structure: none")

	if tile.occupants.size() > 0:
		var names: Array = []
		for occ in tile.occupants:
			names.append(LivingEntity.Kind.keys()[occ.kind])
		lines.append("On the ground: %s" % ", ".join(names))
	else:
		lines.append("On the ground: nothing")

	lines.append("River: %s" % ("yes" if tile.has_river else "no"))

	if tile.village_ref != null:
		var v: Village = tile.village_ref
		lines.append("Village: yes (%d hexes)" % v.hexes.size())
		lines.append("Population: %d  (M:%d  W:%d  C:%d)" % [v.total_population(), v.men, v.women, v.children])
		if tile.is_canal:
			lines.append("Canal: yes (village-claimed river crossing)")
		var wall_count = 0
		for w in tile.wall_sides:
			if w:
				wall_count += 1
		lines.append("Wall on this hex: %d side(s)" % wall_count)
	else:
		lines.append("Village: no")

	var gw = tile.ground_weather
	lines.append("Ground weather: %s (depth %.2f)" % [GroundWeather.Type.keys()[gw.type], gw.depth])
	lines.append("")
	lines.append("Movement cost: %.2f" % tile.movement_cost())

	return "\n".join(lines)

func _structure_subtype_name(structure: Structure) -> String:
	match structure.kind:
		Structure.Kind.MATURE_TREE:
			return Structure.TreeSpecies.keys()[structure.subtype]
		Structure.Kind.BUILDING:
			return Structure.BuildingKind.keys()[structure.subtype]
		Structure.Kind.VEHICLE_LARGE:
			return Structure.VehicleKind.keys()[structure.subtype]
		Structure.Kind.BRIDGE:
			return Bridge.BridgeType.keys()[structure.subtype]
		_:
			return ""

func _dim(c: Color, brightness: float) -> Color:
	var d = c * brightness
	d.a = c.a
	return d

## Which directions from this canal hex lead to another river hex - used to
## draw the stream following the water's actual course, not a fixed line.
func _stream_directions(coord: Vector2i) -> Array:
	var dirs: Array = []
	for d in range(HexUtils.DIRECTIONS.size()):
		var n = coord + HexUtils.DIRECTIONS[d]
		if hexes.has(n) and hexes[n].has_river:
			dirs.append(d)
	return dirs

func _best_opposite_pair(dirs: Array) -> Array:
	if dirs.size() < 2:
		return dirs
	var best_pair = [dirs[0], dirs[1]]
	var best_diff = -1
	for i in range(dirs.size()):
		for j in range(i + 1, dirs.size()):
			var diff = abs(dirs[i] - dirs[j])
			diff = min(diff, 6 - diff)
			if diff > best_diff:
				best_diff = diff
				best_pair = [dirs[i], dirs[j]]
	return best_pair

func _draw() -> void:
	for coord in hexes.keys():
		var tile: HexTile = hexes[coord]
		var center = HexUtils.axial_to_pixel(coord, hex_size_px)
		var points = HexUtils.hex_corners(center, hex_size_px)

		var brightness = _brightness_cache.get(coord, 1.0)

		var ground_color: Color = GroundLayer.COLORS[tile.ground_type]
		var color = ground_color
		if tile.is_canal:
			# Looks like ordinary town ground - the water only shows as a
			# thin stream line, drawn below, not a solid tinted hex.
			color = GroundLayer.COLORS[GroundLayer.Type.LIME].lerp(VegetationLayer.COLORS[VegetationLayer.Type.SHORT_GRASS], 0.5)
		elif tile.vegetation != VegetationLayer.Type.NONE:
			var veg_color: Color = VegetationLayer.COLORS[tile.vegetation]
			var blend = 0.3 if tile.vegetation == VegetationLayer.Type.BARE else 0.75
			color = ground_color.lerp(veg_color, blend)

		var gw = tile.ground_weather
		var tint: Color = GroundWeather.TINT[gw.type]
		if tint.a > 0.0:
			color = color.lerp(tint, tint.a * clamp(gw.depth, 0.0, 1.0))

		draw_colored_polygon(points, _dim(color, brightness))
		draw_polyline(_closed(points), Color(0, 0, 0, 0.15), 1.0)

		if tile.is_canal:
			var stream_dirs = _stream_directions(coord)
			var stream_thickness = max(hex_size_px * 0.12, 2.0)
			var stream_color = _dim(Color(0.35, 0.55, 0.78), brightness)
			if stream_dirs.size() >= 2:
				var pair = _best_opposite_pair(stream_dirs)
				var se1 = HexUtils.EDGE_FOR_DIRECTION[pair[0]]
				var se2 = HexUtils.EDGE_FOR_DIRECTION[pair[1]]
				var sp1 = (points[se1] + points[(se1 + 1) % 6]) / 2.0
				var sp2 = (points[se2] + points[(se2 + 1) % 6]) / 2.0
				draw_line(sp1, center, stream_color, stream_thickness)
				draw_line(center, sp2, stream_color, stream_thickness)
			elif stream_dirs.size() == 1:
				var se = HexUtils.EDGE_FOR_DIRECTION[stream_dirs[0]]
				var sp = (points[se] + points[(se + 1) % 6]) / 2.0
				draw_line(sp, center, stream_color, stream_thickness)

		for d in range(6):
			if tile.wall_sides[d]:
				var e = HexUtils.EDGE_FOR_DIRECTION[d]
				var p1 = points[e]
				var p2 = points[(e + 1) % 6]
				draw_line(p1, p2, _dim(Color(0.32, 0.28, 0.22), brightness), max(hex_size_px * 0.14, 2.0))

		if tile.has_river and tile.ground_type != GroundLayer.Type.WATER:
			draw_circle(center, hex_size_px * 0.12, _dim(Color(0.15, 0.35, 0.85), brightness))

		if tile.structure != null:
			if tile.structure.kind == Structure.Kind.BRIDGE:
				var bridge: Bridge = tile.structure
				var bcolor: Color = Bridge.BRIDGE_COLORS.get(bridge.bridge_type, Color.WHITE)
				var thickness = clamp(bridge.width_m * 2.5, 6.0, hex_size_px * 0.9)
				var dirs = bridge.deck_directions
				var d1 = dirs[0] if dirs.size() > 0 else 0
				var d2 = dirs[1] if dirs.size() > 1 else (d1 + 3) % 6
				var e1 = HexUtils.EDGE_FOR_DIRECTION[d1]
				var e2 = HexUtils.EDGE_FOR_DIRECTION[d2]
				var p1 = (points[e1] + points[(e1 + 1) % 6]) / 2.0
				var p2 = (points[e2] + points[(e2 + 1) % 6]) / 2.0
				draw_line(p1, p2, _dim(bcolor, brightness), thickness)
			else:
				var s_color: Color = Structure.COLORS.get(tile.structure.kind, Color.MAGENTA)
				if tile.structure.kind == Structure.Kind.BUILDING and tile.structure.subtype == Structure.BuildingKind.WELL:
					s_color = Color(0.35, 0.55, 0.75)
				draw_circle(center, hex_size_px * 0.3, _dim(s_color, brightness))

		for i in range(tile.occupants.size()):
			var occ: LivingEntity = tile.occupants[i]
			var offset = Vector2((i - tile.occupants.size() / 2.0) * hex_size_px * 0.25, 0)
			var occ_color: Color = LivingEntity.COLORS.get(occ.kind, Color.WHITE)
			draw_circle(center + offset, hex_size_px * 0.08, _dim(occ_color, brightness))

		if selected_coord != null and coord == selected_coord:
			draw_polyline(_closed(points), Color(1, 1, 0, 0.9), 3.0)

	# Cloud layer - a separate pass so it consistently sits above every hex's
	# terrain/structures rather than interleaving with the per-hex drawing
	# above. Thresholding the same coherent noise field used for brightness
	# means adjacent hexes over the threshold naturally clump into cloud-
	# shaped clusters, rather than each hex being an independent fleck.
	for coord in hexes.keys():
		var cloud = _cloud_cache.get(coord, 0.0)
		if cloud <= CLOUD_VISIBLE_THRESHOLD:
			continue
		var ground_center = HexUtils.axial_to_pixel(coord, hex_size_px)
		var cloud_center = ground_center + CLOUD_SHADOW_OFFSET * hex_size_px
		var cloud_points = HexUtils.hex_corners(cloud_center, hex_size_px)
		var strength = clamp((cloud - CLOUD_VISIBLE_THRESHOLD) / (1.0 - CLOUD_VISIBLE_THRESHOLD), 0.0, 1.0)
		draw_colored_polygon(cloud_points, Color(1, 1, 1, strength * CLOUD_MAX_ALPHA))

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var closed = points.duplicate()
	closed.append(points[0])
	return closed

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			hex_size_px = min(hex_size_px * 1.1, 100.0)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			hex_size_px = max(hex_size_px * 0.9, 2.0)
			queue_redraw()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_press_pos = event.position
			else:
				_dragging = false
				if event.position.distance_to(_press_pos) < DRAG_THRESHOLD and select_mode_enabled:
					_select_hex_at(event.position)
	elif event is InputEventMouseMotion and _dragging:
		position += event.relative
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				seed_value = randi()
				_regenerate()
			KEY_BRACKETLEFT:
				time_system.day_length_seconds = min(time_system.day_length_seconds * 1.5, 6000.0)
			KEY_BRACKETRIGHT:
				time_system.day_length_seconds = max(time_system.day_length_seconds / 1.5, 10.0)
			KEY_C:
				time_system.time_of_day_hours = fmod(time_system.time_of_day_hours + 1.0, 24.0)
