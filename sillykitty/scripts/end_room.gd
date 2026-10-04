class_name EndRoom
extends Node2D
## Shown after the last level: the cat home in its bed, the star total, credits
## and confetti. Game loads level 1 after GameState.END_ROOM_TIME; no input needed.

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _headline: Label = %Headline
@onready var _stars: Label = %StarTotal
@onready var _confetti: CPUParticles2D = %Confetti


func _ready() -> void:
	_headline.text = GameState.END_TEXT
	var stars := _game.star_total()
	_stars.text = "%d of %d stars" % [stars.x, stars.y]
	_confetti.emitting = true
	_game.enter_room("end room")
