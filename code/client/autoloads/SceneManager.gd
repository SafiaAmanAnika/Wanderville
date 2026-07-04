extends Node

const LOGIN_SCENE := "res://Scenes/menus/LoginScene.tscn"
const SIGNUP_SCENE := "res://Scenes/menus/SignupScene.tscn"
const MAIN_MENU_SCENE := "res://Scenes/menus/MainMenu.tscn"

const TITLE_SCENE := "res://Scenes/menus/TitleScreen.tscn"
const MAP_SELECTION_SCENE := "res://Scenes/menus/MapSelectionScreen.tscn"
const MAP_SHOWCASE_SCENE := "res://Scenes/menus/MapShowcaseScreen.tscn"
const CHARACTER_SELECT_SCENE := "res://Scenes/menus/CharacterSelectScreen.tscn"
const WORLD_SCENE := "res://Scenes/world.tscn"


func goto_login() -> void:
	get_tree().change_scene_to_file(LOGIN_SCENE)


func goto_signup() -> void:
	get_tree().change_scene_to_file(SIGNUP_SCENE)


func goto_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func goto_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func goto_map_selection() -> void:
	get_tree().change_scene_to_file(MAP_SELECTION_SCENE)


func goto_map_showcase() -> void:
	get_tree().change_scene_to_file(MAP_SHOWCASE_SCENE)


func goto_character_select() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func goto_world() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)
