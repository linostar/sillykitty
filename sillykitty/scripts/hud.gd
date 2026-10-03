class_name Hud
extends CanvasLayer
## Level heads-up display: level indicator, countdown, hint, outcome banner and
## star rating. Display only; it never takes input.

const NORMAL_COLOR := Color("#3B2C35")
const WARNING_COLOR := Color("#E8574A")
const STAR_EARNED := Color.WHITE
const STAR_MISSING := Color(0.231, 0.173, 0.208, 0.3)

## Played by the level when its countdown runs out.
@export var time_up_sound: AudioStream

@onready var _level_label: Label = %LevelLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _hint: Label = %Hint
@onready var _banner: Label = %Banner
@onready var _stars: HBoxContainer = %Stars
@onready var _tick: AudioStreamPlayer = %Tick


func _ready() -> void:
	if time_up_sound == null:
		push_error("Hud '%s' has no time_up_sound assigned" % get_path())
	_banner.visible = false
	_stars.visible = false


func set_level(number: int, total: int) -> void:
	_level_label.text = "Level %d/%d" % [number, total] if number > 0 else "Level ?/%d" % total


func set_hint(text: String) -> void:
	_hint.text = text


## Shows whole seconds left, rounded up, as m:ss.
func set_time(seconds_left: float, warning: bool) -> void:
	var whole := ceili(seconds_left)
	_timer_label.text = "%d:%02d" % [floori(whole / 60.0), whole % 60]
	_timer_label.add_theme_color_override("font_color", WARNING_COLOR if warning else NORMAL_COLOR)


func play_tick() -> void:
	_tick.play()


## Pops the banner in; `stars` >= 0 also shows the 3-star rating.
func show_banner(text: String, stars: int = -1) -> void:
	_banner.text = text
	_banner.visible = true
	_banner.pivot_offset = _banner.size / 2.0
	_banner.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stars.visible = stars >= 0
	for i in _stars.get_child_count():
		(_stars.get_child(i) as CanvasItem).modulate = STAR_EARNED if i < stars else STAR_MISSING


func banner_text() -> String:
	return _banner.text if _banner.visible else ""


func timer_color() -> Color:
	return _timer_label.get_theme_color("font_color")
