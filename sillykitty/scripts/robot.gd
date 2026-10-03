class_name Robot
extends CharacterBody2D
## The player. Movement is the only input in the game: 8-directional top-down
## steering read from the move_* actions. The robot hovers, so hazards ignore it.

## Emitted once, on the first frame with movement input (starts the level clock).
signal started_moving

@export var max_speed := 280.0
@export var acceleration := 1600.0
@export var friction := 1800.0

const HOVER_HEIGHT := 8.0
const BOB_AMPLITUDE := 4.0
const BOB_SPEED := 3.2
const MAX_TILT := 0.18
const FACE_LOOK := Vector2(6.0, 4.0)

## True from the first frame with movement input on.
var has_moved := false

var _time := 0.0

@onready var _hover: Node2D = $Hover
@onready var _shadow: Sprite2D = $Shadow
@onready var _thruster: Sprite2D = $Hover/Thruster
@onready var _antenna: Node2D = $Hover/AntennaPivot
@onready var _face: Sprite2D = $Hover/Face
@onready var _face_rest := _face.position


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if not has_moved and input != Vector2.ZERO:
		has_moved = true
		started_moving.emit()
	var rate := acceleration if input != Vector2.ZERO else friction
	velocity = velocity.move_toward(input * max_speed, rate * delta)
	move_and_slide()


func _process(delta: float) -> void:
	_time += delta
	var lift := HOVER_HEIGHT + sin(_time * BOB_SPEED) * BOB_AMPLITUDE
	_hover.position.y = -lift
	_shadow.scale = Vector2.ONE * remap(lift, HOVER_HEIGHT - BOB_AMPLITUDE, HOVER_HEIGHT + BOB_AMPLITUDE, 1.05, 0.9)
	var thrust := 1.0 + sin(_time * 31.0) * 0.08 + velocity.length() / max_speed * 0.25
	_thruster.scale = Vector2(thrust, thrust)
	var motion := velocity / max_speed
	_hover.rotation = lerp_angle(_hover.rotation, motion.x * MAX_TILT, minf(1.0, delta * 10.0))
	_antenna.rotation = lerp_angle(_antenna.rotation, -motion.x * 0.5 + sin(_time * 5.0) * 0.08, minf(1.0, delta * 8.0))
	_face.position = _face.position.lerp(_face_rest + motion * FACE_LOOK, minf(1.0, delta * 12.0))
