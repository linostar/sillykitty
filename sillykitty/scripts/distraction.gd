class_name Distraction
extends Node2D
## Something the cat may abandon the robot for. After the cat has played with
## it, it stays boring for a cooldown and is drawn faded.

@export var appeal := 1.0

var _cooldown_left := 0.0
var _in_play := false
var _time := 0.0

@onready var _sprite: Node2D = $Sprite


func _ready() -> void:
	add_to_group(Cat.DISTRACTION_GROUP)


func is_available() -> bool:
	return _cooldown_left <= 0.0


func start_play() -> void:
	_in_play = true


func finish_play(cooldown: float) -> void:
	_in_play = false
	_cooldown_left = cooldown


func _process(delta: float) -> void:
	_time += delta
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _in_play:
		_sprite.position = Vector2(sin(_time * 11.0) * 6.0, -absf(sin(_time * 9.0)) * 8.0)
		_sprite.rotation = sin(_time * 7.0) * 0.6
	else:
		_sprite.position = _sprite.position.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
		_sprite.rotation = lerp_angle(_sprite.rotation, 0.0, minf(1.0, delta * 8.0))
	modulate.a = 0.45 if _cooldown_left > 0.0 else 1.0
