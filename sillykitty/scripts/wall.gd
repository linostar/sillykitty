@tool
class_name Wall
extends StaticBody2D
## Room wall or furniture block. The origin is the bottom-centre of the
## footprint so walls placed under a y-sorted node sort correctly with actors.
## Only the footprint collides; the front face below it is decoration.
## Runs in the editor so levels can be laid out visually.

const FRONT_HEIGHT := 18.0
const INK := Color("#3B2C35")

@export var size := Vector2(128.0, 64.0):
	set(value):
		size = value
		queue_redraw()
@export var top_color := Color("#C99C74"):
	set(value):
		top_color = value
		queue_redraw()
@export var front_color := Color("#A77B5A"):
	set(value):
		front_color = value
		queue_redraw()


func _ready() -> void:
	# Collision is built at runtime only, so the editor never saves a generated child.
	if Engine.is_editor_hint():
		return
	var shape := RectangleShape2D.new()
	shape.size = size
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0.0, -size.y / 2.0)
	add_child(collision)


func _draw() -> void:
	var top := Rect2(-size.x / 2.0, -size.y, size.x, size.y)
	var front := Rect2(-size.x / 2.0, 0.0, size.x, FRONT_HEIGHT)
	draw_rect(top, top_color)
	draw_rect(front, front_color)
	draw_line(Vector2(-size.x / 2.0, 0.0), Vector2(size.x / 2.0, 0.0), INK, 2.0)
	draw_rect(top.merge(front), INK, false, 3.0)
