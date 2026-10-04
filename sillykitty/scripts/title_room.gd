class_name TitleRoom
extends Node2D
## The title room (main scene). The cat and robot are live; the player's first
## movement starts the game at the furthest unlocked level. No other input exists.

## The jam restriction, shown on the title (plan criterion 16).
const RESTRICTION_TEXT := "You only ever move the robot; the cat decides everything else."
## Seconds between the first movement and the level loading, so the start registers.
const START_DELAY := 0.6

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _robot: Robot = %Robot
@onready var _tagline: Label = %Tagline
@onready var _progress: Label = %Progress


func _ready() -> void:
	_tagline.text = RESTRICTION_TEXT
	var stars := _game.star_total()
	if _game.furthest_index > 0 or stars.x > 0:
		_progress.text = "Continue at level %d of %d  -  %d of %d stars" % [_game.furthest_index + 1, _game.level_count(),
			stars.x, stars.y]
	else:
		_progress.text = "%d levels. Lead the kitty to its bed!" % _game.level_count()
	_robot.started_moving.connect(_on_robot_started_moving)
	_game.enter_room("title room")


func _on_robot_started_moving() -> void:
	await get_tree().create_timer(START_DELAY).timeout
	_game.start_game()
