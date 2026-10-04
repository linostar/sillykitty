@tool
class_name RoomFloor
extends Node2D
## Draws the garden lawn of a 1280x720 room (also in the editor): mown stripes
## with grass tufts and a few daisies, scattered the same way every time. It
## sits two z levels down, below the floor-level zones of y-sorted props (a
## sprinkler's zone is at -1).

const Z_LEVEL := -2
const SIZE := Vector2(1280.0, 720.0)
const STRIPE_HEIGHT := 48.0
const GRASS := Color("#A9D879")
const GRASS_STRIPE := Color("#9FCF6E")
const TUFT := Color("#86BA58")
const DAISY := Color("#FFFFFF")
const DAISY_HEART := Color("#FFC94D")
const TUFTS := 140
const DAISIES := 26
const SEED := 20261002


func _init() -> void:
	z_index = Z_LEVEL


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), GRASS)
	var y := 0.0
	var row := 0
	while y < SIZE.y:
		if row % 2 == 1:
			draw_rect(Rect2(0.0, y, SIZE.x, STRIPE_HEIGHT), GRASS_STRIPE)
		y += STRIPE_HEIGHT
		row += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in TUFTS:
		var at := Vector2(rng.randf_range(0.0, SIZE.x), rng.randf_range(0.0, SIZE.y))
		for blade: float in [-1.0, 0.0, 1.0]:
			draw_line(at, at + Vector2(blade * 4.0, -7.0 + absf(blade) * 2.0), TUFT, 2.0, true)
	for i in DAISIES:
		var at := Vector2(rng.randf_range(0.0, SIZE.x), rng.randf_range(0.0, SIZE.y))
		for petal in 5:
			draw_circle(at + Vector2.from_angle(petal * TAU / 5.0) * 3.0, 2.2, DAISY)
		draw_circle(at, 1.8, DAISY_HEART)
