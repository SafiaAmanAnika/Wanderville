extends CanvasLayer

signal seed_selected(seed_name: String)

@onready var panel: Panel = $Panel
@onready var grid: GridContainer = $Panel/VBoxContainer/Grid
@onready var title: Label = $Panel/VBoxContainer/TitleLabel

func _ready() -> void:
	_style_panel()
	visible = false

func _style_panel() -> void:
	title.text = "Choose a Seed"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", WoodPanel.SIZE_BUTTON)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))

	grid.columns = 4

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.05, 0.92)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.65, 0.3, 0.9)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

func show_menu() -> void:
	# Clear old buttons
	for child in grid.get_children():
		child.queue_free()

	# Build a button for each seed the player has
	for seed_name in GameState.seed_inventory:
		var count: int = GameState.seed_inventory[seed_name]
		if count <= 0:
			continue

		var btn := Button.new()
		btn.text = "%s\n×%d" % [seed_name.capitalize(), count]
		btn.custom_minimum_size = Vector2(72, 72)
		btn.pressed.connect(_on_seed_pressed.bind(seed_name))

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.25, 0.55, 0.2, 0.9)
		btn_style.corner_radius_top_left = 8
		btn_style.corner_radius_top_right = 8
		btn_style.corner_radius_bottom_left = 8
		btn_style.corner_radius_bottom_right = 8
		btn.add_theme_stylebox_override("normal", btn_style)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_font_size_override("font_size", WoodPanel.SIZE_SMALL)

		grid.add_child(btn)

	# Wait one frame so Control nodes calculate their sizes, then center
	await get_tree().process_frame
	var screen_size := get_viewport().get_visible_rect().size
	var min_size := panel.get_combined_minimum_size()
	panel.size = min_size
	panel.position = (screen_size - min_size) / 2

	GameState.menu_open = true
	visible = true

func hide_menu() -> void:
	GameState.menu_open = false
	visible = false

func _on_seed_pressed(seed_name: String) -> void:
	hide_menu()
	seed_selected.emit(seed_name)

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide_menu()
