class_name Goal
extends Node2D
## The cat's bed. A cat within its goal_sense_radius walks in by itself.


func _ready() -> void:
	add_to_group(Cat.GOAL_GROUP)
