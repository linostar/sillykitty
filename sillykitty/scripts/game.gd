class_name GameState
extends Node
## Autoload "Game" (scenes/game.tscn): the ordered level list and linear
## progression (title -> furthest level; clear -> next level, fail -> retry, last
## level -> end room -> level 1), the user:// save of the furthest unlocked level
## and the best stars per level, the music and a fade-in after every scene change.
## Levels only report their outcome; every transition happens here, without input.
## Logs save loads, save writes and scene transitions.

## Where the autoload lives. Scripts fetch it through this path instead of the
## global "Game" name, which does not exist yet when test scripts compile.
const AUTOLOAD_PATH := ^"/root/Game"
const LEVEL_PATHS: Array[String] = [
	"res://scenes/levels/level_01.tscn",
	"res://scenes/levels/level_02.tscn",
	"res://scenes/levels/level_03.tscn",
	"res://scenes/levels/level_04.tscn",
	"res://scenes/levels/level_05.tscn",
	"res://scenes/levels/level_06.tscn",
	"res://scenes/levels/level_07.tscn",
	"res://scenes/levels/level_08.tscn",
]
const SAVE_PATH := "user://progress.json"
const FAIL_RETRY_DELAY := 1.6
const CLEAR_ADVANCE_DELAY := 2.5
const END_ROOM_PATH := "res://scenes/end_room.tscn"
## Seconds the end room shows before level 1 loads.
const END_ROOM_TIME := 7.0
const END_TEXT := "You did it! Every kitty is home."
const FADE_TIME := 0.35
## Rooms are drawn at this scale, centred and resting on the bottom of the
## screen. Sprites rise up to ~141 px above their feet (the cat's bubble), so at
## full scale an actor by the top wall would draw off screen and under the HUD;
## the band this frees above the room keeps them visible.
const ROOM_SCALE := 0.87

## Music for the title and end rooms, and for every level.
@export var title_music: AudioStream
@export var level_music: AudioStream

## Tests replace these to run against their own levels and save file.
var level_paths: Array[String] = LEVEL_PATHS.duplicate()
var save_path := SAVE_PATH
## Tests set quiet_errors to assert on expected errors without failing the log check.
var quiet_errors := false
var reported_errors: Array[String] = []

var current_index := 0
## True while the current level was loaded as a retry of a failed attempt.
var retrying := false
var furthest_index := 0
var best_stars: Array[int] = []

var _transitioning := false

@onready var _music: AudioStreamPlayer = $Music
@onready var _curtain: ColorRect = $Fade/Curtain


func _ready() -> void:
	if title_music == null or level_music == null:
		push_error("[Game] title_music and level_music must both be assigned in game.tscn")
	# Applies to every scene's world (not to CanvasLayers such as the HUD) and
	# survives scene changes, so it is set once here.
	get_viewport().canvas_transform = Transform2D(0.0, Vector2(ROOM_SCALE, ROOM_SCALE), 0.0, room_origin())
	_fit_window()
	load_progress()


## Desktop windows are sized in physical pixels, so on a high-density screen
## (a 2x Retina display) the project's window size would show at half size.
## Scales the window by the screen's density, shrunk to fit the usable screen
## area, and centres it. The web build fills its page and is left alone.
func _fit_window() -> void:
	var window := get_window()
	if OS.has_feature("web") or window.mode != Window.MODE_WINDOWED:
		return
	var density := DisplayServer.screen_get_scale(window.current_screen)
	if density <= 1.0:
		return
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	var wanted := Vector2(window.size) * density
	wanted *= minf(1.0, minf(usable.size.x / wanted.x, usable.size.y / wanted.y))
	window.size = Vector2i(wanted)
	window.position = usable.position + Vector2i(Vector2(usable.size - window.size) / 2.0)
	print("[Game] Scaled the window for a %.1fx screen to %s" % [density, window.size])


## Loads the furthest unlocked level.
func start_game() -> void:
	retrying = false
	_go_to(furthest_index)


## Called by the title and end rooms when they open.
func enter_room(room_name: String) -> void:
	print("[Game] Entered the %s" % room_name)
	_play(title_music)


## Screen position of the room's top-left corner: centred horizontally and
## resting on the bottom of the (base-resolution) screen.
func room_origin() -> Vector2:
	var screen := get_viewport().get_visible_rect().size
	return Vector2(screen.x * (1.0 - ROOM_SCALE) / 2.0, screen.y * (1.0 - ROOM_SCALE))


## Total stars earned over all levels and the most there are.
func star_total() -> Vector2i:
	var total := 0
	for stars in best_stars:
		total += stars
	return Vector2i(total, best_stars.size() * 3)


## The music stream currently playing (null if none).
func music_playing() -> AudioStream:
	return _music.stream if _music.playing else null


## The fade curtain's opacity, 0 once a scene change has faded in.
func curtain_alpha() -> float:
	return _curtain.color.a


func level_count() -> int:
	return level_paths.size()


## 1-based position of a level scene in the list, or 0 if it is not listed.
func level_number(path: String) -> int:
	return level_paths.find(path) + 1


## Index to load after level `index` ends: the next level after a clear (level 1
## after the last one), the same level after a fail.
func next_index(index: int, cleared: bool) -> int:
	if not cleared:
		return index
	return (index + 1) % level_paths.size()


## Called by every Level when it is ready; Game takes over its outcome.
func attach_level(level: Level) -> void:
	var index := level_paths.find(level.scene_file_path)
	if index >= 0:
		current_index = index
	level.finished.connect(_on_level_finished)
	_play(level_music)


func save_progress() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_report_error("Could not open save '%s' for writing: %s" % [save_path, error_string(FileAccess.get_open_error())])
		return
	var written := file.store_string(JSON.stringify({"furthest_level": furthest_index, "best_stars": best_stars}))
	file.close()
	if not written:
		_report_error("Could not write save '%s'" % save_path)
		return
	print("[Game] Saved progress to %s: furthest level %d, best stars %s" % [save_path, furthest_index + 1, best_stars])


## Saves are JSON: a JSON instance reports parse errors as return values instead of
## printing engine errors, so a corrupt save is reported exactly once, by us.
func load_progress() -> void:
	_reset_progress()
	if not FileAccess.file_exists(save_path):
		print("[Game] No save at %s; starting fresh" % save_path)
		return
	var text := FileAccess.get_file_as_string(save_path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_discard_save("unreadable (%s)" % error_string(FileAccess.get_open_error()))
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		_discard_save("corrupt (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
		return
	var data: Variant = json.data
	if not (data is Dictionary):
		_discard_save("corrupt (not an object)")
		return
	var saved: Dictionary = data
	var furthest: Variant = saved.get("furthest_level")
	var stars: Variant = saved.get("best_stars")
	if not _is_whole(furthest) or not (stars is Array) or not (stars as Array).all(_is_whole):
		_discard_save("corrupt (bad furthest_level or best_stars)")
		return
	furthest_index = clampi(int(furthest), 0, level_paths.size() - 1)
	var saved_stars: Array = stars
	for i in mini(saved_stars.size(), best_stars.size()):
		best_stars[i] = clampi(int(saved_stars[i]), 0, 3)
	print("[Game] Loaded save from %s: furthest level %d, best stars %s" % [save_path, furthest_index + 1, best_stars])


func _on_level_finished(cleared: bool, stars: int) -> void:
	if _transitioning:
		return
	_transitioning = true
	var index := current_index
	if cleared:
		_record_clear(index, stars)
		await get_tree().create_timer(CLEAR_ADVANCE_DELAY).timeout
		if index == level_paths.size() - 1:
			print("[Game] All %d levels cleared; loading the end room" % level_paths.size())
			_change_scene(END_ROOM_PATH)
			await get_tree().create_timer(END_ROOM_TIME).timeout
	else:
		print("[Game] Level %d failed; retrying" % (index + 1))
		await get_tree().create_timer(FAIL_RETRY_DELAY).timeout
	retrying = not cleared
	_go_to(next_index(index, cleared))


## Clearing the last level sends the player back to level 1 (via the end room),
## so the furthest level then resets to 1 as well: a reload resumes there too.
func _record_clear(index: int, stars: int) -> void:
	best_stars[index] = maxi(best_stars[index], stars)
	furthest_index = 0 if index == level_paths.size() - 1 else maxi(furthest_index, index + 1)
	print("[Game] Level %d cleared with %d star(s)" % [index + 1, stars])
	save_progress()


func _go_to(index: int) -> void:
	current_index = index
	print("[Game] Loading level %d/%d (%s)" % [index + 1, level_paths.size(), level_paths[index]])
	_change_scene(level_paths[index])
	_transitioning = false


## Swaps the current scene and fades it in from the curtain colour.
func _change_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_report_error("Failed to load scene '%s': %s" % [path, error_string(error)])
		return
	_curtain.color.a = 1.0
	create_tween().tween_property(_curtain, "color:a", 0.0, FADE_TIME)


func _play(stream: AudioStream) -> void:
	if stream != null and (_music.stream != stream or not _music.playing):
		_music.stream = stream
		_music.play()


func _reset_progress() -> void:
	furthest_index = 0
	best_stars.clear()
	best_stars.resize(level_paths.size())
	best_stars.fill(0)


func _discard_save(problem: String) -> void:
	_report_error("Save '%s' is %s; replacing it with fresh progress" % [save_path, problem])
	save_progress()


## JSON numbers load as floats; accept whole numbers only.
func _is_whole(value: Variant) -> bool:
	return value is int or (value is float and is_equal_approx(value, roundf(value)))


func _report_error(message: String) -> void:
	reported_errors.append(message)
	if not quiet_errors:
		push_error("[Game] " + message)
