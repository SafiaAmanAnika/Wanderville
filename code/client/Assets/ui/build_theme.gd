extends SceneTree
## Writes Assets/ui/skin/wanderville_theme.tres, the project's default theme
## (project.godot gui/theme/custom), from UiSkin. Any Button, text field,
## progress bar or slider that no script dresses picks up the UI pack.
##
## Labels and panels are deliberately left at Godot's defaults: name tags and
## world labels rely on the default white text, which would vanish on parchment.
##
##     Godot --headless --path code/client --script res://Assets/ui/build_theme.gd

const OUT := "res://Assets/ui/skin/wanderville_theme.tres"


func _initialize() -> void:
	var theme := Theme.new()
	for type in ["Button", "OptionButton", "MenuButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			theme.set_stylebox(state, type, UiSkin.button(state))
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())
		theme.set_color("font_color", type, UiSkin.INK)
		theme.set_color("font_focus_color", type, UiSkin.INK)
		theme.set_color("font_hover_color", type, UiSkin.CREAM)
		theme.set_color("font_pressed_color", type, UiSkin.CREAM)
		theme.set_color("font_hover_pressed_color", type, UiSkin.CREAM)
		theme.set_color("font_disabled_color", type, Color(UiSkin.INK_SOFT, 0.6))
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, UiSkin.input())
		theme.set_stylebox("focus", type, UiSkin.input(true))
		theme.set_stylebox("read_only", type, UiSkin.input())
		theme.set_color("font_color", type, UiSkin.INK)
		theme.set_color("font_placeholder_color", type, UiSkin.INK_SOFT)
		theme.set_color("caret_color", type, UiSkin.INK)
	theme.set_stylebox("background", "ProgressBar", UiSkin.progress_track())
	theme.set_stylebox("fill", "ProgressBar", UiSkin.progress_fill())
	theme.set_color("font_color", "ProgressBar", UiSkin.CREAM)
	var track := UiSkin.progress_track()
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", UiSkin.progress_fill())
	theme.set_stylebox("grabber_area_highlight", "HSlider", UiSkin.progress_fill())
	var error := ResourceSaver.save(theme, OUT)
	print("wrote ", OUT, " error=", error)
	quit(error)
