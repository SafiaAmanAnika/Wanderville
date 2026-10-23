extends PanelContainer
## Original six-character picker; previews never change the active player.
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const Preview := preload("res://Scripts/customization/character_preview.gd")
const Frames := preload("res://Scripts/chara_frames.gd")
signal close_requested
var avatar: AnimatedSprite2D
var title_label: Label
var status: Label
var options: GridContainer
var draft := "girl_a"
var _session := -1
var _saving := false
var _save: Button

func _ready() -> void:
 theme = Style.theme()
 custom_minimum_size = Vector2(1020,520)
 add_theme_stylebox_override("panel",Style.box(Style.PAPER,18))
 var column := VBoxContainer.new(); column.add_theme_constant_override("separation",12); add_child(column)
 var header := HBoxContainer.new(); column.add_child(header)
 var title := Style.label("Choose your character",28); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
 var close_button := Style.button("X"); header.add_child(close_button); close_button.pressed.connect(func(): close_requested.emit())
 var body := HBoxContainer.new(); body.add_theme_constant_override("separation",20); column.add_child(body)
 var stage_panel := PanelContainer.new(); stage_panel.add_theme_stylebox_override("panel",Style.box(Color("efd6b1"),0)); body.add_child(stage_panel)
 var stage := Control.new(); stage.custom_minimum_size=Vector2(380,370); stage_panel.add_child(stage)
 avatar=Preview.new(); avatar.position=Vector2(190,185); avatar.scale=Vector2.ONE*0.85; stage.add_child(avatar)
 var right := VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; body.add_child(right)
 title_label=Style.label("Characters",24); right.add_child(title_label)
 options=GridContainer.new(); options.columns=3; options.add_theme_constant_override("h_separation",10); options.add_theme_constant_override("v_separation",10); right.add_child(options)
 status=Style.label("",18); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(status)
 var footer := HBoxContainer.new(); column.add_child(footer)
 _save=Style.button("Save character",true); footer.add_child(_save); _save.pressed.connect(save)
 var cancel_button := Style.button("Close / Escape"); footer.add_child(cancel_button); cancel_button.pressed.connect(func(): close_requested.emit())
 get_viewport().size_changed.connect(_fit); minimum_size_changed.connect(_fit.call_deferred); _fit.call_deferred()

func _fit() -> void:
 size=get_combined_minimum_size().max(custom_minimum_size)
 var viewport := get_viewport_rect().size
 var factor := minf(1.0,minf((viewport.x-40)/size.x,(viewport.y-40)/size.y))
 scale=Vector2.ONE*maxf(0.1,factor); position=(viewport-size*scale)/2.0

func begin(kind: String="character") -> void:
 _session=Global.session_version; _saving=false; _save.disabled=false
 draft=Global.selected_character if Global.CHARACTERS.has(Global.selected_character) and Global.CHARACTERS[Global.selected_character].folder!="" else "girl_a"
 avatar.set_character(draft)
 avatar.set_pose("idle","front")
 var mirror := kind=="mirror"
 title_label.text="Mirror" if mirror else "Characters"
 options.visible=not mirror
 _save.visible=not mirror
 for child in options.get_children(): options.remove_child(child); child.queue_free()
 var group := ButtonGroup.new()
 for code in Global.CHARACTERS:
  var info: Dictionary=Global.CHARACTERS[code]
  if info.folder=="": continue
  var button := Style.button(""); button.custom_minimum_size=Vector2(185,150); button.toggle_mode=true; button.button_group=group; button.button_pressed=code==draft; options.add_child(button)
  var selected := Style.box(Color("e1c49b"),10); selected.border_color=Style.MAROON; button.add_theme_stylebox_override("pressed",selected)
  var preview := Preview.new(); preview.character=code; preview.position=Vector2(92,60); preview.scale=Vector2.ONE*0.55; button.add_child(preview)
  var label := Style.label(info.name,17); label.position=Vector2(10,124); label.mouse_filter=Control.MOUSE_FILTER_IGNORE; button.add_child(label)
  button.pressed.connect(func(): draft=code; avatar.set_character(code))
 status.text="Your current character." if mirror else "Choose a character. Save to use this look."
 _fit()

func cancel() -> void:
 pass # Preview has no session/player side effects.

func save() -> void:
 if _saving or _session!=Global.session_version: return
 _saving=true; _save.disabled=true
 if Global.is_logged_in() and draft!=Global.selected_character:
  var response: Dictionary=await APIClient.update_profile({"character_code":draft})
  if _session!=Global.session_version: return
  if not bool(response.get("ok",false)):
   status.text=APIClient.error_text(response); _saving=false; _save.disabled=false; return
 var changed := Global.selected_character!=draft
 Global.selected_character=draft
 Global.modular_look={} # Clear retired generated preferences only on explicit Save.
 Global.save_session(); Global.appearance_changed.emit()
 var room := get_tree().current_scene
 if changed and room!=null and room.has_method("respawn_player"): room.respawn_player()
 status.text="Character saved."; _saving=false; _save.disabled=false
