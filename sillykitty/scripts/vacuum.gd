class_name Vacuum
extends Hazard
## The robot lawnmower (named Vacuum in code) on a fixed patrol loop: from
## where it starts it drives to each waypoint in turn, then round again from the
## first. The cat flees it, and touching it fails the level.

## Patrol points in the parent's coordinates, visited in order and looped.
@export var waypoints: PackedVector2Array
@export var speed := 110.0

var _next := 0
var _time := 0.0

@onready var _visual: Node2D = $Visual
@onready var _brushes: Array[Node2D] = [$Visual/BrushLeft/Brush, $Visual/BrushRight/Brush]
@onready var _light: Sprite2D = $Visual/Light


func _ready() -> void:
	super._ready()
	if waypoints.is_empty():
		push_error("Vacuum '%s' has no waypoints" % get_path())
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	position = position.move_toward(waypoints[_next], speed * delta)
	if position == waypoints[_next]:
		_next = (_next + 1) % waypoints.size()


func _process(delta: float) -> void:
	_time += delta
	_brushes[0].rotation -= delta * 14.0
	_brushes[1].rotation += delta * 14.0
	_visual.position.y = sin(_time * 47.0) * 0.7
	_light.visible = fmod(_time, 0.8) < 0.5
