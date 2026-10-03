class_name Level
extends Node2D
## Runs one level: the countdown (started by the player's first movement), the
## HUD and the outcome banner. It only reports the outcome through `finished`;
## the Game autoload decides what loads next, so no input is ever needed.

signal finished(cleared: bool, stars: int)

const CLEAR_TEXT := "Purrfect! Kitty is home."
const TIME_UP_TEXT := "Time's up! Kitty lost interest."
## The countdown turns red and ticks once per second from here down.
const WARNING_SECONDS := 10
## Fractions of the time limit still left for 3 and 2 stars; any clear earns 1.
## Every time limit is at least 1.25x its level's scripted solution time, so a
## run at that pace always leaves 20% and earns 3 stars.
const THREE_STAR_FRACTION := 0.2
const TWO_STAR_FRACTION := 0.1

@export var time_limit := 60.0
@export_multiline var hint := "Lead the kitty to its bed!"

var time_left := 0.0
var clock_running := false

var _over := false

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _robot: Robot = %Robot
@onready var _cat: Cat = %Cat
@onready var _hud: Hud = %Hud
@onready var _sfx_fail: AudioStreamPlayer = %SfxFail
@onready var _sfx_clear: AudioStreamPlayer = %SfxClear


static func stars_for(seconds_left: float, limit: float) -> int:
	if seconds_left >= limit * THREE_STAR_FRACTION:
		return 3
	if seconds_left >= limit * TWO_STAR_FRACTION:
		return 2
	return 1


func _ready() -> void:
	time_left = time_limit
	var number := _game.level_number(scene_file_path)
	if number == 0:
		push_error("Level '%s' is not listed in GameState.LEVEL_PATHS" % scene_file_path)
	_hud.set_level(number, _game.level_count())
	_hud.set_hint(hint)
	_hud.set_time(time_left, false)
	_robot.started_moving.connect(_on_robot_started_moving)
	_cat.failed.connect(_on_cat_failed)
	_cat.reached_goal.connect(_on_cat_reached_goal)
	_game.attach_level(self)


## Used by Game for the end-of-game banner.
func show_banner(text: String) -> void:
	_hud.show_banner(text)


func _process(delta: float) -> void:
	if not clock_running:
		return
	var shown_before := ceili(time_left)
	time_left = maxf(0.0, time_left - delta)
	var shown_now := ceili(time_left)
	_hud.set_time(time_left, shown_now <= WARNING_SECONDS)
	if shown_now < shown_before and shown_now <= WARNING_SECONDS and shown_now > 0:
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
