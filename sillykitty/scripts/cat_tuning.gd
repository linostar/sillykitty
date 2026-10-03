class_name CatTuning
extends Resource
## Every number that shapes the cat's behaviour. The values live only in
## res://data/cat_tuning.tres so the cat can be tuned without touching code.

@export_group("Movement")
@export var walk_speed: float
@export var run_speed: float
@export var acceleration: float
## Speed per pixel of remaining distance when easing in to a stop (higher = later, sharper stop).
@export var arrive_slowdown: float

@export_group("Robot")
## The cat sits once the robot is this close.
@export var stop_distance: float
## Beyond this distance the cat runs instead of walking.
@export var run_distance: float
## The cat ignores a robot farther away than this.
@export var interest_radius: float
@export var chase_weight: float
## How much of the chase score is lost at the edge of interest_radius (0..1).
@export var chase_falloff: float

@export_group("Distractions")
@export var distraction_sense_radius: float
@export var distraction_weight: float
## The cat starts playing once it is this close to a distraction.
@export var engage_distance: float
## Seconds the cat plays with a distraction before losing interest.
@export var engage_time: float
## Seconds a distraction stays boring after the cat played with it.
@export var distraction_cooldown: float

@export_group("Bed")
@export var goal_sense_radius: float
@export var goal_weight: float
@export var arrive_distance: float

@export_group("Flee")
## Score of fleeing a threat; beats every other option.
@export var flee_weight: float
## Seconds the cat keeps running after it last saw a threat in range.
@export var flee_linger: float
@export var hiss_cooldown: float
## Below this real speed a fleeing cat counts as cornered (see give_up_time).
@export var flee_stall_speed: float

@export_group("Nap")
## Seconds of having nothing to do before the cat dozes off (fails the level).
@export var nap_fill_time: float
## Seconds for a full nap meter to drain while the cat is busy.
@export var nap_drain_time: float

@export_group("Brain")
## Score of doing nothing; any option must beat it.
@export var idle_score: float
## Bonus for the current choice so the cat does not flicker between options.
@export var hysteresis: float
@export var meow_cooldown: float
## Seconds without getting closer to a distraction or bed before the cat gives up on it.
@export var give_up_time: float
## Seconds a given-up target is ignored.
@export var give_up_cooldown: float
## Pixels the cat must close in on its target to count as progress.
@export var min_progress: float
