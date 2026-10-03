class_name Hazard
extends Area2D
## Fails the level when the cat touches it. The scene's collision mask only
## watches the cat's physics layer: the robot hovers over every hazard.

@export var reason := "Splash! Kitty hates water."
## Played by the level when this hazard ends it.
@export var sound: AudioStream


func _ready() -> void:
	if sound == null:
		push_error("Hazard '%s' has no fail sound assigned" % get_path())
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var cat := body as Cat
	if cat != null:
		cat.fall_into(reason, sound)
