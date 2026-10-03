extends Node
## Entry scene: hands over to the Game autoload, which loads the furthest unlocked level.


func _ready() -> void:
	(get_node(GameState.AUTOLOAD_PATH) as GameState).start_game.call_deferred()
