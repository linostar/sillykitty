class_name Cat
extends CharacterBody2D
## The AI cat. Every physics tick it scores each option (do nothing, follow the
## robot, play with a distraction, walk into its bed) and follows the best one.
## The current choice gets a hysteresis bonus so the cat does not flicker.
## Distractions and beds are only sensed in line of sight, and a target the cat
## cannot get closer to is given up for a while, so the cat never stays stuck
## (the player has no restart button). All numbers come from CatTuning.

signal state_changed(new_state: State)
signal failed(reason: String, sound: AudioStream)
signal reached_goal

enum State { IDLE, CHASE_ROBOT, DISTRACTED, GO_TO_BED, FAILED, CLEARED }

const DISTRACTION_GROUP := &"distractions"
const GOAL_GROUP := &"goals"
## Diagonal paw pairs move together: back-left with front-right.
const PAW_PHASES: Array[float] = [0.0, PI, PI, 0.0]
const WET_TINT := Color("#9fd4ee")
## Physics layer of walls and furniture; blocks the cat's line of sight.
const WALL_LAYER_MASK := 1

@export var tuning: CatTuning
@export var robot: Robot

var state := State.IDLE

var _distraction: Distraction
var _goal: Goal
var _engage_left := 0.0
var _meow_cooldown_left := 0.0
var _anim_time := 0.0
var _walk_phase := 0.0
var _facing := 1.0
var _ear_twitch_in := 0.0
var _paw_rest: Array[Vector2] = []
var _ear_rest: Array[float] = []
var _rng := RandomNumberGenerator.new()
## Given-up targets: instance id -> seconds left to ignore them. Ids, not
## references, so a freed target is never dereferenced.
var _ignored: Dictionary[int, float] = {}
var _progress_target_id := 0
var _progress_best := INF
var _progress_stall := 0.0

@onready var _visual: Node2D = $Visual
@onready var _body: Sprite2D = $Visual/Body
@onready var _body_rest := _body.position
@onready var _head: Node2D = $Visual/Head
@onready var _tail: Node2D = $Visual/TailPivot
@onready var _ears: Array[Node2D] = [$Visual/Head/EarBack, $Visual/Head/EarFront]
@onready var _paws: Array[Node2D] = [$Visual/PawBackL, $Visual/PawBackR, $Visual/PawFrontL, $Visual/PawFrontR]
@onready var _meow: AudioStreamPlayer2D = $Meow
@onready var _boing: AudioStreamPlayer2D = $Boing
@onready var _splash_fx: CPUParticles2D = $SplashFx


func _ready() -> void:
	if tuning == null or robot == null:
		push_error("Cat '%s' needs both 'tuning' and 'robot' assigned" % get_path())
		set_physics_process(false)
		set_process(false)
		return
	_rng.randomize()
	for paw in _paws:
		_paw_rest.append(paw.position)
	for ear in _ears:
		_ear_rest.append(ear.rotation)
	_ear_twitch_in = _rng.randf_range(1.5, 4.0)


## Called by hazards. Ends the level with a comic fail animation.
func fall_into(reason: String, sound: AudioStream) -> void:
	if state == State.FAILED or state == State.CLEARED:
		return
	if is_instance_valid(_distraction):
		_distraction.finish_play(0.0)
	_distraction = null
	velocity = Vector2.ZERO
	_set_state(State.FAILED)
	_splash_fx.restart()
	failed.emit(reason, sound)
	_play_fail_animation()


func _physics_process(delta: float) -> void:
	_meow_cooldown_left = maxf(0.0, _meow_cooldown_left - delta)
	if state == State.FAILED or state == State.CLEARED:
		return
	_think(delta)
	if state == State.DISTRACTED and _engage_left <= 0.0 \
			and global_position.distance_to(_distraction.global_position) <= tuning.engage_distance:
		_engage_left = tuning.engage_time
		_distraction.start_play()
		_boing.play()
	velocity = velocity.move_toward(_desired_velocity(), tuning.acceleration * delta)
	move_and_slide()
	if state == State.GO_TO_BED and global_position.distance_to(_goal.global_position) <= tuning.arrive_distance:
		_clear()


func _think(delta: float) -> void:
	# A distraction or bed removed from the level mid-play: drop it and choose again.
	if not is_instance_valid(_distraction):
		_distraction = null
		_engage_left = 0.0
	if not is_instance_valid(_goal):
		_goal = null
	_tick_ignored(delta)
	if state == State.DISTRACTED and _engage_left > 0.0:
		_engage_left -= delta
		if _engage_left > 0.0:
			return
		_distraction.finish_play(tuning.distraction_cooldown)
		_distraction = null

	var best_state := State.IDLE
	var best_score := tuning.idle_score + _bonus(State.IDLE)
	var best_distraction: Distraction = null
	var best_goal: Goal = null

	var robot_distance := global_position.distance_to(robot.global_position)
	if robot_distance < tuning.interest_radius:
		var chase := tuning.chase_weight * (1.0 - tuning.chase_falloff * robot_distance / tuning.interest_radius)
		chase += _bonus(State.CHASE_ROBOT)
		if chase > best_score:
			best_score = chase
			best_state = State.CHASE_ROBOT

	for node in get_tree().get_nodes_in_group(DISTRACTION_GROUP):
		var distraction := node as Distraction
		if distraction == null or not distraction.is_available():
			continue
		var distance := global_position.distance_to(distraction.global_position)
		if distance >= tuning.distraction_sense_radius or not _can_sense(distraction):
			continue
		var score := tuning.distraction_weight * distraction.appeal * (1.0 - distance / tuning.distraction_sense_radius)
		if distraction == _distraction:
			score += tuning.hysteresis
		if score > best_score:
			best_score = score
			best_state = State.DISTRACTED
			best_distraction = distraction

	for node in get_tree().get_nodes_in_group(GOAL_GROUP):
		var goal := node as Goal
		if goal == null or global_position.distance_to(goal.global_position) >= tuning.goal_sense_radius \
				or not _can_sense(goal):
			continue
		if tuning.goal_weight > best_score:
			best_score = tuning.goal_weight
			best_state = State.GO_TO_BED
			best_goal = goal

	_distraction = best_distraction
	_goal = best_goal
	_set_state(best_state)
	_track_progress(delta)


## True when the target is not given up and no wall blocks the straight line to it.
func _can_sense(target: Node2D) -> bool:
	if _ignored.has(target.get_instance_id()):
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, WALL_LAYER_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _tick_ignored(delta: float) -> void:
	for id: int in _ignored.keys():
		_ignored[id] -= delta
		if _ignored[id] <= 0.0:
			_ignored.erase(id)


## Gives up on the distraction or bed being approached when the cat has not got
## closer for give_up_time (e.g. it is pressed against furniture).
func _track_progress(delta: float) -> void:
	var target: Node2D = null
	if state == State.DISTRACTED and _engage_left <= 0.0:
		target = _distraction
	elif state == State.GO_TO_BED:
		target = _goal
	var target_id := target.get_instance_id() if target != null else 0
	if target_id != _progress_target_id:
		_progress_target_id = target_id
		_progress_best = INF
		_progress_stall = 0.0
	if target == null:
		return
	var distance := global_position.distance_to(target.global_position)
	if distance < _progress_best - tuning.min_progress:
		_progress_best = distance
		_progress_stall = 0.0
		return
	_progress_stall += delta
	if _progress_stall >= tuning.give_up_time:
		_ignored[target_id] = tuning.give_up_cooldown
		_progress_target_id = 0


func _bonus(option: State) -> float:
	return tuning.hysteresis if option == state else 0.0


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var previous := state
	state = new_state
	state_changed.emit(new_state)
	if new_state == State.CHASE_ROBOT and previous == State.IDLE and _meow_cooldown_left <= 0.0:
		_meow.play()
		_meow_cooldown_left = tuning.meow_cooldown


func _desired_velocity() -> Vector2:
	match state:
		State.CHASE_ROBOT:
			var far := global_position.distance_to(robot.global_position) > tuning.run_distance
			return _seek(robot.global_position, tuning.stop_distance, tuning.run_speed if far else tuning.walk_speed)
		State.DISTRACTED:
			if _engage_left > 0.0:
				return Vector2.ZERO
			return _seek(_distraction.global_position, 0.0, tuning.run_speed)
		State.GO_TO_BED:
			return _seek(_goal.global_position, 0.0, tuning.walk_speed)
		_:
			return Vector2.ZERO


func _seek(target: Vector2, stop_at: float, speed: float) -> Vector2:
	var offset := target - global_position
	var distance := offset.length()
	if distance <= stop_at:
		return Vector2.ZERO
	# Ease in over the last stretch so the cat settles instead of overshooting.
	return offset / distance * minf(speed, (distance - stop_at) * tuning.arrive_slowdown)


func _clear() -> void:
	velocity = Vector2.ZERO
	global_position = _goal.global_position
	_set_state(State.CLEARED)
	reached_goal.emit()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_visual, "scale", Vector2(_facing * 1.08, 0.85), 0.4).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_tail, "rotation", 1.2, 0.5)
	tween.tween_property(_head, "rotation", 0.25, 0.5)


func _play_fail_animation() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_visual, "position:y", -70.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "rotation", TAU * _facing, 0.6)
	tween.tween_property(_visual, "modulate", WET_TINT, 0.3)
	tween.chain().tween_property(_visual, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "scale", Vector2(_facing * 1.25, 0.7), 0.35)


func _process(delta: float) -> void:
	_anim_time += delta
	if state == State.FAILED or state == State.CLEARED:
		return
	_update_facing(delta)
	var engaged := state == State.DISTRACTED and _engage_left > 0.0
	var speed := velocity.length()
	if speed > 10.0:
		_animate_walk(delta, speed)
	elif engaged:
		_animate_play()
	else:
		_animate_sit(delta)
	if not engaged:
		_visual.position.y = 0.0
	_update_ear_twitch(delta)


func _update_facing(delta: float) -> void:
	if absf(velocity.x) > 8.0:
		_facing = signf(velocity.x)
	elif state == State.CHASE_ROBOT and not is_equal_approx(robot.global_position.x, global_position.x):
		_facing = signf(robot.global_position.x - global_position.x)
	_visual.scale.x = move_toward(_visual.scale.x, _facing, delta * 10.0)


func _animate_walk(delta: float, speed: float) -> void:
	_walk_phase += delta * speed * 0.09
	for i in _paws.size():
		var lift := maxf(0.0, sin(_walk_phase + PAW_PHASES[i])) * 5.0
		_paws[i].position = _paw_rest[i] + Vector2(0.0, -lift)
	_body.position.y = _body_rest.y - absf(sin(_walk_phase)) * 1.5
	_body.scale.y = 1.0
	_tail.rotation = -0.25 + sin(_anim_time * 6.0) * 0.15
	_head.rotation = sin(_walk_phase) * 0.04


func _animate_play() -> void:
	_visual.position.y = -absf(sin(_anim_time * 9.0)) * 7.0
	_head.rotation = sin(_anim_time * 7.0) * 0.18
	_tail.rotation = sin(_anim_time * 12.0) * 0.35


func _animate_sit(delta: float) -> void:
	for i in _paws.size():
		_paws[i].position = _paws[i].position.lerp(_paw_rest[i], minf(1.0, delta * 12.0))
	_body.position.y = _body_rest.y
	_body.scale.y = 1.0 + sin(_anim_time * 2.4) * 0.025
	_tail.rotation = sin(_anim_time * 1.6) * 0.3
	_head.rotation = lerp_angle(_head.rotation, 0.0, minf(1.0, delta * 6.0))


func _update_ear_twitch(delta: float) -> void:
	_ear_twitch_in -= delta
	if _ear_twitch_in > 0.0:
		return
	_ear_twitch_in = _rng.randf_range(1.5, 4.0)
	var index := _rng.randi_range(0, _ears.size() - 1)
	var tween := create_tween()
	tween.tween_property(_ears[index], "rotation", _ear_rest[index] + 0.35, 0.06)
	tween.tween_property(_ears[index], "rotation", _ear_rest[index], 0.12)
