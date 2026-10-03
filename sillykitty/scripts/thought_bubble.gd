class_name ThoughtBubble
extends Node2D
## A thought bubble above the cat showing an icon for its current state, with
## the nap meter above it while the meter is not empty. Display only.

## Icons are scaled to fit a square of this many pixels.
const ICON_SIZE := 30.0
const METER_RECT := Rect2(-24.0, -42.0, 48.0, 7.0)
const METER_BACK := Color(0.231, 0.173, 0.208, 0.35)
const METER_FILL := Color("#8A8FE0")
const POP_TIME := 0.2

@export var idle_icon: Texture2D
@export var chase_icon: Texture2D
@export var distracted_icon: Texture2D
@export var go_to_bed_icon: Texture2D
@export var flee_icon: Texture2D
@export var nap_icon: Texture2D

var _nap := 0.0

@onready var _cloud: Node2D = $Cloud
@onready var _icon: Sprite2D = $Cloud/Icon


func _ready() -> void:
	for icon: Texture2D in [idle_icon, chase_icon, distracted_icon, go_to_bed_icon, flee_icon, nap_icon]:
		if icon == null:
			push_error("ThoughtBubble '%s' is missing a state icon" % get_path())
			return


## The icon for a cat state, or null for states without a bubble (FAILED, CLEARED).
func icon_for(state: Cat.State) -> Texture2D:
	match state:
		Cat.State.IDLE:
			return idle_icon
		Cat.State.CHASE_ROBOT:
			return chase_icon
		Cat.State.DISTRACTED:
			return distracted_icon
		Cat.State.GO_TO_BED:
			return go_to_bed_icon
		Cat.State.FLEE:
			return flee_icon
		Cat.State.NAP:
			return nap_icon
		_:
			return null


## The icon on show, or null when the bubble is hidden.
func shown_icon() -> Texture2D:
	return _icon.texture if visible else null


## Swaps the icon with a little pop; hides the bubble for states without one.
func show_state(state: Cat.State) -> void:
	var icon := icon_for(state)
	visible = icon != null
	if icon == null or icon == _icon.texture:
		return
	_icon.texture = icon
	_icon.scale = Vector2.ONE * ICON_SIZE / maxf(icon.get_width(), icon.get_height())
	_cloud.scale = Vector2(0.6, 0.6)
	create_tween().tween_property(_cloud, "scale", Vector2.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## `value` 0..1; the meter is drawn only while above 0.
func set_nap(value: float) -> void:
	if not is_equal_approx(value, _nap):
		_nap = value
		queue_redraw()


func _draw() -> void:
	if _nap <= 0.0:
		return
	draw_rect(METER_RECT, METER_BACK)
	draw_rect(Rect2(METER_RECT.position, Vector2(METER_RECT.size.x * _nap, METER_RECT.size.y)), METER_FILL)
