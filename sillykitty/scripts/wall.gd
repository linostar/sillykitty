@tool
class_name Wall
extends StaticBody2D
## Room wall or furniture block. The origin is the bottom-centre of the
## footprint so walls placed under a y-sorted node sort correctly with actors.
## Only the footprint collides; the front face below it is decoration.
## Runs in the editor so levels can be laid out visually.

## How the block is drawn: plain room wall, sofa (backrest, armrests, seat
## cushions) or wooden cabinet (planked top, drawers with knobs).
enum Kind { WALL, SOFA, CABINET }

const FRONT_HEIGHT := 18.0
const INK := Color("#3B2C35")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.3)
## Roughly how wide one seat cushion or drawer is.
const CUSHION_WIDTH := 90.0
const DRAWER_WIDTH := 110.0
const PLANK_WIDTH := 16.0

@export var size := Vector2(128.0, 64.0):
	set(value):
		size = value
		queue_redraw()
@export var kind := Kind.WALL:
	set(value):
		kind = value
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
	match kind:
		Kind.SOFA:
			_draw_sofa(top, front)
		Kind.CABINET:
			_draw_cabinet(top, front)
	draw_line(Vector2(-size.x / 2.0, 0.0), Vector2(size.x / 2.0, 0.0), INK, 2.0)
	draw_rect(top.merge(front), INK, false, 3.0)


## Seen from above: the backrest along the back edge, an armrest at each end and
## the seat cushions between them; the front shows the armrest and seat fronts.
func _draw_sofa(top: Rect2, front: Rect2) -> void:
	var shade := top_color.darkened(0.12)
	var arm := minf(26.0, top.size.x * 0.14)
	var back := top.size.y * 0.32
	_draw_box(Rect2(top.position, Vector2(top.size.x, back)), shade, 8.0)
	draw_line(top.position + Vector2(10.0, 5.0), top.position + Vector2(top.size.x - 10.0, 5.0), HIGHLIGHT, 3.0)
	for x: float in [top.position.x, top.end.x - arm]:
		_draw_box(Rect2(x, top.position.y, arm, top.size.y), shade, 8.0)
		_draw_box(Rect2(x, front.position.y, arm, front.size.y), front_color.darkened(0.1), 4.0)
	var seat := Rect2(top.position.x + arm, top.position.y + back, top.size.x - arm * 2.0, top.size.y - back)
	var count := maxi(1, roundi(seat.size.x / CUSHION_WIDTH))
	var width := seat.size.x / count
	for i in count:
		var cushion := Rect2(seat.position.x + width * i + 2.0, seat.position.y + 2.0, width - 4.0, seat.size.y - 4.0)
		_draw_box(cushion, top_color.lightened(0.08), 7.0)
		draw_line(cushion.position + Vector2(8.0, 5.0), cushion.position + Vector2(cushion.size.x - 8.0, 5.0), HIGHLIGHT, 2.0)
		if i > 0:
			var x := seat.position.x + width * i
			draw_line(Vector2(x, front.position.y), Vector2(x, front.end.y), INK, 2.0)


## A planked wooden top (planks along the long side) and a row of drawers with
## knobs on the front.
func _draw_cabinet(top: Rect2, front: Rect2) -> void:
	var seam := Color(front_color, 0.5)
	var along_x := top.size.x >= top.size.y
	var across := top.size.y if along_x else top.size.x
	var planks := maxi(1, roundi(across / PLANK_WIDTH))
	var length := top.size.x if along_x else top.size.y
	for i in planks:
		var start := across * i / planks
		var end := across * (i + 1) / planks
		# Each plank has a butt joint, staggered from its neighbours.
		var joint := fposmod(0.3 + 0.37 * i, 1.0) * length
		if along_x:
			if i > 0:
				draw_line(Vector2(top.position.x, top.position.y + start), Vector2(top.end.x, top.position.y + start), seam, 2.0)
			draw_line(Vector2(top.position.x + joint, top.position.y + start), Vector2(top.position.x + joint, top.position.y + end), seam, 2.0)
		else:
			if i > 0:
				draw_line(Vector2(top.position.x + start, top.position.y), Vector2(top.position.x + start, top.end.y), seam, 2.0)
			draw_line(Vector2(top.position.x + start, top.position.y + joint), Vector2(top.position.x + end, top.position.y + joint), seam, 2.0)
	draw_line(top.position + Vector2(6.0, 4.0), Vector2(top.end.x - 6.0, top.position.y + 4.0), HIGHLIGHT, 3.0)
	var count := maxi(1, roundi(front.size.x / DRAWER_WIDTH))
	var width := front.size.x / count
	for i in count:
		var drawer := Rect2(front.position.x + width * i + 4.0, front.position.y + 3.0, width - 8.0, front.size.y - 6.0)
		_draw_box(drawer, front_color.lightened(0.12), 3.0, 2.0)
		draw_circle(drawer.get_center(), 2.5, INK)


## A filled rounded rectangle with an ink outline.
func _draw_box(rect: Rect2, fill: Color, radius: float, border: float = 2.5) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = INK
	box.set_border_width_all(roundi(border))
	box.set_corner_radius_all(roundi(radius))
	box.anti_aliasing = true
	box.draw(get_canvas_item(), rect)
