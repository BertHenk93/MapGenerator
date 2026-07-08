extends Control

## Simple main menu. For now just one button that goes to the map scene.

func _ready() -> void:
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)

	var title = Label.new()
	title.text = "Map Generator"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var generate_button = Button.new()
	generate_button.text = "Generate map"
	generate_button.custom_minimum_size = Vector2(200, 40)
	generate_button.pressed.connect(_on_generate_pressed)
	vbox.add_child(generate_button)

func _on_generate_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map_scene.tscn")
