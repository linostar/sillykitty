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
## The bubble art trails its small circles down to the left; this is the tip
## of that trail relative to the unmirrored cloud's centre.
const TRAIL_TIP := Vector2(-27.0, 25.0)
## Facing right, the cloud sits this far right of the cat so its (mirrored)
## trail ends just above the head; facing left, everything mirrors.
const CLOUD_X := 3.0
## The icon sits this far from the cloud's centre, towards the puffy side.
const ICON_X := 2.0

@export var idle_icon: Texture2D
@export var chase_icon: Texture2D
@export var distracted_icon: Texture2D
@export var go_to_bed_icon: Texture2D
@export var flee_icon: Texture2D
@export var nap_icon: Texture2D

var _nap := 0.0
## The nap meter's sideways offset, kept centred over the cloud.
var _meter_x := CLOUD_X

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


## Mirrors the cloud so its trail ends above the cat's head, which is on the
## side given (+1 right, -1 left). The icon itself is never mirrored.
func face(facing: float) -> void:
	_cloud.flip_h = facing > 0.0
	_cloud.position.x = CLOUD_X * facing
	_icon.position.x = -ICON_X * facing
	if _meter_x != _cloud.position.x:
		_meter_x = _cloud.position.x
		queue_redraw()


## Where the trail of small circles ends, in global coordinates.
func trail_tip() -> Vector2:
	return _cloud.to_global(TRAIL_TIP * Vector2(-1.0 if _cloud.flip_h else 1.0, 1.0))


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
	var meter := Rect2(METER_RECT.position + Vector2(_meter_x, 0.0), METER_RECT.size)
	draw_rect(meter, METER_BACK)
	draw_rect(Rect2(meter.position, Vector2(meter.size.x * _nap, meter.size.y)), METER_FILL)
