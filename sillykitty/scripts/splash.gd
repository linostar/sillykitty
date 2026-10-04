class_name Splash
extends Node2D
## The loading screen (main scene): the Silly Kitty logo, the cat head popping
## in above the title, for SPLASH_TIME seconds; then the Game autoload loads
## the title room. Display only; it takes no input.

const SPLASH_TIME := 2.0
const POP_TIME := 0.45
## The title rises into place after the head has popped in.
const TITLE_DELAY := 0.25
const TITLE_RISE := 30.0
const TITLE_TIME := 0.35
## The head bobs gently while the logo shows: tilt (radians) and period (seconds).
const BOB_TILT := 0.06
const BOB_TIME := 0.5

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _head: Sprite2D = %Head
@onready var _title: Label = %Title


func _ready() -> void:
	_game.enter_room("splash screen")
	var head_scale := _head.scale
	_head.scale = Vector2.ZERO
	var pop := create_tween()
	pop.tween_property(_head, "scale", head_scale, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_head, "rotation", BOB_TILT, BOB_TIME / 2.0).set_trans(Tween.TRANS_SINE)
	pop.tween_property(_head, "rotation", -BOB_TILT, BOB_TIME).set_trans(Tween.TRANS_SINE)
	pop.tween_property(_head, "rotation", 0.0, BOB_TIME / 2.0).set_trans(Tween.TRANS_SINE)
	var title_rest := _title.position
	_title.position.y += TITLE_RISE
	_title.modulate.a = 0.0
	var rise := create_tween().set_parallel(true)
	rise.tween_property(_title, "position", title_rest, TITLE_TIME).set_delay(TITLE_DELAY).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rise.tween_property(_title, "modulate:a", 1.0, TITLE_TIME).set_delay(TITLE_DELAY)
	# Bound to this scene, so a splash that is freed early never changes scene.
	create_tween().tween_callback(_game.show_title).set_delay(SPLASH_TIME)
