class_name Sprinkler
extends Hazard
## A floor sprinkler on a fixed cycle: idle for idle_time, a warning wobble
## for warn_time, then it sprays its zone for spray_time and goes idle again.
## The cat flees it while it warns or sprays, but only the spray soaks it, so
## an idle sprinkler can be walked past. The zone (its collision circle) is
## drawn on the floor in every phase, so the player can see its reach.

enum Phase { IDLE, WARN, SPRAY }

const WATER := Color("#6EC1E4")
const WATER_DEEP := Color("#4FA3CC")
const INK := Color("#3B2C35")
## Head spin while spraying and its wobble while warning (radians, per second).
const SPIN_SPEED := 14.0
const WOBBLE_ANGLE := 0.35
const WOBBLE_SPEED := 40.0
## Water jets while spraying: how many, droplets per jet and the arc's height.
const JETS := 4
const JET_DROPS := 9
const JET_ARC := 34.0

@export var idle_time := 2.0
@export var warn_time := 0.5
@export var spray_time := 2.0
## Seconds into the cycle at the start, to put several sprinklers out of step.
@export var start_time := 0.0

var phase := Phase.IDLE

var _cycle_time := 0.0
var _anim_time := 0.0
var _radius := 0.0

@onready var _head: Node2D = $Visual/HeadPivot/Head
@onready var _nozzle: Vector2 = ($Visual/HeadPivot as Node2D).position * ($Visual as Node2D).scale
@onready var _jets: Node2D = $Jets
@onready var _drops: CPUParticles2D = $Drops
@onready var _spray_sound: AudioStreamPlayer2D = $Spray


func _ready() -> void:
	super._ready()
	var circle := ($Shape as CollisionShape2D).shape as CircleShape2D
	if circle == null:
		push_error("Sprinkler '%s' needs a CircleShape2D zone" % get_path())
	else:
		_radius = circle.radius
	_jets.draw.connect(_draw_jets)
	if cycle_time() <= 0.0 or minf(idle_time, minf(warn_time, spray_time)) < 0.0:
		push_error("Sprinkler '%s' needs non-negative times with a positive total" % get_path())
		set_physics_process(false)
		return
	_cycle_time = fposmod(start_time, cycle_time())
	_enter(_phase_at(_cycle_time))


func cycle_time() -> float:
	return idle_time + warn_time + spray_time


func _physics_process(delta: float) -> void:
	_cycle_time = fposmod(_cycle_time + delta, cycle_time())
	var wanted := _phase_at(_cycle_time)
	if wanted != phase:
		_enter(wanted)


func _process(delta: float) -> void:
	_anim_time += delta
	match phase:
		Phase.SPRAY:
			_head.rotation += SPIN_SPEED * delta
			_jets.queue_redraw()
		Phase.WARN:
			_head.rotation = sin(_anim_time * WOBBLE_SPEED) * WOBBLE_ANGLE
			queue_redraw()


func _draw() -> void:
	var fill := 0.12
	var ring := 0.45
	match phase:
		Phase.WARN:
			ring = 0.6 + 0.4 * sin(_anim_time * WOBBLE_SPEED * 0.5)
		Phase.SPRAY:
			fill = 0.35
			ring = 0.9
	draw_circle(Vector2.ZERO, _radius, Color(WATER, fill))
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64, Color(WATER_DEEP, ring), 3.0, true)


## Jets arc from the nozzle to the edge of the zone, turning with the head.
func _draw_jets() -> void:
	if phase != Phase.SPRAY:
		return
	for jet in JETS:
		var end := Vector2.from_angle(_head.rotation + jet * TAU / JETS) * _radius
		for drop in range(1, JET_DROPS + 1):
			var t := float(drop) / JET_DROPS
			var at := _nozzle.lerp(end, t) + Vector2(0.0, -sin(t * PI) * JET_ARC)
			var size := 2.5 + t * 2.0
			_jets.draw_circle(at, size + 1.2, Color(INK, 0.6))
			_jets.draw_circle(at, size, WATER)


func _phase_at(time: float) -> Phase:
	if time >= idle_time + warn_time:
		return Phase.SPRAY
	if time >= idle_time:
		return Phase.WARN
	return Phase.IDLE


func _enter(next: Phase) -> void:
	phase = next
	scary = phase != Phase.IDLE
	_drops.emitting = phase == Phase.SPRAY
	_jets.queue_redraw()
	if phase == Phase.SPRAY:
		_spray_sound.play()
		# A cat already standing in the zone is soaked the moment the spray starts.
		for body in get_overlapping_bodies():
			_on_body_entered(body)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if phase == Phase.SPRAY:
		super._on_body_entered(body)
