class_name Level
extends Node2D
## Runs one level: shows the outcome banner and restarts automatically, so the
## player never needs anything but movement input.

signal finished(cleared: bool)

const FAIL_RESTART_DELAY := 1.6
const CLEAR_RESTART_DELAY := 2.5
const CLEAR_TEXT := "Purrfect! Kitty is home."

var _over := false

@onready var _cat: Cat = %Cat
@onready var _banner: Label = %Banner
@onready var _sfx_splash: AudioStreamPlayer = %SfxSplash
@onready var _sfx_clear: AudioStreamPlayer = %SfxClear


func _ready() -> void:
	_banner.visible = false
	_cat.failed.connect(_on_cat_failed)
	_cat.reached_goal.connect(_on_cat_reached_goal)


func _on_cat_failed(reason: String) -> void:
	_sfx_splash.play()
	_finish(false, reason, FAIL_RESTART_DELAY)


func _on_cat_reached_goal() -> void:
	_sfx_clear.play()
	_finish(true, CLEAR_TEXT, CLEAR_RESTART_DELAY)


func _finish(cleared: bool, text: String, delay: float) -> void:
	if _over:
		return
	_over = true
	_banner.text = text
	_banner.visible = true
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	finished.emit(cleared)
	await get_tree().create_timer(delay).timeout
	var error := get_tree().reload_current_scene()
	if error != OK:
		push_error("Level '%s' failed to restart: %s" % [scene_file_path, error_string(error)])
