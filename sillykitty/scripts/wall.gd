@tool
class_name Wall
extends StaticBody2D
## A garden obstacle: the border fence, a bench or greenery. The origin is the
## bottom-centre of the footprint so walls placed under a y-sorted node sort
## correctly with actors.
## Only the footprint collides; the front face below it is decoration.
## Runs in the editor so levels can be laid out visually.

## How the block is drawn, all garden pieces: a white picket fence (the room
## border), a wooden bench, or greenery (a hedge for long blocks, a row of small
## round trees for compact ones). Every piece stays inside its footprint and
## front strip, so nothing behind it is hidden.
enum Kind { FENCE, BENCH, HEDGE }

const FRONT_HEIGHT := 18.0
const INK := Color("#3B2C35")
const HIGHLIGHT := Color(1.0, 1.0, 1.0, 0.3)
const GRASS_SHADE := Color("#8CC25C")
const FENCE_WOOD := Color("#F4E6C8")
const FENCE_SHADE := Color("#D9C29A")
const BENCH_WOOD := Color("#C98B52")
const BENCH_SHADE := Color("#9C6638")
const BENCH_IRON := Color("#56606B")
const HEDGE := Color("#5E9E4A")
const HEDGE_SHADE := Color("#467A36")
const LEAF_LIGHT := Color("#82C062")
const TRUNK := Color("#8A6446")
const BLOSSOMS: Array[Color] = [Color("#FFFFFF"), Color("#FFC94D"), Color("#F48FA0")]
## Picket spacing along a fence and seat-slat width on a bench.
const PICKET_STEP := 22.0
const SLAT_WIDTH := 12.0
## Blocks at least this many times longer than deep are hedges; shorter ones
## are a row of trees.
const HEDGE_ASPECT := 2.5

@export var size := Vector2(128.0, 64.0):
	set(value):
		size = value
		queue_redraw()
@export var kind := Kind.FENCE:
	set(value):
		kind = value
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
	# Leaf and blossom placement is random but fixed per block, so it never flickers.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(position))
	match kind:
		Kind.FENCE:
			_draw_fence(top, front)
		Kind.BENCH:
			_draw_bench(top, front)
		Kind.HEDGE:
			if maxf(size.x, size.y) >= minf(size.x, size.y) * HEDGE_ASPECT:
				_draw_hedge(top, front, rng)
			else:
				_draw_trees(top, front, rng)


## A strip of longer grass with the fence on it. Along a horizontal border the
## pickets stand up into the room with two rails behind them; along a vertical
## one they are seen from above, a rail with a picket every step.
func _draw_fence(top: Rect2, front: Rect2) -> void:
	draw_rect(top, GRASS_SHADE)
	if top.size.x >= top.size.y:
		var rail_y := front.position.y - 4.0
		for y: float in [rail_y - 10.0, rail_y + 6.0]:
			_draw_box(Rect2(top.position.x, y, top.size.x, 5.0), FENCE_SHADE, 1.0, 2.0)
		var x := top.position.x + PICKET_STEP / 2.0
		while x < top.end.x:
			var picket := PackedVector2Array([Vector2(x - 6.0, front.end.y - 2.0), Vector2(x - 6.0, rail_y - 18.0),
				Vector2(x, rail_y - 25.0), Vector2(x + 6.0, rail_y - 18.0), Vector2(x + 6.0, front.end.y - 2.0)])
			draw_colored_polygon(picket, FENCE_WOOD)
			draw_polyline(picket + PackedVector2Array([picket[0]]), INK, 2.0, true)
			draw_line(Vector2(x - 3.0, rail_y - 16.0), Vector2(x - 3.0, front.end.y - 5.0), HIGHLIGHT, 2.0)
			x += PICKET_STEP
	else:
		var centre := top.get_center().x
		_draw_box(Rect2(centre - 3.0, top.position.y, 6.0, top.size.y), FENCE_SHADE, 2.0, 2.0)
		var y := top.position.y + PICKET_STEP / 2.0
		while y < top.end.y:
			_draw_box(Rect2(centre - 7.0, y - 4.0, 14.0, 8.0), FENCE_WOOD, 3.0, 2.0)
			y += PICKET_STEP


## A wooden garden bench seen from above: the backrest along the back edge,
## iron armrests at both ends and seat slats along its length; the front shows
## the seat edge and the legs.
func _draw_bench(top: Rect2, front: Rect2) -> void:
	var arm := minf(16.0, top.size.x * 0.1)
	var back := top.size.y * 0.3
	for x: float in [top.position.x + arm * 0.5, top.end.x - arm * 1.5]:
		_draw_box(Rect2(x, front.position.y + 4.0, arm, front.size.y - 4.0), BENCH_IRON, 2.0, 2.0)
	var seat := Rect2(top.position.x + arm, top.position.y + back, top.size.x - arm * 2.0, top.size.y - back)
	_draw_box(Rect2(seat.position.x, seat.end.y - 2.0, seat.size.x, 8.0), BENCH_SHADE, 2.0)
	var slats := maxi(1, roundi(seat.size.y / SLAT_WIDTH))
	var slat := seat.size.y / slats
	for i in slats:
		var plank := Rect2(seat.position.x, seat.position.y + slat * i + 1.0, seat.size.x, slat - 2.0)
		_draw_box(plank, BENCH_WOOD, 2.0, 2.0)
		draw_line(plank.position + Vector2(6.0, 3.0), Vector2(plank.end.x - 6.0, plank.position.y + 3.0), HIGHLIGHT, 2.0)
	_draw_box(Rect2(top.position.x + arm, top.position.y, top.size.x - arm * 2.0, back - 3.0), BENCH_SHADE, 3.0)
	for x: float in [top.position.x, top.end.x - arm]:
		_draw_box(Rect2(x, top.position.y, arm, top.size.y), BENCH_IRON, 5.0)


## A trimmed hedge: a dark base along the front, the leafy top inside the
## footprint, light leaf clumps and a few blossoms.
func _draw_hedge(top: Rect2, front: Rect2, rng: RandomNumberGenerator) -> void:
	_draw_box(Rect2(top.position.x, top.end.y - 8.0, top.size.x, front.size.y + 8.0), HEDGE_SHADE, 8.0)
	_draw_box(top, HEDGE, minf(18.0, minf(top.size.x, top.size.y) / 2.0))
	draw_line(top.position + Vector2(10.0, 5.0), Vector2(top.end.x - 10.0, top.position.y + 5.0), HIGHLIGHT, 3.0)
	for i in roundi(top.get_area() / 1400.0):
		var at := Vector2(rng.randf_range(top.position.x + 10.0, top.end.x - 10.0), rng.randf_range(top.position.y + 9.0, top.end.y - 9.0))
		draw_circle(at, rng.randf_range(5.0, 8.0), Color(LEAF_LIGHT, 0.7) if rng.randf() < 0.6 else Color(HEDGE_SHADE, 0.6))
	for i in roundi(top.get_area() / 4000.0):
		var at := Vector2(rng.randf_range(top.position.x + 8.0, top.end.x - 8.0), rng.randf_range(top.position.y + 7.0, top.end.y - 7.0))
		draw_circle(at, 2.5, BLOSSOMS[rng.randi() % BLOSSOMS.size()])


## A row of small round trees, one per footprint-depth of length: the trunk
## shows in the front strip and the crown fills its share of the footprint.
func _draw_trees(top: Rect2, front: Rect2, rng: RandomNumberGenerator) -> void:
	var across := minf(top.size.x, top.size.y)
	var count := maxi(1, roundi(maxf(top.size.x, top.size.y) / across))
	var along_x := top.size.x >= top.size.y
	var step := (top.size.x if along_x else top.size.y) / count
	for i in count:
		var centre := top.position + (Vector2(step * (i + 0.5), across / 2.0) if along_x else Vector2(across / 2.0, step * (i + 0.5)))
		if along_x or i == count - 1:
			_draw_box(Rect2(centre.x - 5.0, front.position.y - 4.0, 10.0, front.size.y + 2.0), TRUNK, 3.0, 2.0)
		var radius := minf(across, step) / 2.0
		draw_circle(centre, radius, INK)
		draw_circle(centre, radius - 2.5, HEDGE)
		draw_circle(centre + Vector2(radius * 0.15, radius * 0.2), radius * 0.6, HEDGE_SHADE)
		draw_circle(centre - Vector2(radius * 0.25, radius * 0.25), radius * 0.45, LEAF_LIGHT)
		for j in 3:
			var at := centre + Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.0, radius * 0.6)
			draw_circle(at, maxf(2.0, radius * 0.12), LEAF_LIGHT if j < 2 else HEDGE_SHADE)
		draw_circle(centre - Vector2(radius * 0.35, radius * 0.4), radius * 0.15, HIGHLIGHT)


## A filled rounded rectangle with an ink outline.
func _draw_box(rect: Rect2, fill: Color, radius: float, border: float = 2.5) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = INK
	box.set_border_width_all(roundi(border))
	box.set_corner_radius_all(roundi(radius))
	box.anti_aliasing = true
	box.draw(get_canvas_item(), rect)
