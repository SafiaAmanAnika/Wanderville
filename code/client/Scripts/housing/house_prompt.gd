extends CanvasLayer
# The game's one message line, a riveted strip from the UI pack at the bottom
# of the screen. Every in-game notice uses it instead of a popup:
#   HousePrompt.show_text("Press H to open the door")   → stays until hide_text()
#   HousePrompt.flash("Get 10 wood to build the floor")  → disappears by itself
# A flash shows over a standing prompt and hands the line back to it afterwards.

const MIN_WIDTH := 460.0
const BOTTOM_GAP := 24.0
const FONT_SIZE := 22

var _panel: PanelContainer
var _label: Label
var _flash_id := 0
var _standing := ""   ## the show_text() prompt a flash returns to
var _message := ""    ## what is on the line, before wrapping


func _ready() -> void:
	layer = 40
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiSkin.message_strip())
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Wrapped by _wrap(), not autowrap: an autowrapping label measured at a
	# stale width reports a huge height, and a PanelContainer never shrinks back.
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.add_theme_font_override("font", WoodPanel.PIXEL_FONT)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", UiSkin.INK)
	_panel.add_child(_label)
	add_child(_panel)
	_panel.visible = false
	get_viewport().size_changed.connect(_fit)


func text() -> String:
	return _message if _panel.visible else ""


func show_text(message: String) -> void:
	_flash_id += 1   # cancels a running flash
	_standing = message
	_display(message)


func hide_text() -> void:
	_standing = ""
	_flash_id += 1
	_panel.visible = false


func flash(message: String, seconds := 2.5, sound := true) -> void:
	if sound:
		AudioManager.play("notification")
	_flash_id += 1
	var my_id := _flash_id
	_display(message)
	await get_tree().create_timer(seconds).timeout
	if my_id != _flash_id:   # something newer owns the line
		return
	if _standing != "":
		_display(_standing)
	else:
		_panel.visible = false


func _display(message: String) -> void:
	var style := _panel.get_theme_stylebox("panel")
	var chrome := style.content_margin_left + style.content_margin_right
	var widest := _panel.get_viewport_rect().size.x * 0.8 - chrome
	_message = message
	_label.text = _wrap(message, widest)
	_label.custom_minimum_size.x = MIN_WIDTH - chrome
	_panel.visible = true
	_fit()


## Hug the text, centred above the bottom edge.
func _fit() -> void:
	if _panel == null or not _panel.visible:
		return
	var screen := _panel.get_viewport_rect().size
	var wanted := _panel.get_combined_minimum_size()
	_panel.size = wanted
	_panel.position = Vector2((screen.x - wanted.x) / 2.0, screen.y - wanted.y - BOTTOM_GAP)


## Greedy word wrap at the given pixel width.
func _wrap(message: String, width: float) -> String:
	var font: Font = WoodPanel.PIXEL_FONT
	var lines := PackedStringArray()
	var line := ""
	for word in message.split(" ", false):
		var candidate := word if line == "" else line + " " + word
		if line != "" and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x > width:
			lines.append(line)
			line = word
		else:
			line = candidate
	lines.append(line)
	return "\n".join(lines)
