@tool
class_name RoomFloor
extends Node2D
## Draws the wooden floor boards of a 1280x720 room (also in the editor). It
## sits two z levels down, below the floor-level zones of y-sorted props (a
## sprinkler's zone is at -1).

const Z_LEVEL := -2

const SIZE := Vector2(1280.0, 720.0)
const BOARD_HEIGHT := 48.0
const BOARD_LENGTH := 256.0
const FLOOR_COLOR := Color("#F6E7CB")
const LINE_COLOR := Color("#E8D3AE")


func _init() -> void:
	z_index = Z_LEVEL


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), FLOOR_COLOR)
	var row := 0
	var y := 0.0
	while y < SIZE.y:
		draw_line(Vector2(0.0, y), Vector2(SIZE.x, y), LINE_COLOR, 2.0)
		var x := fmod(row * BOARD_LENGTH * 0.5, BOARD_LENGTH)
		while x < SIZE.x:
			draw_line(Vector2(x, y), Vector2(x, y + BOARD_HEIGHT), LINE_COLOR, 2.0)
			x += BOARD_LENGTH
		y += BOARD_HEIGHT
		row += 1
