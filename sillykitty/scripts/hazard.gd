class_name Hazard
extends Area2D
## Fails the level when the cat touches it. The scene's collision mask only
## watches the cat's physics layer: the robot hovers over every hazard.

@export var reason := "Splash! Kitty hates water."


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var cat := body as Cat
	if cat != null:
		cat.fall_into(reason)
