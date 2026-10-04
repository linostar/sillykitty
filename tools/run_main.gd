extends SceneTree
## Headless run of the game's main scene for validate.sh: loads it the way the
## engine would, runs RUN_FRAMES frames (env, default 300), then quits cleanly.
## Prints "run_main: OK" on success.
## Quitting while a sound plays races the audio thread and reports leaked
## playbacks, so the scene (with any meow, hum or spray still playing) is freed
## and the Game autoload's music stopped, and they get real time to be released
## first (see the CLAUDE.md gotcha).

const AUDIO_RELEASE_MSEC := 500


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var error := change_scene_to_file(path)
	if error != OK:
		printerr("run_main: FAILED to load main scene '%s': %s" % [path, error_string(error)])
		quit(1)
		return
	var frames := int(OS.get_environment("RUN_FRAMES")) if OS.get_environment("RUN_FRAMES") != "" else 300
	for i in frames:
		await process_frame
	var music := root.get_node_or_null("Game/Music") as AudioStreamPlayer
	if music == null:
		printerr("run_main: FAILED: Game autoload has no Music player")
		quit(1)
		return
	current_scene.queue_free()
	music.stop()
	music.stream = null
	var release_deadline := Time.get_ticks_msec() + AUDIO_RELEASE_MSEC
	while Time.get_ticks_msec() < release_deadline:
		await process_frame
	print("run_main: OK (%s, %d frames)" % [path, frames])
	quit(0)
