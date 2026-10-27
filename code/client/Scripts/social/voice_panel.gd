extends PanelContainer
## UI reads actual capture and voice-transport state, independent of gameplay.
const Style := preload("res://Scripts/ui/lobby_theme.gd")
var voice: Node
var state: Label
var detail: Label
var input_meter: ProgressBar
var output_meter: ProgressBar
var join_button: Button
var mute: CheckBox
var deafen: CheckBox
var mode: OptionButton
var talk_button: Button
var devices: VBoxContainer
var _ptt := false
var _last_state := "Not joined"

func _ready() -> void:
	theme = Style.theme()
	add_theme_stylebox_override("panel", UiSkin.panel())
	UiSkin.ink_text(self)
	var column := VBoxContainer.new(); add_child(column)
	column.add_child(Style.label("Proximity Voice", 22))
	state = Style.label("Not joined", 18); column.add_child(state)
	preload("res://Scripts/ui/loading_progress.gd").attach(state)
	detail = Style.label("Join when you are ready. Microphone is off.", 16)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(detail)
	column.add_child(Style.label("Microphone", 16))
	input_meter = ProgressBar.new(); input_meter.max_value = 1.0; input_meter.show_percentage = false; input_meter.custom_minimum_size.y = 10; column.add_child(input_meter)
	column.add_child(Style.label("Receiving audio", 16))
	output_meter = ProgressBar.new(); output_meter.max_value = 1.0; output_meter.show_percentage = false; output_meter.custom_minimum_size.y = 10; column.add_child(output_meter)
	for meter in [input_meter, output_meter]:
		UiSkin.apply_progress_bar(meter)
		meter.custom_minimum_size.y = 14
	join_button = Style.button("Join Voice", true); column.add_child(join_button)
	join_button.pressed.connect(func():
		if voice.session_id.is_empty(): await voice.join_voice()
		else: voice.leave()
	)
	mode = OptionButton.new(); mode.add_item("Push to Talk (V)"); mode.add_item("Open mic"); column.add_child(mode)
	mode.item_selected.connect(func(_index: int): voice.talk(mode.selected == 1 and not mute.button_pressed))
	talk_button = Style.button("Hold V to talk"); column.add_child(talk_button)
	talk_button.button_down.connect(func(): _talk(true))
	talk_button.button_up.connect(func(): _talk(false))
	var controls := HBoxContainer.new(); column.add_child(controls)
	mute = CheckBox.new(); mute.text = "Mute"; controls.add_child(mute)
	mute.toggled.connect(func(value: bool): voice.talk(not value and mode.selected == 1))
	deafen = CheckBox.new(); deafen.text = "Deafen"; controls.add_child(deafen)
	deafen.toggled.connect(func(value: bool):
		voice.set_deafened(value)
		if not value and mode.selected == 1 and not mute.button_pressed: voice.talk(true)
	)
	var device_button := Style.button("Devices"); controls.add_child(device_button)
	devices = VBoxContainer.new(); devices.hide(); column.add_child(devices)
	device_button.pressed.connect(func(): devices.visible = not devices.visible)
	_device(devices, "Input", AudioServer.get_input_device_list(), true)
	_device(devices, "Output", AudioServer.get_output_device_list(), false)
	voice.status_changed.connect(func(message: String): detail.text = message)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): _talk(false)
	)

func _device(parent: Node, title: String, values: PackedStringArray, input: bool) -> void:
	parent.add_child(Style.label(title, 16))
	var picker := OptionButton.new(); parent.add_child(picker)
	for value in values:
		picker.add_item(value)
		if value == (AudioServer.input_device if input else AudioServer.output_device): picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int):
		await voice.talk(false)
		if input: AudioServer.input_device = picker.get_item_text(index)
		else: AudioServer.output_device = picker.get_item_text(index)
		if mode.selected == 1 and not mute.button_pressed: voice.talk(true)
	)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_V and not event.echo:
		if not event.pressed:
			_talk(false)
		elif get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit or GameState.menu_open:
			return
		else:
			_talk(true)

func _talk(pressed: bool) -> void:
	if mode.selected != 0 or mute.button_pressed: return
	if _ptt == pressed: return
	_ptt = pressed
	voice.talk(pressed)

func _process(_delta: float) -> void:
	state.text = voice.connection_state()
	if state.text == "Connected" and _last_state != "Connected" and mode.selected == 1 and not mute.button_pressed: voice.talk(true)
	_last_state = state.text
	if voice.is_transmitting(): state.text += " · Transmitting"
	elif voice.output_level > 0.015: state.text += " · Receiving"
	state.add_theme_color_override("font_color", Style.SAGE if voice.is_transmitting() else Style.INK)
	input_meter.value = voice.input_level
	output_meter.value = voice.output_level
	join_button.text = "Leave Voice" if not voice.session_id.is_empty() else "Join Voice"
	join_button.disabled = voice.connection_state() == "Connecting"
	talk_button.disabled = voice.connection_state() != "Connected" or mute.button_pressed or mode.selected != 0 or voice.deafened
	deafen.set_pressed_no_signal(voice.deafened)
