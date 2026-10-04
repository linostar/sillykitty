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
const VACUUM_SCENE := preload("res://scenes/vacuum.tscn")
const DOG_SCENE := preload("res://scenes/dog.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const FPS := 60
const AUDIO_RELEASE_MSEC := 500

## Real-time limit for the whole run; a test stuck on an await fails instead of hanging.
const WATCHDOG_MSEC := 120000
## Frames before/after the restart deadline at which "not yet" / "already" are asserted.
const RESTART_MARGIN_FRAMES := 12
const TEST_SAVE_PATH := "user://test_progress.json"

## One scripted solution per level (index = level number - 1), flown only through
## the move_* actions in 8 directions, like a keyboard: Vector2 = fly to that
## point, Vector3 = fly to (x, y) but turn back for the cat whenever it is more
## than z px behind (INF: never), float = hover for that many seconds. Like a
## player, the route also turns back whenever the cat has lost track of the robot.
## Their clear times set the levels' time limits (see _test_level_routes for the rules).
const LEVEL_ROUTES: Array[Array] = [
	[Vector2(380, 470), Vector2(500, 270), Vector2(780, 260), Vector2(920, 380), Vector2(1180, 470)],
	[Vector2(190, 430), Vector2(190, 170), Vector3(480, 190, 400), 1.5, Vector2(900, 240), Vector2(1200, 190)],
	[Vector2(300, 470), Vector3(430, 470, 200), Vector3(440, 300, 150), Vector3(560, 260, 150), Vector3(690, 300, 150),
		Vector3(690, 420, 150), Vector3(820, 470, 150), Vector3(950, 420, 150), Vector3(950, 300, 150),
		Vector3(1080, 250, 150), Vector2(1200, 220)],
	[Vector2(260, 520), Vector2(640, 580), Vector2(1000, 520), Vector2(1200, 390)],
	[Vector2(700, 140), Vector2(1130, 130), Vector2(1150, 330), Vector2(900, 350), Vector2(200, 350), Vector2(140, 560),
		Vector2(500, 540), Vector2(900, 520), Vector2(1190, 580)],
	[Vector2(380, 420), Vector3(640, 130, 400), Vector2(860, 200), Vector2(1200, 300)],
	[Vector2(450, 430), 3.2, Vector2(650, 540), Vector2(820, 570), Vector2(1000, 550), Vector2(1200, 380)],
	[Vector3(190, 410, INF), Vector3(450, 410, INF), Vector3(760, 430, INF), Vector3(1050, 430, INF),
		Vector3(1200, 150, INF)],
]
## Without a Vector3 pace, the route turns back for a cat more than this far behind.
const ROUTE_PACE := 300.0
const ROUTE_REACH := 14.0
## A route step that has not reached its point by then is abandoned (the level then fails its check).
const ROUTE_STEP_TIMEOUT := 20.0
## Seconds the cat gets to walk into its bed after the route ends.
const ROUTE_SETTLE := 15.0
## Level 5 played by racing ahead without ever waiting for the cat: the cat
## loses sight of the robot behind the long walls and dozes off.
const LEVEL_05_RACE: Array = [Vector3(1130, 170, INF), Vector3(1150, 340, INF), Vector3(200, 350, INF),
	Vector3(150, 600, INF), 10.0]
## The mechanics each level must have and the one it introduces (criterion 24).
const LEVEL_MECHANICS: Array[Array] = [
	["puddle"], ["yarn"], ["puddle"], ["vacuum"], ["puddle", "yarn"], ["dog"],
	["vacuum", "puddle", "yarn"], ["dog", "vacuum", "puddle"],
]
const INTRODUCED_AT: Dictionary[String, int] = {"puddle": 1, "yarn": 2, "vacuum": 4, "dog": 6}

var _failures: Array[String] = []
var _passed := 0
var _deadline_msec := 0
var _real_save_path := ""
## The "Game" autoload; this script compiles before autoloads exist, so it is fetched at start.
var _game: GameState


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + WATCHDOG_MSEC
	_game = root.get_node_or_null("Game") as GameState
	if _game == null:
		printerr("test_gameplay: FAILED: Game autoload not found")
		quit(1)
		return
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline_msec:
		printerr("test_gameplay: FAILED watchdog: tests did not finish within %d ms" % WATCHDOG_MSEC)
		quit(1)
	return false


func _run() -> void:
	# Never touch the player's real save.
	_real_save_path = _game.save_path
	_game.save_path = TEST_SAVE_PATH
	_delete_test_save()
	await _test_robot_moves_with_input()
	await _test_cat_chases_nearby_robot()
	await _test_cat_turns_round_with_a_hop()
	await _test_dog_turns_round_like_the_cat()
	await _test_fail_animations_do_not_spin()
	await _test_ears_settle_after_fleeing()
	await _test_cat_does_not_turn_on_small_sideways_moves()
	await _test_cat_lands_when_level_ends_mid_turn()
	await _test_cat_ignores_distant_robot()
	await _test_cat_plays_with_distraction_then_returns()
	await _test_hazard_fails_cat()
	await _test_robot_crosses_hazard_unharmed()
	await _test_cat_recovers_when_distraction_removed()
	await _test_cat_ignores_target_behind_wall()
	await _test_cat_ignores_robot_behind_wall()
	await _test_cat_gives_up_unreachable_target()
	await _test_cat_walks_into_nearby_bed()
	_test_thought_bubble_icons()
	await _test_vacuum_patrols_waypoints()
	await _test_cat_flees_vacuum()
	await _test_threat_interrupts_play()
	await _test_threat_behind_wall_is_ignored()
	await _test_cat_slides_along_wall_when_fleeing()
	await _test_cornered_cat_gives_up_fleeing()
	await _test_threat_touch_fails_level()
	await _test_dog_sleeps_wakes_chases_and_sleeps_again()
	await _test_dog_cut_off_from_home_still_sleeps()
	await _test_dog_ignores_cat_once_level_is_over()
	await _test_robot_unharmed_by_dog()
	await _test_nap_waits_for_first_movement_then_fails()
	await _test_nap_drains_while_busy()
	await _test_level_hints_fit_hud()
	_test_stars_for_time_left()
	_test_warning_seconds()
	_test_fit_window_rect()
	_test_next_index()
	_test_save_round_trip()
	_test_missing_save_starts_fresh()
	_test_corrupt_save_is_replaced()
	await _test_clock_starts_on_first_movement()
	await _test_time_up_fails_level()
	await _test_fail_retries_same_level()
	await _test_intro_card_not_on_retry()
	await _test_splash_opens_the_game()
	await _test_title_room_starts_on_movement()
	await _test_clear_advances_to_next_level()
	await _test_level_routes()
	await _test_level_beelines_fail()
	await _test_level_05_racing_ahead_naps()
	_game.save_path = _real_save_path
	# The audio thread releases freed sound playbacks in real time, and --fixed-fps
	# frames take almost no real time; quitting too early reports them as leaks.
	# The Game autoload's music keeps playing, so stop it and drop its stream first.
	var music := _game.get_node("Music") as AudioStreamPlayer
	music.stop()
	music.stream = null
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


## Turning round: the head swings across the body while the cat hops, and the
## cat mirrors at the top of the hop at full width (never squeezed), ending
## turned, on the floor, with its head and shadow back in place.
func _test_cat_turns_round_with_a_hop() -> void:
	var arena := _arena(Vector2(500, 300), Vector2(300, 300))
	var cat := arena.get_node("Cat") as Cat
	var bot := arena.get_node("Robot") as Robot
	var visual := cat.get_node("Visual") as Node2D
	var head := cat.get_node("Visual/Head") as Node2D
	var shadow := cat.get_node("Shadow") as Node2D
	var bubble := cat.get_node("ThoughtBubble") as ThoughtBubble
	await _frames(60)
	var facing_right := is_equal_approx(visual.scale.x, 1.0)
	var bubble_before := _bubble_over_head(bubble, head)
	var shadow_rest := shadow.scale
	var head_rest := head.position
	bot.position = Vector2(cat.position.x - 150.0, 300)
	var turn := await _watch_turn(visual, head, shadow, 60)
	var bubble_after := _bubble_over_head(bubble, head)
	var turned := is_equal_approx(visual.scale.x, -1.0) and visual.position.y == 0.0 \
		and shadow.scale.is_equal_approx(shadow_rest) and head.position.is_equal_approx(head_rest) and head.scale.x == 1.0
	_check(facing_right and turned and turn.hop > Turn.HOP * 0.8 and turn.narrowest == 1.0 and turn.head_swung
		and turn.head_flipped and turn.smallest_shadow < 1.0 - Turn.SHADOW_SHRINK * 0.8 and bubble_before and bubble_after,
		"cat_turns_round_with_a_hop", "started facing right=%s, ended turned=%s (scale.x=%.2f), %s, bubble trail over the head before=%s after=%s"
		% [facing_right, turned, visual.scale.x, turn, bubble_before, bubble_after])
	await _dispose(arena)


## True when the thought bubble's trail ends right above the cat's head.
func _bubble_over_head(bubble: ThoughtBubble, head: Node2D) -> bool:
	var tip := bubble.trail_tip()
	return absf(tip.x - head.global_position.x) <= 6.0 and tip.y < head.global_position.y - 40.0


## The dog turns round the same way as the cat: on waking (while it jumps
## with its bark) and again when the cat runs past it, with the turn's own hop.
func _test_dog_turns_round_like_the_cat() -> void:
	var arena := _arena(Vector2(400, 2000), Vector2(480, 300))
	var cat := arena.get_node("Cat") as Cat
	var dog := _add_dog(arena, Vector2(600, 300), cat)
	var visual := dog.get_node("Visual") as Node2D
	var head := dog.get_node("Visual/Head") as Node2D
	var shadow := dog.get_node("Shadow") as Node2D
	var facing_right := is_equal_approx(visual.scale.x, 1.0)
	var waking := await _watch_turn(visual, head, shadow, 30)
	var woke_left := dog.state == Dog.State.CHASE and is_equal_approx(visual.scale.x, -1.0)
	cat.position = dog.position + Vector2(150.0, 0.0)
	var again := await _watch_turn(visual, head, shadow, 30)
	var turned_back := dog.state == Dog.State.CHASE and is_equal_approx(visual.scale.x, 1.0)
	_check(facing_right and woke_left and turned_back and waking.hop > 20.0 and waking.narrowest == 1.0
		and again.hop > Turn.HOP * 0.8 and again.hop < Turn.HOP + 1.0 and again.narrowest == 1.0
		and again.head_swung and again.head_flipped and again.smallest_shadow < 1.0 - Turn.SHADOW_SHRINK * 0.8,
		"dog_turns_round_like_the_cat", "started facing right=%s, woke facing left=%s %s, turned back=%s %s"
		% [facing_right, woke_left, waking, turned_back, again])
	await _dispose(arena)


## Watches an animal for `frames` physics frames: its highest hop, narrowest
## width, whether its head swung to the other side (and mirrored on the way)
## and its smallest shadow
## (relative to the shadow's scale at the start).
func _watch_turn(visual: Node2D, head: Node2D, shadow: Node2D, frames: int) -> Dictionary:
	var shadow_rest := shadow.scale.x
	var watched := {"hop": 0.0, "narrowest": INF, "head_swung": false, "head_flipped": false, "smallest_shadow": INF}
	for i in frames:
		await physics_frame
		watched.hop = maxf(watched.hop, -visual.position.y)
		watched.narrowest = minf(watched.narrowest, absf(visual.scale.x))
		watched.head_swung = watched.head_swung or head.position.x < 0.0
		watched.head_flipped = watched.head_flipped or head.scale.x < 0.0
		watched.smallest_shadow = minf(watched.smallest_shadow, shadow.scale.x / shadow_rest)
	return watched


## Neither fail animation spins the cat (it shakes off water or trembles
## instead), the cat never gets narrower than 90% of its width, its ears end
## pinned back (even when it was fleeing), and it is settled on the floor
## before the level retries.
func _test_fail_animations_do_not_spin() -> void:
	var results: Array[String] = []
	var ok := true
	# Soaked; scared; scared while fleeing (the usual way to be caught); scared
	# just after the cat stopped fleeing, while its ears are still coming back up.
	for case in 4:
		var wet := case == 0
		var arena := _arena(Vector2(900, 2000), Vector2(300, 300))
		var cat := arena.get_node("Cat") as Cat
		var visual := cat.get_node("Visual") as Node2D
		var ears: Array[Node2D] = [cat.get_node("Visual/Head/EarBack"), cat.get_node("Visual/Head/EarFront")]
		var ear_rest: Array[float] = [ears[0].rotation, ears[1].rotation]
		await _frames(5)
		var fleeing := false
		if case >= 2:
			var vacuum := _add_vacuum(arena, Vector2(420, 300), PackedVector2Array([Vector2(420, 300)]))
			for i in 30:
				await physics_frame
				fleeing = cat.state == Cat.State.FLEE
				if fleeing:
					break
			if case == 3:
				vacuum.queue_free()
				for i in 2 * FPS:
					await physics_frame
					if cat.state != Cat.State.FLEE:
						break
				fleeing = fleeing and cat.state != Cat.State.FLEE
				await _frames(3)
		cat.fall_into("test", null, wet)
		var turn := 0.0
		var narrowest := INF
		var leapt := 0.0
		for i in int(GameState.FAIL_RETRY_DELAY * FPS) - 6:
			await physics_frame
			turn = maxf(turn, absf(visual.rotation))
			narrowest = minf(narrowest, absf(visual.scale.x))
			leapt = maxf(leapt, -visual.position.y)
		var settled := is_zero_approx(visual.rotation) and visual.position.is_zero_approx()
		var pinned := is_equal_approx(ears[0].rotation, ear_rest[0] * 3.0) and is_equal_approx(ears[1].rotation, ear_rest[1] * 3.0)
		ok = ok and turn <= Cat.SHAKE_ANGLE + 0.001 and narrowest >= 0.9 and leapt > 40.0 and settled and pinned \
			and (fleeing or case < 2)
		results.append("case %d (wet=%s, fled first=%s): max rotation %.2f, narrowest %.2f, leap %.0f, settled %s, ears pinned %s"
			% [case, wet, fleeing, turn, narrowest, leapt, settled, pinned])
		await _dispose(arena)
	_check(ok, "fail_animations_do_not_spin", "; ".join(results))


## After fleeing, both ears come back to rest even when a twitch falls due at
## once (its timer is frozen while the cat flees), and a level that ends while
## they are coming back up (here a nap) leaves them at rest too.
func _test_ears_settle_after_fleeing() -> void:
	var results: Array[String] = []
	var ok := true
	for ends_in_nap: bool in [false, true]:
		var arena := _arena(Vector2(900, 2000), Vector2(300, 300))
		var cat := arena.get_node("Cat") as Cat
		var bot := arena.get_node("Robot") as Robot
		var ears: Array[Node2D] = [cat.get_node("Visual/Head/EarBack"), cat.get_node("Visual/Head/EarFront")]
		var ear_rest: Array[float] = [ears[0].rotation, ears[1].rotation]
		var vacuum := _add_vacuum(arena, Vector2(420, 300), PackedVector2Array([Vector2(420, 300)]))
		for i in 30:
			await physics_frame
			if cat.state == Cat.State.FLEE:
				break
		var fled := cat.state == Cat.State.FLEE
		# Test hook: the twitch timer is private; make a twitch due the moment fleeing
		# ends. set() ignores unknown names, so check it took (a rename fails here).
		cat.set("_ear_twitch_in", 0.0)
		var hooked := "_ear_twitch_in" in cat and is_zero_approx(cat.get("_ear_twitch_in"))
		vacuum.queue_free()
		for i in 2 * FPS:
			await physics_frame
			if cat.state != Cat.State.FLEE:
				break
		var stopped := cat.state != Cat.State.FLEE and not cat.is_over()
		if ends_in_nap:
			await _frames(3)
			bot.has_moved = true
			cat.nap = 0.999
			await _frames(2)
		await _frames(FPS)
		var at_rest := is_equal_approx(ears[0].rotation, ear_rest[0]) and is_equal_approx(ears[1].rotation, ear_rest[1])
		ok = ok and hooked and fled and stopped and at_rest and (cat.state == Cat.State.NAP) == ends_in_nap
		results.append("nap=%s: twitch hook=%s fled=%s stopped=%s state=%s ears %.2f, %.2f (rest %.2f, %.2f)" % [ends_in_nap, hooked, fled, stopped,
			Cat.State.keys()[cat.state], ears[0].rotation, ears[1].rotation, ear_rest[0], ear_rest[1]])
		await _dispose(arena)
	_check(ok, "ears_settle_after_fleeing", "; ".join(results))


## A cat walking almost straight down (sideways speed under Turn.MIN_SPEED)
## towards a robot only slightly to its left (under TURN_MIN_OFFSET) keeps facing
## right instead of hopping round.
func _test_cat_does_not_turn_on_small_sideways_moves() -> void:
	var arena := _arena(Vector2(288, 550), Vector2(300, 300))
	var cat := arena.get_node("Cat") as Cat
	var visual := cat.get_node("Visual") as Node2D
	var highest := 0.0
	var lowest_scale := INF
	for i in 120:
		await physics_frame
		highest = maxf(highest, -visual.position.y)
		lowest_scale = minf(lowest_scale, visual.scale.x)
	var moved := cat.position.distance_to(Vector2(300, 300))
	_check(cat.state == Cat.State.CHASE_ROBOT and moved > 100.0 and is_zero_approx(highest) and is_equal_approx(lowest_scale, 1.0),
		"cat_does_not_turn_on_small_sideways_moves", "state=%s moved=%.1f hop=%.1f lowest scale.x=%.2f"
		% [Cat.State.keys()[cat.state], moved, highest, lowest_scale])
	await _dispose(arena)


## A level that ends in the middle of a turn-around hop puts the cat (and its
## shadow) back on the floor.
func _test_cat_lands_when_level_ends_mid_turn() -> void:
	var arena := _arena(Vector2(500, 300), Vector2(300, 300))
	var cat := arena.get_node("Cat") as Cat
	var bot := arena.get_node("Robot") as Robot
	var visual := cat.get_node("Visual") as Node2D
	var shadow := cat.get_node("Shadow") as Node2D
	await _frames(60)
	var shadow_rest := shadow.scale
	bot.position = Vector2(cat.position.x - 150.0, 300)
	var head := cat.get_node("Visual/Head") as Node2D
	var lifted := 0.0
	for i in 30:
		await physics_frame
		lifted = -visual.position.y
		if head.scale.x < 0.0:
			break
	cat.time_up("test", null)
	await _frames(30)
	var head_home := is_equal_approx(absf(head.position.x), 30.0) and head.scale.x == 1.0
	_check(lifted > Turn.HOP * 0.5 and is_zero_approx(visual.position.y) and shadow.scale.is_equal_approx(shadow_rest)
		and head_home, "cat_lands_when_level_ends_mid_turn",
		"lifted=%.1f when the level ended, then y=%.1f shadow=%s (rest %s) head=%s scale.x=%.0f"
		% [lifted, visual.position.y, shadow.scale, shadow_rest, head.position, head.scale.x])
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
	cat.failed.connect(func(reason: String, _sound: AudioStream) -> void: reasons.append(reason))
	# The robot darts left over the puddle and back; the cat, following it, walks into the water.
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
	cat.failed.connect(func(reason: String, _sound: AudioStream) -> void: reasons.append(reason))
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


func _test_cat_ignores_target_behind_wall() -> void:
	# Without the wall the yarn (120 px) would beat the robot (150 px); the wall hides it.
	var arena := _arena(Vector2(250, 150), Vector2(250, 300))
	var cat := arena.get_node("Cat") as Cat
	_add_wall(arena, Vector2(250, 360), Vector2(300, 20))
	_add(arena, YARN_SCENE, Vector2(250, 420))
	await _frames(60)
	_check(cat.state == Cat.State.CHASE_ROBOT, "cat_ignores_target_behind_wall",
		"state=%s" % Cat.State.keys()[cat.state])
	await _dispose(arena)


func _test_cat_ignores_robot_behind_wall() -> void:
	# The robot is well inside the interest radius, but a wall hides it.
	var arena := _arena(Vector2(250, 120), Vector2(250, 300))
	var cat := arena.get_node("Cat") as Cat
	_add_wall(arena, Vector2(250, 220), Vector2(400, 20))
	await _frames(60)
	var moved := cat.position.distance_to(Vector2(250, 300))
	_check(cat.state == Cat.State.IDLE and moved < 5.0, "cat_ignores_robot_behind_wall",
		"state=%s moved=%.1f" % [Cat.State.keys()[cat.state], moved])
	await _dispose(arena)


func _test_cat_gives_up_unreachable_target() -> void:
	# A 10 px gap: the line of sight passes, the cat (18 px collision radius) cannot.
	var arena := _arena(Vector2(250, 150), Vector2(250, 300))
	var cat := arena.get_node("Cat") as Cat
	_add_wall(arena, Vector2(172.5, 360), Vector2(145, 20))
	_add_wall(arena, Vector2(327.5, 360), Vector2(145, 20))
	_add(arena, YARN_SCENE, Vector2(250, 420))
	await _frames(FPS)
	var was_stuck := cat.state == Cat.State.DISTRACTED and cat.position.y < 345.0
	await _frames(int((cat.tuning.give_up_time + 1.0) * FPS))
	_check(was_stuck and cat.state == Cat.State.CHASE_ROBOT, "cat_gives_up_unreachable_target",
		"was_stuck=%s state=%s" % [was_stuck, Cat.State.keys()[cat.state]])
	await _dispose(arena)


func _test_thought_bubble_icons() -> void:
	var bubble := (CAT_SCENE.instantiate() as Cat).get_node("ThoughtBubble") as ThoughtBubble
	var shown: Array[Cat.State] = [Cat.State.IDLE, Cat.State.CHASE_ROBOT, Cat.State.DISTRACTED, Cat.State.GO_TO_BED,
		Cat.State.FLEE, Cat.State.NAP]
	var icons: Array[Texture2D] = []
	for state in shown:
		var icon := bubble.icon_for(state)
		if icon != null and not icons.has(icon):
			icons.append(icon)
	var hidden := bubble.icon_for(Cat.State.FAILED) == null and bubble.icon_for(Cat.State.CLEARED) == null
	_check(icons.size() == shown.size() and hidden, "thought_bubble_icons",
		"distinct icons=%d of %d, hidden on fail/clear=%s" % [icons.size(), shown.size(), hidden])
	bubble.get_parent().free()


func _test_vacuum_patrols_waypoints() -> void:
	# The idle cat is far away; the robot hovers on the patrol line.
	var arena := _arena(Vector2(300, 200), Vector2(2000, 2000))
	var cat := arena.get_node("Cat") as Cat
	var bot := arena.get_node("Robot") as Robot
	var waypoints := PackedVector2Array([Vector2(400, 200), Vector2(400, 400), Vector2(200, 200)])
	var vacuum := _add_vacuum(arena, Vector2(200, 200), waypoints)
	var closest: Array[float] = [INF, INF, INF]
	var robot_detected := false
	var lap := (200.0 + 200.0 + Vector2(200, 200).length()) / vacuum.speed
	for i in int((lap + 0.5) * FPS):
		await physics_frame
		for w in waypoints.size():
			closest[w] = minf(closest[w], vacuum.position.distance_to(waypoints[w]))
		robot_detected = robot_detected or vacuum.overlaps_body(bot)
	var visited := closest.all(func(d: float) -> bool: return d < 1.0)
	var moving_on := vacuum.position.distance_to(Vector2(200, 200)) > 10.0
	_check(visited and moving_on and not robot_detected and not cat.is_over(), "vacuum_patrols_waypoints",
		"closest=%s moving_on=%s robot_detected=%s cat=%s" % [closest, moving_on, robot_detected, Cat.State.keys()[cat.state]])
	await _dispose(arena)


func _test_cat_flees_vacuum() -> void:
	var arena := _arena(Vector2(300, 300), Vector2(260, 300))
	var cat := arena.get_node("Cat") as Cat
	await _frames(10)
	var was_chasing := cat.state == Cat.State.CHASE_ROBOT
	var vacuum := _add_vacuum(arena, Vector2(140, 300), PackedVector2Array([Vector2(1000, 300)]))
	await _frames(5)
	var fled := cat.state == Cat.State.FLEE
	var bubble := cat.get_node("ThoughtBubble") as ThoughtBubble
	var flee_icon := bubble.shown_icon() == bubble.flee_icon
	var start_gap := cat.position.distance_to(vacuum.position)
	await _frames(30)
	var gap_grew := cat.position.distance_to(vacuum.position) > start_gap
	_check(was_chasing and fled and flee_icon and gap_grew and not cat.is_over(), "cat_flees_vacuum",
		"was_chasing=%s fled=%s flee_icon=%s gap_grew=%s state=%s" % [was_chasing, fled, flee_icon, gap_grew,
		Cat.State.keys()[cat.state]])
	await _dispose(arena)


func _test_threat_interrupts_play() -> void:
	var arena := _arena(Vector2(300, 300), Vector2(250, 300))
	var cat := arena.get_node("Cat") as Cat
	var yarn := _add(arena, YARN_SCENE, Vector2(250, 360)) as Distraction
	await _frames(60)
	var playing := cat.state == Cat.State.DISTRACTED and cat.position.distance_to(yarn.position) <= cat.tuning.engage_distance
	_add_vacuum(arena, Vector2(250, 480), PackedVector2Array([Vector2(250, 100)]))
	await _frames(3)
	_check(playing and cat.state == Cat.State.FLEE and not yarn.is_available(), "threat_interrupts_play",
		"playing=%s state=%s yarn_available=%s" % [playing, Cat.State.keys()[cat.state], yarn.is_available()])
	await _dispose(arena)


func _test_threat_behind_wall_is_ignored() -> void:
	# A wall hides the vacuum from the cat and the cat from the sleeping dog.
	var arena := _arena(Vector2(300, 200), Vector2(250, 250))
	var cat := arena.get_node("Cat") as Cat
	_add_wall(arena, Vector2(400, 310), Vector2(1000, 20))
	_add_vacuum(arena, Vector2(250, 380), PackedVector2Array([Vector2(250, 380)]))
	var dog := _add_dog(arena, Vector2(320, 380), cat)
	var calm := true
	for i in FPS:
		await physics_frame
		calm = calm and cat.state != Cat.State.FLEE and dog.state == Dog.State.SLEEP
	_check(calm and not cat.is_over(), "threat_behind_wall_is_ignored",
		"calm=%s cat=%s dog=%s" % [calm, Cat.State.keys()[cat.state], Dog.State.keys()[dog.state]])
	await _dispose(arena)


func _test_cat_slides_along_wall_when_fleeing() -> void:
	# The vacuum drives almost straight at the cat, which has a wall right behind
	# it; coming from a little above, it pushes the cat down along the wall.
	var arena := _arena(Vector2(2000, 300), Vector2(150, 300))
	var cat := arena.get_node("Cat") as Cat
	_add_wall(arena, Vector2(110, 700), Vector2(20, 700))
	_add_vacuum(arena, Vector2(320, 290), PackedVector2Array([Vector2(175, 290)]))
	await _frames(4 * FPS)
	_check(not cat.is_over() and cat.position.y > 400.0, "cat_slides_along_wall_when_fleeing",
		"cat=%s position=%s" % [Cat.State.keys()[cat.state], cat.position])
	await _dispose(arena)


func _test_cornered_cat_gives_up_fleeing() -> void:
	# A dead-end alcove 44 px wide; the vacuum parked at its mouth scares the cat deeper in.
	var arena := _arena(Vector2(2000, 2000), Vector2(322, 240))
	var cat := arena.get_node("Cat") as Cat
	_add_wall(arena, Vector2(322, 200), Vector2(124, 20))
	_add_wall(arena, Vector2(290, 340), Vector2(20, 140))
	_add_wall(arena, Vector2(354, 340), Vector2(20, 140))
	_add_vacuum(arena, Vector2(322, 360), PackedVector2Array([Vector2(322, 360)]))
	await _frames(FPS)
	var cornered := cat.state == Cat.State.FLEE
	var gave_up := false
	for i in int((cat.tuning.flee_give_up_time + 1.0) * FPS):
		await physics_frame
		gave_up = gave_up or (cat.state != Cat.State.FLEE and not cat.is_over())
	# The vacuum is only ignored briefly: the cat soon reacts to it again.
	var fled_again := false
	for i in int((cat.tuning.flee_ignore_time + 0.5) * FPS):
		await physics_frame
		fled_again = fled_again or (gave_up and cat.state == Cat.State.FLEE)
	_check(cornered and gave_up and fled_again, "cornered_cat_gives_up_fleeing",
		"cornered=%s gave_up=%s fled_again=%s cat=%s position=%s" % [cornered, gave_up, fled_again,
		Cat.State.keys()[cat.state], cat.position])
	await _dispose(arena)


func _test_threat_touch_fails_level() -> void:
	var expected_sounds: Dictionary[String, String] = {"vacuum": "res://audio/sfx/hiss.wav", "dog": "res://audio/sfx/bark.wav"}
	for kind: String in expected_sounds:
		var arena := _arena(Vector2(2000, 300), Vector2(300, 300))
		var cat := arena.get_node("Cat") as Cat
		var reasons: Array[String] = []
		var sounds: Array[String] = []
		cat.failed.connect(func(reason: String, sound: AudioStream) -> void:
			reasons.append(reason)
			sounds.append(sound.resource_path if sound != null else "<none>"))
		var hazard: Hazard
		if kind == "vacuum":
			hazard = _add_vacuum(arena, Vector2(300, 300), PackedVector2Array([Vector2(300, 300)]))
		else:
			hazard = _add_dog(arena, Vector2(300, 300), cat).get_node("Bite") as Hazard
		await _frames(5)
		_check(cat.state == Cat.State.FAILED and reasons == [hazard.reason] and sounds == [expected_sounds[kind]],
			"%s_touch_fails_level" % kind, "state=%s reasons=%s sounds=%s" % [Cat.State.keys()[cat.state], reasons, sounds])
		await _dispose(arena)


func _test_dog_sleeps_wakes_chases_and_sleeps_again() -> void:
	# The cat starts between the dog's wake radius (170) and fear radius (210).
	var arena := _arena(Vector2(400, 2000), Vector2(410, 300))
	var cat := arena.get_node("Cat") as Cat
	var dog := _add_dog(arena, Vector2(600, 300), cat)
	var bite := dog.get_node("Bite") as Hazard
	var calm := true
	for i in 2 * FPS:
		await physics_frame
		calm = calm and dog.state == Dog.State.SLEEP and not bite.scary and cat.state != Cat.State.FLEE
	cat.position = Vector2(480, 300)
	await _frames(3)
	var woke := dog.state == Dog.State.CHASE and bite.scary and cat.state == Cat.State.FLEE
	await _frames(FPS)
	var chased := dog.position.distance_to(Vector2(600, 300)) > dog.chase_speed * 0.5
	await _frames(int((dog.chase_time + dog.return_time - 0.5) * FPS))
	var asleep_again := dog.state == Dog.State.SLEEP and not bite.scary \
		and dog.position.distance_to(Vector2(600, 300)) <= Dog.HOME_DISTANCE + 1.0
	_check(calm and woke and chased and asleep_again and not cat.is_over(), "dog_sleeps_wakes_chases_and_sleeps_again",
		"calm=%s woke=%s chased=%s asleep_again=%s dog=%s cat=%s" % [calm, woke, chased, asleep_again,
		Dog.State.keys()[dog.state], Cat.State.keys()[cat.state]])
	await _dispose(arena)


func _test_dog_cut_off_from_home_still_sleeps() -> void:
	# Woken, the dog is moved behind a long wall it cannot get round on its way home.
	var arena := _arena(Vector2(400, 2000), Vector2(500, 300))
	var cat := arena.get_node("Cat") as Cat
	var dog := _add_dog(arena, Vector2(600, 300), cat)
	_add_wall(arena, Vector2(600, 260), Vector2(1400, 20))
	await _frames(3)
	var woke := dog.state == Dog.State.CHASE
	dog.position = Vector2(600, 150)
	cat.position = Vector2(100, 60)
	await _frames(int((dog.chase_time + dog.return_time + 0.5) * FPS))
	var away := dog.position.distance_to(Vector2(600, 300))
	_check(woke and dog.state == Dog.State.SLEEP and away > 50.0, "dog_cut_off_from_home_still_sleeps",
		"woke=%s dog=%s distance_from_home=%.1f" % [woke, Dog.State.keys()[dog.state], away])
	await _dispose(arena)


func _test_dog_ignores_cat_once_level_is_over() -> void:
	# A chasing dog gives up when the cat fails, and a failed cat does not wake a dog.
	var arena := _arena(Vector2(400, 2000), Vector2(480, 300))
	var cat := arena.get_node("Cat") as Cat
	var chaser := _add_dog(arena, Vector2(600, 300), cat)
	await _frames(3)
	var woke := chaser.state == Dog.State.CHASE
	cat.time_up("test time up", null)
	await _frames(3)
	var stopped := chaser.state != Dog.State.CHASE
	var sleeper := _add_dog(arena, Vector2(480, 420), cat)
	var slept := true
	for i in FPS:
		await physics_frame
		slept = slept and sleeper.state == Dog.State.SLEEP
	_check(woke and stopped and slept, "dog_ignores_cat_once_level_is_over",
		"woke=%s stopped=%s slept=%s" % [woke, stopped, slept])
	await _dispose(arena)


func _test_robot_unharmed_by_dog() -> void:
	# The robot hovers right over the dog; the bite detects touches asleep or awake, but only the cat's.
	var arena := _arena(Vector2(600, 300), Vector2(2000, 2000))
	var cat := arena.get_node("Cat") as Cat
	var bot := arena.get_node("Robot") as Robot
	var bite := _add_dog(arena, Vector2(600, 300), cat).get_node("Bite") as Hazard
	var detected := false
	for i in FPS:
		await physics_frame
		detected = detected or bite.overlaps_body(bot)
	_check(not detected and not cat.is_over(), "robot_unharmed_by_dog",
		"detected=%s cat=%s" % [detected, Cat.State.keys()[cat.state]])
	await _dispose(arena)


func _test_nap_waits_for_first_movement_then_fails() -> void:
	var arena := _arena(Vector2(900, 300), Vector2(100, 300))
	var cat := arena.get_node("Cat") as Cat
	var failures: Array[String] = []
	var sounds: Array[AudioStream] = []
	cat.failed.connect(func(reason: String, sound: AudioStream) -> void:
		failures.append(reason)
		sounds.append(sound))
	await _frames(int((cat.tuning.nap_fill_time + 1.0) * FPS))
	var waited := cat.state == Cat.State.IDLE and cat.nap == 0.0
	Input.action_press("move_right")
	await _frames(1)
	Input.action_release("move_right")
	await _frames(int(cat.tuning.nap_fill_time * FPS) - 30)
	var not_yet := cat.state == Cat.State.IDLE and cat.nap > 0.8
	await _frames(60)
	var bubble := cat.get_node("ThoughtBubble") as ThoughtBubble
	var napped := cat.state == Cat.State.NAP and failures == [Cat.NAP_TEXT] and sounds == [cat.nap_sound] \
		and cat.nap_sound != null and bubble.shown_icon() == bubble.nap_icon
	_check(waited and not_yet and napped, "nap_waits_for_first_movement_then_fails",
		"waited=%s not_yet=%s napped=%s state=%s nap=%.2f failures=%s" % [waited, not_yet, napped,
		Cat.State.keys()[cat.state], cat.nap, failures])
	await _dispose(arena)


func _test_nap_drains_while_busy() -> void:
	# The player has moved and the robot is out of reach, but the yarn keeps the cat busy.
	var arena := _arena(Vector2(1000, 300), Vector2(250, 300))
	var cat := arena.get_node("Cat") as Cat
	var bot := arena.get_node("Robot") as Robot
	bot.has_moved = true
	_add(arena, YARN_SCENE, Vector2(250, 360))
	cat.nap = 0.9
	await _frames(30)
	_check(cat.state == Cat.State.DISTRACTED and cat.nap < 0.9 - 0.4 / cat.tuning.nap_drain_time, "nap_drains_while_busy",
		"state=%s nap=%.2f" % [Cat.State.keys()[cat.state], cat.nap])
	await _dispose(arena)


## Every level's hint fits the HUD's hint box between the level and timer pills.
func _test_level_hints_fit_hud() -> void:
	var hud := HUD_SCENE.instantiate() as Hud
	root.add_child(hud)
	await process_frame
	var label := hud.get_node("Hint") as Label
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var outline := label.get_theme_constant("outline_size")
	var too_wide: Array[String] = []
	for path in _game.LEVEL_PATHS:
		var level := (load(path) as PackedScene).instantiate() as Level
		var width := font.get_string_size(level.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + outline
		if width > label.size.x:
			too_wide.append("%s (%.0f px)" % [path.get_file(), width])
		level.free()
	_check(too_wide.is_empty(), "level_hints_fit_hud", "hint box %.0f px; too wide: %s" % [label.size.x, too_wide])
	hud.queue_free()
	await process_frame


func _test_stars_for_time_left() -> void:
	var stars: Array[int] = [Level.stars_for(12.0, 60.0), Level.stars_for(11.0, 60.0), Level.stars_for(6.0, 60.0),
		Level.stars_for(5.0, 60.0), Level.stars_for(0.0, 60.0)]
	_check(stars == [3, 2, 2, 1, 1], "stars_for_time_left", "got %s, expected [3, 2, 2, 1, 1]" % [stars])


## The desktop window is scaled by the screen density, shrunk to fit with its
## frame, and its framed rect is centred inside the usable screen area.
func _test_fit_window_rect() -> void:
	var base := Vector2i(1408, 792)
	# 2x Retina with room to spare (macOS: 64 px title bar, menu bar above y 78).
	var roomy := GameState.fit_window_rect(base, 2.0, Rect2i(0, 78, 3600, 2070), Vector2i(0, 64), Vector2i(0, 64))
	# 1x 1366x768 laptop with a 40 px taskbar (Windows-style frame: borders and a 31 px title).
	var small_usable := Rect2i(0, 0, 1366, 728)
	var small := GameState.fit_window_rect(base, 1.0, small_usable, Vector2i(16, 39), Vector2i(8, 31))
	var small_framed := Rect2i(small.position - Vector2i(8, 31), small.size + Vector2i(16, 39))
	# 2x 13-inch screen too short for the window: the framed top sits at the usable top.
	var tight := GameState.fit_window_rect(base, 2.0, Rect2i(0, 74, 2880, 1626), Vector2i(0, 64), Vector2i(0, 64))
	# 1x full-HD screen: unchanged.
	var full_hd := GameState.fit_window_rect(base, 1.0, Rect2i(0, 0, 1920, 1040), Vector2i(16, 39), Vector2i(8, 31))
	var ok := roomy == Rect2i(392, 353, 2816, 1584) \
		and small_usable.encloses(small_framed) and small_framed.size.y == small_usable.size.y \
		and absf(float(small.size.x) / small.size.y - 16.0 / 9.0) < 0.01 \
		and tight.position.y - 64 == 74 and tight.size.y + 64 <= 1626 \
		and full_hd.size == base
	_check(ok, "fit_window_rect", "roomy=%s small=%s (framed %s) tight=%s full_hd=%s" % [roomy, small, small_framed, tight, full_hd])


func _test_warning_seconds() -> void:
	# The red ticking countdown covers the last 10 s, or the last 40% of a short limit.
	var got: Array[float] = [Level.warning_seconds(60.0), Level.warning_seconds(25.0), Level.warning_seconds(12.0)]
	var ok := is_equal_approx(got[0], 10.0) and is_equal_approx(got[1], 10.0) and is_equal_approx(got[2], 4.8)
	_check(ok, "warning_seconds", "got %s, expected [10, 10, 4.8]" % [got])


func _test_next_index() -> void:
	var saved_paths := _game.level_paths
	_game.level_paths = ["a", "b", "c"]
	var got: Array[int] = [_game.next_index(0, true), _game.next_index(2, true), _game.next_index(1, false)]
	_game.level_paths = saved_paths
	_check(got == [1, 0, 1], "next_index", "got %s, expected [1, 0, 1]" % [got])


func _test_save_round_trip() -> void:
	var saved_paths := _game.level_paths
	_game.level_paths = ["a", "b", "c"]
	_game.load_progress()
	_game.furthest_index = 2
	_game.best_stars = [3, 1, 0]
	_game.save_progress()
	_game.load_progress()
	var ok := _game.furthest_index == 2 and _game.best_stars == [3, 1, 0] and _game.reported_errors.is_empty()
	_check(ok, "save_round_trip", "furthest=%d stars=%s errors=%s" % [_game.furthest_index, _game.best_stars, _game.reported_errors])
	_game.level_paths = saved_paths
	_delete_test_save()
	_game.load_progress()


func _test_missing_save_starts_fresh() -> void:
	_delete_test_save()
	_game.load_progress()
	var ok := _game.furthest_index == 0 and _game.best_stars.count(0) == _game.level_count() and _game.reported_errors.is_empty()
	_check(ok, "missing_save_starts_fresh", "furthest=%d stars=%s errors=%s" % [_game.furthest_index, _game.best_stars, _game.reported_errors])


func _test_corrupt_save_is_replaced() -> void:
	var cases: Array[String] = ["{{{ not json", "[1, 2]", '{"furthest_level": "x", "best_stars": []}', '{"furthest_level": 0, "best_stars": [1.5]}']
	for contents in cases:
		var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
		if file == null:
			_check(false, "corrupt_save_is_replaced", "cannot write " + TEST_SAVE_PATH)
			return
		file.store_string(contents)
		file.close()
		_game.quiet_errors = true
		_game.reported_errors.clear()
		_game.load_progress()
		_game.quiet_errors = false
		var reported := _game.reported_errors.size() == 1 and "corrupt" in _game.reported_errors[0]
		_game.reported_errors.clear()
		_game.load_progress()
		var replaced := _game.reported_errors.is_empty() and _game.furthest_index == 0
		_check(reported and replaced, "corrupt_save_is_replaced", "contents=%s reported=%s replaced=%s" % [contents, reported, replaced])
		_game.reported_errors.clear()
	_delete_test_save()


func _test_clock_starts_on_first_movement() -> void:
	_game.retrying = false
	var level := await _load_level(-1.0)
	var hud := level.get_node("%Hud") as Hud
	await _frames(int(0.5 * FPS))
	var idle_ok := not level.clock_running and is_equal_approx(level.time_left, level.time_limit) and hud.intro_shown()
	Input.action_press("move_up")
	await _frames(1)
	Input.action_release("move_up")
	var intro_gone := not hud.intro_shown()
	await _frames(FPS)
	var elapsed := level.time_limit - level.time_left
	_check(idle_ok and intro_gone and level.clock_running and elapsed > 0.9 and elapsed < 1.1, "clock_starts_on_first_movement",
		"idle_ok=%s intro_gone=%s running=%s elapsed=%.2f" % [idle_ok, intro_gone, level.clock_running, elapsed])
	await _unload_level()


func _test_time_up_fails_level() -> void:
	var level := await _load_level(2.0)
	var cat := level.get_node("%Cat") as Cat
	var hud := level.get_node("%Hud") as Hud
	Input.action_press("move_up")
	await _frames(1)
	Input.action_release("move_up")
	# A 2 s limit warns only for its last 0.8 s (40%), so the clock starts out normal.
	await _frames(int(0.5 * FPS))
	var calm_at_start := hud.timer_color() != Hud.WARNING_COLOR
	await _frames(int(1.5 * FPS) + 5)
	var frozen_at := level.time_left
	await _frames(20)
	var sfx_fail := level.get_node("%SfxFail") as AudioStreamPlayer
	var ok := calm_at_start and cat.state == Cat.State.FAILED and hud.banner_text() == Level.TIME_UP_TEXT \
		and hud.timer_color() == Hud.WARNING_COLOR and not level.clock_running and level.time_left == frozen_at \
		and hud.time_up_sound != null and sfx_fail.stream == hud.time_up_sound
	_check(ok, "time_up_fails_level", "cat=%s banner='%s' red=%s running=%s sound=%s" % [Cat.State.keys()[cat.state],
		hud.banner_text(), hud.timer_color() == Hud.WARNING_COLOR, level.clock_running, sfx_fail.stream])
	await _frames(int(_game.FAIL_RETRY_DELAY * FPS))
	await _unload_level()


func _test_fail_retries_same_level() -> void:
	var trigger := func(level: Level) -> void:
		(level.get_node("%Cat") as Cat).fall_into("test hazard", null)
	await _check_transition("fail_retries_same_level", trigger, _game.FAIL_RETRY_DELAY, "test hazard", _game.LEVEL_PATHS[0])
	# The transition check proves the retry happens at FAIL_RETRY_DELAY (+ margin);
	# the plan requires it within 2 seconds of failing.
	var latest_retry := _game.FAIL_RETRY_DELAY + RESTART_MARGIN_FRAMES / float(FPS)
	_check(latest_retry <= 2.0, "fail_retries_within_two_seconds", "retry happens by %.2f s" % latest_retry)


func _test_intro_card_not_on_retry() -> void:
	_game.retrying = false
	var level := await _load_level(-1.0)
	var first_shown := (level.get_node("%Hud") as Hud).intro_shown()
	(level.get_node("%Cat") as Cat).fall_into("test hazard", null)
	await _frames(int(_game.FAIL_RETRY_DELAY * FPS) + RESTART_MARGIN_FRAMES)
	var retry := current_scene as Level
	var retry_shown := retry != null and retry != level and (retry.get_node("%Hud") as Hud).intro_shown()
	_check(first_shown and retry != level and not retry_shown and _game.retrying, "intro_card_not_on_retry",
		"first_shown=%s retried=%s retry_shown=%s retrying=%s" % [first_shown, retry != level, retry_shown, _game.retrying])
	await _unload_level()
	_game.retrying = false

func _test_clear_advances_to_next_level() -> void:
	var trigger := func(level: Level) -> void:
		var cat := level.get_node("%Cat") as Cat
		cat.global_position = (level.get_node("Bed") as Node2D).global_position + Vector2(-40, 0)
	await _check_transition("clear_advances_to_next_level", trigger, _game.CLEAR_ADVANCE_DELAY, Level.CLEAR_TEXT,
		_game.LEVEL_PATHS[1])
	_check(_game.best_stars[0] >= 1 and _game.furthest_index == 1 and FileAccess.file_exists(TEST_SAVE_PATH),
		"clear_records_and_saves_progress", "best_stars=%s furthest=%d save_exists=%s" % [_game.best_stars,
		_game.furthest_index, FileAccess.file_exists(TEST_SAVE_PATH)])
	_delete_test_save()
	_game.load_progress()


## The end room (current scene, just loaded after the last clear) shows the end
## text and star total with the title music, then level 1 loads with the level music.
func _check_end_room() -> void:
	var room := current_scene as EndRoom
	var stars := _game.star_total()
	var shows := room != null and (room.get_node("%Headline") as Label).text == GameState.END_TEXT \
		and (room.get_node("%StarTotal") as Label).text == "%d of %d stars" % [stars.x, stars.y]
	var title_music := _game.music_playing() == _game.title_music and _game.title_music != null
	await _frames(int(_game.END_ROOM_TIME * FPS))
	var back := current_scene != null and current_scene.scene_file_path == _game.LEVEL_PATHS[0]
	var level_music := _game.music_playing() == _game.level_music and _game.level_music != null
	_check(shows and title_music and back and level_music, "end_room_then_level_1",
		"shows=%s title_music=%s back_at_level_1=%s level_music=%s" % [shows, title_music, back, level_music])


## The main scene is the title room: it shows the restriction sentence, plays the
## title music and waits; the first movement loads the furthest unlocked level,
## which fades in with the level music (criteria 3 and 16).
## The game opens on the splash screen (the main scene): the Silly Kitty logo
## with the cat head, which loads the title room after SPLASH_TIME, untouched.
func _test_splash_opens_the_game() -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var splash := (load(path) as PackedScene).instantiate() as Splash
	if splash == null:
		_check(false, "splash_opens_the_game", "main scene '%s' is not a Splash" % path)
		return
	root.add_child(splash)
	current_scene = splash
	var logo := (splash.get_node("%Title") as Label).text == "Silly Kitty" \
		and (splash.get_node("%Head") as Sprite2D).texture != null
	await _frames(int((Splash.SPLASH_TIME - 0.1) * FPS))
	var still_showing := is_instance_valid(splash) and current_scene == splash
	await _frames(int(0.1 * FPS) + RESTART_MARGIN_FRAMES)
	var titled := current_scene != null and current_scene.scene_file_path == GameState.TITLE_ROOM_PATH \
		and _game.music_playing() == _game.title_music
	_check(logo and still_showing and titled, "splash_opens_the_game", "logo=%s still showing before %.1f s=%s then title room=%s (scene %s)"
		% [logo, Splash.SPLASH_TIME, still_showing, titled, current_scene.scene_file_path if current_scene else "none"])
	await _unload_level()


func _test_title_room_starts_on_movement() -> void:
	var title := (load(GameState.TITLE_ROOM_PATH) as PackedScene).instantiate() as TitleRoom
	root.add_child(title)
	current_scene = title
	var tagline := (title.get_node("%Tagline") as Label).text
	var goal := (title.get_node("%Goal") as Label).text
	await _frames(FPS)
	var waiting := is_instance_valid(title) and current_scene == title and tagline == TitleRoom.RESTRICTION_TEXT \
		and goal == TitleRoom.GOAL_TEXT \
		and _game.music_playing() == _game.title_music
	Input.action_press("move_right")
	await _frames(1)
	Input.action_release("move_right")
	await _frames(int(TitleRoom.START_DELAY * FPS) + RESTART_MARGIN_FRAMES)
	var started := current_scene != null and (not is_instance_valid(title) or current_scene != title) \
		and current_scene.scene_file_path == _game.LEVEL_PATHS[_game.furthest_index]
	var level_music := _game.music_playing() == _game.level_music
	await _frames(int(_game.FADE_TIME * FPS) + 2)
	var faded_in := is_zero_approx(_game.curtain_alpha())
	# The scaled room view survives scene changes and still rests on the screen bottom.
	var view := root.canvas_transform
	var scaled := is_equal_approx(view.get_scale().x, GameState.ROOM_SCALE) \
		and view.origin.is_equal_approx(Vector2(640.0, 720.0) * (1.0 - GameState.ROOM_SCALE))
	_check(waiting and started and level_music and faded_in and scaled, "title_room_starts_on_movement",
		"waiting=%s (tagline '%s') started=%s level_music=%s faded_in=%s scaled=%s" % [waiting, tagline, started,
		level_music, faded_in, scaled])
	await _unload_level()


## Flies every level's scripted route (criteria 4, 24 and 25): each level has
## the mechanics planned for it, the route clears it with 3 stars, the clear
## banner shows and the next level loads (the last level loads the end room,
## then level 1). Time limit / route clear time must be >= 1.25 on every
## level, >= 1.8 on levels 1-2, <= 1.5 on levels 7-8 and never rise from one
## level to the next.
func _test_level_routes() -> void:
	var count := _game.LEVEL_PATHS.size()
	# Per level; stays -1 for a level its route did not clear.
	var ratios: Array[float] = []
	ratios.resize(count)
	ratios.fill(-1.0)
	for i in count:
		var level := await _load_level(-1.0, i)
		var bot := level.get_node("%Robot") as Robot
		var cat := level.get_node("%Cat") as Cat
		var hud := level.get_node("%Hud") as Hud
		var name := "level_%02d" % (i + 1)
		var missing := _missing_mechanics(level, i)
		_check(missing.is_empty(), name + "_mechanics", "missing or introduced too early: %s" % [missing])
		var outcomes: Array[int] = []
		level.finished.connect(func(cleared: bool, earned: int) -> void: outcomes.append(earned if cleared else -1))
		await _fly_route(LEVEL_ROUTES[i], bot, cat)
		var settle := 0
		while outcomes.is_empty() and settle < int(ROUTE_SETTLE * FPS):
			await physics_frame
			settle += 1
		var limit := level.time_limit
		var used := limit - level.time_left
		var cat_at := cat.global_position
		var stars: int = outcomes[0] if outcomes.size() == 1 else -1
		var last := i == count - 1
		await _frames(int(_game.CLEAR_ADVANCE_DELAY * FPS) - RESTART_MARGIN_FRAMES)
		var banner := hud.banner_text() if current_scene == level else "<scene already changed>"
		await _frames(2 * RESTART_MARGIN_FRAMES)
		var expected_path := _game.END_ROOM_PATH if last else _game.LEVEL_PATHS[i + 1]
		var loaded := current_scene != null and current_scene != level and current_scene.scene_file_path == expected_path
		_check(stars == 3 and banner == Level.CLEAR_TEXT and loaded, name + "_route",
			"stars=%d (-1 = not cleared) used=%.2f s of %.1f banner='%s' next_loaded=%s cat_at=%s" % [stars, used, limit,
			banner, loaded, cat_at])
		if last:
			_check(_game.furthest_index == 0 and _game.star_total().x == 3 * count, "full_clear_resumes_at_level_1",
				"furthest=%d stars=%s" % [_game.furthest_index, _game.star_total()])
			await _check_end_room()
		await _unload_level()
		if stars > 0:
			# The rules use the faster of the route as written and the same route
			# flown without ever turning back, so a slow route cannot hide a slack limit.
			ratios[i] = limit / minf(used, await _rushed_clear_time(i))
	var rules_ok := true
	for i in count:
		rules_ok = rules_ok and ratios[i] >= 1.25 and (i > 1 or ratios[i] >= 1.8) and (i < count - 2 or ratios[i] <= 1.5) \
			and (i == 0 or ratios[i] <= ratios[i - 1])
	var shown := ", ".join(range(count).map(func(i: int) -> String: return "L%d %.2f" % [i + 1, ratios[i]]))
	print("test_gameplay: time limit / fastest route clear time per level: " + shown)
	_check(rules_ok, "level_time_limits", "limit / route time per level: " + shown)
	_delete_test_save()
	_game.load_progress()


## Seconds level `index` takes when its route is flown without ever turning back
## for the cat (INF if that fails). Waits for Game's retry or advance, then unloads.
func _rushed_clear_time(index: int) -> float:
	var rushed: Array = LEVEL_ROUTES[index].map(func(step: Variant) -> Variant:
		return step if step is float else Vector3(step.x, step.y, INF))
	var level := await _load_level(-1.0, index)
	var cat := level.get_node("%Cat") as Cat
	var outcomes: Array[bool] = []
	level.finished.connect(func(cleared: bool, _stars: int) -> void: outcomes.append(cleared))
	await _fly_route(rushed, level.get_node("%Robot") as Robot, cat)
	var settle := 0
	while outcomes.is_empty() and settle < int(ROUTE_SETTLE * FPS):
		await physics_frame
		settle += 1
	var used := level.time_limit - level.time_left if outcomes == [true] else INF
	var delay := _game.FAIL_RETRY_DELAY if outcomes != [true] else _game.CLEAR_ADVANCE_DELAY + _game.END_ROOM_TIME
	await _frames(int(delay * FPS) + RESTART_MARGIN_FRAMES)
	await _unload_level()
	return used


## Flying straight at the bed must not clear any level: each level's walls,
## puddles, yarn and threats have to be worked around.
func _test_level_beelines_fail() -> void:
	for i in _game.LEVEL_PATHS.size():
		var level := await _load_level(-1.0, i)
		var cat := level.get_node("%Cat") as Cat
		var outcomes: Array[bool] = []
		level.finished.connect(func(cleared: bool, _stars: int) -> void: outcomes.append(cleared))
		await _fly_route([(level.get_node("Bed") as Node2D).global_position], level.get_node("%Robot") as Robot, cat)
		var settle := 0
		while outcomes.is_empty() and settle < int(ROUTE_SETTLE * FPS):
			await physics_frame
			settle += 1
		var state := Cat.State.keys()[cat.state] as String
		_check(outcomes == [false], "level_%02d_beeline_fails" % (i + 1), "outcomes=%s (true = cleared) cat=%s" % [outcomes, state])
		# Let Game's pending retry or advance happen before the level is unloaded.
		var won := outcomes == [true]
		var delay := _game.FAIL_RETRY_DELAY if not won else _game.CLEAR_ADVANCE_DELAY + _game.END_ROOM_TIME
		await _frames(int(delay * FPS) + RESTART_MARGIN_FRAMES)
		await _unload_level()


## Level 5's long walls punish leaving the cat behind with a nap.
func _test_level_05_racing_ahead_naps() -> void:
	var level := await _load_level(-1.0, 4)
	var cat := level.get_node("%Cat") as Cat
	var reasons: Array[String] = []
	cat.failed.connect(func(reason: String, _sound: AudioStream) -> void: reasons.append(reason))
	await _fly_route(LEVEL_05_RACE, level.get_node("%Robot") as Robot, cat)
	var settle := 0
	while reasons.is_empty() and settle < int(ROUTE_SETTLE * FPS):
		await physics_frame
		settle += 1
	_check(reasons == [Cat.NAP_TEXT], "level_05_racing_ahead_naps", "fail reasons=%s cat=%s" % [reasons,
		Cat.State.keys()[cat.state]])
	await _frames(int(_game.FAIL_RETRY_DELAY * FPS) + RESTART_MARGIN_FRAMES)
	await _unload_level()


## Mechanics the level lacks from LEVEL_MECHANICS, plus any it has before INTRODUCED_AT.
func _missing_mechanics(level: Level, index: int) -> Array[String]:
	var found: Array[String] = []
	for node in level.find_children("*", "Node", true, false):
		var kind := ""
		if node is Vacuum:
			kind = "vacuum"
		elif node is Dog:
			kind = "dog"
		elif node is Distraction:
			kind = "yarn"
		elif node is Hazard and not (node.get_parent() is Dog):
			kind = "puddle"
		if kind != "" and not found.has(kind):
			found.append(kind)
	var problems: Array[String] = []
	for kind: String in LEVEL_MECHANICS[index]:
		if not found.has(kind):
			problems.append(kind)
	for kind in found:
		if index + 1 < INTRODUCED_AT[kind]:
			problems.append("early " + kind)
	return problems


## Flies the robot along a LEVEL_ROUTES route until it ends or the level is over
## for the cat. Like a player, it turns back for the cat when it falls behind
## or has lost track of the robot (unless the step's pace is INF).
func _fly_route(route: Array, bot: Robot, cat: Cat) -> void:
	for step: Variant in route:
		var frames := 0
		if step is float:
			_steer(Vector2.ZERO)
			while frames < int(step * FPS) and not cat.is_over():
				await physics_frame
				frames += 1
			continue
		var target := Vector2(step.x, step.y) if step is Vector3 else step as Vector2
		var pace: float = step.z if step is Vector3 else ROUTE_PACE
		while not cat.is_over() and frames < int(ROUTE_STEP_TIMEOUT * FPS):
			var offset := target - bot.global_position
			if offset.length() < ROUTE_REACH:
				break
			var behind := cat.global_position - bot.global_position
			var turn_back := pace < INF and (behind.length() > pace or cat.state == Cat.State.IDLE)
			_steer(behind.normalized() if turn_back else offset.normalized())
			await physics_frame
			frames += 1
	_steer(Vector2.ZERO)


## Presses the move_* actions like a keyboard: `direction` snapped to the nearest
## of 8 directions, each action fully on or off (zero releases them all).
func _steer(direction: Vector2) -> void:
	var keys := Vector2.ZERO if direction == Vector2.ZERO else Vector2.from_angle(snappedf(direction.angle(), PI / 4.0)).round()
	_press("move_right", keys.x > 0.0)
	_press("move_left", keys.x < 0.0)
	_press("move_down", keys.y > 0.0)
	_press("move_up", keys.y < 0.0)


func _press(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


## Loads the first level, triggers an outcome and asserts: the expected banner is
## showing just before `delay`, the level is still there then, and `expected_path`
## is loaded just after `delay`.
func _check_transition(test_name: String, trigger: Callable, delay: float, banner: String, expected_path: String) -> void:
	var level := await _load_level(-1.0)
	var hud := level.get_node("%Hud") as Hud
	var outcomes: Array[bool] = []
	level.finished.connect(func(cleared: bool, _stars: int) -> void: outcomes.append(cleared))
	trigger.call(level)
	var waited := 0
	while outcomes.is_empty() and waited < 5 * FPS:
		await physics_frame
		waited += 1
	await _frames(int(delay * FPS) - RESTART_MARGIN_FRAMES)
	var banner_before := hud.banner_text() if current_scene == level else "<scene already changed>"
	await _frames(2 * RESTART_MARGIN_FRAMES)
	var loaded := current_scene != null and current_scene != level and current_scene.scene_file_path == expected_path
	_check(outcomes.size() == 1 and banner_before == banner and loaded, test_name,
		"outcomes=%s banner_before='%s' loaded=%s" % [outcomes, banner_before, loaded])
	await _unload_level()


## Instantiates a listed level (the first by default) as the current scene. A
## `time_limit` >= 0 overrides the level's own limit.
func _load_level(time_limit: float, index: int = 0) -> Level:
	var level := (load(_game.LEVEL_PATHS[index]) as PackedScene).instantiate() as Level
	if time_limit >= 0.0:
		level.time_limit = time_limit
	root.add_child(level)
	current_scene = level
	await _frames(2)
	return level


func _unload_level() -> void:
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await _frames(2)


func _delete_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
		if error != OK:
			_failures.append("cannot delete %s: %s" % [TEST_SAVE_PATH, error_string(error)])


func _add_wall(arena: Node2D, bottom_centre: Vector2, size: Vector2) -> void:
	var wall := Wall.new()
	wall.size = size
	wall.position = bottom_centre
	arena.add_child(wall)


func _add_vacuum(arena: Node2D, at: Vector2, waypoints: PackedVector2Array) -> Vacuum:
	var vacuum := VACUUM_SCENE.instantiate() as Vacuum
	vacuum.position = at
	vacuum.waypoints = waypoints
	arena.add_child(vacuum)
	return vacuum


func _add_dog(arena: Node2D, at: Vector2, cat: Cat) -> Dog:
	var dog := DOG_SCENE.instantiate() as Dog
	dog.position = at
	dog.cat = cat
	arena.add_child(dog)
	return dog


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
