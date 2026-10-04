class_name Turn
extends RefCounted
## Turning round for the side-view animals built from parts (cat, dog). The
## head swings across the body to the new side (mirroring as it passes the
## middle) while the animal hops, and the whole animal mirrors at the top of
## the hop, when its head is already where it belongs. Nothing is ever
## squeezed, so the animal keeps its full width throughout. Display only: the
## owner applies `facing`, `lift`, `head_shift` and `head_mirrored()` to its
## nodes.

const TIME := 0.24
## Hop height in pixels at the top of the turn.
const HOP := 6.0
## The shadow shrinks by this fraction at the top of the hop.
const SHADOW_SHRINK := 0.25
## Sideways speed needed to turn, so an animal walking up or down does not
## hop back and forth on every small wobble.
const MIN_SPEED := 20.0

## +1 facing right, -1 facing left.
var facing := 1.0
## 0..1: height of the hop (multiply by HOP for pixels).
var lift := 0.0
## 0..1: how far the head has swung from its side of the body to the other.
var head_shift := 0.0

var _to := 1.0
var _left := 0.0


func turning() -> bool:
	return _left > 0.0


## Starts a turn towards `wanted` (+1 or -1) unless one is already playing.
func want(wanted: float) -> void:
	if not turning() and wanted != facing:
		_to = wanted
		_left = TIME


## Plays the turn: the head swings over in the first half, the animal mirrors
## at the top of the hop and lands in the second half.
func advance(delta: float) -> void:
	if not turning():
		return
	_left = maxf(0.0, _left - delta)
	var progress := 1.0 - _left / TIME
	# Exactly on the ground once the turn is over (sin(PI) is not quite 0).
	lift = sin(progress * PI) if turning() else 0.0
	if progress < 0.5:
		head_shift = smoothstep(0.0, 0.5, progress)
	else:
		facing = _to
		head_shift = 0.0


## True while the head, swung past the middle, looks the new way.
func head_mirrored() -> bool:
	return head_shift > 0.5


## Faces `wanted` (+1 or -1) at once, with no turn (the animal starts that way).
func face(wanted: float) -> void:
	facing = wanted
	_to = wanted
	stop()


## Ends any turn at once with the animal on the ground (the level ended).
func stop() -> void:
	_left = 0.0
	lift = 0.0
	head_shift = 0.0
