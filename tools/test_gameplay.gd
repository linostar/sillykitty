extends SceneTree
## Headless gameplay tests. Each test builds a small arena (or loads a real
## level), drives the robot through the move_* actions only and asserts on the
## cat's behaviour. Run with --fixed-fps 60 so one frame = one physics tick:
##   "$GODOT" --headless --path sillykitty --fixed-fps 60 --script "$PWD/tools/test_gameplay.gd"
## Prints "test_gameplay: OK" when every test passes; exits 1 otherwise.

const ROBOT_SCENE := preload("res://scenes/robot.tscn")
const CAT_SCENE := preload("res://scenes/cat.tscn")
const YARN_SCENE := preload("res://scenes/yarn.tscn")
const PUDDLE_SCENE := preload("res://scenes/puddle.tscn")
const BED_SCENE := preload("res://scenes/bed.tscn")
const LEVEL_PATH := "res://scenes/levels/level_01.tscn"
const FPS := 60
const AUDIO_RELEASE_MSEC := 500

## Real-time limit for the whole run; a test stuck on an await fails instead of hanging.
const WATCHDOG_MSEC := 120000

var _failures: Array[String] = []
var _passed := 0
var _deadline_msec := 0


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + WATCHDOG_MSEC
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline_msec:
		printerr("test_gameplay: FAILED watchdog: tests did not finish within %d ms" % WATCHDOG_MSEC)
		quit(1)
	return false


func _run() -> void:
	await _test_robot_moves_with_input()
	await _test_cat_chases_nearby_robot()
	await _test_cat_ignores_distant_robot()
	await _test_cat_plays_with_distraction_then_returns()
	await _test_hazard_fails_cat()
	await _test_robot_crosses_hazard_unharmed()
	await _test_cat_recovers_when_distraction_removed()
	await _test_cat_walks_into_nearby_bed()
	await _test_level_restarts_after_fail()
	# The audio thread releases freed sound playbacks in real time, and --fixed-fps
	# frames take almost no real time; quitting too early reports them as leaks.
	var release_deadline := Time.get_ticks_msec() + AUDIO_RELEASE_MSEC
	while Time.get_ticks_msec() < release_deadline:
		await process_frame
	for failure in _failures:
		printerr("test_gameplay: FAIL " + failure)
	if _failures.is_empty():
		print("test_gameplay: OK (%d tests)" % _passed)
		quit(0)
	else:
		printerr("test_gameplay: FAILED %d of %d tests" % [_failures.size(), _failures.size() + _passed])
		quit(1)


func _test_robot_moves_with_input() -> void:
	var arena := _arena(Vector2(200, 300), Vector2(-2000, -2000))
	var bot := arena.get_node("Robot") as Robot
	Input.action_press("move_right")
	await _frames(30)
	Input.action_release("move_right")
	_check(bot.position.x > 300.0, "robot_moves_with_input", "robot x=%.1f, expected > 300" % bot.position.x)
	await _dispose(arena)


func _test_cat_chases_nearby_robot() -> void:
	var arena := _arena(Vector2(500, 300), Vector2(250, 300))
	var cat := arena.get_node("Cat") as Cat
	var bot := arena.get_node("Robot") as Robot
	await _frames(150)
	var distance := cat.position.distance_to(bot.position)
	_check(cat.state == Cat.State.CHASE_ROBOT and distance < 100.0, "cat_chases_nearby_robot",
		"state=%s distance=%.1f" % [Cat.State.keys()[cat.state], distance])
	await _dispose(arena)


func _test_cat_ignores_distant_robot() -> void:
	var arena := _arena(Vector2(900, 300), Vector2(100, 300))
	var cat := arena.get_node("Cat") as Cat
	await _frames(60)
	var moved := cat.position.distance_to(Vector2(100, 300))
	_check(cat.state == Cat.State.IDLE and moved < 5.0, "cat_ignores_distant_robot",
		"state=%s moved=%.1f" % [Cat.State.keys()[cat.state], moved])
	await _dispose(arena)


func _test_cat_plays_with_distraction_then_returns() -> void:
	var arena := _arena(Vector2(300, 300), Vector2(250, 300))
	var cat := arena.get_node("Cat") as Cat
	var yarn := _add(arena, YARN_SCENE, Vector2(250, 360)) as Distraction
	await _frames(60)
	var distance := cat.position.distance_to(yarn.position)
	_check(cat.state == Cat.State.DISTRACTED and distance <= 30.0, "cat_goes_to_distraction",
		"state=%s distance=%.1f" % [Cat.State.keys()[cat.state], distance])
	await _frames(int((cat.tuning.engage_time + 0.5) * FPS))
	_check(cat.state == Cat.State.CHASE_ROBOT and not yarn.is_available(), "cat_returns_after_play",
		"state=%s yarn_available=%s" % [Cat.State.keys()[cat.state], yarn.is_available()])
	await _dispose(arena)


func _test_hazard_fails_cat() -> void:
	var arena := _arena(Vector2(560, 300), Vector2(200, 300))
	var cat := arena.get_node("Cat") as Cat
	_add(arena, PUDDLE_SCENE, Vector2(380, 300))
	var reasons: Array[String] = []
	cat.failed.connect(func(reason: String) -> void: reasons.append(reason))
	# The robot flies straight across the puddle and on; the cat follows into it.
	Input.action_press("move_left")
	await _frames(40)
	Input.action_release("move_left")
	Input.action_press("move_right")
	await _frames(40)
	Input.action_release("move_right")
	await _frames(120)
	_check(cat.state == Cat.State.FAILED and reasons.size() == 1, "hazard_fails_cat",
		"state=%s failed_signals=%d" % [Cat.State.keys()[cat.state], reasons.size()])
	await _dispose(arena)


func _test_robot_crosses_hazard_unharmed() -> void:
	# The cat sits far away and idle; only the robot flies across the puddle.
	var arena := _arena(Vector2(200, 300), Vector2(200, 2000))
	var cat := arena.get_node("Cat") as Cat
	var bot := arena.get_node("Robot") as Robot
	var puddle := _add(arena, PUDDLE_SCENE, Vector2(400, 300)) as Hazard
	var reasons: Array[String] = []
	cat.failed.connect(func(reason: String) -> void: reasons.append(reason))
	var robot_detected := false
	Input.action_press("move_right")
	for i in 90:
		await physics_frame
		robot_detected = robot_detected or puddle.overlaps_body(bot)
	Input.action_release("move_right")
	_check(bot.position.x > 520.0 and not robot_detected and reasons.is_empty(), "robot_crosses_hazard_unharmed",
		"robot x=%.1f detected_by_hazard=%s failed_signals=%d" % [bot.position.x, robot_detected, reasons.size()])
	await _dispose(arena)


func _test_cat_recovers_when_distraction_removed() -> void:
	var arena := _arena(Vector2(300, 300), Vector2(250, 300))
	var cat := arena.get_node("Cat") as Cat
	var yarn := _add(arena, YARN_SCENE, Vector2(250, 360)) as Distraction
	await _frames(20)
	var was_distracted := cat.state == Cat.State.DISTRACTED
	yarn.queue_free()
	await _frames(30)
	_check(was_distracted and cat.state == Cat.State.CHASE_ROBOT, "cat_recovers_when_distraction_removed",
		"was_distracted=%s state=%s" % [was_distracted, Cat.State.keys()[cat.state]])
	await _dispose(arena)


func _test_cat_walks_into_nearby_bed() -> void:
	var arena := _arena(Vector2(420, 300), Vector2(300, 300))
	var cat := arena.get_node("Cat") as Cat
	_add(arena, BED_SCENE, Vector2(380, 300))
	var cleared: Array[bool] = []
	cat.reached_goal.connect(func() -> void: cleared.append(true))
	await _frames(180)
	_check(cat.state == Cat.State.CLEARED and cleared.size() == 1, "cat_walks_into_nearby_bed",
		"state=%s reached_goal_signals=%d" % [Cat.State.keys()[cat.state], cleared.size()])
	await _dispose(arena)


func _test_level_restarts_after_fail() -> void:
	var packed := load(LEVEL_PATH) as PackedScene
	if packed == null:
		_check(false, "level_restarts_after_fail", "cannot load " + LEVEL_PATH)
		return
	var level := packed.instantiate() as Level
	root.add_child(level)
	current_scene = level
	await _frames(10)
	var cat := level.get_node("%Cat") as Cat
	cat.fall_into("test hazard")
	# The plan requires an automatic restart within 2 seconds of failing.
	await _frames(2 * FPS)
	var restarted := current_scene != null and current_scene != level and current_scene.scene_file_path == LEVEL_PATH
	_check(restarted, "level_restarts_after_fail", "current scene was not replaced within 2s")
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await _frames(2)


func _arena(robot_position: Vector2, cat_position: Vector2) -> Node2D:
	var arena := Node2D.new()
	var bot := ROBOT_SCENE.instantiate() as Robot
	bot.position = robot_position
	arena.add_child(bot)
	var cat := CAT_SCENE.instantiate() as Cat
	cat.position = cat_position
	cat.robot = bot
	arena.add_child(cat)
	root.add_child(arena)
	return arena


func _add(arena: Node2D, scene: PackedScene, at: Vector2) -> Node2D:
	var node := scene.instantiate() as Node2D
	node.position = at
	arena.add_child(node)
	return node


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _dispose(arena: Node2D) -> void:
	arena.queue_free()
	await _frames(2)


func _check(condition: bool, test_name: String, detail: String) -> void:
	if condition:
		_passed += 1
		print("test_gameplay: pass " + test_name)
	else:
		_failures.append("%s: %s" % [test_name, detail])
