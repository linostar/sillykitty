class_name Hazard
extends Area2D
## Fails the level when the cat touches it. The scene's collision mask only
## watches the cat's physics layer: the robot hovers over every hazard.
## A hazard with a fear_radius is a threat: the cat flees it while it is scary.

@export var reason := "Splash! Kitty hates water."
## Played by the level when this hazard ends it.
@export var sound: AudioStream
## The cat flees this hazard when it sees it closer than this; 0 = never (a puddle).
@export var fear_radius := 0.0
## True plays the cat's wet splash fail animation, false its dizzy one.
@export var splashes := true

## False while the threat is harmless-looking (a sleeping dog); the cat ignores it.
var scary := true


func _ready() -> void:
	if sound == null:
		push_error("Hazard '%s' has no fail sound assigned" % get_path())
	if fear_radius > 0.0:
		add_to_group(Cat.THREAT_GROUP)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var cat := body as Cat
	if cat != null:
		cat.fall_into(reason, sound, splashes)
