class_name Hud
extends CanvasLayer
## Level heads-up display: level indicator, countdown, hint, the level intro
## card, the outcome banner with its star rating and confetti. Display only; it
## never takes input.

const NORMAL_COLOR := Color("#3B2C35")
const WARNING_COLOR := Color("#E8574A")
const STAR_EARNED := Color.WHITE
const STAR_MISSING := Color(0.231, 0.173, 0.208, 0.3)
const INTRO_HOLD := 1.4
const INTRO_FADE := 0.5
## Seconds between the stars popping in on the clear banner.
const STAR_STEP := 0.3

## Played by the level when its countdown runs out.
@export var time_up_sound: AudioStream

@onready var _level_label: Label = %LevelLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _hint: Label = %Hint
@onready var _banner: Label = %Banner
@onready var _panel: PanelContainer = %BannerPanel
@onready var _stars: HBoxContainer = %Stars
@onready var _intro: Control = %Intro
@onready var _intro_title: Label = %IntroTitle
@onready var _intro_hint: Label = %IntroHint
@onready var _confetti: CPUParticles2D = %Confetti
@onready var _star_sfx: AudioStreamPlayer = %StarSfx
@onready var _tick: AudioStreamPlayer = %Tick


func _ready() -> void:
	if time_up_sound == null:
		push_error("Hud '%s' has no time_up_sound assigned" % get_path())
	_panel.visible = false
	_intro.visible = false
	# Pop animations scale around the centre, which moves whenever the text does.
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size / 2.0)
	for star in _stars.get_children():
		var rect := star as Control
		rect.resized.connect(func() -> void: rect.pivot_offset = rect.size / 2.0)


func set_level(number: int, total: int) -> void:
	_level_label.text = "Level %d/%d" % [number, total] if number > 0 else "Level ?/%d" % total


func set_hint(text: String) -> void:
	_hint.text = text


## Shows whole seconds left, rounded up, as m:ss.
func set_time(seconds_left: float, warning: bool) -> void:
	var whole := ceili(seconds_left)
	_timer_label.text = "%d:%02d" % [floori(whole / 60.0), whole % 60]
	_timer_label.add_theme_color_override("font_color", WARNING_COLOR if warning else NORMAL_COLOR)


## Ticks and gives the countdown a little pulse.
func play_tick() -> void:
	_tick.play()
	_timer_label.pivot_offset = _timer_label.size * Vector2(1.0, 0.5)
	_timer_label.scale = Vector2(1.3, 1.3)
	create_tween().tween_property(_timer_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Shows "Level N" and the hint in the middle of the screen, then fades them out.
func show_intro(number: int, hint: String) -> void:
	_intro_title.text = "Level %d" % number
	_intro_hint.text = hint
	_intro.visible = true
	_intro.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(INTRO_HOLD)
	tween.tween_property(_intro, "modulate:a", 0.0, INTRO_FADE)
	tween.tween_callback(_intro.hide)


## Pops the banner in; `stars` >= 0 also pops in the 3-star rating one star at a
## time, with a chime per earned star, and throws confetti.
func show_banner(text: String, stars: int = -1) -> void:
	_intro.hide()
	_banner.text = text
	_panel.visible = true
	_panel.scale = Vector2(0.4, 0.4)
	create_tween().tween_property(_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_stars.visible = stars >= 0
	if stars < 0:
		return
	_confetti.restart()
	for i in _stars.get_child_count():
		var star := _stars.get_child(i) as Control
		star.modulate = STAR_EARNED if i < stars else STAR_MISSING
		star.scale = Vector2.ZERO
		var tween := create_tween()
		tween.tween_interval(0.25 + STAR_STEP * i)
		if i < stars:
			tween.tween_callback(_play_star.bind(i))
		tween.tween_property(star, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func intro_shown() -> bool:
	return _intro.visible


func banner_text() -> String:
	return _banner.text if _panel.visible else ""


func timer_color() -> Color:
	return _timer_label.get_theme_color("font_color")


func _play_star(index: int) -> void:
	_star_sfx.pitch_scale = 1.0 + 0.12 * index
	_star_sfx.play()
