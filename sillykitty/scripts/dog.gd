class_name Dog
extends CharacterBody2D
## Sleeps on its spot until it sees the cat within wake_radius (walls block
## its view), then barks and chases the cat for chase_time, trots home and
## sleeps again. The wake radius is far wider than the bite, so in the open the
## cat always wakes the dog before it can touch it. If it cannot get home
## within return_time it lies down where it is, so it never stays awake for
## good. Once the level is over for the cat it no longer wakes or chases. Its
## Bite hazard fails the level on touch, and the cat only fears it while it is
## awake.

enum State { SLEEP, CHASE, RETURN }

## The dog is home once this close to where it started.
const HOME_DISTANCE := 6.0
## Speed per pixel of remaining distance when easing in to home.
const ARRIVE_SLOWDOWN := 5.0
## Diagonal paw pairs move together: back-left with front-right.
const PAW_PHASES: Array[float] = [0.0, PI, PI, 0.0]
## How far the dog looks left and right for the open side to sleep facing.
const LOOK_DISTANCE := 400.0

@export var cat: Cat
@export var wake_radius := 170.0
@export var chase_speed := 190.0
@export var return_speed := 150.0
@export var acceleration := 900.0
@export var chase_time := 3.5
@export var return_time := 6.0

var state := State.SLEEP

var _state_time := 0.0
var _home := Vector2.ZERO
var _anim_time := 0.0
var _walk_phase := 0.0
var _turn := Turn.new()
## Whether the dog has picked the side to sleep facing (on its first physics
## tick, once the walls are in the physics space).
var _faced := false
## Height of the startled jump when the dog wakes, in pixels (tweened).
var _jump := 0.0
var _paw_rest: Array[Vector2] = []

@onready var _bite: Hazard = $Bite
@onready var _visual: Node2D = $Visual
@onready var _shadow: Sprite2D = $Shadow
@onready var _shadow_rest := _shadow.scale
@onready var _body: Sprite2D = $Visual/Body
@onready var _body_rest := _body.position
@onready var _head: Node2D = $Visual/Head
@onready var _head_rest := _head.position
@onready var _ear: Node2D = $Visual/Head/EarPivot
@onready var _eyelid: Sprite2D = $Visual/Head/Eyelid
@onready var _tail: Node2D = $Visual/TailPivot
@onready var _paws: Array[Node2D] = [$Visual/PawBackL, $Visual/PawBackR, $Visual/PawFrontL, $Visual/PawFrontR]
@onready var _snore: Sprite2D = $Snore
@onready var _bark: AudioStreamPlayer2D = $Bark


func _ready() -> void:
	if cat == null:
		push_error("Dog '%s' needs 'cat' assigned" % get_path())
		set_physics_process(false)
		set_process(false)
		return
	_home = global_position
	for paw in _paws:
		_paw_rest.append(paw.position)
	_enter(State.SLEEP)


func _physics_process(delta: float) -> void:
	if not _faced:
		_faced = true
		_face_open_side()
	_state_time += delta
	match state:
		State.SLEEP:
			if _sees_cat():
				_enter(State.CHASE)
		State.CHASE:
			if _state_time >= chase_time or cat.is_over():
				_enter(State.RETURN)
		State.RETURN:
			if global_position.distance_to(_home) <= HOME_DISTANCE or _state_time >= return_time:
				_enter(State.SLEEP)
	velocity = velocity.move_toward(_desired_velocity(), acceleration * delta)
	move_and_slide()


## Faces the side with more room, so the dog never sleeps nose to a fence or
## a hedge.
func _face_open_side() -> void:
	var space := get_world_2d().direct_space_state
	var room: Array[float] = []
	for side: float in [-1.0, 1.0]:
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(side * LOOK_DISTANCE, 0.0),
			Cat.WALL_LAYER_MASK)
		var hit := space.intersect_ray(query)
		room.append(LOOK_DISTANCE if hit.is_empty() else global_position.distance_to(hit.position))
	_turn.face(-1.0 if room[0] > room[1] else 1.0)


func _sees_cat() -> bool:
	if cat.is_over() or global_position.distance_to(cat.global_position) >= wake_radius:
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, cat.global_position, Cat.WALL_LAYER_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _desired_velocity() -> Vector2:
	match state:
		State.CHASE:
			return global_position.direction_to(cat.global_position) * chase_speed
		State.RETURN:
			var offset := _home - global_position
			# Eases in over the last few pixels instead of overshooting home.
			return (offset * ARRIVE_SLOWDOWN).limit_length(return_speed) if offset.length() > HOME_DISTANCE else Vector2.ZERO
		_:
			return Vector2.ZERO


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	_bite.scary = new_state != State.SLEEP
	_eyelid.visible = new_state == State.SLEEP
	_snore.visible = new_state == State.SLEEP
	if new_state == State.CHASE:
		_bark.play()
		var tween := create_tween()
		tween.tween_property(self, "_jump", 26.0, 0.12).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "_jump", 0.0, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_anim_time += delta
	# Turns round like the cat (see Turn).
	if absf(velocity.x) > Turn.MIN_SPEED:
		_turn.want(signf(velocity.x))
	_turn.advance(delta)
	_visual.scale.x = _turn.facing
	var speed := velocity.length()
	if state == State.SLEEP:
		_animate_sleep(delta)
	elif speed > 10.0:
		_animate_walk(delta, speed)
	else:
		_animate_stand(delta)
	# The animations place the head; the turn swings it across the body.
	_head.position.x *= 1.0 - 2.0 * _turn.head_shift
	_head.scale.x = -1.0 if _turn.head_mirrored() else 1.0
	_visual.position.y = -(_jump + _turn.lift * Turn.HOP)
	_shadow.scale = _shadow_rest * (1.0 - Turn.SHADOW_SHRINK * _turn.lift)


func _animate_sleep(delta: float) -> void:
	var breath := sin(_anim_time * 1.8)
	_body.position.y = _body_rest.y + 6.0
	_body.scale.y = 0.9 + breath * 0.03
	_head.position = _head_rest + Vector2(2.0, 16.0)
	_head.rotation = lerp_angle(_head.rotation, 0.15, minf(1.0, delta * 6.0))
	_tail.rotation = lerp_angle(_tail.rotation, 1.1, minf(1.0, delta * 4.0))
	_ear.rotation = 0.2
	for i in _paws.size():
		_paws[i].position = _paws[i].position.lerp(_paw_rest[i], minf(1.0, delta * 12.0))
	_snore.position.y = -70.0 - (fmod(_anim_time, 2.0)) * 8.0
	_snore.modulate.a = 1.0 - fmod(_anim_time, 2.0) / 2.0


func _animate_walk(delta: float, speed: float) -> void:
	_walk_phase += delta * speed * 0.08
	for i in _paws.size():
		var lift := maxf(0.0, sin(_walk_phase + PAW_PHASES[i])) * 6.0
		_paws[i].position = _paw_rest[i] + Vector2(0.0, -lift)
	_body.position.y = _body_rest.y - absf(sin(_walk_phase)) * 2.0
	_body.scale.y = 1.0
	_head.position = _head_rest + Vector2(0.0, sin(_walk_phase * 2.0) * 1.5)
	_head.rotation = sin(_walk_phase) * 0.05
	_ear.rotation = sin(_walk_phase * 2.0) * 0.35
	_tail.rotation = sin(_anim_time * 16.0) * 0.4


func _animate_stand(delta: float) -> void:
	for i in _paws.size():
		_paws[i].position = _paws[i].position.lerp(_paw_rest[i], minf(1.0, delta * 12.0))
	_body.position.y = _body_rest.y
	_body.scale.y = 1.0 + sin(_anim_time * 3.0) * 0.02
	_head.position = _head_rest
	_head.rotation = lerp_angle(_head.rotation, 0.0, minf(1.0, delta * 6.0))
	_ear.rotation = sin(_anim_time * 4.0) * 0.1
	_tail.rotation = sin(_anim_time * 12.0) * 0.4
