class_name Level
extends Node2D
## Runs one level: the countdown (started by the player's first movement), the
## HUD and the outcome banner. It only reports the outcome through `finished`;
## the Game autoload decides what loads next, so no input is ever needed.

signal finished(cleared: bool, stars: int)

const CLEAR_TEXT := "Purrfect! Kitty is home."
const TIME_UP_TEXT := "Time's up! Kitty lost interest."
## The countdown turns red and ticks once per second for the last 10 seconds,
## or the last 40% of a shorter limit (see warning_seconds).
const WARNING_SECONDS := 10.0
const WARNING_FRACTION := 0.4
## Fractions of the time limit still left for 3 and 2 stars; any clear earns 1.
## Every time limit is at least 1.25x its level's scripted solution time, so a
## run at that pace always leaves 20% and earns 3 stars.
const THREE_STAR_FRACTION := 0.2
const TWO_STAR_FRACTION := 0.1
## Screen shake on a fail: peak offset in pixels, duration and number of jolts.
const SHAKE_STRENGTH := 12.0
const SHAKE_TIME := 0.45
const SHAKE_STEPS := 9

@export var time_limit := 60.0
@export_multiline var hint := "Lead the kitty to its bed!"

var time_left := 0.0
var clock_running := false

var _over := false
var _warning := 0.0
var _rng := RandomNumberGenerator.new()

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _robot: Robot = %Robot
@onready var _cat: Cat = %Cat
@onready var _hud: Hud = %Hud
@onready var _sfx_fail: AudioStreamPlayer = %SfxFail
@onready var _sfx_clear: AudioStreamPlayer = %SfxClear


static func warning_seconds(limit: float) -> float:
	return minf(WARNING_SECONDS, limit * WARNING_FRACTION)


static func stars_for(seconds_left: float, limit: float) -> int:
	if seconds_left >= limit * THREE_STAR_FRACTION:
		return 3
	if seconds_left >= limit * TWO_STAR_FRACTION:
		return 2
	return 1


func _ready() -> void:
	time_left = time_limit
	_warning = warning_seconds(time_limit)
	var number := _game.level_number(scene_file_path)
	if number == 0:
		push_error("Level '%s' is not listed in GameState.LEVEL_PATHS" % scene_file_path)
	_hud.set_level(number, _game.level_count())
	_hud.set_hint(hint)
	_hud.set_time(time_left, false)
	if not _game.retrying:
		_hud.show_intro(number, hint)
	_robot.started_moving.connect(_on_robot_started_moving)
	_cat.failed.connect(_on_cat_failed)
	_cat.reached_goal.connect(_on_cat_reached_goal)
	_game.attach_level(self)


func _process(delta: float) -> void:
	if not clock_running:
		return
	var shown_before := ceili(time_left)
	time_left = maxf(0.0, time_left - delta)
	var shown_now := ceili(time_left)
	_hud.set_time(time_left, shown_now <= _warning)
	if shown_now < shown_before and shown_now <= _warning and shown_now > 0:
		_hud.play_tick()
	if time_left <= 0.0:
		_cat.time_up(TIME_UP_TEXT, _hud.time_up_sound)


func _on_robot_started_moving() -> void:
	if not _over:
		clock_running = true


func _on_cat_failed(reason: String, sound: AudioStream) -> void:
	# Hazards guarantee a sound (they report a missing one at load); tests may pass none.
	if sound != null:
		_sfx_fail.stream = sound
		_sfx_fail.play()
	_shake()
	_finish(false, reason, -1)


func _on_cat_reached_goal() -> void:
	_sfx_clear.play()
	_finish(true, CLEAR_TEXT, stars_for(time_left, time_limit))


func _finish(cleared: bool, text: String, stars: int) -> void:
	if _over:
		return
	_over = true
	clock_running = false
	_hud.show_banner(text, stars)
	finished.emit(cleared, stars)


## Jolts the whole room (not the HUD, which is a CanvasLayer) and settles it back.
func _shake() -> void:
	var tween := create_tween()
	for i in SHAKE_STEPS:
		var strength := SHAKE_STRENGTH * (1.0 - float(i) / SHAKE_STEPS)
		var offset := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * strength
		tween.tween_property(self, "position", offset, SHAKE_TIME / SHAKE_STEPS)
	tween.tween_property(self, "position", Vector2.ZERO, SHAKE_TIME / SHAKE_STEPS)
