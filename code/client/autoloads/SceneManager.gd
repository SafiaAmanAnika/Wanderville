extends Node

const LOGIN_SCENE := "res://scenes/menus/LoginScene.tscn"
const SIGNUP_SCENE := "res://scenes/menus/SignupScene.tscn"


func goto_login() -> void:
	get_tree().change_scene_to_file(LOGIN_SCENE)


func goto_signup() -> void:
	get_tree().change_scene_to_file(SIGNUP_SCENE)
