extends Node

const LOGIN_SCENE := "res://Scenes/menus/LoginScene.tscn"
const SIGNUP_SCENE := "res://Scenes/menus/SignupScene.tscn"
const MAIN_MENU_SCENE := "res://Scenes/menus/MainMenu.tscn"


func goto_login() -> void:
	get_tree().change_scene_to_file(LOGIN_SCENE)


func goto_signup() -> void:
	get_tree().change_scene_to_file(SIGNUP_SCENE)


func goto_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
