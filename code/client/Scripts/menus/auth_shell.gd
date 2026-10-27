extends Node
## A shared quiet card family around the existing authentication controllers.
const Style := preload("res://Scripts/ui/lobby_theme.gd")
const Eye := preload("res://Scripts/menus/auth_eye.gd")
const Mark := preload("res://Scripts/menus/auth_mark.gd")
const Art := preload("res://Scripts/menus/auth_panel_art.gd")
const FRAME := preload("res://Assets/ui/auth/parchment-frame.res")
var screen: Control
var center: CenterContainer
var _last_min := Vector2.ZERO
var _last_view := Vector2.ZERO

static func install(target: Control) -> void:
	var shell := load("res://Scripts/menus/auth_shell.gd").new() as Node
	shell.screen=target; target.add_child(shell)

static func field_error(field: LineEdit) -> void:
	var style := _field_style(Color("fff4e7")); style.border_color=Style.MAROON
	field.add_theme_stylebox_override("normal",style)

static func clear_field(field: LineEdit) -> void:
	field.add_theme_stylebox_override("normal",_field_style())

static func _field_style(color: Color = Color("fff0d8")) -> StyleBoxFlat:
	var style := Style.box(color,12); style.border_color=Color("c7a37b")
	style.set_corner_radius_all(8); style.content_margin_left=48
	style.content_margin_right=48
	return style

static func reveal(panel: Control) -> void:
	panel.modulate.a=0.0
	panel.create_tween().tween_property(panel,"modulate:a",1.0,0.22)

func _ready() -> void:
	screen.get_node("%Background").hide()
	SceneManager.show_journey_background(screen,0.0)
	center=screen.get_node("Center")
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	Style.apply_tree(center)
	for panel in center.get_children():
		if not panel is PanelContainer: continue
		panel.custom_minimum_size=Vector2(620,0)
		var backing := StyleBoxTexture.new(); backing.texture=FRAME
		backing.content_margin_left=108; backing.content_margin_right=82
		backing.content_margin_top=84; backing.content_margin_bottom=54
		panel.add_theme_stylebox_override("panel",backing)
		var column := panel.get_child(0) as VBoxContainer
		column.add_theme_constant_override("separation",12)
		for spacer in column.get_children():
			if String(spacer.name).begins_with("Spacer"): spacer.hide()
		var artwork := Art.new(); artwork.name="AuthArtwork"; artwork.panel=panel
		panel.add_child(artwork)
		if panel.name != "FormPanel":
			var mark := Mark.new(); mark.name="StatusMark"; mark.custom_minimum_size=Vector2(48,48)
			mark.checkmark=screen.name=="ResetPasswordScene" and panel.name=="SuccessPanel"
			column.add_child(mark); column.move_child(mark,1)
	for node in center.find_children("*","Label",true,false):
		node.add_theme_font_override("font",Style.FONT if node.name=="AuthBrand" else Style.body_font())
		node.add_theme_font_size_override("font_size",19)
		node.add_theme_color_override("font_color",Style.INK)
		if String(node.name).contains("Title"):
			node.add_theme_font_override("font",Style.FONT)
			node.add_theme_font_size_override("font_size",30)
			node.add_theme_color_override("font_color",Style.MAROON)
		if node.name in [&"ErrorLabel",&"ErrorMessageLabel"]: node.add_theme_color_override("font_color",Style.MAROON)
		if node.name=="AuthBrand": node.add_theme_color_override("font_color",Style.SAGE)
		if node.name != "Title": node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	for node in center.find_children("*","LineEdit",true,false):
		node.add_theme_font_override("font",Style.body_font())
		node.custom_minimum_size=Vector2(0,52)
		node.add_theme_font_size_override("font_size",20)
		node.add_theme_stylebox_override("normal",_field_style())
		node.add_theme_stylebox_override("focus",_field_style(Color("fff7e6")))
		if node.secret: _password_eye(node)
		var icon := TextureRect.new(); icon.name="FieldIcon"
		icon.texture=Art.field_icon(String(node.name).contains("Password") or String(node.name).contains("Confirm"))
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position=Vector2(14,14); icon.size=Vector2(24,24)
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE; node.add_child(icon)
	for node in center.find_children("*","Button",true,false):
		node.custom_minimum_size.y=46
		node.add_theme_font_size_override("font_size",22)
		if node.name in [&"LoginBtn",&"CreateBtn",&"SendBtn",&"ResetBtn",&"ContinueBtn",&"BackToLoginBtn",&"GoToLoginBtn"]:
			node.custom_minimum_size.y=54
			for state in ["normal","hover","pressed","focus"]:
				var backing := Style.box(Style.MAROON.lightened(0.08) if state=="hover" else Style.MAROON,12)
				backing.border_color=Color("562b29"); backing.set_corner_radius_all(10)
				node.add_theme_stylebox_override(state,backing)
			node.add_theme_color_override("font_color",Style.PAPER)
			node.add_theme_color_override("font_hover_color",Style.PAPER)
			node.add_theme_color_override("font_focus_color",Style.PAPER)
			Art.button_leaves(node)
		if node.name in [&"BackBtn",&"ForgotBtn",&"CreateAccountLink"]: _link(node)
	if screen.name=="LoginScene": _login_layout()
	if screen.name=="SignupScene": _signup_layout()
	if screen.name=="ForgotPasswordScene": screen.get_node("%Title").text="Find your way back"
	if screen.has_node("%GoogleBtn"): _google(screen.get_node("%GoogleBtn"))
	for node in center.find_children("*","RichTextLabel",true,false):
		node.add_theme_font_override("normal_font",Style.body_font())
		node.add_theme_color_override("default_color",Style.INK)
		node.add_theme_font_size_override("normal_font_size",20)
	_fit()
	if screen.has_node("%LoadingLabel"):
		preload("res://Scripts/ui/loading_progress.gd").attach(screen.get_node("%LoadingLabel"))

func _password_eye(field: LineEdit) -> void:
	var parent := field.get_parent(); var index := field.get_index()
	var row := Control.new(); row.name=String(field.name)+"Row"; row.custom_minimum_size.y=52
	parent.add_child(row); parent.move_child(row,index); field.reparent(row)
	field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var eye := Eye.new(); eye.name="PasswordEye"; eye.field=field; row.add_child(eye)
	eye.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	eye.offset_left=-48; eye.offset_right=-4; eye.offset_top=3; eye.offset_bottom=-3
	for state in ["normal","hover","pressed","focus"]: eye.add_theme_stylebox_override(state,StyleBoxEmpty.new())

func _link(button: Button) -> void:
	button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	button.add_theme_color_override("font_color",Style.MAROON)
	button.custom_minimum_size.y=32
	button.add_theme_font_size_override("font_size",18)

func _divider(parent: Node,before: Node) -> void:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12)
	parent.add_child(row); parent.move_child(row,before.get_index())
	for index in 3:
		if index==1: row.add_child(Style.label("or continue with",16))
		else:
			var line := HSeparator.new(); line.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(line)

func _login_layout() -> void:
	screen.get_node("%Title").text="Welcome to Wanderville"
	screen.get_node("%Title").hide()
	var column := screen.get_node("%FormPanel").get_child(0)
	var forgot := screen.get_node("%ForgotBtn") as Button
	column.move_child(forgot,screen.get_node("%PasswordInput").get_parent().get_index()+1)
	forgot.alignment=HORIZONTAL_ALIGNMENT_RIGHT; forgot.text="Forgot Password?"
	_divider(column,screen.get_node("%GoogleBtn"))
	var create := Style.button("New to Wanderville? Create Account"); create.name="CreateAccountLink"
	column.add_child(create); column.move_child(create,screen.get_node("%GoogleBtn").get_index()+1)
	_link(create); create.pressed.connect(SceneManager.goto_signup)
	screen.get_node("%BackBtn").text="Back to title"

func _signup_layout() -> void:
	screen.get_node("%Title").text="Make yourself at home"
	var google := Style.button("Continue with Google"); google.name="GoogleBtn"
	var column := screen.get_node("%FormPanel").get_child(0)
	column.add_child(google); column.move_child(google,screen.get_node("%BackBtn").get_index())
	google.owner=screen; google.unique_name_in_owner=true
	_divider(column,google); google.pressed.connect(screen._on_google)
	screen.set("_google_btn",google)
	screen.get_node("%BackBtn").text="Already have an account? Log In"

func _google(button: Button) -> void:
	button.text=""; button.icon=null; button.tooltip_text="Continue with Google"
	var center_content := CenterContainer.new(); button.add_child(center_content)
	center_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_content.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",12)
	row.mouse_filter=Control.MOUSE_FILTER_IGNORE; center_content.add_child(row)
	var logo := TextureRect.new(); logo.name="GoogleLogo"
	logo.texture=load("res://Assets/ui/google-g.png")
	logo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; logo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size=Vector2(20,20); logo.mouse_filter=Control.MOUSE_FILTER_IGNORE; row.add_child(logo)
	var label := Style.label("Continue with Google",20); label.name="GoogleLabel"
	label.add_theme_color_override("font_color",Color("303134"))
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE; row.add_child(label)
	button.add_theme_font_override("font",Style.body_font()); button.add_theme_font_size_override("font_size",20)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var box := Style.box(Color.WHITE,12); box.border_color=Color("c5b79f"); box.set_border_width_all(1); box.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state,box)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(state,Color("303134"))
	for state in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]: button.add_theme_color_override(state,Color.WHITE)

func _process(_delta: float) -> void:
	for name in ["ErrorLabel","LoadingLabel","PasswordStrength"]:
		var label := screen.get_node_or_null("%"+name) as Label
		if label != null:
			var progress := label.get_parent().get_node_or_null("SharedLoadingProgress") as Control
			label.visible=not label.text.strip_edges().is_empty() and not (name=="LoadingLabel" and progress!=null and progress.visible)
	for node in center.find_children("PasswordEye","Button",true,false): node.disabled=not node.field.editable
	if screen.name=="EmailVerificationScene":
		var mark := screen.get_node("%FormPanel").find_child("StatusMark",true,false)
		if mark==null:
			mark=Mark.new(); mark.name="StatusMark"; mark.custom_minimum_size=Vector2(48,48)
			var column := screen.get_node("%Title").get_parent(); column.add_child(mark); column.move_child(mark,1)
		mark.checkmark=screen.get_node("%Title").text.contains("Verified"); mark.queue_redraw()
	_fit()

func _fit() -> void:
	var minimum := center.get_combined_minimum_size()
	var viewport := screen.get_viewport_rect().size
	if minimum==_last_min and viewport==_last_view: return
	_last_min=minimum; _last_view=viewport
	var factor := minf(1.0,minf((viewport.x-48)/maxf(620,minimum.x),(viewport.y-160)/maxf(1,minimum.y)))
	center.scale=Vector2.ONE*maxf(0.1,factor); center.size=viewport/center.scale.x
	center.position.y=54*factor
